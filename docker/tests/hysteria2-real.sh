#!/usr/bin/env bash
set -euo pipefail

# 只在本次唯一项目与命名卷中验收，不连接或覆盖现有 padm 部署。
[[ "$#" == 3 ]] || { printf 'usage: hysteria2-real.sh <local-xray> <local-sing-box> <local-ops>\n' >&2; exit 2; }
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'hysteria2-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3
HY2_SITES=${PADM_TEST_HY2_SITES:-0}
[[ "${HY2_SITES}" == 0 || "${HY2_SITES}" == 1 ]] || exit 2
for tool in docker jq python3 sha256sum tar openssl; do command -v "${tool}" >/dev/null; done
# 不接受缺失镜像或隐式拉取，所有容器固定到本机 inspect 得到的不可变 image ID。
XRAY_ID=$(docker image inspect --format '{{.Id}}' "${XRAY_REF}")
SING_ID=$(docker image inspect --format '{{.Id}}' "${SING_REF}")
OPS_ID=$(docker image inspect --format '{{.Id}}' "${OPS_REF}")
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
CURL_ID=
if [[ "${HY2_SITES}" == 1 ]]; then
    [[ -n "${PADM_TEST_HY2_CURL_REF:-}" ]] || exit 2
    CURL_ID=$(docker image inspect --format '{{.Id}}' "${PADM_TEST_HY2_CURL_REF}")
    [[ "${CURL_ID}" =~ ^sha256:[a-f0-9]{64}$ ]]
fi
project="padm-hysteria2-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
subnet=$(printf 'fd42:7061:646d:%x::/64' "${RANDOM}")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-hysteria2-real.XXXXXX")
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
        printf 'hysteria2-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2
        status=1
    fi
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
DOMAIN=hy2.padm.test
UUID=11111111-1111-4111-8111-111111111111
TLS_DIR="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
mkdir -p "${TEST_ROOT}/certs" "${TLS_DIR}" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=padm-hysteria2-test-ca \
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
  def entry($tag; $port; $mode; $obfs): {
    id:3,listener_id:$tag,core:"sing-box",server:$domain,public_port:$port,
    address_families:["ipv4","ipv6"],name:$tag,uuid:$uuid,
    hy2:{domain:$domain,bandwidth_mode:$mode,
      up_mbps:(if $mode == "bbr" then 100 else 120 end),
      down_mbps:(if $mode == "bbr" then 50 else 60 end),
      obfs:$obfs,masquerade:""}};
  {schema_version:3,
   release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"sing-box",secondary_type:null,protocols:[
     entry("entry-hy2-bbr";35461;"bbr";null),
     entry("entry-hy2-brutal";35462;"brutal";null),
     entry("entry-hy2-salamander";35463;"bbr";{type:"salamander",password:"salamander-real-123456"})]},
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
  (.inbounds | length) == 3 and
  all(.inbounds[]; .type == "hysteria2" and .listen == "::" and
    .users == [{name:$uuid,password:$uuid}] and
    .tls == {enabled:true,server_name:$domain,alpn:["h3"],
      certificate_path:("/etc/padm/secrets/tls/"+$domain+".crt"),
      key_path:("/etc/padm/secrets/tls/"+$domain+".key")}) and
  any(.inbounds[]; .tag == "entry-hy2-brutal" and .up_mbps == 120 and .down_mbps == 60 and
    (has("ignore_client_bandwidth") | not)) and
  all(.inbounds[] | select(.tag != "entry-hy2-brutal");
    .ignore_client_bandwidth == true and (has("up_mbps") | not) and (has("down_mbps") | not)) and
  any(.inbounds[]; .tag == "entry-hy2-salamander" and
    .obfs == {type:"salamander",password:"salamander-real-123456"}) and
  .experimental.v2ray_api.stats.users == [$uuid]
' "${candidate}/config/sing-box/config.json" >/dev/null
jq -e '
  .services["sing-box"].ports | sort == ([
    "0.0.0.0:35461:35461/udp","[::]:35461:35461/udp",
    "0.0.0.0:35462:35462/udp","[::]:35462:35462/udp",
    "0.0.0.0:35463:35463/udp","[::]:35463:35463/udp"] | sort)
' "${candidate}/compose.json" >/dev/null
dockerDeploymentFileValidate "${candidate}/deployment.json"
jq -e '
  .core.type == "sing-box" and .core.secondary_type == null and .core.protocol_ids == [3] and
  (.listeners | length) == 3 and
  all(.listeners[]; .service == "sing-box" and .transport == "udp" and
    .public_port == .container_port and .address_families == ["ipv4","ipv6"])
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
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 3 ]]
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/certs/ca.crt" "${TEST_ROOT}/runtime/client/ca.crt"
printf 'padm-hysteria2-real-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
chmod 0750 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
chmod 0640 "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/proof.txt"
chown 0:10001 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin" \
    "${TEST_ROOT}/runtime/client/ca.crt" "${TEST_ROOT}/runtime/origin/proof.txt"
# docker cp 到停止容器可能重写归属；tar 流保持生产夹具的 UID/GID 和权限模式。
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
COMPOSE="${TEST_ROOT}/compose.json"
generateCompose() {
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
}
generateCompose
compose() {
    docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"
}
compose config --format json >/dev/null
compose run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null
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
# 客户端只从 URI 取得协议参数；地址映射不读 spec，强制每条 URI 分别走 IPv4 与 IPv6。
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" <<'PY'
import ipaddress
import json
import pathlib
import sys
import urllib.parse
import uuid

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
endpoints = json.loads(sys.argv[3])
assert len(endpoints) == 2
assert [ipaddress.ip_address(endpoint).version for endpoint in endpoints] == [4, 6], endpoints
config = {"log":{"level":"warn"}, "inbounds":[], "outbounds":[], "route":{"rules":[]}}

def parse(line):
    uri = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    assert uri.scheme == "hysteria2" and uri.username and uri.password is None and uri.hostname == "hy2.padm.test"
    assert str(uuid.UUID(urllib.parse.unquote(uri.username))) == urllib.parse.unquote(uri.username)
    required = {"peer", "insecure", "sni", "alpn"}
    if "upmbps" in q or "downmbps" in q:
        required |= {"upmbps", "downmbps"}
    if "obfs" in q or "obfs-password" in q:
        required |= {"obfs", "obfs-password"}
    assert set(q) == required and all(len(v) == 1 and v[0] for v in q.values()), q
    q = {key:values[0] for key, values in q.items()}
    assert q["peer"] == q["sni"] == uri.hostname and q["insecure"] == "0" and q["alpn"] == "h3"
    if "upmbps" in q:
        assert q["upmbps"].isdecimal() and 0 < int(q["upmbps"]) <= 1000000
        assert q["downmbps"].isdecimal() and 0 < int(q["downmbps"]) <= 1000000
    if "obfs" in q:
        assert q["obfs"] == "salamander" and 16 <= len(q["obfs-password"]) <= 128
    return uri, q

sample = urllib.parse.urlsplit(lines[0])
for invalid in (sample._replace(scheme="vless").geturl(),
                sample._replace(query=sample.query.replace("insecure=0", "insecure=1")).geturl(),
                sample._replace(query=sample.query+"&sni=").geturl(),
                sample._replace(query=sample.query+"&unknown=").geturl()):
    try:
        parse(invalid)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid URI accepted")
expected = {35461:"bbr", 35462:"brutal", 35463:"salamander"}
seen = set()
for line in lines:
    uri, q = parse(line)
    mode = expected[uri.port]
    assert uri.port not in seen
    seen.add(uri.port)
    if mode == "brutal":
        assert q["upmbps"] == "60" and q["downmbps"] == "120" and "obfs" not in q
    else:
        assert "upmbps" not in q and "downmbps" not in q
        assert ("obfs" in q) == (mode == "salamander")
    for family, endpoint in zip((4, 6), endpoints):
        tag = "hy2-"+mode+"-v"+str(family)
        port = 2081 + len(config["inbounds"])
        config["inbounds"].append({"type":"socks", "tag":"socks-"+tag, "listen":"0.0.0.0", "listen_port":port})
        outbound = {"type":"hysteria2", "tag":tag, "server":endpoint, "server_port":uri.port,
                    "password":urllib.parse.unquote(uri.username),
                    "tls":{"enabled":True, "server_name":q["sni"], "alpn":[q["alpn"]],
                           "certificate_path":"/etc/padm/client/ca.crt"}}
        if "upmbps" in q:
            outbound.update(up_mbps=int(q["upmbps"]), down_mbps=int(q["downmbps"]))
        if "obfs" in q:
            outbound["obfs"] = {"type":q["obfs"], "password":q["obfs-password"]}
        config["outbounds"].append(outbound)
        config["route"]["rules"].append({"inbound":["socks-"+tag], "action":"route", "outbound":tag})
assert seen == set(expected) and len(config["outbounds"]) == 6
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
PY
chmod 0640 "${TEST_ROOT}/runtime/client/config.json"
chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
tar -cpf - -C "${TEST_ROOT}" runtime/client |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
compose run --rm --no-deps client check -c /etc/padm/client/config.json >/dev/null
compose up -d --pull never client
# ops 镜像不含 curl，复用 stdlib SOCKS 请求；只等待监听，不重试已发送的真实握手。
businessProbe() {
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
        assert body==b"padm-hysteria2-real-proof\n", response
    return str(port)
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    results=list(pool.map(probe,range(2081,2087)))
print("docker-hysteria2-real-probe-ok: source=protocol-links transport=udp family=ipv4,ipv6 modes=bbr,brutal,salamander socks="+",".join(results))
'
}
businessProbe

if [[ "${HY2_SITES}" == 1 ]]; then
    siteSpec="${TEST_ROOT}/site.json"
    DOCKER_STAGED_BUNDLE_PATH=$(dockerCurrentBundlePath)
    siteProbe() {
        local theme=$1 enabled=$2
        server=$(compose ps -q sing-box)
        addresses=$(docker inspect "${server}" |
            jq -cer --arg project "${project}" '.[0].NetworkSettings.Networks[$project] | [.IPAddress,.GlobalIPv6Address]')
        docker inspect "${server}" | jq -e --argjson enabled "${enabled}" '
          .[0] | .State.Running == true and .State.Health.Status == "healthy" and
          ([.Mounts[] | select(.Destination == "/srv/padm")] |
            if $enabled then length == 1 and .[0].RW == false else length == 0 end)
        ' >/dev/null
        docker run --rm --init -i --pull=never --read-only --cap-drop ALL --user 10001:10001 \
            --tmpfs /tmp:rw,nosuid,nodev,size=32m --network "${project}" \
            --label "io.padm.test=${project}" \
            --mount "type=volume,source=${volume},target=/site,readonly,volume-subpath=runtime/data/static" \
            --mount "type=volume,source=${volume},target=/client,readonly,volume-subpath=runtime/client" \
            --entrypoint python3 "${CURL_ID}" - "${theme}" "${addresses}" "${enabled}" <<'PY'
import ipaddress
import json
from pathlib import Path
import subprocess
import sys
import tempfile

theme, endpoints, enabled = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3] == "true"
assert [ipaddress.ip_address(value).version for value in endpoints] == [4, 6]
site = Path("/site")
articles = {
    "notes": ("a-reading-notebook.html", "assets/woodland.jpg"),
    "photos": ("reading-a-ridgeline.html", "assets/ridge.jpg"),
    "docs": ("checking-file-integrity.html", "assets/ridge.jpg"),
}
cases = [
    ("GET", "/", 200, "index.html"),
    ("HEAD", "/", 200, "index.html"),
    ("GET", "/index.html", 301, None),
    ("GET", "/"+articles[theme][0], 200, articles[theme][0]),
    ("GET", "/assets/style.css", 200, "assets/style.css"),
    ("GET", "/assets/favicon.png", 200, "assets/favicon.png"),
    ("GET", "/"+articles[theme][1], 200, articles[theme][1]),
    ("GET", "/404.html", 200, "404.html"),
]
cases += [("GET", path, 404, None) for path in (
    "/missing-page", "/check", "/static-site.json", "/.env", "/.padm-site",
    "/api", "/api/status", "/config/spec.json", "/deployment.json",
    "/secrets/tls/hy2.padm.test.key", "/../../secrets/tls/hy2.padm.test.key")]
cases.append(("POST", "/auth", 404, None))
records = []
with tempfile.TemporaryDirectory(prefix="hy2-site-") as work:
    for endpoint in endpoints:
        authority = f"[{endpoint}]" if ":" in endpoint else endpoint
        base = [
            "curl", "--http3-only", "--silent", "--show-error", "--noproxy", "*",
            "--path-as-is", "--connect-timeout", "2", "--max-time", "10",
            "--cacert", "/client/ca.crt", "--resolve", f"hy2.padm.test:35461:{authority}",
        ]
        for method, path, expected, asset in cases:
            headers_path, body_path = Path(work)/"headers", Path(work)/"body"
            arguments = base + ["--dump-header", str(headers_path), "--output", str(body_path),
                                "--write-out", "%{http_code} %{http_version}"]
            if method == "HEAD":
                arguments += ["--head"]
            elif method == "POST":
                arguments += ["--request", "POST", "--header", "Hysteria-Auth: incorrect-password"]
            if path.startswith("/../"):
                # 跟随路径规范化后仍须拒绝私有文件，不能只检查首个跳转。
                arguments += ["--location", "--max-redirs", "3"]
            arguments += [f"https://hy2.padm.test:35461{path}"]
            response = subprocess.run(arguments, capture_output=True, text=True, check=True)
            status, version = response.stdout.split()
            status = int(status)
            headers = {}
            for line in headers_path.read_text().splitlines()[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.lower()] = value.strip()
            body = b"" if method == "HEAD" else body_path.read_bytes()
            wanted = expected if enabled else 404
            record = dict(theme=theme, enabled=enabled, family=ipaddress.ip_address(endpoint).version,
                          method=method, path=path, status=status, http_version=version, bytes=len(body))
            assert version == "3" and status == wanted, record
            if enabled and asset is not None:
                expected_body = (site/asset).read_bytes()
                if method == "HEAD":
                    assert int(headers["content-length"]) == len(expected_body), record
                else:
                    assert body == expected_body, record
            if enabled and path == "/index.html":
                assert headers["location"] == "./", record
            assert all(secret not in body for secret in (
                b"11111111-1111-4111-8111-111111111111", b"salamander-real-123456",
                b"PRIVATE KEY", b'"private_key"', b'"manifest_sha256"')), record
            if path == "/auth":
                assert "hysteria-udp" not in headers and "hysteria-cc-rx" not in headers, record
            records.append(record)
        if enabled:
            for host, ca in (("hy2.padm.test", None), ("wrong.padm.test", "/client/ca.crt")):
                arguments = [
                    "curl", "--http3-only", "--silent", "--show-error", "--noproxy", "*",
                    "--connect-timeout", "2", "--max-time", "5", "--output", "/dev/null",
                    "--resolve", f"{host}:35461:{authority}", f"https://{host}:35461/",
                ]
                if ca:
                    arguments[1:1] = ["--cacert", ca]
                response = subprocess.run(arguments, capture_output=True)
                assert response.returncode == 60, (host, response.returncode, response.stderr)
print("docker-hy2-sites-h3-ok: "+json.dumps(records, separators=(",", ":")), flush=True)
PY
    }
    installSiteCandidate() {
        compose stop sing-box >/dev/null
        [[ "${PADM_DOCKER_INSTALL_DIR}" == "${TEST_ROOT}/state" ]]
        rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/data/static" "${TEST_ROOT}/runtime/data/static"
        cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
        cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
        cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
        cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
        cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
        cp -a "${candidate}/config" "${candidate}/data" "${candidate}/secrets" "${TEST_ROOT}/runtime/"
        dockerCleanupConfigurationCandidate
        tar -cpf - -C "${TEST_ROOT}" runtime/config runtime/data runtime/secrets |
            docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
                --mount "type=volume,source=${volume},target=/test" --entrypoint sh "${OPS_ID}" \
                -c 'rm -rf -- /test/runtime/data/static && tar -xpf - -C /test'
        generateCompose
        compose config --format json >/dev/null
        compose run --rm --no-deps sing-box check -D /var/lib/padm/sing-box \
            -c /etc/padm/sing-box/config.json >/dev/null
        compose up -d --force-recreate --pull never --wait --wait-timeout 60 sing-box
        compose restart client >/dev/null
    }
    for theme in notes photos docs; do
        # 先用生产模板落盘，再用普通规格字段启用 local，保留已有认证与混淆入口。
        jq '.site = {mode:"static"}' "${SPEC}" >"${siteSpec}"
        chmod 0600 "${siteSpec}"
        dockerCreateConfigurationCandidate
        candidate=${DOCKER_CONFIG_CANDIDATE}
        dockerGenerateCandidate "${siteSpec}" "${candidate}" '' '' '' '' "${theme}"
        jq -e 'all(.inbounds[]; has("masquerade") | not)' \
            "${candidate}/config/sing-box/config.json" >/dev/null
        [[ "${PADM_DOCKER_INSTALL_DIR}" == "${TEST_ROOT}/state" ]]
        rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/data/static"
        cp -a "${candidate}/data/static" "${PADM_DOCKER_INSTALL_DIR}/data/"
        dockerCleanupConfigurationCandidate
        jq '.core.protocols |= map(if .hy2.obfs == null then .hy2.masquerade = "local" else . end)' \
            "${siteSpec}" >"${siteSpec}.next"
        mv "${siteSpec}.next" "${siteSpec}"
        chmod 0600 "${siteSpec}"
        dockerConfigureSpecValidate "${siteSpec}"
        dockerCreateConfigurationCandidate
        candidate=${DOCKER_CONFIG_CANDIDATE}
        dockerGenerateCandidate "${siteSpec}" "${candidate}"
        jq -e 'all(.inbounds[] | select(.tag != "entry-hy2-salamander");
          .masquerade == "file:///srv/padm/" and (has("obfs") | not)) and
          all(.inbounds[] | select(.tag == "entry-hy2-salamander"); has("masquerade") | not)' \
            "${candidate}/config/sing-box/config.json" >/dev/null
        jq -e '.services["sing-box"].volumes |
          [.[] | select(.target == "/srv/padm" and .source == "${PADM_DOCKER_ROOT}/data/static" and .read_only == true)] |
          length == 1' "${candidate}/compose.json" >/dev/null
        installSiteCandidate
        siteProbe "${theme}" true
        businessProbe
    done
    jq '.core.protocols |= map(.hy2.masquerade = "")' "${siteSpec}" >"${siteSpec}.next"
    mv "${siteSpec}.next" "${siteSpec}"
    chmod 0600 "${siteSpec}"
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${siteSpec}" "${candidate}"
    jq -e 'all(.inbounds[]; has("masquerade") | not)' \
        "${candidate}/config/sing-box/config.json" >/dev/null
    installSiteCandidate
    siteProbe docs false
    businessProbe
    printf 'docker-hy2-sites-real-ok: themes=notes,photos,docs family=ipv4,ipv6 ca-sni=verified mount=readonly disabled=404 auth=preserved\n'
fi
printf 'docker-hysteria2-real-ok: endpoint=isolated-compose xray=%s sing-box=%s ops=%s\n' \
    "${XRAY_ID}" "${SING_ID}" "${OPS_ID}"
