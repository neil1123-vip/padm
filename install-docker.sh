#!/usr/bin/env bash

dockerEntryUsage() {
    cat >&2 <<'EOF'
用法:
  padm-docker                          # 交互终端进入菜单；非交互显示帮助
  padm-docker menu
  install-docker.sh install [--source <目录>] [--ref <commit|latest>] [--no-menu]
  padm-docker help                     # 查看全部命令
EOF
}

# 无参数非交互入口不安装依赖、不下载模块，也不初始化状态。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    if [[ "$#" -eq 0 ]]; then
        if [[ ! -t 0 || ! -t 1 ]]; then
            dockerEntryUsage
            exit 0
        elif [[ -f "${PADM_DOCKER_INSTALL_DIR:-/etc/padm-docker}/mode" ||
            "${0##*/}" == padm-docker ]]; then
            set -- menu
        else
            set -- install
        fi
    elif [[ "$1" == menu && ( ! -t 0 || ! -t 1 ) ]]; then
        dockerEntryUsage
        exit 2
    fi
fi

dockerEntryResolvePath() {
    local sourcePath=${1:-${BASH_SOURCE[0]}}
    local sourceDir targetPath resolvedTarget
    while true; do
        sourceDir=$(cd -- "$(dirname -- "${sourcePath}")" && pwd -P) || return 1
        targetPath=$(readlink "${sourcePath}" 2>/dev/null) || break
        [[ -n "${targetPath}" ]] || break
        if [[ "${targetPath}" != /* ]]; then
            resolvedTarget="${sourceDir}/${targetPath}"
        else
            resolvedTarget=${targetPath}
        fi
        [[ -e "${resolvedTarget}" || -L "${resolvedTarget}" ]] || break
        sourcePath=${resolvedTarget}
    done
    sourceDir=$(cd -- "$(dirname -- "${sourcePath}")" && pwd -P) || return 1
    printf '%s/%s\n' "${sourceDir}" "$(basename -- "${sourcePath}")"
}

dockerEntryPathIsSafe() {
    local path=$1
    [[ -n "${path}" && "${path}" == /* && "${path}" != "/" &&
        "${path}" != */../* && "${path}" != */.. &&
        "${path}" != */./* && "${path}" != */. ]]
}

dockerEntryDownloadFile() {
    local url=$1 target=$2 maxSize=$3 deadline remaining
    local -a pipelineStatus=()
    deadline=$((SECONDS + 120))
    : >"${target}" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 --max-filesize "${maxSize}" \
            -o "${target}" "${url}" && [[ "$(wc -c <"${target}")" -le "${maxSize}" ]] && return 0
    fi
    : >"${target}" || return 1
    if command -v wget >/dev/null 2>&1; then
        remaining=$((deadline - SECONDS))
        ((remaining > 0)) || return 1
        command -v timeout >/dev/null 2>&1 || {
            dockerEntryError '缺少 timeout，无法限制 Docker 下载时长'
            return 1
        }
        timeout -k 2 "${remaining}" wget -T 30 -t 2 -qO- "${url}" | head -c "$((maxSize + 1))" >"${target}"
        pipelineStatus=("${PIPESTATUS[@]}")
        [[ "${pipelineStatus[0]:-1}" -eq 0 && "${pipelineStatus[1]:-1}" -eq 0 &&
            "$(wc -c <"${target}")" -le "${maxSize}" ]] && return 0
    fi
    return 1
}

dockerEntryError() {
    printf '%s\n' "$*" >&2
}

dockerEntryDockerAvailable() {
    command -v docker >/dev/null 2>&1
}

dockerEntryReadOsRelease() {
    local osReleaseFile=/etc/os-release
    local ID= VERSION_CODENAME= UBUNTU_CODENAME=
    [[ -r "${osReleaseFile}" ]] || {
        dockerEntryError '无法读取 /etc/os-release，拒绝自动安装 Docker'
        return 1
    }
    # shellcheck disable=SC1091
    . "${osReleaseFile}"
    DOCKER_ENTRY_OS_ID=${ID:-}
    DOCKER_ENTRY_OS_CODENAME=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
}

dockerEntryInstallPlatformReady() {
    local arch
    [[ "$(uname -s 2>/dev/null)" == 'Linux' ]] || {
        dockerEntryError '自动安装 Docker 仅支持 Linux 主机'
        return 1
    }
    [[ "$(id -u 2>/dev/null)" == '0' ]] || {
        dockerEntryError '自动安装 Docker 必须以 root 运行'
        return 1
    }
    command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]] || {
        dockerEntryError '自动安装 Docker 需要正在运行的 systemd'
        return 1
    }
    arch=$(uname -m 2>/dev/null) || return 1
    case "${arch}" in
    x86_64 | amd64 | aarch64 | arm64) ;;
    *)
        dockerEntryError "自动安装 Docker 不支持主机架构: ${arch:-unknown}"
        return 1
        ;;
    esac
    dockerEntryReadOsRelease
}

dockerEntryInstallApt() {
    local repoOs=$1 codename=$2 arch=$3
    local keySource keyringTemp repoTemp
    [[ "${repoOs}" == 'debian' || "${repoOs}" == 'ubuntu' ]] || return 1
    [[ "${codename}" =~ ^[a-z][a-z0-9.-]+$ && "${arch}" =~ ^(amd64|arm64)$ ]] || {
        dockerEntryError '无法确定 Debian/Ubuntu 的 Docker 仓库版本或架构'
        return 1
    }
    command -v apt-get >/dev/null 2>&1 || {
        dockerEntryError '缺少 apt-get，无法自动安装 Docker'
        return 1
    }
    DEBIAN_FRONTEND=noninteractive apt-get update || return 1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates curl gnupg jq tar || return 1
    install -d -m 0755 /etc/apt/keyrings || return 1
    keySource=$(mktemp /etc/apt/keyrings/.padm-docker.asc.XXXXXX) || return 1
    if ! dockerEntryDownloadFile \
        "https://download.docker.com/linux/${repoOs}/gpg" "${keySource}" 1048576; then
        rm -f -- "${keySource}"
        dockerEntryError '无法下载 Docker 官方 APT 签名密钥'
        return 1
    fi
    keyringTemp=$(mktemp /etc/apt/keyrings/.padm-docker.gpg.XXXXXX) || {
        rm -f -- "${keySource}"
        return 1
    }
    if ! gpg --dearmor --yes --output "${keyringTemp}" "${keySource}"; then
        rm -f -- "${keySource}" "${keyringTemp}"
        dockerEntryError '无法处理 Docker 官方 APT 签名密钥'
        return 1
    fi
    install -m 0644 "${keyringTemp}" /etc/apt/keyrings/padm-docker.gpg || {
        rm -f -- "${keySource}" "${keyringTemp}"
        return 1
    }
    rm -f -- "${keySource}" "${keyringTemp}"
    repoTemp=$(mktemp /etc/apt/sources.list.d/.padm-docker.list.XXXXXX) || return 1
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/padm-docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
        "${arch}" "${repoOs}" "${codename}" >"${repoTemp}" || {
        rm -f -- "${repoTemp}"
        return 1
    }
    install -m 0644 "${repoTemp}" /etc/apt/sources.list.d/padm-docker.list || {
        rm -f -- "${repoTemp}"
        return 1
    }
    rm -f -- "${repoTemp}"
    DEBIAN_FRONTEND=noninteractive apt-get update || return 1
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
}

dockerEntryInstallRpm() {
    local repoOs=$1 packageManager repoTemp
    local -a packageCommand=()
    case "${repoOs}" in
    centos | fedora | rhel) ;;
    *) return 1 ;;
    esac
    if command -v dnf >/dev/null 2>&1; then
        packageManager=dnf
    elif command -v yum >/dev/null 2>&1; then
        packageManager=yum
    else
        dockerEntryError '缺少 dnf 或 yum，无法自动安装 Docker'
        return 1
    fi
    packageCommand=("${packageManager}")
    "${packageCommand[@]}" -y install ca-certificates curl jq tar || return 1
    install -d -m 0755 /etc/yum.repos.d || return 1
    repoTemp=$(mktemp /etc/yum.repos.d/.padm-docker.repo.XXXXXX) || return 1
    if ! dockerEntryDownloadFile \
        "https://download.docker.com/linux/${repoOs}/docker-ce.repo" "${repoTemp}" 1048576; then
        rm -f -- "${repoTemp}"
        dockerEntryError '无法下载 Docker 官方 RPM 仓库配置'
        return 1
    fi
    install -m 0644 "${repoTemp}" /etc/yum.repos.d/padm-docker.repo || {
        rm -f -- "${repoTemp}"
        return 1
    }
    rm -f -- "${repoTemp}"
    "${packageCommand[@]}" -y install \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
}

dockerEntryStartAndVerifyDocker() {
    local attempt
    systemctl enable --now docker.service || {
        dockerEntryError 'Docker 服务启动失败，请检查 systemd 日志'
        return 1
    }
    systemctl enable containerd.service >/dev/null 2>&1 || true
    for ((attempt = 0; attempt < 30; attempt++)); do
        if docker info >/dev/null 2>&1 && docker compose version --short >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    dockerEntryError 'Docker daemon 或 Compose CLI 插件安装后仍不可用'
    return 1
}

dockerEntryInstallDockerEngine() {
    local arch repoOs
    dockerEntryInstallPlatformReady || return 1
    arch=$(uname -m 2>/dev/null) || return 1
    case "${arch}" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    esac
    case "${DOCKER_ENTRY_OS_ID}" in
    debian | ubuntu)
        [[ -n "${DOCKER_ENTRY_OS_CODENAME}" ]] || {
            dockerEntryError '无法读取 Debian/Ubuntu 发布代号，拒绝猜测 Docker 仓库'
            return 1
        }
        dockerEntryInstallApt "${DOCKER_ENTRY_OS_ID}" \
            "${DOCKER_ENTRY_OS_CODENAME}" "${arch}" || return 1
        ;;
    centos | fedora | rhel)
        repoOs=${DOCKER_ENTRY_OS_ID}
        dockerEntryInstallRpm "${repoOs}" || return 1
        ;;
    *)
        dockerEntryError "当前发行版不在自动安装支持范围: ${DOCKER_ENTRY_OS_ID:-unknown}"
        dockerEntryError '请先按 Docker 官方文档安装 Docker Engine 和 Compose CLI 插件，再重试: https://docs.docker.com/engine/install/'
        return 1
        ;;
    esac
    dockerEntryStartAndVerifyDocker
}

dockerEntryNativeInstallAllowed() {
    local module=${DOCKER_ENTRY_SOURCE_DIR:-}/shell/core/deployment_mode.sh
    local state root entry unit
    root=${PADM_NATIVE_INSTALL_DIR:-${PADM_INSTALL_DIR:-/etc/padm}}
    [[ "${root}" == /* && "${root}" != '/' && "${root}" != *'/../'* &&
        "${root}" != */.. && "${root}" != *'/./'* && "${root}" != */. ]] || {
        dockerEntryError '原生版状态根路径不安全，拒绝自动安装 Docker'
        return 1
    }
    [[ ! -L "${root}" && ( ! -e "${root}" || -d "${root}" ) ]] || {
        dockerEntryError '原生版状态根不是普通目录，拒绝自动安装 Docker'
        return 1
    }
    if [[ -f "${module}" && ! -L "${module}" ]]; then
        # shellcheck disable=SC1090
        source "${module}" || return 1
        state=$(padmNativeDeploymentState 2>/dev/null) || state=ambiguous
        [[ "${state}" == 'absent' ]] || {
            dockerEntryError "检测到原生版状态 (${state})，请先清理原生部署后再安装 Docker"
            return 1
        }
    fi
    if [[ -e "${root}/mode" || -L "${root}/mode" ]]; then
        dockerEntryError "检测到原生版模式标记: ${root}/mode"
        return 1
    fi
    for entry in install.sh .padm-ref .padm-module-manifest xray/xray sing-box/sing-box; do
        if [[ -e "${root}/${entry}" || -L "${root}/${entry}" ]]; then
            dockerEntryError "检测到原生版残留: ${root}/${entry}"
            return 1
        fi
    done
    for unit in \
        /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service \
        /etc/init.d/xray /etc/init.d/sing-box; do
        if [[ -f "${unit}" ]] && grep -Fq "${root}/" "${unit}"; then
            dockerEntryError "检测到原生版服务残留: ${unit}"
            return 1
        fi
    done
    if [[ -d "${root}" ]]; then
        entry=$(find "${root}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null) || {
            dockerEntryError "无法检查原生版状态根: ${root}"
            return 1
        }
        [[ -z "${entry}" ]] || {
            dockerEntryError "检测到原生版状态根存在残留: ${root}"
            return 1
        }
    fi
}

dockerEntryEnsureDockerForInstall() {
    [[ "${DOCKER_ENTRY_ENGINE_READY:-0}" == '1' ]] && return 0
    dockerEntryDockerAvailable && return 0
    dockerEntryNativeInstallAllowed || return 10
    printf '未检测到 Docker。是否使用 Docker 官方软件源安装 Docker Engine 和 Compose CLI 插件？[y/N]: ' >&2
    local answer=
    IFS= read -r answer || answer=
    case "${answer}" in
    y | Y | yes | YES | Yes | 是 | 是的) ;;
    *)
        dockerEntryError '未确认安装 Docker，已停止'
        return 10
        ;;
    esac
    printf '正在安装 Docker Engine 和 Compose CLI 插件，请稍候...\n' >&2
    dockerEntryInstallDockerEngine || return 10
    DOCKER_ENTRY_ENGINE_READY=1
}

dockerEntryInstallCommandRequested() {
    [[ "${BASH_SOURCE[0]}" == "$0" ]] || return 1
    [[ "${1:-}" == 'install' ]]
}

dockerEntryParseInstallArgs() {
    local sourceRoot= requestedRef= noMenu=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --no-menu)
            noMenu=1
            shift
            ;;
        --source|--ref)
            [[ "$#" -ge 2 && -n "$2" ]] || return 2
            if [[ "$1" == --source ]]; then sourceRoot=$2; else requestedRef=$2; fi
            shift 2
            ;;
        *)
            dockerEntryUsage
            return 2
            ;;
        esac
    done
    if [[ -n "${sourceRoot}" && "${requestedRef}" == latest ]]; then
        dockerEntryError '--source 不能与 --ref latest 同时使用'
        return 2
    fi
    if [[ -n "${requestedRef}" && "${requestedRef}" != latest &&
        ! "${requestedRef}" =~ ^[0-9a-f]{40}$ && ! "${requestedRef}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
        dockerEntryError '--ref 必须是 40 位小写 commit SHA 或 latest'
        return 2
    fi
    if [[ "${requestedRef}" == sha256:* && -z "${sourceRoot}" ]]; then
        dockerEntryError 'sha256 ref 必须与本地 --source 同时使用'
        return 2
    fi
    if [[ -n "${sourceRoot}" ]]; then
        sourceRoot=$(cd -- "${sourceRoot}" 2>/dev/null && pwd -P) || return 13
        dockerEntryPathIsSafe "${sourceRoot}" && dockerEntryBundleModulesPresent "${sourceRoot}" || {
            dockerEntryError "Docker bundle 源不完整: ${sourceRoot}"
            return 13
        }
    fi
    DOCKER_ENTRY_INSTALL_SOURCE=${sourceRoot}
    DOCKER_ENTRY_INSTALL_REF=${requestedRef}
    [[ "${noMenu}" -ne 1 ]] || DOCKER_MENU_AFTER_INSTALL=0
    return 0
}

dockerEntryArchivePathIsSafe() {
    local path=${1%/} segment
    local -a segments=()
    [[ -n "${path}" && "${path}" != /* ]] || return 1
    IFS='/' read -r -a segments <<<"${path}"
    for segment in "${segments[@]}"; do
        [[ -n "${segment}" && "${segment}" != "." && "${segment}" != ".." ]] || return 1
    done
}

dockerEntryArchiveIsSafe() {
    local archive=$1 entryList=$2 detailList=$3 entry line expandedBytes
    tar -tzf "${archive}" >"${entryList}" 2>/dev/null || return 1
    [[ "$(wc -l <"${entryList}" | tr -d '[:space:]')" -le 10000 ]] || return 1
    while IFS= read -r entry; do
        dockerEntryArchivePathIsSafe "${entry}" || return 1
    done <"${entryList}"
    tar -tvzf "${archive}" >"${detailList}" 2>/dev/null || return 1
    while IFS= read -r line; do
        case "${line:0:1}" in
        - | d) ;;
        *) return 1 ;;
        esac
    done <"${detailList}"
    expandedBytes=$(
        { tar -xOzf "${archive}" 2>/dev/null || true; } |
            head -c 104857601 |
            wc -c |
            tr -d '[:space:]'
    ) || return 1
    [[ "${expandedBytes}" =~ ^[0-9]+$ ]] && ((expandedBytes <= 104857600))
}

dockerEntryCleanup() {
    local tempDir=${DOCKER_ENTRY_TEMP_DIR:-}
    [[ -n "${tempDir}" ]] || return 0
    dockerEntryPathIsSafe "${tempDir}" || return 1
    rm -rf -- "${tempDir}"
    DOCKER_ENTRY_TEMP_DIR=
}

dockerEntryBundleModulesPresent() {
    local sourceRoot=$1 required links
    [[ -d "${sourceRoot}" && ! -L "${sourceRoot}" ]] || return 1
    [[ -d "${sourceRoot}/docker" && ! -L "${sourceRoot}/docker" ]] || return 1
    links=$(find "${sourceRoot}/docker" -type l -print -quit 2>/dev/null) || return 1
    [[ -z "${links}" ]] || return 1
    for required in \
        install-docker.sh \
        docker/lib/bootstrap.sh docker/lib/bundle.sh docker/lib/manifest.sh \
        docker/lib/services.sh docker/lib/traffic.sh docker/lib/lifecycle.sh docker/lib/setup.sh \
        docker/lib/accounts.sh docker/lib/subscriptions.sh docker/lib/business.sh \
        docker/lib/menu.sh docker/contracts/configure.schema.json \
        docker/contracts/deployment.schema.json docker/contracts/features.json \
        shell/core/deployment_mode.sh shell/core/stats_grpc.sh; do
        [[ -f "${sourceRoot}/${required}" && ! -L "${sourceRoot}/${required}" ]] || return 1
    done
    for required in renewal schedule geo control-sync control; do
        if grep -qF "/${required}.sh\"" "${sourceRoot}/docker/lib/services.sh"; then
            [[ -f "${sourceRoot}/docker/lib/${required}.sh" &&
                ! -L "${sourceRoot}/docker/lib/${required}.sh" ]] || return 1
        fi
    done
    if grep -qF '/shell/core/cores.sh"' "${sourceRoot}/docker/lib/lifecycle.sh"; then
        [[ -f "${sourceRoot}/shell/core/cores.sh" && ! -L "${sourceRoot}/shell/core/cores.sh" ]] || return 1
    fi
    if grep -qF '/reality-targets.sh"' "${sourceRoot}/docker/lib/services.sh" ||
        [[ -f "${sourceRoot}/docker/lib/reality-targets.sh" ]]; then
        for required in docker/lib/reality-targets.sh shell/core/runtime.sh shell/core/reality_targets.sh; do
            [[ -f "${sourceRoot}/${required}" && ! -L "${sourceRoot}/${required}" ]] || return 1
        done
    fi
}

dockerEntryFetchBundle() {
    local requestedRef=${1:-latest}
    local metadata archive entryList detailList extractDir candidate found=0
    local refUrl=https://api.github.com/repos/neil1123-vip/padm/commits/main
    local archiveBase=https://github.com/neil1123-vip/padm/archive

    command -v jq >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || return 1
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 1
    dockerEntryCleanup || return 1
    DOCKER_ENTRY_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-entry.XXXXXX") || return 1
    dockerEntryPathIsSafe "${DOCKER_ENTRY_TEMP_DIR}" || return 1
    metadata="${DOCKER_ENTRY_TEMP_DIR}/ref.json"
    archive="${DOCKER_ENTRY_TEMP_DIR}/bundle.tar.gz"
    entryList="${DOCKER_ENTRY_TEMP_DIR}/entries"
    detailList="${DOCKER_ENTRY_TEMP_DIR}/details"
    extractDir="${DOCKER_ENTRY_TEMP_DIR}/extract"

    if [[ "${requestedRef}" == "latest" ]]; then
        dockerEntryDownloadFile "${refUrl}" "${metadata}" 1048576 || return 1
        requestedRef=$(jq -er '.sha | select(type == "string" and test("^[0-9a-f]{40}$"))' "${metadata}") || return 1
    fi
    [[ "${requestedRef}" =~ ^[0-9a-f]{40}$ ]] || return 1
    dockerEntryDownloadFile "${archiveBase}/${requestedRef}.tar.gz" "${archive}" 52428800 || return 1
    [[ -s "${archive}" ]] || return 1
    dockerEntryArchiveIsSafe "${archive}" "${entryList}" "${detailList}" || return 1
    mkdir -p "${extractDir}" || return 1
    tar -xzf "${archive}" -C "${extractDir}" || return 1

    while IFS= read -r candidate; do
        candidate=${candidate%/install-docker.sh}
        dockerEntryBundleModulesPresent "${candidate}" || continue
        DOCKER_ENTRY_SOURCE_DIR=${candidate}
        found=$((found + 1))
    done < <(find "${extractDir}" -mindepth 2 -maxdepth 2 -type f -name install-docker.sh -print)
    [[ "${found}" -eq 1 ]] || return 1
    if [[ "${DOCKER_ENTRY_REQUIRE_MATCH:-}" == "1" && -f "${DOCKER_ENTRY_PATH}" &&
        "${DOCKER_ENTRY_PATH}" != /dev/* ]] &&
        ! cmp -s "${DOCKER_ENTRY_PATH}" "${DOCKER_ENTRY_SOURCE_DIR}/install-docker.sh"; then
        printf 'Docker 入口与下载 bundle 版本不一致，请重新获取入口后重试\n' >&2
        return 1
    fi
    DOCKER_ENTRY_FETCHED_REF=${requestedRef}
}

dockerEntryPrepareBundleSource() {
    local sourceRoot= requestedRef= command=${1:-}
    if [[ "${1:-}" == install ]]; then
        shift
        dockerEntryParseInstallArgs "$@" || return $?
        sourceRoot=${DOCKER_ENTRY_INSTALL_SOURCE}
        requestedRef=${DOCKER_ENTRY_INSTALL_REF}
    fi
    if [[ -n "${sourceRoot}" ]]; then
        sourceRoot=$(cd -- "${sourceRoot}" 2>/dev/null && pwd -P) || return 13
        dockerEntryPathIsSafe "${sourceRoot}" || return 13
        DOCKER_ENTRY_SOURCE_DIR=${sourceRoot}
        cmp -s "${DOCKER_ENTRY_PATH}" "${sourceRoot}/install-docker.sh" || {
            dockerEntryError 'Docker 入口与本地 bundle 版本不一致，请使用匹配的入口'
            return 13
        }
    else
        DOCKER_ENTRY_REQUIRE_MATCH=1 dockerEntryFetchBundle "${requestedRef:-latest}" || return 13
        [[ "${command}" != install ]] || DOCKER_ENTRY_BOOTSTRAP_REF=${requestedRef:-latest}
    fi
    dockerEntryBundleModulesPresent "${DOCKER_ENTRY_SOURCE_DIR}" || return 13
}

DOCKER_ENTRY_PATH=$(dockerEntryResolvePath "${BASH_SOURCE[0]}") || {
    printf '无法解析 Docker 安装入口路径\n' >&2
    exit 1
}
DOCKER_ENTRY_DIR=$(cd -- "$(dirname -- "${DOCKER_ENTRY_PATH}")" && pwd -P)
DOCKER_ENTRY_SOURCE_DIR=${DOCKER_ENTRY_DIR}
DOCKER_ENTRY_TEMP_DIR=
DOCKER_ENTRY_FETCHED_REF=
DOCKER_ENTRY_BOOTSTRAP_REF=
DOCKER_ENTRY_ENGINE_READY=0
DOCKER_MENU_AFTER_INSTALL=0
if [[ "${1:-}" == install && -t 0 && -t 1 ]]; then
    DOCKER_MENU_AFTER_INSTALL=1
fi

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'dockerEntryCleanup || true' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
fi

if dockerEntryInstallCommandRequested "${1:-}"; then
    dockerEntryParseInstallArgs "${@:2}" || exit $?
    dockerEntryEnsureDockerForInstall
    DOCKER_ENTRY_ENGINE_STATUS=$?
    if [[ "${DOCKER_ENTRY_ENGINE_STATUS}" -ne 0 ]]; then
        exit "${DOCKER_ENTRY_ENGINE_STATUS}"
    fi
fi

if [[ ! -f "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/bootstrap.sh" ]]; then
    dockerEntryPrepareBundleSource "$@"
    DOCKER_ENTRY_SOURCE_STATUS=$?
    if [[ "${DOCKER_ENTRY_SOURCE_STATUS}" -ne 0 ]]; then
        dockerEntryCleanup || true
        printf '无法准备完整 Docker 控制 bundle\n' >&2
        exit "${DOCKER_ENTRY_SOURCE_STATUS}"
    fi
fi

# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/bundle.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/manifest.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/lifecycle.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/setup.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/accounts.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/subscriptions.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/business.sh"
# shellcheck source=/dev/null
source "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/menu.sh"

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    dockerMain "$@"
    DOCKER_ENTRY_STATUS=$?
    if [[ "${DOCKER_ENTRY_STATUS}" -eq 0 && "${DOCKER_MENU_AFTER_INSTALL}" -eq 1 ]]; then
        dockerMenu
        DOCKER_ENTRY_STATUS=$?
    fi
    exit "${DOCKER_ENTRY_STATUS}"
fi
