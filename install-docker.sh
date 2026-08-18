#!/usr/bin/env bash

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
    local url=$1 target=$2 maxSize=$3
    local -a pipelineStatus=()
    : >"${target}" || return 1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 --max-filesize "${maxSize}" \
            -o "${target}" "${url}" && [[ "$(wc -c <"${target}")" -le "${maxSize}" ]] && return 0
    fi
    : >"${target}" || return 1
    if command -v wget >/dev/null 2>&1; then
        wget -T 30 -t 2 -qO- "${url}" | head -c "$((maxSize + 1))" >"${target}"
        pipelineStatus=("${PIPESTATUS[@]}")
        [[ "${pipelineStatus[0]:-1}" -eq 0 && "${pipelineStatus[1]:-1}" -eq 0 &&
            "$(wc -c <"${target}")" -le "${maxSize}" ]] && return 0
    fi
    return 1
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
        [[ -f "${candidate}/docker/lib/bootstrap.sh" &&
            -f "${candidate}/docker/lib/bundle.sh" &&
            -f "${candidate}/docker/lib/manifest.sh" &&
            -f "${candidate}/docker/lib/lifecycle.sh" &&
            -f "${candidate}/shell/core/deployment_mode.sh" ]] || continue
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

DOCKER_ENTRY_PATH=$(dockerEntryResolvePath "${BASH_SOURCE[0]}") || {
    printf '无法解析 Docker 安装入口路径\n' >&2
    exit 1
}
DOCKER_ENTRY_DIR=$(cd -- "$(dirname -- "${DOCKER_ENTRY_PATH}")" && pwd -P)
DOCKER_ENTRY_SOURCE_DIR=${DOCKER_ENTRY_DIR}
DOCKER_ENTRY_TEMP_DIR=
DOCKER_ENTRY_FETCHED_REF=

if [[ ! -f "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/bootstrap.sh" ]]; then
    if ! DOCKER_ENTRY_REQUIRE_MATCH=1 dockerEntryFetchBundle latest; then
        dockerEntryCleanup || true
        printf '无法下载完整 Docker 控制 bundle\n' >&2
        exit 13
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    trap 'dockerEntryCleanup || true' EXIT
    dockerMain "$@"
    exit $?
fi
