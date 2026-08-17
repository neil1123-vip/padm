#!/usr/bin/env bash

if [[ "${PADM_DOCKER_BOOTSTRAP_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_BOOTSTRAP_LOADED=1

DOCKER_LIB_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
DOCKER_BUNDLE_SOURCE_ROOT=$(cd -- "${DOCKER_LIB_DIR}/../.." && pwd -P)

# shellcheck source=/dev/null
source "${DOCKER_BUNDLE_SOURCE_ROOT}/shell/core/deployment_mode.sh"

readonly PADM_DOCKER_PROJECT=padm-docker
readonly PADM_DOCKER_RC_USAGE=2
readonly PADM_DOCKER_RC_HOST=10
readonly PADM_DOCKER_RC_CONFLICT=11
readonly PADM_DOCKER_RC_LOCK=12
readonly PADM_DOCKER_RC_BUNDLE=13
readonly PADM_DOCKER_RC_COMPOSE=14
readonly PADM_DOCKER_RC_STATE=15

DOCKER_DEPLOYMENT_LOCK_DIR=

dockerError() {
    printf '%s\n' "$*" >&2
}

dockerInstallRoot() {
    padmDeploymentRoot docker
}

dockerPathIsSafeAbsolute() {
    local path=$1
    [[ -n "${path}" && "${path}" == /* && "${path}" != "/" &&
        "${path}" != "/." && "${path}" != "/.." &&
        "${path}" != */../* && "${path}" != */.. &&
        "${path}" != */./* && "${path}" != */. ]]
}

dockerManagedPathIsSafe() {
    local root=$1 path=$2
    dockerPathIsSafeAbsolute "${root}" && dockerPathIsSafeAbsolute "${path}" &&
        [[ "${path}" == "${root%/}/"* && "${path}" != "${root}" ]]
}

dockerRemoveManagedTree() {
    local root=$1 path=$2
    dockerManagedPathIsSafe "${root}" "${path}" || return 1
    rm -rf -- "${path}"
}

dockerNormalizeArchitecture() {
    case "$1" in
    x86_64 | amd64) printf 'amd64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
    *) return 1 ;;
    esac
}

dockerRequireCommand() {
    command -v "$1" >/dev/null 2>&1 || {
        dockerError "缺少必需命令: $1"
        return 1
    }
}

dockerHostPreflight() {
    local hostArch daemonArch daemonOs securityOptions endpoint composeVersion
    [[ -n "${BASH_VERSION:-}" && "${BASH_VERSINFO[0]:-0}" -ge 4 ]] || {
        dockerError 'Docker 版需要 Bash 4 或更高版本'
        return 1
    }
    [[ "$(uname -s 2>/dev/null)" == "Linux" ]] || {
        dockerError 'Docker 版首发仅支持 Linux 主机'
        return 1
    }
    [[ "$(id -u 2>/dev/null)" == "0" ]] || {
        dockerError 'Docker 版必须以 root 运行并连接 rootful Docker daemon'
        return 1
    }
    hostArch=$(dockerNormalizeArchitecture "$(uname -m 2>/dev/null)") || {
        dockerError 'Docker 版仅支持 amd64 和 arm64 主机'
        return 1
    }
    dockerRequireCommand docker && dockerRequireCommand jq &&
        dockerRequireCommand sha256sum && dockerRequireCommand tar || return 1
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        dockerError '缺少 curl 或 wget，无法获取预构建发布资产'
        return 1
    fi
    docker info >/dev/null 2>&1 || {
        dockerError 'Docker daemon 不可用或当前 root 无访问权限'
        return 1
    }
    daemonOs=$(docker info --format '{{.OSType}}' 2>/dev/null) || return 1
    [[ "${daemonOs}" == "linux" ]] || {
        dockerError 'Docker daemon 必须运行 Linux 容器'
        return 1
    }
    daemonArch=$(dockerNormalizeArchitecture "$(docker info --format '{{.Architecture}}' 2>/dev/null)") || {
        dockerError 'Docker daemon 架构不受支持'
        return 1
    }
    [[ "${daemonArch}" == "${hostArch}" ]] || {
        dockerError 'Docker daemon 架构与本地主机不一致'
        return 1
    }
    securityOptions=$(docker info --format '{{json .SecurityOptions}}' 2>/dev/null) || return 1
    jq -e 'type == "array"' <<<"${securityOptions}" >/dev/null 2>&1 || {
        dockerError '无法确认 Docker daemon 安全模式'
        return 1
    }
    if jq -e 'any(.[]; tostring | test("rootless"; "i"))' <<<"${securityOptions}" >/dev/null 2>&1; then
        dockerError '检测到 rootless Docker daemon，当前版本不支持该模式'
        return 1
    fi
    if [[ -n "${DOCKER_HOST:-}" && ( "${DOCKER_HOST}" != unix:///* || "${DOCKER_HOST}" == unix:///run/user/* ) ]]; then
        dockerError 'Docker 版必须连接本机 rootful Unix socket'
        return 1
    fi
    endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null) || {
        dockerError '无法确认 Docker context 连接目标'
        return 1
    }
    [[ "${endpoint}" == unix:///* && "${endpoint}" != unix:///run/user/* ]] || {
        dockerError 'Docker context 不是本机 rootful Unix socket'
        return 1
    }
    composeVersion=$(docker compose version --short 2>/dev/null) || {
        dockerError '缺少 Docker Compose v2 插件'
        return 1
    }
    [[ "${composeVersion}" =~ ^v?2([.][0-9]+){1,2}([+-].*)?$ ]] || {
        dockerError "Docker Compose 版本不受支持: ${composeVersion:-unknown}"
        return 1
    }
}

dockerRootHasOnlyBootstrapFiles() {
    local root=$1 entry lockEntry lockFile
    [[ -d "${root}" && ! -L "${root}" ]] || return 1
    while IFS= read -r entry; do
        [[ "${entry}" == "${root}/locks" ]] || return 1
    done < <(find "${root}" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
    if [[ -e "${root}/locks" || -L "${root}/locks" ]]; then
        [[ -d "${root}/locks" && ! -L "${root}/locks" && -O "${root}/locks" ]] || return 1
        while IFS= read -r lockEntry; do
            [[ "${lockEntry}" == "${root}/locks/deployment.lock" && -d "${lockEntry}" &&
                ! -L "${lockEntry}" && -O "${lockEntry}" ]] || return 1
            while IFS= read -r lockFile; do
                [[ "${lockFile}" == "${lockEntry}/pid" && -f "${lockFile}" &&
                    ! -L "${lockFile}" && -O "${lockFile}" ]] || return 1
            done < <(find "${lockEntry}" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
        done < <(find "${root}/locks" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
    fi
}

dockerReportNativeConflict() {
    case "$1" in
    active) dockerError '检测到原生版 padm 正在运行，请先停止并清理原生部署' ;;
    installed) dockerError '检测到原生版 padm 已安装但未清理，Docker 版不会与其混装' ;;
    ambiguous) dockerError '原生版状态异常或存在无法识别的残留，已拒绝 Docker 安装' ;;
    *) return 1 ;;
    esac
}

dockerNativeRootHasResidue() {
    local root firstEntry
    root=$(padmDeploymentRoot native) || return 0
    [[ ! -L "${root}" ]] || return 0
    if [[ -e "${root}" && ! -d "${root}" ]]; then
        return 0
    fi
    [[ -d "${root}" ]] || return 1
    firstEntry=$(find "${root}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) || return 0
    [[ -n "${firstEntry}" ]]
}

dockerAssertInstallAllowed() {
    local root nativeState marker
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${root}" || {
        dockerError "Docker 状态根路径不安全: ${root}"
        return 1
    }
    [[ ! -L "${root}" ]] || {
        dockerError "Docker 状态根不能是符号链接: ${root}"
        return 1
    }
    if [[ -e "${root}" && ! -d "${root}" ]]; then
        dockerError "Docker 状态根不是目录: ${root}"
        return 1
    fi
    if [[ -e "${root}" && ! -O "${root}" ]]; then
        dockerError "Docker 状态根不属于当前 root: ${root}"
        return 1
    fi
    nativeState=$(padmNativeDeploymentState) || nativeState=ambiguous
    if [[ "${nativeState}" == "absent" ]] && dockerNativeRootHasResidue; then
        nativeState=ambiguous
    fi
    if [[ "${nativeState}" != "absent" ]]; then
        dockerReportNativeConflict "${nativeState}"
        return 1
    fi
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    case "${marker}" in
    docker)
        [[ -O "${root}/mode" ]] || {
            dockerError 'Docker mode marker 不属于当前 root'
            return 1
        }
        return 0
        ;;
    missing)
        if padmDockerDeploymentActive; then
            dockerError '检测到无有效状态标记的 padm-docker 容器，已拒绝接管'
            return 1
        fi
        [[ ! -d "${root}" ]] && return 0
        dockerRootHasOnlyBootstrapFiles "${root}" && return 0
        dockerError "Docker 状态根存在无模式标记的残留: ${root}"
        return 1
        ;;
    *)
        dockerError "Docker 状态根模式标记异常: ${root}"
        return 1
        ;;
    esac
}

dockerAcquireDeploymentLock() {
    local root lockDir timeout deadline ownerPid lockMtime now
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${root}" || return 1
    [[ ! -L "${root}" ]] || return 1
    mkdir -p -- "${root}/locks" || return 1
    [[ -d "${root}/locks" && ! -L "${root}/locks" ]] || return 1
    chmod 0750 "${root}" "${root}/locks" || return 1
    lockDir="${root}/locks/deployment.lock"
    timeout=${PADM_DOCKER_LOCK_TIMEOUT:-30}
    [[ "${timeout}" =~ ^[0-9]+$ ]] || return 1
    deadline=$((SECONDS + timeout))
    while ! mkdir -- "${lockDir}" 2>/dev/null; do
        ownerPid=$(cat "${lockDir}/pid" 2>/dev/null || true)
        if [[ "${ownerPid}" =~ ^[0-9]+$ ]] && ! kill -0 "${ownerPid}" 2>/dev/null; then
            rm -f -- "${lockDir}/pid" 2>/dev/null || true
            rmdir -- "${lockDir}" 2>/dev/null || true
            continue
        fi
        if [[ -z "${ownerPid}" ]]; then
            now=$(date +%s)
            lockMtime=$(stat --format=%Y -- "${lockDir}" 2>/dev/null || printf '%s\n' "${now}")
            if ((now - lockMtime > 5)); then
                rmdir -- "${lockDir}" 2>/dev/null || true
                continue
            fi
        fi
        ((SECONDS < deadline)) || {
            dockerError '等待 Docker 部署锁超时'
            return 1
        }
        sleep 0.1
    done
    chmod 0750 "${lockDir}" || {
        rmdir -- "${lockDir}" 2>/dev/null || true
        return 1
    }
    printf '%s\n' "${BASHPID:-$$}" >"${lockDir}/pid" && chmod 0640 "${lockDir}/pid" || {
        rm -f -- "${lockDir}/pid" 2>/dev/null || true
        rmdir -- "${lockDir}" 2>/dev/null || true
        return 1
    }
    DOCKER_DEPLOYMENT_LOCK_DIR=${lockDir}
}

dockerReleaseDeploymentLock() {
    local lockDir=${DOCKER_DEPLOYMENT_LOCK_DIR:-} ownerPid
    [[ -n "${lockDir}" && -d "${lockDir}" ]] || return 0
    ownerPid=$(cat "${lockDir}/pid" 2>/dev/null || true)
    [[ "${ownerPid}" == "${BASHPID:-$$}" ]] || return 0
    rm -f -- "${lockDir}/pid" 2>/dev/null || return 1
    rmdir -- "${lockDir}" 2>/dev/null || return 1
    DOCKER_DEPLOYMENT_LOCK_DIR=
}

dockerInitializeStateRoot() {
    local root modeFile tempMode directory mode
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${root}" && [[ ! -L "${root}" ]] || return 1
    mkdir -p -- "${root}" || return 1
    for directory in .bundles bundle config data secrets logs backups locks; do
        [[ "${directory}" == "bundle" ]] && continue
        if [[ -e "${root}/${directory}" || -L "${root}/${directory}" ]]; then
            [[ -d "${root}/${directory}" && ! -L "${root}/${directory}" &&
                -O "${root}/${directory}" ]] || return 1
        else
            mkdir -- "${root}/${directory}" || return 1
        fi
    done
    chmod 0750 "${root}" "${root}/.bundles" "${root}/config" "${root}/data" \
        "${root}/logs" "${root}/backups" "${root}/locks" || return 1
    chmod 0700 "${root}/secrets" || return 1

    modeFile="${root}/mode"
    mode=$(padmDeploymentModeAtRoot "${root}") || return 1
    if [[ "${mode}" == "docker" ]]; then
        [[ -O "${modeFile}" ]] || return 1
        chmod 0640 "${modeFile}" || return 1
        return 0
    fi
    [[ "${mode}" == "missing" ]] || return 1
    tempMode=$(mktemp "${root}/.mode.XXXXXX") || return 1
    printf 'docker\n' >"${tempMode}" && chmod 0640 "${tempMode}" && mv -f -- "${tempMode}" "${modeFile}" || {
        rm -f -- "${tempMode}" 2>/dev/null || true
        return 1
    }
}

dockerInstallCli() {
    local root binDir target tempLink expectedTarget existingTarget
    root=$(dockerInstallRoot) || return 1
    binDir=${PADM_DOCKER_BIN_DIR:-/usr/local/bin}
    dockerPathIsSafeAbsolute "${binDir}" || return 1
    [[ ! -L "${binDir}" ]] || return 1
    mkdir -p -- "${binDir}" || return 1
    [[ -d "${binDir}" && -O "${binDir}" ]] || return 1
    target="${binDir}/padm-docker"
    expectedTarget="${root}/bundle/install-docker.sh"
    if [[ -e "${target}" || -L "${target}" ]]; then
        [[ -L "${target}" ]] || {
            dockerError "不会覆盖已有的非符号链接命令: ${target}"
            return 1
        }
        existingTarget=$(readlink "${target}" 2>/dev/null || true)
        [[ "${existingTarget}" == "${expectedTarget}" ]] || {
            dockerError "已有 padm-docker 链接不属于当前部署: ${target}"
            return 1
        }
    fi
    tempLink="${binDir}/.padm-docker.${BASHPID:-$$}"
    rm -f -- "${tempLink}" 2>/dev/null || true
    ln -s "${expectedTarget}" "${tempLink}" || return 1
    mv -Tf -- "${tempLink}" "${target}" || {
        rm -f -- "${tempLink}" 2>/dev/null || true
        return 1
    }
}

dockerRemoveCli() {
    local root binDir target expectedTarget existingTarget
    root=$(dockerInstallRoot) || return 1
    binDir=${PADM_DOCKER_BIN_DIR:-/usr/local/bin}
    dockerPathIsSafeAbsolute "${binDir}" || return 1
    target="${binDir}/padm-docker"
    expectedTarget="${root}/bundle/install-docker.sh"
    [[ -e "${target}" || -L "${target}" ]] || return 0
    [[ -L "${target}" ]] || {
        dockerError "padm-docker 不是本部署创建的符号链接，已保留: ${target}"
        return 1
    }
    existingTarget=$(readlink "${target}" 2>/dev/null || true)
    [[ "${existingTarget}" == "${expectedTarget}" ]] || {
        dockerError "padm-docker 指向其他目标，已保留: ${target}"
        return 1
    }
    rm -f -- "${target}"
}
