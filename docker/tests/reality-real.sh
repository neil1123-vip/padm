#!/usr/bin/env bash
set -euo pipefail

# 只在本次唯一项目与命名卷中验收，不连接或覆盖现有 padm 部署。
[[ "$#" == 3 || ( "$#" == 4 && ( "$4" == regenerate || "$4" == mldsa65 ) ) ]] || {
    printf 'usage: reality-real.sh <local-xray> <local-sing-box> <local-ops> [regenerate|mldsa65]\n' >&2
    exit 2
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'reality-real.sh requires Linux root\n' >&2
    exit 1
}
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
XRAY_REF=$1 SING_REF=$2 OPS_REF=$3
MODE=${4:-connect}
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
            while IFS= read -r id; do
                printf 'docker-reality-real-container-log: %s\n' "$(docker inspect --format '{{.Name}}' "${id}")" >&2
                docker logs "${id}" >&2 || true
            done <<<"${ids}"
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
if [[ "${MODE}" == mldsa65 ]]; then
    # 固定核心生成真实配对；直接装入隔离夹具，不冒充 CLI 目标探测自动启用验收。
    (umask 077; dockerSetupTool "${XRAY_ID}" mldsa65 >"${TEST_ROOT}/mldsa65.keys")
    python3 - "${SPEC}" "${TEST_ROOT}/mldsa65.keys" "${TEST_ROOT}/mldsa65-mismatch.json" <<'PY'
import base64
import json
import pathlib
import sys

spec, keys, mismatch = map(pathlib.Path, sys.argv[1:])
pair = dict(line.split(":", 1) for line in keys.read_text().splitlines() if ":" in line)
seed, verify = (pair[name].strip() for name in ("Seed", "Verify"))
for value, size in ((seed, 32), (verify, 1952)):
    raw = base64.b64decode(value+"="*(-len(value)%4), altchars=b"-_", validate=True)
    assert len(raw) == size and base64.urlsafe_b64encode(raw).decode().rstrip("=") == value
value = json.loads(spec.read_text())
for item in value["core"]["protocols"]:
    item["reality"].update(target_host="reality-target.padm.test", target_port=8443)
entry = next(item for item in value["core"]["protocols"] if item["listener_id"] == "entry-xhttp")
entry["reality"].update(mldsa65_seed=seed, mldsa65_verify=verify)
spec.write_text(json.dumps(value))
public = bytearray(base64.urlsafe_b64decode(verify+"="*(-len(verify)%4)))
public[0] ^= 1
entry["reality"]["mldsa65_verify"] = base64.urlsafe_b64encode(public).decode().rstrip("=")
mismatch.write_text(json.dumps(value))
mismatch.chmod(0o600)
PY
    dockerConfigureSpecValidate "${SPEC}" || {
        printf 'ML-DSA real fixture schema validation failed\n' >&2
        exit 1
    }
    dockerRealityMldsa65Validate "${SPEC}" "${OPS_ID}" || {
        printf 'ML-DSA real pair derivation validation failed\n' >&2
        exit 1
    }
    dockerConfigureSpecValidate "${TEST_ROOT}/mldsa65-mismatch.json"
    if dockerRealityMldsa65Validate "${TEST_ROOT}/mldsa65-mismatch.json" "${OPS_ID}"; then
        printf 'ML-DSA mismatched real pair accepted\n' >&2
        exit 1
    fi
    rm -f -- "${TEST_ROOT}/mldsa65.keys" "${TEST_ROOT}/mldsa65-mismatch.json"
    printf 'docker-reality-mldsa65-pair-ok: source=fixed-xray real-pair=accepted mismatched-pair=rejected\n'
fi
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
dockerEnsureRuntimeDataPermissions
dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
[[ "$(wc -l <"${TEST_ROOT}/links.txt")" == 3 ]]
if [[ "${MODE}" == regenerate ]]; then
    cp "${TEST_ROOT}/links.txt" "${TEST_ROOT}/old-links.txt"
    cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${TEST_ROOT}/snapshot"
    snapshot_hash=$(find "${TEST_ROOT}/snapshot" -type f -print0 | sort -z | xargs -0 sha256sum)
    jq -n --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
      name:"real-account",upload:11,download:17,limit_bytes:1000000,
      baseline:{xray:{upload:{generation:"before-regenerate",value:7}}}}}}' |
        dockerTrafficWriteState
    state_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
    for core in xray sing-box; do
        dockerTrafficAccounts "${core}" >"${TEST_ROOT}/accounts-${core}.json"
    done
    # 真实本机 image ID 只用于夹具中的已验证镜像映射，不绕过生产 CLI 的发布验证。
    dockerManifestImageReference() {
        case "$1" in xray) printf '%s\n' "${XRAY_ID}" ;; ops) printf '%s\n' "${OPS_ID}" ;; *) return 1 ;; esac
    }
    for listener in entry-xhttp entry-grpc-sing; do
        cp "${SPEC}" "${TEST_ROOT}/before-regenerate.json"
        dockerEditRegenerateReality "${SPEC}" "${listener}"
        dockerConfigureSpecValidate "${SPEC}"
        jq -en --arg listener "${listener}" --slurpfile before "${TEST_ROOT}/before-regenerate.json" \
            --slurpfile after "${SPEC}" '
          def fixed: .core.protocols |= map(if .listener_id == $listener then
            del(.reality.private_key,.reality.public_key,.reality.short_id,
              .reality.mldsa65_seed,.reality.mldsa65_verify) else . end);
          (first($before[0].core.protocols[] | select(.listener_id == $listener)).reality) as $old |
          (first($after[0].core.protocols[] | select(.listener_id == $listener)).reality) as $new |
          ($before[0] | fixed) == ($after[0] | fixed) and
          $new.private_key != $old.private_key and $new.public_key != $old.public_key and
          $new.short_id != $old.short_id
        ' >/dev/null
    done
    dockerCreateConfigurationCandidate
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${SPEC}" "${candidate}"
    for core in xray sing-box; do
        jq -en --arg core "${core}" --slurpfile before "${TEST_ROOT}/snapshot/${core}/users.base" \
            --slurpfile after "${candidate}/config/${core}/users.base" '
          def fixed: .inbounds |= map(
            if $core == "xray" and .tag == "entry-xhttp" then
              del(.streamSettings.realitySettings.privateKey,.streamSettings.realitySettings.shortIds,
                .streamSettings.realitySettings.mldsa65Seed,.streamSettings.realitySettings.mldsa65Verify)
            elif $core == "sing-box" and .tag == "entry-grpc-sing" then
              del(.tls.reality.private_key,.tls.reality.short_id)
            else . end);
          ($before[0] | fixed) == ($after[0] | fixed)
        ' >/dev/null
    done
    cp -a "${candidate}/config/." "${PADM_DOCKER_INSTALL_DIR}/config/"
    cp "${candidate}/compose.json" "${candidate}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/"
    cp "${candidate}/images.runtime.env" "${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerCleanupConfigurationCandidate
    dockerEnsureRuntimeDataPermissions
    dockerProtocolCommand links >"${TEST_ROOT}/links.txt"
    for core in xray sing-box; do
        dockerTrafficAccounts "${core}" | jq -e --slurpfile before "${TEST_ROOT}/accounts-${core}.json" \
            '. == $before[0]' >/dev/null
    done
    [[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" == "${state_hash}" ]]
    [[ "$(find "${TEST_ROOT}/snapshot" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${snapshot_hash}" ]]
fi
# 客户端只从 URI 取得协议参数，规格不参与生成；仅公开端点映射到隔离服务名。
python3 - "${TEST_ROOT}/links.txt" "${TEST_ROOT}" "${MODE}" <<'PY'
import copy
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
    if "pqv" in q:
        required.add("pqv")
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
        if "pqv" in q:
            xray["outbounds"][-1]["streamSettings"]["realitySettings"]["mldsa65Verify"] = q["pqv"]
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
if sys.argv[3] == "mldsa65":
    xray["log"]["loglevel"] = "info"
    sing["log"]["level"] = "info"
(out/"client-xray.json").write_text(json.dumps(xray))
(out/"client-sing.json").write_text(json.dumps(sing))
if sys.argv[3] == "mldsa65":
    import base64
    verify = xray["outbounds"][0]["streamSettings"]["realitySettings"]["mldsa65Verify"]
    assert len(verify) == 2603
    wrong_verify = copy.deepcopy(xray)
    wrong_verify["inbounds"][0]["port"] = 2086
    public = bytearray(base64.urlsafe_b64decode(verify+"="*(-len(verify)%4)))
    public[0] ^= 1
    wrong_verify["outbounds"][0]["streamSettings"]["realitySettings"]["mldsa65Verify"] = (
        base64.urlsafe_b64encode(public).decode().rstrip("="))
    wrong_auth = copy.deepcopy(xray)
    wrong_auth["inbounds"][0]["port"] = 2087
    wrong_auth["outbounds"][0]["settings"]["vnext"][0]["users"][0]["id"] = "22222222-2222-4222-8222-222222222222"
    (out/"client-wrong-verify.json").write_text(json.dumps(wrong_verify))
    (out/"client-wrong-auth.json").write_text(json.dumps(wrong_auth))
if sys.argv[3] == "regenerate":
    previous = {}
    current = {}
    for line in (out/"old-links.txt").read_text().splitlines():
        uri,q = parse(line)
        previous[uri.port] = (line,uri,q)
    for line in lines:
        uri,q = parse(line)
        current[uri.port] = (line,uri,q)
    assert current[35452][0] == previous[35452][0]
    for port in (35451,35453):
        before = previous[port][2]
        after = current[port][2]
        assert {k:v for k,v in before.items() if k not in ("pbk","sid","pqv")} == {
            k:v for k,v in after.items() if k not in ("pbk","sid","pqv")}
        assert previous[port][1].username == current[port][1].username
        assert before["pbk"] != after["pbk"] and before["sid"] != after["sid"]
    old_xray = copy.deepcopy(xray)
    old_xray["inbounds"][0]["port"] = 2084
    old_xray["outbounds"][0]["streamSettings"]["realitySettings"].update(
        publicKey=previous[35451][2]["pbk"],shortId=previous[35451][2]["sid"])
    old_xray["outbounds"][0]["streamSettings"]["realitySettings"].pop("mldsa65Verify", None)
    old_sing = copy.deepcopy(sing)
    old_sing["inbounds"] = [dict(old_sing["inbounds"][1],listen_port=2085)]
    old_sing["outbounds"] = [old_sing["outbounds"][1]]
    old_sing["route"]["rules"] = [old_sing["route"]["rules"][1]]
    old_sing["outbounds"][0]["tls"]["reality"].update(
        public_key=previous[35453][2]["pbk"],short_id=previous[35453][2]["sid"])
    (out/"client-old-xray.json").write_text(json.dumps(old_xray))
    (out/"client-old-sing.json").write_text(json.dumps(old_sing))
PY
mkdir -p "${TEST_ROOT}/runtime/client" "${TEST_ROOT}/runtime/origin"
cp -a "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" "${TEST_ROOT}/runtime/"
cp "${TEST_ROOT}/client-xray.json" "${TEST_ROOT}/runtime/client/xray.json"
cp "${TEST_ROOT}/client-sing.json" "${TEST_ROOT}/runtime/client/sing.json"
if [[ "${MODE}" == regenerate ]]; then
    cp "${TEST_ROOT}/client-old-xray.json" "${TEST_ROOT}/runtime/client/old-xray.json"
    cp "${TEST_ROOT}/client-old-sing.json" "${TEST_ROOT}/runtime/client/old-sing.json"
fi
if [[ "${MODE}" == mldsa65 ]]; then
    cp "${TEST_ROOT}/client-wrong-verify.json" "${TEST_ROOT}/runtime/client/wrong-verify.json"
    cp "${TEST_ROOT}/client-wrong-auth.json" "${TEST_ROOT}/runtime/client/wrong-auth.json"
    mkdir -p "${TEST_ROOT}/runtime/target"
    # 目标只提供并发 TLS 握手；串行 s_server 会让另一条 Reality 握手等待前一连接。
    cat >"${TEST_ROOT}/runtime/target/server.py" <<'PY'
import socketserver
import ssl

context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_3
context.maximum_version = ssl.TLSVersion.TLSv1_3
context.load_cert_chain("/target/cert.pem", "/target/key.pem")
context.set_alpn_protocols(["h2", "http/1.1"])

class Target(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            self.request.settimeout(10)
            with context.wrap_socket(self.request, server_side=True) as tls:
                while tls.recv(65536):
                    pass
        except OSError:
            pass

class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True

with Server(("0.0.0.0", 8443), Target) as server:
    server.serve_forever()
PY
fi
printf 'padm-reality-real-proof\n' >"${TEST_ROOT}/runtime/origin/proof.txt"
# docker cp 到停止容器可能重写归属；tar 流保持生产夹具的 UID/GID 和权限模式。
tar -cpf - -C "${TEST_ROOT}" runtime |
    docker run --rm -i --pull=never --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint tar "${OPS_ID}" -xpf - -C /test
if [[ "${MODE}" == mldsa65 ]]; then
    # 长证书留出签名空间，本地目标避免公网证书轮换和出口条件影响握手结论。
    docker run --rm --pull=never --network none --log-driver none --label "io.padm.test=${project}" \
        --user 0 --mount "type=volume,source=${volume},target=/test" --entrypoint python3 "${OPS_ID}" -c '
import os
import pathlib
import shutil
import subprocess

os.umask(0o077)
root = pathlib.Path("/test/runtime/target")
names = ["DNS:www.debian.org","DNS:reality-target.padm.test"] + [
    "DNS:padding-%03d.padm.test"%n for n in range(160)]
subprocess.run(["openssl","req","-x509","-newkey","rsa:2048","-sha256","-days","1","-nodes",
    "-subj","/CN=www.debian.org","-addext","subjectAltName="+",".join(names),
    "-keyout",str(root/"key.pem"),"-out",str(root/"cert.pem")],
    check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=30)
der = subprocess.check_output(["openssl","x509","-in",str(root/"cert.pem"),"-outform","DER"])
assert len(der) > 3500, len(der)
for path in root.iterdir():
    os.chown(path,10001,10001)
os.chmod(root/"server.py",0o644)
shutil.copyfile(root/"cert.pem","/test/runtime/client/target-cert.pem")
os.chmod("/test/runtime/client/target-cert.pem",0o644)
'
fi
COMPOSE="${TEST_ROOT}/compose.json"
jq --arg project "${project}" --arg volume "${volume}" --arg xray "${XRAY_ID}" \
    --arg sing "${SING_ID}" --arg ops "${OPS_ID}" --arg mode "${MODE}" '
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
      volume:{nocopy:true,subpath:"runtime/client"}}]} |
  if $mode == "regenerate" then
    .services["client-old-xray"] = (.services["client-xray"] |
      .command = ["run","-c","/etc/padm/client/old-xray.json"]) |
    .services["client-old-sing"] = (.services["client-sing"] |
      .command = ["run","-c","/etc/padm/client/old-sing.json"])
  else . end |
  if $mode == "mldsa65" then
    .services["reality-target"] = {image:$ops,read_only:true,init:true,cap_drop:["ALL"],
      labels:{"io.padm.test":$project},entrypoint:["python3","/target/server.py"],
      networks:{default:{aliases:["reality-target.padm.test"]}},
      healthcheck:{test:["CMD","python3","-c",
        "import socket; socket.create_connection((\"127.0.0.1\",8443),timeout=1).close()"],
        interval:"1s",timeout:"2s",retries:30},
      volumes:[{type:"volume",source:"files",target:"/target",read_only:true,
        volume:{nocopy:true,subpath:"runtime/target"}}]} |
    .services["client-wrong-verify"] = (.services["client-xray"] |
      .command = ["run","-c","/etc/padm/client/wrong-verify.json"]) |
    .services["client-wrong-auth"] = (.services["client-xray"] |
      .command = ["run","-c","/etc/padm/client/wrong-auth.json"])
  else . end
' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >"${COMPOSE}"
compose() {
    docker compose --project-name "${project}" --file "${COMPOSE}" --profile '*' "$@"
}
compose config --format json >/dev/null
compose run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null
compose run --rm --no-deps sing-box check -c /etc/padm/sing-box/config.json >/dev/null
compose run --rm --no-deps client-xray -test -c /etc/padm/client/xray.json >/dev/null
compose run --rm --no-deps client-sing check -c /etc/padm/client/sing.json >/dev/null
if [[ "${MODE}" == regenerate ]]; then
    compose run --rm --no-deps client-old-xray -test -c /etc/padm/client/old-xray.json >/dev/null
    compose run --rm --no-deps client-old-sing check -c /etc/padm/client/old-sing.json >/dev/null
fi
if [[ "${MODE}" == mldsa65 ]]; then
    compose run --rm --no-deps client-wrong-verify -test -c /etc/padm/client/wrong-verify.json >/dev/null
    compose run --rm --no-deps client-wrong-auth -test -c /etc/padm/client/wrong-auth.json >/dev/null
    compose up -d --pull never --wait --wait-timeout 60 reality-target
    # 只给独立探针信任夹具证书；真实 Reality 客户端仍通过分享材料验签。
    compose run --rm --no-deps -e SSL_CERT_FILE=/etc/padm/client/target-cert.pem client-xray \
        tls ping reality-target.padm.test:8443 >"${TEST_ROOT}/target-ping.txt"
    awk '/Pinging with SNI/{inSni=1; next}
      inSni && /Handshake succeeded/{handshake=1}
      inSni && /TLS Version:.*TLS 1\.3/{tls13=1}
      inSni && /TLS Post-Quantum key exchange:.*true.*X25519MLKEM768/{pqc=1}
      inSni && /Certificate chain/ && $5 + 0 > 3500 {chain=1}
      END{exit handshake && tls13 && pqc && chain ? 0 : 1}' "${TEST_ROOT}/target-ping.txt" || {
        cat "${TEST_ROOT}/target-ping.txt" >&2
        exit 1
    }
    docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
        --mount "type=volume,source=${volume},target=/test,readonly" --entrypoint python3 "${OPS_ID}" -c '
import socket
import ssl

context=ssl.create_default_context(cafile="/test/runtime/client/target-cert.pem")
context.set_alpn_protocols(["h2","http/1.1"])
with socket.create_connection(("reality-target.padm.test",8443),timeout=5) as sock:
    with context.wrap_socket(sock,server_hostname="reality-target.padm.test") as tls:
        assert tls.version()=="TLSv1.3" and tls.selected_alpn_protocol()=="h2"
        assert len(tls.getpeercert(binary_form=True)) > 3500
print("docker-reality-target-probe-ok: tls=1.3 pqc=X25519MLKEM768 alpn=h2 chain=long")
'
    # 固定新核心默认阻断 VLESS 私网出口；只在隔离副本允许本次 origin 的 TCP 8088。
    # 不修改生产生成原件、分享材料或认证校验，仅添加本次测试原点的放行规则。
    generated_xray_hash=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json")
    compose up -d --pull never --wait --wait-timeout 60 origin
    origin_ips=$(docker inspect --format '{{json .NetworkSettings.Networks}}' "$(compose ps -q origin)" |
        jq -ce '[.[] | .IPAddress,.GlobalIPv6Address | select(length>0)] | select(length>0)')
    docker run --rm --pull=never --network none --label "io.padm.test=${project}" --user 0 \
        --mount "type=volume,source=${volume},target=/test" --entrypoint python3 "${OPS_ID}" -c '
import ipaddress
import json
import pathlib
import sys

path=pathlib.Path("/test/runtime/config/xray/config.json")
value=json.loads(path.read_text())
outbound=next(item for item in value["outbounds"] if item["tag"]=="direct")
assert outbound["protocol"]=="freedom"
settings=outbound.setdefault("settings",{})
assert "finalRules" not in settings
addresses=[ipaddress.ip_address(value) for value in json.loads(sys.argv[1])]
assert addresses
settings["finalRules"]=[{"action":"allow","network":"tcp","port":"8088",
    "ip":[str(ipaddress.ip_network(str(address))) for address in addresses]}]
value["log"]["loglevel"]="info"
path.write_text(json.dumps(value))
print("docker-reality-origin-fixture-ok: exact-addresses=%s tcp-port=8088 test-only=true"%len(addresses))
' "${origin_ips}"
    [[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json")" == "${generated_xray_hash}" ]]
    compose run --rm --no-deps xray -test -confdir /etc/padm/xray >/dev/null
fi
compose up -d --pull never --wait --wait-timeout 60 xray sing-box origin
compose up -d --pull never client-xray client-sing
if [[ "${MODE}" == regenerate ]]; then
    compose up -d --pull never client-old-xray client-old-sing
fi
if [[ "${MODE}" == mldsa65 ]]; then
    compose up -d --pull never client-wrong-verify client-wrong-auth
fi
# 只等待 SOCKS 监听，然后每条 URI 执行一次真正请求，不用重试掩盖握手错误。
docker run --rm --pull=never --network "${project}" --label "io.padm.test=${project}" \
    --entrypoint python3 "${OPS_ID}" -c '
import concurrent.futures
import http.client
import socket
import struct
import sys
import time

def connect(endpoint):
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
    return sock

def request_proof(endpoint):
    host,port = endpoint
    with connect(endpoint) as sock:
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
        expected=b"padm-reality-real-proof\n"
        body=b""
        stage="http-headers"
        with http.client.HTTPResponse(sock) as response:
            try:
                response.begin()
                assert response.status == 200, response.status
                assert response.headers.get_all("Content-Length") == [str(len(expected))]
                assert response.getheader("Transfer-Encoding") is None
                stage="http-body"
                while len(body) < len(expected):
                    part=response.read1(len(expected)-len(body))
                    if not part:
                        raise http.client.IncompleteRead(body,len(expected)-len(body))
                    body+=part
                assert body == expected, body
            except (EOFError,OSError,AssertionError,ValueError,http.client.HTTPException) as error:
                error.add_note("HTTP proof stage=%s body_received=%s expected=%s parsed_headers=%s"%(
                    stage,len(body),len(expected),len(response.headers or [])))
                raise
    return "%s:%s"%(host,port)

def probe(endpoint):
    print("docker-reality-probe-start: %s:%s"%endpoint,flush=True)
    try:
        result=request_proof(endpoint)
    except (EOFError,OSError,AssertionError,ValueError,http.client.HTTPException) as error:
        error.add_note("Reality proof endpoint: %s:%s"%endpoint)
        raise
    print("docker-reality-probe-ok: "+result,flush=True)
    return result

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    futures={pool.submit(probe,endpoint):endpoint for endpoint in (
        ("client-xray",2081),("client-sing",2082),("client-sing",2083))}
    results=[]
    failures=[]
    for future in concurrent.futures.as_completed(futures):
        try:
            results.append(future.result())
        except (EOFError,OSError,AssertionError,ValueError,http.client.HTTPException) as error:
            endpoint=futures[future]
            print("docker-reality-probe-failed: %s:%s %s: %s"%(
                *endpoint,type(error).__name__,error),file=sys.stderr,flush=True)
            failures.append(error)
if not failures:
    print("docker-reality-real-probe-ok: source=protocol-links socks="+",".join(results))
if sys.argv[1] == "regenerate":
    for endpoint in (("client-old-xray",2084),("client-old-sing",2085)):
        with connect(endpoint) as sock:
            sock.settimeout(5)
            sock.sendall(b"\x05\x01\x00")
            assert sock.recv(2) == b"\x05\x00", ("old client SOCKS unavailable",endpoint)
        try:
            probe(endpoint)
        except (EOFError,OSError,AssertionError,ValueError,http.client.HTTPException):
            print("docker-reality-old-credential-rejected: %s:%s"%endpoint)
        else:
            raise AssertionError(("old Reality credential accepted",endpoint))
if sys.argv[1] == "mldsa65":
    for endpoint, reason in ((("client-wrong-verify",2086),"wrong-verify"),
                             (("client-wrong-auth",2087),"wrong-authentication")):
        probe(("client-xray",2081))
        with connect(endpoint) as sock:
            sock.settimeout(5)
            sock.sendall(b"\x05\x01\x00")
            assert sock.recv(2) == b"\x05\x00", ("negative client SOCKS unavailable",endpoint)
        try:
            probe(endpoint)
        except (EOFError,OSError,AssertionError,ValueError,http.client.HTTPException):
            print("docker-reality-mldsa65-rejected: "+reason)
        else:
            raise AssertionError(("invalid ML-DSA client accepted",reason))
        probe(("client-xray",2081))
    print("docker-reality-mldsa65-real-ok: source=protocol-links pqv=used valid-before-and-after=passed")
if failures:
    raise ExceptionGroup("Reality positive proof failed",failures)
' "${MODE}"
target=www.debian.org
[[ "${MODE}" != mldsa65 ]] || target=reality-target.padm.test
printf 'docker-reality-real-ok: mode=%s target=%s endpoint=isolated-compose xray=%s sing-box=%s ops=%s\n' \
    "${MODE}" "${target}" "${XRAY_ID}" "${SING_ID}" "${OPS_ID}"
