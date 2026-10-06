#!/usr/bin/env bash
set -euo pipefail

# 仅在一次性 Linux 容器运行；probe 只验调度，不执行 ACME 或完整管理 CLI。
[[ "${PADM_RENEWAL_REAL_ISOLATED:-}" == 1 && -f /.dockerenv && "${EUID}" == 0 ]] || {
    printf 'renewal-real: requires an explicitly isolated disposable root container\n' >&2
    exit 2
}
[[ "$#" == 1 ]] || { printf 'usage: renewal-real.sh <systemd-init|systemd-resume|cron-migrate|cron-resume|systemd-migrate>\n' >&2; exit 2; }
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

TEST_ROOT=/var/lib/padm-renewal-real
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin"
export PADM_DOCKER_SYSTEMD_DIR=/etc/systemd/system
UNIT_DIR=${PADM_DOCKER_SYSTEMD_DIR}
TIMER=padm-docker-renewal.timer
SERVICE=padm-docker-renewal.service
EXTERNAL='0 0 * * * /bin/true # renewal-real-external'
CRON_LINE="17 3 * * * PADM_DOCKER_INSTALL_DIR=${PADM_DOCKER_INSTALL_DIR} $(command -v bash) ${PADM_DOCKER_BIN_DIR}/padm-docker acme auto-renew # padm-docker TLS 自动续期 root=${PADM_DOCKER_INSTALL_DIR}"
trap 'dockerRenewalScheduleInterrupted || true' EXIT

fail() { printf 'renewal-real-fail: %s\n' "$*" >&2; exit 1; }
calls() { wc -l <"${PADM_DOCKER_INSTALL_DIR}/probe.log"; }
pid1Start() { awk '{print $22}' /proc/1/stat; }
assertProbe() {
    awk -F'|' -v root="${PADM_DOCKER_INSTALL_DIR}" '
      NF != 6 || $1 != "scheduler-probe" || $2 != "argc=2" ||
      $3 != "argv=acme auto-renew" || $4 != ("root=" root) || $5 != "uid=0" ||
      $6 !~ /^pid1-start=[0-9]+$/ { bad=1 }
      END { exit bad || !NR }
    ' "${PADM_DOCKER_INSTALL_DIR}/probe.log" ||
        fail 'scheduler probe received incorrect arguments, environment, or PID 1'
}
waitProbe() {
    local previous=$1 expected=$2
    for _ in {1..80}; do
        if [[ "$(calls)" -gt "${previous}" ]]; then
            assertProbe
            if tail -n "+$((previous + 1))" "${PADM_DOCKER_INSTALL_DIR}/probe.log" |
                awk -F'|' -v expected="${expected}" '$6 == ("pid1-start=" expected) {seen=1} END {exit !seen}'; then
                return 0
            fi
        fi
        sleep 1
    done
    fail 'real scheduler did not execute the probe within 80 seconds'
}
setEnabled() {
    local domain=$1 enabled=$2 request="${PADM_DOCKER_INSTALL_DIR}/secrets/renewal/$1/request.json"
    jq --argjson enabled "${enabled}" '.enabled = $enabled' "${request}" >"${TEST_ROOT}/request.next"
    install -m 0600 "${TEST_ROOT}/request.next" "${request}"
}
assertSystemd() {
    systemctl show-environment >/dev/null
    systemctl is-enabled --quiet "${TIMER}"
    systemctl is-active --quiet "${TIMER}"
    [[ "$(find "${UNIT_DIR}" -maxdepth 1 -name padm-docker-renewal.timer | wc -l)" == 1 ]]
    [[ "$(systemctl show --property=FragmentPath --value "${TIMER}")" == "${UNIT_DIR}/${TIMER}" ]]
    grep -qxF "ExecStart=$(command -v bash) ${PADM_DOCKER_BIN_DIR}/padm-docker acme auto-renew" "${UNIT_DIR}/${SERVICE}"
    grep -qxF "Environment=PADM_DOCKER_INSTALL_DIR=${PADM_DOCKER_INSTALL_DIR}" "${UNIT_DIR}/${SERVICE}"
    grep -qxF 'OnCalendar=*-*-* 03:17:00' "${UNIT_DIR}/${TIMER}"
    grep -qxF 'Persistent=true' "${UNIT_DIR}/${TIMER}"
    [[ "$(stat -c '%a %u %g' "${UNIT_DIR}/${SERVICE}")" == '644 0 0' ]]
    [[ "$(stat -c '%a %u %g' "${UNIT_DIR}/${TIMER}")" == '644 0 0' ]]
    [[ "$(crontab -l | grep -c '# padm-docker TLS 自动续期' || true)" == 0 ]]
    crontab -l | grep -qxF "${EXTERNAL}"
}
assertCron() {
    systemctl show-environment >/dev/null 2>&1 && fail 'cron fixture still has live systemd'
    pgrep -x cron >/dev/null
    [[ ! -e "${UNIT_DIR}/${SERVICE}" && ! -e "${UNIT_DIR}/${TIMER}" ]]
    [[ ! -e "${UNIT_DIR}/timers.target.wants/${TIMER}" ]]
    [[ "$(crontab -l | grep -c '# padm-docker TLS 自动续期')" == 1 ]]
    crontab -l | grep -qxF "${CRON_LINE}"
    crontab -l | grep -qxF "${EXTERNAL}"
}
assertRemoved() {
    [[ ! -e "${UNIT_DIR}/${SERVICE}" && ! -e "${UNIT_DIR}/${TIMER}" ]]
    [[ ! -e "${UNIT_DIR}/timers.target.wants/${TIMER}" ]]
    [[ "$(crontab -l | grep -c '# padm-docker TLS 自动续期' || true)" == 0 ]]
    crontab -l | grep -qxF "${EXTERNAL}"
}
toggleBoth() {
    local assert=$1
    setEnabled a.example.com false
    dockerRenewalScheduleInstall
    "${assert}"
    setEnabled b.example.com false
    dockerRenewalScheduleInstall
    assertRemoved
    setEnabled a.example.com true
    setEnabled b.example.com true
    dockerRenewalScheduleInstall
    "${assert}"
}
accelerateSystemd() {
    # 仅加速隔离夹具的触发时间，生产 unit 的每日时间与参数保持原样。
    mkdir -p "${UNIT_DIR}/${TIMER}.d"
    printf '[Timer]\nOnCalendar=\nOnActiveSec=1s\nRandomizedDelaySec=0\nAccuracySec=1us\n' \
        >"${UNIT_DIR}/${TIMER}.d/probe.conf"
    systemctl daemon-reload
    systemctl restart "${TIMER}"
}
restoreSystemd() {
    rm -- "${UNIT_DIR}/${TIMER}.d/probe.conf"
    rmdir -- "${UNIT_DIR}/${TIMER}.d"
    systemctl daemon-reload
    systemctl restart "${TIMER}"
    assertSystemd
}
accelerateCron() {
    # 只替换五个时间字段；环境、可执行路径及参数仍由生产模块生成。
    crontab -l >"${TEST_ROOT}/daily.crontab"
    sed 's/^17 3 \* \* \*/\* \* \* \* \*/' "${TEST_ROOT}/daily.crontab" | crontab -
}

case "$1" in
systemd-init)
    [[ ! -e "${TEST_ROOT}" && ! -e "${UNIT_DIR}/${SERVICE}" && ! -e "${UNIT_DIR}/${TIMER}" ]] ||
        fail 'refusing existing fixture or scheduler files'
    existingCrontab=$(dockerTrafficReadCrontab)
    [[ -z "${existingCrontab}" ]] || fail 'refusing an existing root crontab'
    systemctl show-environment >/dev/null
    mkdir -p "${PADM_DOCKER_BIN_DIR}"
    dockerInitializeStateRoot
    : >"${PADM_DOCKER_INSTALL_DIR}/probe.log"
    cat >"${PADM_DOCKER_BIN_DIR}/padm-docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# 调度器 probe，不执行 ACME、Docker 或真实协议操作。
[[ "$#" == 2 && "$1" == acme && "$2" == auto-renew ]]
[[ "${PADM_DOCKER_INSTALL_DIR:-}" == /var/lib/padm-renewal-real/state && "${EUID}" == 0 ]]
    printf 'scheduler-probe|argc=%s|argv=%s|root=%s|uid=%s|pid1-start=%s\n' \
        "$#" "$*" "${PADM_DOCKER_INSTALL_DIR}" "${EUID}" "$(awk '{print $22}' /proc/1/stat)" \
    >>"${PADM_DOCKER_INSTALL_DIR}/probe.log"
EOF
    chmod 0755 "${PADM_DOCKER_BIN_DIR}/padm-docker"
    for domain in a.example.com b.example.com; do
        directory="${PADM_DOCKER_INSTALL_DIR}/secrets/renewal/${domain}"
        mkdir -p "${directory}"
        jq -n --arg domain "${domain}" '{schema_version:1,domain:$domain,email:"admin@example.com",
          provider:"dns_probe",enabled:true}' >"${directory}/request.json"
        printf 'DNS_PROBE_VALUE=test-only\n' >"${directory}/credentials.env"
        chmod 0700 "${PADM_DOCKER_INSTALL_DIR}/secrets/renewal" "${directory}"
        chmod 0600 "${directory}/"*
    done
    printf '%s\n' "${EXTERNAL}" | crontab -
    printf '# external scheduler probe fixture\n[Service]\nExecStart=/bin/true\n' >"${UNIT_DIR}/${SERVICE}"
    systemctl daemon-reload
    before=$(sha256sum "${UNIT_DIR}/${SERVICE}")
    if dockerRenewalScheduleInstall; then fail 'overwrote an external same-name systemd service'; fi
    [[ "$(sha256sum "${UNIT_DIR}/${SERVICE}")" == "${before}" ]]
    rm -- "${UNIT_DIR}/${SERVICE}"
    systemctl daemon-reload
    for _ in 1 2 3; do dockerRenewalScheduleInstall; done
    assertSystemd
    toggleBoth assertSystemd
    previous=$(calls)
    accelerateSystemd
    waitProbe "${previous}" "$(pid1Start)"
    calls >"${TEST_ROOT}/before-reboot"
    pid1Start >"${TEST_ROOT}/pid1-start"
    ;;
systemd-resume)
    [[ "$(awk '{print $22}' /proc/1/stat)" != "$(<"${TEST_ROOT}/pid1-start")" ]] || fail 'systemd was not restarted'
    assertSystemd
    waitProbe "$(<"${TEST_ROOT}/before-reboot")" "$(pid1Start)"
    restoreSystemd
    ;;
cron-migrate)
    systemctl show-environment >/dev/null 2>&1 && fail 'cron fixture still has live systemd'
    pgrep -x cron >/dev/null
    [[ -f "${UNIT_DIR}/${TIMER}" ]] || fail 'missing systemd source for backend migration'
    for _ in 1 2 3; do dockerRenewalScheduleInstall; done
    assertCron
    before=$(crontab -l)
    printf '%s\n%s\n' "${before}" \
        '1 2 * * * /bin/true # padm-docker TLS 自动续期 root=/outside' | crontab -
    conflict=$(crontab -l)
    if dockerRenewalScheduleInstall; then fail 'overwrote an external renewal cron'; fi
    [[ "$(crontab -l)" == "${conflict}" ]]
    printf '%s\n' "${before}" | crontab -
    toggleBoth assertCron
    previous=$(calls)
    accelerateCron
    waitProbe "${previous}" "$(pid1Start)"
    calls >"${TEST_ROOT}/before-reboot"
    pid1Start >"${TEST_ROOT}/pid1-start"
    ;;
cron-resume)
    [[ "$(awk '{print $22}' /proc/1/stat)" != "$(<"${TEST_ROOT}/pid1-start")" ]] || fail 'cron was not restarted'
    systemctl show-environment >/dev/null 2>&1 && fail 'cron fixture still has live systemd'
    pgrep -x cron >/dev/null
    waitProbe "$(<"${TEST_ROOT}/before-reboot")" "$(pid1Start)"
    crontab - <"${TEST_ROOT}/daily.crontab"
    dockerRenewalScheduleInstall
    assertCron
    ;;
systemd-migrate)
    systemctl show-environment >/dev/null
    [[ "$(crontab -l | grep -c '# padm-docker TLS 自动续期')" == 1 ]] || fail 'missing cron source for backend migration'
    for _ in 1 2 3; do dockerRenewalScheduleInstall; done
    assertSystemd
    previous=$(calls)
    accelerateSystemd
    waitProbe "${previous}" "$(pid1Start)"
    restoreSystemd
    setEnabled a.example.com false
    setEnabled b.example.com false
    dockerRenewalScheduleInstall
    assertRemoved
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}/locks" -name 'renewal-schedule.*' -print)" ]]
    assertProbe
    ;;
*) fail "unknown stage: $1" ;;
esac
printf 'docker-renewal-real-ok: stage=%s probes=%s\n' "$1" "$(calls)"
