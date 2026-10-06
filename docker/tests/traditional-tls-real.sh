#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 5 ]] || {
    printf 'usage: traditional-tls-real.sh <local-xray> <local-sing-box> <local-ops> <local-nginx> <local-http2-curl>\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# 两种独立 TLS 入口复用双栈、严格 CA/SNI、h1/h2 fallback 与额度恢复。
export PADM_TEST_HTTP2_CURL_REF=$5
for protocol in 27 29; do
    bash "${scriptRoot}/vmess-real.sh" "$1" "$2" "$3" "$4" "${protocol}" xray
done
printf 'docker-traditional-tls-real-both-ok\n'
