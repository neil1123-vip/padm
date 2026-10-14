#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-sites.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-sites-regression-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-sites-regression-fail: Linux root is required\n' >&2
    exit 1
}
for tool in jq python3 nginx openssl curl stat chmod chown readlink find sort sha256sum mkfifo timeout; do
    command -v "${tool}" >/dev/null || exit 1
done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
DOMAIN=ws.example.com
TOKEN=0123456789abcdef0123456789abcdef
UUID=11111111-1111-4111-8111-111111111111
MODE=ok
LOG=${TEST_ROOT}/command.log
COMPOSE_LOG=${TEST_ROOT}/compose.log

fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-sites-regression-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }

# 核心、宿主和发布只使用桩；生成、权限、锁与恢复走生产代码。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
docker() {
    if [[ "${1:-}" == run ]]; then
        local expectedArg
        local -a expected=(run --rm -i --read-only --network none --cap-drop ALL
            --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m
            --label io.padm.mode=docker --label "io.padm.project=${PADM_DOCKER_PROJECT}"
            --entrypoint python3 "$(dockerManifestImageReference ops)" -c)
        [[ "$#" -eq "$((${#expected[@]} + 1))" ]] || fail 'Reality 公钥派生参数数量不符'
        for expectedArg in "${expected[@]}"; do
            [[ "$1" == "${expectedArg}" ]] || fail 'Reality 公钥派生参数不符'
            shift
        done
        [[ "$1" == *'private_key = base64.b64decode'* ]] || fail '非预期 Python 派生脚本'
        # 在测试容器执行生产派生脚本，真实公私钥仍须通过原校验。
        python3 -c "$1"
        return
    fi
    [[ "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban-control --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban-ssh --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False' ]] ||
        fail "非预期 Docker 操作: $*"
}
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundle"; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerTlsValidateCandidate() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"
}
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
mkdir -p "${TEST_ROOT}/bundle/docker/contracts" "${TEST_ROOT}/bundle/shell/core" "${TEST_ROOT}/bundle/assets"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
cp -- "${PROJECT_ROOT}/shell/core/static_site_renderer.sh" "${TEST_ROOT}/bundle/shell/core/"
cp -a -- "${PROJECT_ROOT}/assets/static-sites" "${TEST_ROOT}/bundle/assets/"
dockerCandidateCompose() {
    local candidate=$1
    shift
    [[ -d "${candidate}" && -e "${root}/locks/deployment.lock" ]] ||
        fail '候选校验没有持有部署锁'
    printf 'candidate:%s\n' "$*" >>"${COMPOSE_LOG}"
}
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '部署未持有部署锁'
    printf 'live:%s\n' "$*" >>"${COMPOSE_LOG}"
    if [[ "${1:-}" == up && "${MODE}" != ok && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        case "${MODE}" in
        health-fail) return 1 ;;
        int) kill -INT "${BASHPID}" ;;
        term) kill -TERM "${BASHPID}" ;;
        esac
    fi
}
dockerComposeExecute() {
    [[ "$*" == down ]] || fail "意外恢复启停参数: $*"
    dockerComposeRun "$@"
}
dockerInitializeStateRoot
mkdir -p "${root}/secrets/tls"
printf 'fixture-cert\n' >"${root}/secrets/tls/${DOMAIN}.crt"
printf 'fixture-key\n' >"${root}/secrets/tls/${DOMAIN}.key"
dockerTlsRuntimePermissions "${root}/secrets/tls"
jq -n --arg domain "${DOMAIN}" --arg token "${TOKEN}" --arg uuid "${UUID}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[{
     id:21,core:"xray",listener_id:"entry-site",server:"proxy.example.com",public_port:24443,
     address_families:["ipv4","ipv6"],name:"site",uuid:$uuid,
     websocket:{domain:$domain,path:"abcdefgh",backend_port:31297,tls_port:8443}}]},
   tls:{domain:$domain},subscription:{enabled:true,token:$token},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${TEST_ROOT}/base.json"

# 同一批输入交给 JSON Schema 和生产校验，防止两份合同出现相反判断。
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

def case(name, value, valid):
    assert validator.is_valid(value) == valid, name
    (root / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")
    cases.append((name, int(valid)))

case("legacy", base, True)
for protocol in (21, 22, 23, 24, 25, 27, 29):
    spec = copy.deepcopy(base)
    entry = spec["core"]["protocols"][0]
    transport = entry.pop("websocket")
    entry["id"] = protocol
    spec["subscription"]["enabled"] = protocol == 21
    if protocol in (21, 22):
        entry["websocket"] = transport
    elif protocol == 23:
        entry["httpupgrade"] = transport
    elif protocol in (24, 25):
        entry["grpc_tls"] = dict(domain=transport["domain"], service_name="padm_grpc",
                                 backend_port=31297, tls_port=8443)
    else:
        entry["fallback_tls"] = dict(domain=transport["domain"], http_port=31300, http2_port=31302)
        spec["subscription"]["enabled"] = False
    for mode in ("default", "static", "redirect"):
        spec["site"] = dict(mode=mode)
        if mode == "redirect":
            spec["site"]["url"] = "https://example.com/path?a=1&b=2#part"
        case(f"valid-{protocol}-{mode}", spec, True)
        value = copy.deepcopy(spec)
        value["tls"]["http01"] = True
        case(f"valid-http01-{protocol}-{mode}", value, True)
    if protocol in (27, 29):
        for index, alpn in enumerate((["h2", "http/1.1"], ["http/1.1", "h2"], ["http/1.1"])):
            value = copy.deepcopy(spec)
            value["site"] = dict(mode="static")
            value["core"]["protocols"][0]["fallback_tls"]["alpn"] = alpn
            case(f"valid-alpn-{protocol}-{index}", value, True)
        for index, alpn in enumerate((None, [], {}, "h2,http/1.1", ["h2"], ["h3"],
                                     ["h2", "h2"], ["http/1.1", "http/1.1"],
                                     ["h2", "http/1.1", "h3"], ["http/1.1", 1],
                                     ["H2", "http/1.1"], ["http/1.1\n"])):
            value = copy.deepcopy(spec)
            value["core"]["protocols"][0]["fallback_tls"]["alpn"] = alpn
            case(f"invalid-alpn-{protocol}-{index}", value, False)

for index, site in enumerate((None, {}, [], {"mode": "unknown"}, {"mode": "default", "url": "https://example.com"},
                              {"mode": "static", "source": "/root/site"}, {"mode": "redirect"},
                              {"mode": "redirect", "url": 1},
                              {"mode": "redirect", "url": "https://example.com", "extra": True})):
    spec = copy.deepcopy(base)
    spec["site"] = site
    case(f"invalid-shape-{index}", spec, False)
for index, url in enumerate(("", "//example.com", "ftp://example.com", "javascript:alert(1)",
                            "https://", "https://example.com/\n", "https://example.com/a b",
                            'https://example.com/";return 200;', "https://example.com/$request_uri",
                            "https://example.com/\\path", "https://example.com/{bad}",
                            "https://example.com/\x7f", "https://example.com/" + "a" * 2048)):
    spec = copy.deepcopy(base)
    spec["site"] = dict(mode="redirect", url=url)
    case(f"invalid-url-{index}", spec, False)
direct = copy.deepcopy(base)
direct["subscription"]["enabled"] = False
entry = direct["core"]["protocols"][0]
entry.pop("websocket")
entry.update(id=28, trojan=dict(domain="ws.example.com"))
case("valid-direct", direct, True)
sing_upgrade = json.loads((root / "valid-23-default.json").read_text())
del sing_upgrade["site"]
sing_upgrade["core"]["type"] = "sing-box"
sing_upgrade["core"]["protocols"][0]["core"] = "sing-box"
case("valid-sing-upgrade", sing_upgrade, True)
hy2 = copy.deepcopy(sing_upgrade)
entry = hy2["core"]["protocols"][0]
del entry["httpupgrade"]
entry.update(id=3, hy2=dict(domain=base["tls"]["domain"], bandwidth_mode="bbr",
                          up_mbps=100, down_mbps=100, obfs=None, masquerade=""))
case("valid-hy2", hy2, True)
hy2_static = copy.deepcopy(hy2)
hy2_static["site"] = dict(mode="static")
case("valid-hy2-static", hy2_static, True)
hy2_local = copy.deepcopy(hy2_static)
hy2_local["core"]["protocols"][0]["hy2"]["masquerade"] = "local"
case("valid-hy2-local", hy2_local, True)
for mode in ("absent", "default", "redirect"):
    value = copy.deepcopy(hy2_local)
    if mode == "absent":
        del value["site"]
    else:
        value["site"] = dict(mode=mode)
        if mode == "redirect":
            value["site"]["url"] = "https://example.com"
    case(f"invalid-hy2-local-{mode}", value, False)
value = copy.deepcopy(hy2_local)
value["core"]["protocols"][0]["hy2"]["obfs"] = dict(type="salamander", password="0123456789abcdef")
case("invalid-hy2-local-obfs", value, False)
for index, masquerade in enumerate(("LOCAL", "local/", "file:///srv/padm/")):
    value = copy.deepcopy(hy2_local)
    value["core"]["protocols"][0]["hy2"]["masquerade"] = masquerade
    case(f"invalid-hy2-local-value-{index}", value, False)
mixed_reality = copy.deepcopy(base)
reality = copy.deepcopy(base["core"]["protocols"][0])
del reality["websocket"]
reality.update(id=1, listener_id="entry-reality", public_port=25444,
               reality=dict(server_name="reality.example.com", target_host="reality.example.com",
                            target_port=443,
                            private_key="dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
                            public_key="hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
                            short_id="abcd"))
mixed_reality["core"]["protocols"].append(reality)
case("valid-site-reality", mixed_reality, True)
for name, extra in (("sing-upgrade", sing_upgrade), ("hy2", hy2)):
    mixed = copy.deepcopy(base)
    mixed["core"]["secondary_type"] = "sing-box"
    entry = copy.deepcopy(extra["core"]["protocols"][0])
    entry.update(listener_id="entry-other-site", public_port=25444)
    if "httpupgrade" in entry:
        entry["httpupgrade"].update(path="otherpath", backend_port=31301, tls_port=8444)
    mixed["core"]["protocols"].append(entry)
    case(f"valid-mixed-{name}", mixed, True)
    if name == "hy2":
        mixed["site"] = dict(mode="static")
        case("valid-mixed-hy2-static", mixed, True)
        mixed["core"]["protocols"][-1]["hy2"]["masquerade"] = "local"
        case("valid-mixed-hy2-local", mixed, True)
for index, value in enumerate((False, None, "", "true", 1, [], {})):
    spec = copy.deepcopy(base)
    spec["tls"]["http01"] = value
    case(f"invalid-http01-shape-{index}", spec, False)
spec = copy.deepcopy(direct)
spec["tls"]["http01"] = True
case("invalid-http01-direct", spec, False)
for index, (field, port) in enumerate((("public_port", 80), ("fallback_http_port", 8088))):
    spec = copy.deepcopy(base)
    spec["tls"]["http01"] = True
    if field == "public_port":
        spec["core"]["protocols"][0][field] = port
    else:
        fallback = copy.deepcopy(spec["core"]["protocols"][0])
        fallback.pop("websocket")
        fallback.update(id=27, listener_id="entry-fallback", public_port=24444,
                       fallback_tls=dict(domain=base["tls"]["domain"], http_port=port, http2_port=31302))
        spec["core"]["protocols"].append(fallback)
    case(f"invalid-http01-port-{index}", spec, False)
spec = copy.deepcopy(base)
spec["tls"]["http01"] = True
spec["core"]["protocols"][0]["websocket"]["backend_port"] = 8088
case("valid-http01-core-backend-8088", spec, True)
mixed = copy.deepcopy(base)
direct_entry = copy.deepcopy(direct["core"]["protocols"][0])
direct_entry.update(listener_id="entry-direct", public_port=25443)
mixed["core"]["protocols"].append(direct_entry)
mixed["site"] = dict(mode="static")
case("valid-mixed-static", mixed, True)
mixed_alpn = json.loads((root / "valid-27-static.json").read_text())
second_fallback = json.loads((root / "valid-29-static.json").read_text())["core"]["protocols"][0]
mixed_alpn["core"]["protocols"][0]["listener_id"] = "entry-fallback-27"
second_fallback.update(listener_id="entry-fallback-29", public_port=24444)
mixed_alpn["core"]["protocols"].append(second_fallback)
case("valid-mixed-alpn", mixed_alpn, True)
for mode in ("default", "static", "redirect"):
    spec = copy.deepcopy(direct)
    spec["site"] = dict(mode=mode)
    if mode == "redirect":
        spec["site"]["url"] = "https://example.com"
    case(f"invalid-direct-{mode}", spec, False)
for version in (1, 2):
    spec = copy.deepcopy(base)
    spec["schema_version"] = version
    del spec["core"]["secondary_type"]
    del spec["core"]["protocols"][0]["core"]
    if version == 1:
        del spec["core"]["protocols"][0]["listener_id"]
        del spec["core"]["protocols"][0]["websocket"]["backend_port"]
        del spec["core"]["protocols"][0]["websocket"]["tls_port"]
    case(f"valid-legacy-v{version}", spec, True)
    value = copy.deepcopy(spec)
    value["tls"]["http01"] = True
    case(f"invalid-http01-v{version}", value, False)
    spec["site"] = dict(mode="static")
    case(f"invalid-site-v{version}", spec, False)
(root / "cases.tsv").write_text("".join(f"{name}\t{valid}\n" for name, valid in cases))
PY
while IFS=$'\t' read -r name valid; do
    actual=0
    dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json" >"${LOG}" 2>&1 || actual=$?
    if [[ "${valid}" == 1 ]]; then
        [[ "${actual}" == 0 ]] || fail "生产校验拒绝 Schema 有效输入: ${name}"
    else
        [[ "${actual}" != 0 ]] || fail "生产校验接受 Schema 无效输入: ${name}"
    fi
done <"${TEST_ROOT}/cases.tsv"

# 固定正文使用内建输出后，条件调用也必须传播实际写入失败。
reject dockerGenerateNginxConfig "${TEST_ROOT}/base.json" /dev/full
reject dockerGenerateSiteLocations "${TEST_ROOT}/valid-21-default.json" /dev/full
(
    # 站点正文已经输出时的读取失败仍须拒绝，不能缓存部分输出。
    jq() {
        command jq "$@" || return $?
        [[ "${1:-}" != -r || "${2:-}" != '.site.mode // "legacy"' ]] || return 17
    }
    reject dockerGenerateNginxConfig "${TEST_ROOT}/valid-21-default.json" "${TEST_ROOT}/failed-site.conf"
) || fail '站点正文读取故障未传播'

# 批量读取必须传播 jq 的非零退出，不能把已打印的正常字段当作成功。
(
    jq() {
        command jq "$@" || return $?
        [[ "$*" != *'join("|")'* ]] || return 17
    }
    reject dockerGenerateNginxConfig "${TEST_ROOT}/base.json" "${TEST_ROOT}/failed-metadata.conf"
    [[ ! -e "${TEST_ROOT}/failed-metadata.conf" ]] || fail '元数据失败仍写入 Nginx 候选'
    reject dockerValidateHostIntegrations "${TEST_ROOT}/base.json" "${TEST_ROOT}/unused"
    reject dockerValidateCandidate "${TEST_ROOT}/base.json" "${TEST_ROOT}/unused"
    dockerCreateConfigurationCandidate
    trap dockerCleanupConfigurationCandidate EXIT
    reject dockerGenerateCandidate "${TEST_ROOT}/base.json" "${DOCKER_CONFIG_CANDIDATE}"
) || fail '元数据批量读取故障合同失败'
(
    dockerCreateConfigurationCandidate
    trap dockerCleanupConfigurationCandidate EXIT
    dockerGenerateCandidate "${TEST_ROOT}/base.json" "${DOCKER_CONFIG_CANDIDATE}"
    # Compose 已输出正常开关后，后段 JSON 解析或工具失败仍须拒绝候选。
    printf '{invalid\n' >"${DOCKER_CONFIG_CANDIDATE}/deployment.json"
    reject dockerValidateCandidate "${TEST_ROOT}/base.json" "${DOCKER_CONFIG_CANDIDATE}"
    grep -Fq '候选 JSON 配置无效' "${LOG}" || fail '后段候选 JSON 错误未传播'
    dockerGenerateDeployment "${TEST_ROOT}/base.json" "${DOCKER_CONFIG_CANDIDATE}/deployment.json"
    jq() {
        command jq "$@" || return $?
        [[ "$*" != *'input_filename == $compose'* ]] || return 17
    }
    reject dockerValidateCandidate "${TEST_ROOT}/base.json" "${DOCKER_CONFIG_CANDIDATE}"
    grep -Fq '候选 JSON 配置无效' "${LOG}" || fail '候选 JSON 批量工具错误未传播'
) || fail '候选 JSON 批量校验故障合同失败'
(
    printf '{invalid\n' >"${TEST_ROOT}/broken-contract.json"
    dockerConfigureSchemaFile() { printf '%s\n' "${TEST_ROOT}/broken-contract.json"; }
    reject dockerConfigureSpecValidate "${TEST_ROOT}/base.json"
) || fail '非法 schema 未拒绝'
(
    dockerFeatureMatrixFile() { printf '%s\n' "${TEST_ROOT}/broken-contract.json"; }
    reject dockerConfigureSpecValidate "${TEST_ROOT}/base.json"
) || fail '非法支持矩阵未拒绝'
cat "${TEST_ROOT}/base.json" "${TEST_ROOT}/base.json" >"${TEST_ROOT}/multiple-specs.json"
printf '[]\n' >"${TEST_ROOT}/nonobject-spec.json"
reject dockerConfigureSpecValidate "${TEST_ROOT}/multiple-specs.json"
reject dockerConfigureSpecValidate "${TEST_ROOT}/nonobject-spec.json"

# bundle 缺少站点能力声明时，真实 bundle gate 必须拒绝含 site 的规格。
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-site-content")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-21-static.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" ||
    fail '无 site 的旧规格被新能力 gate 误拒绝'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

# 纯 Hy2 准备静态网页和启用 local 都要求新能力；原 Nginx 静态网页保持兼容。
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-hy2-local-site")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-hy2-local.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-hy2-static.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-mixed-hy2-local.json"
for spec in valid-hy2 valid-mixed-hy2 valid-mixed-hy2-static; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/${spec}.json" ||
        fail "${spec}: 未启用 local 的旧规格被新能力 gate 误拒绝"
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

# HTTP-01 仅在显式开启时需要新版 bundle，旧部署不能被能力门禁误拒绝。
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-acme-webroot")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-http01-21-default.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" ||
    fail '未开启 HTTP-01 的旧规格被新能力 gate 误拒绝'
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

# 显式 ALPN 需要新版能力；旧规格的默认值不增加兼容门槛。
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved"
jq 'del(."x-padm-fallback-alpn")' \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
for protocol in 27 29; do
    dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-${protocol}-static.json" ||
        fail "${protocol}: 旧默认 ALPN 被能力门禁误拒绝"
    for index in 0 1 2; do
        reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/valid-alpn-${protocol}-${index}.json"
    done
done
mv -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json.saved" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for protocol in 27 29; do
    for index in 0 1 2; do
        spec="${TEST_ROOT}/valid-alpn-${protocol}-${index}.json"
        output="${TEST_ROOT}/alpn-core-${protocol}-${index}.json"
        dockerGenerateXrayConfig "${spec}" "${output}"
        alpn=$(jq -c '.core.protocols[0].fallback_tls.alpn' "${spec}")
        jq -e --argjson alpn "${alpn}" --arg uuid "${UUID}" --argjson protocol "${protocol}" '
          any(.inbounds[]; .tag == "entry-site" and
            .streamSettings.tlsSettings.alpn == $alpn and
            .settings.fallbacks == [{dest:"nginx:31300",xver:1},
              {alpn:"h2",dest:"nginx:31302",xver:1}] and
            (if $protocol == 27 then
              .settings.clients == [{id:$uuid,email:"site",flow:"xtls-rprx-vision"}]
             else .settings.clients == [{password:$uuid,email:$uuid}] end))
        ' "${output}" >/dev/null || fail "${protocol}: ALPN 输出改变认证或 fallback"
        # 只为分享 URI 启用私密副本，不改变原 TLS 规格的订阅合同。
        jq '.subscription.enabled = true' "${spec}" >"${TEST_ROOT}/alpn-share.json"
        dockerGenerateSubscription "${TEST_ROOT}/alpn-share.json" "${TEST_ROOT}/alpn-link-${protocol}-${index}.txt"
        encoded=$(jq -rn --argjson alpn "${alpn}" '$alpn | join(",") | @uri')
        if [[ "${protocol}" == 27 ]]; then
            expected="vless://${UUID}@proxy.example.com:24443?encryption=none&flow=xtls-rprx-vision&security=tls&sni=${DOMAIN}&fp=chrome&alpn=${encoded}&type=tcp#site"
        else
            expected="trojan://${UUID}@proxy.example.com:24443?peer=${DOMAIN}&security=tls&fp=chrome&sni=${DOMAIN}&alpn=${encoded}&type=tcp#site"
        fi
        [[ "$(<"${TEST_ROOT}/alpn-link-${protocol}-${index}.txt")" == "${expected}" ]] ||
            fail "${protocol}: 分享 URI 未保留 ALPN 顺序"
    done
    jq 'del(.core.protocols[0].fallback_tls.alpn)' "${TEST_ROOT}/valid-alpn-${protocol}-0.json" \
        >"${TEST_ROOT}/legacy-alpn-${protocol}.json"
    dockerGenerateXrayConfig "${TEST_ROOT}/legacy-alpn-${protocol}.json" "${TEST_ROOT}/legacy-alpn-${protocol}-core.json"
    cmp -s "${TEST_ROOT}/legacy-alpn-${protocol}-core.json" "${TEST_ROOT}/alpn-core-${protocol}-0.json" ||
        fail "${protocol}: 缺省 ALPN 改变旧核心输出"
done

for protocol in 21 22 23 24 25 27 29; do
    for mode in default static redirect; do
        spec="${TEST_ROOT}/valid-${protocol}-${mode}.json"
        output="${TEST_ROOT}/nginx-${protocol}-${mode}.conf"
        dockerGenerateNginxConfig "${spec}" "${output}"
        if [[ "${mode}" == redirect ]]; then
            grep -Fq 'return 302' "${output}" && grep -Fq 'https://example.com/path?a=1&b=2#part' "${output}" ||
                fail "${protocol}: 302 未保留目标"
        elif [[ "${mode}" == static ]]; then
            grep -Fq 'root /srv/padm;' "${output}" && grep -Fq 'try_files' "${output}" ||
                fail "${protocol}: 静态站点未渲染受管根"
            ! grep -Fq 'return 302' "${output}" || fail "${protocol}: 静态站点被重定向"
        else
            grep -Fq '<h1>Welcome</h1>' "${output}" || fail "${protocol}: 默认页未渲染"
            ! grep -Fq 'try_files /index.html @padm_fallback;' "${output}" ||
                fail "${protocol}: 显式默认页仍发布旧静态首页"
        fi
        if [[ "${protocol}" == 27 || "${protocol}" == 29 ]]; then
            for text in 'listen 31300 proxy_protocol;' 'listen [::]:31300 proxy_protocol;' \
                'listen 31302 proxy_protocol;' 'listen [::]:31302 proxy_protocol;'; do
                grep -Fq "${text}" "${output}" || fail "${protocol}: ${mode} 改变 PROXY listener"
            done
            [[ "$(grep -cF 'http2 on;' "${output}")" == 1 ]] ||
                fail "${protocol}: ${mode} 改变 h2 后端"
        else
            if [[ "${protocol}" == 21 ]]; then
                grep -Fq 'location ~ "^/subscriptions/' "${output}" ||
                    fail "${protocol}: ${mode} 丢失订阅路由"
            else
                ! grep -Fq 'location ~ "^/subscriptions/' "${output}" ||
                    fail "${protocol}: ${mode} 意外开放未启用订阅"
            fi
            case "${protocol}" in
            21|22) grep -Fq 'location = /abcdefghws' "${output}" ;;
            23) grep -Fq 'location = /abcdefgh' "${output}" ;;
            24|25) grep -Fq 'grpc_pass grpc://xray:31297;' "${output}" ;;
            esac || fail "${protocol}: ${mode} 丢失代理路由"
        fi
        dockerGenerateCompose "${spec}" "${TEST_ROOT}/legacy-compose.json"
        jq 'del(.tls.http01)' "${TEST_ROOT}/valid-http01-${protocol}-${mode}.json" \
            >"${TEST_ROOT}/http01-disabled.json"
        dockerGenerateNginxConfig "${TEST_ROOT}/http01-disabled.json" "${TEST_ROOT}/http01-disabled.conf"
        dockerGenerateCompose "${TEST_ROOT}/http01-disabled.json" "${TEST_ROOT}/http01-disabled-compose.json"
        cmp -s "${output}" "${TEST_ROOT}/http01-disabled.conf" &&
            cmp -s "${TEST_ROOT}/legacy-compose.json" "${TEST_ROOT}/http01-disabled-compose.json" ||
            fail "${protocol}: 删除 HTTP-01 字段改变旧版生成内容"
        ! grep -Fq '8088' "${output}" || fail "${protocol}: 缺省部署开放 HTTP-01"
        spec="${TEST_ROOT}/valid-http01-${protocol}-${mode}.json"
        http01Output="${TEST_ROOT}/nginx-http01-${protocol}-${mode}.conf"
        dockerGenerateNginxConfig "${spec}" "${http01Output}"
        dockerGenerateCompose "${spec}" "${TEST_ROOT}/http01-compose.json"
        for text in 'listen 8088;' 'listen [::]:8088;' 'root /srv/padm-acme/active;'; do
            grep -Fq "${text}" "${http01Output}" || fail "${protocol}: HTTP-01 未渲染独立入口"
        done
        jq -e '
          [.services.nginx.ports[] | select(endswith(":80:8088/tcp"))] |
          sort == ["0.0.0.0:80:8088/tcp","[::]:80:8088/tcp"]
        ' "${TEST_ROOT}/http01-compose.json" >/dev/null ||
            fail "${protocol}: HTTP-01 未固定双栈宿主 80 到容器 8088"
        jq -e 'any(.services.nginx.volumes[]; .type == "bind" and
          .source == "${PADM_DOCKER_ROOT}/data/acme-webroot" and
          .target == "/srv/padm-acme" and .read_only == true)' \
            "${TEST_ROOT}/http01-compose.json" >/dev/null ||
            fail "${protocol}: HTTP-01 缺少专属只读 Nginx 挂载"
    done
done
jq 'del(.site)' "${TEST_ROOT}/valid-27-static.json" >"${TEST_ROOT}/legacy-fallback.json"
dockerGenerateNginxConfig "${TEST_ROOT}/legacy-fallback.json" "${TEST_ROOT}/legacy-nginx.conf"
grep -Fq 'try_files /index.html @padm_fallback;' "${TEST_ROOT}/legacy-nginx.conf" ||
    fail '无 site 的旧规格改变静态首页 fallback'
(
    # 同次生成包含多种入口；每个 server 都须完整复用独立入口正文，包括末尾换行与空正文。
    localSpec="${TEST_ROOT}/multi-site.json"
    siteCalls="${TEST_ROOT}/multi-site-calls"
    eval "$(declare -f dockerGenerateSiteLocations | sed '1s/dockerGenerateSiteLocations/dockerGenerateSiteLocationsOriginal/')"
    dockerGenerateSiteLocations() {
        printf '%s\n' "${3:-tls}" >>"${siteCalls}"
        dockerGenerateSiteLocationsOriginal "$@"
    }
    for mode in legacy default static redirect; do
        jq -n --arg mode "${mode}" \
            --slurpfile base "${TEST_ROOT}/base.json" \
            --slurpfile p21 "${TEST_ROOT}/valid-21-default.json" \
            --slurpfile p22 "${TEST_ROOT}/valid-22-default.json" \
            --slurpfile p23 "${TEST_ROOT}/valid-23-default.json" \
            --slurpfile p24 "${TEST_ROOT}/valid-24-default.json" \
            --slurpfile p25 "${TEST_ROOT}/valid-25-default.json" \
            --slurpfile p27 "${TEST_ROOT}/valid-27-default.json" \
            --slurpfile p29 "${TEST_ROOT}/valid-29-default.json" '
          $base[0] |
          .core.protocols = [$p21[0].core.protocols[0], $p22[0].core.protocols[0],
            $p23[0].core.protocols[0], $p24[0].core.protocols[0],
            $p25[0].core.protocols[0], $p27[0].core.protocols[0],
            ($p29[0].core.protocols[0] | .fallback_tls.http_port = 31304 |
              .fallback_tls.http2_port = 31306)] |
          if $mode == "legacy" then del(.site)
          elif $mode == "redirect" then .site = {mode:$mode,url:"https://example.com/path?a=1&b=2#part"}
          else .site = {mode:$mode} end
        ' >"${localSpec}" || fail "${mode}: 多入口规格生成失败"
        : >"${siteCalls}"
        : >"${TEST_ROOT}/expected-tls-${mode}"
        : >"${TEST_ROOT}/expected-fallback-${mode}"
        dockerGenerateSiteLocationsOriginal "${localSpec}" "${TEST_ROOT}/expected-tls-${mode}" ||
            fail "${mode}: TLS 站点正文生成失败"
        dockerGenerateSiteLocationsOriginal "${localSpec}" "${TEST_ROOT}/expected-fallback-${mode}" fallback ||
            fail "${mode}: fallback 站点正文生成失败"
        dockerGenerateNginxConfig "${localSpec}" "${TEST_ROOT}/multi-nginx-${mode}.conf" ||
            fail "${mode}: 多入口 Nginx 生成失败"
        [[ "$(<"${siteCalls}")" == $'fallback\ntls' ]] || fail "${mode}: 重复读取多入口站点正文"
        python3 - "${TEST_ROOT}" "${mode}" <<'PY' || fail "${mode}: 多入口正文与独立入口不同"
import re
import sys
from pathlib import Path

root, mode = Path(sys.argv[1]), sys.argv[2]
text = (root / f"multi-nginx-{mode}.conf").read_bytes()
expected = {
    b"tls": (root / f"expected-tls-{mode}").read_bytes(),
    b"fallback": (root / f"expected-fallback-{mode}").read_bytes(),
}
counts = {b"tls": 0, b"fallback": 0}
for match in re.finditer(rb"(?ms)^server \{\n(.*?)^\}\n", text):
    body = match.group(1)
    kind = b"fallback" if b" proxy_protocol;\n" in body else b"tls" if b" ssl;\n" in body else None
    if kind is None:
        continue
    counts[kind] += 1
    assert body.endswith(expected[kind]), (mode, kind, "站点正文与独立入口不同")
    if not expected[kind]:
        assert b"location = / {\n" not in body, (mode, "空正文改变")
assert counts == {b"tls": 5, b"fallback": 4}, (mode, counts)
PY
    done
) || fail '多入口站点正文差分失败'
SOURCE=${TEST_ROOT}/public-site
SECOND=${TEST_ROOT}/second-site
mkdir -p "${SOURCE}/assets" "${SECOND}"
printf '<h1>original-site</h1>\n' >"${SOURCE}/index.html"
printf 'body { color: green; }\n' >"${SOURCE}/assets/site.css"
printf '<h1>replacement-site</h1>\n' >"${SECOND}/index.html"
chmod -R go-w "${SOURCE}" "${SECOND}"
[[ "$(dockerSiteSourceValidate "${SOURCE}/")" == "${SOURCE}" ]] ||
    fail '独立站点目录未返回规范路径'
(
    cd "${SOURCE}"
    reject dockerSiteSourceValidate /
    reject dockerSiteSourceValidate ''
)
reject dockerSiteSourceValidate "${root}"
reject dockerSiteSourceValidate "${root}/config"
reject dockerSiteSourceValidate "${TEST_ROOT}"
ln -s "${SOURCE}" "${TEST_ROOT}/source-link"
reject dockerSiteSourceValidate "${TEST_ROOT}/source-link"
reject dockerSiteSourceValidate "${TEST_ROOT}/source-link//"
reject dockerSiteSourceValidate "${TEST_ROOT}/source-link/assets"
mkdir -p "${TEST_ROOT}/directory-index/data/static/index.html"
printf 'asset\n' >"${TEST_ROOT}/directory-index/data/static/index.html/asset.txt"
reject dockerSiteSourceValidate "${TEST_ROOT}/directory-index/data/static"
reject dockerSiteStateValidate "${TEST_ROOT}/valid-21-static.json" "${TEST_ROOT}/directory-index"
for name in .env credentials.env private.key id_rsa; do
    printf 'private\n' >"${SOURCE}/${name}"
    reject dockerSiteSourceValidate "${SOURCE}"
    rm -- "${SOURCE}/${name}"
done
printf '%s\n' '-----BEGIN PRIVATE KEY-----' 'private' '-----END PRIVATE KEY-----' >"${SOURCE}/asset.txt"
reject dockerSiteSourceValidate "${SOURCE}"
rm -- "${SOURCE}/asset.txt"
for kind in symlink hardlink fifo; do
    case "${kind}" in
    symlink) ln -s "${SOURCE}/index.html" "${SOURCE}/unsafe" ;;
    hardlink) ln "${SOURCE}/index.html" "${SOURCE}/unsafe" ;;
    fifo) mkfifo "${SOURCE}/unsafe" ;;
    esac
    reject dockerSiteSourceValidate "${SOURCE}"
    reject dockerSiteTreeValidate "${SOURCE}"
    rm -- "${SOURCE}/unsafe"
done
for path in "${SOURCE}" "${SOURCE}/assets" "${SOURCE}/assets/site.css"; do
    chmod g+w "${path}"
    reject dockerSiteSourceValidate "${SOURCE}"
    chmod g-w "${path}"
done
mkdir -p "${TEST_ROOT}/unsafe-parent/site"
printf 'index\n' >"${TEST_ROOT}/unsafe-parent/site/index.html"
chmod 0777 "${TEST_ROOT}/unsafe-parent"
reject dockerSiteSourceValidate "${TEST_ROOT}/unsafe-parent/site"
chmod 0700 "${TEST_ROOT}/unsafe-parent"
chown 10001:10001 "${SOURCE}/assets/site.css"
reject dockerSiteSourceValidate "${SOURCE}"
PADM_DOCKER_SKIP_CHOWN=1 dockerSiteSourceValidate "${SOURCE}" >/dev/null ||
    fail '测试属主放宽仍拒绝普通树'
chown 0:0 "${SOURCE}/assets/site.css"
printf '' >"${SECOND}/index.html"
reject dockerSiteSourceValidate "${SECOND}"
printf '<h1>replacement-site</h1>\n' >"${SECOND}/index.html"

snapshot() (
    cd "${root}"
    if [[ "${1:-}" == without-static ]]; then
        find config data secrets -type f ! -path 'data/static/*' -print0
    else
        find config data secrets -type f -print0
    fi | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
    [[ "${1:-}" == without-static ]] || find data/static -printf '%P %m %U %G\n' | sort
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '站点事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail '站点事务遗留候选'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
}
# 可读网页不能替代已有受管 Hy2 部署，完整规格导入也须遵守两步边界。
: >"${COMPOSE_LOG}"
(
    originalRoot=${root}
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/unmanaged-local"
    root=${PADM_DOCKER_INSTALL_DIR}
    dockerInitializeStateRoot
    cp -a -- "${originalRoot}/secrets/tls" "${root}/secrets/"
    mkdir -p "${root}/data/static"
    cp -- "${SOURCE}/index.html" "${root}/data/static/index.html"
    chmod 0750 "${root}/data/static"
    chmod 0640 "${root}/data/static/index.html"
    chown -R 0:10001 "${root}/data/static"
    [[ ! -e "${root}/deployment.json" && ! -e "${root}/config/spec.json" ]] ||
        fail '无部署 local 夹具意外已有受管规格'
    before=$(snapshot)
    composeBefore=$(wc -l <"${COMPOSE_LOG}")
    actual=0
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerTrafficBeforeChange() { fail 'configure local 首配拒绝前触发流量处理'; }
        dockerCreateConfigurationCandidate() { fail 'configure local 首配拒绝前创建候选'; }
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/valid-hy2-local.json" '' '' configure
    ) >"${LOG}" 2>&1 || actual=$?
    grep -Fq 'configure local 需要已有受管部署，不能首次导入本地网页入口' "${LOG}" ||
        fail 'configure local 首配未经过受管部署门禁'
    [[ "${actual}" == 15 && "$(snapshot)" == "${before}" &&
        "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail 'configure local 首配拒绝改变网页、规格或调用 Compose'
    assertClean
)
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化站点夹具失败'
assertClean
# 批量移动只完成首目录便失败时，真实恢复仍须还原全部配置和内容。
before=$(snapshot)
(
    mv() {
        if [[ "${1:-}" == -- && "${2:-}" == "${root}"/.candidate.*/config/xray &&
            "${@: -1}" == "${root}/config/" ]]; then
            command mv -- "$2" "${@: -1}" || return $?
            return 17
        fi
        command mv "$@"
    }
    actual=0
    (dockerMain edit --site-default --confirm PADM-DOCKER-EDIT) >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 14 ]] || fail "部分批量移动失败没有进入恢复: ${actual}"
) || fail '批量安装故障合同失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '部分批量移动失败没有恢复完整原部署'
before=$(snapshot)
composeBefore=$(grep -c '^live:' "${COMPOSE_LOG}")
runEdit 0 --http01 enable --preview
runEdit 2 --http01 unknown --preview
runEdit 2 --http01 enable --http01 disable --preview
runEdit 2 --http01 enable --site-default --preview
runEdit 2 --http01 enable --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --http01 enable --alpn entry-site h2,http/1.1 --preview
runEdit 2 --http01 enable --confirm invalid
runEdit 2 --http01 enable
[[ "$(snapshot)" == "${before}" && "$(grep -c '^live:' "${COMPOSE_LOG}")" == "${composeBefore}" &&
    ! -e "${root}/data/acme-webroot" ]] || fail 'HTTP-01 预览或非法参数改变在线入口'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/valid-http01-21-default.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'HTTP-01 确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" && ! -e "${root}/data/acme-webroot" ]] ||
    fail 'HTTP-01 取消仍开放 80 或创建在线挑战根'
runEdit 0 --http01 enable --confirm PADM-DOCKER-EDIT
jq -e '.tls == {domain:"ws.example.com",http01:true}' "${root}/config/spec.json" >/dev/null ||
    fail 'HTTP-01 专项改变域名或没有开启'
jq -e '[.listeners[] | select(.listener_id == "host-acme-http")] ==
  [{listener_id:"host-acme-http",service:"nginx",public_port:80,container_port:8088,
    transport:"tcp",address_families:["ipv4","ipv6"]}]' "${root}/deployment.json" >/dev/null ||
    fail 'HTTP-01 部署 listener 未固定双栈 80:8088'
[[ "$(stat -c '%a %u %g' "${root}/data/acme-webroot")" == '750 10001 10001' ]] ||
    fail 'HTTP-01 在线根不是 ops 可写的私有目录'
webrootInode=$(stat -c '%d:%i' "${root}/data/acme-webroot")
cp -- "${root}/config/spec.json" "${TEST_ROOT}/http01-enabled.json"
for mutation in \
    '.tls.domain="other.example.com" | .core.protocols[0].websocket.domain="other.example.com"' \
    '.core.protocols[0].public_port=25443 | del(.tls.http01)'; do
    jq "${mutation}" "${TEST_ROOT}/http01-enabled.json" >"${TEST_ROOT}/http01-mixed.json"
    before=$(snapshot)
    runEdit 15 --spec "${TEST_ROOT}/http01-mixed.json" --preview
    [[ "$(snapshot)" == "${before}" ]] || fail 'HTTP-01 混合修改越过原编辑边界'
done
renewal=${root}/secrets/renewal/${DOMAIN}
mkdir -p "${renewal}"
chmod 0700 "${root}/secrets/renewal" "${renewal}"
jq -n --arg domain "${DOMAIN}" '{schema_version:3,domain:$domain,
  email:"admin@example.com",provider:"webroot",enabled:true}' >"${renewal}/request.json"
chmod 0600 "${renewal}/request.json"
before=$(snapshot)
runEdit 15 --http01 disable --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '自动 webroot 续期仍启用时拆掉了 HTTP 入口'
# 回滚走独立入口，关闭版快照合法也不能绕过仍启用的 webroot 自动续期。
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerBackupConfiguration configure
    backup="${root}/backups/update.http01-fixture"
    mv -- "${DOCKER_CONFIG_BACKUP}" "${backup}"
    DOCKER_CONFIG_BACKUP=${backup}
    jq 'del(.tls.http01)' "${backup}/config/spec.json" >"${backup}/config/spec.json.next"
    mv -- "${backup}/config/spec.json.next" "${backup}/config/spec.json"
    chmod 0600 "${backup}/config/spec.json"
    dockerGenerateDeployment "${backup}/config/spec.json" "${backup}/deployment.json"
    dockerGenerateCompose "${backup}/config/spec.json" "${backup}/compose.json"
    dockerGenerateNginxConfig "${backup}/config/spec.json" "${backup}/config/nginx/default.conf"
    dockerValidateConfigurationBackup "${backup}"
    [[ "$(dockerLatestUpdateBackup)" == "${backup}" ]] ||
        fail 'HTTP-01 回滚夹具未经过真实快照发现和校验'
) >"${LOG}" 2>&1 || fail '初始化 HTTP-01 回滚夹具失败'
assertClean
composeBefore=$(grep -c '^live:' "${COMPOSE_LOG}")
actual=0
(dockerMain rollback) >"${LOG}" 2>&1 || actual=$?
[[ "${actual}" == 15 ]] || fail "HTTP-01 回滚拒绝预期 15，实际 ${actual}"
assertClean
grep -Fq '当前域名仍启用 webroot 自动续期' "${LOG}" ||
    fail 'HTTP-01 回滚没有经过自动续期关闭保护'
[[ "$(snapshot)" == "${before}" &&
    "$(grep -c '^live:' "${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail '自动 webroot 续期仍启用时回滚修改了部署或调用了服务'
rm -- "${renewal}/request.json"
rmdir -- "${renewal}" "${root}/secrets/renewal"
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    runEdit "${expected}" --http01 disable --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" &&
        "$(stat -c '%d:%i' "${root}/data/acme-webroot")" == "${webrootInode}" ]] ||
        fail "${failure}: HTTP-01 事务未恢复原入口或替换了在线挂载根"
done
MODE=ok
runEdit 0 --http01 disable --confirm PADM-DOCKER-EDIT
jq -e '.tls == {domain:"ws.example.com"}' "${root}/config/spec.json" >/dev/null &&
    jq -e 'all(.listeners[]; .listener_id != "host-acme-http")' "${root}/deployment.json" >/dev/null ||
    fail '关闭 HTTP-01 没有删除 opt-in 字段和部署 listener'
jq '.tls.http01=true' "${root}/config/spec.json" >"${TEST_ROOT}/http01-only.json"
runEdit 0 --spec "${TEST_ROOT}/http01-only.json" --confirm PADM-DOCKER-EDIT
runEdit 0 --http01 disable --confirm PADM-DOCKER-EDIT
before=$(snapshot)
runEdit 0 --site-static "${SOURCE}" --preview
[[ "$(snapshot)" == "${before}" ]] || fail '站点预览修改在线内容或配置'
runEdit 2 --site-static "${SOURCE}" --site-default --preview
runEdit 2 --site-static "${SOURCE}" --site-redirect https://example.com --preview
runEdit 2 --site-default --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --site-static "${SOURCE}" --regenerate-reality entry-site --preview
runEdit 2 --site-default --confirm invalid
runEdit 2 --site-default
[[ "$(snapshot)" == "${before}" ]] || fail '非法站点编辑修改在线部署'
runEdit 0 --site-static "${SOURCE}" --confirm PADM-DOCKER-EDIT
cmp -s "${SOURCE}/index.html" "${root}/data/static/index.html" &&
    cmp -s "${SOURCE}/assets/site.css" "${root}/data/static/assets/site.css" ||
    fail '站点提交没有完整复制目录'
jq -e '.site == {mode:"static"}' "${root}/config/spec.json" >/dev/null ||
    fail '站点源路径进入受管规格'
dockerSiteStateValidate "${root}/config/spec.json" "${root}" || fail '已提交静态站点无效'
[[ "$(stat -c '%a %u %g' "${root}/data/static")" == '750 0 10001' &&
    "$(stat -c '%a %u %g' "${root}/data/static/index.html")" == '640 0 10001' ]] ||
    fail '静态资源运行权限不正确'
# Nginx 已有静态网页，也不能经 configure 新增一个 local Hy2 入口。
jq --slurpfile hy2 "${TEST_ROOT}/valid-hy2.json" '
  .core.secondary_type = "sing-box" |
  .core.protocols += [($hy2[0].core.protocols[0] |
    .listener_id = "entry-hy2-new" | .public_port = 25444 | .hy2.masquerade = "local")]
' "${root}/config/spec.json" >"${TEST_ROOT}/nginx-new-local-hy2.json"
dockerConfigureSpecValidate "${TEST_ROOT}/nginx-new-local-hy2.json" ||
    fail '新增 local 的 Nginx 夹具本身违反静态合同'
before=$(snapshot)
composeBefore=$(wc -l <"${COMPOSE_LOG}")
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerTrafficBeforeChange() { fail 'configure 新增 local Hy2 拒绝前触发流量处理'; }
    dockerCreateConfigurationCandidate() { fail 'configure 新增 local Hy2 拒绝前创建候选'; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/nginx-new-local-hy2.json" '' '' configure
) >"${LOG}" 2>&1 || actual=$?
grep -Fq 'configure local 仅支持已有 Hysteria2 入口及已发布的受管静态网页' "${LOG}" ||
    fail 'configure 新增 local Hy2 未经过已有入口门禁'
[[ "${actual}" == 15 && "$(snapshot)" == "${before}" &&
    "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
    fail 'configure 新增 local Hy2 拒绝改变规格、静态内容或调用 Compose'
assertClean
printf '<h1>source-changed</h1>\n' >"${SOURCE}/index.html"
grep -Fq original-site "${root}/data/static/index.html" || fail '在线站点仍引用外部源'
staticBefore=$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)
runEdit 0 --site-redirect https://example.com/new --confirm PADM-DOCKER-EDIT
[[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
    fail '302 编辑删除原静态文件'
runEdit 0 --site-default --confirm PADM-DOCKER-EDIT
[[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
    fail '默认页编辑删除原静态文件'
jq '.site = {mode:"static"}' "${root}/config/spec.json" >"${TEST_ROOT}/static-kept.json"
runEdit 0 --spec "${TEST_ROOT}/static-kept.json" --confirm PADM-DOCKER-EDIT
[[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
    fail '无站点源的编辑丢失现有静态目录'
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    runEdit "${expected}" --site-static "${SECOND}" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 未恢复原静态内容和完整部署"
    grep -Fq 'live:up ' "${COMPOSE_LOG}" || fail "${failure}: 未经过实际事务提交阶段"
done
MODE=ok

# 主题只产生普通静态内容；认证、非空累计和发布文件不得随主题变化。
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"site",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
before=$(snapshot)
protectedBefore=$(snapshot without-static)
runEdit 2 --site-template unknown --preview
runEdit 2 --site-template --preview
runEdit 2 --site-template notes --site-template photos --preview
runEdit 2 --site-template notes --site-static "${SOURCE}" --preview
runEdit 2 --site-template notes --site-default --preview
runEdit 2 --site-template notes --site-redirect https://example.com --preview
runEdit 2 --site-template notes --spec "${TEST_ROOT}/base.json" --preview
runEdit 2 --site-template notes --http01 enable --preview
runEdit 2 --site-template notes --alpn entry-site h2,http/1.1 --preview
runEdit 0 --site-template notes --preview
[[ "$(snapshot)" == "${before}" ]] || fail '主题非法参数或预览改变在线内容和配置'

mkdir -p "${TEST_ROOT}/site-templates"
while IFS=$'\t' read -r theme title accent; do
    runEdit 0 --site-template "${theme}" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot without-static)" == "${protectedBefore}" ]] ||
        fail "${theme}: 主题修改了规格、认证、累计或订阅文件"
    jq -e '.site == {mode:"static"}' "${root}/config/spec.json" >/dev/null ||
        fail "${theme}: 主题或资源路径进入受管规格"
    python3 "${PROJECT_ROOT}/shell/regression/static-site-assets.py" "${PROJECT_ROOT}" \
        --installed "${root}/data/static" >"${LOG}" 2>&1 || fail "${theme}: 主题公开资源不完整"
    expectedFiles=$(awk -v prefix="sites/${theme}/" 'index($2,prefix)==1 {
      print substr($2,length(prefix)+1)}' "${TEST_ROOT}/bundle/assets/static-sites/sites.sha256" | sort)
    [[ "$(find "${root}/data/static" -type f -printf '%P\n' | sort)" == "${expectedFiles}" ]] ||
        fail "${theme}: 主题目录遗漏或增加了清单资源"
    while IFS= read -r resource; do
        case "${resource}" in
        *.png|*.jpg)
            cmp -s "${root}/data/static/${resource}" \
                "${TEST_ROOT}/bundle/assets/static-sites/sites/${theme}/${resource}" ||
                fail "${theme}: 主题图片未完整复制: ${resource}"
            ;;
        esac
    done <<<"${expectedFiles}"
    grep -Fq "${title}" "${root}/data/static/index.html" &&
        grep -Fq "${accent}" "${root}/data/static/assets/style.css" ||
        fail "${theme}: 未渲染固定默认站名或配色"
    [[ "$(stat -c '%a %u %g' "${root}/data/static")" == '750 0 10001' &&
        "$(stat -c '%a %u %g' "${root}/data/static/index.html")" == '640 0 10001' ]] ||
        fail "${theme}: 主题资源运行权限改变"
    cp -a -- "${root}/data/static" "${TEST_ROOT}/site-templates/${theme}"
done <<'THEMES'
notes	Field Notes	#28624b
photos	Light and Distance	#225e91
docs	Pagekit	#974338
THEMES
before=$(snapshot)
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${root}/config/spec.json" '' '' interactive '' "${TEST_ROOT}/site-templates/notes"
) >"${LOG}" 2>&1 || fail '主题候选确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '主题取消改变静态内容、规格、认证或累计'
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    runEdit "${expected}" --site-template notes --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: 主题未恢复旧静态内容和完整部署"
done
MODE=ok

# 资源必须来自完整可信包，损坏在生成备份或调用线上服务前拒绝。
templateAssets=${TEST_ROOT}/bundle/assets/static-sites
cp -a -- "${templateAssets}" "${TEST_ROOT}/template-assets-original"
for damage in missing-page missing-image missing-css missing-manifest tamper symlink hardlink fifo; do
    case "${damage}" in
    missing-page) rm -- "${templateAssets}/sites/notes/about.html" ;;
    missing-image) rm -- "${templateAssets}/sites/photos/assets/forest.jpg" ;;
    missing-css) rm -- "${templateAssets}/sites/docs/assets/style.css" ;;
    missing-manifest) rm -- "${templateAssets}/sites.sha256" ;;
    tamper) printf '\nmodified-resource\n' >>"${templateAssets}/sites/notes/index.html" ;;
    symlink|hardlink|fifo)
        rm -- "${templateAssets}/sites/notes/about.html"
        case "${damage}" in
        symlink) ln -s index.html "${templateAssets}/sites/notes/about.html" ;;
        hardlink) ln "${templateAssets}/sites/notes/index.html" "${templateAssets}/sites/notes/about.html" ;;
        fifo) mkfifo "${templateAssets}/sites/notes/about.html" ;;
        esac
        ;;
    esac
    composeBefore=$(wc -l <"${COMPOSE_LOG}")
    backupsBefore=$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)
    runEdit 15 --site-template notes --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" &&
        "$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)" == "${backupsBefore}" ]] ||
        fail "${damage}: 不安全主题在拒绝前改动部署、备份或服务"
    rm -rf -- "${templateAssets}"
    cp -a -- "${TEST_ROOT}/template-assets-original" "${templateAssets}"
done

# 无主题资源的旧包仍能管理原静态内容、默认页和 302。
cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" "${TEST_ROOT}/template-schema-current.json"
jq 'del(."x-padm-site-templates")' "${TEST_ROOT}/template-schema-current.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
mv -- "${templateAssets}" "${TEST_ROOT}/template-assets-held"
mv -- "${TEST_ROOT}/bundle/shell/core/static_site_renderer.sh" "${TEST_ROOT}/template-renderer-held.sh"
runEdit 15 --site-template notes --preview
[[ "$(snapshot)" == "${before}" ]] || fail '旧包主题拒绝改变部署'
runEdit 0 --site-default --confirm PADM-DOCKER-EDIT
runEdit 0 --site-redirect https://example.com/old-bundle --confirm PADM-DOCKER-EDIT
runEdit 0 --site-static "${TEST_ROOT}/site-templates/docs" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '旧包原站点工作流丢失主题生成后的静态内容'
mv -- "${TEST_ROOT}/template-assets-held" "${templateAssets}"
mv -- "${TEST_ROOT}/template-renderer-held.sh" "${TEST_ROOT}/bundle/shell/core/static_site_renderer.sh"
cp -- "${TEST_ROOT}/template-schema-current.json" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

# 业务恢复继续复制在线静态目录，不新增主题身份或覆盖资源。
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerBusinessExport "${TEST_ROOT}/template-business.json" "${root}/config/spec.json"
    for strategy in merge replace; do
        draft="${TEST_ROOT}/template-business-${strategy}"
        mkdir -p "${draft}"
        dockerBusinessBuildDraft "${TEST_ROOT}/template-business.json" "${root}/config/spec.json" "${strategy}" "${draft}"
        dockerConfigureApply "${draft}/spec.json" '' '' configure "${draft}/business.json"
    done
) >"${LOG}" 2>&1 || fail '主题站点的业务恢复失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '业务恢复改变主题静态目录或回退认证、累计和发布'

# 旧受管树只拒绝链接和特殊文件，不能按发布 allowlist 删除历史静态资源。
printf 'legacy-resource\n' >"${root}/data/static/.legacy-resource"
chmod 0640 "${root}/data/static/.legacy-resource"
chown 0:10001 "${root}/data/static/.legacy-resource"
dockerSiteTreeValidate "${root}/data/static" || fail '普通旧静态资源被发布规则误拒绝'
before=$(snapshot)
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerBackupConfiguration
    backup=${DOCKER_CONFIG_BACKUP}
    grep -qxF data/static "${backup}/present" || fail '新快照遗漏静态目录'
    composeBefore=$(wc -l <"${COMPOSE_LOG}")
    ln -s "${SOURCE}/index.html" "${backup}/data/static/unsafe"
    DOCKER_CONFIG_SWITCHED=1
    reject dockerRestoreConfiguration
    [[ "$(snapshot)" == "${before}" && "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail '损坏站点快照未在停止服务或改动在线目录前拒绝'
    rm -- "${backup}/data/static/unsafe"
    mv -- "${backup}/data/static/index.html" "${backup}/data/static/index.saved"
    reject dockerValidateConfigurationBackup "${backup}"
    mv -- "${backup}/data/static/index.saved" "${backup}/data/static/index.html"
    printf 'damaged\n' >"${root}/data/static/index.html"
    DOCKER_CONFIG_SWITCHED=1
    dockerRestoreConfiguration
    [[ "$(snapshot)" == "${before}" ]] || fail '快照恢复未恢复站点树'
    # 只改夹具快照，复现旧版缺 site 与 data/static 的合法恢复点。
    jq 'del(.site)' "${backup}/config/spec.json" >"${backup}/config/spec.json.next"
    mv -- "${backup}/config/spec.json.next" "${backup}/config/spec.json"
    chmod 0600 "${backup}/config/spec.json"
    dockerGenerateNginxConfig "${backup}/config/spec.json" "${backup}/config/nginx/default.conf"
    sed '/^data\/static$/d' "${backup}/present" >"${backup}/present.next"
    mv -- "${backup}/present.next" "${backup}/present"
    rm -rf -- "${backup}/data/static"
    dockerValidateConfigurationBackup "${backup}"
    printf 'current-legacy-content\n' >"${root}/data/static/index.html"
    DOCKER_CONFIG_SWITCHED=1
    dockerRestoreConfiguration
    grep -qxF current-legacy-content "${root}/data/static/index.html" ||
        fail '旧快照删除当前 legacy 静态内容'
) >"${LOG}" 2>&1 || fail '站点快照合同失败'
assertClean
ln "${root}/data/static/index.html" "${root}/data/static/hardlink"
reject dockerBackupConfiguration
rm -- "${root}/data/static/hardlink"

# 多根枚举或批量复制失败时不能发布恢复点，也不能触碰在线配置。
for backupFailure in find cp; do
    before=$(snapshot)
    (
        DOCKER_CONFIG_BACKUP=
        find() {
            if [[ "${backupFailure}" == find && "$*" == *"${root}/deployment.json"* ]]; then
                command find "$@" || return $?
                return 17
            fi
            command find "$@"
        }
        cp() {
            if [[ "${backupFailure}" == cp && "$*" == *--parents* ]]; then
                command cp -a --parents -- deployment.json "${@: -1}" || return $?
                return 17
            fi
            command cp "$@"
        }
        reject dockerBackupConfiguration
        [[ -z "${DOCKER_CONFIG_BACKUP}" && "$(snapshot)" == "${before}" ]] ||
            fail '失败的批量备份被发布或改变在线内容'
    ) || fail "备份批处理故障未拒绝: ${backupFailure}"
done

# 删除最后一个 Nginx 入口只清除站点模式，仍保留内容和其它 TLS 入口。
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/valid-mixed-static.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化混合站点夹具失败'
assertClean
runEdit 0 --http01 enable --confirm PADM-DOCKER-EDIT
cp -- "${root}/config/spec.json" "${TEST_ROOT}/delete-site-draft.json"
printf '10\nentry-site\n8\n' |
    dockerEditFields "${TEST_ROOT}/delete-site-draft.json" >"${LOG}" 2>&1 ||
    fail '站点配置阻止删除最后一个 Nginx 入口'
jq -e 'has("site") == false and .subscription.enabled == false and .tls.domain == "ws.example.com" and
    (.tls | has("http01") | not) and
    (.core.protocols | length == 1 and .[0].listener_id == "entry-direct")' \
    "${TEST_ROOT}/delete-site-draft.json" >/dev/null || fail '删除入口改变其它 TLS 入口或遗留站点模式'
staticBefore=$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)
runEdit 0 --spec "${TEST_ROOT}/delete-site-draft.json" --confirm PADM-DOCKER-EDIT
[[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
    fail '删除最后一个 Nginx 入口丢失静态内容'

runAlpnStatus() {
    local expected=$1 actual=0
    shift
    (dockerMain protocol alpn-status "$@") >"${LOG}" 2>"${TEST_ROOT}/alpn-status.stderr" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "ALPN 诊断预期 ${expected}，实际 ${actual}"
    assertClean
}
runAlpnStatus 15
runEdit 15 --alpn entry-direct h2,http/1.1 --preview

# 混合入口复用已有站点与非空流量记录，专项不能改动未选择的入口。
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/valid-mixed-alpn.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化 ALPN 混合夹具失败'
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"site",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
before=$(snapshot)
runAlpnStatus 0
jq -e 'type == "array" and length == 2 and all(.[];
  (keys | sort) == (["listener_id","protocol","configured_alpn","running_alpn","recommended_alpn",
    "runtime_matches_spec","recommended","h2_fallback","nginx_matches_spec","repairable"] | sort) and
  (.protocol == 27 or .protocol == 29) and .configured_alpn == ["h2","http/1.1"] and
  .running_alpn == .configured_alpn and .recommended_alpn == ["h2","http/1.1"] and
  .runtime_matches_spec and .recommended and .h2_fallback and .nginx_matches_spec and .repairable)' \
    "${LOG}" >/dev/null || fail 'ALPN 诊断缺少默认合同或输出了多余字段'
[[ "$(snapshot)" == "${before}" ]] || fail 'ALPN 只读诊断改变部署、站点或流量'
runAlpnStatus 15 absent
runEdit 2 --alpn entry-fallback-27 h2 --preview
runEdit 2 --alpn entry-fallback-27 h2,h2 --preview
runEdit 2 --alpn entry-fallback-27 'http/1.1,' --preview
runEdit 2 --alpn entry-fallback-27 h2,http/1.1 --site-default --preview
runEdit 2 --alpn entry-fallback-27 h2,http/1.1 --spec "${TEST_ROOT}/valid-mixed-alpn.json" --preview
runEdit 2 --alpn entry-fallback-27 h2,http/1.1 --regenerate-reality entry-fallback-27 --preview
runEdit 2 --alpn entry-fallback-27 h2,http/1.1 --reality-target entry-fallback-27 example.com 443 example.com --preview
runEdit 2 --alpn entry-fallback-27 h2,http/1.1 --alpn entry-fallback-29 http/1.1 --preview
runEdit 0 --alpn entry-fallback-27 http/1.1,h2 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'ALPN 非法参数或预览改变完整部署'
cp -- "${root}/config/spec.json" "${TEST_ROOT}/alpn-original.json"
jq '(.core.protocols[] | select(.listener_id == "entry-fallback-27") | .fallback_tls.alpn) = ["http/1.1","h2"]' \
    "${root}/config/spec.json" >"${TEST_ROOT}/alpn-cancel.json"
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerSetupRead() { printf -v "$1" '%s' n; }
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/alpn-cancel.json" '' '' interactive
) >"${LOG}" 2>&1 || fail 'ALPN 确认取消失败'
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail 'ALPN 取消改变规格、运行文件、静态内容或流量'
runEdit 0 --alpn entry-fallback-27 http/1.1,h2 --confirm PADM-DOCKER-EDIT
jq -en --slurpfile old "${TEST_ROOT}/alpn-original.json" --slurpfile new "${root}/config/spec.json" '
  $new[0] == ($old[0] |
    (.core.protocols[] | select(.listener_id == "entry-fallback-27") | .fallback_tls.alpn) = ["http/1.1","h2"])
' >/dev/null || fail 'ALPN 专项改变选中字段之外的规格'
runAlpnStatus 0 entry-fallback-27
jq -e 'length == 1 and .[0].listener_id == "entry-fallback-27" and
  .[0].configured_alpn == ["http/1.1","h2"] and .[0].running_alpn == .[0].configured_alpn and
  .[0].runtime_matches_spec and (.[0].recommended | not) and .[0].repairable' \
    "${LOG}" >/dev/null || fail '非推荐但符合规格的 ALPN 被误算为损坏'
! grep -Fq "${UUID}" "${LOG}" || fail 'ALPN 诊断泄露账号'

cp -a -- "${root}/config/xray/config.json" "${TEST_ROOT}/alpn-valid-config.json"
cp -a -- "${root}/config/xray/users.base" "${TEST_ROOT}/alpn-valid-users.base"
cp -a -- "${root}/config/nginx/default.conf" "${TEST_ROOT}/alpn-valid-nginx.conf"
stable=$(snapshot)
# 运行配置中的非数组 ALPN 可能含敏感字符串，诊断必须脱敏且不把 marker 写入任何输出。
secret_alpn=fixture-secret-alpn
jq --arg marker "${secret_alpn}" \
    '(.inbounds[] | select(.tag == "entry-fallback-27") | .streamSettings.tlsSettings.alpn) = $marker' \
    "${TEST_ROOT}/alpn-valid-config.json" >"${root}/config/xray/config.json"
runAlpnStatus 0 entry-fallback-27
jq -e '.[0].running_alpn == null and .[0].repairable' "${LOG}" >/dev/null ||
    fail '非数组 ALPN 未脱敏或未保持可修复'
! grep -Fq "${secret_alpn}" "${LOG}" ||
    fail '非数组 ALPN marker 泄露到诊断标准输出'
! grep -Fq "${secret_alpn}" "${TEST_ROOT}/alpn-status.stderr" ||
    fail '非数组 ALPN marker 泄露到诊断错误输出'
cp -a -- "${TEST_ROOT}/alpn-valid-config.json" "${root}/config/xray/config.json"

for drift in runtime base both; do
    for file in config.json users.base; do
        [[ "${drift}" == both || ( "${drift}" == runtime && "${file}" == config.json ) ||
            ( "${drift}" == base && "${file}" == users.base ) ]] || continue
        jq '(.inbounds[] | select(.tag == "entry-fallback-27") | .streamSettings.tlsSettings.alpn) = ["h3"]' \
            "${root}/config/xray/${file}" >"${TEST_ROOT}/drift-core.json"
        cp -- "${TEST_ROOT}/drift-core.json" "${root}/config/xray/${file}"
    done
    before=$(snapshot)
    runAlpnStatus 0 entry-fallback-27
    jq -e '.[0].repairable and .[0].h2_fallback and .[0].nginx_matches_spec' "${LOG}" >/dev/null ||
        fail "${drift}: 选中入口的单独 ALPN 漂移未标为可修复"
    if [[ "${drift}" != base ]]; then
        jq -e '(.[0].runtime_matches_spec | not) and .[0].running_alpn == null' "${LOG}" >/dev/null ||
            fail "${drift}: 运行 ALPN 漂移未被诊断"
    fi
    runEdit 0 --alpn entry-fallback-27 http/1.1,h2 --preview
    [[ "$(snapshot)" == "${before}" ]] || fail "${drift}: 漂移修复预览提交了配置"
    runEdit 0 --alpn entry-fallback-27 http/1.1,h2 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${stable}" ]] || fail "${drift}: 未精确恢复 ALPN 或改变其它文件"
done

# 所选字段之外的漂移不能借 ALPN 修复接管，失败后原文件必须原样保留。
for mutation in \
    '(.inbounds[] | select(.tag == "entry-fallback-27") | .settings.fallbacks[1].xver) = 0' \
    '(.inbounds[] | select(.tag == "entry-fallback-27") | .streamSettings.tlsSettings.serverName) = "other.example.com"' \
    '(.inbounds[] | select(.tag == "entry-fallback-27") | .settings.clients[0].id) = "22222222-2222-4222-8222-222222222222"' \
    '.routing.rules += [{type:"field",domain:["example.com"],outboundTag:"direct"}]' \
    '(.inbounds[] | select(.tag == "entry-fallback-29") | .streamSettings.tlsSettings.alpn) = ["h3"]'; do
    jq "${mutation}" "${TEST_ROOT}/alpn-valid-config.json" >"${root}/config/xray/config.json"
    before=$(snapshot)
    runAlpnStatus 0 entry-fallback-27
    jq -e '.[0].repairable == false' "${LOG}" >/dev/null || fail 'ALPN 诊断接受其它漂移'
    runEdit 15 --alpn entry-fallback-27 h2,http/1.1 --preview
    [[ "$(snapshot)" == "${before}" ]] || fail 'ALPN 拒绝其它漂移后改变部署'
    cp -a -- "${TEST_ROOT}/alpn-valid-config.json" "${root}/config/xray/config.json"
done
printf '\n# fixture-nginx-drift\n' >>"${root}/config/nginx/default.conf"
before=$(snapshot)
runAlpnStatus 0 entry-fallback-27
jq -e '.[0].nginx_matches_spec == false and .[0].repairable == false' "${LOG}" >/dev/null ||
    fail 'ALPN 诊断未拒绝 Nginx 漂移'
runEdit 15 --alpn entry-fallback-27 h2,http/1.1 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'Nginx 漂移拒绝改变文件'
cp -a -- "${TEST_ROOT}/alpn-valid-nginx.conf" "${root}/config/nginx/default.conf"
printf '{\n' >"${root}/config/xray/config.json"
before=$(snapshot)
runAlpnStatus 15 entry-fallback-27
runEdit 15 --alpn entry-fallback-27 h2,http/1.1 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'ALPN 损坏 JSON 拒绝后改变文件'
cp -a -- "${TEST_ROOT}/alpn-valid-config.json" "${root}/config/xray/config.json"

# 专项诊断在读取或比较前拒绝 FIFO，超时护栏避免边界回退拖住整套回归。
for fifo in "${root}/config/xray/config.json" "${root}/config/nginx/fixture-fifo"; do
    [[ "${fifo}" != "${root}/config/xray/config.json" ]] || rm -- "${fifo}"
    mkfifo -- "${fifo}"
    actual=0
    timeout -k 1 5 bash -c '
      source "$1"
      dockerHostPreflight() { :; }
      dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
      dockerMain protocol alpn-status entry-fallback-27
    ' _ "${PROJECT_ROOT}/install-docker.sh" >"${LOG}" 2>"${TEST_ROOT}/alpn-status.stderr" || actual=$?
    [[ "${actual}" == 15 ]] || fail "ALPN 特殊文件诊断应返回 15 而非阻塞: ${actual}"
    assertClean
    rm -- "${fifo}"
    [[ "${fifo}" != "${root}/config/xray/config.json" ]] ||
        cp -a -- "${TEST_ROOT}/alpn-valid-config.json" "${fifo}"
done

runEdit 0 --alpn entry-fallback-29 http/1.1 --confirm PADM-DOCKER-EDIT
runAlpnStatus 0 entry-fallback-29
jq -e 'length == 1 and .[0].configured_alpn == ["http/1.1"] and
  .[0].running_alpn == ["http/1.1"] and .[0].h2_fallback and .[0].runtime_matches_spec and
  .[0].nginx_matches_spec and .[0].repairable and (.[0].recommended | not)' "${LOG}" >/dev/null ||
    fail 'Trojan 单 HTTP/1.1 ALPN 合同错误'
# 仅运行配置漂移，users.base 保持规范顺序；事务失败恢复必须保留该运行时差异。
jq '(.inbounds[] | select(.tag == "entry-fallback-29") | .streamSettings.tlsSettings.alpn) = ["h3"]' \
    "${root}/config/xray/config.json" >"${TEST_ROOT}/alpn-29-runtime-drift.json"
cp -- "${TEST_ROOT}/alpn-29-runtime-drift.json" "${root}/config/xray/config.json"
before=$(snapshot)
for failure in health-fail int term; do
    MODE=${failure}
    rm -f -- "${TEST_ROOT}/failed-once"
    expected=14
    [[ "${failure}" != int ]] || expected=130
    [[ "${failure}" != term ]] || expected=143
    runEdit "${expected}" --alpn entry-fallback-29 h2,http/1.1 --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail "${failure}: ALPN 事务未恢复规格、文件、站点和非空流量"
done
MODE=ok

# Xray Nginx 类型继续使用同一主题入口，直连和 sing-box 23 仍明确拒绝。
for protocol in 21 22 23 24 25 27 29; do
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/valid-${protocol}-static.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail "${protocol}: 初始化主题支持范围夹具失败"
    assertClean
    before=$(snapshot)
    runEdit 0 --site-template notes --preview
    [[ "$(snapshot)" == "${before}" ]] || fail "${protocol}: 主题预览修改已有部署"
done
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/valid-site-reality.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化主题与 Reality 共存夹具失败'
assertClean
before=$(snapshot)
runEdit 0 --site-template notes --preview
[[ "$(snapshot)" == "${before}" ]] || fail '主题预览改动共存的 Reality 入口'
for spec in valid-direct valid-sing-upgrade valid-mixed-sing-upgrade; do
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/${spec}.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail "${spec}: 初始化主题拒绝范围夹具失败"
    assertClean
    before=$(snapshot)
    composeBefore=$(wc -l <"${COMPOSE_LOG}")
    runEdit 15 --site-template notes --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" && "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail "${spec}: 无适用入口的主题拒绝改变已有部署或服务"
done

# Hy2 先准备普通静态站点，再编辑已有入口启用 local；混合 Nginx 共用同一目录。
for spec in valid-hy2 valid-mixed-hy2; do
    if [[ "${spec}" == valid-mixed-hy2 ]]; then
        jq --slurpfile reality "${TEST_ROOT}/valid-site-reality.json" '
          .core.protocols += [($reality[0].core.protocols[] | select(.id == 1) | .public_port = 25445)]
        ' "${TEST_ROOT}/${spec}.json" >"${TEST_ROOT}/hy2-site-topology.json"
    else
        cp -- "${TEST_ROOT}/${spec}.json" "${TEST_ROOT}/hy2-site-topology.json"
    fi
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        dockerConfigureApply "${TEST_ROOT}/hy2-site-topology.json" '' '' configure
    ) >"${LOG}" 2>&1 || fail "${spec}: 初始化 Hy2 站点夹具失败"
    assertClean
    before=$(snapshot)
    runEdit 0 --site-template notes --preview
    [[ "$(snapshot)" == "${before}" ]] || fail "${spec}: Hy2 主题预览改变部署"
    runEdit 0 --site-template notes --confirm PADM-DOCKER-EDIT
    jq -e '.site == {mode:"static"} and
      all(.core.protocols[] | select(.id == 3); .hy2.masquerade == "" and .hy2.obfs == null)' \
        "${root}/config/spec.json" >/dev/null || fail "${spec}: 主题提前启用 Hy2 local"
    jq -e 'all(.services["sing-box"].volumes[]; .target != "/srv/padm")' \
        "${root}/compose.json" >/dev/null || fail "${spec}: 未启用 local 就挂载网页"
    jq -e 'all(.inbounds[] | select(.type == "hysteria2"); has("masquerade") | not)' \
        "${root}/config/sing-box/users.base" >/dev/null || fail "${spec}: 准备阶段改变 Hy2 伪装"
    staticBefore=$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)
    jq '(.core.protocols[] | select(.id == 3) | .hy2.masquerade) = "local"' \
        "${root}/config/spec.json" >"${TEST_ROOT}/hy2-site-local.json"
    before=$(snapshot)
    runEdit 0 --spec "${TEST_ROOT}/hy2-site-local.json" --preview
    [[ "$(snapshot)" == "${before}" ]] || fail "${spec}: local 预览修改线上状态"
    if [[ "${spec}" == valid-hy2 ]]; then
        (
            trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
            dockerAcquireDeploymentLock
            dockerConfigureApply "${TEST_ROOT}/hy2-site-local.json" '' '' configure
        ) >"${LOG}" 2>&1 || fail '已有 Hy2/static 的 configure local 被误拒绝'
        assertClean
    fi
    runEdit 0 --spec "${TEST_ROOT}/hy2-site-local.json" --confirm PADM-DOCKER-EDIT
    [[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
        fail "${spec}: local 编辑改写已发布网页"
    jq -e 'all(.inbounds[] | select(.type == "hysteria2");
      .masquerade == "file:///srv/padm/" and (has("obfs") | not))' \
        "${root}/config/sing-box/users.base" >/dev/null || fail "${spec}: local 未生成固定文件路径"
    jq -e '[.services["sing-box"].volumes[] | select(.target == "/srv/padm")] ==
      [{type:"bind",source:"${PADM_DOCKER_ROOT}/data/static",target:"/srv/padm",read_only:true}]' \
        "${root}/compose.json" >/dev/null || fail "${spec}: local 网页挂载未固定只读目录"
    if [[ "${spec}" == valid-mixed-hy2 ]]; then
        jq -e 'any(.services.nginx.volumes[];
          .source == "${PADM_DOCKER_ROOT}/data/static" and .target == "/srv/padm" and .read_only)' \
            "${root}/compose.json" >/dev/null || fail '混合 Hy2/Nginx 没有共用静态目录'
    else
        jq -e '.services | has("nginx") | not' "${root}/compose.json" >/dev/null ||
            fail '纯 Hy2 local 新增无用 Nginx 服务'
    fi
    before=$(snapshot)
    composeBefore=$(wc -l <"${COMPOSE_LOG}")
    runEdit 15 --site-default --confirm PADM-DOCKER-EDIT
    runEdit 15 --site-redirect https://example.com --confirm PADM-DOCKER-EDIT
    jq '(.core.protocols[] | select(.id == 3) | .hy2.obfs) =
      {type:"salamander",password:"0123456789abcdef"}' \
        "${root}/config/spec.json" >"${TEST_ROOT}/hy2-local-obfs.json"
    runEdit 15 --spec "${TEST_ROOT}/hy2-local-obfs.json" --preview
    [[ "$(snapshot)" == "${before}" && "$(wc -l <"${COMPOSE_LOG}")" == "${composeBefore}" ]] ||
        fail "${spec}: local 的 default/302/混淆拒绝改变线上状态"
    for failure in health-fail int term; do
        MODE=${failure}
        rm -f -- "${TEST_ROOT}/failed-once"
        expected=14
        [[ "${failure}" != int ]] || expected=130
        [[ "${failure}" != term ]] || expected=143
        runEdit "${expected}" --site-template photos --confirm PADM-DOCKER-EDIT
        [[ "$(snapshot)" == "${before}" ]] || fail "${spec}/${failure}: 未恢复 local 网页、配置和流量"
    done
    MODE=ok
    if [[ "${spec}" == valid-mixed-hy2 ]]; then
        # 删除消费者只调整其配置，剩余 Hy2 local 继续服务同一份网页。
        cp -- "${root}/config/spec.json" "${TEST_ROOT}/hy2-delete-nginx.json"
        printf '10\nentry-site\n8\n' |
            dockerEditFields "${TEST_ROOT}/hy2-delete-nginx.json" >"${LOG}" 2>&1 ||
            fail '删除最后 Nginx 入口被 Hy2 local 站点阻止'
        jq -e '.site == {mode:"static"} and (.tls | has("http01") | not) and
          any(.core.protocols[]; .id == 3 and .hy2.masquerade == "local")' \
            "${TEST_ROOT}/hy2-delete-nginx.json" >/dev/null || fail '删除 Nginx 清掉 Hy2 local 站点模式'
        runEdit 0 --spec "${TEST_ROOT}/hy2-delete-nginx.json" --confirm PADM-DOCKER-EDIT
        jq -e '(.services | has("nginx") | not) and
          any(.services["sing-box"].volumes[]; .target == "/srv/padm" and .read_only)' \
            "${root}/compose.json" >/dev/null || fail '删除 Nginx 丢失 Hy2 local 只读挂载'
        cp -- "${root}/config/spec.json" "${TEST_ROOT}/hy2-delete-last-consumer.json"
        printf '10\nentry-other-site\n8\n' |
            dockerEditFields "${TEST_ROOT}/hy2-delete-last-consumer.json" >"${LOG}" 2>&1 ||
            fail '删除最后 Hy2 站点消费者失败'
        jq -e '(has("site") | not) and .core.type == "xray" and .core.secondary_type == null and
          (.core.protocols | length == 1 and .[0].id == 1)' \
            "${TEST_ROOT}/hy2-delete-last-consumer.json" >/dev/null ||
            fail '删除最后站点消费者没有清理模式或改变剩余 Reality'
        runEdit 0 --spec "${TEST_ROOT}/hy2-delete-last-consumer.json" --confirm PADM-DOCKER-EDIT
        [[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
            fail '删除站点消费者丢失已发布静态内容'
    fi
done
python3 "${PROJECT_ROOT}/docker/tests/sites-real.py" "${TEST_ROOT}"
printf 'docker-sites-regression-ok\n'
