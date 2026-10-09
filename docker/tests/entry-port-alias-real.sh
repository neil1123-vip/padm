#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-entry-port-alias-real.XXXXXX")
cleanup() {
    local status=$? file
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nentry-port-alias-fixture-log: %s\n' "${file##*/}" >&2
            cat -- "${file}" >&2
        done
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv ]] || exit 1
for tool in jq python3 docker dockerd nsenter ip unshare sysctl openssl; do
    command -v "${tool}" >/dev/null
done
[[ -f /node-images.json && -f /node-images.tar && -d /n ]] || {
    printf 'entry-port-alias-real: 缺少离线镜像或隔离数据卷\n' >&2
    exit 1
}
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

jq -n '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[
     {id:1,core:"xray",listener_id:"entry-xray",server:"alias.padm.test",
      public_port:35441,address_families:["ipv4"],name:"xray-account",
      uuid:"11111111-1111-4111-8111-111111111111",
      reality:{server_name:"target.padm.test",target_host:"target.padm.test",target_port:18443,
        private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
        public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}},
     {id:30,core:"sing-box",listener_id:"entry-sing-box",server:"alias.padm.test",
      public_port:35442,address_families:["ipv4"],name:"sing-box-account",
      uuid:"22222222-2222-4222-8222-222222222222",
      shadowsocks:{method:"2022-blake3-aes-128-gcm",
        server_password:"AAECAwQFBgcICQoLDA0ODw==",
        user_password:"//79/Pv6+fj39vX08/Lx8A=="}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:image(.)}) | from_entries),host_integrations:[]}
' >"${TEST_ROOT}/off.spec.json"
jq '.port_aliases=[{listener_id:"entry-xray",public_port:36441},
  {listener_id:"entry-sing-box",public_port:36442}]' \
    "${TEST_ROOT}/off.spec.json" >"${TEST_ROOT}/on.spec.json"
mkdir -p "${TEST_ROOT}/bundle"
printf '%040d\n' 0 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
for phase in off on; do
    spec="${TEST_ROOT}/${phase}.spec.json"
    dockerConfigureSpecValidate "${spec}"
    dockerGenerateCompose "${spec}" "${TEST_ROOT}/${phase}.compose.json"
    dockerGenerateDeployment "${spec}" "${TEST_ROOT}/${phase}.deployment.json"
    dockerDeploymentFileValidate "${TEST_ROOT}/${phase}.deployment.json"
    jq '.subscription.enabled=true' "${spec}" >"${TEST_ROOT}/${phase}.links.spec.json"
    dockerGenerateSubscription "${TEST_ROOT}/${phase}.links.spec.json" "${TEST_ROOT}/${phase}.links"
    for core in xray sing-box; do
        if [[ "${core}" == xray ]]; then
            dockerGenerateXrayConfig "${spec}" "${TEST_ROOT}/${phase}.${core}.base"
        else
            dockerGenerateSingBoxConfig "${spec}" "${TEST_ROOT}/${phase}.${core}.base"
        fi
        dockerTrafficRender "${core}" "${TEST_ROOT}/${phase}.${core}.base" \
            '{"schema_version":1,"accounts":{}}' >"${TEST_ROOT}/${phase}.${core}.json"
    done
done
# alias 只增加发布，不生成账号、核心入站或新的分享身份。
cmp "${TEST_ROOT}/on.links" "${TEST_ROOT}/off.links"
for core in xray sing-box; do
    cmp "${TEST_ROOT}/on.${core}.base" "${TEST_ROOT}/off.${core}.base"
    cmp "${TEST_ROOT}/on.${core}.json" "${TEST_ROOT}/off.${core}.json"
done
jq -e '
  [.listeners[] | select(.listener_id | startswith("alias-"))] |
  length == 3 and
  any(.[]; .listener_id=="alias-36441-tcp" and .target_listener_id=="entry-xray" and
    .service=="xray" and .container_port==35441) and
  all(.[] | select(.public_port==36442); .target_listener_id=="entry-sing-box" and
    .service=="sing-box" and .container_port==35442)
' "${TEST_ROOT}/on.deployment.json" >/dev/null
python3 "${PROJECT_ROOT}/docker/tests/entry-port-alias-real.py" "${TEST_ROOT}"
printf 'docker-entry-port-alias-real-ok\n'
