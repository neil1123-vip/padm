#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d /root/padm-docker-recovery-preview.XXXXXX)
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
# 材料数学绑定由独立 OpenSSL 回归覆盖；此处验证恢复调用和私密候选。
dockerRecoveryAcmeValidate() {
    local spec=$1 candidate=$2 file
    [[ "$#" == 2 && "${spec}" == "${candidate}/config/spec.json" &&
        -n "${EXPECTED_ACME_DIR}" &&
        "$(jq -r '.tls.domain' "${spec}")" == "${DOMAIN}" &&
        "$(find "${DOCKER_RECOVERY_INPUT}/data/acme" -type f | wc -l)" == 10 &&
        "$(find "${candidate}/data/acme" -type f | wc -l)" == 9 &&
        -z "$(find "${candidate}/data/acme" -type d ! -perm 0700 -print -quit)" &&
        -z "$(find "${candidate}/data/acme" -type f ! -perm 0600 -print -quit)" &&
        -z "$(find "${candidate}/data/acme" \( ! -user root -o ! -group root \) -print -quit)" &&
        ! -e "${candidate}/data/acme/${DOMAIN}_ecc/${DOMAIN}.csr" ]] ||
        candidate_fail 'ACME 材料校验调用、数量或私密权限错误'
    for file in ca/ca.example.test/dir/account.key ca/ca.example.test/dir/account.json \
        "${DOMAIN}_ecc/${DOMAIN}.key" "${DOMAIN}_ecc/${DOMAIN}.cer" \
        "${DOMAIN}_ecc/ca.cer" "${DOMAIN}_ecc/fullchain.cer"; do
        cmp -- "${EXPECTED_ACME_DIR}/${file}" "${candidate}/data/acme/${file}" ||
            candidate_fail 'ACME 原材料没有保持原字节'
    done
    cmp -- "${candidate}/data/acme/account.conf" \
        <(printf "USER_PATH='%s'\nCA_BUNDLE=''\n" \
            '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin') ||
        candidate_fail 'ACME 账户执行配置没有重建'
    for file in "Le_RealCertPath=''" "Le_RealCACertPath=''" \
        "Le_RealKeyPath='/var/lib/padm/tls-output/${DOMAIN}.key'" \
        "Le_RealFullChainPath='/var/lib/padm/tls-output/${DOMAIN}.crt'"; do
        grep -qxF -- "${file}" "${candidate}/data/acme/${DOMAIN}_ecc/${DOMAIN}.conf" ||
            candidate_fail 'ACME 安装输出没有重建到固定目录'
    done
    printf '%s\n' "${MODE}" >>"${TEST_ROOT}/acme-validated"
    [[ "${MODE}" != acme-material-fail ]]
}
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
dockerMaintenanceScheduleApply() { candidate_fail "预览修改了外部调度: $*"; }
dockerRealityProbeRun() {
    local directory probe
    if [[ "$*" == *'wg pubkey'* ]]; then
        [[ "$#" == 16 && "$1 $2 $3 $4 $5 $6 $7 $8 $9 ${10}" == \
            '10 --pull never --user 0:0 --network none --log-driver none --mount' &&
            "${12} ${13}" == '--entrypoint sh' && "${15}" == -ec &&
            "${16}" == 'wg pubkey < /input/private.key' &&
            "${14}" == "$(jq -r '.images.net' "${EXPECTED_SPEC}")" &&
            -n "${EXPECTED_WIREGUARD_DIR}" ]] ||
            candidate_fail 'WireGuard 公钥验证没有使用可信镜像和隔离参数'
        directory=${11#type=bind,src=}
        directory=${directory%,dst=/input,readonly}
        cmp -- "${EXPECTED_WIREGUARD_DIR}/private.key" "${directory}/private.key" ||
            candidate_fail 'WireGuard 公钥验证没有读取归档私钥'
        if [[ "${MODE}" == wireguard-key-mismatch ]]; then
            printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n'
        else
            jq -r '.public_key' "${EXPECTED_WIREGUARD_DIR}/identity.json"
        fi
        return 0
    fi
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
    local candidate=$1 marker file relative core root
    root=$(dockerInstallRoot) || return 1
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
          $actual[0].subscription == $expected[0].subscription and
          $actual[0].tls == $expected[0].tls and
          $actual[0].reality_stream == $expected[0].reality_stream and
          $actual[0].control == $expected[0].control and
          $actual[0].control_sync == $expected[0].control_sync
        ' >/dev/null || candidate_fail '恢复改变了入口、独立账号凭据或订阅身份'
        cmp -- "${SOURCE}/config/share-groups.json" "${candidate}/config/share-groups.json" ||
            candidate_fail '分享组身份或外键改变'
        jq -e --slurpfile expected "${EXPECTED_TRAFFIC_FILE}" '
          .schema_version == $expected[0].schema_version and
          .accounts == ($expected[0].accounts | map_values(.baseline = {}))
        ' "${candidate}/business-traffic.json" >/dev/null ||
            candidate_fail '累计、限额、历史账户或 baseline 恢复错误'
        core=$(jq -r '.core.type' "${EXPECTED_SPEC}")
        if [[ "${core}" == xray || -f "${candidate}/config/xray/users.base" ]]; then
            jq -e --arg alice "${ALICE}" --arg uuid '44444444-4444-4444-8444-444444444444' '
              any(.inbounds[]?.settings.clients[]?; .padm_account == $alice and .id == $uuid)
            ' "${candidate}/config/xray/users.base" >/dev/null ||
                candidate_fail '超额账号没有保留在私密基础输入'
            jq -e --arg uuid '44444444-4444-4444-8444-444444444444' '
              all(.inbounds[]?.settings.clients[]?; .id != $uuid)
            ' "${candidate}/config/xray/config.json" >/dev/null ||
                candidate_fail '超额账号仍存在于运行配置'
        else
            jq -e --arg alice "${ALICE}" '
              any(.inbounds[]?.users[]?; .padm_account == $alice and .password == "Alice.-~@+=:Secret")
            ' "${candidate}/config/sing-box/users.base" >/dev/null ||
                candidate_fail 'sing-box 超额账号的基础凭据丢失'
            jq -e 'all(.inbounds[]?.users[]?; .password != "Alice.-~@+=:Secret")' \
                "${candidate}/config/sing-box/config.json" >/dev/null ||
                candidate_fail 'sing-box 超额账号仍存在于运行配置'
        fi
        jq -e --arg core "${core}" '.services[$core] != null and .services.evil == null' \
            "${candidate}/compose.json" >/dev/null ||
            candidate_fail '使用了源归档 Compose 或没有重新生成'
        [[ "$(stat -c %a "${candidate}/config/spec.json")" == 600 &&
            "$(stat -c %a "${candidate}/config/${core}/users.base")" == 600 &&
            "$(stat -c %a "${candidate}/config/share-groups.json")" == 600 ]] ||
            candidate_fail '私密候选文件权限过宽'
        if jq -e '.tls != null' "${EXPECTED_SPEC}" >/dev/null; then
            cmp -- "${SOURCE}/secrets/tls/${DOMAIN}.crt" "${candidate}/secrets/tls/${DOMAIN}.crt" &&
                cmp -- "${SOURCE}/secrets/tls/${DOMAIN}.key" "${candidate}/secrets/tls/${DOMAIN}.key" ||
                candidate_fail 'TLS 没有恢复到候选'
            if jq -e '.site.mode == "static"' "${EXPECTED_SPEC}" >/dev/null; then
                cmp -- "${SOURCE}/data/static/index.html" "${candidate}/data/static/index.html" ||
                    candidate_fail '静态资源没有恢复到候选'
            fi
        else
            [[ -z "$(find "${candidate}/secrets/tls" -mindepth 1 -print -quit)" ]] ||
                candidate_fail '无 TLS 规格意外恢复了 TLS 输入'
        fi
        if jq -e '.tls.http01 == true' "${EXPECTED_SPEC}" >/dev/null; then
            [[ -d "${candidate}/data/acme-webroot" &&
                -z "$(find "${candidate}/data/acme-webroot" -mindepth 1 -print -quit)" &&
                "$(stat -c '%u:%g:%a' "${candidate}/data/acme-webroot")" == \
                    "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}:750" ]] ||
                candidate_fail 'HTTP-01 挑战根没有以运行权限重建为空目录'
            cmp -- "${candidate}/config/nginx/default.conf" \
                <(dockerGenerateNginxConfig "${EXPECTED_SPEC}" /dev/stdout) ||
                candidate_fail 'HTTP-01 Nginx 没有按规格重新生成'
            jq -e 'any(.services.nginx.volumes[];
              .source == "${PADM_DOCKER_ROOT}/data/acme-webroot" and
              .target == "/srv/padm-acme" and .read_only == true) and
              ([.services.nginx.ports[] | select(contains(":80:"))] ==
                ["0.0.0.0:80:8088/tcp","[::]:80:8088/tcp"])' \
                "${candidate}/compose.json" >/dev/null ||
                candidate_fail 'HTTP-01 挑战根挂载或双栈 80 端口错误'
        else
            [[ ! -e "${candidate}/data/acme-webroot" ]] ||
                candidate_fail '未启用 HTTP-01 却生成了挑战根'
        fi
        [[ ! -e "${TEST_ROOT}/source-compose-executed" ]] ||
            candidate_fail '源 Compose 被执行'
        if [[ -n "${EXPECTED_WIREGUARD_DIR}" ]]; then
            for file in identity.json private.key wg-padm.conf; do
                cmp -- "${EXPECTED_WIREGUARD_DIR}/${file}" \
                    "${candidate}/secrets/net/wireguard/${file}" ||
                    candidate_fail 'WireGuard 身份或配置没有保持原字节'
                [[ "$(stat -c '%u:%g:%a' "${candidate}/secrets/net/wireguard/${file}")" == 0:0:600 ]] ||
                    candidate_fail 'WireGuard 候选文件权限错误'
            done
            [[ "$(stat -c '%u:%g:%a' "${candidate}/secrets/net/wireguard")" == 0:0:700 &&
                ! -e "${candidate}/secrets/control-sync" ]] ||
                candidate_fail 'WireGuard 私密目录权限错误或恢复了自动同步凭据'
            jq -e '.services["net-wireguard"].network_mode == "host" and
              .services["net-wireguard"].command ==
                ["wireguard","/etc/wireguard/wg-padm.conf","wg-padm"]' \
                "${candidate}/compose.json" >/dev/null ||
                candidate_fail 'WireGuard 服务没有由规格重新生成'
        fi
        for file in results.tsv blocked.tsv; do
            cmp -- "${SOURCE}/data/reality-targets/${file}" "${candidate}/data/reality-targets/${file}" ||
                candidate_fail '目标库未按原字节恢复'
            [[ "$(stat -c '%u:%g:%a' "${candidate}/data/reality-targets/${file}")" == 0:0:600 ]] ||
                candidate_fail '目标库文件权限不私密'
        done
        [[ "$(stat -c '%u:%g:%a' "${candidate}/data/reality-targets")" == 0:0:700 ]] ||
            candidate_fail '目标库目录权限不私密'
        if [[ -n "${EXPECTED_RENEWAL_DIR}" ]]; then
            [[ "$(find "${candidate}/secrets/renewal" -type f | wc -l)" == \
                "$(find "${EXPECTED_RENEWAL_DIR}" -type f | wc -l)" &&
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
            jq -e --slurpfile spec "${EXPECTED_SPEC}" '
              .services.xray.ports == ["0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp"] and
              .services.nginx.ports ==
                (if $spec[0].reality_stream.host_website != null then
                  ["0.0.0.0:24443:8443/tcp","[::]:24443:8443/tcp"] else [] end +
                  ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"] +
                  if $spec[0].tls.http01 == true then
                    ["0.0.0.0:80:8088/tcp","[::]:80:8088/tcp"] else [] end) and
              (if $spec[0].reality_stream.host_website != null then
                .services.nginx.extra_hosts == ["host.docker.internal:host-gateway"]
               else true end) and
              any(.services.nginx.volumes[]; .target == "/etc/nginx/stream.d" and .read_only == true)
            ' "${candidate}/compose.json" >/dev/null || candidate_fail '共存 Compose 映射错误'
            jq -e --slurpfile spec "${EXPECTED_SPEC}" '
              [.listeners[] | select(.listener_id == "entry-site" or .listener_id == "entry-reality")] |
              length == 2 and all(.[]; .service == "nginx" and
                if $spec[0].reality_stream.host_website != null and .listener_id == "entry-site" then
                  .public_port == 24443 and .container_port == 8443
                else .public_port == 443 and .container_port == 15443 end)
            ' "${candidate}/deployment.json" >/dev/null || candidate_fail '共存部署有效公网端口错误'
            grep -q '@proxy.example.com:443?' "${candidate}/data/subscription/${TOKEN}" &&
                grep -q '@proxy.example.com:24445?' "${candidate}/data/subscription/${TOKEN}" ||
                candidate_fail '共存订阅没有保留有效公网端口及未绑定入口'
            if jq -e '.reality_stream.host_website != null' "${EXPECTED_SPEC}" >/dev/null; then
                grep -q '@proxy.example.com:24443?' "${candidate}/data/subscription/${TOKEN}" ||
                    candidate_fail '宿主共存改变了独立受管网站入口的订阅端口'
            fi
        fi
        if jq -e '.port_hopping != null' "${EXPECTED_SPEC}" >/dev/null; then
            jq -en --slurpfile expected "${EXPECTED_SPEC}" \
                --slurpfile actual "${candidate}/config/spec.json" \
                --slurpfile deployment "${candidate}/deployment.json" \
                --slurpfile compose "${candidate}/compose.json" '
              $expected[0].port_hopping as $saved |
              $actual[0].port_hopping == $saved and $deployment[0].port_hopping == $saved and
              $compose[0]["x-padm-port-hopping"] == $saved and
              ($compose[0].services | keys) == ["acme","sing-box"]
            ' >/dev/null || candidate_fail '跳跃 tuple 未同步或意外生成了跳跃服务'
            [[ ! -e "${candidate}/data/net/.hopping-supervisor" &&
                ! -e "${candidate}/data/net/port-hopping.state" ]] ||
                candidate_fail '跳跃恢复候选包含运行态'
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
    if [[ "$*" == 'run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c /etc/padm/sing-box/config.json' ]]; then
        printf '%s\n' "${MODE}" >>"${TEST_ROOT}/sing-box-checked"
        [[ "${MODE}" != sing-box-fail ]] || return 1
    fi
    if [[ "$*" == 'run --rm --no-deps net-wireguard preflight wireguard /etc/wireguard/wg-padm.conf wg-padm unowned /run/padm-wireguard-owner' ]]; then
        printf '%s\n' "${MODE}" >>"${TEST_ROOT}/wireguard-checked"
        [[ "${MODE}" != wireguard-foreign ]] || return 1
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
    EXPECTED_ACME_DIR=
    EXPECTED_WIREGUARD_DIR=
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
grep -q '"acme_files": 0' "${LOG}" || fail '无 ACME 预览缺少兼容计数'
grep -q '"wireguard_files": 0' "${LOG}" || fail '无 WireGuard 预览缺少兼容计数'

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

archive_variant acme-normalized
python3 -B - "${PROJECT_ROOT}/docker/tests/acme_recovery.py" "${VARIANT}" "${DOMAIN}" <<'PY'
import importlib.util
import json
import os
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("acme_fixture", sys.argv[1])
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
root, domain = Path(sys.argv[2]), sys.argv[3]
files = {name.replace(fixture.DOMAIN, domain): data.replace(fixture.DOMAIN.encode(), domain.encode())
         for name, data in fixture.fixture().items()}
files[domain + "_ecc/" + domain + ".csr"] = b"discarded-request-marker\n"
files["secrets/renewal/" + domain + "/request.json"] = json.dumps({
    "schema_version": 2, "domain": domain, "email": fixture.EMAIL,
    "provider": "standalone", "enabled": False,
}).encode()
for name, data in files.items():
    path = root / (name if name.startswith("secrets/") else "data/acme/" + name)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(0o600)
for directory in (root / "data/acme", root / "secrets/renewal"):
    for parent, _, _ in os.walk(directory):
        Path(parent).chmod(0o700)
PY
ACME_SOURCE=${VARIANT}
export_variant acme-normalized
prepare_target acme-normalized
EXPECTED_ACME_DIR="${ACME_SOURCE}/data/acme"
EXPECTED_RENEWAL_DIR="${ACME_SOURCE}/secrets/renewal"
run_case acme-normalized "${TEST_ROOT}/acme-normalized.tar" 0
grep -q '"acme_files": 9' "${LOG}" && grep -q '"discarded_files": 1' "${LOG}" ||
    fail 'ACME 预览缺少重建与丢弃计数'
! grep -q 'restore@example.test\|ca.example.test\|private-marker\|discarded-request-marker' "${LOG}" ||
    fail 'ACME 预览泄露账户或材料'
prepare_target acme-material-fail
EXPECTED_ACME_DIR="${ACME_SOURCE}/data/acme"
EXPECTED_RENEWAL_DIR="${ACME_SOURCE}/secrets/renewal"
MODE=acme-material-fail
run_case acme-material-fail "${TEST_ROOT}/acme-normalized.tar" "${PADM_DOCKER_RC_STATE}"
[[ "$(cat "${TEST_ROOT}/acme-validated")" == $'ok\nacme-material-fail' ]] ||
    fail 'ACME 材料失败没有进入恢复专项校验'

VARIANT="${TEST_ROOT}/variant-acme-enabled"
cp -a -- "${ACME_SOURCE}" "${VARIANT}"
jq '.enabled = true' "${VARIANT}/secrets/renewal/${DOMAIN}/request.json" >"${TEST_ROOT}/request.json"
cat -- "${TEST_ROOT}/request.json" >"${VARIANT}/secrets/renewal/${DOMAIN}/request.json"
export_variant acme-enabled
prepare_target acme-enabled
EXPECTED_ACME_DIR="${VARIANT}/data/acme"
EXPECTED_RENEWAL_DIR="${VARIANT}/secrets/renewal"
run_case acme-enabled "${TEST_ROOT}/acme-enabled.tar" 0
grep -q '"acme_files": 9' "${LOG}" && grep -q '"renewal_registrations": 1' "${LOG}" ||
    fail '启用 standalone 预览缺少绑定材料和登记计数'

for enabled in false true; do
    VARIANT="${TEST_ROOT}/variant-acme-webroot-${enabled}"
    cp -a -- "${ACME_SOURCE}" "${VARIANT}"
    python3 -B - "${PROJECT_ROOT}/docker/tests/acme_recovery.py" "${VARIANT}" "${DOMAIN}" "${enabled}" <<'PY'
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location("acme_fixture", sys.argv[1])
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
root, domain = Path(sys.argv[2]), sys.argv[3]
path = root / ("data/acme/" + domain + "_ecc/" + domain + ".conf")
values = fixture.acme.assignments(path.read_bytes(), fixture.acme.DOMAIN_FIELDS)
values["Le_Webroot"] = fixture.acme.WEBROOT
values.pop("Le_HTTPPort")
path.write_bytes(fixture.acme.encoded(values))
path = root / "config/spec.json"
value = json.loads(path.read_bytes())
value["tls"]["http01"] = True
path.write_text(json.dumps(value))
path = root / ("secrets/renewal/" + domain + "/request.json")
value = json.loads(path.read_bytes())
value.update(schema_version=3, provider="webroot", enabled=sys.argv[4] == "true")
path.write_text(json.dumps(value))
PY
    dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
    export_variant "acme-webroot-${enabled}"
    prepare_target "acme-webroot-${enabled}"
    EXPECTED_SPEC="${VARIANT}/config/spec.json"
    EXPECTED_ACME_DIR="${VARIANT}/data/acme"
    EXPECTED_RENEWAL_DIR="${VARIANT}/secrets/renewal"
    run_case "acme-webroot-${enabled}" "${TEST_ROOT}/acme-webroot-${enabled}.tar" 0
    grep -q '"validation": "webroot-http01"' "${LOG}" &&
        grep -q '"acme_files": 9' "${LOG}" || fail 'Webroot 预览未绑定验证方式和重建材料'
done

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
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail '桥接宿主网站夹具无效'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
HOST_SOURCE=${VARIANT}
export_variant stream-host
prepare_target stream-host
EXPECTED_SPEC="${HOST_SOURCE}/config/spec.json"
run_case stream-host "${TEST_ROOT}/stream-host.tar" 0
jq -e '.listeners == [{listener_id:"entry-site",public_port:24443},
  {listener_id:"entry-reality",public_port:443},{listener_id:"entry-other",public_port:24445}]' \
    <(sed -n '/^{/,$p' "${LOG}") >/dev/null || fail '宿主共存预览改变了独立网站或未绑定入口端口'

prepare_target stream-host-nginx-fail
EXPECTED_SPEC="${HOST_SOURCE}/config/spec.json"
MODE=nginx-fail
run_case stream-host-nginx-fail "${TEST_ROOT}/stream-host.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'Nginx 候选配置校验失败' "${LOG}" || fail '宿主共存 Nginx 失败未明确拒绝'

jq 'del(.["x-padm-reality-stream-host-website"])' "${TEST_ROOT}/schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
prepare_target stream-host-missing-capability
run_case stream-host-missing-capability "${TEST_ROOT}/stream-host.tar" "${PADM_DOCKER_RC_MANIFEST}"
grep -q '目标控制 bundle 不支持' "${LOG}" || fail '宿主共存能力缺失未明确拒绝'
cp -- "${TEST_ROOT}/schema.json" "${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"

for variant in host-network loopback host-main; do
    VARIANT="${TEST_ROOT}/variant-stream-${variant}"
    cp -a -- "${HOST_SOURCE}" "${VARIANT}"
    case "${variant}" in
    host-network)
        jq '.reality_stream.host_website |= (.address = "127.0.0.1" | .network_mode = "host")' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/host.json"
        cat -- "${TEST_ROOT}/host.json" >"${VARIANT}/config/spec.json"
        dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail 'host 网络拒绝夹具无效'
        dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json" ;;
    loopback)
        jq '.reality_stream.host_website.address = "127.0.0.1"' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/host.json"
        cat -- "${TEST_ROOT}/host.json" >"${VARIANT}/config/spec.json" ;;
    host-main)
        printf 'untrusted host network config;\n' >"${VARIANT}/config/nginx/stream/host-main"
        chmod 0640 "${VARIANT}/config/nginx/stream/host-main" ;;
    esac
    export_variant "stream-${variant}"
    prepare_target "stream-${variant}"
    run_case "stream-${variant}" "${TEST_ROOT}/stream-${variant}.tar" "${PADM_DOCKER_RC_STATE}"
    if [[ "${variant}" == host-network ]]; then
        grep -q 'host 网络共存' "${LOG}" || fail 'host 网络共存未明确拒绝'
    elif [[ "${variant}" == host-main ]]; then
        grep -q '尚未接入恢复的持久输入' "${LOG}" || fail 'host-main 未处理输入未明确拒绝'
    fi
done

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
EXPECTED_GEO_DIR="${VARIANT}/config/xray/geo"
run_case geo-enabled "${TEST_ROOT}/geo-enabled.tar" 0
grep -q '"geo_files": 3' "${LOG}" || fail '启用 Geo 预览缺少三文件计数'

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
[[ "$(wc -l <"${TEST_ROOT}/geo-probed")" -eq 4 ]] || fail 'Geo 探针次数错误'

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

for protocol in hy2 tuic; do
    archive_variant "hopping-${protocol}" config/spec.json '
      .core.type = "sing-box" | .core.secondary_type = null |
      .core.protocols = [(.core.protocols[0] | del(.websocket) |
        .id = 3 | .core = "sing-box" | .public_port = 35442 |
        .hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:100,
          obfs:null,masquerade:""})] |
      .subscription.enabled = false | del(.site) |
      .port_hopping = {listener_id:"entry-site",range_start:36000,range_end:36002,
        ipv4:"198.18.1.1",ipv6:"2001:db8:1::1"}'
    if [[ "${protocol}" == tuic ]]; then
        jq '.core.protocols[0] |= (del(.hy2) | .id = 31 |
          .tuic = {domain:"ws.example.com",congestion_control:"cubic",
            auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false})' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/hopping.json"
        cat -- "${TEST_ROOT}/hopping.json" >"${VARIANT}/config/spec.json"
    fi
    rm -rf -- "${VARIANT}/config/xray" "${VARIANT}/config/nginx" \
        "${VARIANT}/data/static" "${VARIANT}/data/subscription"
    dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail "${protocol} 跳跃夹具无效"
    dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
    export_variant "hopping-${protocol}"
    prepare_target "hopping-${protocol}"
    EXPECTED_SPEC="${VARIANT}/config/spec.json"
    run_case "hopping-${protocol}" "${TEST_ROOT}/hopping-${protocol}.tar" 0
done
HOPPING_SOURCE=${VARIANT}
prepare_target hopping-sing-box-fail
EXPECTED_SPEC="${HOPPING_SOURCE}/config/spec.json"
MODE=sing-box-fail
run_case hopping-sing-box-fail "${TEST_ROOT}/hopping-tuic.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'sing-box 候选配置校验失败' "${LOG}" || fail 'sing-box 失败未明确拒绝'

for variant in tuple topology unknown-net; do
    VARIANT="${TEST_ROOT}/variant-hopping-${variant}"
    cp -a -- "${HOPPING_SOURCE}" "${VARIANT}"
    if [[ "${variant}" == unknown-net ]]; then
        mkdir -p -- "${VARIANT}/config/net"
        printf 'unhandled-input\n' >"${VARIANT}/config/net/unknown.conf"
        chmod 0640 "${VARIANT}/config/net/unknown.conf"
    else
        filter='.port_hopping.range_start = 0'
        [[ "${variant}" != topology ]] || filter='.core.protocols[0].address_families = ["ipv4"]'
        jq "${filter}" "${VARIANT}/config/spec.json" >"${TEST_ROOT}/hopping.json"
        cat -- "${TEST_ROOT}/hopping.json" >"${VARIANT}/config/spec.json"
        dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
    fi
    export_variant "hopping-${variant}"
    prepare_target "hopping-${variant}"
    run_case "hopping-${variant}" "${TEST_ROOT}/hopping-${variant}.tar" "${PADM_DOCKER_RC_STATE}"
done

# 运行态不在归档白名单，伪造完整清单及摘要也不能将监督或规则状态带入目标。
python3 -B - "${TEST_ROOT}/hopping-tuic.tar" "${TEST_ROOT}/hopping-runtime.tar" <<'PY'
import hashlib
import io
import json
import os
import sys
import tarfile
with tarfile.open(sys.argv[1], "r:") as source:
    records = [(entry, source.extractfile(entry).read() if entry.isfile() else None)
               for entry in source]
manifest = json.loads(next(data for entry, data in records if entry.name == "manifest.json"))
for path, data in (("data/net", None), ("data/net/.hopping-supervisor", None),
                   ("data/net/.hopping-supervisor/pid", b"123\n"),
                   ("data/net/port-hopping.state", b"runtime-state\n")):
    entry = tarfile.TarInfo(path)
    entry.type = tarfile.DIRTYPE if data is None else tarfile.REGTYPE
    entry.mode = 0o700 if data is None else 0o600
    entry.size = len(data) if data is not None else 0
    records.append((entry, data))
    manifest["entries"].append(dict(path=path, type="directory" if data is None else "file",
                                    mode=entry.mode, size=entry.size,
                                    sha256=hashlib.sha256(data).hexdigest() if data is not None else None))
manifest["entries"].sort(key=lambda entry: entry["path"])
with tarfile.open(sys.argv[2], "w", format=tarfile.USTAR_FORMAT) as target:
    for entry, data in records:
        if entry.name == "manifest.json":
            data = json.dumps(manifest, separators=(",", ":")).encode()
            entry.size = len(data)
        target.addfile(entry, io.BytesIO(data) if data is not None else None)
os.chmod(sys.argv[2], 0o600)
PY
prepare_target hopping-runtime
run_case hopping-runtime "${TEST_ROOT}/hopping-runtime.tar" "${PADM_DOCKER_RC_STATE}"

prepare_target corrupt
printf 'not a recovery archive\n' >"${TEST_ROOT}/corrupt.tar"
chmod 0600 "${TEST_ROOT}/corrupt.tar"
run_case corrupt "${TEST_ROOT}/corrupt.tar" "${PADM_DOCKER_RC_STATE}"

# 单 Peer 只恢复规范三件套；被控快照与业务累计使用相同候选断言。
archive_variant wireguard config/spec.json '
  .host_integrations = [{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
    devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'
mkdir -p -- "${VARIANT}/secrets/net"
rmdir -- "${VARIANT}/secrets/net/wireguard"
printf 'dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo=\n' >"${TEST_ROOT}/wg-private"
printf 'hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo=\n' >"${TEST_ROOT}/wg-public"
chmod 0600 "${TEST_ROOT}/wg-private" "${TEST_ROOT}/wg-public"
python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare \
    --directory "${VARIANT}/secrets/net/wireguard" --address 10.77.0.1 --listen-port 51820 \
    --private-key "${TEST_ROOT}/wg-private" --public-key "${TEST_ROOT}/wg-public" >/dev/null
python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" peer \
    --directory "${VARIANT}/secrets/net/wireguard" --peer-address 10.77.0.2 \
    --peer-public-key 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' \
    --endpoint 192.0.2.2:51820 >/dev/null
DOCKER_WIREGUARD_INPUT="${VARIANT}/secrets/net/wireguard" \
    dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
WIREGUARD_SOURCE=${VARIANT}
export_variant wireguard
prepare_target wireguard
EXPECTED_SPEC="${WIREGUARD_SOURCE}/config/spec.json"
EXPECTED_WIREGUARD_DIR="${WIREGUARD_SOURCE}/secrets/net/wireguard"
run_case wireguard "${TEST_ROOT}/wireguard.tar" 0
grep -q '"wireguard_files": 3' "${LOG}" || fail 'WireGuard 预览缺少三文件计数'
! grep -q 'dwdtCnMY\|hSDwCYkw\|192.0.2.2' "${LOG}" || fail 'WireGuard 预览泄露私密配置'

VARIANT="${TEST_ROOT}/variant-wireguard-controlled"
cp -a -- "${WIREGUARD_SOURCE}" "${VARIANT}"
jq --arg managed 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' '
  .accounts += [(.accounts[0] | .id = $managed | .name = "Managed" |
    .uuid = "55555555-5555-4555-8555-555555555555" | .password = "ManagedSecret.123")] |
  .control_sync = {schema_version:1,role:"controlled",
    node_id:"00000002-1111-4111-8111-000000000002",
    controller_id:"00000001-1111-4111-8111-000000000001",
    listener_ids:["entry-site"],last_revision:7,last_digest:("d"*64),
    managed_accounts:[.accounts[-1]],connection:{
      listen:{interface:"wg-padm",address:"10.77.0.2",port:18080},peer_address:"10.77.0.1"}}
' "${VARIANT}/config/spec.json" >"${TEST_ROOT}/controlled.json"
cat -- "${TEST_ROOT}/controlled.json" >"${VARIANT}/config/spec.json"
jq --arg alice "${ALICE}" --arg managed 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' '
  .accounts[$managed] = (.accounts[$alice] | .name = "Managed" | .upload = 101 |
    .download = 103 | .limit_bytes = 1000)
' "${VARIANT}/data/traffic/state.json" >"${TEST_ROOT}/controlled-traffic.json"
cat -- "${TEST_ROOT}/controlled-traffic.json" >"${VARIANT}/data/traffic/state.json"
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail 'WireGuard 被控夹具无效'
DOCKER_WIREGUARD_INPUT="${VARIANT}/secrets/net/wireguard" \
    dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
CONTROLLED_SOURCE=${VARIANT}
export_variant wireguard-controlled
prepare_target wireguard-controlled
EXPECTED_SPEC="${CONTROLLED_SOURCE}/config/spec.json"
EXPECTED_TRAFFIC_FILE="${CONTROLLED_SOURCE}/data/traffic/state.json"
EXPECTED_WIREGUARD_DIR="${CONTROLLED_SOURCE}/secrets/net/wireguard"
run_case wireguard-controlled "${TEST_ROOT}/wireguard-controlled.tar" 0

prepare_target wireguard-foreign
EXPECTED_SPEC="${WIREGUARD_SOURCE}/config/spec.json"
EXPECTED_WIREGUARD_DIR="${WIREGUARD_SOURCE}/secrets/net/wireguard"
MODE=wireguard-foreign
run_case wireguard-foreign "${TEST_ROOT}/wireguard.tar" "${PADM_DOCKER_RC_STATE}"
grep -q 'WireGuard.*前置检查失败' "${LOG}" || fail '外来 WireGuard 接口没有明确拒绝'

prepare_target wireguard-key-mismatch
EXPECTED_SPEC="${WIREGUARD_SOURCE}/config/spec.json"
EXPECTED_WIREGUARD_DIR="${WIREGUARD_SOURCE}/secrets/net/wireguard"
MODE=wireguard-key-mismatch
run_case wireguard-key-mismatch "${TEST_ROOT}/wireguard.tar" "${PADM_DOCKER_RC_STATE}"

for variant in missing-key missing-identity missing-conf legacy-conf address-binding sync-enabled main control-log-enabled fail2ban; do
    VARIANT="${TEST_ROOT}/variant-wireguard-${variant}"
    cp -a -- "${CONTROLLED_SOURCE}" "${VARIANT}"
    case "${variant}" in
    missing-key) rm -f -- "${VARIANT}/secrets/net/wireguard/private.key" ;;
    missing-identity) rm -f -- "${VARIANT}/secrets/net/wireguard/identity.json" ;;
    missing-conf) rm -f -- "${VARIANT}/secrets/net/wireguard/wg-padm.conf" ;;
    legacy-conf) rm -f -- "${VARIANT}/secrets/net/wireguard/"{private.key,identity.json} ;;
    address-binding)
        jq '.control_sync.connection.peer_address = "10.77.0.9"' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/variant.json"
        cat -- "${TEST_ROOT}/variant.json" >"${VARIANT}/config/spec.json" ;;
    sync-enabled)
        mkdir -m 0700 -- "${VARIANT}/secrets/control-sync"
        printf '{}\n' >"${VARIANT}/secrets/control-sync/request.json"
        chmod 0600 "${VARIANT}/secrets/control-sync/request.json" ;;
    main|control-log-enabled)
        jq 'del(.control_sync) | .control = {schema_version:1,role:"main",
          node_id:"00000001-1111-4111-8111-000000000001",
          listen:{interface:"wg-padm",address:"10.77.0.1",port:18080},
          peer:{id:"00000002-1111-4111-8111-000000000002",address:"10.77.0.2",
            enabled:true,expires_at:2000000000,token_sha256:("a"*64)},revision:0,last_digest:null}' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/variant.json"
        cat -- "${TEST_ROOT}/variant.json" >"${VARIANT}/config/spec.json"
        if [[ "${variant}" == control-log-enabled ]]; then
            mkdir -m 0700 -- "${VARIANT}/data/control-log"
            printf '{"schema_version":1,"enabled":true}\n' >"${VARIANT}/data/control-log/schedule.json"
            chmod 0600 "${VARIANT}/data/control-log/schedule.json"
        fi ;;
    fail2ban)
        jq '.host_integrations += [{type:"fail2ban",profile:"net-fail2ban",
          firewall_rules:["DOCKER-USER"],devices:[],schedules:[],
          settings:{log_file:"access.log",ports:[24443],max_retry:3,find_time:600,ban_time:600}}]' \
            "${VARIANT}/config/spec.json" >"${TEST_ROOT}/variant.json"
        cat -- "${TEST_ROOT}/variant.json" >"${VARIANT}/config/spec.json" ;;
    esac
    if [[ "${variant}" != missing-conf ]]; then
        DOCKER_WIREGUARD_INPUT="${VARIANT}/secrets/net/wireguard" \
            dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
    fi
    export_variant "wireguard-${variant}"
    prepare_target "wireguard-${variant}"
    run_case "wireguard-${variant}" "${TEST_ROOT}/wireguard-${variant}.tar" "${PADM_DOCKER_RC_STATE}"
done

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
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail 'HTTP-01 夹具无效'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
printf 'untrusted archived HTTP-01 config;\n' >"${VARIANT}/config/nginx/default.conf"
HTTP01_SOURCE=${VARIANT}
export_variant http01
prepare_target http01
EXPECTED_SPEC="${VARIANT}/config/spec.json"
run_case http01 "${TEST_ROOT}/http01.tar" 0

VARIANT="${TEST_ROOT}/variant-http01-stream"
cp -a -- "${STREAM_SOURCE}" "${VARIANT}"
jq '.tls.http01 = true' "${STREAM_SOURCE}/config/spec.json" >"${VARIANT}/config/spec.json"
dockerConfigureSpecValidate "${VARIANT}/config/spec.json" || fail 'HTTP-01 共存夹具无效'
dockerGenerateDeployment "${VARIANT}/config/spec.json" "${VARIANT}/deployment.json"
export_variant http01-stream
prepare_target http01-stream
EXPECTED_SPEC="${VARIANT}/config/spec.json"
run_case http01-stream "${TEST_ROOT}/http01-stream.tar" 0

for variant in acme-input renewal-enabled; do
    VARIANT="${TEST_ROOT}/variant-http01-${variant}"
    cp -a -- "${HTTP01_SOURCE}" "${VARIANT}"
    if [[ "${variant}" == acme-input ]]; then
        mkdir -p -- "${VARIANT}/data/acme"
        chmod 0700 "${VARIANT}/data/acme"
        printf 'ACCOUNT_CONF=must-not-execute\n' >"${VARIANT}/data/acme/account.conf"
        chmod 0600 "${VARIANT}/data/acme/account.conf"
    else
        cp -a -- "${RENEWAL_SOURCE}/secrets/renewal" "${VARIANT}/secrets/"
        jq '.enabled = true' "${VARIANT}/secrets/renewal/webroot.example.com/request.json" \
            >"${TEST_ROOT}/request.json"
        cat -- "${TEST_ROOT}/request.json" >"${VARIANT}/secrets/renewal/webroot.example.com/request.json"
    fi
    export_variant "http01-${variant}"
    prepare_target "http01-${variant}"
    run_case "http01-${variant}" "${TEST_ROOT}/http01-${variant}.tar" "${PADM_DOCKER_RC_STATE}"
    if [[ "${variant}" == acme-input ]]; then
        grep -q 'ACME 执行配置' "${LOG}" || fail 'HTTP-01 恢复接受了实际 ACME 输入'
    else
        grep -q 'enabled=false' "${LOG}" || fail 'HTTP-01 恢复接受了启用续期登记'
    fi
done

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
[[ "$(wc -l <"${TEST_ROOT}/candidate-checked")" -eq 29 ]] ||
    fail '正常、验证失败或中断场景没有经过真实候选校验'
grep -q '^nginx-fail$' "${TEST_ROOT}/nginx-checked" || fail '未执行 Nginx 失败校验'
[[ "$(wc -l <"${TEST_ROOT}/sing-box-checked")" -eq 4 ]] &&
    grep -q '^sing-box-fail$' "${TEST_ROOT}/sing-box-checked" || fail 'sing-box 候选检查次数错误'
printf 'docker-recovery-preview-ok: %s cases\n' "${CASES}"
