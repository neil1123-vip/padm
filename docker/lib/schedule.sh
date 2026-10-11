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
    case "${job}" in renewal|geo|traffic|control-log|control-sync) ;; *) return 1 ;; esac
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
    control-log) DOCKER_MAINTENANCE_CHANGED=0 DOCKER_CONTROL_LOG_SWITCHED=0 ;;
    control-sync) DOCKER_MAINTENANCE_CHANGED=0 DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED=0 ;;
    traffic) DOCKER_MAINTENANCE_CHANGED=0 ;;
    *) return 1 ;;
    esac
    dockerMaintenanceScheduleInterrupted "${job}"
}

dockerMaintenanceScheduleApply() {
    [[ "$#" -eq 2 ]] || return 1
    local action=$1 job=$2 root cli bashPath unitDir file fragment snapshot= cronText= cronLine line
    local marker cronMarker command calendar cronSchedule description timerDescription expected
    local controlLogService= controlLogTimer= dropIns= loaded= prefix= backend=none active=false
    local timeout=1800 timerOptions='RandomizedDelaySec=300' legacy=0
    local systemdReady=0 cronReady=0 timerEnabled=0 timerActive=0 haveUnits=0 haveCron=0
    case "${action}" in install|remove) ;; check) [[ "${job}" == control-log || "${job}" == control-sync ]] || return 1 ;; *) return 1 ;; esac
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
    traffic)
        marker='# padm-docker 流量采集'
        command='traffic collect'
        calendar='*-*-* *:*:00'
        cronSchedule='* * * * *'
        description='padm Docker traffic accounting'
        timerDescription='Collect padm Docker traffic every minute'
        timeout=90
        timerOptions='AccuracySec=1s'
        ;;
    control-log)
        marker='# padm-docker 控制认证日志自动轮转'
        command='control auto-log-rotate'
        calendar='*-*-* *:19:00'
        cronSchedule='19 * * * *'
        description='padm Docker control authentication log rotation'
        timerDescription='Check padm Docker control authentication log hourly'
        timeout=0
        ;;
    control-sync)
        marker='# padm-docker 被控账号自动同步'
        command='control auto-sync'
        calendar='*-*-* *:0/5:00'
        cronSchedule='*/5 * * * *'
        description='padm Docker controlled account synchronization'
        timerDescription='Synchronize padm Docker controlled accounts every five minutes'
        timeout=0
        timerOptions='AccuracySec=1s'
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
    if [[ "${job}" == control-log || "${job}" == control-sync ]]; then
        # 新任务完整核对模板，不能把同 marker 的改写任务当作受管调度。
        controlLogService=$(cat <<EOF
${marker}
# padm-docker root=${root}
[Unit]
Description=${description}
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} ${command}
TimeoutStartSec=0
TimeoutStopSec=0
SuccessExitStatus=12
EOF
)
        controlLogTimer=$(cat <<EOF
${marker}
# padm-docker root=${root}
[Unit]
Description=${timerDescription}
[Timer]
OnCalendar=${calendar}
${timerOptions}
Persistent=true
Unit=padm-docker-${job}.service
[Install]
WantedBy=timers.target
EOF
)
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        systemdReady=1
    fi
    if command -v crontab >/dev/null 2>&1; then
        cronText=$(dockerTrafficReadCrontab) || return 1
        if command -v pgrep >/dev/null 2>&1 && { pgrep -x cron >/dev/null || pgrep -x crond >/dev/null; }; then
            cronReady=1
        fi
    fi
    cronMarker=${marker}
    if [[ "${job}" == traffic ]]; then
        cronMarker='# padm-docker-traffic'
        cronLine="${cronSchedule} PADM_DOCKER_INSTALL_DIR=${root} ${bashPath} ${cli} ${command} ${cronMarker}"
    else
        cronLine="${cronSchedule} PADM_DOCKER_INSTALL_DIR=${root} ${bashPath} ${cli} ${command} ${cronMarker} root=${root}"
    fi
    # 全部来源先确认归本部署所有，不能覆盖同名外部 unit 或其它 root 的任务。
    while IFS= read -r line; do
        [[ "${line}" == *"${cronMarker}"* ]] || continue
        [[ "${line}" == "${cronLine}" ]] || return 1
        haveCron=1
    done <<<"${cronText}"
    if [[ -e "${unitDir}" || -L "${unitDir}" ]]; then
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" &&
            "$(cd -- "${unitDir}" && pwd -P)" == "${unitDir}" ]] || return 1
    fi
    for file in "padm-docker-${job}.service" "padm-docker-${job}.timer"; do
        legacy=0
        [[ ! -L "${unitDir}/${file}" ]] || return 1
        if [[ "${job}" == control-log || "${job}" == control-sync ]]; then
            [[ ! -e "${unitDir}/${file}.d" && ! -L "${unitDir}/${file}.d" ]] || return 1
        fi
        if [[ -e "${unitDir}/${file}" ]]; then
            [[ -f "${unitDir}/${file}" && -O "${unitDir}/${file}" ]] &&
                grep -qxF "${marker}" "${unitDir}/${file}" || return 1
            if [[ "${job}" == control-log || "${job}" == control-sync ]]; then
                [[ "$(stat -c '%u:%g:%a:%h' "${unitDir}/${file}")" == 0:0:644:1 ]] || return 1
                if [[ "${file}" == *.service ]]; then expected=${controlLogService};
                else expected=${controlLogTimer}; fi
                [[ "$(<"${unitDir}/${file}")" == "${expected}" ]] || return 1
            fi
            if [[ "${job}" == traffic ]] &&
                ! grep -q '^# padm-docker root=' "${unitDir}/${file}"; then
                # 旧流量模板只凭精确内容迁移，默认同名 timer 必须仍绑定本 root 的 service。
                if [[ "${file}" == *.service ]]; then
                    expected=$(cat <<EOF
${marker}
[Unit]
Description=${description}
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} ${command}
TimeoutStartSec=${timeout}
EOF
)
                else
                    grep -qxF "Environment=PADM_DOCKER_INSTALL_DIR=${root}" \
                        "${unitDir}/padm-docker-traffic.service" &&
                        grep -qxF "ExecStart=${bashPath} ${cli} ${command}" \
                            "${unitDir}/padm-docker-traffic.service" || return 1
                    expected=$(cat <<EOF
${marker}
[Unit]
Description=${timerDescription}
[Timer]
OnCalendar=${calendar}
${timerOptions}
Persistent=true
[Install]
WantedBy=timers.target
EOF
)
                fi
                [[ "$(<"${unitDir}/${file}")" == "${expected}" ]] || return 1
                legacy=1
            else
                grep -qxF "# padm-docker root=${root}" "${unitDir}/${file}" || return 1
            fi
            if [[ "${file}" == *.service ]]; then
                grep -qxF "Environment=PADM_DOCKER_INSTALL_DIR=${root}" "${unitDir}/${file}" &&
                    grep -qxF "ExecStart=${bashPath} ${cli} ${command}" "${unitDir}/${file}" || return 1
            else
                [[ "${legacy}" == 1 ]] ||
                    grep -qxF "Unit=padm-docker-${job}.service" "${unitDir}/${file}" || return 1
            fi
            haveUnits=1
        fi
        if [[ "${systemdReady}" == 1 ]]; then
            fragment=$(systemctl show --property=FragmentPath --value "${file}" 2>/dev/null) || return 1
            [[ -z "${fragment}" ||
                ( "${fragment}" == "${unitDir}/${file}" && -f "${unitDir}/${file}" ) ]] || return 1
            if [[ "${job}" == control-log || "${job}" == control-sync ]]; then
                dropIns=$(systemctl show --property=DropInPaths --value "${file}" 2>/dev/null) || return 1
                [[ -z "${dropIns}" ]] || return 1
            fi
            if [[ "${job}" == control-sync && -n "${fragment}" ]]; then
                [[ "$(systemctl show --property=NeedDaemonReload --value "${file}" 2>/dev/null)" == no ]] ||
                    return 1
            fi
            if [[ "${job}" == control-sync && -n "${fragment}" && "${file}" == *.service ]]; then
                # 文件模板正确仍可能加载旧命令；确认实际执行定义后才允许幂等跳过。
                [[ "$(systemctl show --property=Environment --value "${file}" 2>/dev/null)" == "PADM_DOCKER_INSTALL_DIR=${root}" ]] ||
                    return 1
                loaded=$(systemctl show --property=ExecStart --value "${file}" 2>/dev/null) || return 1
                prefix="{ path=${bashPath} ; argv[]=${bashPath} ${cli} ${command} ; ignore_errors=no ; "
                [[ "${loaded}" == "${prefix}"* ]] || return 1
                loaded=${loaded#"${prefix}"}
                [[ "${loaded}" != *'path='* && "${loaded}" != *'argv[]='* ]] || return 1
            fi
        fi
    done
    if [[ "${action}" == install ]]; then
        if [[ "${systemdReady}" == 1 ]]; then
            [[ -d "${unitDir}" ]] || return 1
        elif [[ "${cronReady}" != 1 ]]; then
            dockerError "${marker#'# padm-docker '}需要正在运行的 systemd 或 cron"
            return 1
        fi
    elif [[ "${action}" == remove && "${haveUnits}" == 0 && "${haveCron}" == 0 ]]; then
        return 0
    fi
    [[ "${haveUnits}" == 0 ]] || command -v systemctl >/dev/null 2>&1 || return 1
    if [[ -f "${unitDir}/padm-docker-${job}.timer" ]]; then
        if systemctl is-enabled --quiet "padm-docker-${job}.timer"; then timerEnabled=1; fi
        if [[ "${systemdReady}" == 1 ]] && systemctl is-active --quiet "padm-docker-${job}.timer"; then timerActive=1; fi
    fi
    if [[ "${action}" == check ]]; then
        if [[ "${haveUnits}" == 1 ]]; then
            [[ -f "${unitDir}/padm-docker-${job}.service" &&
                -f "${unitDir}/padm-docker-${job}.timer" ]] || return 1
            backend=systemd
            [[ "${timerActive}" != 1 ]] || active=true
        fi
        if [[ "${haveCron}" == 1 ]]; then
            if [[ "${backend}" == none ]]; then backend=cron; else backend=mixed; fi
            [[ "${cronReady}" != 1 ]] || active=true
        fi
        jq -cn --arg backend "${backend}" --argjson active "${active}" \
            '{backend:$backend,installed:($backend != "none"),active:$active}'
        return $?
    fi
    if [[ "${action}" == install && "${job}" == control-sync ]]; then
        # 同步提交和失败恢复均会重装调度；完整核验后的原任务不得停止自身。
        if [[ "${systemdReady}" == 1 && "${haveCron}" == 0 &&
            -f "${unitDir}/padm-docker-${job}.service" && -f "${unitDir}/padm-docker-${job}.timer" &&
            "${timerEnabled}" == 1 && "${timerActive}" == 1 ]]; then return 0; fi
        if [[ "${systemdReady}" == 0 && "${cronReady}" == 1 &&
            "${haveUnits}" == 0 && "${haveCron}" == 1 ]]; then return 0; fi
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
        if [[ "${job}" == control-log || "${job}" == control-sync ]]; then
            printf '%s\n' "${controlLogService}" >"${snapshot}/new.service" &&
                printf '%s\n' "${controlLogTimer}" >"${snapshot}/new.timer" || exit 1
        else
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
TimeoutStartSec=${timeout}
EOF
        cat >"${snapshot}/new.timer" <<EOF
${marker}
# padm-docker root=${root}
[Unit]
Description=${timerDescription}
[Timer]
OnCalendar=${calendar}
${timerOptions}
Persistent=true
Unit=padm-docker-${job}.service
[Install]
WantedBy=timers.target
EOF
        fi
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
        control-log)
            [[ -z "${DOCKER_CONTROL_LOG_STAGE:-}" || "${DOCKER_CONTROL_LOG_SWITCHED:-0}" != 1 ]] || return 0
            dockerMaintenanceScheduleCommit control-log
            ;;
        control-sync)
            [[ -z "${DOCKER_CONTROL_SYNC_SCHEDULE_STAGE:-}" ||
                "${DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED:-0}" != 1 ]] || return 0
            dockerMaintenanceScheduleCommit control-sync
            ;;
        traffic) dockerMaintenanceScheduleCommit traffic ;;
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
