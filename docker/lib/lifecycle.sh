#!/usr/bin/env bash

if [[ "${PADM_DOCKER_LIFECYCLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_LIFECYCLE_LOADED=1

dockerUsage() {
    cat >&2 <<'EOF'
用法:
  padm-docker                          # 交互终端进入菜单；非交互显示帮助
  padm-docker menu
  install-docker.sh install [--source <目录>] [--ref <commit|latest>] [--no-menu]
  padm-docker release [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker setup [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker edit [--spec <完整 JSON 文件>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker protocol list
  padm-docker protocol links [入口 ID]
  padm-docker protocol stream-status
  padm-docker edit --reality-stream <Reality 入口 ID> <网站 TLS 入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --reality-stream-host <Reality 入口 ID> <网站域名,域名> <宿主可达地址> <TLS 端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --reality-stream off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker configure --spec <JSON 文件> [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker tls install --domain <域名> --cert <文件> --key <文件> [--ops-image <tag@digest>]
  padm-docker tls validate --domain <域名>
  padm-docker tls manage
  padm-docker acme <issue|renew> --domain <域名> --email <邮箱> --dns <dns_*> --credentials <文件> [--ops-image <tag@digest>]
  padm-docker acme schedule <enable|disable|status> [续期输入参数]
  padm-docker acme auto-renew
  padm-docker validate
  padm-docker status
  padm-docker traffic <show|collect>
  padm-docker traffic limit <账号 ID> <额度 GiB，0 不限额>
  padm-docker traffic reset <账号 ID>
  padm-docker up
  padm-docker down
  padm-docker restart
  padm-docker logs [Compose logs 参数]
  padm-docker update [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker rollback
  padm-docker uninstall [--remove-images] [--purge --confirm PADM-DOCKER-PURGE]
EOF
}

dockerTrafficScheduleCheck() {
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        return 0
    fi
    if command -v crontab >/dev/null 2>&1 && command -v pgrep >/dev/null 2>&1 &&
        { pgrep -x cron >/dev/null || pgrep -x crond >/dev/null; }; then
        return 0
    fi
    dockerError '自动流量采集需要正在运行的 systemd 或 cron，请先启用其中一项'
    return 1
}

dockerTrafficReadCrontab() {
    local content
    content=$(LC_ALL=C crontab -l 2>&1) || {
        case "${content}" in
        *'no crontab for'*|*"can't open 'root': No such file or directory"*) return 0 ;;
        *) dockerError "${content}"; return 1 ;;
        esac
    }
    printf '%s\n' "${content}"
}

dockerTrafficCronRemove() {
    local content
    command -v crontab >/dev/null 2>&1 || return 0
    content=$(dockerTrafficReadCrontab) || return 1
    if [[ "${content}" == *'# padm-docker-traffic'* ]]; then
        printf '%s\n' "${content}" | sed '/# padm-docker-traffic$/d' | crontab - || return 1
    fi
}

dockerTrafficRuntimeCheck() {
    local cores=${1:-} core
    if [[ -z "${cores}" ]]; then
        cores=$(dockerTrafficCore) || return 1
    fi
    while IFS= read -r core; do
        case "${core}" in
        xray) ;;
        sing-box)
            dockerRequireCommand nsenter && dockerRequireCommand curl || return 1
            curl --version | grep -Eq '^Features:.*[[:space:]]HTTP2([[:space:]]|$)' || {
                dockerError 'sing-box 自动流量采集需要支持 HTTP/2 的宿主 curl'
                return 1
            }
            ;;
        *) dockerError "流量采集核心无效: ${core}"; return 1 ;;
        esac
    done <<<"${cores}"
    dockerTrafficScheduleCheck
}

dockerTrafficScheduleInstall() {
    local root cli bashPath unitDir temp cronText
    dockerTrafficScheduleCheck || return 1
    root=$(dockerInstallRoot) || return 1
    cli="${PADM_DOCKER_BIN_DIR:-/usr/local/bin}/padm-docker"
    bashPath=$(command -v bash) || return 1
    # 定时任务配置不能接受换行、shell 表达式或 systemd 占位符。
    [[ "${root}" =~ ^/[A-Za-z0-9._/-]+$ && "${cli}" =~ ^/[A-Za-z0-9._/-]+$ &&
        "${bashPath}" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system}
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" ]] || return 1
        for temp in "${unitDir}/padm-docker-traffic.service" "${unitDir}/padm-docker-traffic.timer"; do
            [[ ! -L "${temp}" ]] || return 1
            if [[ -e "${temp}" ]]; then
                [[ -f "${temp}" && -O "${temp}" ]] &&
                    grep -qxF '# padm-docker 流量采集' "${temp}" || return 1
            fi
        done
        temp=$(mktemp "${root}/locks/traffic-unit.XXXXXX") || return 1
        cat >"${temp}" <<EOF
# padm-docker 流量采集
[Unit]
Description=padm Docker traffic accounting
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} traffic collect
TimeoutStartSec=90
EOF
        install -m 0644 "${temp}" "${unitDir}/padm-docker-traffic.service" || { rm -f -- "${temp}"; return 1; }
        cat >"${temp}" <<'EOF'
# padm-docker 流量采集
[Unit]
Description=Collect padm Docker traffic every minute
[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s
Persistent=true
[Install]
WantedBy=timers.target
EOF
        install -m 0644 "${temp}" "${unitDir}/padm-docker-traffic.timer" || { rm -f -- "${temp}"; return 1; }
        rm -f -- "${temp}"
        systemctl daemon-reload && systemctl enable --now padm-docker-traffic.timer && dockerTrafficCronRemove
    else
        cronText=$(dockerTrafficReadCrontab) || return 1
        {
            printf '%s\n' "${cronText}" | sed '/# padm-docker-traffic$/d'
            printf '* * * * * PADM_DOCKER_INSTALL_DIR=%s %s %s traffic collect # padm-docker-traffic\n' "${root}" "${bashPath}" "${cli}"
        } | crontab -
    fi
}

dockerTrafficScheduleRemove() {
    local unitDir file changed=0
    unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system}
    for file in "${unitDir}/padm-docker-traffic.timer" "${unitDir}/padm-docker-traffic.service"; do
        [[ -e "${file}" || -L "${file}" ]] || continue
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" &&
            -f "${file}" && ! -L "${file}" && -O "${file}" ]] || return 1
        grep -qxF '# padm-docker 流量采集' "${file}" || return 1
        if [[ "${file}" == *.timer ]]; then systemctl disable --now "${file##*/}" || return 1;
        else systemctl stop "${file##*/}" || return 1; fi
        rm -f -- "${file}" || return 1
        changed=1
    done
    [[ "${changed}" == 0 ]] || systemctl daemon-reload || return 1
    dockerTrafficCronRemove
}

dockerRenewalScheduleRestore() {
    local snapshot=$1 unitDir=$2 systemdReady=$3 timerEnabled=$4 timerActive=$5 file failed=0
    if [[ "${systemdReady}" == 1 ]]; then
        [[ ! -f "${unitDir}/padm-docker-renewal.timer" ]] ||
            systemctl disable --now padm-docker-renewal.timer >/dev/null 2>&1 || return 1
        [[ ! -f "${unitDir}/padm-docker-renewal.service" ]] ||
            systemctl stop padm-docker-renewal.service >/dev/null 2>&1 || return 1
    fi
    for file in padm-docker-renewal.service padm-docker-renewal.timer; do
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
        systemctl enable padm-docker-renewal.timer >/dev/null || failed=1
    fi
    if [[ "${systemdReady}" == 1 && "${timerActive}" == 1 ]]; then
        systemctl start padm-docker-renewal.timer >/dev/null || failed=1
    fi
    if [[ -f "${snapshot}/crontab" ]]; then
        crontab - <"${snapshot}/crontab" || failed=1
    fi
    [[ "${failed}" == 0 ]]
}

dockerRenewalScheduleInterrupted() {
    local snapshot=${DOCKER_RENEWAL_SCHEDULE_SNAPSHOT:-} root
    [[ -n "${snapshot}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ "${DOCKER_RENEWAL_SCHEDULE_CHANGED:-0}" == 1 ]]; then
        dockerRenewalScheduleRestore "${snapshot}" "${DOCKER_RENEWAL_SCHEDULE_UNIT_DIR}" \
            "${DOCKER_RENEWAL_SCHEDULE_SYSTEMD_READY}" "${DOCKER_RENEWAL_SCHEDULE_TIMER_ENABLED}" \
            "${DOCKER_RENEWAL_SCHEDULE_TIMER_ACTIVE}" || {
            dockerError "TLS 调度恢复失败，请检查: ${snapshot}"
            return 1
        }
    fi
    dockerRemoveManagedTree "${root}" "${snapshot}" || return 1
    DOCKER_RENEWAL_SCHEDULE_SNAPSHOT=
    DOCKER_RENEWAL_SCHEDULE_CHANGED=0
}

dockerRenewalScheduleCommit() {
    if [[ -n "${DOCKER_RENEWAL_STAGE:-}" && "${DOCKER_RENEWAL_SWITCHED:-0}" == 1 ]]; then
        # 输入与调度同时结束恢复窗口，TERM 不能只回退其中一份。
        DOCKER_RENEWAL_SCHEDULE_CHANGED=0 DOCKER_RENEWAL_SWITCHED=0
    else
        DOCKER_RENEWAL_SCHEDULE_CHANGED=0
    fi
    dockerRenewalScheduleInterrupted
}

dockerRenewalScheduleApply() {
    local action=$1 root cli bashPath unitDir file fragment snapshot= cronText= cronLine line
    local systemdReady=0 cronReady=0 timerEnabled=0 timerActive=0 haveUnits=0 haveCron=0
    [[ -z "${DOCKER_RENEWAL_SCHEDULE_SNAPSHOT:-}" ]] || return 1
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
    cronLine="17 3 * * * PADM_DOCKER_INSTALL_DIR=${root} ${bashPath} ${cli} acme auto-renew # padm-docker TLS 自动续期 root=${root}"
    # 全部来源先确认归本部署所有，不能覆盖同名外部 unit 或其它 root 的任务。
    while IFS= read -r line; do
        [[ "${line}" == *'# padm-docker TLS 自动续期'* ]] || continue
        [[ "${line}" == "${cronLine}" ]] || return 1
        haveCron=1
    done <<<"${cronText}"
    if [[ -e "${unitDir}" || -L "${unitDir}" ]]; then
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" &&
            "$(cd -- "${unitDir}" && pwd -P)" == "${unitDir}" ]] || return 1
    fi
    for file in padm-docker-renewal.service padm-docker-renewal.timer; do
        [[ ! -L "${unitDir}/${file}" ]] || return 1
        if [[ -e "${unitDir}/${file}" ]]; then
            [[ -f "${unitDir}/${file}" && -O "${unitDir}/${file}" ]] &&
                grep -qxF '# padm-docker TLS 自动续期' "${unitDir}/${file}" &&
                grep -qxF "# padm-docker root=${root}" "${unitDir}/${file}" || return 1
            if [[ "${file}" == *.service ]]; then
                grep -qxF "Environment=PADM_DOCKER_INSTALL_DIR=${root}" "${unitDir}/${file}" &&
                    grep -qxF "ExecStart=${bashPath} ${cli} acme auto-renew" "${unitDir}/${file}" || return 1
            else
                grep -qxF 'Unit=padm-docker-renewal.service' "${unitDir}/${file}" || return 1
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
            dockerError 'TLS 自动续期需要正在运行的 systemd 或 cron'
            return 1
        fi
    elif [[ "${haveUnits}" == 0 && "${haveCron}" == 0 ]]; then
        return 0
    fi
    [[ "${haveUnits}" == 0 ]] || command -v systemctl >/dev/null 2>&1 || return 1
    if [[ -f "${unitDir}/padm-docker-renewal.timer" ]]; then
        if systemctl is-enabled --quiet padm-docker-renewal.timer; then timerEnabled=1; fi
        if [[ "${systemdReady}" == 1 ]] && systemctl is-active --quiet padm-docker-renewal.timer; then timerActive=1; fi
    fi
    dockerManagedPathIsSafe "${root}" "${root}/locks" &&
        [[ -d "${root}/locks" && ! -L "${root}/locks" && -O "${root}/locks" ]] || return 1
    snapshot=$(mktemp -d "${root}/locks/renewal-schedule.XXXXXX") || return 1
    DOCKER_RENEWAL_SCHEDULE_SNAPSHOT=${snapshot}
    DOCKER_RENEWAL_SCHEDULE_UNIT_DIR=${unitDir}
    DOCKER_RENEWAL_SCHEDULE_SYSTEMD_READY=${systemdReady}
    DOCKER_RENEWAL_SCHEDULE_TIMER_ENABLED=${timerEnabled}
    DOCKER_RENEWAL_SCHEDULE_TIMER_ACTIVE=${timerActive}
    DOCKER_RENEWAL_SCHEDULE_CHANGED=0
    chmod 0700 "${snapshot}" || return 1
    for file in padm-docker-renewal.service padm-docker-renewal.timer; do
        [[ ! -f "${unitDir}/${file}" ]] || cp -- "${unitDir}/${file}" "${snapshot}/${file}" || return 1
    done
    [[ "${haveCron}" == 0 && ( "${action}" == remove || "${systemdReady}" == 1 ) ]] ||
        printf '%s\n' "${cronText}" >"${snapshot}/crontab" || return 1
    DOCKER_RENEWAL_SCHEDULE_CHANGED=1
    if (
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [[ "${haveUnits}" == 1 ]]; then
        if [[ "${systemdReady}" == 1 ]]; then
            [[ ! -f "${unitDir}/padm-docker-renewal.timer" ]] ||
                systemctl disable --now padm-docker-renewal.timer >/dev/null || exit 1
            [[ ! -f "${unitDir}/padm-docker-renewal.service" ]] ||
                systemctl stop padm-docker-renewal.service >/dev/null || exit 1
        else
            [[ ! -f "${unitDir}/padm-docker-renewal.timer" ]] ||
                systemctl disable padm-docker-renewal.timer >/dev/null || exit 1
        fi
    fi
    if [[ "${haveCron}" == 1 ]]; then
        printf '%s\n' "${cronText}" | awk -v owned="${cronLine}" '$0 != owned' | crontab - || exit 1
    fi
    if [[ "${action}" == install && "${systemdReady}" == 1 ]]; then
        cat >"${snapshot}/new.service" <<EOF
# padm-docker TLS 自动续期
# padm-docker root=${root}
[Unit]
Description=padm Docker TLS renewal
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} acme auto-renew
TimeoutStartSec=1800
EOF
        cat >"${snapshot}/new.timer" <<EOF
# padm-docker TLS 自动续期
# padm-docker root=${root}
[Unit]
Description=Renew padm Docker TLS daily
[Timer]
OnCalendar=*-*-* 03:17:00
RandomizedDelaySec=300
Persistent=true
Unit=padm-docker-renewal.service
[Install]
WantedBy=timers.target
EOF
        install -m 0644 "${snapshot}/new.service" "${unitDir}/padm-docker-renewal.service" &&
            install -m 0644 "${snapshot}/new.timer" "${unitDir}/padm-docker-renewal.timer" &&
            systemctl daemon-reload &&
            systemctl enable --now padm-docker-renewal.timer >/dev/null || exit 1
    else
        rm -f -- "${unitDir}/padm-docker-renewal.service" "${unitDir}/padm-docker-renewal.timer" || exit 1
        [[ "${systemdReady}" == 0 || "${haveUnits}" == 0 ]] || systemctl daemon-reload || exit 1
        if [[ "${action}" == install ]]; then
            { printf '%s\n' "${cronText}" | awk -v owned="${cronLine}" '$0 != owned'; printf '%s\n' "${cronLine}"; } | crontab - || exit 1
        fi
    fi
    ); then
        if [[ -n "${DOCKER_RENEWAL_STAGE:-}" && "${DOCKER_RENEWAL_SWITCHED:-0}" == 1 ]]; then
            return 0
        fi
        dockerRenewalScheduleCommit
    else
        dockerRenewalScheduleInterrupted || true
        return 1
    fi
}

dockerRenewalScheduleInstall() {
    local root
    root=$(dockerInstallRoot) || return 1
    if [[ ! -e "${root}/secrets/renewal" && ! -L "${root}/secrets/renewal" ]]; then
        dockerRenewalScheduleRemove
        return $?
    fi
    dockerTrafficSafePath "${root}" "${root}/secrets/renewal" &&
        dockerRenewalRegistryValidate "${root}/secrets/renewal" || return 1
    if dockerRenewalEnabled "${root}/secrets/renewal"; then
        dockerRenewalScheduleApply install
    else
        dockerRenewalScheduleRemove
    fi
}

dockerRenewalScheduleRemove() {
    local unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system} content
    if [[ ! -e "${unitDir}/padm-docker-renewal.service" && ! -L "${unitDir}/padm-docker-renewal.service" &&
        ! -e "${unitDir}/padm-docker-renewal.timer" && ! -L "${unitDir}/padm-docker-renewal.timer" ]]; then
        command -v crontab >/dev/null 2>&1 || return 0
        content=$(dockerTrafficReadCrontab) || return 1
        [[ "${content}" == *'# padm-docker TLS 自动续期'* ]] || return 0
    fi
    dockerRenewalScheduleApply remove
}

dockerTrafficBeforeChange() {
    local root cores core
    root=$(dockerInstallRoot) || return 0
    [[ -f "${root}/deployment.json" ]] || return 0
    cores=$(dockerTrafficCore) || return 0
    while IFS= read -r core; do
        if [[ -f "${root}/config/${core}/users.base" ]]; then
            dockerTrafficSnapshot || dockerError '变更前采集失败，已保留历史流量；本次未采集的增量无法恢复'
            break
        fi
    done <<<"${cores}"
    return 0
}

dockerTrafficCommand() {
    local action=${1:-show} bytes
    [[ "$#" -eq 0 ]] || shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    case "${action}" in
    show|collect)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${action}" == show ]]; then dockerTrafficShow; else dockerTrafficCollect; fi
        ;;
    limit)
        [[ "$#" -eq 2 && "$2" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || return "${PADM_DOCKER_RC_USAGE}"
        bytes=$(jq -en --arg value "$2" '($value | tonumber) * 1073741824 | floor | select(. <= 9007199254740991)') ||
            return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficSetLimit "$1" "${bytes}"
        ;;
    reset)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficReset "$1"
        ;;
    *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
}

dockerPrepareInstallSource() {
    local sourceRoot=$1 requestedRef=${2:-}
    if [[ -z "${sourceRoot}" && -n "${requestedRef}" ]]; then
        dockerEntryFetchBundle "${requestedRef}" || return 1
        sourceRoot=${DOCKER_ENTRY_SOURCE_DIR}
        requestedRef=${DOCKER_ENTRY_FETCHED_REF}
    fi
    [[ -n "${sourceRoot}" ]] || sourceRoot=${DOCKER_ENTRY_SOURCE_DIR}
    sourceRoot=$(cd -- "${sourceRoot}" 2>/dev/null && pwd -P) || return 1
    dockerBundleSourceIsComplete "${sourceRoot}" || return 1
    DOCKER_INSTALL_SOURCE_ROOT=${sourceRoot}
    DOCKER_INSTALL_SOURCE_REF=${requestedRef}
}

dockerInstallCommand() {
    local sourceRoot= requestedRef= root
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --no-menu)
            DOCKER_MENU_AFTER_INSTALL=0
            shift
            ;;
        --source)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            sourceRoot=$2
            shift 2
            ;;
        --ref)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            requestedRef=$2
            shift 2
            ;;
        *)
            dockerUsage
            return "${PADM_DOCKER_RC_USAGE}"
            ;;
        esac
    done
    if [[ -n "${sourceRoot}" && "${requestedRef}" == "latest" ]]; then
        dockerError '--source 不能与 --ref latest 同时使用'
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    if [[ -n "${requestedRef}" && "${requestedRef}" != "latest" ]] &&
        ! dockerBundleRefIsValid "${requestedRef}"; then
        dockerError '--ref 必须是 40 位小写 commit SHA 或 latest'
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerAssertInstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerPrepareInstallSource "${sourceRoot}" "${requestedRef}" || {
        dockerError '无法准备 Docker 控制 bundle'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    dockerAcquireDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerAssertInstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerInitializeStateRoot || {
        dockerError 'Docker 状态目录初始化失败'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerInstallBundle "${DOCKER_INSTALL_SOURCE_ROOT}" "${DOCKER_INSTALL_SOURCE_REF}" || {
        dockerError 'Docker 控制 bundle 校验或切换失败'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    dockerInstallCli || {
        dockerError 'padm-docker 命令安装失败'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 控制骨架已安装: %s\n' "${root}"
}

dockerDeploymentState() {
    local state
    state=$(padmDockerDeploymentState) || return 1
    printf '%s\n' "${state}"
}

dockerRequireInstalledBundle() {
    local state marker root
    root=$(dockerInstallRoot) || return 1
    state=$(dockerDeploymentState) || return 1
    case "${state}" in
    installed | active) ;;
    absent)
        dockerError 'Docker 版 padm 尚未安装'
        return 1
        ;;
    *)
        dockerError 'Docker 版 padm 状态异常，已拒绝操作'
        return 1
        ;;
    esac
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    [[ "${marker}" == "docker" ]] || return 1
    dockerCurrentBundlePath >/dev/null || {
        dockerError '当前 Docker 控制 bundle 缺失或校验失败'
        return 1
    }
}

dockerComposeFile() {
    local root composeFile deploymentFile
    root=$(dockerInstallRoot) || return 1
    composeFile="${root}/compose.json"
    deploymentFile="${root}/deployment.json"
    [[ -f "${composeFile}" && ! -L "${composeFile}" ]] || return 1
    padmDockerDeploymentIdentityValid "${deploymentFile}" || return 1
    printf '%s\n' "${composeFile}"
}

dockerComposeRun() {
    local composeFile composeDir root profile
    local -a commandArgs=() extraArgs=()
    composeFile=$(dockerComposeFile) || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    case "${1:-}" in
    up|restart|run|exec)
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]] || {
        dockerError 'images.env 缺失或不安全'
        return "${PADM_DOCKER_RC_STATE}"
    }
    composeDir=$(dirname -- "${composeFile}")
    commandArgs=(docker compose --project-name "${PADM_DOCKER_PROJECT}"
        --project-directory "${composeDir}" --env-file "${root}/images.env"
        --file "${composeFile}")
    while IFS= read -r profile; do
        [[ -n "${profile}" ]] || continue
        commandArgs+=(--profile "${profile}")
    done < <(jq -r '.compose.profiles[]' "${root}/deployment.json")
    case "${1:-}" in
    up|down) extraArgs+=(--remove-orphans) ;;
    logs)
        # 日志只读且可能持续跟随，不能长期阻塞管理命令或流量采集。
        dockerReleaseDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
        ;;
    esac
    # 管理动作不接收交互输入，避免 Compose 吞掉调用方循环中的下一项。
    "${commandArgs[@]}" "$@" "${extraArgs[@]}" </dev/null || {
        dockerError 'Docker Compose 操作失败'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
}

dockerLockInstalledDeployment() {
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    dockerAcquireDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
}

dockerStatusCommand() {
    local state bundlePath ref root
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${state}" == "absent" ]]; then
        printf 'state=absent\n'
        return 0
    fi
    [[ "${state}" != "ambiguous" ]] || {
        dockerError 'state=ambiguous'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerLockInstalledDeployment || return $?
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
    ref=$(<"${bundlePath}/${PADM_DOCKER_BUNDLE_REF}")
    printf 'state=%s\nbundle_ref=%s\n' "${state}" "${ref}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if ! dockerComposeFile >/dev/null; then
        printf 'configured=no\n'
        return 0
    fi
    printf 'configured=yes\nrelease=%s\nprofiles=%s\n' \
        "$(jq -r '.padm_version' "${root}/deployment.json")" \
        "$(jq -r '.compose.profiles | join(",")' "${root}/deployment.json")"
    dockerComposeRun ps
}

dockerLifecycleCommand() {
    local operation=$1 root
    shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    case "${operation}" in
    up|restart)
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    case "${operation}" in
    up)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficScheduleInstall && dockerRenewalScheduleInstall && dockerComposeRun up -d
        ;;
    down)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
        dockerTrafficBeforeChange
        dockerComposeRun down && dockerTrafficScheduleRemove
        ;;
    restart)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficBeforeChange
        dockerTrafficScheduleInstall && dockerRenewalScheduleInstall && dockerComposeRun restart
        ;;
    logs) dockerComposeRun logs "$@" ;;
    esac
}

dockerPullManifestImages() {
    local name reference
    for name in "${PADM_DOCKER_MANIFEST_IMAGE_NAMES[@]}"; do
        reference=$(dockerManifestImageReference "${name}") || return 1
        docker pull "${reference}" || {
            dockerError "镜像拉取失败: ${reference}"
            return 1
        }
    done
}

dockerReleaseCommand() {
    local manifest= bundle= controlBundle=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" ||
        return "${PADM_DOCKER_RC_MANIFEST}"
    # 仅校验候选控制脚本，不切换当前 bundle；标准输出只保留可信 JSON。
    dockerStageReleaseBundle >&2 || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages >&2 || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerManifestConfigurationInputs || return "${PADM_DOCKER_RC_MANIFEST}"
}

dockerUpdateCommand() {
    local manifest= bundle= controlBundle= candidate backup root
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            manifest=$2
            shift 2
            ;;
        --bundle)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            bundle=$2
            shift 2
            ;;
        --control-bundle)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            controlBundle=$2
            shift 2
            ;;
        *)
            dockerUsage
            return "${PADM_DOCKER_RC_USAGE}"
            ;;
        esac
    done
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" ||
        return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle || {
        dockerError '无法准备 release 控制 bundle，现有部署未切换'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    dockerRenewalBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
    dockerTrafficBeforeChange
    dockerCreateUpdateCandidate || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerValidateUpdateCandidate "${candidate}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerBackupConfiguration update || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerActivateStagedBundle ||
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall ||
        ! dockerRenewalScheduleInstall; then
        dockerError '控制脚本切换、启动或健康检查失败，正在恢复旧配置和控制脚本'
        if ! dockerRestoreConfiguration; then
            dockerError "旧版本恢复失败，请检查备份: ${backup}"
        fi
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_STREAM_TRANSITION=0
    dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 镜像和控制脚本更新已提交，回滚快照: %s\n' "${backup}"
}

dockerConfigurationBackupAllowed() {
    case "$1" in
    deployment.json|deployment.previous.json|images.env|compose.json|config/xray|config/sing-box|config/nginx|config/net|config/spec.json|data/subscription|secrets/tls|data/acme) return 0 ;;
    *) return 1 ;;
    esac
}

dockerValidateConfigurationBackup() {
    local backup=$1 root relative entry bundlePath
    root=$(dockerInstallRoot) || return 1
    dockerManagedPathIsSafe "${root}" "${backup}" || return 1
    [[ "${backup}" == "${root%/}/backups/"* && -d "${backup}" && ! -L "${backup}" && -O "${backup}" ]] || return 1
    [[ -f "${backup}/present" && ! -L "${backup}/present" && -O "${backup}/present" ]] || return 1
    [[ -z "$(find "${backup}" -type l -print -quit 2>/dev/null)" ]] || return 1
    if [[ -e "${backup}/bundle.target" ]]; then
        [[ -f "${backup}/bundle.target" && -O "${backup}/bundle.target" ]] || return 1
        dockerBundlePathForTarget "$(<"${backup}/bundle.target")" >/dev/null || return 1
    fi
    while IFS= read -r relative; do
        dockerConfigurationBackupAllowed "${relative}" || return 1
        [[ -n "${relative}" && -e "${backup}/${relative}" && ! -L "${backup}/${relative}" &&
            -O "${backup}/${relative}" ]] || return 1
    done <"${backup}/present"
    [[ -z "$(sort "${backup}/present" | uniq -d)" ]] || return 1
    while IFS= read -r entry; do
        [[ "${entry}" == "${backup}/present" || "${entry}" == "${backup}/bundle.target" ||
            "${entry}" == "${backup}/deployment.json" ||
            "${entry}" == "${backup}/deployment.previous.json" || "${entry}" == "${backup}/images.env" ||
            "${entry}" == "${backup}/compose.json" || "${entry}" == "${backup}/config" ||
            "${entry}" == "${backup}/data" || "${entry}" == "${backup}/secrets" ||
            "${entry}" == "${backup}/secrets/tls" || "${entry}" == "${backup}/secrets/tls/"* ||
            "${entry}" == "${backup}/config/"* ||
            "${entry}" == "${backup}/data/"* ]] || return 1
        [[ -O "${entry}" ]] || return 1
    done < <(find "${backup}" -mindepth 1 -print)
    grep -qxF deployment.json "${backup}/present" || return 1
    grep -qxF compose.json "${backup}/present" || return 1
    grep -qxF images.env "${backup}/present" || return 1
    dockerDeploymentFileValidate "${backup}/deployment.json" || return 1
    if [[ -e "${backup}/config/spec.json" || -L "${backup}/config/spec.json" ]]; then
        grep -qxF config/spec.json "${backup}/present" || return 1
        dockerManagedSpecMatchesDeployment "${backup}/config/spec.json" \
            "${backup}/deployment.json" "${backup}/images.env" || return 1
        if [[ -f "${backup}/bundle.target" ]]; then
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") || return 1
        else
            bundlePath=$(dockerCurrentBundlePath) || return 1
        fi
        dockerBundleSupportsSpec "${bundlePath}" "${backup}/config/spec.json" || return 1
    fi
}

dockerLatestUpdateBackup() {
    local root backup= candidate
    root=$(dockerInstallRoot) || return 1
    while IFS= read -r candidate; do
        [[ -d "${candidate}" && ! -L "${candidate}" && -O "${candidate}" ]] || continue
        dockerValidateConfigurationBackup "${candidate}" || continue
        if [[ -z "${backup}" ]] || [[ "$(stat -c %Y "${candidate}" 2>/dev/null || printf 0)" -gt \
            "$(stat -c %Y "${backup}" 2>/dev/null || printf 0)" ]]; then
            backup=${candidate}
        fi
    done < <(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d -name 'update.*' -print 2>/dev/null)
    [[ -n "${backup}" ]] || return 1
    printf '%s\n' "${backup}"
}

dockerTrafficRollbackCheck() {
    local backup=$1 root version
    jq -e '[.core.type, .core.secondary_type] | index("sing-box") != null' "${backup}/deployment.json" >/dev/null ||
        return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -f "${root}/data/traffic/state.json" || -f "${root}/config/sing-box/users.base" ||
        -f "${backup}/config/sing-box/users.base" ]]; then
        version=$(dockerCandidateCompose "${backup}" run --rm --no-deps sing-box version) || return 1
        grep -Eq '(^|[^[:alnum:]_])with_v2ray_api([^[:alnum:]_]|$)' <<<"${version}" || {
            dockerError '回滚目标 sing-box 不支持用户统计，无法保留当前采集与额度管理；现有部署未停止'
            return 1
        }
    fi
}

dockerRollbackCommand() {
    local backup currentBackup bundlePath root
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，无法回滚'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    backup=$(dockerLatestUpdateBackup) || {
        dockerError '没有可用的更新回滚快照'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${backup}/config/spec.json" "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/secrets/renewal" &&
        dockerRenewalRegistryValidate "${root}/secrets/renewal" || return "${PADM_DOCKER_RC_STATE}"
    if dockerRenewalEnabled "${root}/secrets/renewal"; then
        if [[ -e "${backup}/bundle.target" || -L "${backup}/bundle.target" ]]; then
            [[ -f "${backup}/bundle.target" && ! -L "${backup}/bundle.target" &&
                -O "${backup}/bundle.target" ]] || return "${PADM_DOCKER_RC_BUNDLE}"
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") || return "${PADM_DOCKER_RC_BUNDLE}"
        else
            bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
        fi
        dockerRenewalBundleCheck "${bundlePath}" || return "${PADM_DOCKER_RC_BUNDLE}"
    fi
    dockerTrafficRollbackCheck "${backup}" || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck "$(jq -r '.core.type, (.core.secondary_type // empty)' "${backup}/deployment.json")" ||
        return "${PADM_DOCKER_RC_HOST}"
    dockerTrafficBeforeChange
    dockerBackupConfiguration rollback || return "${PADM_DOCKER_RC_STATE}"
    currentBackup=${DOCKER_CONFIG_BACKUP}
    DOCKER_CONFIG_BACKUP=${backup}
    DOCKER_CONFIG_SWITCHED=1
    if dockerRestoreConfiguration && dockerTrafficScheduleInstall; then
        DOCKER_CONFIG_BACKUP=${currentBackup}
        printf 'Docker 已回滚到: %s\n' "${backup}"
        return 0
    fi
    dockerError '回滚失败，正在尝试恢复当前版本'
    DOCKER_CONFIG_BACKUP=${currentBackup}
    DOCKER_CONFIG_SWITCHED=1
    dockerRestoreConfiguration && dockerTrafficScheduleInstall ||
        dockerError "当前版本或采集调度恢复失败，请检查备份: ${currentBackup}"
    return "${PADM_DOCKER_RC_COMPOSE}"
}

dockerRemoveRecordedImages() {
    local root name key reference expectedDigest actualDigest
    local -A keys=(
        [xray]=PADM_XRAY_IMAGE [sing-box]=PADM_SINGBOX_IMAGE [nginx]=PADM_NGINX_IMAGE
        [ops]=PADM_OPS_IMAGE [net]=PADM_NET_IMAGE
    )
    root=$(dockerInstallRoot) || return 1
    dockerDeploymentFileValidate "${root}/deployment.json" || return 1
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" && -O "${root}/images.env" ]] || return 1
    for name in "${PADM_DOCKER_MANIFEST_IMAGE_NAMES[@]}"; do
        key=${keys[${name}]}
        reference=$(sed -n "s/^${key}=//p" "${root}/images.env") || return 1
        [[ "$(printf '%s\n' "${reference}" | wc -l | tr -d '[:space:]')" == "1" ]] || return 1
        [[ "${reference}" =~ ^[a-z0-9][a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] || return 1
        expectedDigest=$(jq -er --arg name "${name}" '.images[$name].index_digest' "${root}/deployment.json") || return 1
        actualDigest=${reference##*@}
        [[ "${actualDigest}" == "${expectedDigest}" ]] || return 1
        docker image rm "${reference}" || return 1
    done
}

dockerPurgeStateRoot() {
    local root marker parent resolved
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${root}" || return 1
    [[ -d "${root}" && ! -L "${root}" && -O "${root}" ]] || return 1
    parent=$(cd -- "$(dirname -- "${root}")" 2>/dev/null && pwd -P) || return 1
    resolved="${parent}/$(basename -- "${root}")"
    [[ "${resolved}" == "${root}" ]] || return 1
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    [[ "${marker}" == docker && -f "${root}/mode" && ! -L "${root}/mode" && -O "${root}/mode" ]] || return 1
    rm -rf -- "${root}"
}

dockerUninstallCommand() {
    local state removeImages=0 purge=0 confirm= backup root
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --remove-images) removeImages=1; shift ;;
        --purge) purge=1; shift ;;
        --confirm)
            [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
            confirm=$2
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    if ((purge)); then
        [[ "${confirm}" == 'PADM-DOCKER-PURGE' ]] || {
            dockerError 'purge 必须使用 --confirm PADM-DOCKER-PURGE'
            return "${PADM_DOCKER_RC_USAGE}"
        }
    elif [[ -n "${confirm}" ]]; then
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${state}" == "absent" ]]; then
        printf 'Docker 版 padm 未安装，无需卸载\n'
        return 0
    fi
    dockerLockInstalledDeployment || return $?
    dockerTrafficBeforeChange
    if ((purge)); then
        dockerBackupConfiguration uninstall || return "${PADM_DOCKER_RC_STATE}"
        backup=${DOCKER_CONFIG_BACKUP}
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/compose.json" || -e "${root}/deployment.json" || -e "${root}/images.env" ]]; then
        dockerComposeFile >/dev/null || {
            dockerError 'Docker Compose 状态不完整，已拒绝卸载'
            return "${PADM_DOCKER_RC_STATE}"
        }
        dockerComposeRun down || return $?
    fi
    dockerTrafficScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerRemoveCli || return "${PADM_DOCKER_RC_STATE}"
    if ((removeImages)); then
        dockerRemoveRecordedImages || return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    if ((purge)); then
        dockerPurgeStateRoot || {
            dockerError "purge 失败；卸载备份仍保留: ${backup}"
            return "${PADM_DOCKER_RC_STATE}"
        }
        printf 'Docker 状态、控制 bundle、配置和数据已清理\n'
    else
        printf 'Docker 控制命令已卸载；状态、配置、数据、备份和镜像均已保留\n'
    fi
}

dockerCommandInterrupted() {
    local status=$1
    dockerRenewalScheduleInterrupted || true
    if declare -F dockerRenewalInterrupted >/dev/null 2>&1; then
        dockerRenewalInterrupted || true
    fi
    if declare -F dockerConfigurationInterrupted >/dev/null 2>&1; then
        dockerConfigurationInterrupted || true
    fi
    dockerSetupCleanup || true
    dockerReleaseDeploymentLock || true
    dockerCleanupStagedBundle || true
    dockerManifestCleanup || true
    dockerEntryCleanup || true
    exit "${status}"
}

dockerMain() {
    local command=${1:-menu} status
    [[ "$#" -gt 0 ]] && shift
    # 菜单不持有部署锁，各操作由独立 CLI 进程完成清理。
    if [[ "${command}" == menu ]]; then
        dockerMenu "$@"
        return $?
    fi
    trap 'dockerCommandInterrupted 130' INT
    trap 'dockerCommandInterrupted 143' TERM
    case "${command}" in
    install) dockerInstallCommand "$@" ;;
    release) dockerReleaseCommand "$@" ;;
    setup) dockerSetupCommand "$@" ;;
    edit) dockerEditCommand "$@" ;;
    protocol) dockerProtocolCommand "$@" ;;
    configure) dockerConfigureCommand "$@" ;;
    tls)
        case "${1:-}" in
        install) shift; dockerTlsInstallCommand "$@" ;;
        validate) shift; dockerTlsValidateCommand "$@" ;;
        manage) shift; dockerTlsManageCommand "$@" ;;
        *) status=${PADM_DOCKER_RC_USAGE} ;;
        esac
        ;;
    acme)
        case "${1:-}" in
        schedule) shift; dockerRenewalCommand "$@" ;;
        auto-renew) shift; dockerRenewalCommand run "$@" ;;
        *) dockerAcmeCommand "$@" ;;
        esac
        ;;
    validate) dockerValidateInstalledCommand "$@" ;;
    status) dockerStatusCommand "$@" ;;
    traffic) dockerTrafficCommand "$@" ;;
    up | down | restart | logs) dockerLifecycleCommand "${command}" "$@" ;;
    update) dockerUpdateCommand "$@" ;;
    rollback) dockerRollbackCommand "$@" ;;
    uninstall) dockerUninstallCommand "$@" ;;
    help | --help | -h)
        dockerUsage
        status=0
        ;;
    *)
        dockerUsage
        status=${PADM_DOCKER_RC_USAGE}
        ;;
    esac
    status=${status:-$?}
    dockerRenewalScheduleInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    if declare -F dockerRenewalInterrupted >/dev/null 2>&1; then
        dockerRenewalInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    fi
    if [[ "${DOCKER_TLS_SWITCHED:-0}" == 1 ]]; then
        dockerRestoreTlsFiles || dockerError "TLS 事务恢复失败，请检查备份: ${DOCKER_TLS_BACKUP:-}"
        [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    fi
    dockerCleanupTlsCandidate || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerSetupCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerReleaseDeploymentLock || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_LOCK}
    dockerCleanupStagedBundle || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    dockerManifestCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_MANIFEST}
    if [[ "${command}" != install || "${status}" -ne 0 || "${DOCKER_MENU_AFTER_INSTALL:-0}" -ne 1 ]]; then
        dockerEntryCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    fi
    trap - INT TERM
    return "${status}"
}
