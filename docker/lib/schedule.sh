#!/usr/bin/env bash

if [[ "${PADM_DOCKER_SCHEDULE_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SCHEDULE_LOADED=1

DOCKER_MAINTENANCE_JOB=
DOCKER_MAINTENANCE_SNAPSHOT=
DOCKER_MAINTENANCE_CHANGED=0

dockerMaintenanceScheduleRestore() {
    local snapshot=$1 unitDir=$2 systemdReady=$3 timerEnabled=$4 timerActive=$5 job=$6 file failed=0
    case "${job}" in renewal|geo) ;; *) return 1 ;; esac
    if [[ "${systemdReady}" == 1 ]]; then
        [[ ! -f "${unitDir}/padm-docker-${job}.timer" ]] ||
            systemctl disable --now "padm-docker-${job}.timer" >/dev/null 2>&1 || return 1
        [[ ! -f "${unitDir}/padm-docker-${job}.service" ]] ||
            systemctl stop "padm-docker-${job}.service" >/dev/null 2>&1 || return 1
    fi
    for file in "padm-docker-${job}.service" "padm-docker-${job}.timer"; do
        if [[ -f "${snapshot}/${file}" ]]; then
            install -m 0644 "${snapshot}/${file}" "${unitDir}/${file}" || failed=1
        else
            rm -f -- "${unitDir}/${file}" || failed=1
        fi
    done
    if [[ "${systemdReady}" == 1 ]]; then
        systemctl daemon-reload || failed=1
    fi
    if [[ "${timerEnabled}" == 1 ]]; then
        systemctl enable "padm-docker-${job}.timer" >/dev/null || failed=1
    fi
    if [[ "${systemdReady}" == 1 && "${timerActive}" == 1 ]]; then
        systemctl start "padm-docker-${job}.timer" >/dev/null || failed=1
    fi
    if [[ -f "${snapshot}/crontab" ]]; then
        crontab - <"${snapshot}/crontab" || failed=1
    fi
    [[ "${failed}" == 0 ]]
}

dockerMaintenanceScheduleInterrupted() {
    local job=$1 snapshot=${DOCKER_MAINTENANCE_SNAPSHOT:-} root
    [[ -n "${snapshot}" && "${DOCKER_MAINTENANCE_JOB:-}" == "${job}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ "${DOCKER_MAINTENANCE_CHANGED:-0}" == 1 ]]; then
        dockerMaintenanceScheduleRestore "${snapshot}" "${DOCKER_MAINTENANCE_UNIT_DIR}" \
            "${DOCKER_MAINTENANCE_SYSTEMD_READY}" "${DOCKER_MAINTENANCE_TIMER_ENABLED}" \
            "${DOCKER_MAINTENANCE_TIMER_ACTIVE}" "${job}" || {
            dockerError "${job} 调度恢复失败，请检查: ${snapshot}"
            return 1
        }
    fi
    dockerRemoveManagedTree "${root}" "${snapshot}" || return 1
    DOCKER_MAINTENANCE_SNAPSHOT= DOCKER_MAINTENANCE_JOB= DOCKER_MAINTENANCE_CHANGED=0
}

dockerMaintenanceScheduleCommit() {
    local job=$1
    [[ -z "${DOCKER_MAINTENANCE_SNAPSHOT:-}" || "${DOCKER_MAINTENANCE_JOB:-}" == "${job}" ]] || return 1
    # 登记与调度同时结束恢复窗口，TERM 不能只回退其中一份。
    case "${job}" in
    renewal) DOCKER_MAINTENANCE_CHANGED=0 DOCKER_RENEWAL_SWITCHED=0 ;;
    geo) DOCKER_MAINTENANCE_CHANGED=0 DOCKER_GEO_SWITCHED=0 ;;
    *) return 1 ;;
    esac
    dockerMaintenanceScheduleInterrupted "${job}"
}

dockerMaintenanceScheduleApply() {
    [[ "$#" -eq 2 ]] || return 1
    local action=$1 job=$2 root cli bashPath unitDir file fragment snapshot= cronText= cronLine line
    local marker command calendar cronSchedule description timerDescription
    local systemdReady=0 cronReady=0 timerEnabled=0 timerActive=0 haveUnits=0 haveCron=0
    case "${action}" in install|remove) ;; *) return 1 ;; esac
    case "${job}" in
    renewal)
        marker='# padm-docker TLS 自动续期'
        command='acme auto-renew'
        calendar='*-*-* 03:17:00'
        cronSchedule='17 3 * * *'
        description='padm Docker TLS renewal'
        timerDescription='Renew padm Docker TLS daily'
        ;;
    geo)
        marker='# padm-docker Geo 自动更新'
        command='geo auto-update'
        calendar='*-*-* 01:35:00'
        cronSchedule='35 1 * * *'
        description='padm Docker Xray Geo update'
        timerDescription='Update padm Docker Xray Geo daily'
        ;;
    *) return 1 ;;
    esac
    [[ -z "${DOCKER_MAINTENANCE_SNAPSHOT:-}" ]] || return 1
    root=$(dockerInstallRoot) || return 1
    cli="${PADM_DOCKER_BIN_DIR:-/usr/local/bin}/padm-docker"
    bashPath=$(command -v bash) || return 1
    unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system}
    [[ "${root}" =~ ^/[A-Za-z0-9._/-]+$ && "${cli}" =~ ^/[A-Za-z0-9._/-]+$ &&
        "${bashPath}" =~ ^/[A-Za-z0-9._/-]+$ && "${unitDir}" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        systemdReady=1
    fi
    if command -v crontab >/dev/null 2>&1; then
        cronText=$(dockerTrafficReadCrontab) || return 1
        if command -v pgrep >/dev/null 2>&1 && { pgrep -x cron >/dev/null || pgrep -x crond >/dev/null; }; then
            cronReady=1
        fi
    fi
    cronLine="${cronSchedule} PADM_DOCKER_INSTALL_DIR=${root} ${bashPath} ${cli} ${command} ${marker} root=${root}"
    # 全部来源先确认归本部署所有，不能覆盖同名外部 unit 或其它 root 的任务。
    while IFS= read -r line; do
        [[ "${line}" == *"${marker}"* ]] || continue
        [[ "${line}" == "${cronLine}" ]] || return 1
        haveCron=1
    done <<<"${cronText}"
    if [[ -e "${unitDir}" || -L "${unitDir}" ]]; then
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" &&
            "$(cd -- "${unitDir}" && pwd -P)" == "${unitDir}" ]] || return 1
    fi
    for file in "padm-docker-${job}.service" "padm-docker-${job}.timer"; do
        [[ ! -L "${unitDir}/${file}" ]] || return 1
        if [[ -e "${unitDir}/${file}" ]]; then
            [[ -f "${unitDir}/${file}" && -O "${unitDir}/${file}" ]] &&
                grep -qxF "${marker}" "${unitDir}/${file}" &&
                grep -qxF "# padm-docker root=${root}" "${unitDir}/${file}" || return 1
            if [[ "${file}" == *.service ]]; then
                grep -qxF "Environment=PADM_DOCKER_INSTALL_DIR=${root}" "${unitDir}/${file}" &&
                    grep -qxF "ExecStart=${bashPath} ${cli} ${command}" "${unitDir}/${file}" || return 1
            else
                grep -qxF "Unit=padm-docker-${job}.service" "${unitDir}/${file}" || return 1
            fi
            haveUnits=1
        fi
        if [[ "${systemdReady}" == 1 ]]; then
            fragment=$(systemctl show --property=FragmentPath --value "${file}" 2>/dev/null) || return 1
            [[ -z "${fragment}" ||
                ( "${fragment}" == "${unitDir}/${file}" && -f "${unitDir}/${file}" ) ]] || return 1
        fi
    done
    if [[ "${action}" == install ]]; then
        if [[ "${systemdReady}" == 1 ]]; then
            [[ -d "${unitDir}" ]] || return 1
        elif [[ "${cronReady}" != 1 ]]; then
            dockerError "${marker#'# padm-docker '}需要正在运行的 systemd 或 cron"
            return 1
        fi
    elif [[ "${haveUnits}" == 0 && "${haveCron}" == 0 ]]; then
        return 0
    fi
    [[ "${haveUnits}" == 0 ]] || command -v systemctl >/dev/null 2>&1 || return 1
    if [[ -f "${unitDir}/padm-docker-${job}.timer" ]]; then
        if systemctl is-enabled --quiet "padm-docker-${job}.timer"; then timerEnabled=1; fi
        if [[ "${systemdReady}" == 1 ]] && systemctl is-active --quiet "padm-docker-${job}.timer"; then timerActive=1; fi
    fi
    dockerManagedPathIsSafe "${root}" "${root}/locks" &&
        [[ -d "${root}/locks" && ! -L "${root}/locks" && -O "${root}/locks" ]] || return 1
    snapshot=$(mktemp -d "${root}/locks/${job}-schedule.XXXXXX") || return 1
    DOCKER_MAINTENANCE_JOB=${job} DOCKER_MAINTENANCE_SNAPSHOT=${snapshot} \
        DOCKER_MAINTENANCE_UNIT_DIR=${unitDir} DOCKER_MAINTENANCE_SYSTEMD_READY=${systemdReady} \
        DOCKER_MAINTENANCE_TIMER_ENABLED=${timerEnabled} DOCKER_MAINTENANCE_TIMER_ACTIVE=${timerActive} \
        DOCKER_MAINTENANCE_CHANGED=0
    chmod 0700 "${snapshot}" || return 1
    for file in "padm-docker-${job}.service" "padm-docker-${job}.timer"; do
        [[ ! -f "${unitDir}/${file}" ]] || cp -- "${unitDir}/${file}" "${snapshot}/${file}" || return 1
    done
    [[ "${haveCron}" == 0 && ( "${action}" == remove || "${systemdReady}" == 1 ) ]] ||
        printf '%s\n' "${cronText}" >"${snapshot}/crontab" || return 1
    DOCKER_MAINTENANCE_CHANGED=1
    if (
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [[ "${haveUnits}" == 1 ]]; then
        if [[ "${systemdReady}" == 1 ]]; then
            [[ ! -f "${unitDir}/padm-docker-${job}.timer" ]] ||
                systemctl disable --now "padm-docker-${job}.timer" >/dev/null || exit 1
            [[ ! -f "${unitDir}/padm-docker-${job}.service" ]] ||
                systemctl stop "padm-docker-${job}.service" >/dev/null || exit 1
        else
            [[ ! -f "${unitDir}/padm-docker-${job}.timer" ]] ||
                systemctl disable "padm-docker-${job}.timer" >/dev/null || exit 1
        fi
    fi
    if [[ "${haveCron}" == 1 ]]; then
        printf '%s\n' "${cronText}" | awk -v owned="${cronLine}" '$0 != owned' | crontab - || exit 1
    fi
    if [[ "${action}" == install && "${systemdReady}" == 1 ]]; then
        cat >"${snapshot}/new.service" <<EOF
${marker}
# padm-docker root=${root}
[Unit]
Description=${description}
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} ${command}
TimeoutStartSec=1800
EOF
        cat >"${snapshot}/new.timer" <<EOF
${marker}
# padm-docker root=${root}
[Unit]
Description=${timerDescription}
[Timer]
OnCalendar=${calendar}
RandomizedDelaySec=300
Persistent=true
Unit=padm-docker-${job}.service
[Install]
WantedBy=timers.target
EOF
        install -m 0644 "${snapshot}/new.service" "${unitDir}/padm-docker-${job}.service" &&
            install -m 0644 "${snapshot}/new.timer" "${unitDir}/padm-docker-${job}.timer" &&
            systemctl daemon-reload &&
            systemctl enable --now "padm-docker-${job}.timer" >/dev/null || exit 1
    else
        rm -f -- "${unitDir}/padm-docker-${job}.service" "${unitDir}/padm-docker-${job}.timer" || exit 1
        [[ "${systemdReady}" == 0 || "${haveUnits}" == 0 ]] || systemctl daemon-reload || exit 1
        if [[ "${action}" == install ]]; then
            { printf '%s\n' "${cronText}" | awk -v owned="${cronLine}" '$0 != owned'; printf '%s\n' "${cronLine}"; } | crontab - || exit 1
        fi
    fi
    ); then
        case "${job}" in
        renewal)
            [[ -z "${DOCKER_RENEWAL_STAGE:-}" || "${DOCKER_RENEWAL_SWITCHED:-0}" != 1 ]] || return 0
            dockerRenewalScheduleCommit
            ;;
        geo)
            [[ -z "${DOCKER_GEO_STAGE:-}" || "${DOCKER_GEO_SWITCHED:-0}" != 1 ]] || return 0
            dockerGeoScheduleCommit
            ;;
        esac
    else
        dockerMaintenanceScheduleInterrupted "${job}" || true
        return 1
    fi
}

dockerGeoScheduleApply() {
    dockerMaintenanceScheduleApply "$1" geo
}

dockerGeoScheduleInterrupted() {
    dockerMaintenanceScheduleInterrupted geo
}

dockerGeoScheduleCommit() {
    dockerMaintenanceScheduleCommit geo
}
