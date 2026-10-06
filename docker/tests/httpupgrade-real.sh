#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 4 || "$#" == 5 ]] || {
    printf 'usage: httpupgrade-real.sh <local-xray> <local-sing-box> <local-ops> <local-nginx> [local-http2-curl]\n' >&2
    exit 2
}
if [[ "$#" == 5 ]]; then export PADM_TEST_HTTP2_CURL_REF=$5; fi
[[ -n "${PADM_TEST_HTTP2_CURL_REF:-}" ]] || {
    printf 'HTTPUpgrade two-core real stats requires a local HTTP2 curl image\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# 两核心依次使用同一隔离验证，保留各自的源站计数和同客户端恢复断言。
for core in xray sing-box; do
    bash "${scriptRoot}/vmess-real.sh" "$1" "$2" "$3" "$4" 23 "${core}"
done
printf 'docker-httpupgrade-real-both-ok\n'
