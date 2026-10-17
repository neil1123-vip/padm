#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-recovery-preview.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-recovery-preview-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || {
    printf 'docker-recovery-preview-fail: Linux root is required\n' >&2
    exit 1
}
for tool in jq python3 stat chmod chown find cmp sha256sum; do
    command -v "${tool}" >/dev/null || exit 1
done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/source" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
MODE=ok
CASES=0
LOG=${TEST_ROOT}/command.log
ALICE=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
HISTORY=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
DOMAIN=ws.example.com
TOKEN=0123456789abcdef0123456789abcdef
SHARE_TOKEN=recovery-group-token

fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-recovery-preview-fail: %s\n' "$*" >&2
    exit 1
}
candidate_fail() {
    printf 'docker-recovery-preview-candidate-fail: %s\n' "$*" >&2
    exit 99
}

# 仅替换宿主、发布下载和容器执行；归档、业务、生成、权限与锁走生产代码。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerLockInstalledDeployment() { dockerAcquireDeploymentLock; }
dockerTrafficRuntimeCheck() { :; }
dockerConfigurePortsAvailable() { :; }
dockerTlsValidateCandidate() { :; }
# REALITY 目标探测可能访问公网或调用派生容器；此处仅隔离只读检测，规格与生成保持真实。
dockerRealityTargetsValidate() { :; }
dockerIPv6NetworkManage() { :; }
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerConfigureSchemaFile() { printf '%s\n' "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"; }
dockerConfigureReleasePrepare() {
    printf '%s\n' "$@" >"${TEST_ROOT}/release-arguments"
    DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/bundle"
    DOCKER_CONFIG_RELEASE_INPUTS=$(jq -c '{release,images}' "${TEST_ROOT}/base.json") || return 1
    if [[ "${MODE}" == release-mismatch ]]; then
        DOCKER_CONFIG_RELEASE_INPUTS=$(jq -c '.release.manifest_sha256 = ("b"*64)' \
            <<<"${DOCKER_CONFIG_RELEASE_INPUTS}") || return 1
    fi
}
dockerComposeRun() { candidate_fail "预览执行了在线 Compose: $*"; }
dockerComposeExecute() { candidate_fail "预览执行了在线恢复: $*"; }
dockerInstallCandidate() { candidate_fail '预览安装了候选'; }
dockerTrafficBeforeChange() { candidate_fail '预览采集或写入了在线流量'; }
dockerRealityProbeRun() {
    local directory probe
    [[ "$#" == 13 && "$1 $2 $3 $4 $5 $6" == \
        '60 --network none --env XRAY_LOCATION_ASSET=/etc/padm/xray/geo --volume' &&
        "$7" == */config/xray/geo:/etc/padm/xray/geo:ro && "$8" == --volume &&
        "$9" == */geo-probe.json:/probe.json:ro &&
        "${10}" == "$(jq -r '.images.xray' "${EXPECTED_SPEC}")" &&
        "${11} ${12} ${13}" == '-test -config /probe.json' ]] ||
        candidate_fail "Geo 探针未使用固定镜像、只读挂载或无网络: $*"
    directory=${7%:/etc/padm/xray/geo:ro}
    probe=${9%:/probe.json:ro}
    [[ -n "${EXPECTED_GEO_DIR}" && "$(stat -c '%u:%g:%a' "${probe}")" == \
        "0:${PADM_DOCKER_CONTAINER_GID}:640" ]] || candidate_fail 'Geo 探针输入或权限错误'
    jq -e '.routing.rules == [
      {type:"field",domain:["geosite:cn"],outboundTag:"direct"},
      {type:"field",ip:["geoip:cn"],outboundTag:"direct"}]' "${probe}" >/dev/null ||
        candidate_fail 'Geo 探针没有强制加载双库'
    for file in state.json geoip.dat geosite.dat; do
        cmp -- "${EXPECTED_GEO_DIR}/${file}" "${directory}/${file}" ||
            candidate_fail 'Geo 候选未保持原字节'
        [[ "$(stat -c '%u:%g:%a' "${directory}/${file}")" == \
            "0:${PADM_DOCKER_CONTAINER_GID}:640" ]] || candidate_fail 'Geo 候选文件权限错误'
    done
    [[ "$(stat -c '%u:%g:%a' "${directory}")" == "0:${PADM_DOCKER_CONTAINER_GID}:750" ]] ||
        candidate_fail 'Geo 候选目录权限错误'
    printf '%s\n' "${MODE}" >>"${TEST_ROOT}/geo-probed"
    [[ "${MODE}" != geo-probe-fail ]]
}
docker() {
    [[ "${1:-}" == ps && "$#" -eq 4 && "$2" == -aq && "$3" == --filter ]] ||
        candidate_fail "非预期 Docker 调用: $*"
    case "$4" in
    "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}")
        [[ "${MODE}" != compose-container ]] || printf '0123456789ab\n' ;;
    "label=io.padm.project=${PADM_DOCKER_PROJECT}")
        [[ "${MODE}" != padm-container ]] || printf '0123456789ab\n' ;;
    *) candidate_fail "非预期项目容器查询: $*" ;;
    esac
}
dockerCandidateCompose() {
    local candidate=$1 marker file relative
    shift
    [[ -d "${candidate}" && -e "${root}/locks/deployment.lock" ]] ||
        candidate_fail '候选校验没有持有部署锁'
    [[ -n "${DOCKER_RECOVERY_INPUT:-}" && -f "${DOCKER_RECOVERY_INPUT}/manifest.json" &&
        "$(stat -c %a "${DOCKER_RECOVERY_INPUT}")" == 700 &&
        "$(stat -c %a "${DOCKER_RECOVERY_INPUT%/input}")" == 700 ]] ||
        candidate_fail '恢复输入没有处于私密暂存目录'
    [[ ! -e "${candidate}/geo-probe.json" ]] || candidate_fail 'Geo 探针临时配置未清理'
    if [[ -n "${EXPECTED_GEO_DIR}" ]]; then
        jq -e '.services.xray.environment.XRAY_LOCATION_ASSET == "/etc/padm/xray/geo"' \
            "${candidate}/compose.json" >/dev/null || candidate_fail 'Geo 读取路径没有写入 Compose'
    else
        [[ ! -e "${candidate}/config/xray/geo" ]] || candidate_fail '无 Geo 归档生成了 Geo 数据'
    fi
    marker="${TEST_ROOT}/checked-${candidate##*/}"
    if [[ ! -e "${marker}" ]]; then
        jq -en --slurpfile expected "${EXPECTED_SPEC}" \
            --slurpfile actual "${candidate}/config/spec.json" '
          $actual[0].core == $expected[0].core and
          $actual[0].accounts == $expected[0].accounts and
          $actual[0].subscription == $expected[0].subscription
        ' >/dev/null || candidate_fail '恢复改变了入口、独立账号凭据或订阅身份'
        cmp -- "${SOURCE}/config/share-groups.json" "${candidate}/config/share-groups.json" ||
            candidate_fail '分享组身份或外键改变'
        jq -e --slurpfile expected "${EXPECTED_TRAFFIC_FILE}" '
          .schema_version == $expected[0].schema_version and
          .accounts == ($expected[0].accounts | map_values(.baseline = {}))
        ' "${candidate}/business-traffic.json" >/dev/null ||
            candidate_fail '累计、限额、历史账户或 baseline 恢复错误'
        jq -e --arg alice "${ALICE}" --arg uuid '44444444-4444-4444-8444-444444444444' '
          any(.inbounds[]?.settings.clients[]?; .padm_account == $alice and .id == $uuid)
        ' "${candidate}/config/xray/users.base" >/dev/null ||
            candidate_fail '超额账号没有保留在私密基础输入'
        jq -e --arg uuid '44444444-4444-4444-8444-444444444444' '
          all(.inbounds[]?.settings.clients[]?; .id != $uuid)
        ' "${candidate}/config/xray/config.json" >/dev/null ||
            candidate_fail '超额账号仍存在于运行配置'
        jq -e '.services.xray != null and .services.evil == null' \
            "${candidate}/compose.json" >/dev/null ||
            candidate_fail '使用了源归档 Compose 或没有重新生成'
        [[ "$(stat -c %a "${candidate}/config/spec.json")" == 600 &&
            "$(stat -c %a "${candidate}/config/xray/users.base")" == 600 &&
            "$(stat -c %a "${candidate}/config/share-groups.json")" == 600 ]] ||
            candidate_fail '私密候选文件权限过宽'
        if jq -e '.tls != null' "${EXPECTED_SPEC}" >/dev/null; then
            cmp -- "${SOURCE}/secrets/tls/${DOMAIN}.crt" "${candidate}/secrets/tls/${DOMAIN}.crt" &&
                cmp -- "${SOURCE}/secrets/tls/${DOMAIN}.key" "${candidate}/secrets/tls/${DOMAIN}.key" &&
                cmp -- "${SOURCE}/data/static/index.html" "${candidate}/data/static/index.html" ||
                candidate_fail 'TLS 或静态资源没有恢复到候选'
        else
            [[ -z "$(find "${candidate}/secrets/tls" -mindepth 1 -print -quit)" ]] ||
                candidate_fail '无 TLS 规格意外恢复了 TLS 输入'
        fi
        [[ ! -e "${TEST_ROOT}/source-compose-executed" ]] ||
            candidate_fail '源 Compose 被执行'
        for file in results.tsv blocked.tsv; do
            cmp -- "${SOURCE}/data/reality-targets/${file}" "${candidate}/data/reality-targets/${file}" ||
                candidate_fail '目标库未按原字节恢复'
            [[ "$(stat -c '%u:%g:%a' "${candidate}/data/reality-targets/${file}")" == 0:0:600 ]] ||
                candidate_fail '目标库文件权限不私密'
        done
        [[ "$(stat -c '%u:%g:%a' "${candidate}/data/reality-targets")" == 0:0:700 ]] ||
            candidate_fail '目标库目录权限不私密'
        if [[ -n "${EXPECTED_RENEWAL_DIR}" ]]; then
            [[ "$(find "${candidate}/secrets/renewal" -type f | wc -l)" == 5 &&
                -z "$(find "${candidate}/secrets/renewal" -type d ! -perm 0700 -print -quit)" &&
                -z "$(find "${candidate}/secrets/renewal" -type f ! -perm 0600 -print -quit)" &&
                -z "$(find "${candidate}/secrets/renewal" \( ! -user root -o ! -group root \) -print -quit)" ]] ||
                candidate_fail '停用续期登记的数量、所有者或权限错误'
            while IFS= read -r file; do
                relative=${file#"${EXPECTED_RENEWAL_DIR}/"}
                cmp -- "${file}" "${candidate}/secrets/renewal/${relative}" ||
                    candidate_fail '停用续期登记没有保持原字节'
            done < <(find "${EXPECTED_RENEWAL_DIR}" -type f)
        else
            [[ ! -e "${candidate}/secrets/renewal" ]] || candidate_fail '无续期输入生成了登记'
        fi
        if jq -e '.reality_stream != null' "${EXPECTED_SPEC}" >/dev/null; then
            cmp -- "${candidate}/config/nginx/stream/reality.conf" \
                <(dockerGenerateRealityStreamConfig "${EXPECTED_SPEC}" /dev/stdout) ||
                candidate_fail '共存 stream 未由规格重新生成'
            jq -e '.services.xray.ports == ["0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp"] and
              .services.nginx.ports == ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"] and
              any(.services.nginx.volumes[]; .target == "/etc/nginx/stream.d" and .read_only == true)
            ' "${candidate}/compose.json" >/dev/null || candidate_fail '共存 Compose 映射错误'
            jq -e '[.listeners[] | select(.listener_id == "entry-site" or .listener_id == "entry-reality")] |
              length == 2 and all(.[]; .service == "nginx" and .public_port == 443 and .container_port == 15443)
            ' "${candidate}/deployment.json" >/dev/null || candidate_fail '共存部署有效公网端口错误'
            grep -q '@proxy.example.com:443?' "${candidate}/data/subscription/${TOKEN}" &&
                grep -q '@proxy.example.com:24445?' "${candidate}/data/subscription/${TOKEN}" ||
                candidate_fail '共存订阅没有保留有效公网端口及未绑定入口'
        fi
        : >"${marker}"
        printf '%s\n' "${MODE}" >>"${TEST_ROOT}/candidate-checked"
        case "${MODE}" in
        int) kill -INT "${BASHPID}" ;;
        term) kill -TERM "${BASHPID}" ;;
        esac
    fi
    if [[ "$*" == --file*' nginx -t' ]]; then
        printf '%s\n' "${MODE}" >>"${TEST_ROOT}/nginx-checked"
        [[ "${MODE}" != nginx-fail ]] || return 1
    fi
    [[ "${MODE}" != validation-fail ]]
}

mkdir -p -- "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/features.json" \
    "${TEST_ROOT}/bundle/docker/contracts/features.json"
dockerInitializeStateRoot
mkdir -p -- "${root}/secrets/tls" "${root}/data/static" "${root}/data/traffic"
printf 'fixture-cert\n' >"${root}/secrets/tls/${DOMAIN}.crt"
printf 'fixture-key\n' >"${root}/secrets/tls/${DOMAIN}.key"
printf '<!doctype html><title>Recovery fixture</title>\n' >"${root}/data/static/index.html"
dockerTlsRuntimePermissions "${root}/secrets/tls"
jq -n --arg domain "${DOMAIN}" --arg token "${TOKEN}" --arg alice "${ALICE}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"xray",secondary_type:null,protocols:[{
     id:21,core:"xray",listener_id:"entry-site",server:"proxy.example.com",public_port:24443,
     address_families:["ipv4","ipv6"],name:"Recovery",uuid:"11111111-1111-4111-8111-111111111111",
     websocket:{domain:$domain,path:"abcdefgh",backend_port:31297,tls_port:8443}}]},
   tls:{domain:$domain},site:{mode:"static"},subscription:{enabled:true,token:$token},
   images:(["xray","sing-box","nginx","ops","net"] |
     map({key:.,value:("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[],accounts:[{
     id:$alice,name:"Alice",enabled:true,uuid:"44444444-4444-4444-8444-444444444444",
     password:"Alice.-~@+=:Secret",shadowsocks_password:null,listeners:["entry-site"]}]}
' >"${TEST_ROOT}/base.json"
chmod 0600 "${TEST_ROOT}/base.json"
jq -n --arg alice "${ALICE}" --arg token "${SHARE_TOKEN}" '
  {schema_version:1,groups:[{id:"share-cccccccccccccccc",name:"Recovery-Team",enabled:true,
    token:$token,account_ids:[$alice],listener_ids:["entry-site"]}]}
' >"${root}/config/share-groups.json"
jq -n --arg alice "${ALICE}" --arg history "${HISTORY}" '
  def old: {xray:{upload:{generation:"old-core",value:17},download:{generation:"old-core",value:19}}};
  {schema_version:1,accounts:{
    ($alice):{name:"Alice",upload:17,download:19,limit_bytes:30,baseline:old},
    ($history):{name:"Historical",upload:41,download:43,limit_bytes:1000,baseline:old}}}
' >"${root}/data/traffic/state.json"
chmod 0600 "${root}/config/share-groups.json" "${root}/data/traffic/state.json"
dockerConfigureSpecValidate "${TEST_ROOT}/base.json" || fail '源规格夹具无效'
dockerCreateConfigurationCandidate || fail '源候选创建失败'
SOURCE=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${TEST_ROOT}/base.json" "${SOURCE}" || fail '源候选生成失败'
printf 'docker\n' >"${SOURCE}/mode"
mkdir -p -- "${SOURCE}/data/traffic"
cp -- "${root}/data/traffic/state.json" "${SOURCE}/data/traffic/state.json"
chmod 0600 "${SOURCE}/mode" "${SOURCE}/data/traffic/state.json"
mkdir -m 0700 -- "${SOURCE}/data/reality-targets"
printf 'Example.COM:00443\tExample.COM\t\tcustom\tyes\tunknown\tunknown\t\tauto_probe\tunknown\tunknown\tunknown\tunknown\t0\t\n' \
    >"${SOURCE}/data/reality-targets/results.tsv"
printf 'blocked.example||custom-reason|custom description\n' >"${SOURCE}/data/reality-targets/blocked.tsv"
chmod 0600 "${SOURCE}/data/reality-targets/"*.tsv
jq -n --arg command "touch ${TEST_ROOT}/source-compose-executed" '
  {services:{evil:{image:"untrusted.invalid/evil",entrypoint:["/bin/sh","-c",$command]}}}
' >"${SOURCE}/compose.json"
chmod 0640 "${SOURCE}/compose.json"
dockerManagedSpecMatchesDeployment "${SOURCE}/config/spec.json" \
    "${SOURCE}/deployment.json" "${SOURCE}/images.env" || fail '源部署证据不一致'
ARCHIVE="${TEST_ROOT}/private recovery archive.tar"
python3 -B "${PROJECT_ROOT}/docker/lib/recovery.py" export \
    --root "${SOURCE}" --output "${ARCHIVE}" >/dev/null || fail '源归档导出失败'
DOCKER_CONFIG_CANDIDATE=
EXPECTED_SPEC="${TEST_ROOT}/base.json"

archive_variant() {
    local name=$1 file=${2:-} filter=${3:-}
    VARIANT="${TEST_ROOT}/variant-${name}"
    cp -a -- "${SOURCE}" "${VARIANT}"
    if [[ -n "${file}" ]]; then
        jq "${filter}" "${VARIANT}/${file}" >"${TEST_ROOT}/variant.json"
        cat -- "${TEST_ROOT}/variant.json" >"${VARIANT}/${file}"
    fi
}
export_variant() {
    python3 -B "${PROJECT_ROOT}/docker/lib/recovery.py" export \
        --root "${VARIANT}" --output "${TEST_ROOT}/${1}.tar" >/dev/null ||
        fail "变体归档失败: $1"
}
snapshot() {
    python3 -B - "${root}" <<'PY'
import hashlib
import json
import os
import pathlib
import stat
import sys
root = pathlib.Path(sys.argv[1])
entries = []
for path in sorted([root] + list(root.rglob("*"))):
    relative = path.relative_to(root).as_posix()
    if relative == "locks" or relative.startswith("locks/"):
        continue
    info = path.lstat()
    payload = os.readlink(path) if path.is_symlink() else (
        hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None)
    entries.append((relative, stat.S_IMODE(info.st_mode), info.st_uid, info.st_gid, payload))
print(json.dumps(entries, separators=(",", ":")))
PY
}
prepare_target() {
    root="${TEST_ROOT}/target-${1}"
    export PADM_DOCKER_INSTALL_DIR="${root}"
    dockerInitializeStateRoot
    MODE=ok
    EXPECTED_GEO_DIR=
    EXPECTED_RENEWAL_DIR=
    EXPECTED_SPEC="${TEST_ROOT}/base.json"
    EXPECTED_TRAFFIC_FILE="${SOURCE}/data/traffic/state.json"
}
run_case() {
    local name=$1 archive=$2 expected=$3 status=0
    shift 3
    snapshot >"${TEST_ROOT}/before.json"
    (dockerMain restore preview "${archive}" "$@") >"${LOG}" 2>&1 || status=$?
    [[ "${status}" -eq "${expected}" ]] || fail "${name}: 退出码 ${status}，预期 ${expected}"
    snapshot >"${TEST_ROOT}/after.json"
    cmp -- "${TEST_ROOT}/before.json" "${TEST_ROOT}/after.json" ||
        fail "${name}: 预览改变了目标或留下暂存"
    [[ ! -e "${root}/locks/deployment.lock" && ! -L "${root}/locks/deployment.lock" ]] ||
        fail "${name}: 部署锁没有释放"
    [[ ! -e "${TEST_ROOT}/source-compose-executed" ]] || fail "${name}: 源 Compose 被执行"
    CASES=$((CASES + 1))
}

prepare_target tls-static
run_case tls-static "${ARCHIVE}" 0 --manifest "${TEST_ROOT}/trusted.json" \
    --bundle "${TEST_ROOT}/trusted.tar" --control-bundle "${TEST_ROOT}/control.tar"
[[ "$(cat "${TEST_ROOT}/release-arguments")" == \
    "$(printf '%s\n' "${TEST_ROOT}/trusted.json" "${TEST_ROOT}/trusted.tar" "${TEST_ROOT}/control.tar")" ]] ||
    fail '可信发布参数没有完整传递'
grep -q '灾备恢复预览通过' "${LOG}" || fail '正常预览没有输出明确结果'
grep -q '"reality_results": 1' "${LOG}" && grep -q '"reality_blocked": 1' "${LOG}" ||
    fail '预览缺少目标库条数'
! grep -q 'Example.COM\|custom-reason' "${LOG}" || fail '预览泄露目标库记录'
grep -q '"geo_files": 0' "${LOG}" || fail '无 Geo 预览缺少兼容计数'
grep -q '"renewal_registrations": 0' "${LOG}" || fail '无续期预览缺少兼容计数'

archive_variant renewal-disabled
mkdir -m 0700 -- "${VARIANT}/secrets/renewal"
for provider in dns_cf standalone webroot alpn; do
    domain="${provider//_/-}.example.com"
    version=1
    [[ "${provider}" != standalone ]] || version=2
    [[ "${provider}" != webroot ]] || version=3
    [[ "${provider}" != alpn ]] || version=4
    mkdir -m 0700 -- "${VARIANT}/secrets/renewal/${domain}"
    jq -n --arg domain "${domain}" --arg provider "${provider}" --argjson version "${version}" \
        '{schema_version:$version,domain:$domain,email:"admin@example.com",provider:$provider,enabled:false}' \
        >"${VARIANT}/secrets/renewal/${domain}/request.json"
    chmod 0600 "${VARIANT}/secrets/renewal/${domain}/request.json"
done
printf '# DNS provider\r\nDNS_Token=private-value\r\n' \
    >"${VARIANT}/secrets/renewal/dns-cf.example.com/credentials.env"
chmod 0600 "${VARIANT}/secrets/renewal/dns-cf.example.com/credentials.env"
RENEWAL_SOURCE=${VARIANT}
export_variant renewal-disabled
prepare_target renewal-disabled
EXPECTED_RENEWAL_DIR="${RENEWAL_SOURCE}/secrets/renewal"
run_case renewal-disabled "${TEST_ROOT}/renewal-disabled.tar" 0
grep -q '"renewal_registrations": 4' "${LOG}" || fail '续期预览缺少登记计数'
! grep -q 'private-value\|admin@example.com\|dns-cf.example.com' "${LOG}" || fail '续期预览泄露登记或凭据'

for variant in enabled webroot-enabled webroot-credentials; do
    VARIANT="${TEST_ROOT}/variant-renewal-${variant}"
    cp -a -- "${RENEWAL_SOURCE}" "${VARIANT}"
    entry=standalone.example.com
    [[ "${variant}" != webroot-* ]] || entry=webroot.example.com
    if [[ "${variant}" == webroot-credentials ]]; then
        cp -- "${VARIANT}/secrets/renewal/dns-cf.example.com/credentials.env" \
            "${VARIANT}/secrets/renewal/${entry}/credentials.env"
    else
        jq '.enabled = true' "${VARIANT}/secrets/renewal/${entry}/request.json" >"${TEST_ROOT}/request.json"
        cat -- "${TEST_ROOT}/request.json" >"${VARIANT}/secrets/renewal/${entry}/request.json"
    fi
    export_variant "renewal-${variant}"
    prepare_target "renewal-${variant}"
    run_case "renewal-${variant}" "${TEST_ROOT}/renewal-${variant}.tar" "${PADM_DOCKER_RC_STATE}"
    grep -q 'enabled=false' "${LOG}" || fail "续期 ${variant} 未明确拒绝"
done

archive_variant acme-empty
mkdir -p -- "${VARIANT}/data/acme"
chmod 0700 -- "${VARIANT}/data/acme"
export_variant acme-empty
prepare_target acme-empty
run_case acme-empty "${TEST_ROOT}/acme-empty.tar" 0
printf 'ACCOUNT_CONF=must-not-execute\n' >"${VARIANT}/data/acme/account.conf"
chmod 0600 "${VARIANT}/data/acme/account.conf"
export_variant acme-input
prepare_target acme-input
run_case acme-input "${TEST_ROOT}/acme-input.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'ACME 执行配置' "${LOG}" || fail '实际 ACME 输入未明确拒绝'

archive_variant stream config/spec.json '
  .core.protocols += [{id:1,core:"xray",listener_id:"entry-reality",server:"proxy.example.com",
    public_port:24444,address_families:["ipv4","ipv6"],name:"Reality",
    uuid:"11111111-1111-4111-8111-111111111111",reality:{server_name:"reality.example.com",
      target_host:"reality.example.com",target_port:443,
      public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
      private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",short_id:"6ba85179e30d4fc2"}}] |
  .core.protocols += [(.core.protocols[1] | .id = 26 | .listener_id = "entry-other" |
    .public_port = 24445 | .name = "Other-gRPC" | .grpc = {service_name:"other"})] |
  .accounts[0].listeners += ["entry-reality","entry-other"] |
  .reality_stream = {listener_id:"entry-reality",website_listener_id:"entry-site"}'
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail '受管共存夹具无效'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
mkdir -p -- "${VARIANT}/config/nginx/stream"
printf 'untrusted archived stream;\n' >"${VARIANT}/config/nginx/stream/reality.conf"
chmod 0640 "${VARIANT}/config/nginx/stream/reality.conf"
STREAM_SOURCE=${VARIANT}
export_variant stream
prepare_target stream
EXPECTED_SPEC="${STREAM_SOURCE}/config/spec.json"
run_case stream "${TEST_ROOT}/stream.tar" 0
jq -e '.listeners == [{listener_id:"entry-site",public_port:443},
  {listener_id:"entry-reality",public_port:443},{listener_id:"entry-other",public_port:24445}]' \
    <(sed -n '/^{/,$p' "${LOG}") >/dev/null || fail '共存预览未显示有效公网端口'

prepare_target stream-nginx-fail
EXPECTED_SPEC="${STREAM_SOURCE}/config/spec.json"
MODE=nginx-fail
run_case stream-nginx-fail "${TEST_ROOT}/stream.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'Nginx 候选配置校验失败' "${LOG}" || fail '共存 Nginx 失败未明确拒绝'

cp -- "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json" "${TEST_ROOT}/schema.json"
jq 'del(.["x-padm-reality-stream-deployment"])' "${TEST_ROOT}/schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
prepare_target stream-missing-capability
run_case stream-missing-capability "${TEST_ROOT}/stream.tar" "${PADM_DOCKER_RC_MANIFEST}"
grep -q '目标控制 bundle 不支持' "${LOG}" || fail '共存能力缺失未明确拒绝'
cp -- "${TEST_ROOT}/schema.json" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

VARIANT="${TEST_ROOT}/variant-stream-host"
cp -a -- "${STREAM_SOURCE}" "${VARIANT}"
jq '.reality_stream = {listener_id:"entry-reality",host_website:{
  domains:["host.example.com"],address:"host.docker.internal",port:8443}}' \
    "${VARIANT}/config/spec.json" >"${TEST_ROOT}/host.json"
cat -- "${TEST_ROOT}/host.json" >"${VARIANT}/config/spec.json"
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail '宿主网站拒绝夹具无效'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant stream-host
prepare_target stream-host
run_case stream-host "${TEST_ROOT}/stream-host.tar" "${PADM_DOCKER_RC_STATE}"
grep -q '宿主网站共存' "${LOG}" || fail '宿主网站未明确拒绝'

archive_variant geo
mkdir -m 0750 -- "${VARIANT}/config/xray/geo"
printf 'fixture-ip\000\377\n' >"${VARIANT}/config/xray/geo/geoip.dat"
printf 'fixture-site\000\376\n' >"${VARIANT}/config/xray/geo/geosite.dat"
jq -n --arg ip "$(sha256sum "${VARIANT}/config/xray/geo/geoip.dat" | cut -d ' ' -f 1)" \
    --arg site "$(sha256sum "${VARIANT}/config/xray/geo/geosite.dat" | cut -d ' ' -f 1)" \
    '{schema_version:1,version:"202610170001",enabled:false,
      sha256:{"geoip.dat":$ip,"geosite.dat":$site}}' >"${VARIANT}/config/xray/geo/state.json"
chmod 0640 "${VARIANT}/config/xray/geo/"*
GEO_SOURCE=${VARIANT}
export_variant geo
prepare_target geo
EXPECTED_GEO_DIR="${GEO_SOURCE}/config/xray/geo"
run_case geo "${TEST_ROOT}/geo.tar" 0
grep -q '"geo_files": 3' "${LOG}" || fail 'Geo 预览缺少三文件计数'

prepare_target geo-probe-fail
EXPECTED_GEO_DIR="${GEO_SOURCE}/config/xray/geo"
MODE=geo-probe-fail
run_case geo-probe-fail "${TEST_ROOT}/geo.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'Geo 数据的无网络 Xray 解析校验失败' "${LOG}" || fail 'Geo 探针失败未明确拒绝'

VARIANT="${TEST_ROOT}/variant-geo-enabled"
cp -a -- "${GEO_SOURCE}" "${VARIANT}"
jq '.enabled = true' "${VARIANT}/config/xray/geo/state.json" >"${TEST_ROOT}/state.json"
cat -- "${TEST_ROOT}/state.json" >"${VARIANT}/config/xray/geo/state.json"
export_variant geo-enabled
prepare_target geo-enabled
run_case geo-enabled "${TEST_ROOT}/geo-enabled.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'enabled=false' "${LOG}" || fail 'Geo 自动更新启用未明确拒绝'

VARIANT="${TEST_ROOT}/variant-geo-digest"
cp -a -- "${GEO_SOURCE}" "${VARIANT}"
printf 'changed-data\n' >"${VARIANT}/config/xray/geo/geoip.dat"
export_variant geo-digest
prepare_target geo-digest
run_case geo-digest "${TEST_ROOT}/geo-digest.tar" "${PADM_DOCKER_RC_STATE}"
grep -q '摘要一致' "${LOG}" || fail 'Geo 数据与 state 摘要失配未明确拒绝'

VARIANT="${TEST_ROOT}/variant-geo-secondary"
cp -a -- "${GEO_SOURCE}" "${VARIANT}"
jq '.core.type = "sing-box" | .core.secondary_type = "xray" |
  .core.protocols += [{id:1,core:"sing-box",listener_id:"entry-secondary",server:"proxy.example.com",
    public_port:24444,address_families:["ipv4"],name:"Secondary",uuid:"11111111-1111-4111-8111-111111111111",
    reality:{server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
      private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"}}]' \
    "${VARIANT}/config/spec.json" >"${TEST_ROOT}/secondary.json"
cat -- "${TEST_ROOT}/secondary.json" >"${VARIANT}/config/spec.json"
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant geo-secondary
prepare_target geo-secondary
EXPECTED_SPEC="${VARIANT}/config/spec.json"
EXPECTED_GEO_DIR="${GEO_SOURCE}/config/xray/geo"
run_case geo-secondary "${TEST_ROOT}/geo-secondary.tar" 0

VARIANT="${TEST_ROOT}/variant-geo-no-xray"
cp -a -- "${GEO_SOURCE}" "${VARIANT}"
jq '.tls = null | .subscription.enabled = false | del(.site) |
  .core.type = "sing-box" | .core.secondary_type = null | .core.protocols[0] |=
  (del(.websocket) | .id = 1 | .core = "sing-box" |
    .reality = {server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
      private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"})' \
    "${VARIANT}/config/spec.json" >"${TEST_ROOT}/no-xray.json"
cat -- "${TEST_ROOT}/no-xray.json" >"${VARIANT}/config/spec.json"
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant geo-no-xray
prepare_target geo-no-xray
run_case geo-no-xray "${TEST_ROOT}/geo-no-xray.tar" "${PADM_DOCKER_RC_STATE}"
grep -q '主核心或副核心包含 Xray' "${LOG}" || fail '无 Xray 的 Geo 归档未明确拒绝'
[[ "$(wc -l <"${TEST_ROOT}/geo-probed")" -eq 3 ]] || fail 'Geo 探针次数错误'

archive_variant bad-library
printf 'malformed\n' >"${VARIANT}/data/reality-targets/results.tsv"
export_variant bad-library
prepare_target bad-library
run_case bad-library "${TEST_ROOT}/bad-library.tar" "${PADM_DOCKER_RC_STATE}"

# 1,024 条历史账使紧凑 JSON 超过 Linux 单参数上限，恢复链不得把完整账作为参数传递。
archive_variant large-traffic
jq -c --arg history "${HISTORY}" '
  .accounts[$history] as $template |
  .accounts |= del(.[$history]) |
  reduce range(0;1024) as $index (.;
    .accounts["historical-\($index)"] = ($template |
      .name = "Historical-\($index)" | .upload = ($index + 41) |
      .download = ($index + 43) | .limit_bytes = ($index + 10000)))
' "${VARIANT}/data/traffic/state.json" >"${TEST_ROOT}/large-traffic.json"
[[ "$(stat -c %s "${TEST_ROOT}/large-traffic.json")" -gt 131072 ]] ||
    fail '大账夹具没有超过 Linux 单参数上限'
cp -- "${TEST_ROOT}/large-traffic.json" "${VARIANT}/data/traffic/state.json"
export_variant large-traffic
prepare_target large-traffic
EXPECTED_TRAFFIC_FILE="${VARIANT}/data/traffic/state.json"
run_case large-traffic "${TEST_ROOT}/large-traffic.tar" 0

# 无 TLS 的受限部署同样可预览，不能因缺少 secrets/tls 而误拒绝。
archive_variant no-tls config/spec.json '
  .tls = null | .subscription.enabled = false | del(.site) | .core.protocols[0] |=
    (del(.websocket) | .id = 1 |
      .reality = {server_name:"reality.example.com",target_host:"reality.example.com",target_port:443,
        private_key:("A"*43),public_key:("B"*43),short_id:"1234abcd"})'
rm -rf -- "${VARIANT}/secrets/tls" "${VARIANT}/data/static"
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant no-tls
prepare_target no-tls
EXPECTED_SPEC="${VARIANT}/config/spec.json"
run_case no-tls "${TEST_ROOT}/no-tls.tar" 0

prepare_target corrupt
printf 'not a recovery archive\n' >"${TEST_ROOT}/corrupt.tar"
chmod 0600 "${TEST_ROOT}/corrupt.tar"
run_case corrupt "${TEST_ROOT}/corrupt.tar" "${PADM_DOCKER_RC_STATE}"

prepare_target deployed
printf '{}\n' >"${root}/deployment.json"
run_case deployed "${ARCHIVE}" "${PADM_DOCKER_RC_STATE}"

prepare_target residual
mkdir -- "${root}/data/traffic"
printf 'keep-residual\n' >"${root}/data/traffic/state.json"
run_case residual "${ARCHIVE}" "${PADM_DOCKER_RC_STATE}"

prepare_target unknown-root
printf 'keep-unknown\n' >"${root}/unexpected"
run_case unknown-root "${ARCHIVE}" "${PADM_DOCKER_RC_STATE}"

for mode in compose-container padm-container; do
    prepare_target "${mode}"
    MODE=${mode}
    run_case "${mode}" "${ARCHIVE}" "${PADM_DOCKER_RC_STATE}"
done

python3 -B - "${ARCHIVE}" "${TEST_ROOT}/architecture.tar" <<'PY'
import io
import json
import os
import sys
import tarfile
with tarfile.open(sys.argv[1], "r:") as source, tarfile.open(
        sys.argv[2], "w", format=tarfile.USTAR_FORMAT) as target:
    for entry in source:
        content = source.extractfile(entry).read() if entry.isfile() else None
        if entry.name == "manifest.json":
            manifest = json.loads(content)
            manifest["architecture"] = "arm64" if manifest["architecture"] == "amd64" else "amd64"
            content = json.dumps(manifest, separators=(",", ":")).encode()
            entry.size = len(content)
        target.addfile(entry, io.BytesIO(content) if content is not None else None)
os.chmod(sys.argv[2], 0o600)
PY
prepare_target architecture
run_case architecture "${TEST_ROOT}/architecture.tar" "${PADM_DOCKER_RC_STATE}"

archive_variant renewal
mkdir -m 0700 -- "${VARIANT}/secrets/renewal"
printf '{}\n' >"${VARIANT}/secrets/renewal/provider.json"
chmod 0600 "${VARIANT}/secrets/renewal/provider.json"
export_variant renewal
prepare_target renewal
run_case renewal "${TEST_ROOT}/renewal.tar" "${PADM_DOCKER_RC_STATE}"

archive_variant shares config/share-groups.json '
  .groups[0].account_ids = ["eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"]'
export_variant shares
prepare_target shares
run_case shares "${TEST_ROOT}/shares.tar" "${PADM_DOCKER_RC_STATE}"

archive_variant drift deployment.json '.padm_version = "0.0.0"'
export_variant drift
prepare_target drift
run_case drift "${TEST_ROOT}/drift.tar" "${PADM_DOCKER_RC_STATE}"

archive_variant http01 config/spec.json '.tls.http01 = true'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant http01
prepare_target http01
run_case http01 "${TEST_ROOT}/http01.tar" "${PADM_DOCKER_RC_STATE}"

archive_variant missing-tls
rm -f -- "${VARIANT}/secrets/tls/${DOMAIN}.key"
export_variant missing-tls
prepare_target missing-tls
run_case missing-tls "${TEST_ROOT}/missing-tls.tar" "${PADM_DOCKER_RC_STATE}"

prepare_target release-mismatch
MODE=release-mismatch
run_case release-mismatch "${ARCHIVE}" "${PADM_DOCKER_RC_MANIFEST}"

prepare_target validation-fail
MODE=validation-fail
run_case validation-fail "${ARCHIVE}" "${PADM_DOCKER_RC_STATE}"

for mode in int term; do
    prepare_target "${mode}"
    MODE=${mode}
    expected=130
    [[ "${mode}" != term ]] || expected=143
    run_case "${mode}" "${ARCHIVE}" "${expected}"
done
# Geo 解析失败前也已完成 Compose 候选校验。
[[ "$(wc -l <"${TEST_ROOT}/candidate-checked")" -eq 13 ]] ||
    fail '正常、验证失败或中断场景没有经过真实候选校验'
grep -q '^nginx-fail$' "${TEST_ROOT}/nginx-checked" || fail '未执行 Nginx 失败校验'
printf 'docker-recovery-preview-ok: %s cases\n' "${CASES}"
