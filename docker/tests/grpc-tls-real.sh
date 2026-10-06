#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 4 ]] || {
    printf 'usage: grpc-tls-real.sh <local-xray> <local-sing-box> <local-ops> <local-nginx>\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# 两种身份分别经过相同严格 CA/h2 代理及额度恢复，客户端由实际 URI 构建。
for protocol in 24 25; do
    bash "${scriptRoot}/vmess-real.sh" "$1" "$2" "$3" "$4" "${protocol}" xray
done
printf 'docker-grpc-tls-real-both-ok\n'
