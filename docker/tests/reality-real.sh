#!/usr/bin/env bash
set -euo pipefail

# 只在本次唯一项目与命名卷中验收，不连接或覆盖现有 padm 部署。
[[ "$#" == 3 ]] || { printf 'usage: reality-real.sh <local-xray> <local-sing-box> <local-ops>\n' >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'reality-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3
for tool in docker jq python3 sha256sum tar curl; do command -v "${tool}" >/dev/null; done
# 不接受缺失镜像或隐式拉取，所有容器固定到本机 inspect 得到的不可变 image ID。
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-reality-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-reality-real.XXXXXX")
cleanup() {
    local status=$? ids
    trap - EXIT
    ids=$(docker ps -aq --filter "label=io.padm.test=${project}")
    if [[ -n "${ids}" ]]; then
        if [[ "${status}" != 0 ]]; then
            while IFS= read -r id; do docker logs "${id}" >&2 || true; done <<<"${ids}"
        fi
        docker rm -f ${ids} >/dev/null || status=1
    fi
    if docker network inspect "${project}" >/dev/null 2>&1; then
        docker network rm "${project}" >/dev/null || status=1
    fi
    docker volume rm "${volume}" >/dev/null || status=1
    rm -rf -- "${TEST_ROOT}"
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
SPEC="${TEST_ROOT}/spec.json"
UUID=11111111-1111-4111-8111-111111111111
PUBLIC_KEY=hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
PRIVATE_KEY=dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo
jq -n --arg uuid "${UUID}" --arg public "${PUBLIC_KEY}" --arg private "${PRIVATE_KEY}" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  def reality: {server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
    private_key:$private,public_key:$public,short_id:"6ba85179e30d4fc2"};
  {schema_version:3,
   release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"xray",secondary_type:"sing-box",protocols:[
     {id:2,listener_id:"entry-xhttp",core:"xray",server:"proxy.padm.test",public_port:35451,
      address_families:["ipv4","ipv6"],name:"real-xhttp",uuid:$uuid,reality:reality,
      xhttp:{path:"/padm-xhttp",host:"www.debian.org",mode:"auto"}},
     {id:26,listener_id:"entry-grpc-xray",core:"xray",server:"proxy.padm.test",public_port:35452,
      address_families:["ipv4"],name:"real-grpc-xray",uuid:$uuid,reality:reality,
      grpc:{service_name:"padm-grpc-xray"}},
     {id:26,listener_id:"entry-grpc-sing",core:"sing-box",server:"proxy.padm.test",public_port:35453,
      address_families:["ipv4"],name:"real-grpc-sing",uuid:$uuid,reality:reality,
      grpc:{service_name:"padm-grpc-sing"}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${candidate}"
cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerCleanupConfigurationCandidate
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 3 ]]
# 客户端只从 URI 取得协议参数，规格不参与生成；仅公开端点映射到隔离服务名。
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}" <<'PY'
import json
import pathlib
import sys
import urllib.parse

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
out = pathlib.Path(sys.argv[2])
xray = {"log":{"loglevel":"warning"}, "inbounds":[], "outbounds":[]}
sing = {"log":{"level":"warn"}, "inbounds":[], "outbounds":[],
        "route":{"rules":[]}}
def parse(line):
    uri = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    assert uri.scheme == "vless" and uri.username and uri.password is None and uri.hostname == "proxy.padm.test"
    required = {"encryption","security","sni","fp","pbk","sid","type"}
    if q.get("type") == ["xhttp"]:
        required |= {"path","host","mode"}
    elif q.get("type") == ["grpc"]:
        required |= {"path","serviceName","alpn"}
    else:
        raise ValueError("unknown transport")
    assert set(q) == required and all(len(v) == 1 and v[0] for v in q.values()), q
    q = {k:v[0] for k,v in q.items()}
    assert q["encryption"] == "none" and q["security"] == "reality" and "flow" not in q
    if q["type"] == "grpc":
        assert q["alpn"] == "h2" and q["path"] == q["serviceName"]
    return uri, q
sample = urllib.parse.urlsplit(lines[0])
for invalid in (sample._replace(scheme="trojan").geturl(),
                sample._replace(query=sample.query+"&flow=xtls-rprx-vision").geturl(),
                sample._replace(query=sample.query+"&sni=").geturl()):
    try:
        parse(invalid)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid URI accepted")
for line in lines:
    uri,q = parse(line)
    if q["type"] == "xhttp":
        assert uri.port == 35451 and q["mode"] == "auto"
        xray["inbounds"].append({"listen":"0.0.0.0","port":2081,"protocol":"socks","settings":{"auth":"noauth","udp":False}})
        xray["outbounds"].append({"protocol":"vless","settings":{"vnext":[{
            "address":"xray","port":uri.port,"users":[{"id":uri.username,"encryption":q["encryption"]}]}]},
            "streamSettings":{"network":q["type"],"security":q["security"],
                "realitySettings":{"serverName":q["sni"],"fingerprint":q["fp"],
                                   "publicKey":q["pbk"],"shortId":q["sid"]},
                "xhttpSettings":{"path":q["path"],"host":q["host"],"mode":q["mode"]}}})
    else:
        port = {35452:2082,35453:2083}[uri.port]
        host = {35452:"xray",35453:"sing-box"}[uri.port]
        tag = "grpc-"+str(port)
        sing["inbounds"].append({"type":"socks","tag":"socks-"+tag,"listen":"0.0.0.0","listen_port":port})
        sing["outbounds"].append({"type":"vless","tag":tag,"server":host,"server_port":uri.port,"uuid":uri.username,
            "tls":{"enabled":True,"server_name":q["sni"],"alpn":[q["alpn"]],
                   "utls":{"enabled":True,"fingerprint":q["fp"]},
                   "reality":{"enabled":True,"public_key":q["pbk"],"short_id":q["sid"]}},
            "transport":{"type":q["type"],"service_name":q["serviceName"]}})
        sing["route"]["rules"].append({"inbound":["socks-"+tag],"action":"route","outbound":tag})
assert len(xray["outbounds"]) == 1 and len(sing["outbounds"]) == 2
(out/"client-xray.json").write_text(json.dumps(xray))
(out/"client-sing.json").write_text(json.dumps(sing))
PY
mkdir -p "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/client-xray.json" "${TEST_ROOT}/runtime/client/xray.json"
cp "${TEST_ROOT}/client-sing.json" "${TEST_ROOT}/runtime/client/sing.json"
printf 'padm-reality-real-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
# docker cp 到停止容器可能重写归属；tar 流保持生产夹具的 UID/GID 和权限模式。
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" \
    --arg sing "${SING_ID}" --arg ops "${OPS_ID}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services |= with_entries(
    .value.image = (if .key == "xray" then $xray else $sing end) |
    .value.ports = [] | .value.labels["io.padm.test"] = $project |
    .value.volumes |= map(.source as $source |
      .type = "volume" | .source = "files" |
      .volume = {nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} |
      del(.bind))) |
  .services.origin = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
    entrypoint:["python3","-m","http.server","8088","--bind","0.0.0.0","--directory","/srv"],
    labels:{"io.padm.test":$project},
    volumes:[{type:"volume",source:"files",target:"/srv",read_only:true,
      volume:{nocopy:true,subpath:"runtime/origin"}}]} |
  .services["client-xray"] = {image:$xray,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/xray.json"],
    volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]} |
  .services["client-sing"] = {image:$sing,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    command:["run","-c","/etc/padm/client/sing.json"],
    volumes:[{type:"volume",source:"files",target:"/etc/padm/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]}
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() {
    docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"
}
compose config --format json >/dev/null
compose run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null
compose run --rm --no-deps sing-box check -c /etc/padm/sing-box/config.json >/dev/null
compose run --rm --no-deps client-xray -test -c /etc/padm/client/xray.json >/dev/null
compose run --rm --no-deps client-sing check -c /etc/padm/client/sing.json >/dev/null
compose up -d --pull never --wait --wait-timeout 60 xray sing-box origin
compose up -d --pull never client-xray client-sing
# 只等待 SOCKS 监听，然后每条 URI 执行一次真正请求，不用重试掩盖握手错误。
docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
    --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import socket
import struct
import time

def probe(endpoint):
    host,port = endpoint
    deadline = time.monotonic()+10
    while True:
        try:
            sock=socket.create_connection((host,port),timeout=0.2)
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
        assert header[0:2]==b"\x05\x00", (endpoint,header)
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
        assert body==b"padm-reality-real-proof\n", response
    return "%s:%s"%(host,port)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    results=list(pool.map(probe,(("client-xray",2081),("client-sing",2082),("client-sing",2083))))
print("docker-reality-real-probe-ok: source=protocol-links socks="+",".join(results))
'
printf 'docker-reality-real-ok: target=www.debian.org endpoint=isolated-compose xray=%s sing-box=%s ops=%s\n' \
    "${XRAY_ID}" "${SING_ID}" "${OPS_ID}"
