#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
# 初装和发布信任仅适配本地夹具；后续已安装 CLI 不替换任何防护事务函数。
if [[ "${1:-}" == --seed ]]; then
    [[ "$#" == 2 && "$(id -u)" == 0 && -f /.dockerenv ]]
    TEST_ROOT=$(cd -- "$2" && pwd -P)
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/deployment" PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin"
    source "${PROJECT_ROOT}/install-docker.sh"
    MOCK_BIN="${TEST_ROOT}/bin" IMAGE_DIGEST=$(printf '%064d' 0)
    OPS_IMAGE=$(jq -r '.ops.reference' "${TEST_ROOT}/images.json")
    source "${PROJECT_ROOT}/docker/tests/configure-fixture.sh"
    dockerConfigureTestFixture
    jq --slurpfile images "${TEST_ROOT}/images.json" '
      .images = ($images[0] | with_entries(
        .value.reference as $ref | ($ref | split("@")[1]) as $digest |
        .value = {reference:$ref,index_digest:$digest,
          platforms:{"linux/amd64":$digest,"linux/arm64":$digest}}))
    ' "${CONFIGURE_MANIFEST}" >"${CONFIGURE_MANIFEST}.next"
    mv -- "${CONFIGURE_MANIFEST}.next" "${CONFIGURE_MANIFEST}"
    CONFIGURE_MANIFEST_SHA=$(sha256sum "${CONFIGURE_MANIFEST}" | cut -d ' ' -f 1)
    jq --arg sha "${CONFIGURE_MANIFEST_SHA}" '.manifest_sha256 = $sha' \
        "${CONFIGURE_BUNDLE}" >"${CONFIGURE_BUNDLE}.next"
    mv -- "${CONFIGURE_BUNDLE}.next" "${CONFIGURE_BUNDLE}"
    jq --arg sha "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
        --slurpfile images "${TEST_ROOT}/images.json" '
      .release = {version:"3.1.8",manifest_sha256:$sha,signature_identity:$identity} |
      .images = ($images[0] | with_entries(.value = .value.reference))
    ' "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/request.json"
    chmod 0600 "${TEST_ROOT}/request.json"
    dockerHostPreflight
    dockerAssertInstallAllowed
    dockerAcquireDeploymentLock
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerReleaseDeploymentLock' EXIT
    dockerInitializeStateRoot
    dockerInstallBundle "${PROJECT_ROOT}"
    dockerInstallCli
    dockerRequireInstalledBundle
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/static"
    cp -a -- "${TEST_ROOT}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
    printf '<!doctype html><title>Source Test</title>source-ok\n' \
        >"${PADM_DOCKER_INSTALL_DIR}/data/static/index.html"
    dockerCreateConfigurationCandidate
    dockerGenerateCandidate "${TEST_ROOT}/request.json" "${DOCKER_CONFIG_CANDIDATE}"
    dockerValidateCandidate "${DOCKER_CONFIG_CANDIDATE}/config/spec.json" "${DOCKER_CONFIG_CANDIDATE}"
    dockerBackupConfiguration
    dockerInstallCandidate "${DOCKER_CONFIG_CANDIDATE}" "${DOCKER_CONFIG_BACKUP}"
    dockerEnsureRuntimeDataPermissions
    dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-8}"
    dockerTrafficScheduleInstall
    dockerRenewalScheduleInstall
    dockerGeoScheduleInstall
    DOCKER_CONFIG_SWITCHED=0
    printf 'ws-port-seed-scope=local-test-only-not-release-verified\n'
    exit 0
fi
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
for tool in jq python3 docker dockerd nsenter ip unshare sysctl openssl curl; do
    command -v "${tool}" >/dev/null
done
[[ -f /node-images.json && -f /node-images.tar && -d /n ]] || {
    printf 'fail2ban-source-real: 缺少离线镜像或隔离数据卷\n' >&2
    exit 1
}
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

mkdir -p "${TEST_ROOT}/bundle"
printf 'local-test\n' >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
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
     devices:[],schedules:[],settings:{log_file:"access.log",ports:[24444,24445],
       max_retry:3,find_time:600,ban_time:3600}}]} |
   .core.protocols += [(.core.protocols[0] | .listener_id = "entry-source-ws2" |
     .public_port = 24445 | .name = "source-ws2" |
     .uuid = "22222222-2222-4222-8222-222222222222" |
     .websocket.path = "source-test2" | .websocket.backend_port = 31298 | .websocket.tls_port = 8444)]
' >"${TEST_ROOT}/base.json"
for family in ipv4 dual; do
    target="${TEST_ROOT}/${family}"
    mkdir -p "${target}/config/"{xray,nginx,net/fail2ban} "${target}/data/"{xray,static,net/fail2ban} \
        "${target}/logs/nginx" "${target}/secrets/tls"
    jq --arg family "${family}" '
      if $family == "dual" then
        .core.protocols |= map(.address_families |= ((. + ["ipv6"]) | unique))
      else . end
    ' "${TEST_ROOT}/base.json" >"${target}/config/spec.json"
    dockerConfigureSpecValidate "${target}/config/spec.json"
    dockerGenerateCompose "${target}/config/spec.json" "${target}/compose.json"
    dockerGenerateDeployment "${target}/config/spec.json" "${target}/deployment.json"
    dockerGenerateImagesEnv "${target}/config/spec.json" "${target}/images.env" "${target}"
    dockerGenerateNginxConfig "${target}/config/spec.json" "${target}/config/nginx/default.conf"
    dockerGenerateFail2banConfig "${target}/config/spec.json" "${target}"
    dockerGenerateXrayConfig "${target}/config/spec.json" "${target}/xray.base"
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
        "${target}/secrets/tls/source.padm.test.crt"
    chmod 0750 "${target}/logs/nginx"
    chmod 0640 "${target}/logs/nginx/access.log"
    chmod 0600 "${target}/secrets/tls/source.padm.test.key"
done
python3 "${PROJECT_ROOT}/docker/tests/fail2ban-source-real.py" "${TEST_ROOT}"
printf 'docker-fail2ban-source-real-dual-stack-ok\n'
