#!/usr/bin/env bash

padmDeploymentRoot() {
    case "$1" in
    native) printf '%s\n' "${PADM_NATIVE_INSTALL_DIR:-${PADM_INSTALL_DIR:-/etc/padm}}" ;;
    docker) printf '%s\n' "${PADM_DOCKER_INSTALL_DIR:-/etc/padm-docker}" ;;
    *) return 1 ;;
    esac
}

padmDeploymentModeAtRoot() {
    local root=$1
    local modeFile marker lineCount
    [[ -n "${root}" && "${root}" == /* && "${root}" != "/" ]] || return 1
    modeFile="${root%/}/mode"
    if [[ ! -e "${modeFile}" && ! -L "${modeFile}" ]]; then
        printf 'missing\n'
        return 0
    fi
    if [[ ! -f "${modeFile}" || -L "${modeFile}" ]]; then
        printf 'invalid\n'
        return 0
    fi
    lineCount=$(awk 'END { print NR + 0 }' "${modeFile}") || return 1
    marker=$(awk 'NR == 1 { print; exit }' "${modeFile}") || return 1
    if [[ "${lineCount}" == "1" && ( "${marker}" == "native" || "${marker}" == "docker" ) ]]; then
        printf '%s\n' "${marker}"
    else
        printf 'invalid\n'
    fi
}

padmDeploymentMode() {
    local root
    root=$(padmDeploymentRoot "$1") || return 1
    padmDeploymentModeAtRoot "${root}"
}

padmNativeLegacyInstalled() {
    local root unit
    root=$(padmDeploymentRoot native) || return 1
    if [[ -f "${root}/install.sh" || -f "${root}/.padm-ref" ||
        -f "${root}/.padm-module-manifest" || -x "${root}/xray/xray" ||
        -x "${root}/sing-box/sing-box" ]]; then
        return 0
    fi
    [[ "${root}" == "/etc/padm" ]] || return 1
    for unit in \
        /etc/systemd/system/xray.service /etc/systemd/system/sing-box.service \
        /etc/init.d/xray /etc/init.d/sing-box; do
        [[ -f "${unit}" ]] && grep -Fq "${root}/" "${unit}" && return 0
    done
    command -v crontab >/dev/null 2>&1 &&
        crontab -l 2>/dev/null | grep -Fq "${root}/install.sh"
}

padmNativeManagedServiceActive() {
    local root service unit
    root=$(padmDeploymentRoot native) || return 1
    [[ "${root}" == "/etc/padm" ]] || return 1
    for service in xray sing-box; do
        for unit in "/etc/systemd/system/${service}.service" "/etc/init.d/${service}"; do
            [[ -f "${unit}" ]] && grep -Fq "${root}/" "${unit}" || continue
            if [[ "${unit}" == /etc/systemd/system/* ]] && command -v systemctl >/dev/null 2>&1; then
                systemctl is-active --quiet "${service}.service" && return 0
            elif command -v rc-service >/dev/null 2>&1; then
                rc-service "${service}" status >/dev/null 2>&1 && return 0
            fi
        done
    done
    return 1
}

padmNativeManagedProcessActive() {
    local root process pid cmdline
    root=$(padmDeploymentRoot native) || return 1
    command -v pgrep >/dev/null 2>&1 || return 1
    for process in xray sing-box; do
        while IFS= read -r pid; do
            [[ "${pid}" =~ ^[0-9]+$ && -r "/proc/${pid}/cmdline" ]] || continue
            cmdline=$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)
            [[ "${cmdline}" == *"${root%/}/"* ]] && return 0
        done < <(pgrep -x "${process}" 2>/dev/null || true)
    done
    return 1
}

padmNativeDeploymentState() {
    local marker
    marker=$(padmDeploymentMode native) || return 1
    if padmNativeManagedServiceActive || padmNativeManagedProcessActive; then
        printf 'active\n'
    elif [[ "${marker}" == "native" ]] || { [[ "${marker}" == "missing" ]] && padmNativeLegacyInstalled; }; then
        printf 'installed\n'
    elif [[ "${marker}" == "missing" ]]; then
        printf 'absent\n'
    else
        printf 'ambiguous\n'
    fi
}

padmDockerDeploymentActive() {
    local ids
    command -v docker >/dev/null 2>&1 || return 1
    ids=$(docker ps --filter 'label=io.padm.project=padm-docker' --format '{{.ID}}' 2>/dev/null) || return 1
    [[ -n "${ids//[[:space:]]/}" ]] && return 0
    ids=$(docker ps --filter 'label=com.docker.compose.project=padm-docker' --format '{{.ID}}' 2>/dev/null) || return 1
    [[ -n "${ids//[[:space:]]/}" ]]
}

padmDockerDeploymentIdentityValid() {
    local deploymentFile=$1
    [[ -f "${deploymentFile}" && ! -L "${deploymentFile}" && -s "${deploymentFile}" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '
      type == "object" and
      .schema_version == 1 and
      .mode == "docker" and
      .compose.project == "padm-docker"
    ' "${deploymentFile}" >/dev/null 2>&1
}

padmDockerDeploymentState() {
    local root marker
    root=$(padmDeploymentRoot docker) || return 1
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    if padmDockerDeploymentActive; then
        printf 'active\n'
    elif [[ "${marker}" == "docker" ]]; then
        printf 'installed\n'
    elif [[ "${marker}" != "missing" ]]; then
        printf 'ambiguous\n'
    elif padmDockerDeploymentIdentityValid "${root}/deployment.json"; then
        printf 'installed\n'
    elif [[ -e "${root}/deployment.json" || -L "${root}/deployment.json" ]]; then
        printf 'ambiguous\n'
    elif [[ -d "${root}" ]] && find "${root}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
        printf 'ambiguous\n'
    else
        printf 'absent\n'
    fi
}

padmReportNativeInstallConflict() {
    local state=$1 message
    case "${state}" in
    active) message="检测到 Docker 版 padm 正在运行，请先使用 padm-docker 停止并清理该部署" ;;
    installed) message="检测到 Docker 版 padm 已安装但未清理，原生版不会与其混装" ;;
    ambiguous) message="检测到 /etc/padm-docker 残留或状态异常，无法安全确认部署归属" ;;
    *) return 1 ;;
    esac
    if declare -F errorCard >/dev/null 2>&1; then
        errorCard "${message}"
    else
        printf '%s\n' "${message}" >&2
    fi
}

padmAssertNativeInstallAllowed() {
    local state
    state=$(padmDockerDeploymentState) || {
        padmReportNativeInstallConflict ambiguous
        return 1
    }
    [[ "${state}" == "absent" ]] && return 0
    padmReportNativeInstallConflict "${state}"
    return 1
}
