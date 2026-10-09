#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-routing-warp-real.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv ]] || exit 1
for tool in jq python3 setpriv unshare nsenter ip wg; do command -v "${tool}" >/dev/null; done
[[ -f /routing-cores/xray && -f /routing-cores/sing-box ]] || {
    printf 'routing-warp-real: 缺少入口传入的固定核心程序\n' >&2
    exit 1
}
chmod 0755 /routing-cores/xray /routing-cores/sing-box
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
   routing:{dns:{server:"192.0.2.2",port:5353,domains:["domain:warp.invalid"]},
     hosts:{"hosts.warp.invalid":"198.51.100.80","ipv6-first.warp.invalid":"2001:db8:80::80"},
     direct:{domains:["full:direct.warp.invalid"]},block:{domains:["full:blocked.warp.invalid"]},
     block_ips:{ips:["198.51.100.199"]},block_bt:true,
     socks5:{server:"192.0.2.2",port:1080,username:"fixture-user",password:"fixture-password",
       domains:["full:matched.warp.invalid","full:proxy.test"]}}}
' >"${TEST_ROOT}/base.json"
for mode in control selective4 selective6 global4 global6 off; do
    jq --arg mode "${mode}" '
      if ($mode | startswith("selective") or startswith("global")) then
        .routing.warp = {
          mode:(if $mode | startswith("global") then "global" else "selective" end),
          family:(if $mode | endswith("6") then "ipv6" else "ipv4" end),
          private_key:"AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA=",
          peer_public_key:"ISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0A=",
          ipv6_address:"2606:4700:110:8a10::2",reserved:[1,2,255],
          domains:(if $mode | startswith("global") then [] else ["domain:warp.invalid"] end)}
      else . end |
      .routing.ipv6 = {mode:"selective",domains:["full:ipv6-first.warp.invalid"]}
    ' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/${mode}.spec.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/${mode}.spec.json"
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
# 本地真实 WireGuard Peer 验证 userspace 加密链路，不注册或访问 Cloudflare。
python3 "${PROJECT_ROOT}/docker/tests/routing-warp-real.py" "${TEST_ROOT}"
printf 'docker-routing-warp-real-ok\n'
