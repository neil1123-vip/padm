#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-cdn.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-cdn-entries-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in bash shellcheck jq python3 stat chmod chown find sort sha256sum; do command -v "${tool}" >/dev/null; done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
UUID=11111111-1111-4111-8111-111111111111
ACCOUNT=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
LOG=${TEST_ROOT}/command.log
MODE=ok
fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-cdn-entries-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }
# 只替换发布与宿主服务动作，校验、订阅、权限、锁和部署事务仍使用生产实现。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerSetupRealityPublicKey() {
    [[ "$(cat)" == dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo ]] || return 1
    printf '%s\n' hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo
}
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerTlsValidateCandidate() { :; }
dockerIPv6NetworkManage() { :; }
dockerConfigurePortsAvailable() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"
}
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerCandidateCompose() {
    [[ -d "$1" && -e "${root}/locks/deployment.lock" ]] || fail '候选未持有部署锁'
}
docker() {
    [[ "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False" &&
        "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban-control --filter label=com.docker.compose.oneoff=False" &&
        "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-fail2ban-ssh --filter label=com.docker.compose.oneoff=False" &&
        "$*" != "ps -aq --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False" ]] || return 0
    command docker "$@"
}
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '发布未持有部署锁'
    if [[ "${1:-}" == up && "${MODE}" == health-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
}
dockerComposeExecute() {
    [[ "$*" == down ]] || fail "意外恢复启停参数: $*"
    dockerComposeRun "$@"
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${TEST_ROOT}/bundle/docker/contracts/"
dockerInitializeStateRoot
jq -n --arg uuid "${UUID}" --arg account "${ACCOUNT}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[
     {id:1,core:"xray",listener_id:"entry-reality",server:"origin.example.com",
      public_port:35001,address_families:["ipv4","ipv6"],name:"Reality",uuid:$uuid,
      reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
        private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
        public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}},
     (21,22,23,24,25 | . as $protocol |
       {id:$protocol,core:"xray",listener_id:("entry-"+($protocol|tostring)),
        server:"origin.example.com",public_port:(35000+$protocol),
        address_families:["ipv4","ipv6"],name:("Protocol-"+($protocol|tostring)),uuid:$uuid} +
       {(if $protocol >= 24 then "grpc_tls"
         elif $protocol == 23 then "httpupgrade" else "websocket" end):
         ({domain:"tls.example.com",backend_port:(40000+$protocol),tls_port:(41000+$protocol)} +
          if $protocol >= 24 then {service_name:("cdn_grpc-"+($protocol|tostring))}
          else {path:("cdn-path"+($protocol|tostring))} end)})
   ]},tls:{domain:"tls.example.com"},subscription:{enabled:true,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[],accounts:[
     {id:$account,name:"Alice",enabled:true,uuid:"44444444-4444-4444-8444-444444444444",
      password:"Alice.-~@+=:Secret",shadowsocks_password:null,
      listeners:["entry-reality","entry-21","entry-22","entry-23","entry-24","entry-25"]},
     {id:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",name:"Disabled",enabled:false,
      uuid:"55555555-5555-4555-8555-555555555555",password:"Disabled-secret01",
      shadowsocks_password:null,listeners:["entry-21","entry-22","entry-23","entry-24","entry-25"]}],
   port_aliases:[21,22,23,24,25 | {listener_id:("entry-"+(tostring)),public_port:(51000+.),share_default:true}]}
' >"${TEST_ROOT}/base.json"

# Schema 检查字段形状，生产校验还检查唯一入口、协议允许范围和严格地址。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "base.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
cases = []

def case(name, value, valid, schema_valid=None):
    expected = valid if schema_valid is None else schema_valid
    assert validator.is_valid(value) == expected, (
        name, [(list(error.path), error.message) for error in validator.iter_errors(value)])
    (root / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

case("base", base, True)
cdn = copy.deepcopy(base)
cdn["cdn_entries"] = [
    {"listener_id": "entry-21", "addresses": ["edge.example.com", "2001:db8::21"]},
    {"listener_id": "entry-22", "addresses": ["192.0.2.22", "2001:db8:0:0:0:0:0:22"]},
    {"listener_id": "entry-23", "addresses": ["edge23.example.com"]},
    {"listener_id": "entry-24", "addresses": ["192.0.2.24", "2001:db8::24", "edge24.example.com"]},
    {"listener_id": "entry-25", "addresses": ["edge25.example.com", "2001:db8::25"]}]
case("cdn", cdn, True)
value = copy.deepcopy(cdn)
value["cdn_entries"][0]["addresses"] = [f"edge{n}.example.com" for n in range(16)]
case("sixteen-addresses", value, True)
value = copy.deepcopy(cdn)
value["core"]["protocols"] = []
value["cdn_entries"] = []
value["accounts"] = []
value["port_aliases"] = []
for n in range(16):
    entry = copy.deepcopy(base["core"]["protocols"][1])
    entry.update(listener_id=f"entry-count-{n}", public_port=36000+n, name=f"Count-{n}")
    entry["websocket"].update(path=f"count-path{n}", backend_port=42000+n, tls_port=43000+n)
    value["core"]["protocols"].append(entry)
    value["cdn_entries"].append({"listener_id": entry["listener_id"],
                                 "addresses": ["edge.example.com"]})
del value["accounts"], value["port_aliases"]
case("sixteen-records", value, True)
for index, bad in enumerate((None, {}, [], True, "edge.example.com", [None],
                             [{"listener_id": "entry-21"}],
                             [{"listener_id": "entry-21", "addresses": ["edge.example.com"],
                               "extra": True}], cdn["cdn_entries"] * 6)):
    value = copy.deepcopy(cdn)
    value["cdn_entries"] = bad
    case(f"invalid-records-{index}", value, False)
for index, bad in enumerate((None, {}, [], True, "edge.example.com", [None],
                             ["edge.example.com"] * 2,
                             [f"edge{n}.example.com" for n in range(17)])):
    value = copy.deepcopy(cdn)
    value["cdn_entries"][0]["addresses"] = bad
    case(f"invalid-address-array-{index}", value, False)
for index, bad in enumerate(("", " ", "edge.example.com ", " edge.example.com",
                             "edge.example.com\n", "edge.example.com\t",
                             "https://edge.example.com", "edge.example.com:443",
                             "edge.example.com/path", "edge_example.com", "-edge.example.com",
                             "edge-.example.com", "256.1.2.3", "01.2.3.4", "1.2.3.04",
                             "[2001:db8::1]", "2001:db8::1%eth0", "::ffff:192.0.2.1",
                             ":", "2001:db8:1", "1:2:3:4:5:6:7:8:9", "2001:::1",
                             "1::2::3", "1:2:3:4:5:6:7::8", "12345::1")):
    value = copy.deepcopy(cdn)
    value["cdn_entries"][0]["addresses"] = [bad]
    case(f"invalid-address-{index}", value, False)
for index, bad in enumerate(("", "entry-missing", "entry-reality")):
    value = copy.deepcopy(cdn)
    value["cdn_entries"][0]["listener_id"] = bad
    case(f"invalid-target-{index}", value, False, bad != "")
value = copy.deepcopy(cdn)
value["cdn_entries"].append({"listener_id": "entry-21", "addresses": ["other.example.com"]})
case("duplicate-listener", value, False, True)
for version in (1, 2):
    value = copy.deepcopy(cdn)
    value["schema_version"] = version
    case(f"invalid-version-{version}", value, False)
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json" >"${LOG}" 2>&1 || actual=$?
    if [[ "${valid}" == 1 ]]; then
        [[ "${actual}" == 0 ]] || fail "生产校验拒绝正例: ${name}"
    else
        [[ "${actual}" != 0 ]] || fail "生产校验接受负例: ${name}"
    fi
done <"${TEST_ROOT}/cases.tsv"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/cdn.json" || fail '当前包拒绝 CDN 规格'
jq 'del(."x-padm-cdn-entry-addresses")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/cdn.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" || fail '旧包拒绝无 CDN 规格'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"
jq 'del(."x-padm-cdn-grpc-tls")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/cdn.json"
for protocol in 24 25; do
    jq --arg listener "entry-${protocol}" '.cdn_entries |= map(select(.listener_id==$listener))' \
        "${TEST_ROOT}/cdn.json" >"${TEST_ROOT}/grpc-cdn-${protocol}.json"
    reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/grpc-cdn-${protocol}.json"
done
jq '.cdn_entries |= map(select(.listener_id!="entry-24" and .listener_id!="entry-25"))' \
    "${TEST_ROOT}/cdn.json" >"${TEST_ROOT}/legacy-cdn.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/legacy-cdn.json" ||
    fail '缺少 gRPC CDN 能力的旧包拒绝 WS/HTTPUpgrade 覆写'
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" ||
    fail '缺少 gRPC CDN 能力的旧包拒绝未覆写 gRPC 入口'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"

# 解码后与无覆盖基线比较，只允许连接地址与多地址名称变化，其余字段必须完全保留。
cat >"${TEST_ROOT}/assert-links.py" <<'PY'
import base64
import copy
import json
import sys
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

spec_path, actual_path, baseline_path = map(Path, sys.argv[1:])
spec = json.loads(spec_path.read_text())

def decode(path):
    result = []
    for line in path.read_text().splitlines():
        if line.startswith("vmess://"):
            result.append(json.loads(base64.b64decode(line[8:])))
        else:
            uri = urlsplit(line)
            assert uri.scheme in ("vless", "trojan") and uri.password is None, line
            result.append(dict(scheme=uri.scheme, uuid=unquote(uri.username), add=uri.hostname,
                               port=str(uri.port), query=parse_qs(uri.query),
                               ps=unquote(uri.fragment)))
    return result

expected = []
baseline = iter(decode(baseline_path))
overrides = {item["listener_id"]: item["addresses"] for item in spec.get("cdn_entries", [])}
for entry in spec["core"]["protocols"]:
    accounts = [a for a in spec.get("accounts", [])
                if a["enabled"] and entry["listener_id"] in a["listeners"]]
    identities = ([(entry["name"], entry["uuid"])]
                  if spec["subscription"].get("include_base", True) else [])
    identities += [(entry["name"] + "-" + a["name"],
                    a["password"] if entry["id"] == 25 else a["uuid"]) for a in accounts]
    for name, credential in identities:
        original = next(baseline)
        assert original["ps"] == name
        assert original["id" if entry["id"] in (22, 23) else "uuid"] == credential
        if entry["id"] in (24, 25):
            assert original["scheme"] == ("vless" if entry["id"] == 24 else "trojan")
            assert original["query"]["sni"] == [entry["grpc_tls"]["domain"]]
            assert original["query"]["alpn"] == ["h2"]
            assert original["query"]["serviceName"] == [entry["grpc_tls"]["service_name"]]
            alias = next(a for a in spec["port_aliases"]
                         if a["listener_id"] == entry["listener_id"] and a["share_default"])
            assert original["port"] == str(alias["public_port"])
        addresses = overrides.get(entry["listener_id"], [entry["server"]])
        for index, address in enumerate(addresses, 1):
            value = copy.deepcopy(original)
            value["add"] = address
            value["ps"] = name + (f"-{index}" if len(addresses) > 1 else "")
            expected.append(value)
assert next(baseline, None) is None
actual = decode(actual_path)
assert actual == expected, (actual_path, actual, expected)
PY
assertShare() {
    local spec=$1 output=$2
    jq 'del(.cdn_entries)' "${spec}" >"${TEST_ROOT}/without-cdn.json"
    dockerGenerateSubscription "${TEST_ROOT}/without-cdn.json" "${TEST_ROOT}/without-cdn.links"
    python3 "${TEST_ROOT}/assert-links.py" "${spec}" "${output}" "${TEST_ROOT}/without-cdn.links"
}
for fixture in base cdn sixteen-addresses; do
    dockerGenerateSubscription "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/${fixture}.links"
    assertShare "${TEST_ROOT}/${fixture}.json" "${TEST_ROOT}/${fixture}.links"
done
group='{"id":"share-cccccccccccccccc","name":"CDN-Team","enabled":true,
  "token":"cdn-transaction-token","account_ids":["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"],
  "listener_ids":["entry-21","entry-22","entry-24","entry-25"]}'
dockerSubscriptionRender "${TEST_ROOT}/cdn.json" "${group}" "${TEST_ROOT}/group.links"
jq --argjson group "${group}" '.subscription.include_base=false |
  .core.protocols |= map(select(.listener_id as $id | ($group.listener_ids|index($id)) != null)) |
  .accounts |= map(select(.id as $id | ($group.account_ids|index($id)) != null))
' "${TEST_ROOT}/cdn.json" >"${TEST_ROOT}/group.json"
assertShare "${TEST_ROOT}/group.json" "${TEST_ROOT}/group.links"
[[ "$(stat -c %a "${TEST_ROOT}/group.links")" == 640 ]] || fail '分享组文件权限错误'

# 旧正文由严格输出精确删除三处新增校验得到，不能由待测 legacy 模式自证。
makeLegacyNginx() {
    python3 - "$@" <<'PY'
import json
import sys
from pathlib import Path

spec_path, strict_path, output_path = map(Path, sys.argv[1:4])
mode = sys.argv[4] if len(sys.argv) == 5 else "full"
assert mode in ("full", "partial")
spec = json.loads(spec_path.read_text())
entries = [entry for entry in spec["core"]["protocols"] if entry["id"] in (21, 22, 23)]
assert sorted(entry["id"] for entry in entries) == [21, 22, 23]
parts = strict_path.read_text().split("\nserver {\n")
gate = f'\n    if ($host != {spec["tls"]["domain"].lower()}) {{ return 404; }}\n'
for entry in entries:
    transport = entry.get("websocket", entry.get("httpupgrade"))
    port = transport["tls_port"]
    matches = [index for index, part in enumerate(parts)
               if part.startswith(f"    listen {port} ssl;\n    listen [::]:{port} ssl;\n")]
    assert len(matches) == 1, (entry["listener_id"], matches)
    index = matches[0]
    assert parts[index].count(gate) == 1, entry["listener_id"]
    if mode == "full" or entry["id"] == 21:
        parts[index] = parts[index].replace(gate, "", 1)
output_path.write_text("\nserver {\n".join(parts))
PY
}
assertNginxDirectory() {
    local expectedStatus=$1 spec=$2 actual=$3 expected status=0
    # 比较器会改写私有旧版草稿，每次重新生成严格目录，不能复用上次结果。
    expected=$(mktemp -d "${TEST_ROOT}/nginx-expected.XXXXXX")
    dockerGenerateNginxConfig "${spec}" "${expected}/default.conf"
    dockerGenerateRealityStreamConfig "${spec}" "${expected}/stream/reality.conf"
    dockerGenerateRealityStreamMain "${spec}" "${expected}/stream/host-main"
    dockerNginxDirectoryMatches "${spec}" "${expected}" "${actual}" >"${LOG}" 2>&1 || status=$?
    [[ "${status}" == "${expectedStatus}" ]] || fail "Nginx 目录校验预期 ${expectedStatus}，实际 ${status}"
}
nginxActual="${TEST_ROOT}/nginx-actual"
mkdir -p "${nginxActual}"
dockerGenerateNginxConfig "${TEST_ROOT}/base.json" "${TEST_ROOT}/nginx-strict.conf"
makeLegacyNginx "${TEST_ROOT}/base.json" "${TEST_ROOT}/nginx-strict.conf" "${TEST_ROOT}/nginx-legacy.conf"
makeLegacyNginx "${TEST_ROOT}/base.json" "${TEST_ROOT}/nginx-strict.conf" "${TEST_ROOT}/nginx-partial.conf" partial
sed 's|proxy_pass http://xray:40021;|proxy_pass http://xray:49999;|' \
    "${TEST_ROOT}/nginx-legacy.conf" >"${TEST_ROOT}/nginx-proxy-drift.conf"
grep -qF 'proxy_pass http://xray:49999;' "${TEST_ROOT}/nginx-proxy-drift.conf"
for variant in strict legacy partial proxy-drift; do
    cp -- "${TEST_ROOT}/nginx-${variant}.conf" "${nginxActual}/default.conf"
    if [[ "${variant}" == strict || "${variant}" == legacy ]]; then
        dockerNginxConfigMatches "${TEST_ROOT}/base.json" "${nginxActual}/default.conf" ||
            fail "拒绝完整 Nginx ${variant} 正文"
        assertNginxDirectory 0 "${TEST_ROOT}/base.json" "${nginxActual}"
    else
        reject dockerNginxConfigMatches "${TEST_ROOT}/base.json" "${nginxActual}/default.conf"
        assertNginxDirectory 1 "${TEST_ROOT}/base.json" "${nginxActual}"
    fi
done
cp -- "${TEST_ROOT}/nginx-legacy.conf" "${nginxActual}/default.conf"
printf 'server { listen 49998; }\n' >"${nginxActual}/unmanaged.conf"
assertNginxDirectory 1 "${TEST_ROOT}/base.json" "${nginxActual}"
rm -- "${nginxActual}/unmanaged.conf"
reject dockerNginxConfigMatches "${TEST_ROOT}/cdn.json" "${nginxActual}/default.conf"
assertNginxDirectory 1 "${TEST_ROOT}/cdn.json" "${nginxActual}"

# 旧模式只缺本次 TLS 校验，既有 HTTP-01 校验和 stream 正文仍须完整一致。
jq '.tls.http01=true' "${TEST_ROOT}/base.json" >"${TEST_ROOT}/nginx-http01.json"
dockerConfigureSpecValidate "${TEST_ROOT}/nginx-http01.json"
dockerGenerateNginxConfig "${TEST_ROOT}/nginx-http01.json" "${TEST_ROOT}/nginx-http01-strict.conf"
makeLegacyNginx "${TEST_ROOT}/nginx-http01.json" "${TEST_ROOT}/nginx-http01-strict.conf" \
    "${nginxActual}/default.conf"
[[ "$(grep -cF 'if ($host != tls.example.com) { return 404; }' "${nginxActual}/default.conf")" == 1 ]]
dockerNginxConfigMatches "${TEST_ROOT}/nginx-http01.json" "${nginxActual}/default.conf"
assertNginxDirectory 0 "${TEST_ROOT}/nginx-http01.json" "${nginxActual}"
sed '/^    if (\$host != tls\.example\.com) { return 404; }$/d' "${nginxActual}/default.conf" \
    >"${TEST_ROOT}/nginx-http01-drift.conf"
cp -- "${TEST_ROOT}/nginx-http01-drift.conf" "${nginxActual}/default.conf"
reject dockerNginxConfigMatches "${TEST_ROOT}/nginx-http01.json" "${nginxActual}/default.conf"
assertNginxDirectory 1 "${TEST_ROOT}/nginx-http01.json" "${nginxActual}"
jq 'del(.port_aliases) |
  .reality_stream={listener_id:"entry-reality",website_listener_id:"entry-21"}' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/nginx-stream.json"
dockerConfigureSpecValidate "${TEST_ROOT}/nginx-stream.json"
dockerGenerateNginxConfig "${TEST_ROOT}/nginx-stream.json" "${TEST_ROOT}/nginx-stream-strict.conf"
makeLegacyNginx "${TEST_ROOT}/nginx-stream.json" "${TEST_ROOT}/nginx-stream-strict.conf" \
    "${nginxActual}/default.conf"
dockerGenerateRealityStreamConfig "${TEST_ROOT}/nginx-stream.json" "${nginxActual}/stream/reality.conf"
dockerNginxConfigMatches "${TEST_ROOT}/nginx-stream.json" "${nginxActual}/default.conf"
assertNginxDirectory 0 "${TEST_ROOT}/nginx-stream.json" "${nginxActual}"
sed 's|server 127.0.0.1:41021;|server 127.0.0.1:49999;|' "${nginxActual}/stream/reality.conf" \
    >"${TEST_ROOT}/nginx-stream-drift.conf"
grep -qF 'server 127.0.0.1:49999;' "${TEST_ROOT}/nginx-stream-drift.conf"
cp -- "${TEST_ROOT}/nginx-stream-drift.conf" "${nginxActual}/stream/reality.conf"
assertNginxDirectory 1 "${TEST_ROOT}/nginx-stream.json" "${nginxActual}"

snapshot() (
    cd "${root}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' -o -name '.subscription.*' \) -print -quit)" ]] ||
        fail '事务遗留候选或订阅临时文件'
}
cdnProtectedSnapshot() (
    cd "${root}"
    jq -S 'del(.cdn_entries)' config/spec.json
    sha256sum compose.json images.env config/xray/config.json config/xray/users.base \
        config/nginx/default.conf config/share-groups.json data/traffic/state.json secrets/tls/*
)
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
}
assertInstalledShare() {
    assertShare "${root}/config/spec.json" "${root}/data/subscription/0123456789abcdef"
    jq --argjson group "${group}" '.subscription.include_base=false |
      .core.protocols |= map(select(.listener_id as $id | ($group.listener_ids|index($id)) != null)) |
      .accounts |= map(select(.id as $id | ($group.account_ids|index($id)) != null))
    ' "${root}/config/spec.json" >"${TEST_ROOT}/installed.group.json"
    assertShare "${TEST_ROOT}/installed.group.json" "${root}/data/subscription/cdn-transaction-token"
    [[ "$(stat -c %a "${root}/config/spec.json")" == 600 ]] || fail '规格权限错误'
    [[ "$(stat -c %a "${root}/data/subscription/0123456789abcdef")" == 640 ]] || fail '主订阅权限错误'
}
mkdir -p "${root}/secrets/tls"
printf '%s\n' fixture-certificate >"${root}/secrets/tls/tls.example.com.crt"
printf '%s\n' fixture-private-key >"${root}/secrets/tls/tls.example.com.key"
chmod 0640 "${root}/secrets/tls/"*
dockerSubscriptionStateWrite "${root}/config/share-groups.json" \
    "$(jq -cn --argjson group "${group}" '{schema_version:1,groups:[$group]}')"
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 CDN 夹具失败'
assertClean
assertInstalledShare
# 模拟旧 bundle 更新后的在线正文，首次 CDN 提交必须一次补齐所有入口校验。
cp -- "${root}/config/nginx/default.conf" "${TEST_ROOT}/nginx-installed-strict.conf"
makeLegacyNginx "${root}/config/spec.json" "${TEST_ROOT}/nginx-installed-strict.conf" \
    "${root}/config/nginx/default.conf"
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"business",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
(dockerMain subscription links share-cccccccccccccccc) >"${TEST_ROOT}/url.before"
grep -qx 'https://tls.example.com/subscriptions/cdn-transaction-token' "${TEST_ROOT}/url.before" ||
    fail '初始分享 URL 不正确'
legacyBefore=$(snapshot)
(dockerMain protocol list) >"${LOG}" 2>&1 || fail '旧 Nginx 不能读取入口列表'
for listener in entry-reality entry-21 entry-22 entry-23 entry-24 entry-25; do
    grep -q "^${listener}  " "${LOG}" || fail "旧 Nginx 入口列表遗漏 ${listener}"
done
(dockerMain protocol links) >"${TEST_ROOT}/legacy.links" || fail '旧 Nginx 不能读取分享链接'
assertShare "${root}/config/spec.json" "${TEST_ROOT}/legacy.links"
(dockerMain protocol cdn-status) >"${LOG}"
jq -e '.enabled==false and (.entries|length)==5 and
  all(.entries[]; .overridden==false and .addresses==["origin.example.com"])' "${LOG}" >/dev/null
assertClean
[[ "$(snapshot)" == "${legacyBefore}" ]] || fail '旧 Nginx 只读菜单修改在线部署'
before=$(snapshot)
runEdit 0 --cdn-entry entry-21 'edge.example.com,2001:db8::21' --preview
grep -Fq 'edge.example.com' "${LOG}" || fail 'CDN 预览未显示有效覆盖地址'
! grep -Fq "${UUID}" "${LOG}" || fail 'CDN 预览泄露 UUID'
runEdit 2 --cdn-entry entry-21
runEdit 2 --cdn-entry-clear
runEdit 2 --cdn-entry entry-21 edge.example.com --cdn-entry-clear entry-21 --preview
runEdit 2 --cdn-entry entry-21 edge.example.com --port-alias-default entry-21 base --preview
runEdit 2 --cdn-entry entry-21 edge.example.com --block-bt --preview
runEdit 2 --cdn-entry entry-21 edge.example.com --spec "${TEST_ROOT}/base.json" --preview
for addresses in 'edge.example.com,' ',edge.example.com' 'edge.example.com,edge.example.com' \
    'edge.example.com, edge2.example.com' ':::' '01.2.3.4' 'https://edge.example.com'; do
    runEdit 15 --cdn-entry entry-21 "${addresses}" --preview
done
runEdit 15 --cdn-entry entry-missing edge.example.com --preview
runEdit 15 --cdn-entry entry-reality edge.example.com --preview
runEdit 15 --cdn-entry-clear entry-reality --preview
runEdit 15 --spec "${TEST_ROOT}/cdn.json" --confirm PADM-DOCKER-EDIT
reject dockerMain protocol cdn-status entry-missing
reject dockerMain protocol cdn-status entry-reality
reject dockerMain protocol cdn-status entry-21 extra
[[ "$(snapshot)" == "${before}" ]] || fail '预览或非法输入改变在线部署'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/cdn.json" '' '' interactive <<<n
) >"${LOG}" 2>&1 || fail 'CDN 候选取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'CDN 确认取消改变在线部署'
runEdit 0 --cdn-entry entry-21 'edge.example.com,2001:db8::21' --confirm PADM-DOCKER-EDIT
cmp -- "${TEST_ROOT}/nginx-installed-strict.conf" "${root}/config/nginx/default.conf" ||
    fail '首次 CDN 提交未完整升级三个入口的 Host 校验'
runEdit 0 --cdn-entry entry-22 '192.0.2.22,2001:db8:0:0:0:0:0:22' --confirm PADM-DOCKER-EDIT
runEdit 0 --cdn-entry entry-23 edge23.example.com --confirm PADM-DOCKER-EDIT
for protocol in 24 25; do
    listener="entry-${protocol}"
    protectedBefore=$(cdnProtectedSnapshot)
    before=$(snapshot)
    runEdit 0 --cdn-entry "${listener}" "edge${protocol}.example.com,2001:db8::${protocol}" --preview
    grep -Fq "edge${protocol}.example.com" "${LOG}" || fail 'gRPC CDN 预览遗漏覆盖地址'
    ! grep -Fq "${UUID}" "${LOG}" || fail 'gRPC CDN 预览泄露认证'
    [[ "$(snapshot)" == "${before}" ]] || fail 'gRPC CDN 预览改变在线部署'
    runEdit 0 --cdn-entry "${listener}" "edge${protocol}.example.com,2001:db8::${protocol}" \
        --confirm PADM-DOCKER-EDIT
    [[ "$(cdnProtectedSnapshot)" == "${protectedBefore}" ]] || fail 'gRPC CDN 设置改变其它配置或业务状态'
    (dockerMain protocol cdn-status "${listener}") >"${LOG}"
    jq -e --arg listener "${listener}" --argjson protocol "${protocol}" '
      .=={enabled:true,entries:[{listener_id:$listener,protocol:$protocol,server:"origin.example.com",
        overridden:true,addresses:[("edge"+($protocol|tostring)+".example.com"),("2001:db8::"+($protocol|tostring))]}]}
    ' "${LOG}" >/dev/null
    (dockerMain protocol links "${listener}") >"${TEST_ROOT}/grpc-selected.links"
    jq --arg listener "${listener}" '.core.protocols |= map(select(.listener_id==$listener))' \
        "${root}/config/spec.json" >"${TEST_ROOT}/grpc-selected.json"
    assertShare "${TEST_ROOT}/grpc-selected.json" "${TEST_ROOT}/grpc-selected.links"
done
assertInstalledShare
(dockerMain protocol cdn-status entry-21) >"${LOG}"
jq -e '.=={enabled:true,entries:[{listener_id:"entry-21",protocol:21,server:"origin.example.com",
  overridden:true,addresses:["edge.example.com","2001:db8::21"]}]}' "${LOG}" >/dev/null
(dockerMain protocol links) >"${TEST_ROOT}/local.links"
assertShare "${root}/config/spec.json" "${TEST_ROOT}/local.links"
(dockerMain protocol links entry-21) >"${TEST_ROOT}/local-selected.links"
jq '.core.protocols |= map(select(.listener_id=="entry-21"))' \
    "${root}/config/spec.json" >"${TEST_ROOT}/local-selected.json"
assertShare "${TEST_ROOT}/local-selected.json" "${TEST_ROOT}/local-selected.links"
(dockerMain subscription links share-cccccccccccccccc) >"${TEST_ROOT}/url.after"
cmp "${TEST_ROOT}/url.before" "${TEST_ROOT}/url.after" || fail 'CDN 覆盖改动订阅 URL 或 token'

# 普通规格导入不能绕过覆盖冻结；失败必须恢复主订阅、组订阅与已有业务状态。
before=$(snapshot)
jq '.cdn_entries[0].addresses=["tampered.example.com"]' "${root}/config/spec.json" >"${TEST_ROOT}/frozen.json"
runEdit 15 --spec "${TEST_ROOT}/frozen.json" --confirm PADM-DOCKER-EDIT
runEdit 0 --cdn-entry-clear entry-21 --preview
[[ "$(snapshot)" == "${before}" ]] || fail '冻结拒绝或清空预览改变在线部署'
MODE=health-fail
runEdit 14 --cdn-entry-clear entry-21 --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'CDN 清空失败未完整恢复部署'
MODE=ok
runEdit 0 --cdn-entry-clear entry-21 --confirm PADM-DOCKER-EDIT
assertInstalledShare
(dockerMain protocol cdn-status entry-21) >"${LOG}"
jq -e '.entries[0].overridden==false and .entries[0].addresses==["origin.example.com"]' "${LOG}" >/dev/null
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
before=$(snapshot)
runEdit 14 --cdn-entry entry-21 new.example.com --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'CDN 设置失败未完整恢复部署'
MODE=ok
runEdit 0 --cdn-entry entry-21 new.example.com --confirm PADM-DOCKER-EDIT
jq '.core.protocols += [(.core.protocols[] | select(.listener_id=="entry-21") |
  .listener_id="entry-copy" | .public_port=35026 | .name="Copy" |
  .websocket.backend_port=42024 | .websocket.tls_port=43024)]' \
    "${root}/config/spec.json" >"${TEST_ROOT}/copy.json"
runEdit 0 --spec "${TEST_ROOT}/copy.json" --confirm PADM-DOCKER-EDIT
jq -e 'all(.cdn_entries[]; .listener_id!="entry-copy")' "${root}/config/spec.json" >/dev/null
assertInstalledShare
# 删除入口时同时清理该入口的映射和别名，不允许影响剩余入口。
jq '.core.protocols |= map(select(.listener_id!="entry-23")) |
  .port_aliases |= map(select(.listener_id!="entry-23")) |
    .cdn_entries |= map(select(.listener_id!="entry-23")) |
    .accounts |= map(.listeners |= map(select(. != "entry-23")))
' "${root}/config/spec.json" >"${TEST_ROOT}/delete.json"
jq '.accounts[0].name="tampered"' "${TEST_ROOT}/delete.json" >"${TEST_ROOT}/delete-tampered.json"
runEdit 15 --spec "${TEST_ROOT}/delete-tampered.json" --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/menu-delete.json"
printf '10\nentry-23\n8\n' | dockerEditFields "${TEST_ROOT}/menu-delete.json" >"${LOG}" ||
    fail '菜单删除未同步账号关联'
jq -en --slurpfile cli "${TEST_ROOT}/delete.json" --slurpfile menu "${TEST_ROOT}/menu-delete.json" \
    '$cli == $menu' >/dev/null || fail '菜单与规格删除结果不一致'
jq '.accounts[0].listeners=["entry-23"]' "${root}/config/spec.json" >"${TEST_ROOT}/last-listener.json"
cp -- "${TEST_ROOT}/last-listener.json" "${TEST_ROOT}/last-listener.before.json"
if printf '10\nentry-23\n8\n' | dockerEditFields "${TEST_ROOT}/last-listener.json" >"${LOG}" 2>&1; then
    fail '菜单允许删除账号最后一个关联入口'
fi
cmp "${TEST_ROOT}/last-listener.before.json" "${TEST_ROOT}/last-listener.json" ||
    fail '最后关联拒绝后仍修改草稿'
runEdit 0 --spec "${TEST_ROOT}/delete.json" --confirm PADM-DOCKER-EDIT
jq -e 'all(.cdn_entries[]; .listener_id!="entry-23") and
  any(.cdn_entries[]; .listener_id=="entry-21" and .addresses==["new.example.com"])' \
    "${root}/config/spec.json" >/dev/null
assertInstalledShare
runEdit 0 --cdn-entry-clear entry-21 --confirm PADM-DOCKER-EDIT
runEdit 0 --cdn-entry-clear entry-22 --confirm PADM-DOCKER-EDIT
for protocol in 24 25; do
    listener="entry-${protocol}"
    protectedBefore=$(cdnProtectedSnapshot)
    before=$(snapshot)
    runEdit 0 --cdn-entry-clear "${listener}" --preview
    [[ "$(snapshot)" == "${before}" ]] || fail 'gRPC CDN 清空预览改变在线部署'
    runEdit 0 --cdn-entry-clear "${listener}" --confirm PADM-DOCKER-EDIT
    [[ "$(cdnProtectedSnapshot)" == "${protectedBefore}" ]] || fail 'gRPC CDN 清空改变其它配置或业务状态'
    (dockerMain protocol cdn-status "${listener}") >"${LOG}"
    jq -e '.entries[0].overridden==false and .entries[0].addresses==["origin.example.com"]' "${LOG}" >/dev/null
    assertInstalledShare
done
jq -e 'has("cdn_entries")|not' "${root}/config/spec.json" >/dev/null ||
    fail '清空最后一个 CDN 条目后遗留空数组'
assertInstalledShare
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload==17 and .accounts[$uuid].download==19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'CDN 事务清空业务流量'

# 菜单直接驱动真实读取流程，只记录 CLI 派发，取消和 EOF 不能触发编辑。
(
    dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/menu.commands"; }
    printf '9\n1\n2\n0\n2\nentry-21\n0\n3\n0\n0\n0\n' |
        dockerMenuProtocols >"${LOG}"
    ! grep -q '^edit ' "${TEST_ROOT}/menu.commands" || fail 'CDN 菜单取消仍派发编辑'
    grep -qx 'protocol cdn-status' "${TEST_ROOT}/menu.commands" || fail 'CDN 状态菜单未派发'
    : >"${TEST_ROOT}/menu.commands"
    printf '2\nentry-24\nedge.example.com,2001:db8::24\n3\nentry-25\n0\n' |
        dockerMenuCdnEntries >"${LOG}"
    grep -qx 'edit --cdn-entry entry-24 edge.example.com,2001:db8::24' "${TEST_ROOT}/menu.commands" ||
        fail 'CDN 设置菜单参数错误'
    grep -qx 'edit --cdn-entry-clear entry-25' "${TEST_ROOT}/menu.commands" || fail 'CDN 清空菜单参数错误'
    : >"${TEST_ROOT}/menu.commands"
    printf '2\nentry-21\n' | dockerMenuCdnEntries >"${LOG}"
    ! grep -q '^edit ' "${TEST_ROOT}/menu.commands" || fail 'CDN 菜单 EOF 仍派发编辑'
)
assertClean
bash -n "${PROJECT_ROOT}/docker/tests/cdn-entries.sh"
shellcheck --severity=warning "${PROJECT_ROOT}/docker/tests/cdn-entries.sh"
for file in bundle lifecycle menu services setup; do
    bash -n "${PROJECT_ROOT}/docker/lib/${file}.sh"
done
shellcheck --severity=error "${PROJECT_ROOT}/docker/lib/"{bundle,lifecycle,menu,services,setup}.sh
printf 'docker-cdn-entries-regression-ok\n'
