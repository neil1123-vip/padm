#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-routing-real.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux ]] || exit 1
for tool in jq python3 setpriv; do command -v "${tool}" >/dev/null; done
[[ -f /routing-cores/xray && -f /routing-cores/sing-box ]] || {
    printf 'routing-socks5-real: 缺少本机镜像传入的两核心程序\n' >&2
    exit 1
}
chmod 0755 /routing-cores/xray /routing-cores/sing-box
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
jq -n '
  def entry($core; $port): {
    id:1, core:$core, listener_id:("entry-"+$core), server:"proxy.example.com",
    public_port:$port, address_families:["ipv4"], name:$core,
    uuid:"11111111-1111-4111-8111-111111111111",
    reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
      private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
      public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}};
  {schema_version:3, release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[entry("xray";35441),entry("sing-box";35442)]},
   tls:null, subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[], routing:{socks5:{server:"192.0.2.1",port:1080,
     username:"fixture-user",password:"fixture-password"}}}
' >"${TEST_ROOT}/spec.json"
dockerConfigureSpecValidate "${TEST_ROOT}/spec.json"
dockerGenerateXrayConfig "${TEST_ROOT}/spec.json" "${TEST_ROOT}/xray.base"
dockerGenerateSingBoxConfig "${TEST_ROOT}/spec.json" "${TEST_ROOT}/sing-box.base"
for core in xray sing-box; do
    dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.base" \
        '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.json"
done
# 原生成器和流量渲染不改写；仅实流量夹具使用隔离回环上游与本地 SOCKS 测试入站。
python3 "${PROJECT_ROOT}/docker/tests/routing-socks5-real.py" "${TEST_ROOT}"
printf 'docker-routing-socks5-real-ok\n'
