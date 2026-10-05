#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    printf 'docker-tls-regression-skip: Linux root is required\n'
    exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'docker-tls-regression-fail: run as root\n' >&2; exit 1; }
for tool in jq python3 openssl setpriv stat chown chmod; do
    command -v "${tool}" >/dev/null || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-tls.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=1 PADM_DOCKER_HEALTH_TIMEOUT=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bundle.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/manifest.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/traffic.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

DOMAIN=example.com
MODE=ok
OPS_IMAGE="ghcr.io/example/padm-ops:3.2.0@sha256:$(printf 'a%.0s' {1..64})"
CERT_FILE=${TEST_ROOT}/new.crt
KEY_FILE=${TEST_ROOT}/new.key
CREDENTIALS=${TEST_ROOT}/dns.env
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN}" -keyout "${KEY_FILE}" -out "${CERT_FILE}" >/dev/null 2>&1
openssl req -x509 -new -key "${KEY_FILE}" -days 2 -set_serial 1 -subj "/CN=${DOMAIN}" \
    -addext "subjectAltName=DNS:${DOMAIN}" -out "${TEST_ROOT}/old.crt" >/dev/null 2>&1
printf 'DNS_API_TOKEN=private-dns-token\n' >"${CREDENTIALS}"
chmod 0600 "${KEY_FILE}" "${CREDENTIALS}"

fail() { printf 'docker-tls-regression-fail: %s\n' "$*" >&2; exit 1; }
reject() { if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi; }
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/mode")" == docker ]]; }
dockerSetupCleanup() { :; }
dockerEntryCleanup() { :; }
cp() {
    command cp "$@" || return $?
    if [[ "${MODE}" == term-copy &&
        "${*: -1}" == "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/.${DOMAIN}.crt.${BASHPID}" ]]; then
        kill -TERM "${BASHPID}"
    fi
}

# 保留实际候选校验，Docker 只映射 bind 路径到本测试目录。
docker() {
    local candidate='' script='' previous='' argument last=''
    [[ "$1" == run ]] || fail '意外的 Docker 命令'
    printf 'validate\n' >>"${TEST_ROOT}/ops.log"
    for argument in "$@"; do
        if [[ "${previous}" == --volume && "${argument}" == *:/candidate:ro ]]; then
            candidate=${argument%:/candidate:ro}
        elif [[ "${previous}" == -c ]]; then
            script=${argument}
        fi
        previous=${argument}
        last=${argument}
    done
    [[ -n "${candidate}" ]] || fail '证书校验缺少只读 bind'
    if [[ -n "${script}" ]]; then
        [[ "${MODE}" != validity-fail ]] || return 1
        python3 -c "${script}" "${candidate}/${last#/candidate/}"
    else
        [[ "${MODE}" != match-fail ]] || return 1
        bash -c '
            trap '\''rm -f -- "/tmp/padm-cert-public.$$" "/tmp/padm-key-public.$$"'\'' EXIT
            source "$1" tls-check "$2" "$3" "$4"
        ' _ "${PROJECT_ROOT}/docker/images/ops/entrypoint.sh" \
            "${candidate}/${DOMAIN}.crt" "${candidate}/${DOMAIN}.key" "${last}"
    fi
}

dockerAcmeRun() {
    local image=$1 credentials=$2 account=$3 output=$4 action=$5
    [[ "${image}" == "${OPS_IMAGE}" && "${credentials}" == "${CREDENTIALS}" &&
        "${account}" == "${PADM_DOCKER_INSTALL_DIR}/.tls."*/acme &&
        "${output}" == "${account%/acme}" ]] || fail 'ACME 未隔离候选账户'
    [[ "$(stat -c '%u %g' "${account}")" == '10001 10001' ]] || fail '候选账户不能由容器读取'
    [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")" == history ]] || fail 'ACME 修改了累计流量'
    printf '%s\n' "${action}" >>"${TEST_ROOT}/acme.log"
    (
        cd "${account}"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c '
            printf "new-account-%s\n" "$1" >account.conf
            mkdir -p "$2"
            printf "new-domain-state\n" >"$2/domain.conf"
        ' _ "${action}" "${DOMAIN}"
    ) || fail '容器 UID 不能更新候选账户'
    if [[ ( "${MODE}" == issue-fail && "${action}" == --issue ) ||
        ( "${MODE}" == renew-fail && "${action}" == --renew ) ||
        ( "${MODE}" == export-fail && "${action}" == --install-cert ) ]]; then return 1; fi
    if [[ "${MODE}" == term-issue && "${action}" == --issue ]]; then kill -TERM "${BASHPID}"; fi
    if [[ "${action}" == --install-cert ]]; then
        cp -- "${CERT_FILE}" "${output}/${DOMAIN}.crt"
        cp -- "${KEY_FILE}" "${output}/${DOMAIN}.key"
    fi
}

dockerComposeRun() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
    [[ -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'TLS 重载未持有部署锁'
    if [[ ! -e "${TEST_ROOT}/failed-once" ]]; then
        if [[ ( "${MODE}" == nginx-test-fail && "$*" == 'exec -T nginx nginx -t' ) ||
            ( "${MODE}" == reload-fail && "$*" == 'exec -T nginx nginx -s reload' ) ||
            ( "${MODE}" == health-fail && "$1" == up ) ]]; then
            : >"${TEST_ROOT}/failed-once"
            return 1
        fi
        if [[ "${MODE}" == term-reload && "$*" == 'exec -T nginx nginx -s reload' ]]; then
            : >"${TEST_ROOT}/failed-once"
            kill -TERM "${BASHPID}"
        fi
    fi
}

newState() {
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/$1"
    dockerInitializeStateRoot
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com" \
        "${PADM_DOCKER_INSTALL_DIR}/data/traffic"
    cp -- "${TEST_ROOT}/old.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
    cp -- "${KEY_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
    printf 'other-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt"
    printf 'other-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key"
    dockerTlsRuntimePermissions "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    printf 'old-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
    printf 'other-domain\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com/domain.conf"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type d -exec chmod 0750 {} +
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -exec chmod 0600 {} +
    printf 'history\n' >"${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json"
    jq -n --arg ops "${OPS_IMAGE}" '
      def ref($name): $ops | sub("padm-ops"; "padm-" + $name);
      {schema_version:1,release:{version:"3.2.0",manifest_sha256:("a"*64),signature_identity:"test"},
       core:{type:"xray",protocols:[{id:21,server:"proxy.example.com",public_port:24443,
         address_families:["ipv4"],name:"main",uuid:"11111111-1111-4111-8111-111111111111",
         websocket:{domain:"example.com",path:"abcdefgh"}}]},
       tls:{domain:"example.com"},subscription:{enabled:false,token:("a"*32)},
       images:{xray:ref("xray"),"sing-box":ref("sing-box"),nginx:ref("nginx"),ops:$ops,net:ref("net")},
       host_integrations:[]}
    ' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -n --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      $spec[0] as $s |
      {schema_version:1,mode:"docker",padm_version:$s.release.version,bundle_version:"fixture",
       manifest:{sha256:$s.release.manifest_sha256,signature_identity:$s.release.signature_identity},
       compose:{project:"padm-docker",profiles:["core-xray","nginx"]},core:{type:"xray",protocol_ids:[21]},
       listeners:[{service:"nginx",public_port:24443,container_port:8443,transport:"tcp",address_families:["ipv4"]}],
       images:($s.images|with_entries(.value={index_digest:(.value|split("@")|last)})),
       formats:{compose:1,config:1,data:1},previous_manifest_sha256:null,host_integrations:[]}
    ' >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    : >"${PADM_DOCKER_INSTALL_DIR}/images.env"
    dockerGenerateImagesEnv "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/images.env" "${PADM_DOCKER_INSTALL_DIR}"
    dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json" || fail '部署夹具格式错误'
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" || fail '规格夹具不一致'
    MODE=ok
    rm -f -- "${TEST_ROOT}/failed-once"
    : >"${TEST_ROOT}/compose.log"
    : >"${TEST_ROOT}/acme.log"
    : >"${TEST_ROOT}/ops.log"
}

materials() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find secrets/tls data/acme -type f -print0 | sort -z | xargs -0 -r sha256sum
)

assertClean() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '部署锁未释放'
    [[ -z "$(find "${root}" -maxdepth 1 -name '.tls.*' -print -quit)" ]] || fail 'TLS 候选未清理'
    [[ -z "$(find "${root}/secrets/tls" -maxdepth 1 -name '.*' -type f -print -quit)" ]] || fail '临时证书未清理'
    [[ "$(<"${root}/data/traffic/state.json")" == history ]] || fail 'TLS 修改了历史累计'
}

runControl() {
    local expected=$1 status
    shift
    if (dockerMain "$@") >"${TEST_ROOT}/control.log" 2>&1; then status=0; else status=$?; fi
    if [[ "${status}" != "${expected}" ]]; then cat "${TEST_ROOT}/control.log" >&2; fail "$*: 预期 ${expected}，实际 ${status}"; fi
    assertClean
}

assertPermissions() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    [[ "$(stat -c '%a %u %g' "${root}/secrets/tls/${DOMAIN}.key")" == '600 10001 10001' &&
        "$(stat -c '%a %u %g' "${root}/secrets/tls/${DOMAIN}.crt")" == '640 0 10001' ]] || fail '证书运行权限不正确'
    (
        cd "${root}/secrets/tls"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r example.com.key && test -r example.com.crt'
    ) || fail '容器 UID 不能读取证书'
    (
        cd "${root}/data/acme"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r account.conf && test -w account.conf && test -w .'
    ) || fail '容器 UID 不能使用 ACME 账户'
}

for ACTION in issue renew; do
    newState "${ACTION}-success"
    runControl 0 acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    cmp -s "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" || fail '申请或续期未安装新证书'
    grep -qxF 'new-account---install-cert' "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" || fail '候选账户未提交'
    [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/acme/other.example.com/domain.conf")" == other-domain &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt")" == other-certificate &&
        "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key")" == other-key ]] || fail '修改了其它域名'
    [[ "$(head -n 2 "${TEST_ROOT}/compose.log")" == $'exec -T nginx nginx -t\nexec -T nginx nginx -s reload' ]] ||
        fail '重载未先校验 Nginx'
    assertPermissions
    before=$(materials)
    : >"${TEST_ROOT}/compose.log"
    runControl 0 tls validate --domain "${DOMAIN}"
    [[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/compose.log" ]] || fail '证书校验写入或重启了部署'
done

for MODE_CASE in issue-fail renew-fail export-fail validity-fail match-fail nginx-test-fail reload-fail health-fail \
    term-issue term-copy term-reload; do
    newState "${MODE_CASE}"
    before=$(materials)
    MODE=${MODE_CASE}
    ACTION=issue
    [[ "${MODE}" != renew-fail ]] || ACTION=renew
    EXPECTED=15
    [[ "${MODE}" != term-* ]] || EXPECTED=143
    runControl "${EXPECTED}" acme "${ACTION}" --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: 失败或中断未恢复证书与账户"
    assertPermissions
done

newState import-success
accountBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -print0 | sort -z | xargs -0 sha256sum)
runControl 0 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ "$(find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -print0 | sort -z | xargs -0 sha256sum)" == "${accountBefore}" &&
    ! -s "${TEST_ROOT}/acme.log" ]] || fail '证书导入修改了 ACME 账户'
assertPermissions
before=$(materials)
MODE=match-fail
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ "$(materials)" == "${before}" ]] || fail '无效导入修改了部署'
MODE=ok
runControl 15 tls validate --domain wrong.example.com
[[ "$(materials)" == "${before}" ]] || fail '证书域名校验失败修改了部署'
MODE=match-fail
runControl 15 tls validate --domain "${DOMAIN}"
[[ "$(materials)" == "${before}" ]] || fail '证书校验失败修改了部署'
MODE=ok

# 已配置部署不允许改写镜像文件或显式换用其它 ops 镜像。
newState image-validation
before=$(materials)
OTHER_IMAGE="ghcr.io/example/padm-ops:3.2.0@sha256:$(printf 'b%.0s' {1..64})"
printf 'PADM_OPS_IMAGE=%s\n' "${OTHER_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls validate --domain "${DOMAIN}"
printf 'PADM_OPS_IMAGE=%s\nPADM_OPS_IMAGE=%s\n' "${OPS_IMAGE}" "${OPS_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls validate --domain "${DOMAIN}"
printf 'PADM_OPS_IMAGE=%s\n' "${OPS_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}" --ops-image "${OTHER_IMAGE}"
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test \
    --credentials "${CREDENTIALS}" --ops-image "${OTHER_IMAGE}"
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/ops.log" && ! -s "${TEST_ROOT}/acme.log" ]] ||
    fail '镜像门禁失败前运行了工具或修改了部署'
rm -- "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 0 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
newState spec-validation
before=$(materials)
jq '.images.ops |= sub("sha256:a"; "sha256:b")' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/invalid-spec.json"
cp -- "${TEST_ROOT}/invalid-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 15 tls validate --domain "${DOMAIN}"
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/ops.log" ]] || fail '规格不一致时执行了证书工具'

# 校验复用真实 openssl，覆盖错域名、错私钥与损坏证书，不能只相信模拟退出码。
newState invalid-materials
dockerCreateTlsCandidate
candidate=${DOCKER_TLS_CANDIDATE}
cp -- "${CERT_FILE}" "${candidate}/${DOMAIN}.crt"
cp -- "${KEY_FILE}" "${candidate}/${DOMAIN}.key"
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" wrong.example.com
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "${candidate}/${DOMAIN}.key" >/dev/null 2>&1
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" "${DOMAIN}"
printf 'invalid-certificate\n' >"${candidate}/${DOMAIN}.crt"
reject dockerTlsValidateCandidate "${OPS_IMAGE}" "${candidate}" "${DOMAIN}"
dockerCleanupTlsCandidate
assertClean

# 新域名与不存在的 ACME 账户同样需要在重载失败时恢复缺失状态。
newState absent-state
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
rm -rf -- "${PADM_DOCKER_INSTALL_DIR}/data/acme"
MODE=health-fail
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/acme" &&
    ! -e "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt" &&
    ! -e "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" ]] || fail '失败事务没有恢复缺失状态'

# 备份损坏与路径跳转必须在任何恢复写入前拒绝。
newState backup-validation
dockerBackupTlsFiles "${DOMAIN}"
BACKUP=${DOCKER_TLS_BACKUP}
DOCKER_TLS_SWITCHED=1
cp -- "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
before=$(materials)
printf 'unexpected\n' >>"${BACKUP}/present"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '坏备份导致部分恢复'
printf 'crt\nkey\n' >"${BACKUP}/present"
rm -- "${BACKUP}/${DOMAIN}.key"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '缺失私钥备份导致部分恢复'
cp -- "${KEY_FILE}" "${BACKUP}/${DOMAIN}.key"
mv "${BACKUP}/${DOMAIN}.crt" "${BACKUP}/${DOMAIN}.crt.real"
ln -s "${DOMAIN}.crt.real" "${BACKUP}/${DOMAIN}.crt"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '备份符号链接导致恢复写入'
DOCKER_TLS_SWITCHED=0

newState account-backup-validation
dockerCreateTlsCandidate
mkdir "${DOCKER_TLS_CANDIDATE}/acme"
cp -a -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/." "${DOCKER_TLS_CANDIDATE}/acme/"
dockerBackupTlsFiles "${DOMAIN}" "${DOCKER_TLS_CANDIDATE}"
BACKUP=${DOCKER_TLS_BACKUP}
DOCKER_TLS_SWITCHED=1
cp -- "${CERT_FILE}" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.crt"
before=$(materials)
rm -rf -- "${BACKUP}/acme"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '缺失 ACME 备份导致部分恢复'
printf 'invalid\n' >"${BACKUP}/acme.changed"
reject dockerRestoreTlsFiles
[[ "$(materials)" == "${before}" ]] || fail '无效 ACME 状态标记导致部分恢复'
DOCKER_TLS_SWITCHED=0
dockerCleanupTlsCandidate
assertClean

newState symlink-validation
dockerCreateTlsCandidate
cp -- "${CERT_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.crt"
cp -- "${KEY_FILE}" "${DOCKER_TLS_CANDIDATE}/${DOMAIN}.key"
printf 'outside-key\n' >"${TEST_ROOT}/outside-key"
tempKey="${PADM_DOCKER_INSTALL_DIR}/secrets/tls/.${DOMAIN}.key.${BASHPID}"
ln -s "${TEST_ROOT}/outside-key" "${tempKey}"
before=$(materials)
reject dockerCommitTlsCandidate "${DOCKER_TLS_CANDIDATE}" "${DOMAIN}"
[[ "$(materials)" == "${before}" && "$(<"${TEST_ROOT}/outside-key")" == outside-key &&
    "${DOCKER_TLS_SWITCHED}" == 0 && -L "${tempKey}" ]] || fail '私钥临时链接导致部分提交或外部写入'
rm -- "${tempKey}"
dockerCleanupTlsCandidate
assertClean
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme" "${PADM_DOCKER_INSTALL_DIR}/data/acme.real"
ln -s acme.real "${PADM_DOCKER_INSTALL_DIR}/data/acme"
runControl 15 acme issue --domain "${DOMAIN}" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
[[ ! -s "${TEST_ROOT}/acme.log" ]] || fail 'ACME 接受了账户符号链接'
rm -- "${PADM_DOCKER_INSTALL_DIR}/data/acme"
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme.real" "${PADM_DOCKER_INSTALL_DIR}/data/acme"
mv "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key.real"
ln -s "${DOMAIN}.key.real" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key"
runControl 15 tls validate --domain "${DOMAIN}"
runControl 15 tls install --domain "${DOMAIN}" --cert "${CERT_FILE}" --key "${KEY_FILE}"
[[ -L "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${DOMAIN}.key" ]] || fail '覆盖了私钥符号链接'
printf 'docker-tls-regression-ok\n'
