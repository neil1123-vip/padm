#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
stage=arguments
# 保留失败位置和原退出码，避免清理日志掩盖没有标准错误的断言。
trap 'status=$?; printf "vmess-real-fail: protocol=%s core=%s stage=%s line=%s rc=%s command=%s\n" "${PROTOCOL:-unset}" "${CORE:-unset}" "${stage}" "${LINENO}" "${status}" "${BASH_COMMAND}" >&2; exit "${status}"' ERR

# 仅使用隔离项目、网络和命名卷，传统 TLS 传输复用同一验证流程。
[[ "$#" == 4 || "$#" == 6 ]] || {
    printf 'usage: vmess-real.sh <local-xray> <local-sing-box> <local-ops> <local-nginx> [21|22|23|24|25|27|29 xray|sing-box]\n' >&2
    exit 2
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || { printf 'vmess-real.sh requires Linux root\n' >&2; exit 1; }
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3 NGINX_REF=$4
PROTOCOL=${5:-22} CORE=${6:-xray}
CDN_ENTRIES=${PADM_TEST_CDN_ENTRIES:-0}
ALPN_ORDERS=${PADM_TEST_ALPN_ORDERS:-0}
SUBSCRIPTION_PUBLICATION=${PADM_TEST_SUBSCRIPTION_PUBLICATION:-0}
SUBSCRIPTION_SITE_TEMPLATE=${PADM_TEST_SUBSCRIPTION_SITE_TEMPLATE:-}
[[ "${CDN_ENTRIES}" == 0 || "${CDN_ENTRIES}" == 1 ]] || exit 2
[[ "${ALPN_ORDERS}" == 0 || "${ALPN_ORDERS}" == 1 ]] || exit 2
[[ "${SUBSCRIPTION_PUBLICATION}" == 0 || "${SUBSCRIPTION_PUBLICATION}" == 1 ]] || exit 2
[[ -z "${SUBSCRIPTION_SITE_TEMPLATE}" || ( "${SUBSCRIPTION_SITE_TEMPLATE}" == photos &&
    "${SUBSCRIPTION_PUBLICATION}" == 1 && "${PROTOCOL}:${CORE}" == 23:sing-box ) ]] || exit 2
[[ "${PROTOCOL}:${CORE}" == 21:xray || "${PROTOCOL}:${CORE}" == 22:xray || "${PROTOCOL}:${CORE}" == 23:xray ||
    "${PROTOCOL}:${CORE}" == 23:sing-box || "${PROTOCOL}:${CORE}" == 24:xray ||
    "${PROTOCOL}:${CORE}" == 25:xray || "${PROTOCOL}:${CORE}" == 27:xray ||
    "${PROTOCOL}:${CORE}" == 29:xray ]] || exit 2
TRANSPORT=ws TRANSPORT_KEY=websocket BACKEND_PORT=31297 TEST_NAME=vmess-real APP_PROTOCOL=vmess
case "${PROTOCOL}" in
21) TEST_NAME=vless-ws-real APP_PROTOCOL=vless ;;
23) TRANSPORT=httpupgrade TRANSPORT_KEY=httpupgrade BACKEND_PORT=31306 TEST_NAME=httpupgrade-real ;;
24) TRANSPORT=grpc TRANSPORT_KEY=grpc_tls BACKEND_PORT=31301 TEST_NAME=vless-grpc-tls-real APP_PROTOCOL=vless ;;
25) TRANSPORT=grpc TRANSPORT_KEY=grpc_tls BACKEND_PORT=31304 TEST_NAME=trojan-grpc-tls-real APP_PROTOCOL=trojan ;;
27) TRANSPORT=tcp TRANSPORT_KEY=fallback_tls BACKEND_PORT=35468 TEST_NAME=vless-tls-vision-real APP_PROTOCOL=vless ;;
29) TRANSPORT=tcp TRANSPORT_KEY=fallback_tls BACKEND_PORT=35468 TEST_NAME=trojan-tls-fallback-real APP_PROTOCOL=trojan ;;
esac
TLS_PORT=8443
if [[ "${CDN_ENTRIES}" == 1 ]]; then
    [[ "${PROTOCOL}" == 21 || "${PROTOCOL}" == 22 || "${PROTOCOL}" == 23 ||
        "${PROTOCOL}:${CORE}" == 24:xray || "${PROTOCOL}:${CORE}" == 25:xray ]] || exit 2
    # 分享端口就是实际 TLS 端口，客户端不得用容器端口替换生产链接。
    TLS_PORT=35469 TEST_NAME="${TEST_NAME}-cdn"
fi
if [[ "${ALPN_ORDERS}" == 1 ]]; then
    [[ "${CDN_ENTRIES}" == 0 &&
        ( "${PROTOCOL}:${CORE}" == 27:xray || "${PROTOCOL}:${CORE}" == 29:xray ) ]] || exit 2
    TEST_NAME="${TEST_NAME}-alpn"
fi
if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
    [[ "${CDN_ENTRIES}" == 0 && "${ALPN_ORDERS}" == 0 &&
        ( "${PROTOCOL}:${CORE}" == 22:xray || "${PROTOCOL}:${CORE}" == 23:sing-box ||
          "${PROTOCOL}:${CORE}" == 24:xray || "${PROTOCOL}:${CORE}" == 25:xray ) ]] || exit 2
    TLS_PORT=35468 TEST_NAME="${TEST_NAME}-publication"
fi
[[ -z "${SUBSCRIPTION_SITE_TEMPLATE}" ]] || TEST_NAME="${TEST_NAME}-photos"
for tool in docker jq python3 sha256sum tar openssl awk diff; do command -v "${tool}" >/dev/null; done
stage=images
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
NGINX_ID=$(docker image inspect --format '{{.Id}}' "${NGINX_REF}")
CURL_ID=
if [[ ( "${CORE}" == sing-box && "${CDN_ENTRIES}" == 0 && "${SUBSCRIPTION_PUBLICATION}" == 0 ) ||
    "${TRANSPORT}" == tcp ]]; then
    [[ -n "${PADM_TEST_HTTP2_CURL_REF:-}" ]] || {
        printf 'sing-box stats or fallback h2 requires PADM_TEST_HTTP2_CURL_REF (local HTTP2 curl image)\n' >&2
        exit 2
    }
    CURL_ID=$(docker image inspect --format '{{.Id}}' "${PADM_TEST_HTTP2_CURL_REF}")
    [[ "${CURL_ID}" =~ ^sha256:[a-f0-9]{64}$ ]]
fi
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${NGINX_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-${TEST_NAME}-${CORE}-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
subnet=$(printf 'fd42:7061:646d:%x::/64' "${RANDOM}")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-vmess-real.XXXXXX")
cleanup() {
    local status=$? ids resource name cleanup_failed=0
    trap - EXIT
    ids=$(docker ps -aq --filter "label=io.padm.test=${project}")
    if [[ -n "${ids}" ]]; then
        if [[ "${status}" != 0 ]]; then
            while IFS= read -r id; do
                docker logs "${id}" >&2 || true
                docker inspect --format '{{.Name}} {{json .State}}' "${id}" >&2 || true
            done <<<"${ids}"
        fi
        # shellcheck disable=SC2086
        docker rm -f ${ids} >/dev/null || cleanup_failed=1
    fi
    for resource in network volume; do
        name=${project}; [[ "${resource}" != volume ]] || name=${volume}
        if docker "${resource}" inspect "${name}" >/dev/null 2>&1; then
            if docker "${resource}" inspect "${name}" |
                jq -e --arg project "${project}" '.[0].Labels["io.padm.test"] == $project' >/dev/null; then
                docker "${resource}" rm "${name}" >/dev/null || cleanup_failed=1
            else cleanup_failed=1; fi
        fi
    done
    if [[ "${cleanup_failed}" == 0 ]]; then rm -rf -- "${TEST_ROOT}"
    else
        printf 'vmess-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2
        status=1
    fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ "${TRANSPORT}" == tcp ]]; then
    docker run --rm --pull=never --network none --label "io.padm.test=${project}" \
        --entrypoint curl "${CURL_ID}" --version |
        grep -Eq '^Features:.*[[:space:]]HTTP2([[:space:]]|$)'
fi
docker volume create --label "io.padm.test=${project}" "${volume}" >/dev/null
stage=bundle
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
dockerCleanupStagedBundle
DOMAIN=vmess.padm.test
[[ "${PROTOCOL}" != 23 ]] || DOMAIN=HttpUpgrade.padm.test
[[ "${TRANSPORT}" != grpc ]] || DOMAIN=grpc-tls.padm.test
[[ "${TRANSPORT}" != tcp ]] || DOMAIN=fallback-tls.padm.test
UUID=11111111-1111-4111-8111-111111111111
stage=certificates
TLS_DIR="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
mkdir -p "${TEST_ROOT}/certs" "${TLS_DIR}" "${TEST_ROOT}/runtime/"{client,origin}
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-vmess-test-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout "${TEST_ROOT}/certs/ca.key" -out "${TEST_ROOT}/certs/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${TLS_DIR}/${DOMAIN}.key" -out "${TEST_ROOT}/certs/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "${DOMAIN}" >"${TEST_ROOT}/certs/extensions"
openssl x509 -req -in "${TEST_ROOT}/certs/server.csr" -days 1 -set_serial 1 \
    -CA "${TEST_ROOT}/certs/ca.crt" -CAkey "${TEST_ROOT}/certs/ca.key" \
    -extfile "${TEST_ROOT}/certs/extensions" -out "${TLS_DIR}/${DOMAIN}.crt" >/dev/null 2>&1
openssl verify -CAfile "${TEST_ROOT}/certs/ca.crt" "${TLS_DIR}/${DOMAIN}.crt" >/dev/null
SPEC="${TEST_ROOT}/spec.json"
jq -n --arg uuid "${UUID}" --arg domain "${DOMAIN}" --arg core "${CORE}" --arg name "${TEST_NAME}" \
    --arg key "${TRANSPORT_KEY}" --argjson protocol "${PROTOCOL}" --argjson backend "${BACKEND_PORT}" \
    --argjson tls_port "${TLS_PORT}" --argjson cdn "${CDN_ENTRIES}" --argjson publication "${SUBSCRIPTION_PUBLICATION}" \
    --arg siteTemplate "${SUBSCRIPTION_SITE_TEMPLATE}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:$core,secondary_type:null,protocols:[
     {id:$protocol,listener_id:"entry-vmess",core:$core,server:$domain,public_port:35468,
      address_families:["ipv4","ipv6"],name:$name,uuid:$uuid,
      ($key):(if $protocol == 27 or $protocol == 29 then {domain:$domain,http_port:31300,http2_port:31302}
        else {domain:$domain,backend_port:$backend,tls_port:$tls_port} +
          if $protocol == 24 or $protocol == 25 then
            {service_name:(if $publication == 1 then "subscriptions" else "padm_grpc-1" end)}
          else {path:"padmvmess"} end
        end)}]},
   tls:{domain:$domain},subscription:{enabled:($publication == 1),token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
    host_integrations:[]} +
      (if $cdn == 1 then {port_aliases:[{listener_id:"entry-vmess",public_port:35469,share_default:true}]}
       else {} end) +
      if $publication == 1 then {accounts:[{
        id:"22222222-2222-4222-8222-222222222222",name:"independent",enabled:true,
        uuid:"33333333-3333-4333-8333-333333333333",password:"44444444-4444-4444-8444-444444444444",
        shadowsocks_password:null,listeners:["entry-vmess"]}]} else {} end |
      if $siteTemplate != "" then .site = {mode:"static"} else . end
' >"${SPEC}"
chmod 0600 "${SPEC}"
subscriptionShares=
if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
    subscriptionShares="${TEST_ROOT}/shares.json"
    jq -n '{schema_version:1,groups:[{
      id:"share-0123456789abcdef",name:"publication",enabled:true,token:"publication_group_0123456789abcdef",
      account_ids:["22222222-2222-4222-8222-222222222222"],listener_ids:["entry-vmess"]}]}' >"${subscriptionShares}"
fi
stage=spec
dockerConfigureSpecValidate "${SPEC}"
stage=candidate
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
if [[ -n "${SUBSCRIPTION_SITE_TEMPLATE}" ]]; then
    # 模板实链路复用已激活可信包，生产生成器继续核验模板清单和默认渲染。
    DOCKER_STAGED_BUNDLE_PATH="$(dockerCurrentBundlePath)" \
        dockerGenerateCandidate "${SPEC}" "${candidate}" '' '' '' '' "${SUBSCRIPTION_SITE_TEMPLATE}" "${subscriptionShares}"
else
    dockerGenerateCandidate "${SPEC}" "${candidate}" '' '' '' '' '' "${subscriptionShares}"
fi
jq -e --arg uuid "${UUID}" --arg core "${CORE}" --arg transport "${TRANSPORT}" \
    --arg domain "${DOMAIN}" --argjson backend "${BACKEND_PORT}" --arg app "${APP_PROTOCOL}" \
    --argjson publication "${SUBSCRIPTION_PUBLICATION}" '
  if $core == "xray" then any(.inbounds[]; .protocol == $app and .tag == "entry-vmess" and .port == $backend and
    (.settings.clients | length) == (1 + $publication) and
    (.settings | .clients |= .[:1]) == ((if $app == "trojan" then {clients:[{password:$uuid,email:$uuid}]}
      elif $app == "vless" then {clients:[{id:$uuid,email:$uuid} +
        if $transport == "tcp" then {flow:"xtls-rprx-vision"} else {} end],decryption:"none"}
      else {clients:[{id:$uuid,email:$uuid,alterId:0}]} end) +
        if $transport == "tcp" then {fallbacks:[{dest:"nginx:31300",xver:1},
          {alpn:"h2",dest:"nginx:31302",xver:1}]} else {} end) and
    .streamSettings == (if $transport == "tcp" then {network:"tcp",security:"tls",tlsSettings:{
      serverName:$domain,alpn:["h2","http/1.1"],rejectUnknownSni:true,minVersion:"1.2",certificates:[{
        certificateFile:("/etc/padm/secrets/tls/"+$domain+".crt"),
        keyFile:("/etc/padm/secrets/tls/"+$domain+".key")}]}}
      else {network:$transport,security:"none"} +
        if $transport == "ws" then {wsSettings:{path:"/padmvmessws"}}
        elif $transport == "grpc" then {grpcSettings:{
          serviceName:(if $publication == 1 then "subscriptions" else "padm_grpc-1" end)}}
        else {httpupgradeSettings:{path:"/padmvmess",host:$domain}} end end))
  else any(.inbounds[]; .type == "vmess" and .tag == "entry-vmess" and .listen_port == $backend and
    (.users | length) == (1 + $publication) and .users[:1] == [{uuid:$uuid,name:$uuid,alterId:0}] and
    .transport == {type:"httpupgrade",path:"/padmvmess",host:$domain}) end' \
    "${candidate}/config/${CORE}/config.json" >/dev/null
if [[ "${TRANSPORT}" == grpc ]]; then
    grep -qF 'http2 on;' "${candidate}/config/nginx/default.conf"
    if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
        # token 正则须优先于同名 gRPC 前缀，同时保留真实 gRPC 通道。
        grep -qF 'location /subscriptions/ {' "${candidate}/config/nginx/default.conf"
    else
        grep -qF 'location ^~ /padm_grpc-1/ {' "${candidate}/config/nginx/default.conf"
    fi
    grep -qF "grpc_pass grpc://xray:${BACKEND_PORT};" "${candidate}/config/nginx/default.conf"
fi
jq -e --arg transport "${TRANSPORT}" --argjson tls_port "${TLS_PORT}" --argjson cdn "${CDN_ENTRIES}" '
  .listeners == ([{listener_id:"entry-vmess",
  service:(if $transport == "tcp" then "xray" else "nginx" end),public_port:35468,
  container_port:(if $transport == "tcp" then 35468 else $tls_port end),transport:"tcp",address_families:["ipv4","ipv6"]}] +
    if $cdn == 1 then [{listener_id:"alias-35469-tcp",target_listener_id:"entry-vmess",service:"nginx",
      public_port:35469,container_port:$tls_port,transport:"tcp",address_families:["ipv4","ipv6"]}] else [] end)' \
    "${candidate}/deployment.json" >/dev/null
cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerCleanupConfigurationCandidate
dockerEnsureRuntimeDataPermissions
[[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/data/static")" == 0:10001:750 ]]
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerTrafficAccounts "${CORE}" | jq -e --arg uuid "${UUID}" --argjson publication "${SUBSCRIPTION_PUBLICATION}" '
  length == (1 + $publication) and any(.[]; .account == $uuid)' >/dev/null
[[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/config.json")" == 0:10001:640 ]]
[[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base")" == 0:0:600 ]]
base_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base")
stage=original-links
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == "$((1 + SUBSCRIPTION_PUBLICATION))" ]]
[[ "${CDN_ENTRIES}" == 0 ]] || cp -- "${TEST_ROOT}/links.txt" "${TEST_ROOT}/original.links.txt"
if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
    bundleEntry="$(dockerCurrentBundlePath)/install-docker.sh"
    bash "${bundleEntry}" subscription content --base >"${TEST_ROOT}/main-content.txt"
    bash "${bundleEntry}" subscription links --base >"${TEST_ROOT}/main-url.txt"
    cmp -s "${TEST_ROOT}/main-content.txt" \
        "${PADM_DOCKER_INSTALL_DIR}/data/subscription/0123456789abcdef"
    dockerSubscriptionLinks "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" share-0123456789abcdef >"${TEST_ROOT}/group-url.txt"
    siteResources='{}'
    if [[ -n "${SUBSCRIPTION_SITE_TEMPLATE}" ]]; then
        siteResources=$(python3 - "${PADM_DOCKER_INSTALL_DIR}/data/static" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
assert "Light and Distance" in (root / "index.html").read_text()
resources = {"/" + path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
             for path in sorted(root.rglob("*")) if path.is_file()}
assert {"/index.html", "/assets/style.css", "/assets/forest.jpg", "/assets/favicon.png",
        "/light-in-the-trees.html"} <= resources.keys()
resources["/"] = resources["/index.html"]
print(json.dumps(resources))
PY
        )
    fi
    jq -n --slurpfile spec "${SPEC}" --rawfile main "${TEST_ROOT}/main-url.txt" \
        --rawfile group "${TEST_ROOT}/group-url.txt" --argjson siteResources "${siteResources}" \
        --rawfile mainContent "${TEST_ROOT}/main-content.txt" \
        --rawfile groupContent "${PADM_DOCKER_INSTALL_DIR}/data/subscription/publication_group_0123456789abcdef" '
      {main:($main | rtrimstr("\n")),
       group:($group | rtrimstr("\n")),domain:$spec[0].tls.domain,port:35468,
       expected:{main:$mainContent,group:$groupContent},site_resources:$siteResources}
    ' >"${TEST_ROOT}/runtime/client/publication.json"
    chmod 0640 "${TEST_ROOT}/runtime/client/publication.json"
    chown 0:10001 "${TEST_ROOT}/runtime/client/publication.json"
fi
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/logs" "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/certs/ca.crt" "${TEST_ROOT}/runtime/client/ca.crt"
cat >"${TEST_ROOT}/runtime/origin/server.py" <<'PY'
import http.server
import json
import socket
import threading

counts = {"tcp": 0, "udp": 0}
lock = threading.Lock()
proof = b"padm-vmess-real-proof\n"
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with lock:
            if self.path == "/proof.txt":
                counts["tcp"] += 1
                body = proof
            elif self.path == "/counts":
                body = json.dumps(counts).encode()
            else:
                self.send_error(404)
                return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
def echo():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("0.0.0.0", 8089))
        while True:
            data, address = sock.recvfrom(65535)
            with lock:
                counts["udp"] += 1
            sock.sendto(data, address)
threading.Thread(target=echo, daemon=True).start()
http.server.ThreadingHTTPServer(("0.0.0.0", 8088), Handler).serve_forever()
PY
chmod 0750 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/"{client,origin}
chmod 0640 "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/server.py"
chown 0:10001 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/"{client,origin} \
    "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/server.py"
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg core "${CORE}" --arg xray "${XRAY_ID}" \
    --arg sing "${SING_ID}" --arg ops "${OPS_ID}" --arg nginx "${NGINX_ID}" --arg subnet "${subnet}" \
    --arg domain "${DOMAIN}" --argjson cdn "${CDN_ENTRIES}" --argjson publication "${SUBSCRIPTION_PUBLICATION}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  .networks.default.enable_ipv6 = true | .networks.default.ipam = {config:[{subnet:$subnet}]} |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services[$core].image = (if $core == "xray" then $xray else $sing end) | .services.nginx.image = $nginx |
  (if $publication == 1 then .services.subscription.image = $ops else . end) |
  (if $cdn == 1 or $publication == 1 then .services.nginx.networks = {default:{aliases:[$domain,"edge.padm.test"]}} else . end) |
  .services |= with_entries(.value.ports = [] | .value.init = true | .value.pull_policy = "never" |
    .value.labels["io.padm.test"] = $project |
    .value.volumes |= map(.source as $source |
      .type = "volume" | .source = "files" |
      .volume = {nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} |
      del(.bind))) |
  .services.origin = {image:$ops,pull_policy:"never",user:"10001:10001",read_only:true,init:true,cap_drop:["ALL"],
    entrypoint:["python3","/srv/server.py"],labels:{"io.padm.test":$project},
    healthcheck:{test:["CMD","python3","-c","import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8088/counts\",timeout=2).read()"],
      interval:"1s",timeout:"3s",retries:3,start_period:"1s"},
    volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
      volume:{nocopy:true,subpath:"runtime/origin"}}]} |
  .services.client = {image:$sing,pull_policy:"never",user:"10001:10001",read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/config.json"],
    volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]}
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@" </dev/null; }
stage=services
compose config --format json >/dev/null
if [[ "${CORE}" == xray ]]; then
    compose run --rm --no-deps xray -test -config /etc/padm/xray/config.json >/dev/null
else
    compose run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null
fi
compose up -d --pull never --wait --wait-timeout 60 "${CORE}" origin
compose run --rm --no-deps nginx -t >/dev/null
compose up -d --pull never --wait --wait-timeout 60 nginx
for service in "${CORE}" nginx; do
    container=$(compose ps -q "${service}")
    case "${service}" in xray) image=${XRAY_ID} ;; sing-box) image=${SING_ID} ;; nginx) image=${NGINX_ID} ;; esac
    docker inspect "${container}" | jq -e --arg project "${project}" --arg image "${image}" '
      .[0] | .State.Running and .Config.Image == $image and .Config.User == "10001:10001" and
      .HostConfig.ReadonlyRootfs and .HostConfig.Init and .HostConfig.CapDrop == ["ALL"] and
      .Config.Labels["io.padm.test"] == $project and
      (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null)' >/dev/null
done
endpointService=nginx
[[ "${TRANSPORT}" != tcp ]] || endpointService=xray
addresses=$(docker inspect "$(compose ps -q "${endpointService}")" |
    jq -cer --arg project "${project}" '.[0].NetworkSettings.Networks[$project] | [.IPAddress,.GlobalIPv6Address]')
cdnRenderConfiguration() {
    local phase=$1 request="${TEST_ROOT}/cdn-${1}.json" file
    stage="cdn-${phase}"
    case "${phase}" in
    override)
        jq --argjson addresses "$(jq -c '. + ["edge.padm.test"]' <<<"${addresses}")" '
          .cdn_entries = [{listener_id:"entry-vmess",addresses:$addresses}]
        ' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${request}"
        ;;
    clear)
        jq 'del(.cdn_entries)' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${request}"
        ;;
    *) return 2 ;;
    esac
    chmod 0600 "${request}"
    dockerConfigureSpecValidate "${request}"
    dockerCreateConfigurationCandidate
    dockerGenerateCandidate "${request}" "${DOCKER_CONFIG_CANDIDATE}"
    for file in "config/${CORE}/config.json" "config/${CORE}/users.base" config/nginx/default.conf; do
        cmp -s -- "${TEST_ROOT}/runtime/${file}" "${DOCKER_CONFIG_CANDIDATE}/${file}"
    done
    # 编辑事务由 cdn-entries.sh 验证；这里核对生产生成器与真实连接，不替换在线前置检查。
    cp -- "${DOCKER_CONFIG_CANDIDATE}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    dockerCleanupConfigurationCandidate
    dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
    if [[ "${phase}" == clear ]]; then
        cmp -s -- "${TEST_ROOT}/original.links.txt" "${TEST_ROOT}/links.txt"
    fi
    printf 'docker-cdn-entries-generation-ok: protocol=%s core=%s phase=%s core-users-nginx=unchanged\n' \
        "${PROTOCOL}" "${CORE}" "${phase}"
}
cdnPhase=base
if [[ "${CDN_ENTRIES}" == 1 ]]; then
    cdnPhase=override
    cdnRenderConfiguration "${cdnPhase}"
fi
if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
    stage=subscription-download
    docker run --rm --init -i --pull=never --read-only --cap-drop ALL --user 10001:10001 \
        --network "${project}" --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly,volume-subpath=runtime/client" --entrypoint python3 "${OPS_ID}" \
        - "${addresses}" >"${TEST_ROOT}/publication-content.json" <<'PY'
import hashlib
import http.client
import ipaddress
import json
from pathlib import Path
import socket
import ssl
import sys
import urllib.parse

root = Path("/test")
settings = json.loads((root / "publication.json").read_text())
endpoints = json.loads(sys.argv[1])
assert [ipaddress.ip_address(value).version for value in endpoints] == [4, 6]
context = ssl.create_default_context(cafile=root / "ca.crt")
assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
contents = {}
for kind in ("main", "group"):
    uri = urllib.parse.urlsplit(settings[kind])
    assert uri.scheme == "https" and uri.hostname == settings["domain"].lower()
    assert uri.port == settings["port"] == 35468 and not uri.query and not uri.fragment
    assert uri.username is None and uri.password is None and uri.path.startswith("/subscriptions/")
    expected = settings["expected"][kind].encode()
    for endpoint in endpoints:
        for path, status in ((uri.path, 200), ("/subscriptions/unknown_token_0123456789abcdef", 404)):
            connection = http.client.HTTPSConnection(uri.hostname, uri.port, context=context, timeout=5)
            with socket.create_connection((endpoint, uri.port), timeout=5) as raw:
                connection.sock = context.wrap_socket(raw, server_hostname=uri.hostname)
                try:
                    connection.request("GET", path)
                    response = connection.getresponse()
                    body = response.read()
                    assert response.status == status, (kind, response.status, status)
                    if status == 200:
                        assert body == expected and body
                        contents[kind] = body.decode()
                finally:
                    connection.close()
for endpoint in endpoints:
    for path, digest in settings["site_resources"].items():
        connection = http.client.HTTPSConnection(uri.hostname, uri.port, context=context, timeout=5)
        with socket.create_connection((endpoint, uri.port), timeout=5) as raw:
            connection.sock = context.wrap_socket(raw, server_hostname=uri.hostname)
            try:
                connection.request("GET", path)
                response = connection.getresponse()
                assert response.status == 200, (path, response.status)
                assert hashlib.sha256(response.read()).hexdigest() == digest, path
            finally:
                connection.close()
# 证书反例直接核验失败类型，不把网络超时当作身份拒绝。
for hostname, trust in (("wrong.padm.test", context), (uri.hostname, ssl.create_default_context())):
    try:
        with socket.create_connection((endpoints[0], uri.port), timeout=5) as raw:
            with trust.wrap_socket(raw, server_hostname=hostname):
                raise AssertionError("错误证书身份被接受")
    except ssl.SSLCertVerificationError:
        pass
print(json.dumps(contents))
PY
    python3 - "${TEST_ROOT}/publication-content.json" "${TEST_ROOT}" <<'PY'
import json
from pathlib import Path
import sys

contents = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
main, group = (contents[key].splitlines() for key in ("main", "group"))
assert len(main) == 2 and len(group) == 1 and main[1] == group[0] and main[0] != group[0]
(root / "links.txt").write_text(main[0] + "\n")
(root / "publication-group.links.txt").write_text(contents["group"])
PY
    cdnPhase=subscription-main
fi
generateClient() {
stage="client-${cdnPhase}"
local alpn
alpn=$(jq -c '.core.protocols[0].fallback_tls.alpn // ["h2","http/1.1"]' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" \
    "${TRANSPORT}" "${PUBLICATION_NAME:-${TEST_NAME}}" "${DOMAIN}" "${APP_PROTOCOL}" "${CDN_ENTRIES}" \
    "${cdnPhase}" "${alpn}" "${PUBLICATION_UUID:-${UUID}}" "${SUBSCRIPTION_PUBLICATION}" <<'PY'
import base64
import ipaddress
import json
import pathlib
import sys
import urllib.parse
import uuid

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
endpoints = json.loads(sys.argv[3])
transport, name, domain, app = sys.argv[4:8]
cdn, cdn_phase = sys.argv[8] == "1", sys.argv[9]
alpn = json.loads(sys.argv[10])
identity, publication = sys.argv[11], sys.argv[12] == "1"
share_port = 35469 if cdn else 35468
assert [ipaddress.ip_address(x).version for x in endpoints] == [4, 6]
servers = endpoints + ["edge.padm.test"] if cdn and cdn_phase == "override" else [domain]
names = [name+"-"+str(index+1) for index in range(len(servers))] if len(servers) > 1 else [name]
assert len(lines) == len(servers)
def parse(line, server=servers[0], label=names[0]):
    if app != "vmess":
        uri = urllib.parse.urlsplit(line)
        pairs = urllib.parse.parse_qsl(uri.query, keep_blank_values=True)
        query = dict(pairs)
        if transport == "tcp":
            expected = ({"encryption":"none","flow":"xtls-rprx-vision","security":"tls","sni":domain,
                         "fp":"chrome"} if app == "vless" else
                        {"peer":domain,"security":"tls","fp":"chrome","sni":domain})
            expected.update(alpn=",".join(alpn),type="tcp")
        elif transport == "grpc":
            expected = ({"encryption":"none","security":"tls","sni":domain} if app == "vless" else
                        {"peer":domain,"fp":"chrome","sni":domain})
            expected.update(type="grpc", alpn="h2",
                            serviceName="subscriptions" if publication else "padm_grpc-1")
        else:
            expected = {"encryption":"none","security":"tls","sni":domain,"type":"ws",
                        "host":domain,"path":"/padmvmessws"}
        assert uri.scheme == app and uri.username == identity
        assert uri.password is None and uri.hostname == server and uri.port == share_port and not uri.path
        assert urllib.parse.unquote(uri.fragment) == label
        assert pairs == list(expected.items())
        assert str(uuid.UUID(uri.username)) == uri.username
        return dict(query,id=uri.username,service=query.get("serviceName"),flow=query.get("flow"),
                    add=uri.hostname,port=str(uri.port),net=query["type"])
    assert line.startswith("vmess://") and "#" not in line and "?" not in line
    payload = line.removeprefix("vmess://")
    raw = base64.b64decode(payload, validate=True)
    assert base64.b64encode(raw).decode() == payload
    value = json.loads(raw)
    assert list(value) == ["v","ps","add","port","id","aid","scy","net","type","host","path","tls","sni"]
    assert raw.decode() == json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    assert value == {"v":"2","ps":label,"add":server,"port":str(share_port),
                     "id":identity,"aid":"0","scy":"auto","net":transport,
                     "type":"none","host":domain,"path":"/padmvmess"+("ws" if transport == "ws" else ""),
                     "tls":"tls","sni":domain}
    assert str(uuid.UUID(value["id"])) == value["id"]
    return value
values = [parse(line, server, label) for line, server, label in zip(lines, servers, names)]
value = values[0]
if app != "vmess":
    sample = urllib.parse.urlsplit(lines[0])
    invalids = []
    fields = ((("encryption","wrong"),("type","tcp"),("host","wrong.test"),("path","/wrong"))
              if transport == "ws" else (("alpn","invalid"),("type","ws")))
    fields += (("sni","wrong.test"),)
    fields += (("flow","wrong"),) if transport == "tcp" and app == "vless" else ()
    fields += (("serviceName","wrong"),) if transport == "grpc" else ()
    for field, bad in fields:
        query = dict(urllib.parse.parse_qsl(sample.query))
        query[field] = bad
        invalids.append(sample._replace(query=urllib.parse.urlencode(query)).geturl())
    invalids.append(sample._replace(query=sample.query+"&sni="+domain).geturl())
else:
    invalids = ["vmess://"+base64.b64encode(json.dumps(dict(value, **{field:bad}),
        separators=(",", ":")).encode()).decode() for field, bad in
        (("aid","1"),("net","tcp"),("tls",""),("path","/wrong"),("scy","none"))]
for uri in invalids:
    try:
        parse(uri)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid transport URI accepted")
config = {"log":{"level":"warn"},"inbounds":[],"outbounds":[],"route":{"rules":[]}}
if cdn:
    config["dns"] = {"servers":[{"type":"local","tag":"local"}]}
    config["route"]["default_domain_resolver"] = "local"
targets = list(zip(values, servers, ("ipv4","ipv6","domain"))) if cdn else [
    (value, endpoint, "ipv"+str(family)) for family, endpoint in zip((4,6), endpoints)]
if cdn and cdn_phase == "clear":
    targets = [(value, domain, "origin-domain")]
variants = (("valid","wrong-auth","wrong-sni","wrong-service") if transport == "grpc" else
            ("valid","wrong-auth","wrong-sni","wrong-host","wrong-path")) if cdn else ("valid","wrong-auth")
probes = []
for variant in variants:
    for value, endpoint, label in targets:
        tag = "vmess-"+label+"-"+variant
        port = 2081+len(config["inbounds"])
        config["inbounds"].append({"type":"socks","tag":"socks-"+tag,"listen":"0.0.0.0","listen_port":port})
        outbound = {"type":app,"tag":tag,"server":value["add"] if cdn else endpoint,
            "server_port":int(value["port"]) if cdn or publication else (35468 if transport == "tcp" else 8443),
            ("password" if app == "trojan" else "uuid"):
                ("22222222-2222-4222-8222-222222222222" if variant == "wrong-auth" else value["id"]),
            "tls":{"enabled":True,"server_name":value["sni"],"certificate_path":"/etc/padm/client/ca.crt"}}
        if transport == "tcp":
            outbound["tls"].update(alpn=value["alpn"].split(","),
                                   utls={"enabled":True,"fingerprint":value["fp"]})
            if app == "vless":
                outbound.update(flow=value["flow"],packet_encoding="xudp")
        elif transport == "grpc":
            outbound["tls"]["alpn"] = [value["alpn"]]
            outbound["transport"] = {"type":"grpc","service_name":value["service"]}
            if app == "vless":
                outbound["packet_encoding"] = "xudp"
        else:
            if app == "vmess":
                outbound.update(security=value["scy"], alter_id=int(value["aid"]))
            else:
                outbound["packet_encoding"] = "xudp"
            outbound["transport"] = dict({"type":value["net"],"path":value["path"]},
                **({"headers":{"Host":value["host"]}} if transport == "ws" else {"host":value["host"]}))
        if variant == "wrong-sni":
            outbound["tls"]["server_name"] = "wrong.padm.test"
        elif variant == "wrong-service":
            outbound["transport"]["service_name"] = "wrong_grpc_service"
        elif variant == "wrong-host":
            if transport == "ws":
                outbound["transport"]["headers"]["Host"] = "wrong.padm.test"
            else:
                outbound["transport"]["host"] = "wrong.padm.test"
        elif variant == "wrong-path":
            outbound["transport"]["path"] = "/wrong"
        config["outbounds"].append(outbound)
        config["route"]["rules"].append({"inbound":["socks-"+tag],"action":"route","outbound":tag})
        probes.append([port, variant, label])
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
pathlib.Path(sys.argv[2]).with_name("probes.json").write_text(json.dumps(probes))
PY
chmod 0640 "${TEST_ROOT}/runtime/client/"{config,probes}.json
chown 0:10001 "${TEST_ROOT}/runtime/client/"{config,probes}.json
tar -cpf - -C "${TEST_ROOT}" runtime/client |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
compose run --rm --no-deps client check -c /etc/padm/client/config.json >/dev/null
}
generateClient
compose up -d --pull never client
client=$(compose ps -q client)
fallbackProbe() {
    [[ "${TRANSPORT}" == tcp ]] || return 0
    local body=${1:-$'padm-fallback-static-proof\n'} endpoint authority option version response actual clientAddress alpn selections proofPath
    local -a options=(--http1.1 --http2)
    fallbackProbeCalls=$(( ${fallbackProbeCalls:-0} + 1 ))
    if [[ "${ALPN_ORDERS}" == 1 ]]; then
        alpn=$(jq -c '.core.protocols[0].fallback_tls.alpn // ["h2","http/1.1"]' \
            "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")
        selections=$(docker run --rm --init -i --pull=never --read-only --cap-drop ALL --user 10001:10001 \
            --network "${project}" --label "io.padm.test=${project}" \
            --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
            --entrypoint python3 "${OPS_ID}" - "${addresses}" "${alpn}" "${DOMAIN}" <<'PY'
import json
import socket
import ssl
import sys

addresses, allowed, domain = json.loads(sys.argv[1]), json.loads(sys.argv[2]), sys.argv[3]
results = {}
for endpoint in addresses:
    results[endpoint] = {}
    for label, offered in (("http1", ["http/1.1"]), ("http2", ["h2", "http/1.1"]),
                           ("h2_only", ["h2"]), ("configured", allowed)):
        context = ssl.create_default_context(cafile="/etc/padm/client/ca.crt")
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.set_alpn_protocols(offered)
        try:
            with socket.create_connection((endpoint, 35468), timeout=5) as connection:
                with context.wrap_socket(connection, server_hostname=domain) as secure:
                    selected = secure.selected_alpn_protocol()
        except ssl.SSLCertVerificationError:
            raise
        except ssl.SSLError:
            assert label == "h2_only" and "h2" not in allowed
            selected = "rejected"
        common = set(offered).intersection(allowed)
        assert (selected in common if common else selected in (None, "rejected")), (
            endpoint, label, offered, allowed, selected)
        results[endpoint][label] = selected
print(json.dumps(results, separators=(",", ":")))
PY
)
        if jq -e 'index("h2") != null' <<<"${alpn}" >/dev/null; then
            options+=(--http2-prior-knowledge)
        fi
    fi
    while IFS= read -r endpoint; do
        authority=${endpoint}; [[ "${endpoint}" != *:* ]] || authority="[${endpoint}]"
        for option in "${options[@]}"; do
            proofPath="/?padm-proxy-proof-${cdnPhase}-${option#--}-${fallbackProbeCalls}"
            version=1.1; [[ "${option}" != --http2 ]] || version=2
            if [[ "${ALPN_ORDERS}" == 1 ]]; then
                version=$(jq -r --arg endpoint "${endpoint}" --arg option "${option}" '
                  .[$endpoint][if $option == "--http1.1" then "http1"
                    elif $option == "--http2" then "http2" else "h2_only" end] |
                    if . == "h2" then "2" elif . == "http/1.1" then "1.1" else error("no HTTP ALPN") end
                ' <<<"${selections}")
            fi
            response=$(docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
                --network "${project}" --label "io.padm.test=${project}" \
                --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
                --entrypoint curl "${CURL_ID}" --fail --silent --show-error --noproxy '*' \
                --connect-timeout 2 --max-time 5 "${option}" --cacert /etc/padm/client/ca.crt \
                --resolve "${DOMAIN}:35468:${authority}" --write-out '%{http_version}\n%{local_ip}' \
                "https://${DOMAIN}:35468${proofPath}")
            clientAddress=${response##*$'\n'}
            response=${response%$'\n'*}
            [[ "${response}" == "${body}${version}" ]] || {
                printf 'fallback content or ALPN mismatch: endpoint=%s option=%s response=%s\n' \
                    "${endpoint}" "${option}" "${response}" >&2
                return 1
            }
            jq -e --arg address "${clientAddress}" 'index($address) == null' <<<"${addresses}" >/dev/null
            compose exec -T nginx cat /var/log/nginx/access.log |
                awk -v address="${clientAddress}" -v path="${proofPath}" '$1 == address && index($0,"GET " path " ") {found=1}
                  END {exit !found}'
            response=$(docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
                --network "${project}" --label "io.padm.test=${project}" \
                --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
                --entrypoint curl "${CURL_ID}" --silent --show-error --noproxy '*' \
                --connect-timeout 2 --max-time 5 "${option}" --cacert /etc/padm/client/ca.crt \
                --resolve "${DOMAIN}:35468:${authority}" --output /dev/null \
                --write-out '%{http_code} %{http_version}' "https://${DOMAIN}:35468/missing-padm-proof")
            [[ "${response}" == "404 ${version}" ]]
        done
        actual=0
        docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
            --network "${project}" --label "io.padm.test=${project}" --entrypoint curl "${CURL_ID}" \
            --fail --silent --show-error --noproxy '*' --connect-timeout 2 --max-time 5 --http1.1 \
            --resolve "${DOMAIN}:35468:${authority}" "https://${DOMAIN}:35468/" \
            >"${TEST_ROOT}/untrusted-fallback.out" 2>"${TEST_ROOT}/untrusted-fallback.err" || actual=$?
        [[ "${actual}" == 60 && ! -s "${TEST_ROOT}/untrusted-fallback.out" ]]
        actual=0
        docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
            --network "${project}" --label "io.padm.test=${project}" \
            --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
            --entrypoint curl "${CURL_ID}" --fail --silent --show-error --noproxy '*' \
            --connect-timeout 2 --max-time 5 --http1.1 --cacert /etc/padm/client/ca.crt \
            --resolve "wrong.padm.test:35468:${authority}" "https://wrong.padm.test:35468/" \
            >"${TEST_ROOT}/wrong-sni-fallback.out" 2>"${TEST_ROOT}/wrong-sni-fallback.err" || actual=$?
        [[ "${actual}" != 0 && ! -s "${TEST_ROOT}/wrong-sni-fallback.out" ]]
    done < <(jq -r '.[]' <<<"${addresses}")
    if [[ "${ALPN_ORDERS}" == 1 ]]; then
        printf 'docker-%s-fallback-ok: alpn=%s selected=%s family=ipv4,ipv6 strict-ca-sni missing=404 proxy-source=client\n' \
            "${TEST_NAME}" "${alpn}" "${selections}"
    else
        printf 'docker-%s-fallback-ok: alpn=h2,http/1.1 family=ipv4,ipv6 strict-ca-sni missing=404 proxy-source=client\n' "${TEST_NAME}"
    fi
}
probe() {
    docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
        --network "${project}" --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
        --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import ipaddress
import json
import pathlib
import socket
import ssl
import struct
import sys
import time
import urllib.request

phase = sys.argv[1]
test_name, core, transport_name = sys.argv[2:5]
assert phase in ("allow","deny")
proof = b"padm-vmess-real-proof\n"
class ProbeRejected(Exception):
    pass
def read(sock, size):
    data = b""
    while len(data) < size:
        part = sock.recv(size-len(data))
        if not part: raise EOFError()
        data += part
    return data
def address(sock, atyp):
    if atyp == 1: return socket.inet_ntop(socket.AF_INET, read(sock, 4))
    if atyp == 4: return socket.inet_ntop(socket.AF_INET6, read(sock, 16))
    if atyp == 3: return read(sock, read(sock, 1)[0]).decode()
    raise AssertionError("invalid SOCKS address")
def connect(port, command):
    deadline = time.monotonic()+10
    while True:
        try:
            sock = socket.create_connection(("client",port),timeout=0.2)
            break
        except OSError as error:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"client unavailable: port={port} command={command}: {error}") from error
            time.sleep(0.05)
    sock.settimeout(4)
    try:
        try:
            sock.sendall(b"\x05\x01\x00")
            assert read(sock,2) == b"\x05\x00"
        except (OSError, EOFError) as error:
            raise RuntimeError(f"SOCKS greeting failed: port={port} command={command}: {error}") from error
        name = b"origin"
        destination = b"\x03"+bytes([len(name)])+name+struct.pack("!H",8088) if command == 1 else b"\x01"+b"\x00"*6
        try:
            sock.sendall(b"\x05"+bytes([command])+b"\x00"+destination)
            header = read(sock,4)
            assert header[0] == 5 and header[2] == 0
            if header[1] != 0:
                assert 1 <= header[1] <= 8
                raise ProbeRejected(f"socks-rep-{header[1]}")
            host = address(sock,header[3])
            relay_port = struct.unpack("!H",read(sock,2))[0]
        except (EOFError, ConnectionResetError) as error:
            raise ProbeRejected(f"socks-reply-{type(error).__name__}") from error
        except TimeoutError as error:
            raise RuntimeError(f"SOCKS reply timeout: port={port} command={command}") from error
        return sock,host,relay_port
    except BaseException:
        sock.close()
        raise
def tcp(port):
    sock,_,_ = connect(port,1)
    with sock:
        try:
            sock.sendall(b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
            response = b""
            while True:
                data = sock.recv(4096)
                if not data: break
                response += data
        except ConnectionResetError as error:
            raise ProbeRejected("upstream-reset") from error
        except TimeoutError as error:
            raise RuntimeError(f"TCP proof timeout: port={port}") from error
    if not response:
        raise ProbeRejected("upstream-eof")
    head,body = response.split(b"\r\n\r\n",1)
    assert (head.startswith(b"HTTP/1.0 200") or head.startswith(b"HTTP/1.1 200")) and body == proof
    return True
def udp(port):
    control,host,relay_port = connect(port,3)
    with control:
        if ipaddress.ip_address(host).is_unspecified: host = control.getpeername()[0]
        family = socket.AF_INET6 if ipaddress.ip_address(host).version == 6 else socket.AF_INET
        with socket.socket(family,socket.SOCK_DGRAM) as sock:
            sock.settimeout(4)
            sock.bind(("::" if family == socket.AF_INET6 else "0.0.0.0",0))
            target = socket.inet_aton(socket.gethostbyname("origin"))
            payload = proof+str(port).encode()+b"-"+phase.encode()
            sock.sendto(b"\x00\x00\x00\x01"+target+struct.pack("!H",8089)+payload,(host,relay_port))
            response,_ = sock.recvfrom(65535)
            assert response[:3] == b"\x00\x00\x00"
            offset = {1:8,4:20}.get(response[3])
            if response[3] == 3: offset = 5+response[4]
            assert offset is not None
            assert response[offset+2:] == payload
            return True
def counts():
    return json.loads(urllib.request.urlopen("http://origin:8088/counts",timeout=5).read())
def check_tcp(item):
    port,variant,label = item
    expected = phase == "allow" and variant == "valid"
    try:
        accepted, reason = tcp(port), "proof"
    except ProbeRejected as error:
        accepted, reason = False, str(error)
    assert accepted == expected,(phase,port,variant,label,"tcp",accepted,reason)
    return port,(accepted,reason)
def check_udp(item):
    port,variant,label = item
    expected = phase == "allow" and variant == "valid"
    try:
        accepted, reason = udp(port), "proof"
    except ProbeRejected as error:
        accepted, reason = False, str(error)
    except TimeoutError:
        accepted, reason = False, "no-response"
    assert accepted == expected,(phase,port,variant,label,"udp",accepted,reason)
    if not expected:
        assert tcp_results[port][0] is False, (port,"UDP silence without explicit TCP rejection")
    return str(port)+"/"+variant+"/"+label+"/tcp="+tcp_results[port][1]+"/udp="+reason
before = counts()
probes = json.loads(pathlib.Path("/etc/padm/client/probes.json").read_text())
if transport_name == "grpc":
    config = json.loads(pathlib.Path("/etc/padm/client/config.json").read_text())
    assert len(probes) == len(config["outbounds"])
    selections, rejections = [], []
    for (_,variant,label), outbound in zip(probes,config["outbounds"]):
        if variant not in ("valid","wrong-sni"):
            continue
        tls = outbound["tls"]
        assert tls["enabled"] is True and tls["alpn"] == ["h2"] and tls.get("insecure",False) is False
        if variant == "wrong-sni":
            assert tls["server_name"] == "wrong.padm.test"
        context = ssl.create_default_context(cafile=tls["certificate_path"])
        assert context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED
        context.set_alpn_protocols(tls["alpn"])
        try:
            with socket.create_connection((outbound["server"],outbound["server_port"]),timeout=4) as raw:
                with context.wrap_socket(raw,server_hostname=tls["server_name"]) as secured:
                    selected = secured.selected_alpn_protocol()
        except ssl.SSLCertVerificationError as error:
            assert variant == "wrong-sni" and error.verify_code == 62, (label,variant,error)
            rejections.append("wrong-sni/"+label+"=hostname-mismatch")
        else:
            assert variant == "valid", (label,"wrong SNI handshake succeeded")
            assert selected == "h2", (label,selected)
            selections.append(label+"="+selected)
    print("docker-"+test_name+"-tls-observed: share-phase="+sys.argv[5]+
          " strict-ca-sni=verified alpn="+",".join(selections))
    if rejections:
        print("docker-"+test_name+"-tls-rejected: share-phase="+sys.argv[5]+" "+",".join(rejections))
    # SNI 用明确证书错误证明，与认证和 serviceName 的 SOCKS 拒绝分开记录。
    probes = [item for item in probes if item[1] != "wrong-sni"]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    tcp_results = dict(pool.map(check_tcp,probes))
    results = list(pool.map(check_udp,probes))
    recovery = [item for item in probes if item[1] == "valid"] if phase == "allow" else []
    recovered_tcp = dict(pool.map(check_tcp,recovery))
    recovered_udp = list(pool.map(check_udp,recovery))
    assert all(accepted for accepted,_ in recovered_tcp.values())
after = counts()
expected_delta = 2*sum(variant == "valid" for _,variant,_ in probes) if phase == "allow" else 0
assert {key:after[key]-before[key] for key in before} == {"tcp":expected_delta,"udp":expected_delta}
print("docker-"+test_name+"-probe-ok: core="+core+" phase="+phase+" source=protocol-links tls="+
      (core if transport_name == "tcp" else "nginx")+"-"+
      transport_name+" share-phase="+sys.argv[5]+" recovery="+str(len(recovered_udp))+
      " socks="+",".join(results))
' "$1" "${TEST_NAME}" "${CORE}" "${TRANSPORT}" "${cdnPhase}"
    docker inspect "$(compose ps -q "${CORE}")" "$(compose ps -q nginx)" "$(compose ps -q client)" |
        jq -e --arg core "${CORE}" 'all(.[]; .State.Running) and
          all(.[] | select(.Config.Labels["com.docker.compose.service"] == $core); .State.Health.Status == "healthy")' >/dev/null
}
if [[ "${SUBSCRIPTION_PUBLICATION}" == 1 ]]; then
    probe allow
    compose stop client
    cp "${TEST_ROOT}/publication-group.links.txt" "${TEST_ROOT}/links.txt"
    PUBLICATION_UUID=33333333-3333-4333-8333-333333333333
    [[ "${APP_PROTOCOL}" != trojan ]] || PUBLICATION_UUID=44444444-4444-4444-8444-444444444444
    PUBLICATION_NAME="${TEST_NAME}-independent"
    cdnPhase=subscription-group
    generateClient
    compose up -d --pull never client
    probe allow
    printf 'docker-subscription-publication-real-ok: protocol=%s core=%s tls=strict-ca-hostname main-group=downloaded token404=ipv4,ipv6 client=tcp-udp effective-port=35468\n' \
        "${PROTOCOL}" "${CORE}"
    [[ -z "${SUBSCRIPTION_SITE_TEMPLATE}" ]] ||
        printf 'docker-subscription-site-real-ok: template=%s core=%s website=all-local-resources family=ipv4,ipv6 base-cli=content,links\n' \
            "${SUBSCRIPTION_SITE_TEMPLATE}" "${CORE}"
    exit 0
fi
if [[ "${ALPN_ORDERS}" == 1 ]]; then
    fallbackProbe '<!doctype html><title>Welcome</title><h1>Welcome</h1>'
    printf 'padm-fallback-static-proof\n' >"${PADM_DOCKER_INSTALL_DIR}/data/static/index.html"
    chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/data/static/index.html"
    chown 0:10001 "${PADM_DOCKER_INSTALL_DIR}/data/static/index.html"
    cp -a -- "${PADM_DOCKER_INSTALL_DIR}/data/static/." "${TEST_ROOT}/runtime/data/static/"
    tar -cpf - -C "${TEST_ROOT}" runtime/data/static |
        docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
    nginxState=$(docker inspect "$(compose ps -q nginx)" | jq -c '.[0] | {id:.Id,started_at:.State.StartedAt}')
    coreState=$(docker inspect "$(compose ps -q "${CORE}")" | jq -c '.[0] | {id:.Id}')
    for cdnPhase in reverse http1 recommended; do
        stage="alpn-${cdnPhase}"
        case "${cdnPhase}" in
        reverse) currentAlpn='["http/1.1","h2"]' ;;
        http1) currentAlpn='["http/1.1"]' ;;
        recommended) currentAlpn='["h2","http/1.1"]' ;;
        esac
        request="${TEST_ROOT}/alpn-${cdnPhase}.json"
        jq --argjson alpn "${currentAlpn}" '.core.protocols[0].fallback_tls.alpn = $alpn' \
            "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${request}"
        chmod 0600 "${request}"
        dockerConfigureSpecValidate "${request}"
        dockerCreateConfigurationCandidate
        dockerGenerateCandidate "${request}" "${DOCKER_CONFIG_CANDIDATE}"
        candidate=${DOCKER_CONFIG_CANDIDATE}
        jq -e --argjson alpn "${currentAlpn}" '
          .core.protocols[0].fallback_tls.alpn == $alpn
        ' "${candidate}/config/spec.json" >/dev/null
        cmp -s <(jq -S 'del(.core.protocols[0].fallback_tls.alpn)' "${TEST_ROOT}/spec.json") \
            <(jq -S 'del(.core.protocols[0].fallback_tls.alpn)' "${candidate}/config/spec.json")
        for file in config.json users.base; do
            jq -e --argjson alpn "${currentAlpn}" '
              [.inbounds[] | select(.tag == "entry-vmess") | .streamSettings.tlsSettings.alpn] == [$alpn]
            ' "${candidate}/config/${CORE}/${file}" >/dev/null
            cmp -s <(jq -S '(.inbounds[] | select(.tag == "entry-vmess") |
                .streamSettings.tlsSettings) |= del(.alpn)' "${TEST_ROOT}/runtime/config/${CORE}/${file}") \
                <(jq -S '(.inbounds[] | select(.tag == "entry-vmess") |
                .streamSettings.tlsSettings) |= del(.alpn)' "${candidate}/config/${CORE}/${file}")
        done
        for file in compose.json deployment.json images.runtime.env; do
            target="${PADM_DOCKER_INSTALL_DIR}/${file}"
            [[ "${file}" != images.runtime.env ]] || target="${PADM_DOCKER_INSTALL_DIR}/images.env"
            if [[ "${file}" == deployment.json ]]; then
                # 候选记录当前 manifest 来源；只有此字段按生成器合同更新。
                jq -e --slurpfile previous "${target}" '
                  .previous_manifest_sha256 == $previous[0].manifest.sha256
                ' "${candidate}/${file}" >/dev/null &&
                    cmp -s <(jq -S 'del(.previous_manifest_sha256)' "${target}") \
                        <(jq -S 'del(.previous_manifest_sha256)' "${candidate}/${file}")
            else
                cmp -s -- "${target}" "${candidate}/${file}"
            fi || {
                printf 'alpn preserved file mismatch: phase=%s file=%s\n' "${cdnPhase}" "${file}" >&2
                exit 1
            }
        done
        for directory in config/nginx secrets data/static; do
            diff -rq -- "${PADM_DOCKER_INSTALL_DIR}/${directory}" "${candidate}/${directory}" >/dev/null
        done
        compose stop client
        # 事务合同已有定向覆盖；这里只适配隔离卷，真实验证候选配置与链接。
        cp -a -- "${candidate}/config/${CORE}/." "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/"
        cp -a -- "${candidate}/config/spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        cp -a -- "${candidate}/config/${CORE}/." "${TEST_ROOT}/runtime/config/${CORE}/"
        dockerCleanupConfigurationCandidate
        tar -cpf - -C "${TEST_ROOT}" "runtime/config/${CORE}" |
            docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
                --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
        compose run --rm --no-deps "${CORE}" -test -config /etc/padm/xray/config.json >/dev/null
        compose restart "${CORE}"
        compose up -d --pull never --wait --wait-timeout 60 "${CORE}"
        dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
        generateClient
        compose up -d --pull never client
        fallbackProbe
        probe allow
        [[ "$(docker inspect "$(compose ps -q nginx)" | jq -c '.[0] | {id:.Id,started_at:.State.StartedAt}')" == "${nginxState}" ]]
        [[ "$(docker inspect "$(compose ps -q "${CORE}")" | jq -c '.[0] | {id:.Id}')" == "${coreState}" ]]
        [[ "$(docker inspect --format '{{.State.Health.Status}}' "$(compose ps -q "${CORE}")")" == healthy ]]
        printf 'docker-alpn-orders-phase-ok: protocol=%s core=%s phase=%s alpn=%s spec-core-users-links=consistent identity-fallback-nginx-compose-tls-site=unchanged\n' \
            "${PROTOCOL}" "${CORE}" "${cdnPhase}" "${currentAlpn}"
    done
    printf 'docker-alpn-orders-real-ok: protocol=%s core=%s phases=reverse,http1,recommended family=ipv4,ipv6 auth=deny tcp-udp=allow strict-ca-sni selected=observed\n' \
        "${PROTOCOL}" "${CORE}"
    exit 0
fi
if [[ "${CDN_ENTRIES}" == 1 ]]; then
    serverStates=$(docker inspect "$(compose ps -q "${CORE}")" "$(compose ps -q nginx)" |
        jq -c '[.[] | {id:.Id,started_at:.State.StartedAt}]')
    probe allow
    compose stop client
    cdnPhase=clear
    cdnRenderConfiguration "${cdnPhase}"
    generateClient
    compose up -d --pull never client
    probe allow
    [[ "$(docker inspect "$(compose ps -q "${CORE}")" "$(compose ps -q nginx)" |
        jq -c '[.[] | {id:.Id,started_at:.State.StartedAt}]')" == "${serverStates}" ]]
    negatives=auth-sni-host-path=deny
    [[ "${TRANSPORT}" != grpc ]] || negatives='auth-service=socks-deny sni=client-tls-hostname-mismatch'
    printf 'docker-cdn-entries-real-ok: protocol=%s core=%s addresses=ipv4,ipv6,domain clear=original-domain effective-port=35469 %s servers=unchanged\n' \
        "${PROTOCOL}" "${CORE}" "${negatives}"
    exit 0
fi
# 只适配命名卷与隔离网络，额度/验证/重启/恢复仍走生产函数。
dockerComposeRun() {
    local action=$1
    shift
    if [[ "${action}" == run || "${action}" == restart ]]; then
        cp -a "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/." "${TEST_ROOT}/runtime/config/${CORE}/"
        tar -cpf - -C "${TEST_ROOT}" "runtime/config/${CORE}" |
            docker run --rm --init -i --pull=never --label "io.padm.test=${project}" --user 0 \
                --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
    fi
    case "${action}" in up) compose "${action}" --pull never "$@" ;; *) compose "${action}" "$@" ;; esac
}
dockerTrafficContainerState() {
    local container
    container=$(compose ps -q "$1")
    [[ "${container}" =~ ^[a-f0-9]{12,64}$ ]]
    docker inspect "${container}" | jq -ce --arg core "$1" --arg project "${project}" '
      .[0] | select(.State.Running and .State.Pid > 1 and
        .Config.Labels["com.docker.compose.project"] == $project and
        .Config.Labels["com.docker.compose.service"] == $core) |
      {id:.Id,started_at:.State.StartedAt,pid:.State.Pid}'
}
# Docker Desktop 的宿主 PID 不可 nsenter；只替换 sing-box 查询的隔离网络，复用生产解析器。
if [[ "${CORE}" == sing-box ]]; then
    dockerTrafficQuery() (
        [[ "$1" == sing-box ]]
        local container
        container=$(compose ps -q sing-box)
        printf '\000\000\000\000\006\032\004user' >"${TEST_ROOT}/request.bin"
        docker run --rm --init -i --pull=never --read-only --cap-drop ALL \
            --network "container:${container}" --label "io.padm.test=${project}" --entrypoint curl "${CURL_ID}" \
            -fsS --http2-prior-knowledge --noproxy '*' --connect-timeout 2 --max-time 5 -D /dev/stderr \
            -H 'Content-Type: application/grpc' -H 'TE: trailers' --data-binary @- --output - \
            http://127.0.0.1:10087/v2ray.core.app.stats.command.StatsService/QueryStats \
            <"${TEST_ROOT}/request.bin" >"${TEST_ROOT}/response.bin" 2>"${TEST_ROOT}/headers" || {
            cat "${TEST_ROOT}/headers" >&2
            exit 1
        }
        awk '{sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1} END {exit !ok}' "${TEST_ROOT}/headers"
        singBoxGrpcResponseToStatsJson "${TEST_ROOT}/response.bin"
    )
fi
if [[ "${TRANSPORT}" == tcp ]]; then
    fallbackProbe '<!doctype html><title>Welcome</title><h1>Welcome</h1>'
    printf 'padm-fallback-static-proof\n' >"${TEST_ROOT}/runtime/data/static/index.html"
    chmod 0640 "${TEST_ROOT}/runtime/data/static/index.html"
    chown 0:10001 "${TEST_ROOT}/runtime/data/static/index.html"
    tar -cpf - -C "${TEST_ROOT}" runtime/data/static |
        docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
fi
fallbackProbe
probe allow
stats=$(dockerTrafficQuery "${CORE}" 0)
jq -e --arg uuid "${UUID}" '
  def positive($direction):
    [.stat[]? | select(.name == ("user>>>"+$uuid+">>>traffic>>>"+$direction)) | (.value|tonumber)] |
    length == 1 and .[0] > 0;
  positive("uplink") and positive("downlink")' <<<"${stats}" >/dev/null
printf 'docker-%s-stats-ok: core=%s identity=%s counters=%s\n' "${TEST_NAME}" "${CORE}" "${UUID}" "${stats}"
dockerTrafficSetLimit "${UUID}" 1
jq -e --arg core "${CORE}" --arg app "${APP_PROTOCOL}" 'if $core == "xray" then
  all(.inbounds[] | select(.protocol == $app); .settings.clients == [])
  else all(.inbounds[] | select(.type == "vmess"); .users == []) end' \
    "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/config.json" >/dev/null
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base")" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe deny
fallbackProbe
dockerTrafficSetLimit "${UUID}" 0
jq -e --arg uuid "${UUID}" --arg core "${CORE}" --arg app "${APP_PROTOCOL}" --arg transport "${TRANSPORT}" '
  if $core == "xray" then any(.inbounds[]; .protocol == $app and
    .settings.clients == (if $app == "trojan" then [{password:$uuid,email:$uuid}]
      elif $app == "vless" then [{id:$uuid,email:$uuid} +
        if $transport == "tcp" then {flow:"xtls-rprx-vision"} else {} end]
      else [{id:$uuid,email:$uuid,alterId:0}] end))
  else any(.inbounds[]; .type == "vmess" and .users == [{uuid:$uuid,name:$uuid,alterId:0}]) end' \
    "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/config.json" >/dev/null
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base")" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe allow
fallbackProbe
dockerTrafficSnapshot
jq -e --arg uuid "${UUID}" --arg core "${CORE}" '(.accounts | keys) == [$uuid] and
  (.accounts[$uuid] | .upload > 0 and .download > 0 and .limit_bytes == 0 and (.baseline | keys) == [$core])' \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" >/dev/null
[[ "$(docker inspect --format '{{.State.Health.Status}}' "$(compose ps -q "${CORE}")")" == healthy ]]
tlsService=nginx
[[ "${TRANSPORT}" != tcp ]] || tlsService=${CORE}
printf 'docker-%s-ok: core=%s tls=%s-%s quota=deny-restore same-client family=ipv4,ipv6 xray=%s sing-box=%s ops=%s nginx=%s\n' \
    "${TEST_NAME}" "${CORE}" "${tlsService}" "${TRANSPORT}" "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${NGINX_ID}"
