#!/usr/bin/env bash

if [[ "${PADM_DOCKER_LIFECYCLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_LIFECYCLE_LOADED=1

dockerUsage() {
    cat >&2 <<'EOF'
用法:
  install-docker.sh install [--source <目录>] [--ref <commit|latest>]  # 缺 Docker 时询问是否安装
  padm-docker configure --spec <JSON 文件>
  padm-docker tls install --domain <域名> --cert <文件> --key <文件> [--ops-image <tag@digest>]
  padm-docker acme <issue|renew> --domain <域名> --email <邮箱> --dns <dns_*> --credentials <文件> [--ops-image <tag@digest>]
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
    local core=${1:-} root
    if [[ -z "${core}" ]]; then
        root=$(dockerInstallRoot) || return 1
        core=$(jq -er '.core.type' "${root}/deployment.json") || return 1
    fi
    if [[ "${core}" == sing-box ]]; then
        dockerRequireCommand nsenter && dockerRequireCommand curl || return 1
        curl --version | grep -q 'HTTP2' || {
            dockerError 'sing-box 自动流量采集需要支持 HTTP/2 的宿主 curl'
            return 1
        }
    fi
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

dockerTrafficBeforeChange() {
    local root core
    root=$(dockerInstallRoot) || return 0
    [[ -f "${root}/deployment.json" ]] || return 0
    core=$(jq -r '.core.type' "${root}/deployment.json") || return 0
    if [[ -f "${root}/config/${core}/users.base" ]]; then
        dockerTrafficSnapshot || dockerError '变更前采集失败，已保留历史流量；本次未采集的增量无法恢复'
    fi
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
    esac
    "${commandArgs[@]}" "$@" "${extraArgs[@]}" || {
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
    local operation=$1
    shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    case "${operation}" in
    up)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficScheduleInstall && dockerComposeRun up -d
        ;;
    down)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficBeforeChange
        dockerComposeRun down && dockerTrafficScheduleRemove
        ;;
    restart)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficBeforeChange
        dockerTrafficScheduleInstall && dockerComposeRun restart
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

dockerUpdateCommand() {
    local manifest= bundle= controlBundle= candidate backup
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
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" ||
        return "${PADM_DOCKER_RC_MANIFEST}"
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
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall; then
        dockerError '更新启动或健康检查失败，正在恢复旧配置'
        if ! dockerRestoreConfiguration; then
            dockerError "旧版本恢复失败，请检查备份: ${backup}"
        fi
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    DOCKER_CONFIG_SWITCHED=0
    dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 更新已提交，回滚快照: %s\n' "${backup}"
}

dockerConfigurationBackupAllowed() {
    case "$1" in
    deployment.json|deployment.previous.json|images.env|compose.json|config/xray|config/sing-box|config/nginx|config/net|data/subscription) return 0 ;;
    *) return 1 ;;
    esac
}

dockerValidateConfigurationBackup() {
    local backup=$1 root relative entry
    root=$(dockerInstallRoot) || return 1
    dockerManagedPathIsSafe "${root}" "${backup}" || return 1
    [[ "${backup}" == "${root%/}/backups/"* && -d "${backup}" && ! -L "${backup}" && -O "${backup}" ]] || return 1
    [[ -f "${backup}/present" && ! -L "${backup}/present" && -O "${backup}/present" ]] || return 1
    [[ -z "$(find "${backup}" -type l -print -quit 2>/dev/null)" ]] || return 1
    while IFS= read -r relative; do
        dockerConfigurationBackupAllowed "${relative}" || return 1
        [[ -n "${relative}" && -e "${backup}/${relative}" && ! -L "${backup}/${relative}" &&
            -O "${backup}/${relative}" ]] || return 1
    done <"${backup}/present"
    [[ -z "$(sort "${backup}/present" | uniq -d)" ]] || return 1
    while IFS= read -r entry; do
        [[ "${entry}" == "${backup}/present" || "${entry}" == "${backup}/deployment.json" ||
            "${entry}" == "${backup}/deployment.previous.json" || "${entry}" == "${backup}/images.env" ||
            "${entry}" == "${backup}/compose.json" || "${entry}" == "${backup}/config" ||
            "${entry}" == "${backup}/data" || "${entry}" == "${backup}/config/"* ||
            "${entry}" == "${backup}/data/"* ]] || return 1
        [[ -O "${entry}" ]] || return 1
    done < <(find "${backup}" -mindepth 1 -print)
    grep -qxF deployment.json "${backup}/present" || return 1
    grep -qxF compose.json "${backup}/present" || return 1
    grep -qxF images.env "${backup}/present" || return 1
    dockerDeploymentFileValidate "${backup}/deployment.json"
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
    [[ "$(jq -r '.core.type' "${backup}/deployment.json")" == sing-box ]] || return 0
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
    local backup currentBackup
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
    dockerTrafficRollbackCheck "${backup}" || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck "$(jq -r '.core.type' "${backup}/deployment.json")" || return "${PADM_DOCKER_RC_HOST}"
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
    if declare -F dockerConfigurationInterrupted >/dev/null 2>&1; then
        dockerConfigurationInterrupted || true
    fi
    dockerReleaseDeploymentLock || true
    dockerManifestCleanup || true
    dockerEntryCleanup || true
    exit "${status}"
}

dockerMain() {
    local command=${1:-install} status
    [[ "$#" -gt 0 ]] && shift
    trap 'dockerCommandInterrupted 130' INT
    trap 'dockerCommandInterrupted 143' TERM
    case "${command}" in
    install) dockerInstallCommand "$@" ;;
    configure) dockerConfigureCommand "$@" ;;
    tls)
        if [[ "${1:-}" == "install" ]]; then
            shift
            dockerTlsInstallCommand "$@"
        else
            status=${PADM_DOCKER_RC_USAGE}
        fi
        ;;
    acme) dockerAcmeCommand "$@" ;;
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
    dockerReleaseDeploymentLock || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_LOCK}
    dockerManifestCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_MANIFEST}
    dockerEntryCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    trap - INT TERM
    return "${status}"
}
