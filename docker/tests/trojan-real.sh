#!/usr/bin/env bash
set -euo pipefail
umask 077

# 只验收本次唯一项目与命名卷，不发布宿主端口或接管现有部署。
[[ "$#" == 4 ]] || { printf 'usage: trojan-real.sh <local-xray> <local-sing-box> <local-ops> <local-curl>\n' >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'trojan-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3 CURL_REF=$4
for tool in docker jq python3 sha256sum tar openssl awk; do command -v "${tool}" >/dev/null; done
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
CURL_ID=$(docker image inspect --format '{{.Id}}' "${CURL_REF}")
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-trojan-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
subnet=$(printf 'fd42:7061:646d:%x::/64' "${RANDOM}")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-trojan-real.XXXXXX")
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
            else
                cleanup_failed=1
            fi
        fi
    done
    if [[ "${cleanup_failed}" == 0 ]]; then rm -rf -- "${TEST_ROOT}"
    else
        printf 'trojan-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2
        status=1
    fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker run --rm --pull=never --network none --label "io.padm.test=${project}" \
    --entrypoint curl "${CURL_ID}" --version |
    grep -Eq '^Features:.*[[:space:]]HTTP2([[:space:]]|$)'
docker volume create --label "io.padm.test=${project}" "${volume}" >/dev/null
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight
dockerInitializeStateRoot
dockerStageBundle "${PROJECT_ROOT}" 0000000000000000000000000000000000000000
dockerActivateStagedBundle
dockerCleanupStagedBundle
DOMAIN=trojan.padm.test
UUID=11111111-1111-4111-8111-111111111111
TLS_DIR="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
mkdir -p "${TEST_ROOT}/certs" "${TLS_DIR}" "${TEST_ROOT}/runtime/"{client,origin}
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-trojan-test-ca \
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
jq -n --arg uuid "${UUID}" --arg domain "${DOMAIN}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[
     {id:28,listener_id:"entry-trojan-xray",core:"xray",server:$domain,public_port:35466,
      address_families:["ipv4","ipv6"],name:"trojan-xray",uuid:$uuid,trojan:{domain:$domain}},
     {id:28,listener_id:"entry-trojan-sing",core:"sing-box",server:$domain,public_port:35467,
      address_families:["ipv4","ipv6"],name:"trojan-sing",uuid:$uuid,trojan:{domain:$domain}}]},
   tls:{domain:$domain},subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${candidate}"
jq -e --arg uuid "${UUID}" --arg domain "${DOMAIN}" '
  ([.inbounds[] | select(.protocol == "trojan")] | length) == 1 and
  (first(.inbounds[] | select(.protocol == "trojan")) | .listen == "::" and .port == 35466 and
    .settings.clients == [{email:$uuid,password:$uuid}] and
    .streamSettings.tlsSettings.serverName == $domain and
    .streamSettings.tlsSettings.alpn == ["http/1.1"])' \
  "${candidate}/config/xray/config.json" >/dev/null
jq -e --arg uuid "${UUID}" --arg domain "${DOMAIN}" '
  ([.inbounds[] | select(.type == "trojan")] | length) == 1 and
  (.inbounds[0] | .listen == "::" and .listen_port == 35467 and
    .users == [{name:$uuid,password:$uuid}] and .tls.server_name == $domain and
    .tls.alpn == ["http/1.1"])' \
  "${candidate}/config/sing-box/config.json" >/dev/null
jq -e '
  .core.type == "xray" and .core.secondary_type == "sing-box" and
  (.listeners | length) == 2 and
  all(.listeners[]; .service == "xray" or .service == "sing-box") and
  all(.listeners[]; .transport == "tcp" and .address_families == ["ipv4","ipv6"])
' "${candidate}/deployment.json" >/dev/null
cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerCleanupConfigurationCandidate
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env"
for core in xray sing-box; do
    dockerTrafficAccounts "${core}" | jq -e --arg uuid "${UUID}" \
        'length == 1 and .[0].account == $uuid' >/dev/null
    [[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json")" == 0:10001:640 ]]
    [[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base")" == 0:10001:640 ]]
done
base_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/"{xray,sing-box}/users.base)
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 2 ]]
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/certs/ca.crt" "${TEST_ROOT}/runtime/client/ca.crt"
cat >"${TEST_ROOT}/runtime/origin/server.py" <<'PY'
import http.server
import json
import socket
import threading

counts = {"tcp": 0, "udp": 0}
lock = threading.Lock()
proof = b"padm-trojan-real-proof\n"
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
jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" \
    --arg sing "${SING_ID}" --arg ops "${OPS_ID}" --arg subnet "${subnet}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  .networks.default.enable_ipv6 = true | .networks.default.ipam = {config:[{subnet:$subnet}]} |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services.xray.image = $xray | .services["sing-box"].image = $sing |
  .services |= with_entries(.value.ports = [] | .value.init = true |
    .value.labels["io.padm.test"] = $project |
    .value.volumes |= map(.source as $source |
      .type = "volume" | .source = "files" |
      .volume = {nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} |
      del(.bind))) |
  .services.origin = {image:$ops,user:"10001:10001",read_only:true,init:true,cap_drop:["ALL"],
    entrypoint:["python3","/srv/server.py"],labels:{"io.padm.test":$project},
    healthcheck:{test:["CMD","python3","-c","import urllib.request; urllib.request.urlopen(\"http://127.0.0.1:8088/counts\",timeout=2).read()"],
      interval:"1s",timeout:"3s",retries:3,start_period:"1s"},
    volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
      volume:{nocopy:true,subpath:"runtime/origin"}}]} |
  .services.client = {image:$sing,user:"10001:10001",read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/config.json"],
    volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]}
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@" </dev/null; }
compose config --format json >/dev/null
compose run --rm --no-deps --pull never xray -test -config /etc/padm/xray/config.json >/dev/null
compose run --rm --no-deps --pull never sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null
compose up -d --pull never --wait --wait-timeout 60 xray sing-box origin
xray_server=$(compose ps -q xray); sing_server=$(compose ps -q sing-box)
for service in xray sing-box; do
    container=$(compose ps -q "${service}")
    image=${XRAY_ID}; [[ "${service}" != sing-box ]] || image=${SING_ID}
    docker inspect "${container}" | jq -e --arg project "${project}" --arg image "${image}" '
      .[0] | .State.Running and .State.Health.Status == "healthy" and .Config.Image == $image and
      .Config.User == "10001:10001" and .HostConfig.ReadonlyRootfs and .HostConfig.Init and
      .HostConfig.CapDrop == ["ALL"] and .Config.Labels["io.padm.test"] == $project and
      (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null)
    ' >/dev/null
done
addresses=$(docker inspect "${xray_server}" "${sing_server}" |
    jq -cer --arg project "${project}" '
      reduce .[] as $container ({}; .[$container.Config.Labels["com.docker.compose.service"]] =
        ($container.NetworkSettings.Networks[$project] | [.IPAddress,.GlobalIPv6Address]))')
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" <<'PY'
import ipaddress
import json
import pathlib
import sys
import urllib.parse
import uuid

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
endpoints = json.loads(sys.argv[3])
assert len(lines) == 2 and set(endpoints) == {"xray", "sing-box"}
for addresses in endpoints.values():
    assert [ipaddress.ip_address(x).version for x in addresses] == [4, 6], addresses
config = {"log":{"level":"warn"}, "inbounds":[], "outbounds":[], "route":{"rules":[]}}
ports = {35466:("xray","trojan-xray"), 35467:("sing-box","trojan-sing")}
def parse(line):
    uri = urllib.parse.urlsplit(line)
    query = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    assert uri.scheme == "trojan" and uri.username and uri.password is None and not uri.path
    assert uri.hostname == "trojan.padm.test" and uri.port in ports
    identity = urllib.parse.unquote(uri.username)
    assert str(uuid.UUID(identity)) == identity
    assert set(query) == {"peer","fp","sni","alpn"} and all(len(x) == 1 for x in query.values())
    assert query["peer"] == [uri.hostname] and query["sni"] == [uri.hostname]
    assert query["fp"] == ["chrome"] and query["alpn"] == ["http/1.1"]
    assert urllib.parse.unquote(uri.fragment) == ports[uri.port][1]
    return uri, identity, query
sample = urllib.parse.urlsplit(lines[0])
for invalid in (sample._replace(scheme="vless").geturl(),
                sample._replace(netloc=f"{sample.username}:extra@{sample.hostname}:{sample.port}").geturl(),
                sample._replace(query=sample.query+"&sni=").geturl(),
                sample._replace(query=sample.query.replace("fp=chrome", "fp=firefox")).geturl(),
                sample._replace(query=sample.query+"&insecure=1").geturl()):
    try:
        parse(invalid)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid Trojan URI accepted")
def append(uri, identity, query, wrong=False):
    service, name = ports[uri.port]
    for family, endpoint in zip((4,6), endpoints[service]):
        tag = name+"-v"+str(family)+("-wrong" if wrong else "")
        port = 2081 + len(config["inbounds"])
        config["inbounds"].append({"type":"socks","tag":"socks-"+tag,
                                   "listen":"0.0.0.0","listen_port":port})
        config["outbounds"].append({"type":"trojan","tag":tag,"server":endpoint,
                                    "server_port":uri.port,"password":("wrong-"+identity if wrong else identity),
                                    "tls":{"enabled":True,"server_name":query["sni"][0],
                                           "alpn":query["alpn"],"utls":{"enabled":True,"fingerprint":query["fp"][0]},
                                           "certificate_path":"/etc/padm/client/ca.crt"}})
        config["route"]["rules"].append({"inbound":["socks-"+tag],"action":"route","outbound":tag})
seen = set()
for line in lines:
    uri, identity, query = parse(line)
    assert uri.port not in seen
    seen.add(uri.port)
    append(uri, identity, query)
assert seen == set(ports)
for line in lines:
    append(*parse(line), wrong=True)
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
PY
chmod 0640 "${TEST_ROOT}/runtime/client/config.json"
chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
tar -cpf - -C "${TEST_ROOT}" runtime/client |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
compose run --rm --no-deps --pull never client check -c /etc/padm/client/config.json >/dev/null
compose up -d --pull never client
client=$(compose ps -q client)
docker inspect "${client}" | jq -e --arg image "${SING_ID}" '
  .[0] | .State.Running and .Config.Image == $image and .Config.User == "10001:10001" and
  .HostConfig.ReadonlyRootfs and .HostConfig.Init and .HostConfig.CapDrop == ["ALL"] and
  (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null)
' >/dev/null
probe() {
    docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
        --network "${project}" --label "io.padm.test=${project}" \
        --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import ipaddress
import json
import socket
import struct
import sys
import time
import urllib.request

phase = sys.argv[1]
assert phase in ("allow", "deny")
proof = b"padm-trojan-real-proof\n"
def read(sock, size):
    data = b""
    while len(data) < size:
        part = sock.recv(size-len(data))
        if not part:
            raise EOFError()
        data += part
    return data
def address(sock, atyp):
    if atyp == 1:
        return socket.inet_ntop(socket.AF_INET, read(sock, 4))
    if atyp == 4:
        return socket.inet_ntop(socket.AF_INET6, read(sock, 16))
    if atyp == 3:
        return read(sock, read(sock, 1)[0]).decode()
    raise AssertionError("invalid SOCKS address")
def connect(port, command):
    deadline = time.monotonic()+10
    while True:
        try:
            sock = socket.create_connection(("client", port), timeout=0.2)
            break
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)
    sock.settimeout(4)
    try:
        sock.sendall(b"\x05\x01\x00")
        assert read(sock, 2) == b"\x05\x00"
        if command == 1:
            name = b"origin"
            destination = b"\x03"+bytes([len(name)])+name+struct.pack("!H", 8088)
        else:
            destination = b"\x01"+b"\x00"*6
        sock.sendall(b"\x05"+bytes([command])+b"\x00"+destination)
        header = read(sock, 4)
        assert header[0] == 5 and header[2] == 0
        host = address(sock, header[3])
        relay_port = struct.unpack("!H", read(sock, 2))[0]
        if header[1] != 0:
            raise ConnectionRefusedError()
        return sock, host, relay_port
    except BaseException:
        sock.close()
        raise
def tcp(port):
    sock, _, _ = connect(port, 1)
    with sock:
        sock.sendall(b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
        response = b""
        while True:
            data = sock.recv(4096)
            if not data:
                break
            response += data
    head, body = response.split(b"\r\n\r\n", 1)
    return (head.startswith(b"HTTP/1.0 200") or head.startswith(b"HTTP/1.1 200")) and body == proof
def udp(port):
    control, host, relay_port = connect(port, 3)
    with control:
        if ipaddress.ip_address(host).is_unspecified:
            host = control.getpeername()[0]
        family = socket.AF_INET6 if ipaddress.ip_address(host).version == 6 else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as sock:
            sock.settimeout(4)
            sock.bind(("::" if family == socket.AF_INET6 else "0.0.0.0", 0))
            target = socket.inet_aton(socket.gethostbyname("origin"))
            payload = proof+str(port).encode()+b"-"+phase.encode()
            sock.sendto(b"\x00\x00\x00\x01"+target+struct.pack("!H", 8089)+payload, (host, relay_port))
            response, _ = sock.recvfrom(65535)
            assert response[:3] == b"\x00\x00\x00"
            atyp = response[3]
            offset = {1:8, 4:20}.get(atyp)
            if atyp == 3:
                offset = 5+response[4]
            assert offset is not None
            return response[offset+2:] == payload
def counts():
    return json.loads(urllib.request.urlopen("http://origin:8088/counts", timeout=5).read())
def check(item):
    port, transport = item
    expected = phase == "allow" and port < 2085
    try:
        accepted = (tcp if transport == "tcp" else udp)(port)
    except (OSError, EOFError, ValueError):
        accepted = False
    assert accepted == expected, (phase, port, transport, accepted)
    return str(port)+"/"+transport
before = counts()
items = [(port, transport) for port in range(2081,2089) for transport in ("tcp","udp")]
with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
    results = list(pool.map(check, items))
after = counts()
expected_delta = 4 if phase == "allow" else 0
assert {key:after[key]-before[key] for key in before} == {"tcp":expected_delta,"udp":expected_delta}
print("docker-trojan-real-probe-ok: phase="+phase+" source=protocol-links cores=xray,sing-box"+
      " family=ipv4,ipv6 tls=alpn-http11 socks="+",".join(results))
' "$1"
}
# 只适配隔离卷与网络；额度状态、配置验证、重启和恢复仍走生产函数。
dockerComposeRun() {
    local action=$1 core
    shift
    if [[ "${action}" == run || "${action}" == restart ]]; then
        for core in xray sing-box; do
            cp -a "${PADM_DOCKER_INSTALL_DIR}/config/${core}/." "${TEST_ROOT}/runtime/config/${core}/"
        done
        tar -cpf - -C "${TEST_ROOT}" runtime/config |
            docker run --rm --init -i --pull=never --label "io.padm.test=${project}" --user 0 \
                --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
    fi
    case "${action}" in
    run|up) compose "${action}" --pull never "$@" ;;
    *) compose "${action}" "$@" ;;
    esac
}
dockerTrafficContainerState() {
    local container
    container=$(compose ps -q "$1")
    [[ "${container}" =~ ^[a-f0-9]{12,64}$ ]]
    docker inspect "${container}" |
        jq -ce --arg core "$1" --arg project "${project}" '
          .[0] | select(.State.Running and .State.Pid > 1 and
            .Config.Labels["com.docker.compose.project"] == $project and
            .Config.Labels["com.docker.compose.service"] == $core) |
          {id:.Id,started_at:.State.StartedAt,pid:.State.Pid}'
}
dockerTrafficQuery() (
    if [[ "$1" == xray ]]; then
        dockerComposeRun exec -T xray /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern user
        exit
    fi
    [[ "$1" == sing-box ]]
    local container
    container=$(compose ps -q sing-box)
    printf '\000\000\000\000\000' >"${TEST_ROOT}/request.bin"
    if ! docker run --rm --init -i --pull=never --read-only --cap-drop ALL \
        --network "container:${container}" --label "io.padm.test=${project}" \
        --entrypoint curl "${CURL_ID}" -fsS --http2-prior-knowledge --noproxy '*' \
        --connect-timeout 2 --max-time 5 -D /dev/stderr \
        -H 'Content-Type: application/grpc' -H 'TE: trailers' --data-binary @- --output - \
        http://127.0.0.1:10087/v2ray.core.app.stats.command.StatsService/QueryStats \
        <"${TEST_ROOT}/request.bin" >"${TEST_ROOT}/response.bin" 2>"${TEST_ROOT}/headers"; then
        cat "${TEST_ROOT}/headers" >&2
        exit 1
    fi
    awk '{sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1} END {exit !ok}' "${TEST_ROOT}/headers"
    singBoxGrpcResponseToStatsJson "${TEST_ROOT}/response.bin"
)
probe allow
# exec -T 不得消费统计循环下一行；同时用真实查询覆盖两核计数。
queried_cores=()
while IFS= read -r core; do
    stats=$(dockerTrafficQuery "${core}")
    jq -e --arg uuid "${UUID}" '
      def positive($direction):
        [.stat[]? | select(.name == ("user>>>"+$uuid+">>>traffic>>>"+$direction)) | (.value|tonumber)] |
        length == 1 and .[0] > 0;
      positive("uplink") and positive("downlink")' <<<"${stats}" >/dev/null
    printf 'docker-trojan-real-stats-ok: core=%s identity=%s counters=%s\n' "${core}" "${UUID}" "${stats}"
    queried_cores+=("${core}")
done <<< $'xray\nsing-box'
[[ "${queried_cores[*]}" == 'xray sing-box' ]]
dockerTrafficSetLimit "${UUID}" 1
for core in xray sing-box; do
    jq -e --arg core "${core}" '
      if $core == "xray" then
        all(.inbounds[] | select(.protocol == "trojan"); .settings.clients == [])
      else all(.inbounds[] | select(.type == "trojan"); .users == []) end' \
        "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null
done
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/"{xray,sing-box}/users.base)" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe deny
dockerTrafficSetLimit "${UUID}" 0
for core in xray sing-box; do
    jq -e --arg core "${core}" --arg uuid "${UUID}" '
      if $core == "xray" then
        any(.inbounds[]; .protocol == "trojan" and .settings.clients == [{email:$uuid,password:$uuid}])
      else any(.inbounds[]; .type == "trojan" and .users == [{name:$uuid,password:$uuid}]) end' \
        "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null
done
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/"{xray,sing-box}/users.base)" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe allow
dockerTrafficSnapshot
jq -e --arg uuid "${UUID}" '
  (.accounts | keys) == [$uuid] and
  (.accounts[$uuid] | .upload > 0 and .download > 0 and .limit_bytes == 0 and
    (.baseline | keys | sort) == ["sing-box","xray"])' \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" >/dev/null
printf 'docker-trojan-real-ok: endpoint=isolated-compose quota=deny-restore family=ipv4,ipv6 xray=%s sing-box=%s ops=%s curl=%s\n' \
    "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"
