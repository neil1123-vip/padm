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
for tool in jq python3 nginx openssl stat chmod chown readlink find sort sha256sum; do
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
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerConfigureReleasePrepare() { :; }
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
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
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
mixed = copy.deepcopy(base)
direct_entry = copy.deepcopy(direct["core"]["protocols"][0])
direct_entry.update(listener_id="entry-direct", public_port=25443)
mixed["core"]["protocols"].append(direct_entry)
mixed["site"] = dict(mode="static")
case("valid-mixed-static", mixed, True)
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
    done
done
jq 'del(.site)' "${TEST_ROOT}/valid-27-static.json" >"${TEST_ROOT}/legacy-fallback.json"
dockerGenerateNginxConfig "${TEST_ROOT}/legacy-fallback.json" "${TEST_ROOT}/legacy-nginx.conf"
grep -Fq 'try_files /index.html @padm_fallback;' "${TEST_ROOT}/legacy-nginx.conf" ||
    fail '无 site 的旧规格改变静态首页 fallback'
python3 "${PROJECT_ROOT}/docker/tests/sites-real.py" "${TEST_ROOT}"

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
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
    find data/static -printf '%P %m %U %G\n' | sort
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '站点事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' \) -print -quit)" ]] ||
        fail '站点事务遗留候选'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
}
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化站点夹具失败'
assertClean
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

# 删除最后一个 Nginx 入口只清除站点模式，仍保留内容和其它 TLS 入口。
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/valid-mixed-static.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化混合站点夹具失败'
assertClean
cp -- "${root}/config/spec.json" "${TEST_ROOT}/delete-site-draft.json"
printf '10\nentry-site\n8\n' |
    dockerEditFields "${TEST_ROOT}/delete-site-draft.json" >"${LOG}" 2>&1 ||
    fail '站点配置阻止删除最后一个 Nginx 入口'
jq -e 'has("site") == false and .subscription.enabled == false and .tls.domain == "ws.example.com" and
    (.core.protocols | length == 1 and .[0].listener_id == "entry-direct")' \
    "${TEST_ROOT}/delete-site-draft.json" >/dev/null || fail '删除入口改变其它 TLS 入口或遗留站点模式'
staticBefore=$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)
runEdit 0 --spec "${TEST_ROOT}/delete-site-draft.json" --confirm PADM-DOCKER-EDIT
[[ "$(find "${root}/data/static" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${staticBefore}" ]] ||
    fail '删除最后一个 Nginx 入口丢失静态内容'
printf 'docker-sites-regression-ok\n'
