#!/usr/bin/env bash
set -euo pipefail

# 在无现有 padm 部署的 rootful Linux daemon 上运行；四个输入必须是已构建的 tag@digest。
[[ "$#" == 4 ]] || { printf 'usage: tls-real.sh <xray> <sing-box> <nginx> <ops>\n' >&2; exit 2; }
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
# 复用完整入口装配，保证信号清理与正式 CLI 一致。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

XRAY_IMAGE=$1 SINGBOX_IMAGE=$2 NGINX_IMAGE=$3 OPS_IMAGE=$4
for image in "$@"; do
    dockerImageReferenceIsValid "${image}"
    docker image inspect "${image}" >/dev/null
done
dockerHostPreflight
for tool in openssl python3 nsenter; do dockerRequireCommand "${tool}"; done
existingContainers=$(docker ps -aq --filter label=com.docker.compose.project=padm-docker)
existingNetworks=$(docker network ls --format '{{.Name}}')
[[ -z "${existingContainers}" ]] && ! grep -qxF padm-docker <<<"${existingNetworks}" || {
    dockerError '真实 TLS 验收拒绝接管已有 padm-docker 容器或网络'
    exit 1
}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-tls-real.XXXXXX")
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_HEALTH_TIMEOUT=10
DOMAIN=tls.padm.test
UUID=11111111-1111-4111-8111-111111111111
TOKEN=0123456789abcdef0123456789abcdef
started=0
pid=
# 只注入健康输入错误；配置校验、换证、重建、失败及恢复全部运行真实 Docker。
cp() {
    local target=${*: -1}
    command cp "$@" || return $?
    if [[ "${started}" == 1 && (
        "${target}" == "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" ||
        "${target}" == "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/.${DOMAIN}.crt."*) ]]; then
        if cmp -s "${target}" "${TEST_ROOT}/certs/3.crt"; then
            printf 'invalid\n' >"${PADM_DOCKER_INSTALL_DIR}/data/sing-box/health.check"
            : >"${TEST_ROOT}/health-injected"
        else
            printf '{}\n' >"${PADM_DOCKER_INSTALL_DIR}/data/sing-box/health.check"
        fi
    fi
}
cleanup() {
    local status=$?
    trap - EXIT
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        [[ ! -f "${TEST_ROOT}/rotation.pid" ]] || kill -TERM "$(<"${TEST_ROOT}/rotation.pid")" 2>/dev/null || true
        wait "${pid}" || true
    fi
    if [[ "${started}" == 1 ]]; then
        if [[ "${status}" != 0 ]]; then
            dockerComposeRun logs --no-color >&2 || true
            dockerComposeRun ps -aq | xargs -r docker inspect --format '{{.Name}} {{json .State}}' >&2 || true
        fi
        if ! dockerComposeRun down --volumes >/dev/null; then
            dockerError "真实 TLS 验收清理失败，保留恢复文件：${TEST_ROOT}"
            dockerReleaseDeploymentLock || true
            exit 1
        fi
    fi
    dockerReleaseDeploymentLock || status=1
    rm -rf -- "${TEST_ROOT}"
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
mkdir -p "${TEST_ROOT}/certs" "${PADM_DOCKER_INSTALL_DIR}/client" \
    "${PADM_DOCKER_INSTALL_DIR}/config/"{xray,sing-box,nginx} \
    "${PADM_DOCKER_INSTALL_DIR}/data/subscription" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-test-ca \
    -addext basicConstraints=critical,CA:TRUE -keyout "${TEST_ROOT}/certs/ca.key" \
    -out "${TEST_ROOT}/certs/ca.crt" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "${DOMAIN}" >"${TEST_ROOT}/certs/extensions"
for serial in 1 2 3; do
    openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
        -keyout "${TEST_ROOT}/certs/${serial}.key" -out "${TEST_ROOT}/certs/${serial}.csr" >/dev/null 2>&1
    openssl x509 -req -in "${TEST_ROOT}/certs/${serial}.csr" -days 1 -set_serial "${serial}" \
        -CA "${TEST_ROOT}/certs/ca.crt" -CAkey "${TEST_ROOT}/certs/ca.key" \
        -extfile "${TEST_ROOT}/certs/extensions" -out "${TEST_ROOT}/certs/${serial}.crt" >/dev/null 2>&1
done
chmod 0600 "${TEST_ROOT}/certs/"*.key
cp "${TEST_ROOT}/certs/1.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
cp "${TEST_ROOT}/certs/1.key" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
cp "${TEST_ROOT}/certs/ca.crt" "${PADM_DOCKER_INSTALL_DIR}/client/ca.crt"
jq -n --arg xray "${XRAY_IMAGE}" --arg sing "${SINGBOX_IMAGE}" --arg nginx "${NGINX_IMAGE}" \
    --arg ops "${OPS_IMAGE}" --arg domain "${DOMAIN}" --arg uuid "${UUID}" --arg token "${TOKEN}" '
  {schema_version:3,release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[
     {id:21,listener_id:"entry-ws",core:"xray",server:$domain,public_port:35441,address_families:["ipv4"],
      name:"test-ws",uuid:$uuid,websocket:{domain:$domain,path:"padmtest",backend_port:31297,tls_port:8443}},
     {id:1,listener_id:"entry-reality",core:"sing-box",server:$domain,public_port:35442,
      address_families:["ipv4"],name:"test-reality",uuid:$uuid,
      reality:{server_name:"www.microsoft.com",target_host:"www.microsoft.com",target_port:443,
        private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
        public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"6ba85179e30d4fc2"}}]},
   tls:{domain:$domain},subscription:{enabled:true,token:$token},
   images:{xray:$xray,"sing-box":$sing,nginx:$nginx,ops:$ops,net:$ops},host_integrations:[]}
' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
spec="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
dockerGenerateXrayConfig "${spec}" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
dockerGenerateSingBoxConfig "${spec}" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
dockerGenerateNginxConfig "${spec}" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
dockerGenerateSubscription "${spec}" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}"
# 内部 TLS 夹具只验证已有轮换底座，不开放 Trojan 协议的菜单合同。
jq --arg domain "${DOMAIN}" '.inbounds += [{
  tag:"test-tls",listen:"0.0.0.0",port:35443,protocol:"trojan",
  settings:{clients:[{email:"test-xray-tls",password:"test-only"}]},
  streamSettings:{network:"tcp",security:"tls",tlsSettings:{certificates:[{
    certificateFile:("/etc/padm/secrets/tls/"+$domain+".crt"),
    keyFile:("/etc/padm/secrets/tls/"+$domain+".key")}]}}}]
' "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" >"${TEST_ROOT}/config.json"
mv "${TEST_ROOT}/config.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
jq --arg domain "${DOMAIN}" '.inbounds += [{
  type:"trojan",tag:"test-tls",listen:"0.0.0.0",listen_port:35444,users:[{name:"test",password:"test-only"}],
  tls:{enabled:true,certificate_path:("/etc/padm/secrets/tls/"+$domain+".crt"),
    key_path:("/etc/padm/secrets/tls/"+$domain+".key")}}]
' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >"${TEST_ROOT}/config.json"
mv "${TEST_ROOT}/config.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
dockerGenerateDeployment "${spec}" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
dockerGenerateImagesEnv "${spec}" "${PADM_DOCKER_INSTALL_DIR}/images.env" "${PADM_DOCKER_INSTALL_DIR}"
dockerGenerateCompose "${spec}" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
jq -n --arg domain "${DOMAIN}" --arg uuid "${UUID}" '
  {inbounds:([{tag:"socks-xray",listen_port:2081},{tag:"socks-sing",listen_port:2082},
    {tag:"socks-ws",listen_port:2083}] | map(. + {type:"socks",listen:"0.0.0.0"})),
   outbounds:([
    {type:"trojan",tag:"xray",server:"xray",server_port:35443,password:"test-only"},
    {type:"trojan",tag:"sing",server:"sing-box",server_port:35444,password:"test-only"},
    {type:"vless",tag:"ws",server:"nginx",server_port:8443,uuid:$uuid,
      transport:{type:"ws",path:"/padmtestws"}}] |
    map(. + {tls:{enabled:true,server_name:$domain,certificate_path:"/etc/padm/client/ca.crt"}})),
   route:{rules:[{inbound:["socks-xray"],action:"route",outbound:"xray"},
     {inbound:["socks-sing"],action:"route",outbound:"sing"},
     {inbound:["socks-ws"],action:"route",outbound:"ws"}]}}
' >"${PADM_DOCKER_INSTALL_DIR}/client/config.json"
jq --arg ops "${OPS_IMAGE}" --arg sing "${SINGBOX_IMAGE}" '
  .services.xray.ports = [] | .services["sing-box"].ports = [] | .services.nginx.ports = [] |
  .services["sing-box"].healthcheck = {
    test:["CMD","/usr/local/bin/sing-box","check","-c","/var/lib/padm/sing-box/health.check"],
    interval:"1s",timeout:"3s",retries:1,start_period:"1s"} |
  .services.origin = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
    entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
    volumes:[{type:"bind",source:"${PADM_DOCKER_ROOT}/data/static",target:"/srv",read_only:true}]} |
  .services.client = {image:$sing,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/config.json"],
    volumes:[{type:"bind",source:"${PADM_DOCKER_ROOT}/client",target:"/etc/padm/client",read_only:true}]} |
  .networks.default.labels["io.padm.test"] = "tls-real" |
  .services |= with_entries(.value.labels["io.padm.test"] = "tls-real")
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${TEST_ROOT}/compose.json"
mv "${TEST_ROOT}/compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}"
dockerEnsureRuntimeDataPermissions
printf '{}\n' >"${PADM_DOCKER_INSTALL_DIR}/data/sing-box/health.check"
chmod 0644 "${PADM_DOCKER_INSTALL_DIR}/data/sing-box/health.check"
chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/client"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/client/"*
chown -R 0:10001 "${PADM_DOCKER_INSTALL_DIR}/client"
printf 'padm-real-client-ok\n' >"${PADM_DOCKER_INSTALL_DIR}/data/static/proof.txt"
chown 0:10001 "${PADM_DOCKER_INSTALL_DIR}/data/static/proof.txt"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/data/static/proof.txt"
dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
dockerManagedSpecMatchesDeployment "${spec}" "${PADM_DOCKER_INSTALL_DIR}/deployment.json" \
    "${PADM_DOCKER_INSTALL_DIR}/images.env"
[[ "$(dockerTlsConsumers "${DOMAIN}")" == '["xray","sing-box","nginx"]' ]]
started=1
dockerComposeRun up -d --wait --wait-timeout 60

probe() {
    local clientPid
    docker run --rm --init --pull=never --network padm-docker --entrypoint python3 "${OPS_IMAGE}" -c '
import socket
import ssl
import sys
import urllib.request

expected, domain, token = sys.argv[1:]
for host, port in (("xray",35443),("sing-box",35444),("nginx",8443)):
    context = ssl._create_unverified_context()
    with context.wrap_socket(socket.create_connection((host,port),timeout=5),server_hostname=domain) as s:
        pem = ssl.DER_cert_to_PEM_cert(s.getpeercert(binary_form=True))
    import subprocess
    serial = subprocess.check_output(["openssl","x509","-noout","-serial"],input=pem.encode()).decode().strip()
    assert serial == "serial=" + expected, (host,serial)
context = ssl._create_unverified_context()
data = urllib.request.urlopen("https://nginx:8443/subscriptions/"+token,context=context,timeout=5).read()
assert b"vless://" in data and b"type=ws" in data and b"security=reality" in data
' "$1" "${DOMAIN}" "${TOKEN}"
    for port in 2081 2082 2083; do
        clientPid=$(docker inspect --format '{{.State.Pid}}' "$(dockerComposeRun ps -q client)")
        nsenter --target "${clientPid}" --net curl -fsS --max-time 10 --noproxy "" \
            --socks5-hostname "127.0.0.1:${port}" http://origin:8088/proof.txt |
            grep -qxF padm-real-client-ok
    done
}
rotate() (
    trap 'dockerCommandInterrupted 143' TERM
    trap 'dockerCleanupTlsCandidate; dockerReleaseDeploymentLock' EXIT
    printf '%s\n' "${BASHPID}" >"${TEST_ROOT}/rotation.pid"
    dockerTlsInstallCommand --domain "${DOMAIN}" --cert "${TEST_ROOT}/certs/$1.crt" \
        --key "${TEST_ROOT}/certs/$1.key"
)
probe 01
rotate 2
probe 02
baseline=$(jq '[.accounts[] | .upload + .download] | add // 0' "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
[[ "${baseline}" -gt 0 ]]
if rotate 3 >"${TEST_ROOT}/health-failure.log" 2>&1; then
    dockerError '应拒绝真实 sing-box 健康失败'
    exit 1
fi
[[ -f "${TEST_ROOT}/health-injected" ]] &&
    grep -q 'is unhealthy' "${TEST_ROOT}/health-failure.log" || {
    cat "${TEST_ROOT}/health-failure.log" >&2
    dockerError '未触发真实 sing-box 健康失败'
    exit 1
}
probe 02
rm -f "${TEST_ROOT}/rotation.pid"
rotate 1 &
pid=$!
for _ in {1..1000}; do
    cmp -s "${TEST_ROOT}/certs/1.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" && break
    kill -0 "${pid}" || { wait "${pid}"; exit 1; }
    sleep 0.01
done
cmp -s "${TEST_ROOT}/certs/1.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
kill -TERM "$(<"${TEST_ROOT}/rotation.pid")"
if wait "${pid}"; then exit 1; else [[ "$?" == 143 ]]; fi
pid=
probe 02
[[ "$(jq '[.accounts[] | .upload + .download] | add // 0' \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" -ge "${baseline}" ]]
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.tls.*' -print)" ]]
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]]
printf 'docker-tls-real-ok: architecture=%s xray=%s sing-box=%s nginx=%s ops=%s\n' \
    "$(docker info --format '{{.Architecture}}')" "$@"
