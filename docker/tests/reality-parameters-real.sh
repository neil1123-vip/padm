#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 3 ]] || {
    printf 'usage: reality-parameters-real.sh <local-xray> <local-sing-box> <local-ops>\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# 真实重生成与新旧凭据连接复用已有隔离 Reality 夹具，不代替完整 CLI 事务验收。
bash "${scriptRoot}/reality-real.sh" "$@" regenerate
printf 'docker-reality-parameters-real-ok\n'
