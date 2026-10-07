#!/usr/bin/env bash
set -euo pipefail
umask 077

# 验证 Desktop Linux VM 的宿主发布端口，不替代原生 Linux、宿主 443 或 host-mode 验收。
[[ "$#" == 3 ]] || {
    printf 'usage: reality-stream-host-real.sh <local-xray> <local-nginx> <local-ops>\n' >&2
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
project="padm-reality-stream-host-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-reality-stream-host.XXXXXX")
cleanup() {
    local status=$? ids resource name cleanupFailed=0
    trap - EXIT
    ids=$(docker ps -aq --filter "label=io.padm.test=${project}")
    if [[ -n "${ids}" ]]; then
        if [[ "${status}" != 0 ]]; then
            while IFS= read -r id; do docker logs "${id}" >&2 || true; done <<<"${ids}"
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
    else printf 'host-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2; status=1; fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 生产停止函数保持原样，隔离层只替换固定项目筛选并复核每个停止目标。
docker() {
    local argument id
    local -a arguments=()
    for argument in "$@"; do
        if [[ "${argument}" == "label=com.docker.compose.project=${PADM_DOCKER_PROJECT:-padm-docker}" ]]; then
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
docker volume create --label "io.padm.test=${project}" "${volume}" >/dev/null
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
dockerCleanupStagedBundle
DOMAIN=site.padm.test
ALIAS=www.site.padm.test
UUID=11111111-1111-4111-8111-111111111111
TARGET=reality.target.test
PUBLIC_KEY=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
PRIVATE_KEY=dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo
mkdir -p "${TEST_ROOT}/runtime/"{host,client,origin} "${TEST_ROOT}/certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-host-stream-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout "${TEST_ROOT}/certs/ca.key" -out "${TEST_ROOT}/runtime/client/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${TEST_ROOT}/runtime/host/site.key" -out "${TEST_ROOT}/certs/site.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s,DNS:%s,DNS:%s\nextendedKeyUsage=serverAuth\n' "${DOMAIN}" "${ALIAS}" "${TARGET}" \
    >"${TEST_ROOT}/certs/extensions"
openssl x509 -req -in "${TEST_ROOT}/certs/site.csr" -days 1 -set_serial 1 \
    -CA "${TEST_ROOT}/runtime/client/ca.crt" -CAkey "${TEST_ROOT}/certs/ca.key" \
    -extfile "${TEST_ROOT}/certs/extensions" -out "${TEST_ROOT}/runtime/host/site.crt" >/dev/null 2>&1
openssl verify -CAfile "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/host/site.crt" >/dev/null
cat >"${TEST_ROOT}/runtime/host/site.py" <<'PY'
import http.server
import ssl

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"padm-host-website-proof:" + self.connection.padm_sni.encode() + b"\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

def sni(sock, name, context):
    if name not in ("site.padm.test", "www.site.padm.test", "reality.target.test"):
        return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME
    sock.padm_sni = name

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.set_alpn_protocols(["h2", "http/1.1"])
context.load_cert_chain("/host/site.crt", "/host/site.key")
context.set_servername_callback(sni)
server = http.server.ThreadingHTTPServer(("0.0.0.0", 8443), Handler)
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
printf 'padm-host-proxy-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
chown -R 0:10001 "${TEST_ROOT}/runtime"
find "${TEST_ROOT}/runtime" -type d -exec chmod 750 {} +
find "${TEST_ROOT}/runtime" -type f -exec chmod 640 {} +
syncRuntime() {
    tar -cpf - -C "${TEST_ROOT}" runtime |
        docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
}
syncRuntime
# 网站不加入项目 bridge，只能从宿主发布端口经 host-gateway 访问。
site=$(docker run --detach --pull=never --name "${project}-host-website" \
    --label "io.padm.test=${project}" --user 10001:10001 --read-only --cap-drop ALL --init \
    --publish '0.0.0.0::8443' \
    --mount "type=volume,source=${volume},target=/host,readonly,volume-subpath=runtime/host" \
    --entrypoint python3 "${OPS_ID}" /host/site.py)
sitePort=$(docker inspect "${site}" | jq -er '.[0].NetworkSettings.Ports["8443/tcp"] |
    select(length == 1 and .[0].HostIp == "0.0.0.0") | .[0].HostPort')
[[ "${sitePort}" =~ ^[0-9]+$ && "${sitePort}" != 443 && "${sitePort}" -gt 1024 ]]
siteStarted=$(docker inspect --format '{{.State.StartedAt}}' "${site}")
BASE="${TEST_ROOT}/base.json"
SPEC="${TEST_ROOT}/spec.json"
COMPOSE="${TEST_ROOT}/compose.json"
HOST_ADDRESS=host.docker.internal
FRONTEND_PORT=auto
jq -n --arg uuid "${UUID}" --arg public "${PUBLIC_KEY}" --arg private "${PRIVATE_KEY}" --arg target "${TARGET}" \
    --argjson targetPort "${sitePort}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  def reality: {server_name:$target,target_host:$target,target_port:$targetPort,
    private_key:$private,public_key:$public,short_id:"6ba85179e30d4fc2"};
  def entry($id;$listener;$port): {id:$id,listener_id:$listener,core:"xray",
    server:"proxy.padm.test",public_port:$port,address_families:["ipv4","ipv6"],
    name:$listener,uuid:$uuid,reality:reality};
  {schema_version:3,release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
    core:{type:"xray",secondary_type:null,protocols:[
      entry(1;"entry-vision";35441),
      (entry(2;"entry-xhttp";35442) + {xhttp:{path:"/host-xhttp",host:$target,mode:"auto"}})]},
    tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
    images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
    host_integrations:[]}
' >"${BASE}"
chmod 600 "${BASE}"
jq -n --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
    name:"host-stream-account",upload:11,download:17,limit_bytes:1000000,
    baseline:{xray:{upload:{generation:"before-host-stream",value:7}}}}}}' | dockerTrafficWriteState
trafficHash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@" </dev/null; }

probe() {
    docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
        --add-host host.docker.internal:host-gateway \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import socket
import ssl
import struct
import sys
import time

phase, selected, site_port = sys.argv[1:]
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
host, port = ("host.docker.internal", int(site_port)) if selected == "off" else ("nginx",15443)
context = ssl.create_default_context(cafile="/test/runtime/client/ca.crt")
context.minimum_version = ssl.TLSVersion.TLSv1_3
for domain in ("site.padm.test","www.site.padm.test"):
    with context.wrap_socket(connect(host,port), server_hostname=domain) as sock:
        data = response(sock,b"GET /proof.txt HTTP/1.1\r\nHost: " + domain.encode() +
            b"\r\nConnection: close\r\n\r\n")
        assert b"200 OK" in data.split(b"\r\n",1)[0],data
        assert data.endswith(b"padm-host-website-proof:" + domain.encode() + b"\n"),data
try:
    with context.wrap_socket(connect(host,port),server_hostname="wrong.padm.test"):
        pass
except (ssl.SSLError,OSError):
    pass
else:
    raise AssertionError("wrong SNI accepted")
def proxy(port):
    with connect("client",port) as sock:
        sock.settimeout(20)
        def receive(count):
            value = b""
            while len(value) < count:
                part = sock.recv(count-len(value))
                if not part:
                    raise EOFError(value)
                value += part
            return value
        sock.sendall(b"\x05\x01\x00")
        assert receive(2) == b"\x05\x00"
        name = b"origin"
        sock.sendall(b"\x05\x01\x00\x03"+bytes([len(name)])+name+struct.pack("!H",8088))
        header = receive(4)
        assert header[:2] == b"\x05\x00",header
        receive(4 if header[3] == 1 else 16 if header[3] == 4 else receive(1)[0])
        receive(2)
        data = response(sock,b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
        assert b"200" in data.split(b"\r\n",1)[0] and data.endswith(b"padm-host-proxy-proof\n"),data
    return str(port)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    result = list(pool.map(proxy,(2081,2082)))
print("reality-stream-host-phase-ok: "+phase+" website=strict-CA-SNI-two-domains proxy="+",".join(result))
' "$1" "$2" "${sitePort}"
}

renderPhase() {
    local phase=$1 listener=$2 candidate hash gateway
    if [[ "${listener}" == off ]]; then cp "${BASE}" "${SPEC}"
    else
        jq --arg listener "${listener}" --arg domain "${DOMAIN}" --arg alias "${ALIAS}" \
            --arg address "${HOST_ADDRESS}" --argjson port "${sitePort}" '
          .reality_stream={listener_id:$listener,host_website:{domains:[$domain,$alias],address:$address,port:$port}}
        ' "${BASE}" >"${SPEC}"
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
        grep -qF "${HOST_ADDRESS}:${sitePort}" "${candidate}/config/nginx/stream/reality.conf"
        if [[ "${HOST_ADDRESS}" == host.docker.internal ]]; then
            jq -e '.services.nginx.extra_hosts | index("host.docker.internal:host-gateway") != null' \
                "${candidate}/compose.json" >/dev/null
        fi
    else jq -e '.services | has("nginx") | not' "${candidate}/compose.json" >/dev/null; fi
    dockerRealityStreamTransitionPrepare "${SPEC}"
    if [[ "${listener}" == off ]]; then
        rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx"
        mkdir -p -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx"
    fi
    for path in config data logs secrets; do
        cp -a "${candidate}/${path}/." "${PADM_DOCKER_INSTALL_DIR}/${path}/"
    done
    if [[ "${listener}" == off ]]; then rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream"; fi
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
    for entry in entry-vision entry-xhttp; do
        dockerProtocolCommand links "${entry}" >"${TEST_ROOT}/link-${entry}.txt"
        if [[ ! -f "${TEST_ROOT}/link-before-${entry}.txt" ]]; then
            cp "${TEST_ROOT}/link-${entry}.txt" "${TEST_ROOT}/link-before-${entry}.txt"
        elif [[ "${entry}" != "${listener}" ]]; then
            cmp "${TEST_ROOT}/link-${entry}.txt" "${TEST_ROOT}/link-before-${entry}.txt"
        fi
    done
    dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
    [[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 2 ]]
    if [[ "${listener}" == off ]]; then
        rm -rf -- "${TEST_ROOT}/runtime/config/nginx"
    fi
    cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/logs" "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
    python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${listener}" <<'PY'
import json
import pathlib
import sys
import urllib.parse

outbounds,inbounds,rules = [],[],[]
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    uri = urllib.parse.urlsplit(line)
    q = {k:v[0] for k,v in urllib.parse.parse_qs(uri.query).items()}
    assert q["security"] == "reality"
    listener = "entry-vision" if q["type"] == "tcp" else "entry-xhttp"
    assert uri.port == (443 if listener == sys.argv[3] else 35441 if listener == "entry-vision" else 35442)
    settings = {"network":q["type"],"security":"reality","realitySettings":{
        "serverName":q["sni"],"fingerprint":q["fp"],"publicKey":q["pbk"],"shortId":q["sid"]}}
    user = {"id":uri.username,"encryption":"none"}
    if q["type"] == "tcp":
        assert q["flow"] == "xtls-rprx-vision"
        user["flow"] = q["flow"]
    else:
        settings["xhttpSettings"] = {"path":q["path"],"host":q["host"],"mode":q["mode"]}
    selected = listener == sys.argv[3]
    inbounds.append({"tag":listener,"listen":"0.0.0.0","port":2081 if q["type"] == "tcp" else 2082,
        "protocol":"socks","settings":{"auth":"noauth","udp":False}})
    outbounds.append({"tag":listener,"protocol":"vless","settings":{"vnext":[{
        "address":"nginx" if selected else "xray","port":15443 if selected else uri.port,
        "users":[user]}]},"streamSettings":settings})
    rules.append({"type":"field","inboundTag":[listener],"outboundTag":listener})
pathlib.Path(sys.argv[2]).write_text(json.dumps({"log":{"loglevel":"warning"},
    "inbounds":inbounds,"outbounds":outbounds,"routing":{"rules":rules}}))
PY
    chmod 640 "${TEST_ROOT}/runtime/client/config.json"
    chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
    syncRuntime
    jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" \
        --arg nginx "${NGINX_ID}" --arg ops "${OPS_ID}" --arg port "${FRONTEND_PORT}" '
      .name=$project | .networks.default.name=$project | .networks.default.labels["io.padm.test"]=$project |
      del(.services.acme) | .volumes={files:{external:true,name:$volume}} |
      .services |= with_entries(
        .value.image=(if .key=="xray" then $xray else $nginx end) |
        .value.ports=[] | .value.pull_policy="never" | .value.labels["io.padm.test"]=$project |
        .value.volumes |= map(.source as $source | .type="volume" | .source="files" |
          .volume={nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} | del(.bind))) |
      if .services.nginx != null then .services.nginx.ports=[{host_ip:"127.0.0.1",
        published:(if $port=="auto" then "0" else $port end),target:15443,protocol:"tcp"}] else . end |
      .services.xray.extra_hosts=["reality.target.test:host-gateway"] |
      .services.origin={image:$ops,read_only:true,init:true,cap_drop:["ALL"],labels:{"io.padm.test":$project},
        entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
        volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
          volume:{nocopy:true,subpath:"runtime/origin"}}]} |
      .services.client={image:$xray,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
        labels:{"io.padm.test":$project},healthcheck:{disable:true},
        command:["run","-c","/etc/padm/client/config.json"],
        volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
          volume:{nocopy:true,subpath:"runtime/client"}}]}
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
    compose config --format json >/dev/null
    compose run --rm --no-deps xray -test -config /etc/padm/xray/config.json >/dev/null
    compose up -d --pull never --force-recreate --remove-orphans --wait --wait-timeout 60 xray origin
    compose run --rm --no-deps client -test -c /etc/padm/client/config.json >/dev/null
    if [[ "${listener}" != off ]]; then
        compose run --rm --no-deps nginx -t >/dev/null
        compose up -d --pull never --force-recreate --wait --wait-timeout 60 nginx
        FRONTEND_PORT=$(docker inspect "$(compose ps -q nginx)" |
            jq -er '.[0].NetworkSettings.Ports["15443/tcp"] |
              select(length == 1 and .[0].HostIp == "127.0.0.1") | .[0].HostPort')
        [[ "${FRONTEND_PORT}" =~ ^[0-9]+$ && "${FRONTEND_PORT}" != 443 && "${FRONTEND_PORT}" -gt 1024 ]]
        gateway=$(compose exec -T nginx cat /etc/hosts | awk '$2=="host.docker.internal" {print $1}')
        printf 'reality-stream-host-route: phase=%s address=%s gateway=%s site=0.0.0.0:%s frontend=127.0.0.1:%s\n' \
            "${phase}" "${HOST_ADDRESS}" "${gateway}" "${sitePort}" "${FRONTEND_PORT}"
    fi
    compose up -d --pull never --force-recreate client
    [[ "$(docker inspect --format '{{.State.StartedAt}}' "${site}")" == "${siteStarted}" ]]
    docker inspect "${site}" | jq -e --arg project "${project}" \
        '.[0].NetworkSettings.Networks | has($project) | not' >/dev/null
    probe "${phase}" "${listener}"
}

renderPhase direct off
renderPhase enable entry-vision
renderPhase repeat entry-vision
renderPhase switch entry-xhttp
HOST_IPV4=$(compose exec -T nginx cat /etc/hosts |
    awk '$2=="host.docker.internal" && $1 ~ /^[0-9]+\./ {print $1; exit}')
[[ "${HOST_IPV4}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
HOST_ADDRESS=${HOST_IPV4}
renderPhase literal-ipv4 entry-xhttp
HOST_ADDRESS=host.docker.internal
backupSpec="${TEST_ROOT}/failure-backup.json"
cp "${SPEC}" "${backupSpec}"
failedCompose="${TEST_ROOT}/failed-compose.json"
dockerRealityStreamTransitionPrepare "${backupSpec}"
jq '.services.nginx.command=["-t","-c","/intentional-missing.conf"]' "${COMPOSE}" >"${failedCompose}"
if docker compose --project-name "${project}" --file "${failedCompose}" --profile '*' \
    up -d --pull never --no-deps --wait --wait-timeout 5 nginx; then
    printf 'intentional bad host frontend unexpectedly became healthy\n' >&2
    exit 1
fi
dockerRealityStreamTransitionPrepare "${backupSpec}"
dockerRealityStreamStopServices nginx xray
renderPhase failure-restore entry-xhttp
renderPhase off off
[[ "${trafficHash}" == "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" ]]
printf 'docker-reality-stream-host-real-ok: desktop-linux-vm-host-gateway offline-reality-target site-port=%s frontend-port=%s xray=%s nginx=%s ops=%s\n' \
    "${sitePort}" "${FRONTEND_PORT}" "${XRAY_ID}" "${NGINX_ID}" "${OPS_ID}"
