#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-port-hopping-target-real.XXXXXX")
cleanup() {
    local status=$?
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nport-hopping-target-real-log: %s\n' "${file##*/}" >&2
            cat -- "${file}" >&2
        done
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv ]] || exit 1
for tool in jq python3 docker dockerd nsenter ip unshare sysctl openssl umount timeout; do
    command -v "${tool}" >/dev/null
done
[[ -f /node-images.json && -f /node-images.tar && -d /n ]] || {
    printf 'port-hopping-target-real: 缺少离线镜像或隔离数据卷\n' >&2
    exit 1
}
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/sing-box" \
    "${PADM_DOCKER_INSTALL_DIR}/data/sing-box" \
    "${PADM_DOCKER_INSTALL_DIR}/data/subscription" \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic" \
    "${PADM_DOCKER_INSTALL_DIR}/data/net" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${TEST_ROOT}/bundle"
printf '%040d\n' 0 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
certificate="${PADM_DOCKER_INSTALL_DIR}/secrets/tls/target.padm.test.crt"
key="${PADM_DOCKER_INSTALL_DIR}/secrets/tls/target.padm.test.key"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=target.padm.test \
    -addext subjectAltName=DNS:target.padm.test -keyout "${key}" -out "${certificate}" \
    >/dev/null 2>&1
chown 10001:10001 "${certificate}" "${key}"
chmod 0644 "${certificate}"
chmod 0600 "${key}"
sing_box_image=$(jq -er '.["sing-box"].reference' /node-images.json)
net_image=$(jq -er '.net.reference' /node-images.json)
ops_image=$(jq -er '.ops.reference' /node-images.json)
jq --arg image "${sing_box_image}" --arg net "${net_image}" --arg ops "${ops_image}" '
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:3,core:"sing-box",listener_id:"entry-hy2",server:"target.padm.test",
     public_port:27443,address_families:["ipv4","ipv6"],name:"Hysteria2",
     uuid:"33333333-3333-4333-8333-333333333333",
     hy2:{domain:"target.padm.test",bandwidth_mode:"bbr",up_mbps:100,down_mbps:50,
       obfs:null,masquerade:""}}]},
   tls:{domain:"target.padm.test"},subscription:{enabled:false,token:"0123456789abcdef"},
   images:{"sing-box":$image,"xray":$image,"nginx":$image,"ops":$ops,"net":$net},
   host_integrations:[]}
' "${PROJECT_ROOT}/docker/configure.example.json" >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
dockerConfigureSpecValidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
dockerGenerateSingBoxConfig "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base"
printf '%s\n' '{"schema_version":1,"accounts":{}}' \
    >"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"
dockerTrafficRender sing-box "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" \
    "$(dockerTrafficReadState)" >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
dockerGenerateCompose "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${PADM_DOCKER_INSTALL_DIR}"
: >"${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerGenerateImagesEnv "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/images.env" "${PADM_DOCKER_INSTALL_DIR}"
dockerGenerateDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
python3 "${PROJECT_ROOT}/docker/tests/port-hopping-target-real.py" "${TEST_ROOT}"
printf 'docker-port-hopping-target-real-ok\n'
