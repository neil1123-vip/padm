#!/usr/bin/env bash

runNginxServiceFailureRegression() (
    set -euo pipefail
    local serviceTmp
    local fakeBin
    serviceTmp=$(mktemp -d)
    fakeBin="${serviceTmp}/bin"
    mkdir -p "${fakeBin}" "${serviceTmp}/etc-padm"

    cat >"${fakeBin}/systemctl" <<'SH'
#!/usr/bin/env bash
case "$1" in
start)
    printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS:-/dev/null}"
    if [[ "${PADM_FAKE_SYSTEMCTL_RETRY_ONCE:-false}" == "true" && ! -e "${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}" ]]; then
        : >"${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}"
        printf 'See "journalctl -xe" for details\n' >&2
        exit 1
    fi
    [[ "${PADM_FAKE_SYSTEMCTL_START_RC:-0}" == "0" ]] || exit "${PADM_FAKE_SYSTEMCTL_START_RC}"
    printf '%s\n' "${PADM_FAKE_SYSTEMCTL_START_STATE:-true}" >"${PADM_FAKE_NGINX_STATE_FILE}"
    ;;
stop)
    printf '%s\n' "$*" >>"${PADM_FAKE_SYSTEMCTL_ACTIONS:-/dev/null}"
    [[ "${PADM_FAKE_SYSTEMCTL_STOP_RC:-0}" == "0" ]] || exit "${PADM_FAKE_SYSTEMCTL_STOP_RC}"
    printf '%s\n' "${PADM_FAKE_SYSTEMCTL_STOP_STATE:-false}" >"${PADM_FAKE_NGINX_STATE_FILE}"
    ;;
*)
    exit 0
    ;;
esac
SH
    cat >"${fakeBin}/pgrep" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-x" && "$2" == "nginx" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]]; then
    printf '12345\n'
    exit 0
fi
exit 1
SH
    cat >"${fakeBin}/kill" <<'SH'
#!/usr/bin/env bash
printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
SH
    cat >"${fakeBin}/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"${fakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PADM_FAKE_NGINX_ACTIONS:-/dev/null}"
if [[ "$1" == "-t" ]]; then
    exit "${PADM_FAKE_NGINX_TEST_RC:-0}"
fi
if [[ "$1" == "-s" && "$2" == "reload" ]]; then
    exit "${PADM_FAKE_NGINX_RELOAD_RC:-0}"
fi
if [[ "$1" == "-s" && "$2" == "stop" ]]; then
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
fi
exit 0
SH
    chmod +x "${fakeBin}/systemctl" "${fakeBin}/pgrep" "${fakeBin}/kill" "${fakeBin}/sleep" "${fakeBin}/nginx"

    PATH="${fakeBin}:${PATH}"
    source "${PROJECT_ROOT}/shell/core/protocols.sh"
    source "${PROJECT_ROOT}/shell/core/services.sh"
    errorCard() { return 0; }
    nginxConfigPath="${serviceTmp}/nginx-reasons/"
    mkdir -p "${nginxConfigPath}"
    realityStreamSplitConfFile() { printf '%s\n' "${serviceTmp}/missing-reality-stream.conf"; }
    subscriptionWireGuardControlEnabled() { return 1; }
    selectCustomInstallType=
    currentInstallProtocolType=
    [[ -z "$(nginxRuntimeReasons)" ]]
    currentInstallProtocolType=","
    [[ -z "$(nginxRuntimeReasons)" ]]
    currentInstallProtocolType=",1,"
    [[ -z "$(nginxRuntimeReasons)" ]]
    currentInstallProtocolType=",21,"
    [[ "$(nginxRuntimeReasons)" == "当前协议入口" ]]
    currentInstallProtocolType=
    export PADM_NGINX_ERROR_LOG="${serviceTmp}/nginx-error.log"
    eval "$(declare -f updateSELinuxHTTPPortT | sed '1s/^updateSELinuxHTTPPortT/originalUpdateSELinuxHTTPPortT/')"
    journalctl() { printf '31300 Permission denied\n'; }
    getenforce() { printf 'Enforcing\n'; }
    semanage() {
        if [[ "$1" == "port" && "$2" == "-l" ]]; then
            printf 'http_port_t tcp 80\n'
            return 0
        fi
        return 1
    }
    if originalUpdateSELinuxHTTPPortT >/dev/null 2>&1; then
        return 1
    fi
    unset -f journalctl getenforce semanage
    updateSELinuxHTTPPortT() {
        printf 'update\n' >>"${serviceTmp}/selinux-update"
        return 0
    }
    protocolSelectionSkipsNginx() { return 1; }
    nginxServiceInstalled() { return 0; }
    padmReadProcExe() {
        [[ "$1" == "/proc/12345/exe" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]] || return 1
        printf '/usr/sbin/nginx\n'
    }
    padmReadProcCmdline() {
        [[ "$1" == "/proc/12345/cmdline" && "$(cat "${PADM_FAKE_NGINX_STATE_FILE}" 2>/dev/null)" == "true" ]] || return 1
        printf 'nginx: master process nginx\n'
    }
    release=centos
    selectCustomInstallType=",21,"
    btDomain=
    SERVICE_QUEUE_ALLOW_FAILURE=true
    export PADM_FAKE_NGINX_STATE_FILE="${serviceTmp}/nginx-running"
    export PADM_NGINX_ERROR_LOG="${serviceTmp}/nginx-error.log"
    export PADM_FAKE_SYSTEMCTL_ACTIONS="${serviceTmp}/systemctl-actions"
    export PADM_FAKE_SYSTEMCTL_RETRY_MARKER="${serviceTmp}/selinux-retry"
    export PADM_FAKE_NGINX_FORCE_KILL_LOG="${serviceTmp}/nginx-force-kill"
    export PADM_FAKE_NGINX_ACTIONS="${serviceTmp}/nginx-actions"
    xargs() { printf '%s\n' "$*" >>"${PADM_FAKE_NGINX_FORCE_KILL_LOG}"; }

    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false handleNginx start >/dev/null 2>&1 && return 1
    local noExitMarker="${serviceTmp}/nginx-no-exit"
    SERVICE_QUEUE_ALLOW_FAILURE=
    (
        set +e
        PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false handleNginx start >/dev/null 2>&1
        printf 'reached\n' >"${noExitMarker}"
    )
    [[ -e "${noExitMarker}" ]]
    SERVICE_QUEUE_ALLOW_FAILURE=true
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=true handleNginx stop >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(cat "${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=true handleNginx start >/dev/null 2>&1
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    PADM_FAKE_SYSTEMCTL_STOP_RC=0 PADM_FAKE_SYSTEMCTL_STOP_STATE=false handleNginx stop >/dev/null 2>&1

    : >"${PADM_FAKE_NGINX_ACTIONS}"
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if PADM_FAKE_NGINX_TEST_RC=1 handleNginx reload >/dev/null 2>&1; then
        return 1
    fi
    grep -qx -- '-t' "${PADM_FAKE_NGINX_ACTIONS}"
    ! grep -q -- '-s reload' "${PADM_FAKE_NGINX_ACTIONS}"
    : >"${PADM_FAKE_NGINX_ACTIONS}"
    PADM_FAKE_NGINX_TEST_RC=0 handleNginx reload >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_ACTIONS}")" == $'-t\n-s reload' ]]

    : >"${PADM_FAKE_NGINX_FORCE_KILL_LOG}"
    printf 'true\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if PADM_FAKE_SYSTEMCTL_STOP_RC=1 handleNginx stop >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    [[ ! -s "${PADM_FAKE_NGINX_FORCE_KILL_LOG}" ]]

    mkdir -p "${serviceTmp}/nginx"
    nginxConfigPath="${serviceTmp}/nginx/"
    selectCustomInstallType=",1,"
    protocolSelectionSkipsNginx() { return 0; }
    subscriptionWireGuardControlEnabled() { return 1; }
    local streamFallbackFile="${serviceTmp}/padm-reality.conf"
    local nginxFallbackFile
    realityStreamSplitConfFile() { printf '%s\n' "${streamFallbackFile}"; }
    command() {
        if [[ "$1" == "-v" && "$2" == "jq" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    subscriptionWireGuardControlEnabled() { return 0; }
    if nginxRuntimeRequired; then
        return 1
    fi
    for nginxFallbackFile in \
        "${streamFallbackFile}" \
        "${nginxConfigPath}alone.conf" \
        "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" \
        "${nginxConfigPath}subscribe.conf" \
        "${nginxConfigPath}padm-control-wg.conf"; do
        : >"${nginxFallbackFile}"
        nginxRuntimeRequired
        rm -f "${nginxFallbackFile}"
    done
    unset -f command
    subscriptionWireGuardControlEnabled() { return 1; }
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "false" ]]
    handleNginx start restore >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]] || return 1
    handleNginx stop >/dev/null 2>&1
    : >"${nginxConfigPath}subscribe.conf"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    rm -f "${nginxConfigPath}subscribe.conf"
    handleNginx stop >/dev/null 2>&1
    : >"${nginxConfigPath}padm-control-wg.conf"
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    rm -f "${nginxConfigPath}padm-control-wg.conf"
    handleNginx stop >/dev/null 2>&1
    subscriptionWireGuardControlEnabled() { return 0; }
    handleNginx start >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    subscriptionWireGuardControlEnabled() { return 1; }
    SERVICE_ACTIONS=
    serviceQueueRestart nginx
    serviceQueueApply >/dev/null 2>&1
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]] || return 1
    protocolSelectionSkipsNginx() { return 1; }
    subscriptionWireGuardControlEnabled() { return 1; }

    : >"${PADM_FAKE_SYSTEMCTL_ACTIONS}"
    rm -f "${PADM_FAKE_SYSTEMCTL_RETRY_MARKER}"
    export PADM_FAKE_SYSTEMCTL_RETRY_ONCE=true
    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    if ! handleNginx start >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${PADM_FAKE_NGINX_STATE_FILE}")" == "true" ]]
    [[ "$(grep -c '^start nginx$' "${PADM_FAKE_SYSTEMCTL_ACTIONS}")" == "2" ]]
    [[ "$(grep -c '^update$' "${serviceTmp}/selinux-update")" == "1" ]]
    unset PADM_FAKE_SYSTEMCTL_RETRY_ONCE

    printf 'false\n' >"${PADM_FAKE_NGINX_STATE_FILE}"
    SERVICE_ACTIONS=
    serviceQueueStart nginx
    serviceQueueStop nginx
    if PADM_FAKE_SYSTEMCTL_START_RC=0 PADM_FAKE_SYSTEMCTL_START_STATE=false serviceQueueApply >/dev/null 2>&1; then
        return 1
    fi
    [[ -z "${SERVICE_ACTIONS}" ]]

    local xrayWaitLog="${serviceTmp}/xray-wait.log"
    find() {
        if [[ "$*" == *'systemctl'* ]]; then
            printf '/usr/bin/systemctl\n'
            return 0
        fi
        if [[ "$*" == *'xray.service'* ]]; then
            printf '/etc/systemd/system/xray.service\n'
            return 0
        fi
        command find "$@"
    }
    systemctl() { return 0; }
    xrayRunning() { return 0; }
    waitForServiceState() {
        printf '%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${xrayWaitLog}"
        return 0
    }
    handleXray stop >/dev/null
    if ! grep -qx 'xrayRunning:stopped:60:0.1' "${xrayWaitLog}"; then
        cat "${xrayWaitLog}" >&2 || true
        return 1
    fi

    local xrayStartLimitLog="${serviceTmp}/xray-start-limit.log"
    local xrayRunningState="${serviceTmp}/xray-running"
    : >"${xrayStartLimitLog}"
    printf 'false\n' >"${xrayRunningState}"
    xrayRunning() {
        [[ "$(<"${xrayRunningState}")" == "true" ]]
    }
    waitForServiceState() {
        printf '%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${xrayWaitLog}"
        [[ "${2}" == "running" ]] && xrayRunning
    }
    systemctl() {
        printf '%s\n' "$*" >>"${xrayStartLimitLog}"
        case "$1" in
        start)
            if ! grep -qx 'reset-failed xray.service' "${xrayStartLimitLog}"; then
                return 1
            fi
            printf 'true\n' >"${xrayRunningState}"
            return 0
            ;;
        reset-failed)
            return 0
            ;;
        esac
        return 0
    }
    SERVICE_QUEUE_ALLOW_FAILURE=true
    if ! handleXray start >/dev/null 2>&1; then
        cat "${xrayStartLimitLog}" >&2 || true
        cat "${xrayWaitLog}" >&2 || true
        return 1
    fi
    grep -qx 'reset-failed xray.service' "${xrayStartLimitLog}" || return 1
    [[ "$(grep -c '^start xray.service$' "${xrayStartLimitLog}")" == "2" ]] || return 1
    grep -qx 'xrayRunning:running:25:0.1' "${xrayWaitLog}" || return 1
    [[ "$(<"${xrayRunningState}")" == "true" ]] || return 1

    local xrayNoExitMarker="${serviceTmp}/xray-no-exit"
    SERVICE_QUEUE_ALLOW_FAILURE=
    xrayRunning() { return 1; }
    xraySystemdStart() { return 1; }
    waitForServiceState() { return 1; }
    (
        set +e
        handleXray start >/dev/null 2>&1
        printf 'reached\n' >"${xrayNoExitMarker}"
    )
    [[ -e "${xrayNoExitMarker}" ]]

    local singBoxNoExitMarker="${serviceTmp}/sing-box-no-exit"
    export PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${serviceTmp}/sing-box.service"
    : >"${PADM_SINGBOX_SYSTEMD_SERVICE_FILE}"
    singBoxRunning() { return 1; }
    singBoxMergeConfig() { return 1; }
    (
        set +e
        handleSingBox start >/dev/null 2>&1
        printf 'reached\n' >"${singBoxNoExitMarker}"
    )
    [[ -e "${singBoxNoExitMarker}" ]]
    rm -rf "${serviceTmp}"
)

runNginxServiceRefreshRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/nginx-service-refresh"
    local actionLog="${root}/actions.log"
    local nginxState=running
    local nginxRequired=false
    local nginxTestRc=0

    rm -rf "${root}"
    mkdir -p "${root}"
    source "${PROJECT_ROOT}/shell/core/services.sh"
    errorCard() { return 0; }
    menuLine() { return 0; }
    uiStyle() { printf '%s' "${2:-}"; }
    nginxRunning() { [[ "${nginxState}" == "running" ]]; }
    nginxRuntimeRequired() { [[ "${nginxRequired}" == "true" ]]; }
    nginx() {
        printf 'nginx:%s\n' "$*" >>"${actionLog}"
        [[ "$1" != "-t" ]] || return "${nginxTestRc}"
        return 0
    }
    eval "$(declare -f handleNginx | sed '1s/^handleNginx/originalHandleNginx/')"
    handleNginx() {
        if [[ "$1" == "start" ]]; then
            printf 'start\n' >>"${actionLog}"
            return 0
        fi
        originalHandleNginx "$@"
    }
    export PADM_NGINX_ERROR_LOG="${root}/nginx-error.log"

    : >"${actionLog}"
    nginxTestRc=1
    if runServiceAction nginx refresh >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${actionLog}")" == 'nginx:-t' ]]

    : >"${actionLog}"
    nginxTestRc=0
    nginxState=running
    runServiceAction nginx refresh >/dev/null 2>&1
    [[ "$(<"${actionLog}")" == $'nginx:-t\nnginx:-s reload' ]]

    : >"${actionLog}"
    nginxState=stopped
    nginxRequired=true
    runServiceAction nginx refresh >/dev/null 2>&1
    [[ "$(<"${actionLog}")" == $'nginx:-t\nstart' ]]

    : >"${actionLog}"
    nginxRequired=false
    runServiceAction nginx refresh >/dev/null 2>&1
    [[ "$(<"${actionLog}")" == 'nginx:-t' ]]
)

runUninstallWireGuardCleanupRegression() (
    local actions=
    local mode=success
    local rc
    local targetDir="${TMP_DIR}/uninstall-wireguard"
    local oldWireGuardDir="${PADM_WIREGUARD_CONTROL_DIR:-}"
    PADM_WIREGUARD_CONTROL_DIR="${targetDir}/state"
    mkdir -p "${PADM_WIREGUARD_CONTROL_DIR}" "${targetDir}/etc-wireguard" "${targetDir}/systemd"
    subscriptionWireGuardWriteState '.'
    printf 'private\n' >"$(subscriptionWireGuardPrivateKeyFile)"
    printf 'public\n' >"$(subscriptionWireGuardPublicKeyFile)"
    printf 'keep\n' >"${PADM_WIREGUARD_CONTROL_DIR}/unmanaged"
    removeInstallPath() { actions+="remove:$1:$2"$'\n'; rm -rf "$1"; }
    systemctl() {
        actions+="systemctl:$*"$'\n'
        if [[ "${mode}" == "wg-stop-fail" && "$*" == "disable --now wg-quick@wg-padm" ]]; then
            return 1
        fi
        if [[ "${mode}" == "control-stop-fail" && "$*" == "disable --now padm-subscription-control.service" ]]; then
            return 1
        fi
        return 0
    }
    command() {
        if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    subscriptionWireGuardConfigFile() { printf '%s\n' "${targetDir}/etc-wireguard/wg-padm.conf"; }
    subscriptionControlServiceFile() { printf '%s\n' "${targetDir}/systemd/padm-subscription-control.service"; }
    printf 'wg\n' >"$(subscriptionWireGuardConfigFile)"
    printf 'svc\n' >"$(subscriptionControlServiceFile)"

    for mode in wg-stop-fail control-stop-fail; do
        actions=
        regressionExpectStatus 1 cleanupSubscriptionWireGuardControlOnUninstall >/dev/null 2>&1
        [[ -e "$(subscriptionWireGuardConfigFile)" ]]
        [[ -e "$(subscriptionWireGuardStateFile)" ]]
        [[ -e "$(subscriptionWireGuardPrivateKeyFile)" ]]
        [[ -e "$(subscriptionWireGuardPublicKeyFile)" ]]
        [[ -e "$(subscriptionControlServiceFile)" ]]
    done

    mode=success
    actions=
    cleanupSubscriptionWireGuardControlOnUninstall
    grep -qxF 'systemctl:disable --now wg-quick@wg-padm' <<<"${actions}"
    grep -qxF 'systemctl:disable --now padm-subscription-control.service' <<<"${actions}"
    [[ ! -e "$(subscriptionWireGuardConfigFile)" ]]
    [[ ! -e "$(subscriptionWireGuardStateFile)" ]]
    [[ ! -e "$(subscriptionWireGuardPrivateKeyFile)" ]]
    [[ ! -e "$(subscriptionWireGuardPublicKeyFile)" ]]
    [[ ! -e "$(subscriptionControlServiceFile)" ]]
    [[ -e "${PADM_WIREGUARD_CONTROL_DIR}/unmanaged" ]]

    local nginxTarget="${targetDir}/nginx/padm-control-wg.conf"
    local nginxBackupDir=
    local nginxRuntimeState=true
    mkdir -p "$(dirname "${nginxTarget}")"
    printf 'old-nginx\n' >"${nginxTarget}"
    checkLogBackupCreate nginxBackupDir "${nginxTarget}"
    printf 'new-nginx\n' >"${nginxTarget}"
    actions=
    subscriptionWireGuardWriteState() { actions+="state-restored"$'\n'; return 0; }
    applySubscriptionWireGuardService() { actions+="wireguard-restored"$'\n'; return 0; }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
    handleNginx() {
        actions+="nginx:$1:${SERVICE_QUEUE_ALLOW_FAILURE:-}"$'\n'
        [[ -n "${2:-}" ]] && actions+="nginx-mode:$*"$'\n'
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
        return 0
    }
    subscriptionWireGuardRestoreStateAndConfig \
        '{"enabled":true,"address":"10.77.0.2/24"}' \
        "${nginxBackupDir}" \
        true
    grep -qxF 'old-nginx' "${nginxTarget}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -qx 'nginx:stop:true' <<<"${actions}"
    grep -qx 'nginx:start:true' <<<"${actions}"
    grep -qx 'nginx-mode:start restore' <<<"${actions}" || return 1
    [[ ! -e "${nginxBackupDir}" ]]

    printf 'old-nginx-after-state-failure\n' >"${nginxTarget}"
    checkLogBackupCreate nginxBackupDir "${nginxTarget}"
    printf 'new-nginx-after-state-failure\n' >"${nginxTarget}"
    actions=
    subscriptionWireGuardWriteState() { actions+="state-restore-failed"$'\n'; return 1; }
    set +e
    subscriptionWireGuardRestoreStateAndConfig \
        '{"enabled":true,"address":"10.77.0.2/24"}' \
        "${nginxBackupDir}" \
        true
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]
    grep -qxF 'old-nginx-after-state-failure' "${nginxTarget}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -qx 'state-restore-failed' <<<"${actions}"
    grep -qx 'nginx:stop:true' <<<"${actions}"
    grep -qx 'nginx:start:true' <<<"${actions}"
    [[ -d "${nginxBackupDir}" ]]
    padmRemoveCleanupPath "${nginxBackupDir}"

    if [[ -n "${oldWireGuardDir}" ]]; then PADM_WIREGUARD_CONTROL_DIR="${oldWireGuardDir}"; else unset PADM_WIREGUARD_CONTROL_DIR; fi
)

runWarpConfigSafeDirRegression() (
    local root="${TMP_DIR}/warp-config-safe-dir"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    PADM_WARP_DIR=relative-warp
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    regressionExpectStatus 1 readConfigWarpReg >/dev/null 2>&1
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${errorLog}" ]]

    regressionExpectStatus 1 installWarpReg >/dev/null 2>&1
    [[ ! -s "${rmLog}" ]]
    [[ ! -s "${errorLog}" ]]

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-stale"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local downloadMarker="${root}/warp-stale-download"
        mkdir -p "${PADM_WARP_DIR}"
        printf 'stale\n' >"${PADM_WARP_DIR}/warp-reg"
        chmod 644 "${PADM_WARP_DIR}/warp-reg"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { :; }
        downloadGitHubReleaseAsset() {
            : >"${downloadMarker}"
            printf '#!/usr/bin/env sh\n' >"${2%/}/$5"
        }
        installWarpReg
        [[ -e "${downloadMarker}" ]]
        [[ -x "${PADM_WARP_DIR}/warp-reg" ]]
    )

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-download-fail"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local callerMarker="${root}/warp-caller-reached"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { :; }
        downloadGitHubReleaseAsset() { return 1; }
        regressionExpectStatus 1 installWarpReg >/dev/null 2>&1
        : >"${callerMarker}"
        [[ -f "${callerMarker}" ]]
    )

    local cancelMarker="${root}/warp-cancel-caller-reached"
    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-cancel"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" n; }
        coreCancelledStatusCard() { :; }
        regressionExpectStatus 1 installWarpReg >/dev/null 2>&1
        : >"${cancelMarker}"
    )
    [[ -f "${cancelMarker}" ]]

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp-latest"
        warpRegCoreCPUVendor="warp-reg-linux-amd64"
        local versionLog="${root}/warp-download-version.log"
        mkdir -p "${PADM_WARP_DIR}"
        echoContent() { :; }
        menuLine() { :; }
        menuClose() { :; }
        autoRead() { printf -v "$3" y; }
        errorCard() { return 1; }
        downloadGitHubReleaseAsset() {
            [[ "$1" == "-P" && "$3" == "badafans/warp-reg" && "$4" == "v1.0" && "$5" == "${warpRegCoreCPUVendor}" ]] || return 1
            printf '%s\n' "$4" >"${versionLog}"
            printf '#!/usr/bin/env sh\n' >"${2%/}/$5"
        }
        installWarpReg >/dev/null 2>&1
        [[ "$(<"${versionLog}")" == "v1.0" ]]
        [[ -s "${PADM_WARP_DIR}/warp-reg" ]]
        [[ "$(stat -c '%a' "${PADM_WARP_DIR}/warp-reg")" == "755" ]]
    )

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        coreInstallType=1
        configPath="${root}/xray/"
        singBoxConfigPath=
        mkdir -p "${configPath}"
        regressionExpectStatus 1 unInstallWireGuard IPv4 >/dev/null 2>&1
    )
    [[ ! -s "${rmLog}" ]]
)

runWireGuardControlSafeDirRegression() (
    local root="${TMP_DIR}/wireguard-control-safe-dir"
    local rmLog="${root}/rm.log"
    local rc

    mkdir -p "${root}"
    : >"${rmLog}"
    PADM_WIREGUARD_CONTROL_DIR=relative-wireguard

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    regressionExpectStatus 1 subscriptionWireGuardWriteState '.enabled = true' >/dev/null 2>&1
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${root}/relative-wireguard" ]]

    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    unset -f rm
    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ ! -e "${root}/relative-wireguard" ]]
)

runWireGuardKeyTransactionRegression() (
    local rootRel="${TMP_DIR}/wireguard-key-transaction"
    local root wireGuardDir privateKeyFile publicKeyFile
    local rc

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    wireGuardDir="${root}/wireguard"
    privateKeyFile="${wireGuardDir}/private.key"
    publicKeyFile="${wireGuardDir}/public.key"
    PADM_WIREGUARD_CONTROL_DIR="${wireGuardDir}"

    wg() {
        case "${1:-}" in
        genkey)
            printf 'generated-private-key\n'
            ;;
        pubkey)
            cat >/dev/null
            printf 'generated-public-key\n'
            ;;
        *)
            return 1
            ;;
        esac
    }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${publicKeyFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ ! -e "${privateKeyFile}" ]]
    [[ ! -e "${publicKeyFile}" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    mkdir -p "${wireGuardDir}"
    printf 'existing-private-key\n' >"${privateKeyFile}"
    printf 'existing-public-key\n' >"${publicKeyFile}"

    regressionExpectStatus 1 subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ "$(<"${privateKeyFile}")" == "existing-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "existing-public-key" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ "$(<"${privateKeyFile}")" == "existing-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "generated-public-key" ]]

    rm -f "${privateKeyFile}" "${publicKeyFile}"
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    [[ "$(<"${privateKeyFile}")" == "generated-private-key" ]]
    [[ "$(<"${publicKeyFile}")" == "generated-public-key" ]]
    if regressionFindHasMatches "${wireGuardDir}" -maxdepth 1 -type f -name '.*.wireguard.*'; then
        return 1
    fi

    command chmod 644 "${privateKeyFile}"
    chmod() {
        if [[ "$1" == "600" && "$2" == "${privateKeyFile}" ]]; then
            return 1
        fi
        command chmod "$@"
    }
    set +e
    subscriptionWireGuardEnsureKeys >/dev/null 2>&1
    rc=$?
    set -e
    unset -f chmod
    [[ "${rc}" == "1" ]]
    [[ "$(stat -c '%a' "${privateKeyFile}")" == "644" ]]
)

runWarpConfigFileCleanupRegression() (
    local rootRel="${TMP_DIR}/warp-config-file-cleanup"
    local root rmLog

    mkdir -p "${rootRel}/warp" "${rootRel}/xray"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    : >"${rmLog}"
    printf 'config\n' >"${root}/warp/config"

    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp"
        coreInstallType=1
        configPath="${root}/xray/"
        singBoxConfigPath=
        rm() {
            printf 'rm:%s\n' "$*" >>"${rmLog}"
            command rm "$@"
        }
        unInstallWireGuard IPv4
    )

    grep -qxF "rm:-f -- ${root}/warp/config" "${rmLog}"
    ! grep -q "rm:-rf ${root}/warp/config" "${rmLog}"
    [[ ! -e "${root}/warp/config" ]]

    printf 'config\n' >"${root}/warp/config"
    mkdir -p "${root}/sing-box"
    printf '{}\n' >"${root}/sing-box/wireguard_endpoints_IPv4.json"
    printf '{}\n' >"${root}/sing-box/wireguard_endpoints_IPv6.json"
    (
        source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
        PADM_WARP_DIR="${root}/warp"
        coreInstallType=2
        configPath=
        singBoxConfigPath="${root}/sing-box/"
        removeSingBoxRouteRule() { return 0; }
        removeSingBoxConfig() { rm -f -- "${singBoxConfigPath}$1.json"; }
        addSingBoxOutbound() { return 0; }

        removeWireGuardRoutingConfig IPv4
        [[ -f "${PADM_WARP_DIR}/config" ]]
        [[ -f "${singBoxConfigPath}wireguard_endpoints_IPv6.json" ]]
        removeWireGuardRoutingConfig IPv6
        [[ ! -e "${PADM_WARP_DIR}/config" ]]
    )
)

runUninstallNginxCleanupRegression() {
    local primaryDir="${TMP_DIR}/uninstall-nginx-primary/"
    local actualDir="${TMP_DIR}/uninstall-nginx-actual/"
    local oldNginxConfigPath="${nginxConfigPath:-}"
    local oldFallbackDir="${PADM_NGINX_CONF_FALLBACK_DIR:-}"
    local name

    mkdir -p "${primaryDir}" "${actualDir}"
    nginxConfigPath="${primaryDir}"
    PADM_NGINX_CONF_FALLBACK_DIR="${actualDir}"
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        printf 'padm config\n' >"${primaryDir}${name}"
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        printf 'padm config\n' >"${actualDir}${name}"
    done

    removePadmNginxConfigFragments
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        [[ ! -e "${primaryDir}${name}" ]]
    done
    for name in sing_box_VMess_HTTPUpgrade.conf subscribe.conf padm-control-wg.conf; do
        [[ ! -e "${actualDir}${name}" ]]
    done

    local installedCrontab=
    readUserCrontabContent() {
        printf '%s\n' \
            '30 1 * * * /bin/bash /etc/padm/install.sh RenewTLS >> /etc/padm/crontab_tls.log 2>&1' \
            '35 1 * * * /bin/bash /etc/padm/install.sh UpdateGeo >> /etc/padm/crontab_tls.log 2>&1' \
            '* * * * * /bin/bash /etc/padm/install.sh SyncSubscriptionGroups' \
            '5 5 * * * /usr/local/bin/keep'
    }
    installUserCrontabContent() { installedCrontab=$1; }
    crontab() { return 0; }
    cleanupPadmCronJobsOnUninstall
    [[ "${installedCrontab}" == '5 5 * * * /usr/local/bin/keep' ]]

    nginxConfigPath="${oldNginxConfigPath}"
    PADM_NGINX_CONF_FALLBACK_DIR="${oldFallbackDir}"
}

runCleanAgentNginxManagedRemovalRegression() (
    local rootRel="${TMP_DIR}/clean-agent-nginx-managed-removal"
    local root
    local rmLog
    local includeLog
    local name

    mkdir -p "${rootRel}/nginx"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    includeLog="${root}/include.log"
    : >"${rmLog}"
    : >"${includeLog}"

    nginxConfigPath="${root}/nginx/"
    PADM_REALITY_STREAM_CONF_FILE="${root}/reality-stream.conf"
    PADM_REALITY_STREAM_STATE_FILE="${root}/reality-stream.json"

    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        printf 'managed\n' >"${root}/nginx/${name}"
    done
    printf 'stream\n' >"${root}/reality-stream.conf"
    printf 'state\n' >"${root}/reality-stream.json"

    removeRealityStreamNginxInclude() {
        printf 'remove-include\n' >>"${includeLog}"
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    cleanAgentNginxConf
    for name in alone.conf checkPortOpen.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf; do
        grep -qxF "rm:-f -- ${root}/nginx/${name}" "${rmLog}"
        [[ ! -e "${root}/nginx/${name}" ]]
    done
    grep -qxF "rm:-f -- ${root}/reality-stream.conf" "${rmLog}"
    grep -qxF "rm:-f -- ${root}/reality-stream.json" "${rmLog}"
    [[ ! -e "${root}/reality-stream.conf" ]]
    [[ ! -e "${root}/reality-stream.json" ]]
    grep -qx 'remove-include' "${includeLog}"

    : >"${rmLog}"
    nginxConfigPath="relative-nginx/"
    if cleanAgentNginxConf >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${rmLog}" ]]
)

runFail2banManagedCleanupRegression() (
    local rootRel="${TMP_DIR}/fail2ban-managed-cleanup"
    local root
    local rmLog

    mkdir -p "${rootRel}/jail.d" "${rootRel}/filter.d" "${rootRel}/log"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    : >"${rmLog}"

    PADM_FAIL2BAN_JAIL_FILE="${root}/jail.d/padm.local"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"

    printf 'jail\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'filter\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }

    fail2banRemoveManagedFiles
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_JAIL_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_FILTER_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" "${rmLog}"
    grep -qxF "rm:-f -- ${PADM_FAIL2BAN_CONTROL_LOG_FILE}" "${rmLog}"
    [[ ! -e "${PADM_FAIL2BAN_JAIL_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_CONTROL_LOG_FILE}" ]]

    : >"${rmLog}"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"
    printf 'filter-again\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan-again\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log-again\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"
    PADM_FAIL2BAN_JAIL_FILE="relative/padm.local"
    if fail2banRemoveManagedFiles >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -s "${rmLog}" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "filter-again" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "scan-again" ]]
    [[ "$(<"${PADM_FAIL2BAN_CONTROL_LOG_FILE}")" == "log-again" ]]

    PADM_FAIL2BAN_JAIL_FILE="${root}/jail.d/padm.local"
    PADM_FAIL2BAN_FILTER_FILE="${root}/filter.d/padm-control.conf"
    PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/filter.d/padm-nginx-scan-basic.conf"
    PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/log/padm-control-access.log"
    printf 'jail-uninstall\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'filter-uninstall\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'scan-uninstall\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'log-uninstall\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"
    fail2banReloadServiceIfRunning() { return 0; }

    cleanupFail2banManagedFilesOnUninstall
    [[ ! -e "${PADM_FAIL2BAN_JAIL_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}" ]]
    [[ ! -e "${PADM_FAIL2BAN_CONTROL_LOG_FILE}" ]]
)

runFail2banApplyTransactionRegression() (
    local rootRel="${TMP_DIR}/fail2ban-apply-transaction"
    local root
    local errorLog="${TMP_DIR}/fail2ban-apply-transaction-errors.log"
    local rc
    local jailCommitFailures=0

    eval "$(declare -f fail2banStartOrReloadService | sed '1s/^fail2banStartOrReloadService/originalFail2banStartOrReloadService/')"

    mkdir -p "${rootRel}/fail2ban/jail.d" "${rootRel}/fail2ban/filter.d"
    root=$(cd -- "${rootRel}" && pwd -P)
    export TMPDIR="${root}"
    export PADM_FAIL2BAN_JAIL_FILE="${root}/fail2ban/jail.d/padm.local"
    export PADM_FAIL2BAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-control.conf"
    export PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-nginx-scan-basic.conf"
    export PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/fail2ban/log/padm-control-access.log"
    export PADM_FAIL2BAN_VALIDATE_LOG="${root}/fail2ban/validate.log"
    : >"${errorLog}"

    mkdir -p "$(dirname "${PADM_FAIL2BAN_CONTROL_LOG_FILE}")"
    printf 'legacy jail\n' >"${PADM_FAIL2BAN_JAIL_FILE}"
    printf 'legacy filter\n' >"${PADM_FAIL2BAN_FILTER_FILE}"
    printf 'legacy scan\n' >"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    printf 'legacy control log\n' >"${PADM_FAIL2BAN_CONTROL_LOG_FILE}"

    fail2banServiceActive() { return 1; }
    fail2banServiceEnabled() { return 1; }
    fail2banInstalled() { return 0; }
    fail2banSystemdServiceInstalled() { return 1; }
    fail2banOpenRcServiceInstalled() { return 1; }
    fail2banValidateManagedConfig() { return 0; }
    fail2banStartOrReloadService() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${PADM_FAIL2BAN_JAIL_FILE}" && "${jailCommitFailures}" == "0" ]]; then
            jailCommitFailures=1
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 fail2banApplyProfile sshd false >/dev/null 2>&1
    [[ "$(<"${PADM_FAIL2BAN_JAIL_FILE}")" == "legacy jail" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "legacy filter" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "legacy scan" ]]
    ! compgen -G "${root}/fail2ban/jail.d/.padm.local.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-control.conf.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-nginx-scan-basic.conf.fail2ban.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    fail2banReloadServiceIfRunning() { return 1; }
    regressionExpectStatus 1 fail2banApplyProfile disabled false >/dev/null 2>&1
    [[ "$(<"${PADM_FAIL2BAN_JAIL_FILE}")" == "legacy jail" ]]
    [[ "$(<"${PADM_FAIL2BAN_FILTER_FILE}")" == "legacy filter" ]]
    [[ "$(<"${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}")" == "legacy scan" ]]
    [[ "$(<"${PADM_FAIL2BAN_CONTROL_LOG_FILE}")" == "legacy control log" ]]

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    fail2banApplyProfile sshd false >/dev/null
    grep -q '^\[sshd\]' "${PADM_FAIL2BAN_JAIL_FILE}"
    grep -q '^enabled = true$' "${PADM_FAIL2BAN_JAIL_FILE}"
    grep -q '/s/control/' "${PADM_FAIL2BAN_FILTER_FILE}"
    grep -Eq 'wp-login\.php|\.env|phpmyadmin|actuator' "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
    ! compgen -G "${root}/fail2ban/jail.d/.padm.local.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-control.conf.fail2ban.*" >/dev/null
    ! compgen -G "${root}/fail2ban/filter.d/.padm-nginx-scan-basic.conf.fail2ban.*" >/dev/null
    if regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
        return 1
    fi

    (
        fail2banSystemdServiceInstalled() { return 1; }
        fail2banOpenRcServiceInstalled() { return 0; }
        fail2banServiceActive() { return 1; }
        systemctl() { return 1; }
        rc-update() { return 1; }
        rc-service() { return 0; }
        if originalFail2banStartOrReloadService; then
            return 1
        fi
    )

    (
        checkLogBackupRestore() { return 0; }
        fail2banSystemdServiceInstalled() { return 0; }
        fail2banOpenRcServiceInstalled() { return 1; }
        fail2banServiceActive() { return 1; }
        systemctl() {
            [[ "$1" != "disable" ]]
        }
        if fail2banRestoreManagedFiles "${root}/unused-backup" false false; then
            return 1
        fi
    )
)

runUninstallServiceStopFailureRegression() (
    local root="${TMP_DIR}/uninstall-service-stop"
    local serviceLog="${root}/service.log"
    local actionLog="${root}/actions.log"
    local errorLog="${root}/errors.log"
    local rcFile="${root}/uninstall.rc"
    local mode shellRc rc
    local nginxState=false

    mkdir -p "${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    autoRead() { printf -v "$3" 'y'; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    menu() { return 0; }
    pgrep() { return 1; }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    xrayRunning() {
        [[ "${mode:-}" == "xray-still-running" ]]
    }
    singBoxRunning() {
        [[ "${mode:-}" == "sing-box-still-running" ]]
    }
    removeInstallPath() {
        printf 'remove:%s:%s\n' "$1" "$2" >>"${actionLog}"
        return 0
    }
    cleanupSubscriptionWireGuardControlOnUninstall() {
        printf 'wireguard-cleanup\n' >>"${actionLog}"
        [[ "${mode:-}" == "wireguard-cleanup-fail" ]] && return 1
        return 0
    }
    cleanupPadmManagedRootOnUninstall() {
        printf 'padm-root-cleanup\n' >>"${actionLog}"
        return 0
    }
    removePadmNginxConfigFragments() {
        printf 'nginx-fragments\n' >>"${actionLog}"
        return 0
    }
    unInstallSubscribe() {
        printf 'unsubscribe-cleanup\n' >>"${actionLog}"
        return 0
    }
    uninstallReloadSystemdUnits() {
        printf 'daemon-reload\n' >>"${serviceLog}"
        return 0
    }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${serviceLog}"
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        if [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "${mode}" == "sing-box-stop-fail" && "$1" == "stop" ]]; then
            [[ "${SERVICE_QUEUE_ALLOW_FAILURE:-}" == "true" ]] && return 1
            exit 0
        fi
        return 0
    }

    runUninstallStopFailureCase() {
        mode=$1
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",27,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            unInstall >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        ! grep -q '^remove:/etc/systemd/system/xray.service:' "${actionLog}"
        ! grep -q '^remove:/etc/systemd/system/sing-box.service:' "${actionLog}"
        grep -q '卸载未完全完成' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallStillRunningCase() {
        mode=$1
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxConfigPath="${root}/nginx/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            unInstall >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        grep -q '停止后仍在运行' "${errorLog}"
        grep -q '卸载未完全完成' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallNoNginxProtocolCase() {
        mode=nginx-stop-fail
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxConfigPath="${root}/nginx/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            unInstall >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "0" ]]
        ! grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        grep -qxF 'padm-root-cleanup' "${actionLog}"
        grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        grep -qx 'systemctl:disable xray.service' "${serviceLog}"
        grep -qx 'systemctl:disable sing-box.service' "${serviceLog}"
        [[ "$(grep -c '^daemon-reload$' "${serviceLog}")" == "2" ]]
        [[ ! -s "${errorLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallWireGuardCleanupFailureCase() {
        mode=wireguard-cleanup-fail
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        rm -f "${rcFile}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",1,"
        singBoxConfigPath=
        nginxConfigPath="${root}/nginx/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        set +e
        (
            set +e
            unInstall >/dev/null 2>&1
            printf '%s\n' "$?" >"${rcFile}"
        )
        shellRc=$?
        set -e
        [[ "${shellRc}" == "0" ]]
        [[ "$(<"${rcFile}")" == "1" ]]
        grep -qxF 'wireguard-cleanup' "${actionLog}"
        ! grep -qxF 'nginx-fragments' "${actionLog}"
        ! grep -qxF 'padm-root-cleanup' "${actionLog}"
        ! grep -qxF 'unsubscribe-cleanup' "${actionLog}"
        ! grep -qF 'remove:/usr/bin/padm:' "${actionLog}"
        ! grep -qF 'remove:/usr/sbin/padm:' "${actionLog}"
        grep -q 'WireGuard 控制面清理失败，已取消后续删除' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallRestoresNginxCase() {
        mode=success
        nginxState=true
        : >"${serviceLog}"
        : >"${actionLog}"
        : >"${errorLog}"
        release=centos
        coreInstallType=1
        currentInstallProtocolType=",27,"
        singBoxConfigPath="${root}/sing-box-conf/"
        nginxStaticPath="${root}/static"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        regressionExpectStatus 0 unInstall >/dev/null 2>&1
        [[ "${nginxState}" == "true" ]] || return 1
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qx 'nginx:start:true' "${serviceLog}" || return 1
        grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    }

    runUninstallStopFailureCase nginx-stop-fail
    runUninstallStopFailureCase xray-stop-fail
    runUninstallStopFailureCase sing-box-stop-fail
    runUninstallStillRunningCase xray-still-running
    runUninstallStillRunningCase sing-box-still-running
    runUninstallNoNginxProtocolCase
    runUninstallWireGuardCleanupFailureCase
    runUninstallRestoresNginxCase
)

runCleanLastInstallationConfigFailureRegression() (
    local root="${TMP_DIR}/clean-last-installation"
    local serviceLog="${root}/service.log"
    local cleanupLog="${root}/cleanup.log"
    local errorLog="${root}/error.log"
    local installLog="${root}/install.log"
    local mode rc
    local nginxState=true

    mkdir -p "${root}/nginx" "${root}/static"
    printf 'managed-static\n' >"${root}/static/check"
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${errorLog}"
    : >"${installLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    currentDefaultPort=443
    currentPort=
    customPort=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityGRPCPort=
    singBoxHysteria2Port=
    singBoxTuicPort=
    singBoxSocks5Port=
    hysteriaPort=
    tuicPort=
    nginxConfigPath="${root}/nginx/"
    nginxStaticPath="${root}/static"
    configPath="${root}/xray-conf/"

    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" ]] && return 1
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "sing-box-stop-fail" ]] && return 1
        return 0
    }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" ]] && return 1
        [[ "$1" == "stop" ]] && nginxState=false
        [[ "$1" == "start" ]] && nginxState=true
        return 0
    }
    nginxRunning() { [[ "${nginxState}" == "true" ]]; }
    cleanAgentNginxConf() {
        printf 'clean-agent\n' >>"${cleanupLog}"
        [[ "${mode}" != "clean-fail" ]]
    }
    cleanDirectoryContent() {
        printf 'clean-dir:%s\n' "$1" >>"${cleanupLog}"
        [[ "${mode}" == "clean-dir-tls-fail" && "$1" == "/etc/padm/tls" ]] && return 1
        return 0
    }
    readInstallType() { printf 'read-install-type\n' >>"${cleanupLog}"; }
    mkdirTools() { printf 'mkdir-tools\n' >>"${cleanupLog}"; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    showLastInstallationConfig() { return 0; }
    autoRead() { printf -v "$3" 'n'; }
    lsof() { return 1; }
    systemctl() {
        printf 'systemctl:%s\n' "$*" >>"${cleanupLog}"
        [[ "${mode}" == "daemon-reload-fail" && "$*" == "daemon-reload" ]] && return 1
        return 0
    }
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        [[ "${mode}" == "rm-warp-fail" && "$*" == "-f -- /etc/padm/warp/config" ]] && return 1
        [[ "${mode}" == "rm-static-fail" && "$1" == "-rf" && "$2" == "--" && "$3" == "${root}/static/" ]] && return 1
        return 0
    }
    unInstallSubscribe() { printf 'uninstall-subscribe\n' >>"${installLog}"; return 0; }
    installTools() { printf 'install-tools:%s\n' "$*" >>"${installLog}"; return 0; }
    initTLSNginxConfig() { printf 'init-tls:%s\n' "$*" >>"${installLog}"; return 0; }
    installTLS() { printf 'install-tls:%s\n' "$*" >>"${installLog}"; return 0; }
    randomPathFunction() { printf 'random-path:%s\n' "$*" >>"${installLog}"; return 0; }
    installXray() { printf 'install-xray:%s\n' "$*" >>"${installLog}"; return 0; }
    installXrayService() { printf 'install-xray-service:%s\n' "$*" >>"${installLog}"; return 0; }
    initXrayConfig() { printf 'init-xray-config:%s\n' "$*" >>"${installLog}"; return 0; }
    cleanUp() { printf 'cleanup-core:%s\n' "$*" >>"${installLog}"; return 0; }
    installCronTLS() { printf 'install-cron:%s\n' "$*" >>"${installLog}"; return 0; }
    nginxBlog() { printf 'nginx-blog:%s\n' "$*" >>"${installLog}"; return 0; }
    updateRedirectNginxConf() { printf 'update-redirect\n' >>"${installLog}"; return 0; }
    checkGFWStatue() { printf 'check-gfw:%s\n' "$*" >>"${installLog}"; return 0; }
    showAccounts() { printf 'show-accounts:%s\n' "$*" >>"${installLog}"; return 0; }

    runCleanFailureCase() {
        local failureMode=$1
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanupLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        regressionExpectStatus 1 cleanLastInstallationConfig >/dev/null 2>&1
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        [[ ! -s "${cleanupLog}" ]]
        grep -q '已取消清空上次安装配置' "${errorLog}"
    }

    runCleanFailureCase xray-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '^sing-box:' "${serviceLog}"

    runCleanFailureCase sing-box-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    ! grep -q '^nginx:' "${serviceLog}"

    runCleanFailureCase nginx-stop-fail
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"

    mode=clean-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${errorLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    regressionExpectStatus 1 cleanLastInstallationConfig >/dev/null 2>&1
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxState}" == "true" ]] || return 1
    grep -qx 'clean-agent' "${cleanupLog}"
    ! grep -q '^clean-dir:' "${cleanupLog}"
    ! grep -q '^read-install-type$' "${cleanupLog}"
    grep -q 'Nginx 配置清理失败，已取消清空上次安装配置' "${errorLog}"

    runCleanupStepFailureCase() {
        local failureMode=$1
        local expectedError=$2
        local expectedLastStep=$3
        local forbiddenNextStep=$4
        mode="${failureMode}"
        : >"${serviceLog}"
        : >"${cleanupLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        regressionExpectStatus 1 cleanLastInstallationConfig >/dev/null 2>&1
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -qx 'sing-box:stop:true' "${serviceLog}"
        grep -qx 'nginx:stop:true' "${serviceLog}"
        grep -qxF "${expectedLastStep}" "${cleanupLog}"
        ! grep -qxF "${forbiddenNextStep}" "${cleanupLog}"
        ! grep -q '^read-install-type$' "${cleanupLog}"
        ! grep -q '^mkdir-tools$' "${cleanupLog}"
        grep -q "${expectedError}" "${errorLog}"
    }

    runCleanupStepFailureCase clean-dir-tls-fail \
        'TLS 目录清理失败，已取消清空上次安装配置' \
        'clean-dir:/etc/padm/tls' \
        'clean-dir:/etc/padm/subscribe'

    runCleanupStepFailureCase rm-warp-fail \
        'WARP 配置清理失败，已取消清空上次安装配置' \
        'rm:-f -- /etc/padm/warp/config' \
        'rm:-f -- /etc/padm/cdn'

    runCleanupStepFailureCase daemon-reload-fail \
        'systemd 配置重载失败，已取消清空上次安装配置' \
        'systemctl:daemon-reload' \
        'read-install-type'

    runCleanupStepFailureCase rm-static-fail \
        '静态站点清理失败，已取消清空上次安装配置' \
        "rm:-rf -- ${root}/static/" \
        'read-install-type'

    local xrayOpenRcServiceFile="${root}/init.d/xray"
    local singBoxOpenRcServiceFile="${root}/init.d/sing-box"
    mkdir -p "${root}/init.d"
    printf 'xray-service\n' >"${xrayOpenRcServiceFile}"
    printf 'sing-box-service\n' >"${singBoxOpenRcServiceFile}"
    export PADM_XRAY_OPENRC_SERVICE_FILE="${xrayOpenRcServiceFile}"
    export PADM_SINGBOX_OPENRC_SERVICE_FILE="${singBoxOpenRcServiceFile}"
    release=alpine
    coreInstallType=1
    rc-update() {
        printf 'rc-update:%s\n' "$*" >>"${cleanupLog}"
        return 0
    }
    mode=
    : >"${cleanupLog}"
    cleanLastInstallationConfig >/dev/null 2>&1
    grep -qx 'rc-update:del xray default' "${cleanupLog}"
    grep -qx 'rc-update:del sing-box default' "${cleanupLog}"
    grep -qxF "rm:-f -- ${xrayOpenRcServiceFile}" "${cleanupLog}"
    grep -qxF "rm:-f -- ${singBoxOpenRcServiceFile}" "${cleanupLog}"
    ! grep -q '^systemctl:' "${cleanupLog}"
    release=debian
    coreInstallType=
    unset PADM_XRAY_OPENRC_SERVICE_FILE PADM_SINGBOX_OPENRC_SERVICE_FILE
    unset -f rc-update

    mode=xray-stop-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    regressionExpectStatus 1 readLastInstallationConfig >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    mode=xray-stop-fail
    : >"${serviceLog}"
    : >"${cleanupLog}"
    : >"${installLog}"
    btDomain=
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    [[ ! -s "${installLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
)

runCleanLastInstallationConfigAcmeHomeRegression() (
    local mode=$1
    local rootRel="${TMP_DIR}/clean-last-installation-acme-${mode}"
    local root workDir homeDir runDir expectedStatus

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    case "${mode}" in
    failure)
        workDir=${root}
        homeDir="${root}/home"
        runDir=${PWD}
        expectedStatus=1
        ;;
    relative-home)
        workDir="${root}/work"
        homeDir="${workDir}/relative-home"
        runDir=${workDir}
        expectedStatus=0
        ;;
    *) return 2 ;;
    esac

    local resolvedAcmeDir="${homeDir}/.acme.sh"
    local cleanupLog="${root}/cleanup.log"
    local errorLog="${root}/error.log"
    mkdir -p "${workDir}/nginx" "${workDir}/static" "${resolvedAcmeDir}"
    : >"${cleanupLog}"
    : >"${errorLog}"

    if [[ "${mode}" == "relative-home" ]]; then
        HOME=relative-home
    else
        HOME=${homeDir}
    fi
    currentDefaultPort=443
    currentPort=
    customPort=
    xrayVLESSRealityPort=
    xrayVLESSRealityXHTTPort=
    singBoxVLESSVisionPort=
    singBoxVLESSRealityVisionPort=
    singBoxVLESSRealityGRPCPort=
    singBoxHysteria2Port=
    singBoxTuicPort=
    singBoxSocks5Port=
    hysteriaPort=
    tuicPort=
    nginxConfigPath="${workDir}/nginx/"
    nginxStaticPath="${workDir}/static"
    configPath="${workDir}/xray-conf/"

    handleXray() { return 0; }
    handleSingBox() { return 0; }
    handleNginx() { return 0; }
    cleanAgentNginxConf() { return 0; }
    cleanDirectoryContent() { return 0; }
    readInstallType() { return 0; }
    mkdirTools() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    showLastInstallationConfig() { return 0; }
    autoRead() {
        if [[ "$1" == "clean_acme" ]]; then
            printf -v "$3" 'y'
        else
            printf -v "$3" 'n'
        fi
    }
    lsof() { return 1; }
    systemctl() { return 0; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${cleanupLog}"
        if [[ "${mode}" == "failure" ]]; then
            [[ "$*" != "-rf -- ${resolvedAcmeDir}" ]]
            return
        fi
        command rm "$@"
    }

    (
        cd "${runDir}"
        regressionExpectStatus "${expectedStatus}" cleanLastInstallationConfig >/dev/null 2>&1
        grep -qxF "rm:-rf -- ${resolvedAcmeDir}" "${cleanupLog}"
        case "${mode}" in
        failure)
            ! grep -q "/root/.acme.sh" "${cleanupLog}"
            grep -q "acme证书和账号配置清理失败" "${errorLog}"
            ;;
        relative-home)
            [[ ! -d "${resolvedAcmeDir}" ]]
            ! grep -q 'rm:-rf -- relative-home/.acme.sh' "${cleanupLog}"
            [[ ! -s "${errorLog}" ]]
            ;;
        esac
    )
)

runAloneNginxConfigWriteTransactionRegression() {
    local nginxRootRel="${TMP_DIR}/nginx-alone"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/alone.conf"
    nginxConfigPath="${nginxRoot}/"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${TMP_DIR}/fake-bin/nginx"
    PATH="${TMP_DIR}/fake-bin:${PATH}"
    domain=example.com
    port=443
    currentPath=padm
    nginxStaticPath="${TMP_DIR}/static"
    selectCustomInstallType=9
    printf 'old config\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if updateRedirectNginxConf 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${targetPath}")" == "old config" ]]
    [[ ! -e "${targetPath}.tmp" ]]

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-backup-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        cp() {
            if [[ "$1" == "-p" && "$2" == "${targetPath}" ]]; then
                return 1
            fi
            command cp "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "old config" ]]
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置备份失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1
    unset -f cp

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "old config" ]]
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置提交失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    printf 'old config\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-write-restore-error.log"
        : >"${errorLog}"
        restoreAloneNginxConfigBackup() {
            ALONE_NGINX_CONFIG_ERROR="Nginx 配置检测失败，且旧 alone.conf 恢复失败，请手动检查 ${targetPath} 和 ${targetPath}.bak"
            printf '%s\n' "${ALONE_NGINX_CONFIG_ERROR}" >>"${errorLog}"
            return 1
        }
        if updateRedirectNginxConf 2>/dev/null; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ "${ALONE_NGINX_CONFIG_ERROR}" == *"旧 alone.conf 恢复失败"* ]]
        grep -q '旧 alone.conf 恢复失败' "${errorLog}"
    ) || return 1
    printf 'old config\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    (
        local errorLog="${TMP_DIR}/nginx-alone-write-backup-cleanup-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        rm() {
            if [[ "$1" == "-f" && "$2" == "--" && "$3" == "${targetPath}.bak" ]]; then
                return 1
            fi
            command rm "$@"
        }
        export PADM_FAKE_NGINX_VALIDATE_MODE=success
        if updateRedirectNginxConf >/dev/null 2>&1; then
            return 1
        fi
        grep -q 'server_name example.com;' "${targetPath}"
        [[ -f "${targetPath}.bak" ]]
        grep -q 'Nginx 配置备份清理失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1
    printf 'old config\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    updateRedirectNginxConf
    grep -q 'server_name example.com;' "${targetPath}"
    [[ ! -e "${targetPath}.tmp" ]]
    [[ ! -e "${targetPath}.bak" ]]

    rm -f "${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-missing-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        if addNginx302 https://missing-alone.example >/dev/null 2>&1; then
            return 1
        fi
        [[ ! -e "${targetPath}" ]]
        grep -q '请先重建 alone.conf' "${errorLog}"
    ) || return 1

    currentInstallProtocolType=",0,2,24,27,"
    currentHost=example.com
    currentPort=443
    currentPath=padm
    rm -f "${targetPath}"
    ensureTraditionalTlsFallbackNginxConfig >/dev/null 2>&1
    grep -q 'server_name example.com;' "${targetPath}"
    grep -q 'location /padmgrpc {' "${targetPath}"
    grep -q 'listen 127.0.0.1:31302 http2 so_keepalive=on proxy_protocol;' "${targetPath}"

    (
        local serviceLog="${TMP_DIR}/nginx-alone-service.log"
        local errorLog="${TMP_DIR}/nginx-alone-error.log"
        : >"${serviceLog}"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        handleNginx() {
            printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        updateRedirectNginxConf >/dev/null 2>&1
        [[ ! -s "${serviceLog}" ]]
        [[ ! -s "${errorLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runAloneNginxUpdateTransactionRegression() {
    local nginxRootRel="${TMP_DIR}/nginx-alone-update"
    local nginxRoot targetPath
    local oldPath="${PATH}"
    mkdir -p "${TMP_DIR}/fake-bin" "${nginxRootRel}"
    nginxRoot=$(cd -- "${nginxRootRel}" && pwd -P)
    targetPath="${nginxRoot}/alone.conf"
    nginxConfigPath="${nginxRoot}/"
    cat >"${TMP_DIR}/fake-bin/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${TMP_DIR}/fake-bin/nginx"
    PATH="${TMP_DIR}/fake-bin:${PATH}"
    domain=example.com
    port=443
    currentPath=padm
    nginxStaticPath="${TMP_DIR}/static"

    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if removeNginx302 2>/dev/null; then
        return 1
    fi
    grep -q 'return 302 https://example.org;' "${targetPath}"

    (
        local errorLog="${TMP_DIR}/nginx-alone-update-restore-error.log"
        : >"${errorLog}"
        restoreAloneNginxConfigBackup() {
            ALONE_NGINX_CONFIG_ERROR="Nginx 配置检测失败，且旧 alone.conf 恢复失败，请手动检查 ${targetPath} 和 ${targetPath}.bak"
            printf '%s\n' "${ALONE_NGINX_CONFIG_ERROR}" >>"${errorLog}"
            return 1
        }
        if removeNginx302 2>/dev/null; then
            return 1
        fi
        ! grep -q 'return 302 https://example.org;' "${targetPath}"
        grep -q 'return 302 https://example.org;' "${targetPath}.bak"
        grep -q '旧 alone.conf 恢复失败' "${errorLog}"
    ) || return 1
    printf 'keep\nreturn 302 https://example.org;\nreturn 302 $scheme://example.org$request_uri;\n' >"${targetPath}"
    rm -f "${targetPath}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    removeNginx302
    ! grep -q 'return 302 https://example.org;' "${targetPath}"
    grep -q 'request_uri' "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if addNginx302 https://redirect.example 2>/dev/null; then
        return 1
    fi
    ! grep -q 'redirect.example' "${targetPath}"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    addNginx302 https://redirect.example
    grep -q "return 302 'https://redirect.example';" "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    if addNginx302 "https://malicious.example'; add_header X-Padm injected; #" >/dev/null 2>&1; then
        return 1
    fi
    ! grep -q 'X-Padm' "${targetPath}"

    printf 'server {\nlocation / {\n}\n}\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-update-commit-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${targetPath}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }
        if addNginx302 https://commit-fail.example >/dev/null 2>&1; then
            return 1
        fi
        ! grep -q 'commit-fail.example' "${targetPath}"
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.bak" ]]
        grep -q 'Nginx 配置提交失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    printf 'server {\n}\n' >"${targetPath}"
    (
        local errorLog="${TMP_DIR}/nginx-alone-add-editor-error.log"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        if addNginx302 https://missing-location.example >/dev/null 2>&1; then
            return 1
        fi
        ! grep -q 'missing-location.example' "${targetPath}"
        [[ ! -e "${targetPath}.tmp" ]]
        [[ ! -e "${targetPath}.tmp.rewrite" ]]
        grep -q 'Nginx 302 配置编辑失败' "${errorLog}"
        ! grep -q '已恢复旧 alone.conf' "${errorLog}"
    ) || return 1

    (
        local curlLog="${TMP_DIR}/nginx-302-curl.log"
        local serviceLog="${TMP_DIR}/nginx-302-service.log"
        PADM_ALONE_NGINX_BACKUP_FILE="${TMP_DIR}/alone_backup.conf"
        printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
        printf 'changed config\n' >"${targetPath}"
        currentHost=example.com
        currentPort=443
        curl() { printf '%s\n' "$*" >>"${curlLog}"; printf '200'; }
        serviceQueueRefresh() { printf 'refresh\n' >>"${serviceLog}"; }
        serviceQueueApply() { printf 'apply\n' >>"${serviceLog}"; }
        if checkNginx302 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${targetPath}")" == "backup config" ]]
        [[ ! -e "${PADM_ALONE_NGINX_BACKUP_FILE}" ]]
        grep -qx 'refresh' "${serviceLog}"
        grep -qx 'apply' "${serviceLog}"
        grep -q -- '--connect-timeout 5' "${curlLog}"
        grep -q -- '--max-time 15' "${curlLog}"

        printf 'backup config\n' >"${PADM_ALONE_NGINX_BACKUP_FILE}"
        printf 'changed config\n' >"${targetPath}"
        curl() { printf '302'; }
        checkNginx302
        [[ "$(<"${targetPath}")" == "changed config" ]]
    )

    (
        local actionLog="${TMP_DIR}/nginx-302-backup-failure.log"
        autoRead() { printf -v "$3" '1'; }
        ensureTraditionalTlsFallbackNginxConfig() { return 0; }
        backupNginxConfig() { printf 'backup\n' >>"${actionLog}"; return 1; }
        removeNginx302() { printf 'remove\n' >>"${actionLog}"; return 0; }
        set +e
        manageTraditionalTlsRedirect >/dev/null 2>&1
        local rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        ! grep -q '^remove$' "${actionLog}"
    )
    PATH="${oldPath}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runNginxBackupManualCheckRegression() {
    (
        set -euo pipefail
        local rootRel="${TMP_DIR}/nginx-backup-manual-check"
        local root targetPath backupPath
        local helperLog="${TMP_DIR}/nginx-backup-helper.log"
        local errorLog="${TMP_DIR}/nginx-backup-error.log"

        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        targetPath="${root}/alone.conf"
        backupPath="${root}/alone_backup.conf"
        nginxConfigPath="${root}/"
        PADM_ALONE_NGINX_BACKUP_FILE="${backupPath}"
        : >"${helperLog}"
        : >"${errorLog}"
        printf 'source config\n' >"${targetPath}"

        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        coreSetPairedFileManualCheckMessage() {
            coreSetManualCheckMessage "$1" "$2" " ${3} 和 ${4}"
        }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        successCard() { return 0; }

        backupManagedFileToPath() { return 1; }
        if backupNginxConfig backup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置文件备份失败| ${targetPath}" "${helperLog}"
        grep -q "nginx配置文件备份失败，请手动检查 ${targetPath}" "${errorLog}"

        : >"${helperLog}"
        : >"${errorLog}"
        printf 'backup config\n' >"${backupPath}"
        restoreManagedFileFromBackup() { return 1; }
        if backupNginxConfig restoreBackup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置文件恢复备份失败| ${targetPath} 和 ${backupPath}" "${helperLog}"
        grep -q "nginx配置文件恢复备份失败，请手动检查 ${targetPath} 和 ${backupPath}" "${errorLog}"

        : >"${helperLog}"
        : >"${errorLog}"
        printf 'backup config\n' >"${backupPath}"
        restoreManagedFileFromBackup() {
            command cp -p "$1" "$2"
        }
        removeManagedFileIfPresent() {
            if [[ "$1" == "${backupPath}" ]]; then
                return 1
            fi
            command rm -f -- "$1"
        }
        if backupNginxConfig restoreBackup >/dev/null 2>&1; then
            return 1
        fi
        grep -q "manual-check:nginx配置备份文件删除失败| ${backupPath}" "${helperLog}"
        grep -q "nginx配置备份文件删除失败，请手动检查 ${backupPath}" "${errorLog}"
    )
}
