#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    printf 'docker-renewal-regression-skip: Linux root is required\n'
    exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'docker-renewal-regression-fail: run as root\n' >&2; exit 1; }
for tool in jq stat chown chmod; do
    command -v "${tool}" >/dev/null || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-renewal.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0 PADM_DOCKER_LOCK_TIMEOUT=0 PADM_DOCKER_HEALTH_TIMEOUT=1
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
source "${PROJECT_ROOT}/docker/lib/renewal.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

ACME_RUN_IMPLEMENTATION=$(declare -f dockerAcmeRun)
OPS_IMAGE="ghcr.io/example/padm-ops:3.2.0@sha256:$(printf 'a%.0s' {1..64})"
CREDENTIALS=${TEST_ROOT}/dns.env
SECRET=private-renewal-token
printf 'DNS_API_TOKEN=%s\n' "${SECRET}" >"${CREDENTIALS}"
chmod 0600 "${CREDENTIALS}"
BACKEND=systemd
MODE=ok
FRAGMENT_OVERRIDE=
CHALLENGE_PENDING=0

fail() {
    printf 'docker-renewal-regression-fail: %s\n' "$*" >&2
    [[ ! -f "${TEST_ROOT}/control.log" ]] || cat "${TEST_ROOT}/control.log" >&2
    exit 1
}
reject() { if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi; }
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { [[ "$(<"${PADM_DOCKER_INSTALL_DIR}/mode")" == docker ]]; }
dockerSetupCleanup() { :; }
dockerEntryCleanup() { :; }

systemctl() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/schedule.log"
    if [[ "$1" == show-environment ]]; then [[ "${BACKEND}" == systemd ]]; return $?; fi
    if [[ "$1" == show ]]; then printf '%s\n' "${FRAGMENT_OVERRIDE}"; return 0; fi
    if [[ "${MODE}" == schedule-fail && ( "$1" == enable || "$1" == disable ) &&
        ! -e "${TEST_ROOT}/schedule-failed" ]]; then
        : >"${TEST_ROOT}/schedule-failed"
        return 1
    fi
    case "$1" in
    enable)
        : >"${TEST_ROOT}/timer-enabled"
        [[ "$*" != *--now* ]] || : >"${TEST_ROOT}/timer-active"
        ;;
    start) : >"${TEST_ROOT}/timer-active" ;;
    stop) [[ "$*" != *padm-docker-renewal.timer* ]] || rm -f -- "${TEST_ROOT}/timer-active" ;;
    disable)
        rm -f -- "${TEST_ROOT}/timer-enabled"
        [[ "$*" != *--now* ]] || rm -f -- "${TEST_ROOT}/timer-active"
        ;;
    is-enabled) [[ -f "${TEST_ROOT}/timer-enabled" ]]; return $? ;;
    is-active) [[ -f "${TEST_ROOT}/timer-active" ]]; return $? ;;
    *) ;;
    esac
    if [[ ( "${MODE}" == schedule-term || "${MODE}" == schedule-parent-term ) &&
        ( "$1" == enable || "$1" == disable ) && ! -e "${TEST_ROOT}/schedule-failed" ]]; then
        : >"${TEST_ROOT}/schedule-failed"
        if [[ "${MODE}" == schedule-parent-term ]]; then kill -TERM "${CONTROL_PID}"; return 1; fi
        kill -TERM "${BASHPID}"
    fi
}

crontab() {
    if [[ "$1" == -l ]]; then cat "${TEST_ROOT}/crontab"; return 0; fi
    [[ "$1" == - ]] || fail '意外的 crontab 参数'
    if [[ "${MODE}" == schedule-fail && ! -e "${TEST_ROOT}/schedule-failed" ]]; then
        : >"${TEST_ROOT}/schedule-failed"
        return 1
    fi
    cat >"${TEST_ROOT}/crontab"
    if [[ ( "${MODE}" == schedule-term || "${MODE}" == schedule-parent-term ) &&
        ! -e "${TEST_ROOT}/schedule-failed" ]]; then
        : >"${TEST_ROOT}/schedule-failed"
        if [[ "${MODE}" == schedule-parent-term ]]; then kill -TERM "${CONTROL_PID}"; return 1; fi
        kill -TERM "${BASHPID}"
    fi
}
pgrep() { [[ "${BACKEND}" == cron && "$*" == '-x cron' ]]; }
install() {
    if [[ "${MODE}" == unit-install-fail && "${*: -1}" == */padm-docker-renewal.timer &&
        ! -e "${TEST_ROOT}/schedule-failed" ]]; then
        : >"${TEST_ROOT}/schedule-failed"
        return 1
    fi
    command install "$@"
}

# 续期调度复用真实 ACME 提交事务；证书密码学校验由独立 TLS 回归覆盖。
dockerTlsValidateCandidate() {
    local image=$1 candidate=$2 domain=$3
    printf '%s\n' "${domain}" >>"${TEST_ROOT}/validate.log"
    [[ "${image}" == "${OPS_IMAGE}" && -s "${candidate}/${domain}.crt" &&
        -s "${candidate}/${domain}.key" && "${MODE}" != validate-fail &&
        "${CHALLENGE_PENDING}" == 0 ]]
}

# 端口占用与服务恢复由 TLS 专项覆盖，这里只核对续期调用与恢复顺序。
dockerAcmeRenewProbe() { return 0; }
dockerAcmeRuntimeSnapshot() { DOCKER_ACME_RUNNING='["xray"]'; }
dockerAcmeWebrootDeploymentCheck() {
    jq -e --arg domain "$1" '.tls.http01 == true and .tls.domain == $domain' \
        "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null
}
dockerAcmeChallengePrepare() {
    [[ "$1" == standalone || "$1" == webroot ]] || return 0
    [[ "$2" == "${PADM_DOCKER_INSTALL_DIR}/.tls."* && -d "$2/acme" &&
        -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'HTTP 续期没有候选账户或部署锁'
    if [[ "$1" == webroot ]]; then
        DOCKER_ACME_WEBROOT="${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active"
        mkdir -p -- "${DOCKER_ACME_WEBROOT}"
        printf 'webroot-prepare\n' >>"${TEST_ROOT}/challenge.log"
        return 0
    fi
    CHALLENGE_PENDING=1
    printf 'prepare\n' >>"${TEST_ROOT}/challenge.log"
}
dockerAcmeChallengeRestore() {
    if [[ -n "${DOCKER_ACME_WEBROOT:-}" ]]; then
        [[ "${MODE}" != webroot-restore-fail ]] || return 1
        rmdir -- "${DOCKER_ACME_WEBROOT}" || return 1
        DOCKER_ACME_WEBROOT=
        printf 'webroot-restore\n' >>"${TEST_ROOT}/challenge.log"
        return 0
    fi
    [[ "${CHALLENGE_PENDING}" == 1 ]] || return 0
    CHALLENGE_PENDING=0
    printf 'restore\n' >>"${TEST_ROOT}/challenge.log"
}

dockerAcmeRun() {
    local image=$1 credentials=$2 account=$3 output=$4 action=$5 domain='' previous='' argument
    [[ "${image}" == "${OPS_IMAGE}" && ( -f "${credentials}" || -z "${credentials}" ) &&
        "${account}" == "${PADM_DOCKER_INSTALL_DIR}/.tls."*/acme ]] || fail '续期没有使用候选账户与私有凭据'
    if [[ -z "${credentials}" && "${action}" == --renew ]]; then
        if [[ -n "${DOCKER_ACME_WEBROOT:-}" ]]; then
            [[ "${CHALLENGE_PENDING}" == 0 && " ${*:5} " != *' --httpport '* &&
                " ${*:5} " != *' --standalone '* ]] || fail 'webroot 续期暂停了服务或混入 standalone 参数'
        else
            [[ "${CHALLENGE_PENDING}" == 1 && " ${*:5} " == *' --httpport 8080 '* ]] ||
                fail 'HTTP 续期没有准备端口或使用非 root 验证端口'
        fi
    fi
    [[ -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '续期未持有部署锁'
    for argument in "${@:5}"; do
        [[ "${previous}" != -d ]] || domain=${argument}
        previous=${argument}
    done
    [[ -n "${domain}" ]] || fail '续期没有明确域名'
    printf '%s:%s\n' "${domain}" "${action}" >>"${TEST_ROOT}/acme.log"
    printf '%s\n' "${*:5}" >>"${TEST_ROOT}/acme.args"
    printf 'candidate-%s\n' "${domain}" >"${account}/account.conf"
    case "${MODE}:${domain}:${action}" in
    skip:*:--renew) return 2 ;;
    first-domain-fail:a.example.com:--renew) return 1 ;;
    renew-fail:*:--renew|export-fail:*:--install-cert) return 1 ;;
    term:*:--renew) kill -TERM "${BASHPID}" ;;
    esac
    if [[ "${action}" == --install-cert ]]; then
        printf 'new-cert-%s\n' "${domain}" >"${output}/${domain}.crt"
        printf 'new-key-%s\n' "${domain}" >"${output}/${domain}.key"
    fi
}

newState() {
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/$1"
    export PADM_DOCKER_SYSTEMD_DIR="${PADM_DOCKER_INSTALL_DIR}/systemd"
    dockerInitializeStateRoot
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme" \
        "${PADM_DOCKER_SYSTEMD_DIR}"
    for domain in a.example.com b.example.com; do
        printf 'old-cert-%s\n' "${domain}" >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${domain}.crt"
        printf 'old-key-%s\n' "${domain}" >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${domain}.key"
        mkdir -- "${PADM_DOCKER_INSTALL_DIR}/data/acme/${domain}"
        printf "Le_Domain='%s'\nLe_Webroot='dns_test'\n" "${domain}" \
            >"${PADM_DOCKER_INSTALL_DIR}/data/acme/${domain}/${domain}.conf"
    done
    dockerTlsRuntimePermissions "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    printf 'old-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type d -exec chmod 0750 {} +
    find "${PADM_DOCKER_INSTALL_DIR}/data/acme" -type f -exec chmod 0600 {} +
    printf 'PADM_OPS_IMAGE=%s\n' "${OPS_IMAGE}" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
    printf '# unrelated job\n' >"${TEST_ROOT}/crontab"
    rm -f -- "${TEST_ROOT}/schedule-failed" "${TEST_ROOT}/timer-enabled" "${TEST_ROOT}/timer-active"
    : >"${TEST_ROOT}/schedule.log"
    : >"${TEST_ROOT}/acme.log"
    : >"${TEST_ROOT}/acme.args"
    : >"${TEST_ROOT}/validate.log"
    : >"${TEST_ROOT}/challenge.log"
    MODE=ok
    FRAGMENT_OVERRIDE=
    CHALLENGE_PENDING=0
    DOCKER_ACME_WEBROOT=
}

registry() { printf '%s/secrets/renewal\n' "${PADM_DOCKER_INSTALL_DIR}"; }
materials() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find secrets/tls data/acme -type f -print0 | sort -z | xargs -0 -r sha256sum
)
registryAndJobs() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find secrets/renewal systemd -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum
    cat "${TEST_ROOT}/crontab"
    [[ ! -f "${TEST_ROOT}/timer-enabled" ]] || printf 'timer-enabled\n'
    [[ ! -f "${TEST_ROOT}/timer-active" ]] || printf 'timer-active\n'
)
assertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '续期结束后锁未释放'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.tls.*' -print -quit)" ]] || fail '续期候选未清理'
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" ]] || fail 'webroot 挑战未清理'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}/locks" -maxdepth 1 \( -name 'renewal.*' -o -name 'renewal-schedule.*' \) -print -quit)" ]] ||
        fail '续期输入或调度事务未清理'
}
runControl() {
    local expected=$1 status
    shift
    if (
        CONTROL_PID=${BASHPID}
        if [[ "${MODE}" == commit-term ]]; then
            dockerRenewalScheduleCommit() { kill -TERM "${BASHPID}"; }
        fi
        dockerMain "$@"
    ) >"${TEST_ROOT}/control.log" 2>&1; then status=0; else status=$?; fi
    if [[ "${expected}" == failure ]]; then
        [[ "${status}" != 0 ]] || fail "应失败: $*"
    elif [[ "${status}" != "${expected}" ]]; then fail "$*: 预期 ${expected}，实际 ${status}"; fi
    if grep -qF "${SECRET}" "${TEST_ROOT}/control.log"; then fail '输出暴露了凭据'; fi
    assertClean
}
enableDomain() {
    runControl 0 acme schedule enable --domain "$1" --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
}

for BACKEND in systemd cron; do
    newState "${BACKEND}-registry"
    enableDomain a.example.com
    enableDomain a.example.com
    enableDomain b.example.com
    dockerRenewalRegistryValidate "$(registry)"
    dockerRenewalEnabled "$(registry)"
    [[ "$(stat -c '%a %u %g' "$(registry)")" == '700 0 0' ]] || fail '续期根目录不是 root 私有'
    for domain in a.example.com b.example.com; do
        [[ "$(stat -c '%a %u %g' "$(registry)/${domain}")" == '700 0 0' &&
            "$(stat -c '%a %u %g' "$(registry)/${domain}/request.json")" == '600 0 0' &&
            "$(stat -c '%a %u %g' "$(registry)/${domain}/credentials.env")" == '600 0 0' ]] || fail '续期输入不是 root 私有'
        cmp -s "${CREDENTIALS}" "$(registry)/${domain}/credentials.env" || fail '保存的续期凭据内容变了'
        jq -e '.schema_version == 1' "$(registry)/${domain}/request.json" >/dev/null ||
            fail 'DNS 登记不再兼容旧 schema 1'
    done
    if [[ "${BACKEND}" == systemd ]]; then
        [[ "$(find "${PADM_DOCKER_SYSTEMD_DIR}" -name '*.timer' | wc -l)" == 1 ]] || fail '安装了多个续期 timer'
    else
        [[ "$(grep -c 'padm-docker.*renew' "${TEST_ROOT}/crontab")" == 1 ]] || fail '安装了多个续期 cron'
    fi
    runControl 0 acme schedule status
    grep -q 'a.example.com' "${TEST_ROOT}/control.log" || fail '状态没有启用域名'
    runControl 0 acme schedule disable --domain a.example.com
    jq -e '.schema_version == 1 and .enabled == false' "$(registry)/a.example.com/request.json" >/dev/null ||
        fail 'DNS 停用删除了原登记或改变了旧格式'
    dockerRenewalEnabled "$(registry)" || fail '禁用单域关闭了其它域名'
    runControl 0 acme schedule disable --domain b.example.com
    if dockerRenewalEnabled "$(registry)"; then fail '全部禁用后仍显示启用'; fi
    [[ ! -e "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.timer" &&
        "$(grep -c 'padm-docker.*renew' "${TEST_ROOT}/crontab" || true)" == 0 ]] || fail '全部停用后仍残留续期任务'
done

for BACKEND in systemd cron; do
    newState "${BACKEND}-ownership"
    if [[ "${BACKEND}" == systemd ]]; then
        printf 'external-unit\n' >"${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service"
        unitBefore=$(sha256sum "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service")
    else
        printf '1 2 * * * external-renew # padm-docker TLS 自动续期 root=/outside\n' >>"${TEST_ROOT}/crontab"
        unitBefore=$(cat "${TEST_ROOT}/crontab")
    fi
    runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    if dockerRenewalEnabled "$(registry)"; then fail '外部调度冲突保留了新的启用登记'; fi
    if [[ "${BACKEND}" == systemd ]]; then
        [[ "$(sha256sum "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service")" == "${unitBefore}" ]] ||
            fail '覆盖了外部同名 systemd unit'
    else
        [[ "$(cat "${TEST_ROOT}/crontab")" == "${unitBefore}" ]] || fail '覆盖了外部续期 cron'
    fi
done

for BACKEND in systemd cron; do
    for DOWN_RESULT in ok traffic-fail; do
        newState "${BACKEND}-down-${DOWN_RESULT}"
        enableDomain a.example.com
        (
            assertNoRenewalJob() {
                [[ ! -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.timer" &&
                    ! -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service" &&
                    ! -f "${TEST_ROOT}/timer-enabled" && ! -f "${TEST_ROOT}/timer-active" &&
                    "$(grep -c 'padm-docker.*renew' "${TEST_ROOT}/crontab" || true)" == 0 ]] ||
                    fail 'down 仍保留可触发续期的调度'
            }
            dockerComposeFile() { printf '/managed/compose.yaml\n'; }
            dockerTrafficBeforeChange() { assertNoRenewalJob; }
            dockerComposeRun() { [[ "$*" == down ]] || fail 'down 执行了意外 Compose 操作'; assertNoRenewalJob; }
            dockerTrafficScheduleRemove() { assertNoRenewalJob; [[ "${DOWN_RESULT}" == ok ]]; }
            EXPECTED=0
            [[ "${DOWN_RESULT}" != traffic-fail ]] || EXPECTED=failure
            runControl "${EXPECTED}" down
            assertNoRenewalJob
            [[ ! -s "${TEST_ROOT}/acme.log" ]] || fail 'down 触发了续期'
        )
    done
done

BACKEND=systemd
for CONFLICT in root exec loaded-path; do
    newState "systemd-ownership-${CONFLICT}"
    enableDomain a.example.com
    case "${CONFLICT}" in
    root) sed -i 's|^# padm-docker root=.*|# padm-docker root=/outside|' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service" ;;
    exec) sed -i 's|^ExecStart=.*|ExecStart=/outside/padm-docker acme auto-renew|' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.service" ;;
    loaded-path) FRAGMENT_OVERRIDE=/outside/padm-docker-renewal.service ;;
    esac
    before=$(registryAndJobs)
    runControl failure acme schedule enable --domain b.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    [[ "$(registryAndJobs)" == "${before}" ]] || fail "${CONFLICT}: 修改了外部 unit 或原续期登记"
done

BACKEND=cron
newState scheduler-migration
enableDomain a.example.com
BACKEND=systemd
enableDomain a.example.com
[[ -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.timer" &&
    "$(grep -c 'padm-docker.*renew' "${TEST_ROOT}/crontab" || true)" == 0 ]] || fail '切换 systemd 后仍保留 cron'
BACKEND=cron
enableDomain a.example.com
[[ ! -f "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-renewal.timer" &&
    "$(grep -c 'padm-docker.*renew' "${TEST_ROOT}/crontab")" == 1 ]] || fail '切换 cron 后仍保留 systemd'

for BACKEND in systemd cron; do
    for MODE_CASE in schedule-fail schedule-term schedule-parent-term commit-term; do
        newState "${BACKEND}-${MODE_CASE}"
        enableDomain a.example.com
        before=$(registryAndJobs)
        MODE=${MODE_CASE}
        EXPECTED=failure
        [[ "${MODE}" != schedule-parent-term && "${MODE}" != commit-term ]] || EXPECTED=143
        runControl "${EXPECTED}" acme schedule enable --domain b.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
        [[ "$(registryAndJobs)" == "${before}" ]] || fail "${BACKEND}/${MODE}: 调度安装中断没有恢复原登记与任务"
        MODE=ok
        rm -f -- "${TEST_ROOT}/schedule-failed"
        MODE=${MODE_CASE}
        runControl "${EXPECTED}" acme schedule disable --domain a.example.com
        [[ "$(registryAndJobs)" == "${before}" ]] || fail "${BACKEND}/${MODE}: 调度删除中断没有恢复原登记与任务"
    done
done

BACKEND=systemd
for TIMER_STATE in normal inactive disabled; do
    newState "partial-unit-${TIMER_STATE}"
    enableDomain a.example.com
    case "${TIMER_STATE}" in
    inactive) rm -- "${TEST_ROOT}/timer-active" ;;
    disabled) rm -- "${TEST_ROOT}/timer-enabled" ;;
    esac
    before=$(registryAndJobs)
    MODE=unit-install-fail
    runControl failure acme schedule enable --domain b.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    [[ "$(registryAndJobs)" == "${before}" ]] || fail "${TIMER_STATE}: 部分 unit 安装失败没有恢复原 enabled/active 状态"
done

newState invalid-input
for args in \
    '--domain ../outside --email admin@example.com --dns dns_test' \
    '--domain a.example.com --email invalid --dns dns_test' \
    '--domain a.example.com --email admin@example.com --dns unsafe'; do
    read -r -a ARGS <<<"${args}"
    runControl 2 acme schedule enable "${ARGS[@]}" --credentials "${CREDENTIALS}"
done
runControl 2 acme schedule enable --domain a.example.com --email admin@example.com --standalone --dns dns_test
runControl 2 acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --standalone
runControl 2 acme schedule enable --domain a.example.com --email admin@example.com --standalone --credentials "${CREDENTIALS}"
for ARGS in '--webroot --standalone' '--standalone --webroot' '--webroot --dns dns_test' \
    '--dns dns_test --webroot' "--webroot --credentials ${CREDENTIALS}" '--webroot /outside'; do
    read -r -a ARGS <<<"${ARGS}"
    runControl 2 acme schedule enable --domain a.example.com --email admin@example.com "${ARGS[@]}"
done
runControl 2 acme schedule disable --domain a.example.com --webroot
runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_other --credentials "${CREDENTIALS}"
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com" "${PADM_DOCKER_INSTALL_DIR}/data/acme/saved-domain"
runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme/saved-domain" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com"
chmod 0644 "${CREDENTIALS}"
runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
chmod 0600 "${CREDENTIALS}"
for CONTENT in 'PATH=/evil' 'PYTHONPATH=/evil' 'LD_PRELOAD=/evil' 'broken-line'; do
    printf '%s\n' "${CONTENT}" >"${TEST_ROOT}/invalid-credentials.env"
    chmod 0600 "${TEST_ROOT}/invalid-credentials.env"
    runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test \
        --credentials "${TEST_ROOT}/invalid-credentials.env"
done
enableDomain a.example.com
cp -- "$(registry)/a.example.com/request.json" "${TEST_ROOT}/valid-request.json"
jq '.enabled = "true"' "${TEST_ROOT}/valid-request.json" >"$(registry)/a.example.com/request.json"
reject dockerRenewalRegistryValidate "$(registry)"
cp -- "${TEST_ROOT}/valid-request.json" "$(registry)/a.example.com/request.json"
chmod 0644 "$(registry)/a.example.com/credentials.env"
reject dockerRenewalRegistryValidate "$(registry)"
chmod 0600 "$(registry)/a.example.com/credentials.env"
mv "$(registry)/a.example.com/credentials.env" "$(registry)/a.example.com/credentials.real"
ln -s credentials.real "$(registry)/a.example.com/credentials.env"
reject dockerRenewalRegistryValidate "$(registry)"
rm -- "$(registry)/a.example.com/credentials.env"
mv "$(registry)/a.example.com/credentials.real" "$(registry)/a.example.com/credentials.env"
dockerRenewalRegistryValidate "$(registry)"

newState account-selection
cp -a "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com_ecc"
sed -i 's/dns_test/dns_other/' "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
if dockerRenewalEnabled "$(registry)"; then fail 'RSA provider 不匹配时采用了备用 ECC 账户'; fi
for FIELD in Le_Domain Le_Webroot; do
    newState "duplicate-${FIELD}"
    VALUE=a.example.com
    [[ "${FIELD}" != Le_Webroot ]] || VALUE=dns_test
    printf "%s='%s'\n" "${FIELD}" "${VALUE}" >>"${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
    runControl failure acme schedule enable --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
    if dockerRenewalEnabled "$(registry)"; then fail "重复 ${FIELD} 赋值被接受"; fi
done

newState ecc-only
mv "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com_ecc"
enableDomain a.example.com
runControl 0 acme auto-renew
for ACTION in --renew --install-cert; do
    grep -Eq "^${ACTION} .* --ecc( |$)" "${TEST_ROOT}/acme.args" || fail "ECC-only ${ACTION} 未传 --ecc"
done
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/a.example.com.crt")" == new-cert-a.example.com ]] ||
    fail 'ECC-only 续期未提交证书'

newState renewal-runs
enableDomain a.example.com
enableDomain b.example.com
before=$(materials)
MODE=skip
runControl 0 acme renew --domain a.example.com --email admin@example.com --dns dns_test --credentials "${CREDENTIALS}"
runControl 0 acme auto-renew
[[ "$(materials)" == "${before}" && ! -s "${TEST_ROOT}/validate.log" ]] || fail '未到期续期没有跳过导出或证书验证'
if grep -q ':--install-cert$' "${TEST_ROOT}/acme.log"; then fail '未到期续期导出了证书'; fi
MODE=first-domain-fail
: >"${TEST_ROOT}/acme.log"
runControl failure acme auto-renew
grep -q '^b.example.com:--install-cert$' "${TEST_ROOT}/acme.log" || fail '首域失败没有继续下一个域名'
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/a.example.com.crt")" == old-cert-a.example.com &&
    "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/b.example.com.crt")" == new-cert-b.example.com ]] ||
    fail '多域续期失败破坏了旧证书或遗漏成功证书'
for MODE_CASE in renew-fail export-fail validate-fail term; do
    newState "run-${MODE_CASE}"
    enableDomain a.example.com
    before=$(materials)
    MODE=${MODE_CASE}
    EXPECTED=failure
    [[ "${MODE}" != term ]] || EXPECTED=143
    runControl "${EXPECTED}" acme auto-renew
    [[ "$(materials)" == "${before}" ]] || fail "${MODE}: 失败或 TERM 没有保留证书与账户"
done

newState stale-account
enableDomain a.example.com
sed -i "s/dns_test/dns_other/" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
before=$(materials)
runControl failure acme auto-renew
[[ ! -s "${TEST_ROOT}/acme.log" && "$(materials)" == "${before}" ]] ||
    fail '账户 provider 漂移仍执行了续期或改写材料'

newState lock-conflict
enableDomain a.example.com
mkdir "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock"
printf '%s\n' "${BASHPID}" >"${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock/pid"
if (dockerMain acme auto-renew) >"${TEST_ROOT}/control.log" 2>&1; then fail '日常续期绕过部署锁'; fi
[[ -d "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" && ! -s "${TEST_ROOT}/acme.log" ]] ||
    fail '锁冲突删除了他人的锁或运行了续期'
rm -- "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock/pid"
rmdir -- "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock"

newState bundle-gate
enableDomain a.example.com
mkdir "${TEST_ROOT}/old-bundle"
reject dockerRenewalBundleCheck "${TEST_ROOT}/old-bundle"
mkdir -p "${TEST_ROOT}/new-bundle/docker/lib"
cp -- "${PROJECT_ROOT}/docker/lib/renewal.sh" "${TEST_ROOT}/new-bundle/docker/lib/renewal.sh"
dockerRenewalBundleCheck "${TEST_ROOT}/new-bundle"
mkdir -p "${TEST_ROOT}/schema1-bundle/docker/lib"
printf 'readonly PADM_DOCKER_RENEWAL_SCHEMA=1\n' >"${TEST_ROOT}/schema1-bundle/docker/lib/renewal.sh"
mkdir -p "${TEST_ROOT}/schema2-bundle/docker/lib"
printf 'readonly PADM_DOCKER_RENEWAL_SCHEMA=2\n' >"${TEST_ROOT}/schema2-bundle/docker/lib/renewal.sh"
mkdir -p "${TEST_ROOT}/schema4-bundle/docker/lib"
printf 'readonly PADM_DOCKER_RENEWAL_SCHEMA=4\n' >"${TEST_ROOT}/schema4-bundle/docker/lib/renewal.sh"
dockerRenewalBundleCheck "${TEST_ROOT}/schema1-bundle"
runControl 0 acme schedule disable --domain a.example.com
dockerRenewalBundleCheck "${TEST_ROOT}/old-bundle"

newState standalone-renewal
sed -i "s/Le_Webroot='dns_test'/Le_Webroot='no'/" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
runControl 0 acme schedule enable --domain a.example.com --email admin@example.com --standalone
[[ "$(find "$(registry)/a.example.com" -mindepth 1 -maxdepth 1 | wc -l)" == 1 &&
    "$(stat -c '%a %u %g' "$(registry)/a.example.com/request.json")" == '600 0 0' ]] ||
    fail 'HTTP 登记多存了 DNS 凭据或放宽了权限'
jq -e '.schema_version == 2 and .provider == "standalone" and .enabled == true' \
    "$(registry)/a.example.com/request.json" >/dev/null || fail 'HTTP 续期登记格式不正确'
dockerRenewalRegistryValidate "$(registry)"
reject dockerRenewalBundleCheck "${TEST_ROOT}/schema1-bundle"
dockerRenewalBundleCheck "${TEST_ROOT}/schema2-bundle"
dockerRenewalBundleCheck "${TEST_ROOT}/new-bundle"
before=$(registryAndJobs)
MODE=schedule-fail
runControl failure acme schedule disable --domain a.example.com
[[ "$(registryAndJobs)" == "${before}" ]] || fail 'HTTP 停用调度失败没有恢复原续期登记和任务'
MODE=ok
rm -f -- "${TEST_ROOT}/schedule-failed"
cp -- "$(registry)/a.example.com/request.json" "${TEST_ROOT}/standalone-request.json"
jq '.schema_version = 1' "${TEST_ROOT}/standalone-request.json" >"$(registry)/a.example.com/request.json"
reject dockerRenewalRegistryValidate "$(registry)"
cp -- "${TEST_ROOT}/standalone-request.json" "$(registry)/a.example.com/request.json"
cp -- "${CREDENTIALS}" "$(registry)/a.example.com/credentials.env"
reject dockerRenewalRegistryValidate "$(registry)"
rm -- "$(registry)/a.example.com/credentials.env"
runControl 0 acme auto-renew
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/a.example.com.crt")" == new-cert-a.example.com &&
    "$(<"${TEST_ROOT}/challenge.log")" == $'prepare\nrestore' ]] ||
    fail 'HTTP 自动续期没有提交证书或完成挑战恢复'
: >"${TEST_ROOT}/acme.log"
sed -i "s/Le_Webroot='no'/Le_Webroot='dns_test'/" "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
before=$(materials)
runControl failure acme auto-renew
[[ ! -s "${TEST_ROOT}/acme.log" && "$(materials)" == "${before}" ]] ||
    fail 'HTTP 账户验证方式漂移仍执行续期或改写材料'
runControl 0 acme schedule disable --domain a.example.com
dockerRenewalBundleCheck "${TEST_ROOT}/schema1-bundle"
[[ ! -e "$(registry)/a.example.com" ]] || fail '停用 HTTP 续期仍留下旧 bundle 无法读取的登记'

newState webroot-renewal
mkdir -p -- "${PADM_DOCKER_INSTALL_DIR}/config"
printf '{"schema_version":3,"tls":{"domain":"a.example.com","http01":true},"core":{"protocols":[{"id":21}]}}\n' \
    >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
sed -i "s|Le_Webroot='dns_test'|Le_Webroot='/var/lib/padm/acme-webroot'|" \
    "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
runControl 0 acme schedule enable --domain a.example.com --email admin@example.com --webroot
[[ "$(find "$(registry)/a.example.com" -mindepth 1 -maxdepth 1 | wc -l)" == 1 &&
    "$(stat -c '%a %u %g' "$(registry)/a.example.com/request.json")" == '600 0 0' ]] ||
    fail 'webroot 登记多存了 DNS 凭据或放宽了权限'
jq -e '.schema_version == 3 and .provider == "webroot" and .enabled == true' \
    "$(registry)/a.example.com/request.json" >/dev/null || fail 'webroot 续期登记格式不正确'
dockerRenewalRegistryValidate "$(registry)"
reject dockerRenewalBundleCheck "${TEST_ROOT}/schema1-bundle"
reject dockerRenewalBundleCheck "${TEST_ROOT}/schema2-bundle"
dockerRenewalBundleCheck "${TEST_ROOT}/new-bundle"
dockerRenewalBundleCheck "${TEST_ROOT}/schema4-bundle"
runControl failure acme schedule enable --domain b.example.com --email admin@example.com --webroot
cp -- "$(registry)/a.example.com/request.json" "${TEST_ROOT}/webroot-request.json"
jq '.schema_version = 2' "${TEST_ROOT}/webroot-request.json" >"$(registry)/a.example.com/request.json"
reject dockerRenewalRegistryValidate "$(registry)"
cp -- "${TEST_ROOT}/webroot-request.json" "$(registry)/a.example.com/request.json"
cp -- "${CREDENTIALS}" "$(registry)/a.example.com/credentials.env"
reject dockerRenewalRegistryValidate "$(registry)"
rm -- "$(registry)/a.example.com/credentials.env"
cp -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/webroot-spec.json"
jq 'del(.tls.http01)' "${TEST_ROOT}/webroot-spec.json" >"${TEST_ROOT}/webroot-disabled.json"
reject dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/webroot-disabled.json"
reject dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/legacy-no-spec.json"
jq '.tls.domain = "b.example.com"' "${TEST_ROOT}/webroot-spec.json" >"${TEST_ROOT}/webroot-domain.json"
reject dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/webroot-domain.json"
dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/webroot-spec.json"
before=$(registryAndJobs)
MODE=schedule-fail
runControl failure acme schedule disable --domain a.example.com
[[ "$(registryAndJobs)" == "${before}" ]] || fail 'webroot 停用调度失败没有恢复登记和任务'
MODE=ok
rm -f -- "${TEST_ROOT}/schedule-failed"
runControl 0 acme auto-renew
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/a.example.com.crt")" == new-cert-a.example.com &&
    "$(<"${TEST_ROOT}/challenge.log")" == $'webroot-prepare\nwebroot-restore' ]] ||
    fail 'webroot 自动续期没有提交证书或清理挑战，或暂停了 standalone 服务'
for DRIFT in disabled domain account; do
    cp -- "${TEST_ROOT}/webroot-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    sed -i "s|Le_Webroot='dns_test'|Le_Webroot='/var/lib/padm/acme-webroot'|" \
        "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
    case "${DRIFT}" in
    disabled) cp -- "${TEST_ROOT}/webroot-disabled.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ;;
    domain) cp -- "${TEST_ROOT}/webroot-domain.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ;;
    account) sed -i "s|Le_Webroot='/var/lib/padm/acme-webroot'|Le_Webroot='dns_test'|" \
        "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf" ;;
    esac
    : >"${TEST_ROOT}/acme.log"
    before=$(materials)
    runControl failure acme auto-renew
    [[ ! -s "${TEST_ROOT}/acme.log" && "$(materials)" == "${before}" ]] ||
        fail "webroot ${DRIFT} 漂移仍执行续期或改写材料"
done
cp -- "${TEST_ROOT}/webroot-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runControl 0 acme schedule disable --domain a.example.com
[[ ! -e "$(registry)/a.example.com" ]] || fail '停用 webroot 仍留下旧 bundle 无法读取的登记'
dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/webroot-disabled.json"
dockerAcmeWebrootTransitionValidate "${TEST_ROOT}/legacy-no-spec.json"
dockerRenewalBundleCheck "${TEST_ROOT}/schema1-bundle"

newState webroot-restore-failure
mkdir -p -- "${PADM_DOCKER_INSTALL_DIR}/config"
cp -- "${TEST_ROOT}/webroot-spec.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
sed -i "s|Le_Webroot='dns_test'|Le_Webroot='/var/lib/padm/acme-webroot'|" \
    "${PADM_DOCKER_INSTALL_DIR}/data/acme/a.example.com/a.example.com.conf"
runControl 0 acme schedule enable --domain a.example.com --email admin@example.com --webroot
enableDomain b.example.com
MODE=webroot-restore-fail
if (dockerMain acme auto-renew) >"${TEST_ROOT}/control.log" 2>&1; then fail 'webroot 恢复失败仍返回成功'; fi
grep -q '^a.example.com:--renew$' "${TEST_ROOT}/acme.log" || fail 'webroot 恢复失败未触发首域续期'
! grep -q '^b.example.com:' "${TEST_ROOT}/acme.log" || fail 'webroot 恢复失败仍启动下一域名'
[[ -d "${PADM_DOCKER_INSTALL_DIR}/data/acme-webroot/active" &&
    -n "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.tls.*' -print -quit)" ]] ||
    fail 'webroot 恢复失败未保留本次挑战和候选账户'

# 凭据必须通过 stdin 传入，不出现在 Docker 参数或宿主导出的环境中。
newState stdin-credentials
(
    eval "${ACME_RUN_IMPLEMENTATION}"
    docker() {
        printf '%s\n' "$*" >"${TEST_ROOT}/docker.args"
        env >"${TEST_ROOT}/docker.env"
        cat >"${TEST_ROOT}/docker.stdin"
    }
    dockerAcmeRun "${OPS_IMAGE}" "${CREDENTIALS}" "${PADM_DOCKER_INSTALL_DIR}/data/acme" \
        "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" --renew -d a.example.com
)
grep -qF "${SECRET}" "${TEST_ROOT}/docker.stdin" || fail '续期没有将凭据放进 stdin'
if grep -qF "${SECRET}" "${TEST_ROOT}/docker.args" "${TEST_ROOT}/docker.env" ||
    grep -Eq -- '(^| )--env-file( |$)|(^| )--env( |$)' "${TEST_ROOT}/docker.args"; then
    fail '续期凭据暴露到 Docker 参数或环境元数据'
fi
printf 'docker-renewal-regression-ok\n'
