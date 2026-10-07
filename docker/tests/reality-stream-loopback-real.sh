#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# 仅验收隔离的 Desktop Linux VM host 网络；不替代原生 Linux、可信发布或公网验收。
[[ "$#" == 3 ]] || {
    printf 'usage: reality-stream-loopback-real.sh <local-xray> <local-nginx> <local-ops>\n' >&2
    exit 2
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
for tool in docker jq python3 openssl sha256sum tar; do command -v "${tool}" >/dev/null; done
XRAY_ID=$(docker image inspect --format '{{.Id}}' "$1")
NGINX_ID=$(docker image inspect --format '{{.Id}}' "$2")
OPS_ID=$(docker image inspect --format '{{.Id}}' "$3")
for image in "${XRAY_ID}" "${NGINX_ID}" "${OPS_ID}"; do [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]; done
project="padm-stream-loopback-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-stream-loopback.XXXXXX")
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
    if [[ -n "${TRUSTED_OPS_ID:-}" ]] &&
        docker image inspect "${TRUSTED_OPS_ID}" |
            jq -e --arg project "${project}" '.[0].Config.Labels["io.padm.test"]==$project' >/dev/null; then
        docker image rm "${project}-ops-trust:local" >/dev/null || cleanupFailed=1
    fi
    if [[ "${cleanupFailed}" == 0 ]]; then rm -rf -- "${TEST_ROOT}"
    else printf 'loopback cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2; status=1; fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "loopback-error: line=%s command=%s\n" "${LINENO}" "${BASH_COMMAND}" >&2' ERR
docker() {
    local argument id
    local -a arguments=() streamIds=()
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
            if [[ "$(command docker inspect --format '{{index .Config.Labels "com.docker.compose.service"}}' "${id}")" == nginx-stream ]]; then
                streamIds+=("${id}")
            fi
        done
    fi
    command docker "${arguments[@]}" || return 1
    for id in "${streamIds[@]}"; do
        command docker inspect "${id}" |
            jq -e '.[0].State | .Status=="exited" and .Pid==0' >/dev/null || return 1
        command docker logs "${id}" >"${TEST_ROOT}/nginx-stop-${id}.log" 2>&1 || return 1
        if grep -qE 'Permission denied|Operation not permitted|kill\(.*failed' "${TEST_ROOT}/nginx-stop-${id}.log"; then return 1; fi
        if [[ "${FAILED_STREAM_ID:-}" == "${id}"* ]]; then
            command docker inspect "${id}" | jq -e '.[0].State.ExitCode==1' >/dev/null || return 1
            grep -qF '/intentional-missing.conf' "${TEST_ROOT}/nginx-stop-${id}.log" || return 1
            printf 'loopback-intentional-failure-stopped-ok: %s expected-exit=1 no-child-pid\n' "${id}" >&2
        else
            command docker inspect "${id}" | jq -e '.[0].State.ExitCode==0' >/dev/null || return 1
            grep -qE 'signal 15 \(SIGTERM\) received|gracefully shutting down' "${TEST_ROOT}/nginx-stop-${id}.log" || return 1
            printf 'loopback-nginx-graceful-stop-ok: %s master-exit=0 no-child-pid\n' "${id}" >&2
        fi
    done
}
portsFree() {
    docker run --rm --pull=never --network host --label "io.padm.test=${project}" \
        --user 0:0 --cap-drop ALL --cap-add NET_BIND_SERVICE --entrypoint python3 "${OPS_ID}" -c '
import socket
for host,port in (("0.0.0.0",443),("::",443),("127.0.0.1",15443)):
    with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET) as sock:
        sock.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        if ":" in host:
            sock.setsockopt(socket.IPPROTO_IPV6,socket.IPV6_V6ONLY,1)
        sock.bind((host,port))
        sock.listen(1)
print("loopback-host-ports-free: 443/ipv4,443/ipv6,15443/127.0.0.1")
'
}
# 只检查并释放端口；若已被占用立即退出，不停止任何现有拥有者。
portsFree
docker volume create --label "io.padm.test=${project}" "${volume}" >/dev/null
docker network create --label "io.padm.test=${project}" "${project}" >/dev/null
BRIDGE_GATEWAY=$(docker network inspect "${project}" --format '{{(index .IPAM.Config 0).Gateway}}')
[[ "${BRIDGE_GATEWAY}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
export PADM_TEST_DOCKER_REAL
PADM_TEST_DOCKER_REAL=$(type -P docker)
export PADM_TEST_OPS_IMAGE="${OPS_ID}" PADM_TEST_PROJECT="${project}"
mkdir -p "${TEST_ROOT}/bin"
# timeout 调用外部命令；只替换伪 Ops 镜像来源，保留生产探针的网络、Python 和超时参数。
cat >"${TEST_ROOT}/bin/docker" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
arguments=()
for argument in "$@"; do
    if [[ "${argument}" == "ghcr.io/example/padm-ops:test@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]]; then
        arguments+=("${PADM_TEST_OPS_IMAGE}")
    else arguments+=("${argument}"); fi
done
if [[ "${1:-}" == run ]]; then
    arguments=(run --label "io.padm.test=${PADM_TEST_PROJECT}" "${arguments[@]:1}")
fi
exec "${PADM_TEST_DOCKER_REAL}" "${arguments[@]}"
SH
chmod 750 "${TEST_ROOT}/bin/docker"
export PATH="${TEST_ROOT}/bin:${PATH}"
dockerHostPreflight
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
dockerCleanupStagedBundle
DOMAIN=site.padm.test
ALIAS=www.site.padm.test
TARGET=reality.target.test
UUID=11111111-1111-4111-8111-111111111111
PUBLIC_KEY=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
PRIVATE_KEY=dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo
mkdir -p "${TEST_ROOT}/runtime/"{tls,client,origin} "${TEST_ROOT}/certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-loopback-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout "${TEST_ROOT}/certs/ca.key" -out "${TEST_ROOT}/runtime/client/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${TEST_ROOT}/runtime/tls/site.key" -out "${TEST_ROOT}/certs/site.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s,DNS:%s,DNS:%s\nextendedKeyUsage=serverAuth\n' "${DOMAIN}" "${ALIAS}" "${TARGET}" \
    >"${TEST_ROOT}/certs/extensions"
openssl x509 -req -in "${TEST_ROOT}/certs/site.csr" -days 1 -set_serial 1 \
    -CA "${TEST_ROOT}/runtime/client/ca.crt" -CAkey "${TEST_ROOT}/certs/ca.key" \
    -extfile "${TEST_ROOT}/certs/extensions" -out "${TEST_ROOT}/runtime/tls/site.crt" >/dev/null 2>&1
cat >"${TEST_ROOT}/runtime/tls/server.py" <<'PY'
import http.server
import socket
import ssl
import sys
import threading

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"padm-loopback-website:" + self.connection.padm_sni.encode() + b"\n"
        self.send_response(200)
        self.send_header("Content-Length",str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self,*args):
        pass
def sni(sock,name,context):
    if name not in ("site.padm.test","www.site.padm.test","reality.target.test"):
        return ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME
    sock.padm_sni = name
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.set_alpn_protocols(["h2","http/1.1"])
context.load_cert_chain("/tls/site.crt","/tls/site.key")
context.set_servername_callback(sni)
class V6Server(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6
if sys.argv[1] == "host":
    first = http.server.ThreadingHTTPServer(("127.0.0.1",0),Handler)
    port = first.server_address[1]
    servers = [first,V6Server(("::1",port),Handler)]
else:
    servers = [http.server.ThreadingHTTPServer(("0.0.0.0",8443),Handler)]
    port = 8443
for server in servers:
    server.socket = context.wrap_socket(server.socket,server_side=True)
    threading.Thread(target=server.serve_forever,daemon=True).start()
print("tls-ready:"+str(port),flush=True)
threading.Event().wait()
PY
printf 'padm-loopback-proxy-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
chown -R 0:10001 "${TEST_ROOT}/runtime"
find "${TEST_ROOT}/runtime" -type d -exec chmod 750 {} +
find "${TEST_ROOT}/runtime" -type f -exec chmod 640 {} +
syncRuntime() {
    tar -cpf - -C "${TEST_ROOT}" runtime |
        docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
}
syncRuntime
trustContainer=$(docker run --detach --pull=never --user 0:0 --label "io.padm.test=${project}" \
    --mount "type=volume,source=${volume},target=/test,readonly,volume-subpath=runtime/client" \
    --entrypoint sleep "${OPS_ID}" 7200)
docker exec "${trustContainer}" sh -c 'cp /test/ca.crt /usr/local/share/ca-certificates/padm-test-ca.crt && update-ca-certificates' \
    >/dev/null
TRUSTED_OPS_ID=$(docker commit --change "LABEL io.padm.test=${project}" "${trustContainer}" "${project}-ops-trust:local")
docker rm -f "${trustContainer}" >/dev/null
site=$(docker run --detach --pull=never --network host --name "${project}-site" \
    --label "io.padm.test=${project}" --user 10001:10001 --read-only --cap-drop ALL --init \
    --mount "type=volume,source=${volume},target=/tls,readonly,volume-subpath=runtime/tls" \
    --entrypoint python3 "${OPS_ID}" /tls/server.py host)
sitePort=
for _ in {1..100}; do
    sitePort=$(docker logs "${site}" 2>/dev/null | sed -n 's/^tls-ready://p')
    [[ -z "${sitePort}" ]] || break
    sleep 0.1
done
[[ "${sitePort}" =~ ^[0-9]+$ && "${sitePort}" != 443 && "${sitePort}" != 15443 ]]
siteStarted=$(docker inspect --format '{{.State.StartedAt}}' "${site}")
docker run --detach --pull=never --network "${project}" --network-alias "${TARGET}" --name "${project}-target" \
    --label "io.padm.test=${project}" --user 10001:10001 --read-only --cap-drop ALL --init \
    --mount "type=volume,source=${volume},target=/tls,readonly,volume-subpath=runtime/tls" \
    --entrypoint python3 "${OPS_ID}" /tls/server.py target >/dev/null
BASE="${TEST_ROOT}/base.json"
SPEC="${TEST_ROOT}/spec.json"
COMPOSE="${TEST_ROOT}/compose.json"
jq -n --arg uuid "${UUID}" --arg public "${PUBLIC_KEY}" --arg private "${PRIVATE_KEY}" --arg target "${TARGET}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  def reality: {server_name:$target,target_host:$target,target_port:8443,
    private_key:$private,public_key:$public,short_id:"6ba85179e30d4fc2"};
  def entry($id;$listener;$port): {id:$id,listener_id:$listener,core:"xray",
    server:"proxy.padm.test",public_port:$port,address_families:["ipv4","ipv6"],name:$listener,uuid:$uuid,reality:reality};
  {schema_version:3,release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"xray",secondary_type:null,protocols:[entry(1;"entry-vision";35441),
     (entry(2;"entry-xhttp";35442)+{xhttp:{path:"/loopback-xhttp",host:$target,mode:"auto"}})]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${BASE}"
chmod 600 "${BASE}"
jq -n --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"loopback-account",upload:11,download:17,limit_bytes:1000000,
  baseline:{xray:{upload:{generation:"before-loopback",value:7}}}}}}' | dockerTrafficWriteState
trafficHash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@" </dev/null; }
websiteProbe() {
    docker run --rm --pull=never --network host --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import socket
import ssl
import sys
phase,port = sys.argv[1],int(sys.argv[2])
context=ssl.create_default_context(cafile="/test/runtime/client/ca.crt")
context.minimum_version=ssl.TLSVersion.TLSv1_3
for address in ("127.0.0.1","::1"):
    for domain in ("site.padm.test","www.site.padm.test"):
        with context.wrap_socket(socket.create_connection((address,port),timeout=5),server_hostname=domain) as sock:
            sock.sendall(b"GET /proof HTTP/1.1\r\nHost: "+domain.encode()+b"\r\nConnection: close\r\n\r\n")
            data=b""
            while True:
                part=sock.recv(65536)
                if not part: break
                data+=part
            assert b"200 OK" in data.split(b"\r\n",1)[0] and data.endswith(
                b"padm-loopback-website:"+domain.encode()+b"\n"),data
    try:
        with context.wrap_socket(socket.create_connection((address,port),timeout=5),server_hostname="wrong.padm.test"):
            pass
    except (ssl.SSLError,OSError):
        pass
    else: raise AssertionError("wrong SNI accepted")
print("loopback-website-ok: "+phase+" family=ipv4,ipv6 strict-ca-sni=two-domains")
' "$1" "$2"
}
proxyProbe() {
    docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
        --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import socket
import struct
import sys
import time
def probe(port):
    try:
        deadline=time.monotonic()+10
        while True:
            try: sock=socket.create_connection(("client",port),timeout=0.2); break
            except OSError:
                if time.monotonic()>=deadline: raise
                time.sleep(0.05)
        with sock:
            sock.settimeout(20)
            def receive(count):
                data=b""
                while len(data)<count:
                    part=sock.recv(count-len(data))
                    if not part: raise EOFError(data)
                    data+=part
                return data
            sock.sendall(b"\x05\x01\x00")
            assert receive(2)==b"\x05\x00"
            name=b"origin"
            sock.sendall(b"\x05\x01\x00\x03"+bytes([len(name)])+name+struct.pack("!H",8088))
            head=receive(4)
            assert head[:2]==b"\x05\x00",head
            receive(4 if head[3]==1 else 16 if head[3]==4 else receive(1)[0]); receive(2)
            sock.sendall(b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
            data=b""
            while True:
                part=sock.recv(65536)
                if not part: break
                data+=part
            assert b"200" in data.split(b"\r\n",1)[0] and data.endswith(b"padm-loopback-proxy-proof\n"),data
    except Exception as error:
        raise RuntimeError(f"proxy port {port}: {error!r}") from error
    return str(port)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: result=list(pool.map(probe,(2081,2082)))
print("loopback-proxy-ok: "+sys.argv[1]+" source=production-uri socks="+",".join(result))
' "$1"
}
frontRouteProbe() {
    docker run --rm --pull=never --network host --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import socket
import ssl
context=ssl.create_default_context(cafile="/test/runtime/client/ca.crt")
with context.wrap_socket(socket.create_connection(("127.0.0.1",15443),timeout=5),server_hostname="reality.target.test") as sock:
    sock.sendall(b"GET / HTTP/1.1\r\nHost: reality.target.test\r\nConnection: close\r\n\r\n")
    assert b"200 OK" in sock.recv(4096)
print("loopback-relay-tls-ok: 127.0.0.1:15443 strict-ca-sni=reality.target.test")
'
    docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
        --add-host host.docker.internal:host-gateway \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import socket
import ssl
import sys
context=ssl.create_default_context(cafile="/test/runtime/client/ca.crt")
for address in ("host.docker.internal",sys.argv[1]):
    try:
        with context.wrap_socket(socket.create_connection((address,443),timeout=5),server_hostname="site.padm.test") as sock:
            sock.sendall(b"GET / HTTP/1.1\r\nHost: site.padm.test\r\nConnection: close\r\n\r\n")
            result=sock.recv(4096)
            assert b"200 OK" in result,result
        print("loopback-front-route-ok: "+address,flush=True)
    except Exception as error:
        print("loopback-front-route-failed: "+address+" "+repr(error),flush=True)
        if address == sys.argv[1]: raise
' "${BRIDGE_GATEWAY}"
}
renderPhase() {
    local phase=$1 listener=$2 address=$3 candidate hash
    if [[ "${listener}" == off ]]; then cp "${BASE}" "${SPEC}"
    else
        jq --arg listener "${listener}" --arg address "${address}" --arg domain "${DOMAIN}" --arg alias "${ALIAS}" \
            --argjson port "${sitePort}" '.reality_stream={listener_id:$listener,host_website:{
              domains:[$domain,$alias],address:$address,port:$port,network_mode:"host"}}' "${BASE}" >"${SPEC}"
    fi
    chmod 600 "${SPEC}"
    dockerConfigureSpecValidate "${SPEC}"
    jq -e --slurpfile base "${BASE}" 'del(.reality_stream)==$base[0]' "${SPEC}" >/dev/null
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${SPEC}" "${candidate}"
    if [[ "${listener}" != off ]]; then
        jq -e '.services["nginx-stream"] | .network_mode=="host" and .user=="0:0" and
          .cap_drop==["ALL"] and (.cap_add|sort)==["KILL","NET_BIND_SERVICE","SETGID","SETUID"] and (.ports==null)' \
            "${candidate}/compose.json" >/dev/null
        jq -e '.services | has("nginx") | not' "${candidate}/compose.json" >/dev/null
        grep -qF 'server 127.0.0.1:15443;' "${candidate}/config/nginx/stream/reality.conf"
        if [[ ! -f "${TEST_ROOT}/default-ca-rejected" ]]; then
            export PADM_TEST_OPS_IMAGE="${OPS_ID}"
            if dockerRealityStreamHostProbe "${SPEC}" backend >"${TEST_ROOT}/default-ca.out" 2>"${TEST_ROOT}/default-ca.err"; then
                printf 'default trust unexpectedly accepted test CA\n' >&2
                return 1
            fi
            grep -qF CERTIFICATE_VERIFY_FAILED "${TEST_ROOT}/default-ca.err"
            touch "${TEST_ROOT}/default-ca-rejected"
        fi
        export PADM_TEST_OPS_IMAGE="${TRUSTED_OPS_ID}"
        dockerRealityStreamHostProbe "${SPEC}" backend
        jq '.reality_stream.host_website.domains=["wrong.padm.test"]' "${SPEC}" >"${TEST_ROOT}/wrong-sni.json"
        if dockerRealityStreamHostProbe "${TEST_ROOT}/wrong-sni.json" backend >/dev/null 2>&1; then
            printf 'trusted probe unexpectedly accepted wrong SNI\n' >&2
            return 1
        fi
    fi
    dockerRealityStreamTransitionPrepare "${SPEC}"
    rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx"
    mkdir -p -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx"
    for path in config data logs secrets; do cp -a "${candidate}/${path}/." "${PADM_DOCKER_INSTALL_DIR}/${path}/"; done
    cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
    cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerCleanupConfigurationCandidate
    dockerEnsureRuntimeDataPermissions
    [[ "${trafficHash}" == "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" ]]
    hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base")
    if [[ -f "${TEST_ROOT}/core-before.sha256" ]]; then [[ "${hash}" == "$(<"${TEST_ROOT}/core-before.sha256")" ]]
    else printf '%s\n' "${hash}" >"${TEST_ROOT}/core-before.sha256"; fi
    dockerTrafficAccounts xray >"${TEST_ROOT}/accounts-${phase}.json"
    if [[ -f "${TEST_ROOT}/accounts-before.json" ]]; then cmp "${TEST_ROOT}/accounts-before.json" "${TEST_ROOT}/accounts-${phase}.json"
    else cp "${TEST_ROOT}/accounts-${phase}.json" "${TEST_ROOT}/accounts-before.json"; fi
    for entry in entry-vision entry-xhttp; do
        dockerProtocolCommand links "${entry}" >"${TEST_ROOT}/link-${entry}.txt"
        if [[ ! -f "${TEST_ROOT}/link-before-${entry}.txt" ]]; then cp "${TEST_ROOT}/link-${entry}.txt" "${TEST_ROOT}/link-before-${entry}.txt"
        elif [[ "${entry}" != "${listener}" ]]; then cmp "${TEST_ROOT}/link-${entry}.txt" "${TEST_ROOT}/link-before-${entry}.txt"; fi
    done
    dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
    rm -rf -- "${TEST_ROOT}/runtime/config/nginx"
    cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/logs" "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
    # Desktop 的 host-gateway 指向另一个 L4 端点；选中 URI 仅在夹具中解析为已实测的 VM 网关。
    python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${listener}" "${BRIDGE_GATEWAY}" <<'PY'
import json
import pathlib
import sys
import urllib.parse
inbounds,outbounds,rules=[],[],[]
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    uri=urllib.parse.urlsplit(line)
    q={k:v[0] for k,v in urllib.parse.parse_qs(uri.query).items()}
    listener="entry-vision" if q["type"]=="tcp" else "entry-xhttp"
    selected=listener==sys.argv[3]
    assert uri.port==(443 if selected else 35441 if listener=="entry-vision" else 35442)
    settings={"network":q["type"],"security":"reality","realitySettings":{
        "serverName":q["sni"],"fingerprint":q["fp"],"publicKey":q["pbk"],"shortId":q["sid"]}}
    user={"id":uri.username,"encryption":"none"}
    if q["type"]=="tcp": user["flow"]=q["flow"]
    else: settings["xhttpSettings"]={"path":q["path"],"host":q["host"],"mode":q["mode"]}
    inbounds.append({"tag":listener,"listen":"0.0.0.0","port":2081 if q["type"]=="tcp" else 2082,
        "protocol":"socks","settings":{"auth":"noauth","udp":False}})
    outbounds.append({"tag":listener,"protocol":"vless","settings":{"vnext":[{
        "address":sys.argv[4] if selected else "xray","port":uri.port,"users":[user]}]},"streamSettings":settings})
    rules.append({"type":"field","inboundTag":[listener],"outboundTag":listener})
pathlib.Path(sys.argv[2]).write_text(json.dumps({"log":{"loglevel":"warning"},
    "inbounds":inbounds,"outbounds":outbounds,"routing":{"rules":rules}}))
PY
    chmod 640 "${TEST_ROOT}/runtime/client/config.json"
    chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
    syncRuntime
    jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" --arg nginx "${NGINX_ID}" --arg ops "${OPS_ID}" '
      .name=$project | .networks.default={name:$project,external:true} |
      del(.services.acme) | .volumes={files:{external:true,name:$volume}} |
      .services |= with_entries(
        .value.image=(if .key=="xray" then $xray else $nginx end) |
        .value.pull_policy="never" | .value.labels["io.padm.test"]=$project |
        (if .key=="xray" then .value.ports |= map(select(startswith("127.0.0.1:15443:"))) else . end) |
        .value.volumes |= map(.source as $source | .type="volume" | .source="files" |
          .volume={nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} | del(.bind))) |
      .services.origin={image:$ops,read_only:true,init:true,cap_drop:["ALL"],labels:{"io.padm.test":$project},
        entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
        volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,volume:{nocopy:true,subpath:"runtime/origin"}}]} |
      .services.client={image:$xray,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
        labels:{"io.padm.test":$project},healthcheck:{disable:true},
        command:["run","-c","/etc/padm/client/config.json"],volumes:[{type:"volume",source:"files",
          target:"/etc/padm/client",read_only:true,volume:{nocopy:true,subpath:"runtime/client"}}]}
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
    compose config --format json >/dev/null
    compose run --rm --no-deps xray -test -config /etc/padm/xray/config.json >/dev/null
    compose up -d --pull never --force-recreate --remove-orphans --wait --wait-timeout 60 xray origin
    if [[ "${listener}" != off ]]; then
        compose run --rm --no-deps nginx-stream -t -c /etc/nginx/stream.d/host-main >/dev/null
        compose up -d --pull never --force-recreate --wait --wait-timeout 60 nginx-stream
        docker inspect "$(compose ps -q nginx-stream)" | jq -e --arg project "${project}" '.[0] |
          .HostConfig.NetworkMode=="host" and .Config.User=="0:0" and .HostConfig.CapDrop==["ALL"] and
          ([.HostConfig.CapAdd[] | sub("^CAP_";"")] | sort)==["KILL","NET_BIND_SERVICE","SETGID","SETUID"] and
          .Config.Labels["io.padm.test"]==$project' >/dev/null
        # shellcheck disable=SC2016
        compose exec -T nginx-stream sh -c 'for path in /proc/[0-9]*/status; do
          awk "/^Name:/ {name=\$2} /^Uid:/ {uid=\$2} /^Gid:/ {gid=\$2}
            END {if (name==\"nginx\") print uid \":\" gid}" "$path"; done' >"${TEST_ROOT}/nginx-identity"
        grep -qxF '0:0' "${TEST_ROOT}/nginx-identity"
        grep -qxF '10001:10001' "${TEST_ROOT}/nginx-identity"
        if grep -qvE '^(0:0|10001:10001)$' "${TEST_ROOT}/nginx-identity"; then return 1; fi
        printf 'loopback-nginx-identity-ok: master=0:0 worker=10001:10001 capabilities=KILL,NET_BIND_SERVICE,SETGID,SETUID\n'
        websiteProbe "${phase}" 443
        frontRouteProbe
    else websiteProbe "${phase}" "${sitePort}"; fi
    compose run --rm --no-deps client -test -c /etc/padm/client/config.json >/dev/null
    compose up -d --pull never --force-recreate client
    [[ "$(docker inspect --format '{{.State.StartedAt}}' "${site}")" == "${siteStarted}" ]]
    proxyProbe "${phase}"
    printf 'loopback-phase-ok: %s website=%s:%s actual-front=443 backend=127.0.0.1:15443\n' "${phase}" "${address}" "${sitePort}"
}
renderPhase direct off 127.0.0.1
renderPhase enable-v4 entry-vision 127.0.0.1
renderPhase switch-v6 entry-xhttp ::1
renderPhase repeat-v6 entry-xhttp ::1
backupSpec="${TEST_ROOT}/backup-spec.json"
cp "${SPEC}" "${backupSpec}"
dockerRealityStreamTransitionPrepare "${backupSpec}"
jq '.services["nginx-stream"].command=["-t","-c","/intentional-missing.conf"]' "${COMPOSE}" >"${TEST_ROOT}/failed-compose.json"
if docker compose --project-name "${project}" --file "${TEST_ROOT}/failed-compose.json" --profile '*' \
    up -d --pull never --no-deps --wait --wait-timeout 5 nginx-stream; then
    printf 'intentional bad host frontend unexpectedly became healthy\n' >&2
    exit 1
fi
FAILED_STREAM_ID=$(compose ps --all --quiet nginx-stream)
[[ "${FAILED_STREAM_ID}" =~ ^[a-f0-9]{64}$ ]]
dockerRealityStreamTransitionPrepare "${backupSpec}"
renderPhase failure-restore entry-xhttp ::1
renderPhase off off 127.0.0.1
portsFree
printf 'docker-reality-stream-loopback-real-ok: desktop-linux-vm actual443 ipv4,ipv6 site-port=%s offline-target xray=%s nginx=%s ops=%s\n' \
    "${sitePort}" "${XRAY_ID}" "${NGINX_ID}" "${OPS_ID}"
