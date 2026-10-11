#!/usr/bin/env bash

dockerSshCollectorRuntime() {
    local action=$1 root
    shift
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/data/net/ssh-collector" &&
        dockerRequireCommand python3 || return 1
    python3 -B "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/lib/ssh-runtime.py" \
        "${action}" "${root}/data/net/ssh-collector" "$@"
}

dockerSshCollectorCheck() {
    dockerSshCollectorRuntime check "$@" >/dev/null
}

dockerSshCollectorStop() {
    local root
    root=$(dockerInstallRoot) || return 1
    [[ -e "${root}/data/net/ssh-collector" || -L "${root}/data/net/ssh-collector" ]] || return 0
    dockerSshCollectorRuntime stop
}

dockerSshFail2banStartVerified() {
    local root unit target port token tuple inputs status=0
    local -a recreate=()
    case "${1:-}" in ''|restart) ;; recreate) recreate=(--force-recreate) ;; *) return 1 ;; esac
    root=$(dockerInstallRoot) || return 1
    [[ -n "${DOCKER_DEPLOYMENT_LOCK_DIR:-}" &&
        "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null)" == "${BASHPID:-$$}" ]] || return 1
    inputs=$(sha256sum -- "${root}/config/spec.json" "${root}/deployment.json" \
        "${root}/compose.json") || return 1
    dockerSshFail2banConfigurationCheck && dockerSshFail2banCleanCheck || return 1
    tuple=$(jq -er '.host_integrations[] | select(.type == "fail2ban-ssh") |
        [.settings.unit,.settings.target,(.settings.port | tostring)] | @tsv' \
        "${root}/config/spec.json") || return 1
    IFS=$'\t' read -r unit target port <<<"${tuple}"
    token=$(dockerSshCollectorRuntime start "${unit}" "${target}" "${port}") || status=$?
    if [[ "${status}" -eq 0 && "${token}" =~ ^[0-9a-f]{32}$ ]]; then
        [[ "$(sha256sum -- "${root}/config/spec.json" "${root}/deployment.json" \
            "${root}/compose.json")" == "${inputs}" ]] &&
            dockerSshFail2banConfigurationCheck && dockerSshFail2banCleanCheck &&
            PADM_SSH_COLLECTOR_TOKEN="${token}" dockerComposeExecute up -d --no-deps \
            "${recreate[@]}" --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" \
            net-fail2ban-ssh >/dev/null &&
            dockerSshFail2banContainer >/dev/null && return 0
    fi
    # 失败时先核验并撤销 jail 的规则，只有证明清理后才能停止日志来源。
    dockerSshFail2banDisablePrepare "${root}/config/spec.json" || {
        dockerError 'SSH 防护启动失败且清理未确认，请保留现场并人工核对'
        return 1
    }
    return 1
}
