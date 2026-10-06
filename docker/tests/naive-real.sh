#!/usr/bin/env bash
set -euo pipefail

# 只在本次唯一项目与命名卷中验收，不连接或覆盖现有 padm 部署。
[[ "$#" == 4 ]] || { printf 'usage: naive-real.sh <local-xray> <local-sing-box> <local-ops> <local-curl>\n' >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'naive-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3 CURL_REF=$4
for tool in docker jq python3 sha256sum tar openssl od awk; do command -v "${tool}" >/dev/null; done
# 不接受缺失镜像或隐式拉取，所有容器固定到本机 inspect 得到的不可变 image ID。
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
CURL_ID=$(docker image inspect --format '{{.Id}}' "${CURL_REF}")
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-naive-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
subnet=$(printf 'fd42:7061:646d:%x::/64' "${RANDOM}")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-naive-real.XXXXXX")
cleanup() {
    local status=$? ids cleanup_failed=0
    trap - EXIT
    ids=$(docker ps -aq --filter "label=io.padm.test=${project}")
    if [[ -n "${ids}" ]]; then
        if [[ "${status}" != 0 ]]; then
            while IFS= read -r id; do
                docker logs "${id}" >&2 || true
                docker inspect --format '{{.Name}} {{json .State}}' "${id}" >&2 || true
            done <<<"${ids}"
        fi
        # Docker 仅输出十六进制容器 ID，此处分词用于一次清理本次项目。
        # shellcheck disable=SC2086
        docker rm -f ${ids} >/dev/null || cleanup_failed=1
    fi
    # 标签不符的同名资源不属于本次验收，不能删除。
    if docker network inspect "${project}" >/dev/null 2>&1; then
        if docker network inspect "${project}" |
            jq -e --arg project "${project}" '.[0].Labels["io.padm.test"] == $project' >/dev/null; then
            docker network rm "${project}" >/dev/null || cleanup_failed=1
        else
            cleanup_failed=1
        fi
    fi
    if docker volume inspect "${volume}" >/dev/null 2>&1; then
        if docker volume inspect "${volume}" |
            jq -e --arg project "${project}" '.[0].Labels["io.padm.test"] == $project' >/dev/null; then
            docker volume rm "${volume}" >/dev/null || cleanup_failed=1
        else
            cleanup_failed=1
        fi
    fi
    if [[ "${cleanup_failed}" == 0 ]]; then
        rm -rf -- "${TEST_ROOT}"
    else
        printf 'naive-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2
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
DOMAIN=naive.padm.test
UUID=11111111-1111-4111-8111-111111111111
TLS_DIR="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
mkdir -p "${TEST_ROOT}/certs" "${TLS_DIR}" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-naive-test-ca \
    -addext basicConstraints=critical,CA:TRUE -addext keyUsage=critical,keyCertSign,cRLSign \
    -keyout "${TEST_ROOT}/certs/ca.key" -out "${TEST_ROOT}/certs/ca.crt" >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${TLS_DIR}/${DOMAIN}.key" -out "${TEST_ROOT}/certs/server.csr" >/dev/null 2>&1
printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\n' "${DOMAIN}" >"${TEST_ROOT}/certs/extensions"
openssl x509 -req -in "${TEST_ROOT}/certs/server.csr" -days 1 -set_serial 1 \
    -CA "${TEST_ROOT}/certs/ca.crt" -CAkey "${TEST_ROOT}/certs/ca.key" \
    -extfile "${TEST_ROOT}/certs/extensions" -out "${TLS_DIR}/${DOMAIN}.crt" >/dev/null 2>&1
openssl verify -CAfile "${TEST_ROOT}/certs/ca.crt" "${TLS_DIR}/${DOMAIN}.crt" >/dev/null
chmod 0600 "${TEST_ROOT}/certs/ca.key" "${TLS_DIR}/${DOMAIN}.key"
SPEC="${TEST_ROOT}/spec.json"
jq -n --arg uuid "${UUID}" --arg domain "${DOMAIN}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:5,listener_id:"entry-naive",core:"sing-box",server:$domain,public_port:35465,
     address_families:["ipv4","ipv6"],name:"entry-naive",uuid:$uuid,naive:{domain:$domain}}]},
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
  (.inbounds | length) == 1 and
  (.inbounds[0] | .type == "naive" and .listen == "::" and .listen_port == 35465 and
    .network == "tcp" and .users == [{username:$uuid,password:$uuid}] and
    .tls == {enabled:true,server_name:$domain,
      certificate_path:("/etc/padm/secrets/tls/"+$domain+".crt"),
      key_path:("/etc/padm/secrets/tls/"+$domain+".key")}) and
  .experimental.v2ray_api.stats.users == [$uuid]
' "${candidate}/config/sing-box/config.json" >/dev/null
jq -e '
  .services["sing-box"].ports | sort == ([
    "0.0.0.0:35465:35465/tcp","[::]:35465:35465/tcp"] | sort)
' "${candidate}/compose.json" >/dev/null
dockerDeploymentFileValidate "${candidate}/deployment.json"
jq -e '
  .core.type == "sing-box" and .core.secondary_type == null and .core.protocol_ids == [5] and
  (.listeners | length) == 1 and
  (.listeners[0] | .service == "sing-box" and .transport == "tcp" and
    .public_port == 35465 and .container_port == 35465 and .address_families == ["ipv4","ipv6"])
' "${candidate}/deployment.json" >/dev/null
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/sing-box/config.json")" == 0:10001:640 ]]
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/sing-box")" == 0:10001:750 ]]
[[ "$(stat -c '%u:%g:%a' "${candidate}/secrets/tls/${DOMAIN}.key")" == 10001:10001:600 ]]
cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerCleanupConfigurationCandidate
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerTrafficAccounts sing-box | jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' >/dev/null
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 1 ]]
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/certs/ca.crt" "${TEST_ROOT}/runtime/client/ca.crt"
printf 'padm-naive-real-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
chmod 0750 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
chmod 0640 "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/proof.txt"
chown 0:10001 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin" \
    "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/proof.txt"
# tar 流保持生产夹具的 UID/GID 和权限模式，不发布宿主端口。
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg sing "${SING_ID}" \
    --arg ops "${OPS_ID}" --arg subnet "${subnet}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  .networks.default.enable_ipv6 = true | .networks.default.ipam = {config:[{subnet:$subnet}]} |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services |= with_entries(
    .value.image = $sing | .value.ports = [] | .value.labels["io.padm.test"] = $project |
    .value.volumes |= map(.source as $source |
      .type = "volume" | .source = "files" |
      .volume = {nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} |
      del(.bind))) |
  .services.origin = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
    entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
      volume:{nocopy:true,subpath:"runtime/origin"}}]} |
  .services.client = {image:$sing,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/config.json"],
    volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]}
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() {
    docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"
}
compose config --format json >/dev/null
compose run --rm --no-deps --pull never sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null
compose up -d --pull never --wait --wait-timeout 60 sing-box origin
server=$(compose ps -q sing-box)
[[ "${server}" =~ ^[a-f0-9]{12,64}$ ]]
docker inspect "${server}" |
    jq -e --arg project "${project}" --arg image "${SING_ID}" '
      .[0] | .State.Running == true and .State.Health.Status == "healthy" and
      .Config.Labels["io.padm.test"] == $project and
      (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null) and .Config.Image == $image
    ' >/dev/null
addresses=$(docker inspect "${server}" |
    jq -cer --arg project "${project}" '.[0].NetworkSettings.Networks[$project] | [.IPAddress,.GlobalIPv6Address]')
# 客户端只从 URI 取得协议参数；地址映射不读 spec，分别强制 IPv4 与 IPv6。
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" <<'PY'
import ipaddress
import json
import pathlib
import sys
import urllib.parse
import uuid

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
endpoints = json.loads(sys.argv[3])
assert len(lines) == 1 and len(endpoints) == 2
assert [ipaddress.ip_address(endpoint).version for endpoint in endpoints] == [4, 6], endpoints

def parse(line):
    uri = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    assert uri.scheme == "naive+https" and uri.username and uri.password and uri.hostname == "naive.padm.test"
    username = urllib.parse.unquote(uri.username)
    password = urllib.parse.unquote(uri.password)
    assert str(uuid.UUID(username)) == username and password == username
    assert uri.port == 35465 and urllib.parse.unquote(uri.fragment) == "entry-naive"
    assert q == {"padding": ["true"]}, q
    return uri, username, password

sample = urllib.parse.urlsplit(lines[0])
for invalid in (sample._replace(scheme="naive+http").geturl(),
                sample._replace(query="padding=false").geturl(),
                sample._replace(query=sample.query+"&padding=true").geturl(),
                sample._replace(query=sample.query+"&insecure=1").geturl()):
    try:
        parse(invalid)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid URI accepted")
uri, username, password = parse(lines[0])
config = {"log":{"level":"warn"}, "inbounds":[], "outbounds":[], "route":{"rules":[]}}
for family, endpoint in zip((4, 6), endpoints):
    tag = "naive-v"+str(family)
    port = 2081 + len(config["inbounds"])
    config["inbounds"].append({"type":"socks", "tag":"socks-"+tag, "listen":"0.0.0.0", "listen_port":port})
    config["outbounds"].append({"type":"naive", "tag":tag, "server":endpoint, "server_port":uri.port,
                               "username":username, "password":password,
                               "tls":{"enabled":True, "server_name":uri.hostname,
                                      "certificate_path":"/etc/padm/client/ca.crt"}})
    config["route"]["rules"].append({"inbound":["socks-"+tag], "action":"route", "outbound":tag})
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
PY
chmod 0640 "${TEST_ROOT}/runtime/client/config.json"
chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
tar -cpf - -C "${TEST_ROOT}" runtime/client |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
compose run --rm --no-deps --pull never client check -c /etc/padm/client/config.json >/dev/null
compose up -d --pull never client
# ops 镜像不含 curl，复用 stdlib SOCKS 请求；只等待监听，不重试已发送的真实握手。
docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
    --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import socket
import struct
import time

def probe(port):
    deadline = time.monotonic()+10
    while True:
        try:
            sock = socket.create_connection(("client",port),timeout=0.2)
            break
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)
    with sock:
        sock.settimeout(20)
        def receive(n):
            data=b""
            while len(data)<n:
                part=sock.recv(n-len(data))
                if not part:
                    raise EOFError(data)
                data+=part
            return data
        sock.sendall(b"\x05\x01\x00")
        assert receive(2)==b"\x05\x00"
        name=b"origin"
        sock.sendall(b"\x05\x01\x00\x03"+bytes([len(name)])+name+struct.pack("!H",8088))
        header=receive(4)
        assert header[0:2]==b"\x05\x00", (port,header)
        if header[3]==1:
            receive(4)
        elif header[3]==4:
            receive(16)
        elif header[3]==3:
            receive(receive(1)[0])
        else:
            raise AssertionError(header)
        receive(2)
        sock.sendall(b"GET /proof.txt HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n")
        response=b""
        while True:
            part=sock.recv(4096)
            if not part:
                break
            response+=part
        head,body=response.split(b"\r\n\r\n",1)
        assert head.startswith(b"HTTP/1.0 200") or head.startswith(b"HTTP/1.1 200"), head
        assert body==b"padm-naive-real-proof\n", response
    return str(port)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results=list(pool.map(probe,range(2081,2083)))
print("docker-naive-real-probe-ok: source=protocol-links transport=tcp family=ipv4,ipv6 socks="+",".join(results))
'
# 共享服务端网络查询真实 gRPC，不依赖宿主 PID，也不修改生产统计监听地址。
printf '\000\000\000\000\000' >"${TEST_ROOT}/request.bin"
if ! docker run --rm -i --pull=never --read-only --cap-drop ALL \
    --network "container:${server}" --label "io.padm.test=${project}" \
    --entrypoint curl "${CURL_ID}" -fsS --http2-prior-knowledge --noproxy '*' \
    --connect-timeout 2 --max-time 5 -D /dev/stderr \
    -H 'Content-Type: application/grpc' -H 'TE: trailers' --data-binary @- --output - \
    http://127.0.0.1:10087/v2ray.core.app.stats.command.StatsService/QueryStats \
    <"${TEST_ROOT}/request.bin" >"${TEST_ROOT}/response.bin" 2>"${TEST_ROOT}/headers"; then
    cat "${TEST_ROOT}/headers" >&2
    exit 1
fi
awk '{sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1} END {exit !ok}' "${TEST_ROOT}/headers"
stats=$(singBoxGrpcResponseToStatsJson "${TEST_ROOT}/response.bin")
if ! jq -e --arg uuid "${UUID}" '
  def positive($direction):
    [.stat[]? | select(.name == ("user>>>"+$uuid+">>>traffic>>>"+$direction)) | .value] |
    length == 1 and (.[0] | type == "number" and . > 0);
  positive("uplink") and positive("downlink")
' <<<"${stats}" >/dev/null; then
    printf 'naive-real UUID traffic missing: %s\n' "${stats}" >&2
    exit 1
fi
printf 'docker-naive-real-stats-ok: identity=%s counters=%s\n' "${UUID}" "${stats}"
printf 'docker-naive-real-ok: endpoint=isolated-compose xray=%s sing-box=%s ops=%s curl=%s\n' \
    "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"
