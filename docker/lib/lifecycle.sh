#!/usr/bin/env bash

if [[ "${PADM_DOCKER_LIFECYCLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_LIFECYCLE_LOADED=1

dockerUsage() {
    cat >&2 <<'EOF'
用法:
  install-docker.sh install [--source <目录>] [--ref <commit|latest>]
  padm-docker status
  padm-docker up
  padm-docker down
  padm-docker restart
  padm-docker logs [Compose logs 参数]
  padm-docker uninstall
EOF
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
    local bundlePath composeFile
    bundlePath=$(dockerCurrentBundlePath) || return 1
    composeFile="${bundlePath}/docker/compose.yaml"
    [[ -f "${composeFile}" && ! -L "${composeFile}" ]] || return 1
    printf '%s\n' "${composeFile}"
}

dockerComposeRun() {
    local composeFile composeDir
    composeFile=$(dockerComposeFile) || {
        dockerError 'Compose 配置尚未安装；该运行能力将在阶段 2 提供'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    composeDir=$(dirname -- "${composeFile}")
    docker compose --project-name "${PADM_DOCKER_PROJECT}" \
        --project-directory "${composeDir}" --file "${composeFile}" "$@" || {
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
    local state bundlePath ref
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
    if ! dockerComposeFile >/dev/null; then
        printf 'compose=unavailable\n'
        dockerError 'Compose 配置尚未安装；服务状态不可用'
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    printf 'compose=available\n'
    dockerComposeRun ps
}

dockerLifecycleCommand() {
    local operation=$1
    shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    case "${operation}" in
    up)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerComposeRun up -d
        ;;
    down)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerComposeRun down
        ;;
    restart)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerComposeRun restart
        ;;
    logs) dockerComposeRun logs "$@" ;;
    esac
}

dockerUninstallCommand() {
    local state
    [[ "$#" -eq 0 ]] || {
        dockerError '阶段 1 的 uninstall 不支持 purge 或镜像删除参数'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${state}" == "absent" ]]; then
        printf 'Docker 版 padm 未安装，无需卸载\n'
        return 0
    fi
    dockerLockInstalledDeployment || return $?
    if dockerComposeFile >/dev/null; then
        dockerComposeRun down || return $?
    fi
    dockerRemoveCli || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 控制命令已卸载；状态、bundle、配置和数据均已保留\n'
}

dockerCommandInterrupted() {
    local status=$1
    dockerReleaseDeploymentLock || true
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
    status) dockerStatusCommand "$@" ;;
    up | down | restart | logs) dockerLifecycleCommand "${command}" "$@" ;;
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
    dockerEntryCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    trap - INT TERM
    return "${status}"
}
