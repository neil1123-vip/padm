#!/usr/bin/env bash
set -euo pipefail
umask 077

# 只验收隔离项目的真实流量；本地镜像夹具不是生产发布验签或公网验收。
[[ "$#" == 3 ]] || {
    printf 'usage: reality-stream-real.sh <local-xray> <local-nginx> <local-ops>\n' >&2
    exit 2
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
for tool in docker jq python3 openssl sha256sum tar; do command -v "${tool}" >/dev/null; done
XRAY_ID=$(docker image inspect --format '{{.Id}}' "$1")
NGINX_ID=$(docker image inspect --format '{{.Id}}' "$2")
OPS_ID=$(docker image inspect --format '{{.Id}}' "$3")
for image in "${XRAY_ID}" "${NGINX_ID}" "${OPS_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-reality-stream-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-reality-stream-real.XXXXXX")
cleanup() {
    local status=$? ids resource name cleanupFailed=0
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
        docker rm -f ${ids} >/dev/null || cleanupFailed=1
    fi
    for resource in network volume; do
        name=${project}; [[ "${resource}" != volume ]] || name=${volume}
        if docker "${resource}" inspect "${name}" >/dev/null 2>&1; then
            if docker "${resource}" inspect "${name}" |
                jq -e --arg project "${project}" '.[0].Labels["io.padm.test"] == $project' >/dev/null; then
                docker "${resource}" rm "${name}" >/dev/null || cleanupFailed=1
            else cleanupFailed=1; fi
        fi
    done
    if [[ "${cleanupFailed}" == 0 ]]; then rm -rf -- "${TEST_ROOT}"
    else printf 'cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2; status=1; fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker volume create --label "io.padm.test=${project}" "${volume}" >/dev/null
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
dockerCleanupStagedBundle
DOMAIN=website.padm.test
TARGET=www.debian.org
UUID=11111111-1111-4111-8111-111111111111
PUBLIC_KEY=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
PRIVATE_KEY=dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo
TLS_DIR="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
mkdir -p "${TEST_ROOT}/certs" "${TLS_DIR}" "${TEST_ROOT}/runtime/"{client,origin}
chmod 750 "${TEST_ROOT}/runtime"
chown 0:10001 "${TEST_ROOT}/runtime"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-stream-test-ca \
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
BASE="${TEST_ROOT}/base.json"
jq -n --arg uuid "${UUID}" --arg public "${PUBLIC_KEY}" --arg private "${PRIVATE_KEY}" \
    --arg domain "${DOMAIN}" --arg target "${TARGET}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  def reality: {server_name:$target,target_host:$target,target_port:443,
    private_key:$private,public_key:$public,short_id:"6ba85179e30d4fc2"};
  def entry($id;$listener;$port): {id:$id,listener_id:$listener,core:"xray",
    server:"proxy.padm.test",public_port:$port,address_families:["ipv4","ipv6"],
    name:$listener,uuid:$uuid};
  {schema_version:3,release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
    core:{type:"xray",secondary_type:null,protocols:[
      (entry(1;"entry-vision";35441) + {reality:reality}),
      (entry(2;"entry-xhttp";35442) + {reality:reality,
        xhttp:{path:"/stream-xhttp",host:$target,mode:"auto"}}),
      (entry(21;"entry-website";35443) + {websocket:{domain:$domain,path:"streamws",backend_port:31297,tls_port:8443}})]},
    tls:{domain:$domain},subscription:{enabled:false,token:"0123456789abcdef"},
    images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
    host_integrations:[]}
' >"${BASE}"
chmod 600 "${BASE}"
jq -n --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
    name:"stream-account",upload:11,download:17,limit_bytes:1000000,
    baseline:{xray:{upload:{generation:"before-stream",value:7}}}}}}' | dockerTrafficWriteState
trafficHash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
COMPOSE="${TEST_ROOT}/compose.json"
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"; }

renderPhase() {
    local phase=$1 listener=$2 candidate hash
    local -a recreate=(--force-recreate)
    [[ -z "${handoffPort:-}" ]] || recreate=()
    if [[ "${listener}" == off ]]; then
        cp -- "${BASE}" "${SPEC}"
    else
        jq --arg listener "${listener}" '.reality_stream={
            listener_id:$listener,website_listener_id:"entry-website"}' "${BASE}" >"${SPEC}"
    fi
    chmod 600 "${SPEC}"
    dockerConfigureSpecValidate "${SPEC}"
    jq -e --slurpfile base "${BASE}" 'del(.reality_stream) == $base[0]' "${SPEC}" >/dev/null
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${SPEC}" "${candidate}"
    if [[ "${listener}" != off ]]; then
        jq -e '.services.nginx.ports == ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"]' \
            "${candidate}/compose.json" >/dev/null
        jq -e --arg listener "${listener}" '[.listeners[] | select(.listener_id == $listener)] |
            length == 1 and .[0].service == "nginx" and .[0].public_port == 443 and .[0].container_port == 15443' \
            "${candidate}/deployment.json" >/dev/null
    fi
    for path in config data logs secrets; do
        cp -a "${candidate}/${path}/." "${PADM_DOCKER_INSTALL_DIR}/${path}/"
    done
    if [[ "${listener}" == off ]]; then
        rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream"
    fi
    cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
    cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerCleanupConfigurationCandidate
    dockerEnsureRuntimeDataPermissions
    [[ "${trafficHash}" == "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" ]]
    hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base")
    if [[ -f "${TEST_ROOT}/core-before.sha256" ]]; then
        [[ "${hash}" == "$(<"${TEST_ROOT}/core-before.sha256")" ]]
    else printf '%s\n' "${hash}" >"${TEST_ROOT}/core-before.sha256"; fi
    dockerTrafficAccounts xray >"${TEST_ROOT}/accounts-${phase}.json"
    if [[ -f "${TEST_ROOT}/accounts-before.json" ]]; then
        cmp "${TEST_ROOT}/accounts-before.json" "${TEST_ROOT}/accounts-${phase}.json"
    else cp "${TEST_ROOT}/accounts-${phase}.json" "${TEST_ROOT}/accounts-before.json"; fi
    dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
    [[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 3 ]]
    if [[ "${listener}" == off ]]; then
        rm -rf -- "${TEST_ROOT}/runtime/config/nginx/stream"
    fi
    cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/logs" "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
    # 网站内容仅注入运行夹具，受管配置不变；静态网站功能另阶段实现。
    sed -i '/    ssl_protocols TLSv1.2 TLSv1.3;/a\    location = /website-proof { default_type text/plain; return 200 "padm-stream-website-proof\\n"; }' \
        "${TEST_ROOT}/runtime/config/nginx/default.conf"
    python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${listener}" "${BASE}" <<'PY'
import json
import pathlib
import sys
import urllib.parse

outbounds, inbounds, rules = [], [], []
selected = sys.argv[3]
original = {entry["listener_id"]:entry["public_port"]
            for entry in json.loads(pathlib.Path(sys.argv[4]).read_text())["core"]["protocols"]}
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    uri = urllib.parse.urlsplit(line)
    q = {k:v[0] for k,v in urllib.parse.parse_qs(uri.query).items()}
    if q.get("security") != "reality":
        continue
    listener = "entry-vision" if q["type"] == "tcp" else "entry-xhttp"
    port = 2081 if listener == "entry-vision" else 2082
    assert uri.port == (443 if listener == selected else original[listener])
    settings = {"network":q["type"],"security":"reality","realitySettings":{
        "serverName":q["sni"],"fingerprint":q["fp"],"publicKey":q["pbk"],"shortId":q["sid"]}}
    user = {"id":uri.username,"encryption":"none"}
    if q["type"] == "tcp":
        assert q["flow"] == "xtls-rprx-vision"
        user["flow"] = q["flow"]
    else:
        settings["xhttpSettings"] = {"path":q["path"],"host":q["host"],"mode":q["mode"]}
    # 仅把 URI 的公网端点投影到本次隔离服务，不修改协议参数。
    address = "nginx" if listener == selected else "xray"
    server_port = 15443 if listener == selected else uri.port
    inbounds.append({"tag":listener,"listen":"0.0.0.0","port":port,"protocol":"socks",
        "settings":{"auth":"noauth","udp":False}})
    outbounds.append({"tag":listener,"protocol":"vless","settings":{"vnext":[{
        "address":address,"port":server_port,"users":[user]}]},"streamSettings":settings})
    rules.append({"type":"field","inboundTag":[listener],"outboundTag":listener})
pathlib.Path(sys.argv[2]).write_text(json.dumps({"log":{"loglevel":"warning"},
    "inbounds":inbounds,"outbounds":outbounds,"routing":{"rules":rules}}))
PY
    cp "${TEST_ROOT}/certs/ca.crt" "${TEST_ROOT}/runtime/client/ca.crt"
    printf 'padm-stream-proxy-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
    chown -R 0:10001 "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
    find "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin" -type d -exec chmod 750 {} +
    find "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin" -type f -exec chmod 640 {} +
    tar -cpf - -C "${TEST_ROOT}" runtime |
        docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
    jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" \
        --arg nginx "${NGINX_ID}" --arg ops "${OPS_ID}" \
        --arg handoffPort "${handoffPort:-}" --arg listener "${listener}" '
      .name = $project | .networks.default.name = $project |
      .networks.default.labels["io.padm.test"] = $project |
      del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
      .services |= with_entries(
        .value.image = (if .key == "xray" then $xray else $nginx end) |
        .value.ports = [] | .value.init = true | .value.pull_policy = "never" |
        .value.labels["io.padm.test"] = $project |
        .value.volumes |= map(.source as $source | .type = "volume" | .source = "files" |
          .volume={nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} | del(.bind))) |
      .services.origin = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
        labels:{"io.padm.test":$project},
        entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
        volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
          volume:{nocopy:true,subpath:"runtime/origin"}}]} |
      .services.client = {image:$xray,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
        labels:{"io.padm.test":$project},healthcheck:{disable:true},
        command:["run","-c","/etc/padm/client/config.json"],
        volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
          volume:{nocopy:true,subpath:"runtime/client"}}]} |
      if $handoffPort != "" then
        .services[if $listener == "off" then "xray" else "nginx" end].ports = [{
          host_ip:"127.0.0.1",published:(if $handoffPort == "auto" then "0" else $handoffPort end),
          target:(if $listener == "off" then 443 else 15443 end),protocol:"tcp"}]
      else . end
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
    compose config --format json | jq -e --arg port "${handoffPort:-}" '
      [.services[].ports[]?] | if $port == "" then length == 0
      else length == 1 and .[0].host_ip == "127.0.0.1" and
        .[0].published == (if $port == "auto" then "0" else $port end) end' >/dev/null
    compose run --rm --no-deps xray -test -config /etc/padm/xray/config.json >/dev/null
    compose up -d --pull never "${recreate[@]}" --wait --wait-timeout 60 xray origin
    compose run --rm --no-deps nginx -t >/dev/null
    compose run --rm --no-deps client -test -c /etc/padm/client/config.json >/dev/null
    compose up -d --pull never --force-recreate --wait --wait-timeout 60 nginx
    compose up -d --pull never --force-recreate client
    docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import socket
import ssl
import struct
import sys
import time

phase, selected, domain = sys.argv[1:]
def connect(host, port):
    deadline = time.monotonic() + 10
    while True:
        try:
            return socket.create_connection((host, port), timeout=0.2)
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)

def response(sock, request):
    sock.settimeout(20)
    sock.sendall(request)
    data = b""
    while True:
        part = sock.recv(65536)
        if not part:
            return data
        data += part

context = ssl.create_default_context(cafile="/test/runtime/client/ca.crt")
context.minimum_version = ssl.TLSVersion.TLSv1_3
website_port = 8443 if selected == "off" else 15443
with context.wrap_socket(connect("nginx", website_port), server_hostname=domain) as sock:
    data = response(sock, b"GET /website-proof HTTP/1.1\r\nHost: " + domain.encode() +
        b"\r\nConnection: close\r\n\r\n")
    assert b"200 OK" in data.split(b"\r\n", 1)[0] and data.endswith(b"padm-stream-website-proof\n"), data
try:
    with context.wrap_socket(connect("nginx", website_port), server_hostname="wrong.padm.test"):
        pass
except (ssl.SSLError, OSError):
    pass
else:
    raise AssertionError("wrong SNI accepted")

def probe(port):
    with connect("client", port) as sock:
        sock.settimeout(20)
        def receive(count):
            value = b""
            while len(value) < count:
                part = sock.recv(count - len(value))
                if not part:
                    raise EOFError(value)
                value += part
            return value
        sock.sendall(b"\x05\x01\x00")
        assert receive(2) == b"\x05\x00"
        name = b"origin"
        sock.sendall(b"\x05\x01\x00\x03" + bytes([len(name)]) + name + struct.pack("!H", 8088))
        header = receive(4)
        assert header[:2] == b"\x05\x00", header
        receive(4 if header[3] == 1 else 16 if header[3] == 4 else receive(1)[0])
        receive(2)
        data = response(sock, b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
        assert b"200" in data.split(b"\r\n", 1)[0] and data.endswith(b"padm-stream-proxy-proof\n"), data
    return str(port)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(probe, (2081,2082)))
print("reality-stream-real-phase-ok: " + phase + " website=strict-CA-SNI proxy=" + ",".join(results))
' "${phase}" "${listener}" "${DOMAIN}"
}

realPortHandoff() (
    local handoffPort=auto oldXray newXray owner backupSpec=${BASE} handoffBase="${TEST_ROOT}/handoff-base.json"
    local enabledSpec="${TEST_ROOT}/handoff-enabled.json" enabledCompose="${TEST_ROOT}/handoff-enabled-compose.json"
    local failedCompose="${TEST_ROOT}/handoff-failed-compose.json" id argument
    # 只改写生产停止函数的固定项目筛选，并在 stop 前逐个核对本次隔离标签。
    docker() {
        local argument id
        local -a arguments=()
        for argument in "$@"; do
            if [[ "${argument}" == "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" ]]; then
                arguments+=("label=com.docker.compose.project=${project}" --filter "label=io.padm.test=${project}")
            else arguments+=("${argument}"); fi
        done
        if [[ "${1:-}" == stop ]]; then
            for id in "${@:2}"; do
                command docker inspect "${id}" |
                    jq -e --arg project "${project}" '.[0].Config.Labels |
                      .["io.padm.test"] == $project and .["com.docker.compose.project"] == $project' >/dev/null ||
                    return 1
            done
        fi
        command docker "${arguments[@]}"
    }
    # 此子验收只把逻辑 443 映射到随机 loopback 端口；不占用宿主 443。
    jq '(.core.protocols[] | select(.listener_id == "entry-vision") | .public_port) = 443' \
        "${backupSpec}" >"${handoffBase}"
    BASE=${handoffBase}
    rm -f -- "${TEST_ROOT}/core-before.sha256"
    renderPhase handoff-direct off
    oldXray=$(compose ps -q xray)
    handoffPort=$(docker inspect "${oldXray}" |
        jq -er '.[0].NetworkSettings.Ports["443/tcp"] |
          select(length == 1 and .[0].HostIp == "127.0.0.1") | .[0].HostPort')
    [[ "${handoffPort}" =~ ^[0-9]+$ && "${handoffPort}" != 443 && "${handoffPort}" -gt 1024 ]]
    jq '.reality_stream={listener_id:"entry-vision",website_listener_id:"entry-website"}' \
        "${BASE}" >"${enabledSpec}"
    jq '.reality_stream={listener_id:"entry-xhttp",website_listener_id:"entry-website"}' \
        "${BASE}" >"${TEST_ROOT}/invalid-switch.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-switch.json"; then
        printf 'switch unexpectedly accepted unselected direct 443 owner\n' >&2
        return 1
    fi
    # 原持有者还在时，Docker 的同端口竞争绑定必须真实失败。
    if docker run --detach --pull=never --name "${project}-port-competitor" \
        --label "io.padm.test=${project}" --publish "127.0.0.1:${handoffPort}:8088" \
        --entrypoint python3 "${OPS_ID}" -m http.server 8088 \
        >"${TEST_ROOT}/port-competitor.out" 2>"${TEST_ROOT}/port-competitor.err"; then
        printf 'competing owner unexpectedly bound port %s\n' "${handoffPort}" >&2
        return 1
    fi
    grep -Eqi 'port is already allocated|address already in use|failed to bind host port' \
        "${TEST_ROOT}/port-competitor.err"
    docker rm "${project}-port-competitor" >/dev/null
    dockerRealityStreamTransitionPrepare "${enabledSpec}"
    [[ "$(docker inspect --format '{{.State.Running}}' "${oldXray}")" == false ]]
    renderPhase handoff-enable entry-vision
    cp "${COMPOSE}" "${enabledCompose}"
    newXray=$(compose ps -q xray)
    owner=$(compose ps -q nginx)
    docker inspect "${owner}" | jq -e --arg port "${handoffPort}" \
        '.[0].NetworkSettings.Ports["15443/tcp"] == [{HostIp:"127.0.0.1",HostPort:$port}]' >/dev/null
    dockerRealityStreamTransitionPrepare "${enabledSpec}"
    [[ "$(docker inspect --format '{{.State.Running}}' "${owner}")" == false ]]
    [[ "$(docker inspect --format '{{.State.Running}}' "${newXray}")" == true ]]
    renderPhase handoff-repeat entry-vision
    [[ "$(compose ps -q xray)" == "${newXray}" ]]
    owner=$(compose ps -q nginx)
    docker inspect "${owner}" | jq -e --arg port "${handoffPort}" \
        '.[0].NetworkSettings.Ports["15443/tcp"] == [{HostIp:"127.0.0.1",HostPort:$port}]' >/dev/null
    dockerRealityStreamTransitionPrepare "${BASE}"
    [[ "$(docker inspect --format '{{.State.Running}}' "${owner}")" == false ]]
    renderPhase handoff-disable off
    oldXray=$(compose ps -q xray)
    docker inspect "${oldXray}" | jq -e --arg port "${handoffPort}" \
        '.[0].NetworkSettings.Ports["443/tcp"] == [{HostIp:"127.0.0.1",HostPort:$port}]' >/dev/null
    dockerRealityStreamTransitionPrepare "${enabledSpec}"
    [[ "$(docker inspect --format '{{.State.Running}}' "${oldXray}")" == false ]]
    jq '.services.nginx.command=["-t","-c","/intentional-missing.conf"]' "${enabledCompose}" >"${failedCompose}"
    if docker compose --project-name "${project}" --file "${failedCompose}" --profile '*' \
        up -d --pull never --no-deps --wait --wait-timeout 5 nginx; then
        printf 'intentional bad owner unexpectedly became healthy\n' >&2
        return 1
    fi
    cp "${enabledSpec}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    dockerGenerateDeployment "${enabledSpec}" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    # 候选启动失败后，以备份方向停止失败候选并恢复原拥有者与真实流量。
    dockerRealityStreamTransitionPrepare "${BASE}"
    dockerRealityStreamStopServices nginx xray
    renderPhase handoff-restore off
    owner=$(compose ps -q xray)
    docker inspect "${owner}" | jq -e --arg port "${handoffPort}" \
        '.[0].NetworkSettings.Ports["443/tcp"] == [{HostIp:"127.0.0.1",HostPort:$port}]' >/dev/null
    printf 'docker-reality-stream-handoff-ok: port=127.0.0.1:%s owners=xray,nginx,nginx,xray,failed-nginx,xray prepare-only-xray-id=unchanged invalid-switch=rejected\n' \
        "${handoffPort}"
)

renderPhase direct off
renderPhase vision entry-vision
renderPhase vision-repeat entry-vision
renderPhase xhttp entry-xhttp
renderPhase disable off
realPortHandoff
[[ "${trafficHash}" == "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" ]]
printf 'docker-reality-stream-real-ok: isolated-loopback-handoff xray=%s nginx=%s ops=%s\n' \
    "${XRAY_ID}" "${NGINX_ID}" "${OPS_ID}"
