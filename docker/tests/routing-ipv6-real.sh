#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-routing-ipv6-real.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv ]] || exit 1
for tool in jq python3 docker dockerd nsenter ip; do command -v "${tool}" >/dev/null; done
[[ -f /node-images.json && -f /node-images.tar && -d /n ]] || {
    printf 'routing-ipv6-real: 缺少入口传入的离线镜像或隔离数据卷\n' >&2
    exit 1
}
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
jq -n '
  def entry($core; $port): {
    id:1,core:$core,listener_id:("entry-"+$core),server:"proxy.example.com",public_port:$port,
    address_families:["ipv4"],name:$core,uuid:"11111111-1111-4111-8111-111111111111",
    reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
      private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
      public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}};
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[entry("xray";35441),entry("sing-box";35442)]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),host_integrations:[],
   routing:{
     dns:{server:"192.0.2.53",port:5353,domains:["domain:padm.invalid"]},
     hosts:{"hosts6.padm.invalid":"2001:db8::80","hosts4.padm.invalid":"203.0.113.80"},
     direct:{domains:["full:direct.padm.invalid"]},
     block:{domains:["full:blocked.padm.invalid"]},
     block_ips:{ips:["192.0.2.199"]},
     block_bt:true,
     socks5:{server:"192.0.2.1",port:1080,username:"fixture-user",password:"fixture-password",
       domains:["full:matched.padm.invalid","full:proxy.test"]}}}
' >"${TEST_ROOT}/base.json"
for mode in control selective global off; do
    jq --arg mode "${mode}" '
      if $mode == "selective" then
        .routing.ipv6 = {mode:"selective",domains:["domain:padm.invalid"]}
      elif $mode == "global" then .routing.ipv6 = {mode:"global",domains:[]}
      else . end
    ' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/${mode}.spec.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/${mode}.spec.json"
    dockerGenerateCompose "${TEST_ROOT}/${mode}.spec.json" "${TEST_ROOT}/${mode}.compose.json"
    for core in xray sing-box; do
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${TEST_ROOT}/${mode}.spec.json" "${TEST_ROOT}/${core}.${mode}.base"
        else
            dockerGenerateSingBoxConfig "${TEST_ROOT}/${mode}.spec.json" "${TEST_ROOT}/${core}.${mode}.base"
        fi
        dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.${mode}.base" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.${mode}.json"
    done
done
# IPv6 网络完全来自生产生成；夹具只补服务、隔离端口与本地解析地址。
python3 "${PROJECT_ROOT}/docker/tests/routing-ipv6-real.py" "${TEST_ROOT}"
printf 'docker-routing-ipv6-real-ok\n'
