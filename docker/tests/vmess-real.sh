#!/usr/bin/env bash
set -euo pipefail
umask 077

# 仅使用隔离项目、网络和命名卷，传统 TLS 传输复用同一验证流程。
[[ "$#" == 4 || "$#" == 6 ]] || {
    printf 'usage: vmess-real.sh <local-xray> <local-sing-box> <local-ops> <local-nginx> [22|23|24|25|27|29 xray|sing-box]\n' >&2
    exit 2
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || { printf 'vmess-real.sh requires Linux root\n' >&2; exit 1; }
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3 NGINX_REF=$4
PROTOCOL=${5:-22} CORE=${6:-xray}
[[ "${PROTOCOL}:${CORE}" == 22:xray || "${PROTOCOL}:${CORE}" == 23:xray ||
    "${PROTOCOL}:${CORE}" == 23:sing-box || "${PROTOCOL}:${CORE}" == 24:xray ||
    "${PROTOCOL}:${CORE}" == 25:xray || "${PROTOCOL}:${CORE}" == 27:xray ||
    "${PROTOCOL}:${CORE}" == 29:xray ]] || exit 2
TRANSPORT=ws TRANSPORT_KEY=websocket BACKEND_PORT=31297 TEST_NAME=vmess-real APP_PROTOCOL=vmess
case "${PROTOCOL}" in
23) TRANSPORT=httpupgrade TRANSPORT_KEY=httpupgrade BACKEND_PORT=31306 TEST_NAME=httpupgrade-real ;;
24) TRANSPORT=grpc TRANSPORT_KEY=grpc_tls BACKEND_PORT=31301 TEST_NAME=vless-grpc-tls-real APP_PROTOCOL=vless ;;
25) TRANSPORT=grpc TRANSPORT_KEY=grpc_tls BACKEND_PORT=31304 TEST_NAME=trojan-grpc-tls-real APP_PROTOCOL=trojan ;;
27) TRANSPORT=tcp TRANSPORT_KEY=fallback_tls BACKEND_PORT=35468 TEST_NAME=vless-tls-vision-real APP_PROTOCOL=vless ;;
29) TRANSPORT=tcp TRANSPORT_KEY=fallback_tls BACKEND_PORT=35468 TEST_NAME=trojan-tls-fallback-real APP_PROTOCOL=trojan ;;
esac
for tool in docker jq python3 sha256sum tar openssl awk; do command -v "${tool}" >/dev/null; done
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
NGINX_ID=$(docker image inspect --format '{{.Id}}' "${NGINX_REF}")
CURL_ID=
if [[ "${CORE}" == sing-box || "${TRANSPORT}" == tcp ]]; then
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
    --arg key "${TRANSPORT_KEY}" --argjson protocol "${PROTOCOL}" --argjson backend "${BACKEND_PORT}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:$core,secondary_type:null,protocols:[
     {id:$protocol,listener_id:"entry-vmess",core:$core,server:$domain,public_port:35468,
      address_families:["ipv4","ipv6"],name:$name,uuid:$uuid,
      ($key):(if $protocol == 27 or $protocol == 29 then {domain:$domain,http_port:31300,http2_port:31302}
        else {domain:$domain,backend_port:$backend,tls_port:8443} +
          if $protocol == 24 or $protocol == 25 then {service_name:"padm_grpc-1"} else {path:"padmvmess"} end
        end)}]},
   tls:{domain:$domain},subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${candidate}"
jq -e --arg uuid "${UUID}" --arg core "${CORE}" --arg transport "${TRANSPORT}" \
    --arg domain "${DOMAIN}" --argjson backend "${BACKEND_PORT}" --arg app "${APP_PROTOCOL}" '
  if $core == "xray" then any(.inbounds[]; .protocol == $app and .tag == "entry-vmess" and .port == $backend and
    .settings == ((if $app == "trojan" then {clients:[{password:$uuid,email:$uuid}]}
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
        elif $transport == "grpc" then {grpcSettings:{serviceName:"padm_grpc-1"}}
        else {httpupgradeSettings:{path:"/padmvmess",host:$domain}} end end))
  else any(.inbounds[]; .type == "vmess" and .tag == "entry-vmess" and .listen_port == $backend and
    .users == [{uuid:$uuid,name:$uuid,alterId:0}] and
    .transport == {type:"httpupgrade",path:"/padmvmess",host:$domain}) end' \
    "${candidate}/config/${CORE}/config.json" >/dev/null
if [[ "${TRANSPORT}" == grpc ]]; then
    grep -qF 'http2 on;' "${candidate}/config/nginx/default.conf"
    grep -qF 'location ^~ /padm_grpc-1/ {' "${candidate}/config/nginx/default.conf"
    grep -qF "grpc_pass grpc://xray:${BACKEND_PORT};" "${candidate}/config/nginx/default.conf"
fi
jq -e --arg transport "${TRANSPORT}" '.listeners == [{listener_id:"entry-vmess",
  service:(if $transport == "tcp" then "xray" else "nginx" end),public_port:35468,
  container_port:(if $transport == "tcp" then 35468 else 8443 end),transport:"tcp",address_families:["ipv4","ipv6"]}]' \
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
dockerTrafficAccounts "${CORE}" | jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' >/dev/null
for file in config.json users.base; do
    [[ "$(stat -c '%u:%g:%a' "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/${file}")" == 0:10001:640 ]]
done
base_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base")
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 1 ]]
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
    --arg sing "${SING_ID}" --arg ops "${OPS_ID}" --arg nginx "${NGINX_ID}" --arg subnet "${subnet}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  .networks.default.enable_ipv6 = true | .networks.default.ipam = {config:[{subnet:$subnet}]} |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services[$core].image = (if $core == "xray" then $xray else $sing end) | .services.nginx.image = $nginx |
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
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" "${TRANSPORT}" "${TEST_NAME}" "${DOMAIN}" "${APP_PROTOCOL}" <<'PY'
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
assert len(lines) == 1 and [ipaddress.ip_address(x).version for x in endpoints] == [4, 6]
def parse(line):
    if transport in ("grpc","tcp"):
        uri = urllib.parse.urlsplit(line)
        pairs = urllib.parse.parse_qsl(uri.query, keep_blank_values=True)
        query = dict(pairs)
        if transport == "tcp":
            expected = ({"encryption":"none","flow":"xtls-rprx-vision","security":"tls","sni":domain,
                         "fp":"chrome"} if app == "vless" else
                        {"peer":domain,"security":"tls","fp":"chrome","sni":domain})
            expected.update(alpn="h2,http/1.1",type="tcp")
        else:
            expected = ({"encryption":"none","security":"tls","sni":domain} if app == "vless" else
                        {"peer":domain,"fp":"chrome","sni":domain})
            expected.update(type="grpc", alpn="h2", serviceName="padm_grpc-1")
        assert uri.scheme == app and uri.username == "11111111-1111-4111-8111-111111111111"
        assert uri.password is None and uri.hostname == domain and uri.port == 35468 and not uri.path
        assert urllib.parse.unquote(uri.fragment) == name
        assert pairs == list(expected.items())
        assert str(uuid.UUID(uri.username)) == uri.username
        return dict(query,id=uri.username,service=query.get("serviceName"),flow=query.get("flow"))
    assert line.startswith("vmess://") and "#" not in line and "?" not in line
    payload = line.removeprefix("vmess://")
    raw = base64.b64decode(payload, validate=True)
    assert base64.b64encode(raw).decode() == payload
    value = json.loads(raw)
    assert list(value) == ["v","ps","add","port","id","aid","scy","net","type","host","path","tls","sni"]
    assert raw.decode() == json.dumps(value, separators=(",", ":"), ensure_ascii=False)
    assert value == {"v":"2","ps":name,"add":domain,"port":"35468",
                     "id":"11111111-1111-4111-8111-111111111111","aid":"0","scy":"auto","net":transport,
                     "type":"none","host":domain,"path":"/padmvmess"+("ws" if transport == "ws" else ""),
                     "tls":"tls","sni":domain}
    assert str(uuid.UUID(value["id"])) == value["id"]
    return value
value = parse(lines[0])
if transport in ("grpc","tcp"):
    sample = urllib.parse.urlsplit(lines[0])
    invalids = []
    fields = (("alpn","http/1.1"),("type","ws"),("sni","wrong.test"))
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
for wrong in (False, True):
    for family, endpoint in zip((4,6), endpoints):
        tag = "vmess-v"+str(family)+("-wrong" if wrong else "")
        port = 2081+len(config["inbounds"])
        config["inbounds"].append({"type":"socks","tag":"socks-"+tag,"listen":"0.0.0.0","listen_port":port})
        outbound = {"type":app,"tag":tag,"server":endpoint,"server_port":35468 if transport == "tcp" else 8443,
            ("password" if app == "trojan" else "uuid"):
                ("22222222-2222-4222-8222-222222222222" if wrong else value["id"]),
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
            outbound.update(security=value["scy"], alter_id=int(value["aid"]),
                transport=dict({"type":value["net"],"path":value["path"]},
                    **({"headers":{"Host":value["host"]}} if transport == "ws" else {"host":value["host"]})))
        config["outbounds"].append(outbound)
        config["route"]["rules"].append({"inbound":["socks-"+tag],"action":"route","outbound":tag})
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
PY
chmod 0640 "${TEST_ROOT}/runtime/client/config.json"
chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
tar -cpf - -C "${TEST_ROOT}" runtime/client |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
compose run --rm --no-deps client check -c /etc/padm/client/config.json >/dev/null
compose up -d --pull never client
client=$(compose ps -q client)
fallbackProbe() {
    [[ "${TRANSPORT}" == tcp ]] || return 0
    local body=${1:-$'padm-fallback-static-proof\n'} endpoint authority option version response actual clientAddress
    while IFS= read -r endpoint; do
        authority=${endpoint}; [[ "${endpoint}" != *:* ]] || authority="[${endpoint}]"
        for option in --http1.1 --http2; do
            version=1.1; [[ "${option}" != --http2 ]] || version=2
            response=$(docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
                --network "${project}" --label "io.padm.test=${project}" \
                --mount "type=volume,source=${volume},target=/etc/padm/client,readonly,volume-subpath=runtime/client" \
                --entrypoint curl "${CURL_ID}" --fail --silent --show-error --noproxy '*' \
                --connect-timeout 2 --max-time 5 "${option}" --cacert /etc/padm/client/ca.crt \
                --resolve "${DOMAIN}:35468:${authority}" --write-out '%{http_version}\n%{local_ip}' \
                "https://${DOMAIN}:35468/?padm-proxy-proof")
            clientAddress=${response##*$'\n'}
            response=${response%$'\n'*}
            [[ "${response}" == "${body}${version}" ]] || {
                printf 'fallback content or ALPN mismatch: endpoint=%s option=%s response=%s\n' \
                    "${endpoint}" "${option}" "${response}" >&2
                return 1
            }
            jq -e --arg address "${clientAddress}" 'index($address) == null' <<<"${addresses}" >/dev/null
            compose exec -T nginx cat /var/log/nginx/access.log |
                awk -v address="${clientAddress}" '$1 == address && /GET \/\?padm-proxy-proof / {found=1}
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
    printf 'docker-%s-fallback-ok: alpn=h2,http/1.1 family=ipv4,ipv6 strict-ca-sni missing=404 proxy-source=client\n' "${TEST_NAME}"
}
probe() {
    docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
        --network "${project}" --label "io.padm.test=${project}" --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import ipaddress
import json
import socket
import struct
import sys
import time
import urllib.request

phase = sys.argv[1]
test_name, core, transport_name = sys.argv[2:5]
assert phase in ("allow","deny")
proof = b"padm-vmess-real-proof\n"
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
        except OSError:
            if time.monotonic() >= deadline: raise
            time.sleep(0.05)
    sock.settimeout(4)
    try:
        sock.sendall(b"\x05\x01\x00")
        assert read(sock,2) == b"\x05\x00"
        name = b"origin"
        destination = b"\x03"+bytes([len(name)])+name+struct.pack("!H",8088) if command == 1 else b"\x01"+b"\x00"*6
        sock.sendall(b"\x05"+bytes([command])+b"\x00"+destination)
        header = read(sock,4)
        assert header[0] == 5 and header[2] == 0
        host = address(sock,header[3])
        relay_port = struct.unpack("!H",read(sock,2))[0]
        if header[1] != 0: raise ConnectionRefusedError()
        return sock,host,relay_port
    except BaseException:
        sock.close()
        raise
def tcp(port):
    sock,_,_ = connect(port,1)
    with sock:
        sock.sendall(b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
        response = b""
        while True:
            data = sock.recv(4096)
            if not data: break
            response += data
    head,body = response.split(b"\r\n\r\n",1)
    return (head.startswith(b"HTTP/1.0 200") or head.startswith(b"HTTP/1.1 200")) and body == proof
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
            return response[offset+2:] == payload
def counts():
    return json.loads(urllib.request.urlopen("http://origin:8088/counts",timeout=5).read())
def check(item):
    port,transport = item
    expected = phase == "allow" and port < 2083
    try: accepted = (tcp if transport == "tcp" else udp)(port)
    except (OSError,EOFError,ValueError): accepted = False
    assert accepted == expected,(phase,port,transport,accepted)
    return str(port)+"/"+transport
before = counts()
items = [(port,transport) for port in range(2081,2085) for transport in ("tcp","udp")]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(check,items))
after = counts()
expected_delta = 2 if phase == "allow" else 0
assert {key:after[key]-before[key] for key in before} == {"tcp":expected_delta,"udp":expected_delta}
print("docker-"+test_name+"-probe-ok: core="+core+" phase="+phase+" source=protocol-links tls="+
      (core if transport_name == "tcp" else "nginx")+"-"+
      transport_name+" family=ipv4,ipv6 socks="+",".join(results))
' "$1" "${TEST_NAME}" "${CORE}" "${TRANSPORT}"
}
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
