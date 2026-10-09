#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-source-real.XXXXXX")
cleanup() {
    local status=$? file
    if [[ "${status}" -ne 0 ]]; then
        for file in "${TEST_ROOT}"/*.log; do
            [[ -f "${file}" ]] || continue
            printf '\nfail2ban-source-fixture-log: %s\n' "${file##*/}" >&2
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
    printf 'fail2ban-source-real: 缺少离线镜像或隔离数据卷\n' >&2
    exit 1
}
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

jq -n '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"xray",secondary_type:null,protocols:[
     {id:21,core:"xray",listener_id:"entry-source-ws",server:"source.padm.test",
      public_port:24444,address_families:["ipv4"],name:"source-ws",
      uuid:"11111111-1111-4111-8111-111111111111",
      websocket:{domain:"source.padm.test",path:"source-test",backend_port:31297,tls_port:8443}}]},
   tls:{domain:"source.padm.test"},site:{mode:"static"},
   subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:image(.)}) | from_entries),
   host_integrations:[{type:"fail2ban",profile:"net-fail2ban",firewall_rules:["DOCKER-USER"],
     devices:[],schedules:[],settings:{log_file:"access.log",ports:[24444],
       max_retry:3,find_time:600,ban_time:3600}}]}
' >"${TEST_ROOT}/base.json"
for family in ipv4 dual; do
    target="${TEST_ROOT}/${family}"
    mkdir -p "${target}/config/"{xray,nginx,net/fail2ban} "${target}/data/"{xray,static,net/fail2ban} \
        "${target}/logs/nginx" "${target}/secrets/tls"
    jq --arg family "${family}" '
      if $family == "dual" then .core.protocols[0].address_families += ["ipv6"] else . end
    ' "${TEST_ROOT}/base.json" >"${target}/spec.json"
    dockerConfigureSpecValidate "${target}/spec.json"
    dockerGenerateCompose "${target}/spec.json" "${target}/compose.json"
    dockerGenerateNginxConfig "${target}/spec.json" "${target}/config/nginx/default.conf"
    dockerGenerateFail2banConfig "${target}/spec.json" "${target}"
    dockerGenerateXrayConfig "${target}/spec.json" "${target}/xray.base"
    dockerTrafficRender xray "${target}/xray.base" \
        '{"schema_version":1,"accounts":{}}' >"${target}/config/xray/config.json"
    printf '<!doctype html><title>Source Test</title>source-ok\n' >"${target}/data/static/index.html"
    openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=source.padm.test \
        -addext subjectAltName=DNS:source.padm.test \
        -keyout "${target}/secrets/tls/source.padm.test.key" \
        -out "${target}/secrets/tls/source.padm.test.crt" >/dev/null 2>&1
    chown -R 10001:10001 "${target}/data/xray" "${target}/logs/nginx" "${target}/secrets/tls"
    chmod 0755 "${target}" "${target}/config" "${target}/config/"{xray,nginx} \
        "${target}/data" "${target}/data/"{xray,static} "${target}/logs" "${target}/logs/nginx" \
        "${target}/secrets" "${target}/secrets/tls"
    chmod 0644 "${target}/config/xray/config.json" "${target}/config/nginx/default.conf" \
        "${target}/secrets/tls/source.padm.test.crt" "${target}/logs/nginx/access.log"
    chmod 0600 "${target}/secrets/tls/source.padm.test.key"
done
python3 "${PROJECT_ROOT}/docker/tests/fail2ban-source-real.py" "${TEST_ROOT}"
printf 'docker-fail2ban-source-real-dual-stack-ok\n'
