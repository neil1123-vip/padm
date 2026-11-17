#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
mapfile -t installers < <(
    sed -nE 's/^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]+sigstore\/cosign-installer@([^[:space:]#]+).*$/\2/p' \
        "${project_root}"/.github/workflows/*.yml | sort -u
)
[[ "${#installers[@]}" -eq 1 ]] || {
    echo 'Cosign installer references must match across workflows.' >&2
    exit 1
}
printf 'Cosign installer: %s\n' "${installers[0]}"
cosign version

umask 077
directory=$(mktemp -d)
trap 'rm -rf -- "${directory}"' EXIT
printf '{"release":"cosign-ci-check"}\n' >"${directory}/manifest.json"
COSIGN_PASSWORD='' cosign generate-key-pair --output-key-prefix "${directory}/cosign"
# 本地密钥仅验证工具兼容性，不访问 OIDC 或上传透明日志。
COSIGN_PASSWORD='' cosign sign-blob --yes --key "${directory}/cosign.key" \
    --new-bundle-format=true --use-signing-config=false --tlog-upload=false \
    --bundle "${directory}/bundle.json" "${directory}/manifest.json"
jq -e '.mediaType == "application/vnd.dev.sigstore.bundle.v0.3+json"' "${directory}/bundle.json" >/dev/null
cosign verify-blob --offline --insecure-ignore-tlog --key "${directory}/cosign.pub" \
    --bundle "${directory}/bundle.json" "${directory}/manifest.json"
printf 'tampered\n' >>"${directory}/manifest.json"
if cosign verify-blob --offline --insecure-ignore-tlog --key "${directory}/cosign.pub" \
    --bundle "${directory}/bundle.json" "${directory}/manifest.json" >"${directory}/tampered.log" 2>&1; then
    echo 'Cosign accepted a tampered manifest.' >&2
    exit 1
fi
printf 'cosign-signature-check-ok\n'
