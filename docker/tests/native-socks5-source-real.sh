#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-native-socks-source.XXXXXX")
cleanup() {
    local status=$? file
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nnative-socks-source-log: %s\n' "${file##*/}" >&2
            cat -- "${file}" >&2
        done
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux ]] || exit 1
for tool in jq python3 setpriv; do command -v "${tool}" >/dev/null; done
for file in shell/core/routing_socks.sh shell/regression/cases/routing.sh \
    shell/regression/suites/routing.sh docker/tests/native-socks5-source-real.sh; do
    bash -n "${PROJECT_ROOT}/${file}"
    shellcheck -S error "${PROJECT_ROOT}/${file}"
done
python3 - "${PROJECT_ROOT}/docker/tests/native-socks5-source-real.py" <<'PY'
import ast
from pathlib import Path
import sys

ast.parse(Path(sys.argv[1]).read_text())
PY
[[ -f /routing-cores/sing-box ]] || {
    printf 'native-socks-source-real: 缺少本机镜像传入的 sing-box 程序\n' >&2
    exit 1
}
chmod 0755 /routing-cores/sing-box
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/bootstrap.sh"
echoContent() { :; }
menuLine() { :; }
menuClose() { :; }
autoRead() {
    case "$1" in
    socks5_inbound_source_ips) printf -v "$3" '%s' "${sourceIPs}" ;;
    socks5_inbound_allow_all) printf -v "$3" '%s' "${allowAll}" ;;
    socks5_inbound_domains) printf -v "$3" 'full:matched.padm.invalid' ;;
    singbox_route_history) printf -v "$3" n ;;
    *) return 1 ;;
    esac
}
for mode in all domains ipv4-only; do
    singBoxConfigPath="${TEST_ROOT}/${mode}/"
    mkdir -p "${singBoxConfigPath}"
    sourceIPs='127.0.0.1/32,::1/128' allowAll=y
    [[ "${mode}" != domains ]] || allowAll=n
    [[ "${mode}" != ipv4-only ]] || sourceIPs='127.0.0.1/32'
    coreInstallType=2 configPath=
    writeSocks5InboundConfig "${singBoxConfigPath}20_socks5_inbounds.json" 31080 \
        11111111-1111-4111-8111-111111111111
    setSocks5InboundRouting
    # 真实 merge 顺序必须证明来源拒绝早于全局放行，而非只比较单个分片。
    jq -n '{log:{level:"debug",timestamp:false},
        inbounds:[{type:"socks",tag:"unrelated",listen:"::",listen_port:31081,
            users:[{username:"11111111-1111-4111-8111-111111111111",
                    password:"11111111-1111-4111-8111-111111111111"}]}]}' \
        >"${singBoxConfigPath}00_fixture.json"
    printf '{"route":{"rules":[{"ip_cidr":["127.0.0.0/8","::1/128"],"outbound":"01_direct_outbound"}]}}\n' \
        >"${singBoxConfigPath}00_allow_domain_route.json"
    /routing-cores/sing-box merge "${TEST_ROOT}/${mode}.json" -C "${singBoxConfigPath}" >/dev/null
done
# 安全 JSON writer 会安装自己的清理 trap，生成后恢复夹具的失败日志收集。
trap cleanup EXIT
python3 "${PROJECT_ROOT}/docker/tests/native-socks5-source-real.py" "${TEST_ROOT}"
printf 'native-socks-source-real-ok\n'
