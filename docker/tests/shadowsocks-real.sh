#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
trap 'printf "docker-shadowsocks-real-fail: line=%s rc=%s\n" "${LINENO}" "$?" >&2' ERR

# 只验收本次唯一项目与命名卷，不发布宿主端口或接管现有部署。
[[ "$#" == 0 || "$#" == 4 ]] || {
    printf 'usage: shadowsocks-real.sh [<local-xray> <local-sing-box> <local-ops> <local-curl>]\n' >&2
    exit 2
}
if [[ "$#" == 0 ]]; then
    python3 - "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" <<'PY'
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import signal
import subprocess
import sys
import tempfile

scripts = Path(sys.argv[1])
helpers = runpy.run_path(str(scripts / "http-relay-published-real.py"))
command, stop, wait_ready = (helpers[name] for name in ("command", "stop", "wait_ready"))
assert os.getuid() == 0 and sys.platform == "linux" and Path("/.dockerenv").is_file()
assert {item["ifname"] for item in json.loads(command(["ip", "-j", "link", "show"]))} == {"lo"}
assert not Path("/var/run/docker.sock").exists(), "不得使用宿主 Docker Socket"
inputs = json.loads(Path("/node-images.json").read_text())
assert set(inputs) == {"xray", "sing-box", "ops", "curl"}
node = Path(tempfile.mkdtemp(prefix=".tmp-shadowsocks-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = child = None

def terminate(*_):
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as log, (node / "child.log").open("wb") as child_log:
    try:
        # 离线镜像只进入本次独立 daemon，源码仍取当前工作区快照。
        daemon = subprocess.Popen([
            "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
            "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
            "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
            "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
        wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
        command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
        for item in inputs.values():
            assert re.fullmatch(r"sha256:[0-9a-f]{64}", item["image_id"])
            image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
            assert image["Id"] == item["image_id"]
        child = subprocess.Popen([
            "bash", str(scripts / "shadowsocks-real.sh"),
            *(inputs[name]["image_id"] for name in ("xray", "sing-box", "ops", "curl"))],
            env=dict(os.environ, DOCKER_HOST=docker[-1]), stdout=child_log, stderr=child_log)
        child_status = child.wait(timeout=600)
        assert child_status == 0, f"Shadowsocks 实链路子脚本退出码 {child_status}"
        assert not command(docker + ["ps", "-aq"]).strip(), "测试容器未清理"
        assert not command(docker + ["volume", "ls", "-q"]).strip(), "测试卷未清理"
        print("docker-shadowsocks-real-images=" + json.dumps(inputs), flush=True)
    finally:
        active_error = sys.exc_info()[0] is not None
        try:
            if child is not None:
                stop(child)
            if daemon is not None:
                try:
                    result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                    if not result.returncode and result.stdout.strip():
                        command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
                finally:
                    stop(daemon)
        finally:
            try:
                for name in (("child.log", "daemon.log") if active_error else ("child.log",)):
                    output = (node / name).read_text(errors="replace")
                    output = re.sub(r"ss://[^\s\"']+", "ss://[已隐藏]", output)
                    output = re.sub(r"[A-Za-z0-9+/]{22}==", "[已隐藏密钥]", output)
                    print(output[-4000:] if active_error else output,
                          file=sys.stderr if active_error else sys.stdout, flush=True)
            finally:
                assert node.parent == Path("/n") and node.name.startswith(".tmp-shadowsocks-")
                shutil.rmtree(node)
PY
    exit 0
fi
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'shadowsocks-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
for tool in docker jq python3 sha256sum tar od awk; do command -v "${tool}" >/dev/null; done
# 固定本机不可变镜像 ID，禁止隐式拉取。
XRAY_ID=$(docker image inspect --format '{{.Id}}' "$1")
SING_ID=$(docker image inspect --format '{{.Id}}' "$2")
OPS_ID=$(docker image inspect --format '{{.Id}}' "$3")
CURL_ID=$(docker image inspect --format '{{.Id}}' "$4")
for image in "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
project="padm-shadowsocks-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
subnet=$(printf 'fd42:7061:646d:%x::/64' "${RANDOM}")
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-shadowsocks-real.XXXXXX")
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
        # Docker 仅输出十六进制 ID，分词仅用于本次项目的批量清理。
        # shellcheck disable=SC2086
        docker rm -f ${ids} >/dev/null || cleanup_failed=1
    fi
    for resource in network volume; do
        name=${project}
        [[ "${resource}" != volume ]] || name=${volume}
        if docker "${resource}" inspect "${name}" >/dev/null 2>&1; then
            if docker "${resource}" inspect "${name}" |
                jq -e --arg project "${project}" '.[0].Labels["io.padm.test"] == $project' >/dev/null; then
                docker "${resource}" rm "${name}" >/dev/null || cleanup_failed=1
            else
                cleanup_failed=1
            fi
        fi
    done
    if [[ "${cleanup_failed}" == 0 ]]; then
        rm -rf -- "${TEST_ROOT}"
    else
        printf 'shadowsocks-real cleanup failed: project=%s files=%s\n' "${project}" "${TEST_ROOT}" >&2
        status=1
    fi
    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
docker run --rm --init --pull=never --network none --label "io.padm.test=${project}" \
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
UUID=11111111-1111-4111-8111-111111111111
mkdir -p "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin" "${TEST_ROOT}/runtime/probe"
# 合成测试密钥只保存在受限文件，包含 +、/、= 以核验 SIP002 转义。
python3 - "${TEST_ROOT}/keys.json" <<'PY'
import base64
import json
import pathlib
import sys

keys = [base64.b64encode(bytes(range(16))).decode(),
        base64.b64encode(bytes(range(255, 239, -1))).decode()]
pathlib.Path(sys.argv[1]).write_text(json.dumps(dict(zip(("server_password", "user_password"), keys))))
PY
SPEC="${TEST_ROOT}/spec.json"
jq -n --arg uuid "${UUID}" --slurpfile keys "${TEST_ROOT}/keys.json" '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  {schema_version:3,
   release:{version:"3.9.9",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:30,listener_id:"entry-shadowsocks",core:"sing-box",server:"ss.padm.test",public_port:35470,
     address_families:["ipv4","ipv6"],name:"entry-shadowsocks",uuid:$uuid,
     shadowsocks:($keys[0]+{method:"2022-blake3-aes-128-gcm"})}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${candidate}"
jq -e --arg uuid "${UUID}" --slurpfile keys "${TEST_ROOT}/keys.json" '
  (.inbounds | length) == 1 and
  (.inbounds[0] | .type == "shadowsocks" and .listen == "::" and .listen_port == 35470 and
    .tag == "entry-shadowsocks" and .method == "2022-blake3-aes-128-gcm" and
    .password == $keys[0].server_password and
    .users == [{name:$uuid,password:$keys[0].user_password}] and
    (has("network") | not) and (has("tls") | not)) and
  .experimental.v2ray_api.stats.users == [$uuid]
' "${candidate}/config/sing-box/config.json" >/dev/null
jq -e '
  .services["sing-box"].ports | sort == ([
    "0.0.0.0:35470:35470/tcp","[::]:35470:35470/tcp",
    "0.0.0.0:35470:35470/udp","[::]:35470:35470/udp"] | sort)
' "${candidate}/compose.json" >/dev/null
dockerDeploymentFileValidate "${candidate}/deployment.json"
jq -e '
  .core.type == "sing-box" and .core.secondary_type == null and .core.protocol_ids == [30] and
  (.listeners | length) == 2 and ([.listeners[].transport] | sort) == ["tcp","udp"] and
  all(.listeners[]; .listener_id == "entry-shadowsocks" and .service == "sing-box" and
    .public_port == 35470 and .container_port == 35470 and .address_families == ["ipv4","ipv6"])
' "${candidate}/deployment.json" >/dev/null
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/sing-box/config.json")" == 0:10001:640 ]]
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/sing-box")" == 0:10001:750 ]]
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/sing-box/users.base")" == 0:0:600 ]]
[[ "$(stat -c '%u:%g:%a' "${candidate}/config/spec.json")" == 0:0:600 ]]
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
base_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base")
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 1 ]]
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${TEST_ROOT}/runtime/"
cat >"${TEST_ROOT}/runtime/origin/server.py" <<'PY'
import http.server
import json
import socket
import threading

counts = {"tcp": 0, "udp": 0}
lock = threading.Lock()
proof = b"padm-shadowsocks-real-proof\n"
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
cat >"${TEST_ROOT}/runtime/probe/probe.py" <<'PY'
import concurrent.futures
import ipaddress
import json
import socket
import struct
import sys
import time
import urllib.request

proof = b"padm-shadowsocks-real-proof\n"
phase = sys.argv[1]
allowed_ports = {
    "allow": {2081, 2082},
    "deny": set(),
    "accounts": {2081, 2082, 2085, 2086},
    "rotated": {2081, 2082, 2085, 2086},
    "server-rotated": {2081, 2082, 2085, 2086},
}
assert phase in allowed_ports
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
    sock.settimeout(3)
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
            sock.settimeout(3)
            sock.bind(("::" if family == socket.AF_INET6 else "0.0.0.0", 0))
            target = socket.inet_aton(socket.gethostbyname("origin"))
            payload = proof+str(port).encode()+b"-"+phase.encode()
            packet = b"\x00\x00\x00\x01"+target+struct.pack("!H", 8089)+payload
            sock.sendto(packet, (host, relay_port))
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
def probe(item):
    port, transport = item
    expected = port in allowed_ports[phase]
    try:
        accepted = (tcp if transport == "tcp" else udp)(port)
    except (OSError, EOFError, ValueError):
        accepted = False
    assert accepted == expected, (phase, port, transport, accepted)
    return str(port)+"/"+transport
end_port = {"allow": 2085, "deny": 2085, "accounts": 2087, "rotated": 2089,
            "server-rotated": 2091}[phase]
results = []
# 拒绝探针单独计数，防止成功账号的请求掩盖旧密钥到达 origin。
for expected in (True, False):
    items = [(port, transport) for port in range(2081, end_port)
             if (port in allowed_ports[phase]) == expected for transport in ("tcp", "udp")]
    before = counts()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results.extend(pool.map(probe, items))
    after = counts()
    expected_delta = len(items)//2 if expected else 0
    assert {key:after[key]-before[key] for key in before} == {"tcp":expected_delta, "udp":expected_delta}
print("docker-shadowsocks-real-probe-ok: phase="+phase+" source=protocol-links family=ipv4,ipv6 socks="+",".join(results))
PY
chmod 0750 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/"{client,origin,probe}
chmod 0640 "${TEST_ROOT}/runtime/origin/server.py" "${TEST_ROOT}/runtime/probe/probe.py"
chown 0:10001 "${TEST_ROOT}/runtime" "${TEST_ROOT}/runtime/"{client,origin,probe} \
    "${TEST_ROOT}/runtime/origin/server.py" "${TEST_ROOT}/runtime/probe/probe.py"
upload() {
    tar -cpf - -C "${TEST_ROOT}" "$1" |
        docker run --rm --init -i --pull=never --label "io.padm.test=${project}" --user 0 \
            --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
}
upload runtime
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg sing "${SING_ID}" \
    --arg ops "${OPS_ID}" --arg subnet "${subnet}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  .networks.default.enable_ipv6 = true | .networks.default.ipam = {config:[{subnet:$subnet}]} |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services |= with_entries(
    .value.image = $sing | .value.ports = [] | .value.init = true |
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
      .[0] | .State.Running and .State.Health.Status == "healthy" and
      .Config.Labels["io.padm.test"] == $project and .Config.Image == $image and
      .Config.User == "10001:10001" and .HostConfig.ReadonlyRootfs and .HostConfig.Init and
      .HostConfig.CapDrop == ["ALL"] and
      (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null)
    ' >/dev/null
addresses=$(docker inspect "${server}" |
    jq -cer --arg project "${project}" '.[0].NetworkSettings.Networks[$project] | [.IPAddress,.GlobalIPv6Address]')
# 只从实际 URI 解析认证和 authority；地址映射与原始 spec 无关。
startClient() {
    python3 - "$1" "${TEST_ROOT}/runtime/client/config.json" "${addresses}" "${2:-}" "${3:-user}" <<'PY'
import base64
import ipaddress
import json
import pathlib
import sys
import urllib.parse

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
endpoints = json.loads(sys.argv[3])
assert len(lines) in (1, 2) and [ipaddress.ip_address(value).version for value in endpoints] == [4, 6]
def parse(line):
    uri = urllib.parse.urlsplit(line)
    assert uri.scheme == "ss" and uri.hostname == "ss.padm.test" and uri.port == 35470
    assert not uri.query and not uri.path
    assert urllib.parse.unquote(uri.fragment) in ("entry-shadowsocks", "entry-shadowsocks-independent")
    method = urllib.parse.unquote(uri.username or "")
    password = urllib.parse.unquote(uri.password or "")
    assert method == "2022-blake3-aes-128-gcm"
    keys = password.split(":")
    assert len(keys) == 2
    for key in keys:
        raw = base64.b64decode(key, validate=True)
        assert len(raw) == 16 and base64.b64encode(raw).decode() == key
    assert keys[0] != keys[1]
    assert uri.netloc == method+":"+urllib.parse.quote(password, safe="")+"@"+uri.hostname+":"+str(uri.port)
    return uri, method, password, keys[0]
sample = urllib.parse.urlsplit(lines[0])
for invalid in (sample._replace(scheme="vless").geturl(),
                sample._replace(query="plugin=unsupported").geturl(),
                sample._replace(netloc=sample.netloc.replace("%3A", ":")).geturl()):
    try:
        parse(invalid)
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid SIP002 URI accepted")
uri, method, password, server_key = parse(lines[0])
assert urllib.parse.unquote(uri.fragment) == "entry-shadowsocks"
modes = [("multi", password), ("server-only", server_key)]
if len(lines) == 2:
    account_uri, account_method, account_password, account_server_key = parse(lines[1])
    assert urllib.parse.unquote(account_uri.fragment) == "entry-shadowsocks-independent"
    assert account_method == method and account_server_key == server_key and account_password != password
    modes.append(("independent", account_password))
if sys.argv[4]:
    previous = pathlib.Path(sys.argv[4]).read_text().splitlines()
    assert len(lines) == len(previous) == 2 and previous[0] != lines[0]
    _, old_method, old_password, old_server_key = parse(previous[0])
    assert old_method == method and old_password != password
    modes.append(("old-self", old_password))
    if sys.argv[5] == "server":
        _, old_account_method, old_account_password, old_account_server_key = parse(previous[1])
        assert old_method == old_account_method and old_server_key == old_account_server_key != server_key
        assert old_password.split(":")[1] == password.split(":")[1]
        assert old_account_password.split(":")[1] == account_password.split(":")[1]
        assert old_account_password != account_password
        modes.append(("old-independent", old_account_password))
    else:
        assert sys.argv[5] == "user" and previous[1] == lines[1] and old_server_key == server_key
config = {"log":{"level":"warn"}, "inbounds":[], "outbounds":[], "route":{"rules":[]}}
for mode, credential in modes:
    for family, endpoint in zip((4, 6), endpoints):
        tag = mode+"-v"+str(family)
        config["inbounds"].append({"type":"socks", "tag":"socks-"+tag, "listen":"0.0.0.0",
                                  "listen_port":2081+len(config["inbounds"])})
        config["outbounds"].append({"type":"shadowsocks", "tag":tag, "server":endpoint,
                                   "server_port":uri.port, "method":method, "password":credential})
        config["route"]["rules"].append({"inbound":["socks-"+tag], "action":"route", "outbound":tag})
pathlib.Path(sys.argv[2]).write_text(json.dumps(config))
PY
    chmod 0640 "${TEST_ROOT}/runtime/client/config.json"
    chown 0:10001 "${TEST_ROOT}/runtime/client/config.json"
    upload runtime/client
    compose run --rm --no-deps --pull never client check -c /etc/padm/client/config.json >/dev/null
    compose up -d --pull never --force-recreate client
}
startClient "${TEST_ROOT}/links.txt"
client=$(compose ps -q client)
docker inspect "${client}" |
    jq -e --arg image "${SING_ID}" '
      .[0] | .State.Running and .Config.Image == $image and .Config.User == "10001:10001" and
      .HostConfig.ReadonlyRootfs and .HostConfig.Init and .HostConfig.CapDrop == ["ALL"] and
      (.HostConfig.PortBindings == {} or .HostConfig.PortBindings == null)
    ' >/dev/null
probe() {
    docker run --rm --init --pull=never --read-only --cap-drop ALL --user 10001:10001 \
        --network "${project}" --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly" \
        --entrypoint python3 "${OPS_ID}" /test/runtime/probe/probe.py "$1"
}
# 只适配隔离卷与网络；额度状态、配置验证、重启和恢复仍走生产函数。
dockerComposeRun() {
    local action=$1
    shift
    case "${action}" in
    run|restart)
        cp -a "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/." "${TEST_ROOT}/runtime/config/sing-box/"
        upload runtime/config/sing-box
        ;;
    esac
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
          {id:.Id,started_at:.State.StartedAt,pid:.State.Pid}
        '
}
dockerTrafficQuery() (
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
stats=$(dockerTrafficQuery sing-box)
jq -e --arg uuid "${UUID}" '
  def positive($direction):
    [.stat[]? | select(.name == ("user>>>"+$uuid+">>>traffic>>>"+$direction)) | .value] |
    length == 1 and (.[0] | type == "number" and . > 0);
  positive("uplink") and positive("downlink")
' <<<"${stats}" >/dev/null
printf 'docker-shadowsocks-real-stats-ok: identity=%s counters=%s\n' "${UUID}" "${stats}"
dockerTrafficSetLimit "${UUID}" 1
jq -e --arg uuid "${UUID}" '.inbounds == [] and .experimental.v2ray_api.stats.users == [$uuid]' \
    "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base")" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe deny
dockerTrafficSetLimit "${UUID}" 0
jq -e --arg uuid "${UUID}" --slurpfile keys "${TEST_ROOT}/keys.json" '
  (.inbounds | length) == 1 and .inbounds[0].type == "shadowsocks" and
  .inbounds[0].password == $keys[0].server_password and
  .inbounds[0].users == [{name:$uuid,password:$keys[0].user_password}]
' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base")" == "${base_hash}" ]]
[[ "$(compose ps -q client)" == "${client}" ]]
probe allow
dockerTrafficSnapshot
jq -e --arg uuid "${UUID}" '
  .accounts[$uuid] | .upload > 0 and .download > 0 and .limit_bytes == 0
' "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" >/dev/null

# 额度恢复后增加独立账号，轮换仍走生产 helper 与候选生成器。
publishTestSpec() {
    dockerConfigureSpecValidate "$1"
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "$1" "${candidate}"
    cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
    cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
    cp "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerCleanupConfigurationCandidate
    dockerComposeRun run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json >/dev/null
    dockerComposeRun restart sing-box
    compose up -d --pull never --wait --wait-timeout 60 sing-box
}
accountSsPassword=$(dockerAccountRandomSsPassword "${OPS_ID}")
jq --rawfile ss <(printf '%s' "${accountSsPassword}") '
  .accounts = [{id:"22222222-2222-4222-8222-222222222222",name:"independent",enabled:true,
    uuid:"33333333-3333-4333-8333-333333333333",password:"independent-test-password",
    shadowsocks_password:$ss,listeners:["entry-shadowsocks"]}]
' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/with-account.json"
accountSsPassword=
publishTestSpec "${TEST_ROOT}/with-account.json"
dockerProtocolCommand links >"${TEST_ROOT}/before-rotation-links.txt"
startClient "${TEST_ROOT}/before-rotation-links.txt"
probe accounts
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/rotated-spec.json"
dockerEditRotateSsPassword "${TEST_ROOT}/rotated-spec.json" entry-shadowsocks "${OPS_ID}" user_password
jq -e -s '
  .[0] as $before | .[1] as $after |
  ($before | del(.core.protocols[0].shadowsocks.user_password)) ==
    ($after | del(.core.protocols[0].shadowsocks.user_password)) and
  $before.core.protocols[0].shadowsocks.user_password != $after.core.protocols[0].shadowsocks.user_password
' "${TEST_ROOT}/with-account.json" "${TEST_ROOT}/rotated-spec.json" >/dev/null
publishTestSpec "${TEST_ROOT}/rotated-spec.json"
dockerProtocolCommand links >"${TEST_ROOT}/rotated-links.txt"
startClient "${TEST_ROOT}/rotated-links.txt" "${TEST_ROOT}/before-rotation-links.txt"
probe rotated
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/server-rotated-spec.json"
dockerEditRotateSsPassword "${TEST_ROOT}/server-rotated-spec.json" entry-shadowsocks "${OPS_ID}" server_password
jq -e -s '
  .[0] as $before | .[1] as $after |
  ($before | del(.core.protocols[0].shadowsocks.server_password)) ==
    ($after | del(.core.protocols[0].shadowsocks.server_password)) and
  $before.core.protocols[0].shadowsocks.server_password != $after.core.protocols[0].shadowsocks.server_password
' "${TEST_ROOT}/rotated-spec.json" "${TEST_ROOT}/server-rotated-spec.json" >/dev/null
publishTestSpec "${TEST_ROOT}/server-rotated-spec.json"
dockerProtocolCommand links >"${TEST_ROOT}/server-rotated-links.txt"
startClient "${TEST_ROOT}/server-rotated-links.txt" "${TEST_ROOT}/rotated-links.txt" server
probe server-rotated
dockerTrafficSnapshot
jq -e --arg uuid "${UUID}" '
  .accounts[$uuid] | .upload > 0 and .download > 0 and .limit_bytes == 0
' "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" >/dev/null
printf 'docker-shadowsocks-real-ok: endpoint=isolated-compose quota=deny-restore rotation=self-user,server old-uri=deny independent-key=preserved xray=%s sing-box=%s ops=%s curl=%s\n' \
    "${XRAY_ID}" "${SING_ID}" "${OPS_ID}" "${CURL_ID}"
