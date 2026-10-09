#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-http-relay-real.XXXXXX")
cleanup() {
    local status=$? file
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nhttp-relay-fixture-log: %s\n' "${file##*/}" >&2
            cat -- "${file}" >&2
        done
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux ]] || exit 1
for tool in jq python3 setpriv; do command -v "${tool}" >/dev/null; done
[[ -f /routing-cores/xray ]] || {
    printf 'http-relay-real: 缺少本机镜像传入的 Xray 程序\n' >&2
    exit 1
}
chmod 0755 /routing-cores/xray
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
jq -n '
  def entry($core; $port): {
    id:1,core:$core,listener_id:("entry-"+$core),server:"proxy.example.com",
    public_port:$port,address_families:["ipv4"],name:$core,
    uuid:"11111111-1111-4111-8111-111111111111",
    reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
      private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
      public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}};
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[entry("xray";35441),entry("sing-box";35442)]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[],routing:{
     socks5:{server:"192.0.2.1",port:1080,username:"upstream-user",password:"upstream-password"},
     hosts:{"relay.padm.invalid":"192.0.2.99"},
     dns:{server:"192.0.2.98",port:5353,domains:["full:relay.padm.invalid"]},
     block_ips:{ips:["127.0.0.0/8","::1/128"]}},
   relay:{http:{core:"xray",port:36080,address_families:["ipv4","ipv6"],
     username:"11111111-1111-4111-8111-111111111111",password:"relay:password",
     source_ips:["127.0.0.1/32","::1/128"]}}}
' >"${TEST_ROOT}/base.json"
jq '.relay.http.core="sing-box"' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/sing-box.spec.json"
if dockerConfigureSpecValidate "${TEST_ROOT}/sing-box.spec.json" >"${TEST_ROOT}/sing-box-rejected.log" 2>&1; then
    printf 'http-relay-real: sing-box HTTP relay 应在生成前拒绝\n' >&2
    exit 1
fi
for core in xray; do
    jq --arg core "${core}" '.relay.http.core=$core' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/${core}.spec.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/${core}.spec.json"
    dockerGenerateXrayConfig "${TEST_ROOT}/${core}.spec.json" "${TEST_ROOT}/${core}.base"
    dockerTrafficRender "${core}" "${TEST_ROOT}/${core}.base" \
        '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${core}.json"
done
python3 "${PROJECT_ROOT}/docker/tests/http-relay-real.py" "${TEST_ROOT}"
printf 'docker-http-relay-real-ok\n'
