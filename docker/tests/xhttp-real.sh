#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; printf "xhttp-real-fail: line=%s rc=%s command=%s\n" "${LINENO}" "${status}" "${BASH_COMMAND}" >&2; exit "${status}"' ERR

[[ "$#" == 0 || "$#" == 2 ]] || {
    printf 'usage: xhttp-real.sh [<local-xray> <local-ops>]\n' >&2
    exit 2
}
scriptRoot=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
if [[ "$#" == 0 ]]; then
    python3 - "${scriptRoot}" <<'PY'
import json
import os
from pathlib import Path
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
assert set(inputs) == {"xray", "ops"}
node = Path(tempfile.mkdtemp(prefix=".tmp-xhttp-", dir="/n"))
docker = ["docker", "--host", f"unix://{node}/docker.sock"]
daemon = child = None
binary_container = None

def terminate(*_):
    raise SystemExit(143)

signal.signal(signal.SIGTERM, terminate)
with (node / "daemon.log").open("wb") as log:
    try:
        # 只加载固定镜像到本次独立 daemon，生产代码仍来自当前工作区快照。
        daemon = subprocess.Popen([
            "dockerd", "--host", docker[-1], "--data-root", str(node / "docker"),
            "--exec-root", str(node / "run"), "--pidfile", str(node / "daemon.pid"),
            "--feature", "containerd-snapshotter=true", "--storage-driver", "overlayfs",
            "--bip", "172.30.0.1/24"], stdout=log, stderr=log)
        wait_ready(lambda: subprocess.run(docker + ["info"], capture_output=True).returncode == 0, 30)
        command(docker + ["load", "--input", "/node-images.tar"], timeout=120)
        for item in inputs.values():
            image = json.loads(command(docker + ["image", "inspect", item["reference"]]))[0]
            assert image["Id"] == item["image_id"]
        # 首部观察使用同一个受信固定镜像的二进制，直接在外层 Linux 回环运行。
        binary_container = command(docker + ["create", inputs["xray"]["image_id"]]).decode().strip()
        binary = node / "xray"
        command(docker + ["cp", f"{binary_container}:/usr/local/bin/xray", str(binary)])
        command(docker + ["rm", binary_container])
        binary_container = None
        binary.chmod(0o755)
        child = subprocess.Popen([
            "python3", str(scripts / "xhttp-headers-real.py"), "--xray", str(binary),
            "--out", str(node / "headers")])
        assert child.wait(timeout=60) == 0, "XHTTP 外层首部观察失败"
        child = subprocess.Popen([
            "bash", str(scripts / "xhttp-real.sh"),
            *(inputs[name]["image_id"] for name in ("xray", "ops"))],
            env=dict(os.environ, DOCKER_HOST=docker[-1]))
        assert child.wait(timeout=180) == 0, "XHTTP 实链路子脚本失败"
        assert not command(docker + ["ps", "-aq"]).strip(), "测试容器未清理"
        print("docker-xhttp-real-images=" + json.dumps(inputs), flush=True)
    finally:
        active_error = sys.exc_info()[0] is not None
        if child is not None:
            stop(child)
        if daemon is not None:
            try:
                if binary_container is not None:
                    command(docker + ["rm", "-f", binary_container], timeout=15)
                result = subprocess.run(docker + ["ps", "-aq"], capture_output=True, timeout=5)
                if not result.returncode and result.stdout.strip():
                    command(docker + ["rm", "-f"] + result.stdout.decode().split(), timeout=15)
            finally:
                stop(daemon)
        if active_error:
            print((node / "daemon.log").read_text()[-4000:], file=sys.stderr)
        assert node.parent == Path("/n") and node.name.startswith(".tmp-xhttp-")
        shutil.rmtree(node)
PY
    exit 0
fi

[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
PROJECT_ROOT=$(cd -- "${scriptRoot}/../.." && pwd -P)
XRAY_ID=$(docker image inspect --format '{{.Id}}' "$1")
OPS_ID=$(docker image inspect --format '{{.Id}}' "$2")
for image in "${XRAY_ID}" "${OPS_ID}"; do
    [[ "${image}" =~ ^sha256:[a-f0-9]{64}$ ]]
done
for tool in docker jq python3 tar openssl; do command -v "${tool}" >/dev/null; done
project="padm-xhttp-$(date +%s)-$$-${RANDOM}"
volume="${project}-files"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-xhttp-real.XXXXXX")
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
    [[ "${TEST_ROOT}" == "${TMPDIR:-/tmp}/padm-xhttp-real."* ]]
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
jq -n '
  def image($name): "ghcr.io/example/padm-"+$name+":test@sha256:"+("a"*64);
  def reality: {server_name:"reality.target.test",target_host:"reality.target.test",target_port:8443,
    private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
    public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"6ba85179e30d4fc2"};
  {schema_version:3,
   release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"local-test-only"},
   core:({type:"xray",secondary_type:null,protocols:[
     {id:2,listener_id:"entry-daily",core:"xray",server:"proxy.padm.test",public_port:35501},
     {id:2,listener_id:"entry-compatible",core:"xray",server:"proxy.padm.test",public_port:35502},
     {id:2,listener_id:"entry-stream",core:"xray",server:"proxy.padm.test",public_port:35503},
     {id:2,listener_id:"entry-single",core:"xray",server:"proxy.padm.test",public_port:35504},
     {id:2,listener_id:"entry-custom",core:"xray",server:"proxy.padm.test",public_port:35505}]} |
     .protocols |= map(. + {address_families:["ipv4"],name:(.listener_id|ltrimstr("entry-")),
       uuid:"11111111-1111-4111-8111-111111111111",reality:reality,
       xhttp:{path:("/padm-"+(.listener_id|ltrimstr("entry-"))),host:"reality.target.test",mode:"auto"}})),
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:{xray:image("xray"),"sing-box":image("sing-box"),nginx:image("nginx"),ops:image("ops"),net:image("net")},
   host_integrations:[]}
' >"${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
# 编辑事务由合同覆盖；真实夹具只验生成器与客户端链接驱动的实际链路。
jq '
  .core.protocols |= map(
    .xhttp.xmux = {maxConcurrency:"16-32",hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"} |
    if .listener_id == "entry-compatible" then
      .xhttp.mode = "packet-up" | .xhttp.xPaddingBytes = "100-1000" |
      .xhttp.noGRPCHeader = true | .xhttp.noSSEHeader = false |
      .xhttp += {scMaxEachPostBytes:16384,scMinPostsIntervalMs:5,
        scMaxBufferedPosts:16,scStreamUpServerSecs:"1-2"}
    elif .listener_id == "entry-stream" then
      .xhttp.mode = "stream-up" | .xhttp.xPaddingBytes = 4096 |
      .xhttp.noGRPCHeader = false | .xhttp.noSSEHeader = true |
      .xhttp += {scMaxEachPostBytes:16384,scMinPostsIntervalMs:5,
        scMaxBufferedPosts:16,scStreamUpServerSecs:"1-2"}
    elif .listener_id == "entry-single" then .xhttp.xmux.maxConcurrency = 1 |
      .xhttp.noGRPCHeader = false | .xhttp.noSSEHeader = false
    elif .listener_id == "entry-custom" then
      .xhttp.headers = {"X-Padm-Trace":"Reality value & extra"} |
      .xhttp.xmux = {maxConcurrency:2,hMaxRequestTimes:"7-9",hMaxReusableSecs:"30-40"}
    else .xhttp.xPaddingBytes = 1 | .xhttp.noGRPCHeader = true | .xhttp.noSSEHeader = true end |
    if .listener_id != "entry-single" then .xhttp.download_port = (.public_port + 1000) else . end) |
  .port_aliases = [.core.protocols[] | select(.xhttp.download_port != null) |
    {listener_id,public_port:.xhttp.download_port}]
' "${SPEC}" >"${TEST_ROOT}/configured.json"
mv "${TEST_ROOT}/configured.json" "${SPEC}"
chmod 0600 "${SPEC}"
dockerConfigureSpecValidate "${SPEC}"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${SPEC}" "${candidate}"
jq -e '
  [.inbounds[] | select(.streamSettings.network == "xhttp") | .streamSettings.xhttpSettings.xmux] |
  length == 5 and all(. == {maxConcurrency:"16-32",hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"})
' "${candidate}/config/xray/users.base" >/dev/null
jq -e --slurpfile spec "${SPEC}" '
  def padding: if has("xPaddingBytes") then {xPaddingBytes} else {} end;
  ([.inbounds[] | select(.streamSettings.network == "xhttp") |
    {id:.tag,padding:(.streamSettings.xhttpSettings | padding)}] | sort_by(.id)) ==
  ([$spec[0].core.protocols[] | {id:.listener_id,padding:(.xhttp | padding)}] | sort_by(.id))
' "${candidate}/config/xray/users.base" >/dev/null
printf 'docker-xhttp-real-padding-config-ok: explicit=1/100-1000/4096 default=2 server=spec\n'
jq -e --slurpfile spec "${SPEC}" '
  def headers:
    (if has("noGRPCHeader") then {noGRPCHeader} else {} end) +
    (if has("noSSEHeader") then {noSSEHeader} else {} end) +
    (if has("headers") then {headers} else {} end);
  ([.inbounds[] | select(.streamSettings.network == "xhttp") |
    {id:.tag,headers:(.streamSettings.xhttpSettings | headers)}] | sort_by(.id)) ==
  ([$spec[0].core.protocols[] | {id:.listener_id,headers:(.xhttp | headers)}] | sort_by(.id))
' "${candidate}/config/xray/users.base" >/dev/null
printf 'docker-xhttp-real-headers-config-ok: dual-ended=true/true,true/false,false/true,false/false default=absent\n'
jq -e --slurpfile spec "${SPEC}" '
  def limits: with_entries(select(.key == "scMaxEachPostBytes" or .key == "scMinPostsIntervalMs" or
    .key == "scMaxBufferedPosts" or .key == "scStreamUpServerSecs"));
  ([.inbounds[] | select(.streamSettings.network == "xhttp") |
    {id:.tag,limits:(.streamSettings.xhttpSettings | limits)}] | sort_by(.id)) ==
  ([$spec[0].core.protocols[] | {id:.listener_id,limits:(.xhttp | limits)}] | sort_by(.id))
' "${candidate}/config/xray/users.base" >/dev/null
printf 'docker-xhttp-real-limits-config-ok: packet-up/stream-up=16384/5/16/1-2 default=3 server=spec\n'
jq -e '
  [.inbounds[] | select(.streamSettings.network == "xhttp") | .streamSettings.xhttpSettings] |
  length == 5 and all(has("download_port") or has("downloadSettings") | not)
' "${candidate}/config/xray/users.base" >/dev/null
jq -e '
  .services.xray.ports as $ports |
  all([35501,35502,35503,35505][]; . as $port |
    $ports | index("0.0.0.0:\($port+1000):\($port)/tcp") != null)
' "${candidate}/compose.json" >/dev/null
printf 'docker-xhttp-real-download-config-ok: server=unchanged split=4 alias=same-backend\n'
cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
cp -a "${candidate}/data/." "${PADM_DOCKER_INSTALL_DIR}/data/"
cp -a "${candidate}/logs/." "${PADM_DOCKER_INSTALL_DIR}/logs/"
cp -a "${candidate}/secrets/." "${PADM_DOCKER_INSTALL_DIR}/secrets/"
cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerCleanupConfigurationCandidate
dockerEnsureRuntimeDataPermissions
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
mkdir -p "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/tls" "${TEST_ROOT}/runtime/origin"
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" "${TEST_ROOT}/runtime/"
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}/runtime/client/config.json" "${SPEC}" <<'PY'
import json
from pathlib import Path
import re
import sys
import urllib.parse

expected = {
    35501: ("daily", "auto", "16-32", "600-900", "1800-3000", 1, True, True),
    35502: ("compatible", "packet-up", "16-32", "600-900", "1800-3000", "100-1000", True, False),
    35503: ("stream", "stream-up", "16-32", "600-900", "1800-3000", 4096, False, True),
    35504: ("single", "auto", 1, "600-900", "1800-3000", None, False, False),
    35505: ("custom", "auto", 2, "7-9", "30-40", None, None, None),
}
required = {"encryption", "security", "sni", "fp", "pbk", "sid", "type", "path", "host", "mode", "extra"}
limit_keys = {"scMaxEachPostBytes", "scMinPostsIntervalMs", "scMaxBufferedPosts", "scStreamUpServerSecs"}
spec = json.loads(Path(sys.argv[3]).read_text())
spec_entries = {entry["public_port"]: entry for entry in spec["core"]["protocols"]}
spec_limits = {entry["public_port"]: {key: value for key, value in entry["xhttp"].items() if key in limit_keys}
               for entry in spec["core"]["protocols"]}
assert spec_limits == {port: {"scMaxEachPostBytes": 16384, "scMinPostsIntervalMs": 5,
                             "scMaxBufferedPosts": 16, "scStreamUpServerSecs": "1-2"}
                       if port in (35502, 35503) else {} for port in expected}
def parse(line):
    uri = urllib.parse.urlsplit(line)
    q = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
    assert uri.scheme == "vless" and uri.hostname == "proxy.padm.test" and uri.password is None
    assert uri.username == "11111111-1111-4111-8111-111111111111" and uri.port in expected
    assert set(q) == required and all(len(values) == 1 and values[0] for values in q.values()), q
    q = {key: values[0] for key, values in q.items()}
    assert q["encryption"] == "none" and q["security"] == "reality" and q["type"] == "xhttp"
    extra = json.loads(q["extra"])
    assert isinstance(extra, dict) and {"xmux"} <= set(extra) <= {
        "xmux", "xPaddingBytes", "noGRPCHeader", "noSSEHeader", "headers", "downloadSettings"} | limit_keys
    assert isinstance(extra["xmux"], dict) and set(extra["xmux"]) == {
        "maxConcurrency", "hMaxRequestTimes", "hMaxReusableSecs"}
    if "xPaddingBytes" in extra:
        value = extra["xPaddingBytes"]
        if isinstance(value, str):
            assert re.fullmatch(r"[1-9][0-9]{0,3}-[1-9][0-9]{0,3}", value), value
            lower, upper = map(int, value.split("-"))
            assert 1 <= lower <= upper <= 4096, value
        else:
            assert type(value) is int and 1 <= value <= 4096, value
    for key in ("noGRPCHeader", "noSSEHeader"):
        if key in extra:
            assert type(extra[key]) is bool, (key, extra[key])
    for key in ("scMaxEachPostBytes", "scMinPostsIntervalMs", "scMaxBufferedPosts"):
        if key in extra:
            assert type(extra[key]) is int and 0 <= extra[key] <= 2147483647, (key, extra[key])
    if "scStreamUpServerSecs" in extra:
        value = extra["scStreamUpServerSecs"]
        if isinstance(value, str):
            assert re.fullmatch(r"(0|[1-9][0-9]{0,9})-(0|[1-9][0-9]{0,9})", value), value
            lower, upper = map(int, value.split("-"))
            assert 0 <= lower <= upper <= 2147483647, value
        else:
            assert type(value) is int and 0 <= value <= 2147483647, value
    if "downloadSettings" in extra:
        download = extra["downloadSettings"]
        assert isinstance(download, dict) and set(download) == {
            "address", "port", "network", "security", "realitySettings", "xhttpSettings"}, download
        assert download["address"] == uri.hostname and download["port"] == uri.port + 1000
        assert download["network"] == "xhttp" and download["security"] == "reality"
        assert download["realitySettings"] == {"serverName": q["sni"], "fingerprint": q["fp"],
            "publicKey": q["pbk"], "shortId": q["sid"]}
        expected_down = dict(spec_entries[uri.port]["xhttp"])
        expected_down.pop("download_port")
        expected_down["mode"] = "auto"
        assert download["xhttpSettings"] == expected_down, download
    return uri, q, extra
lines = Path(sys.argv[1]).read_text().splitlines()
assert len(lines) == 5
config = {"log":{"loglevel":"debug"}, "inbounds":[], "outbounds":[],
          "routing":{"rules":[]}}
seen = set()
for line in lines:
    uri, q, extra = parse(line)
    assert uri.port not in seen
    seen.add(uri.port)
    name, mode, maximum, requests, seconds, padding, no_grpc, no_sse = expected[uri.port]
    assert q["path"] == "/padm-"+name and q["host"] == q["sni"] == "reality.target.test"
    expected_extra = {"xmux":{
        "maxConcurrency":maximum, "hMaxRequestTimes":requests, "hMaxReusableSecs":seconds}}
    if padding is not None:
        expected_extra["xPaddingBytes"] = padding
    if no_grpc is not None:
        expected_extra["noGRPCHeader"] = no_grpc
    if no_sse is not None:
        expected_extra["noSSEHeader"] = no_sse
    expected_extra.update(spec_limits[uri.port])
    if name == "custom":
        expected_extra["headers"] = {"X-Padm-Trace": "Reality value & extra"}
    entry = spec_entries[uri.port]
    if "download_port" in entry["xhttp"]:
        down_settings = {key: value for key, value in entry["xhttp"].items() if key != "download_port"}
        down_settings["mode"] = "auto"
        expected_extra["downloadSettings"] = {"address": entry["server"],
            "port": entry["xhttp"]["download_port"], "network": "xhttp", "security": "reality",
            "realitySettings": {"serverName": q["sni"], "fingerprint": q["fp"],
                "publicKey": q["pbk"], "shortId": q["sid"]}, "xhttpSettings": down_settings}
    assert {key: value for key, value in extra.items() if key in limit_keys} == spec_limits[uri.port]
    assert q["mode"] == mode and extra == expected_extra
    inbound = "socks-"+name
    outbound = "xhttp-"+name
    config["inbounds"].append({"tag":inbound, "listen":"0.0.0.0",
        "port":2081+uri.port-35501, "protocol":"socks", "settings":{"auth":"noauth","udp":False}})
    config["outbounds"].append({"tag":outbound, "protocol":"vless", "settings":{"vnext":[{
        "address":"xray", "port":uri.port, "users":[{"id":uri.username,"encryption":q["encryption"]}]}]},
        "streamSettings":{"network":q["type"],"security":q["security"],
            "realitySettings":{"serverName":q["sni"],"fingerprint":q["fp"],
                "publicKey":q["pbk"],"shortId":q["sid"]},
            "xhttpSettings":{"path":q["path"],"host":q["host"],"mode":q["mode"],"extra":extra}}})
    config["routing"]["rules"].append({"type":"field","inboundTag":[inbound],"outboundTag":outbound})
sample = urllib.parse.urlsplit(lines[0])
sample_extra = json.loads(urllib.parse.parse_qs(sample.query)["extra"][0])
invalid = [[], {"xmux":None}, {"xmux":{"maxConcurrency":1}}, {"xPaddingBytes":1},
           dict(sample_extra, unknown=True)]
invalid += [dict(sample_extra, xPaddingBytes=value) for value in
            (None, 0, -1, True, 1.0, 4097, "1", "0-1", "1-0", "1000-100",
             "01-2", "1-4097", "1-2\n")]
invalid += [dict(sample_extra, **{key: value}) for key in ("noGRPCHeader", "noSSEHeader")
            for value in (None, 0, 1, 1.0, "true", "false", [], {})]
invalid += [dict(sample_extra, **{key: value}) for key in limit_keys
            for value in (None, -1, True, 1.0, 2147483648, "1", "2-1", "01-2", "1-2147483648", "1-2\n")]
for extra in invalid:
    query = urllib.parse.parse_qs(sample.query)
    query["extra"] = [json.dumps(extra)]
    try:
        parse(sample._replace(query=urllib.parse.urlencode(query, doseq=True)).geturl())
    except (AssertionError, ValueError):
        pass
    else:
        raise AssertionError("invalid extra accepted")
Path(sys.argv[2]).write_text(json.dumps(config))
# 只破坏下行端口；若核心忽略 downloadSettings，后续业务请求会意外成功。
broken = json.loads(json.dumps(config))
broken["inbounds"] = [item for item in broken["inbounds"] if item["tag"] != "socks-single"]
broken["outbounds"] = [item for item in broken["outbounds"] if item["tag"] != "xhttp-single"]
broken["routing"]["rules"] = [item for item in broken["routing"]["rules"] if item["outboundTag"] != "xhttp-single"]
for outbound in broken["outbounds"]:
    outbound["streamSettings"]["xhttpSettings"]["extra"]["downloadSettings"]["port"] = 9
Path(sys.argv[2]).with_name("broken.json").write_text(json.dumps(broken))
print("docker-xhttp-real-links-ok: presets=daily,compatible,stream,single custom=2/7-9/30-40 "
      "padding=1/100-1000/4096 default=2 headers=TT/TF/FT/FF/absent "
      "limits=dual-ended/spec/default-compatible download=4/same-identity source=protocol-links")
PY
# 本地 TLS 目标提供 Reality 需要的 TLS 1.3/h2 握手，测试不依赖公网。
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=reality.target.test \
    -addext subjectAltName=DNS:reality.target.test \
    -keyout "${TEST_ROOT}/runtime/tls/site.key" -out "${TEST_ROOT}/runtime/tls/site.crt" >/dev/null 2>&1
cat >"${TEST_ROOT}/runtime/tls/server.py" <<'PY'
import http.server
import ssl

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
    def log_message(self, *_):
        pass
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.set_alpn_protocols(["h2", "http/1.1"])
context.load_cert_chain("/tls/site.crt", "/tls/site.key")
server = http.server.ThreadingHTTPServer(("0.0.0.0",8443), Handler)
server.socket = context.wrap_socket(server.socket, server_side=True)
print("tls-ready", flush=True)
server.serve_forever()
PY
cat >"${TEST_ROOT}/runtime/origin/server.py" <<'PY'
import collections
import http.server
import json
import threading

counts = collections.Counter()
lock = threading.Lock()
barriers = {name:threading.Barrier(3) for name in ("daily","compatible","stream","single","custom")}
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.path.split("/")[2] == "compatible"
        assert self.rfile.read(int(self.headers["Content-Length"])) == b"x" * 32768
        self.do_GET()
    def do_GET(self):
        if self.path == "/counts":
            with lock:
                body = json.dumps(dict(counts), sort_keys=True).encode()
        else:
            _, proof, name, phase, number = self.path.split("/")
            assert proof == "proof" and name in barriers and phase in ("initial","recovery")
            with lock:
                counts[self.path] += 1
            # 同组的三条真实请求到齐再返回，确定触发 maxConcurrency=1/2 的分支。
            if phase == "initial":
                barriers[name].wait(timeout=15)
            body = ("padm-xhttp-real:"+self.path+"\n").encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *_):
        pass
http.server.ThreadingHTTPServer(("0.0.0.0",8088), Handler).serve_forever()
PY
chown -R 0:10001 "${TEST_ROOT}/runtime"
find "${TEST_ROOT}/runtime" -type d -exec chmod 750 {} +
find "${TEST_ROOT}/runtime" -type f -exec chmod 640 {} +
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" --arg ops "${OPS_ID}" '
  .name = $project | .networks.default.name = $project |
  .networks.default.labels["io.padm.test"] = $project |
  del(.services.acme) | .volumes = {files:{external:true,name:$volume}} |
  .services |= with_entries(
    .value.image = $xray | .value.labels["io.padm.test"] = $project |
    .value.volumes |= map(.source as $source |
      .type = "volume" | .source = "files" |
      .volume = {nocopy:true,subpath:("runtime/"+($source|ltrimstr("${PADM_DOCKER_ROOT}/")))} |
      del(.bind))) |
  .services.target = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
    networks:{default:{aliases:["reality.target.test"]}},labels:{"io.padm.test":$project},
    entrypoint:["python3","/tls/server.py"],
    volumes:[{type:"volume",source:"files",target:"/tls",read_only:true,
      volume:{nocopy:true,subpath:"runtime/tls"}}]} |
  .services.origin = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
    labels:{"io.padm.test":$project},entrypoint:["python3","/origin/server.py"],
    volumes:[{type:"volume",source:"files",target:"/origin",read_only:true,
      volume:{nocopy:true,subpath:"runtime/origin"}}]} |
  .services.client = {image:$xray,read_only:true,init:true,cap_drop:["ALL"],tmpfs:["/tmp"],
    labels:{"io.padm.test":$project},healthcheck:{disable:true},
    extra_hosts:{"proxy.padm.test":"host-gateway"},
    command:["run","-c","/client/config.json"],
    volumes:[{type:"volume",source:"files",target:"/client",read_only:true,
      volume:{nocopy:true,subpath:"runtime/client"}}]} |
  .services.broken = (.services.client | .command = ["run","-c","/client/broken.json"])
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() { docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"; }
compose config --format json >/dev/null
compose run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null
compose run --rm --no-deps client -test -c /client/config.json >/dev/null
compose run --rm --no-deps xray version | grep -q '^Xray 26\.3\.27 '
compose up -d --pull never target origin
docker run --rm -i --pull=never --network "${project}" --label "io.padm.test=${project}" \
    --entrypoint python3 "${OPS_ID}" - <<'PY'
import socket
import ssl
import time
import urllib.request

deadline = time.monotonic()+10
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.set_alpn_protocols(["h2"])
while True:
    try:
        with socket.create_connection(("reality.target.test",8443), timeout=1) as raw:
            with context.wrap_socket(raw, server_hostname="reality.target.test") as tls:
                assert tls.version() == "TLSv1.3" and tls.selected_alpn_protocol() == "h2"
        with urllib.request.urlopen("http://origin:8088/counts", timeout=1) as response:
            assert response.read() == b"{}"
        break
    except OSError:
        assert time.monotonic() < deadline, "本地 TLS 目标或原点未就绪"
        time.sleep(0.05)
print("docker-xhttp-real-local-target-ok: tls=1.3 alpn=h2 origin=ready")
PY
compose up -d --pull never --wait --wait-timeout 30 xray
compose up -d --pull never client broken
docker run --rm -i --pull=never --network "${project}" --label "io.padm.test=${project}" \
    --entrypoint python3 "${OPS_ID}" - <<'PY'
import concurrent.futures
import json
import socket
import struct
import time
import urllib.request

names = ("daily","compatible","stream","single","custom")
def connect(port, client):
    deadline = time.monotonic()+10
    while True:
        try:
            return socket.create_connection((client,port), timeout=0.2)
        except OSError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.05)
def probe(item, client="client"):
    name, phase, number = item
    path = f"/proof/{name}/{phase}/{number}"
    with connect(2081+names.index(name), client) as sock:
        sock.settimeout(3 if client == "broken" else 20)
        def receive(size):
            result = b""
            while len(result) < size:
                part = sock.recv(size-len(result))
                if not part:
                    raise EOFError(result)
                result += part
            return result
        sock.sendall(b"\x05\x01\x00")
        assert receive(2) == b"\x05\x00"
        host = b"origin"
        sock.sendall(b"\x05\x01\x00\x03"+bytes([len(host)])+host+struct.pack("!H",8088))
        head = receive(4)
        if head[:2] != b"\x05\x00":
            raise OSError(f"SOCKS CONNECT rejected: {item} {head!r}")
        if head[3] == 1:
            receive(4)
        elif head[3] == 4:
            receive(16)
        elif head[3] == 3:
            receive(receive(1)[0])
        else:
            raise AssertionError(head)
        receive(2)
        if name == "compatible":
            # 沿用原有四次业务请求，上传超过单个 packet-up POST 上限的数据。
            payload = b"x" * 32768
            sock.sendall(f"POST {path} HTTP/1.1\r\nHost: origin\r\nContent-Length: {len(payload)}\r\n"
                         "Connection: close\r\n\r\n".encode() + payload)
        else:
            sock.sendall(f"GET {path} HTTP/1.1\r\nHost: origin\r\nConnection: close\r\n\r\n".encode())
        result = b""
        while True:
            part = sock.recv(4096)
            if not part:
                break
            result += part
        if not result:
            raise EOFError("业务连接未收到响应")
        head, body = result.split(b"\r\n\r\n",1)
        assert head.startswith(b"HTTP/1.0 200") and body == ("padm-xhttp-real:"+path+"\n").encode(), (item,result)
    return path
with concurrent.futures.ThreadPoolExecutor(max_workers=15) as pool:
    futures = []
    for number in range(3):
        futures += [pool.submit(probe, (name,"initial",number)) for name in names]
        if number < 2:
            # 前一批已到达原点时再打开下一批，保证现存连接占用已生效。
            reached = {f"/proof/{name}/initial/{index}" for name in names for index in range(number+1)}
            deadline = time.monotonic()+10
            while True:
                counts = json.load(urllib.request.urlopen("http://origin:8088/counts", timeout=5))
                if reached <= set(counts):
                    break
                assert time.monotonic() < deadline, ("origin arrival timeout",counts)
                time.sleep(0.02)
    paths = [future.result() for future in futures]
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    paths += list(pool.map(probe, [(name,"recovery",0) for name in names]))
def reject_broken(name):
    try:
        probe((name, "recovery", 1), client="broken")
    except (OSError, EOFError):
        return
    raise AssertionError(f"坏下行端口未阻断真实业务: {name}")
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(reject_broken, (name for name in names if name != "single")))
counts = json.load(urllib.request.urlopen("http://origin:8088/counts", timeout=5))
assert all(counts.get(path) == 1 for path in paths), counts
# 下行失败时，上行可能已经抵达原点；只有客户端拿到响应才算业务成功。
broken_paths = {f"/proof/{name}/recovery/1" for name in names if name != "single"}
assert set(counts) - set(paths) <= broken_paths and all(value == 1 for value in counts.values()), counts
print("docker-xhttp-real-probe-ok: origin-proof-count=20 initial=15 recovery=5 presets=4 custom=1 "
      "packet-upload=32768>16384 download=auto/packet-up/stream-up/custom broken-download=4-rejected")
PY
compose logs --no-color client >"${TEST_ROOT}/client.log"
python3 - "${TEST_ROOT}/client.log" <<'PY'
from pathlib import Path
import re
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
modes = {35501:{"packet-up","stream-up"},35502:{"packet-up"},35503:{"stream-up"},
         35504:{"stream-one"},35505:{"packet-up","stream-up"}}
connections = {}
xmux = {}
for line in lines:
    match = re.search(r"\[(\d+)\].*XHTTP is dialing to tcp:xray:(3550[1-5]), mode ([a-z-]+), HTTP version (\d), host reality.target.test", line)
    if match:
        connection, port, mode, version = match.groups()
        port = int(port)
        assert mode in modes[port] and version == "2", line
        connections[connection] = port
    match = re.search(r"\[(\d+)\].*XMUX: creating xmuxClient because (.+)", line)
    if match:
        xmux[match[1]] = match[2]
assert set(connections.values()) == set(modes), connections
for port in modes:
    assert any(connections.get(connection) == port for connection in xmux), (port,xmux)
for port in (35504,35505):
    assert any(connections.get(connection) == port and reason.startswith("maxConcurrency was hit")
               for connection, reason in xmux.items()), (port,xmux)
print("docker-xhttp-real-runtime-ok: h2=5 modes=stream-one/packet-up/stream-up xmux=5 single/custom=maxConcurrency-hit")
PY
[[ "$(docker inspect --format '{{.State.Health.Status}}' "$(compose ps -q xray)")" == healthy ]]
printf 'docker-xhttp-real-ok: target=local-tls13-h2 source=protocol-links padding=dual-ended/default-compatible headers=dual-ended/explicit-false/absent limits=dual-ended/default-compatible download=4/production-alias/broken-port-rejected server-xmux=unchanged xray=%s ops=%s\n' \
    "${XRAY_ID}" "${OPS_ID}"
