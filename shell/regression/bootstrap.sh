#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)

regressionEnsureWritableDir() {
    local varName=$1
    local fallbackPath=$2
    local currentPath=${!varName:-}

    if [[ -n "${currentPath}" && -d "${currentPath}" && -w "${currentPath}" ]]; then
        return 0
    fi
    mkdir -p "${fallbackPath}"
    printf -v "${varName}" '%s' "${fallbackPath}"
    export "${varName}"
}

regressionEnsureWritableDir TMPDIR "${PROJECT_ROOT}/.tmp-msys/tmp"
regressionEnsureWritableDir HOME "${PROJECT_ROOT}/.tmp-msys/home"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

export PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
export PADM_SUBSCRIBE_LOCAL_DIR="${TMP_DIR}/subscribe_local"
export PADM_WIREGUARD_CONTROL_DIR="${TMP_DIR}/wireguard"
export PADM_VLESS_ENCRYPTION_STATE_FILE="${TMP_DIR}/vless_encryption.json"
export PADM_REALITY_TARGET_RESULTS_FILE="${TMP_DIR}/reality_targets_results.tsv"
export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
export PADM_REALITY_TARGET_BLOCKED_FILE="${TMP_DIR}/reality_target_blocked.tsv"
export PADM_ACCESS_CONTROL_BACKUP_DIR="${TMP_DIR}/access_control_backup"
export PADM_FIREWALL_STATE_FILE="${TMP_DIR}/firewall.state"
export PADM_SUPPRESS_PROGRESS=1

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/bootstrap.sh"
padmRegisterCleanupPath "${TMP_DIR}"
padmInstallCleanupTrap

echoContent() {
    if [[ -n "${REGRESSION_ECHO_LOG:-}" ]]; then
        mkdir -p "$(dirname -- "${REGRESSION_ECHO_LOG}")"
        printf '%s\n' "$*" >>"${REGRESSION_ECHO_LOG}"
    fi
    return 0
}

menuLine() {
    return 0
}

menuItem() {
    return 0
}

menuRecommendedItem() {
    return 0
}

menuReturnItem() {
    return 0
}

menuDangerItem() {
    return 0
}

uiStyle() {
    shift
    printf '%s' "$*"
}

statusCard() {
    printf '%s\n' "$*" >>"${REGRESSION_STATUS_CARD_LOG:-/dev/null}"
}

progressCard() {
    return 0
}

successCard() {
    if [[ -n "${REGRESSION_SUCCESS_CARD_LOG:-}" ]]; then
        printf '%s\n' "$*" >>"${REGRESSION_SUCCESS_CARD_LOG}"
    fi
    return 0
}

errorCard() {
    printf '%s\n' "$*" >>"${REGRESSION_ERROR_CARD_LOG:-/dev/null}"
}

menuClose() {
    return 0
}

reloadCore() {
    return 0
}

handleNginx() {
    return 0
}

readNginxSubscribe() {
    subscribePort=${subscribePort:-39778}
}

serviceQueueRestart() {
    return 0
}

serviceQueueApply() {
    return 0
}

cleanDirectoryContent() {
    return 0
}

subscribe() {
    return 0
}

regressionNowMs() {
    local epochRealtime=${EPOCHREALTIME:-}

    if [[ -n "${epochRealtime}" ]]; then
        epochRealtime=${epochRealtime/./}
        printf '%s\n' "${epochRealtime:0:${#epochRealtime}-3}"
        return
    fi
    date +%s%3N 2>/dev/null || printf '%s000\n' "$(date +%s)"
}

runRegressionStep() {
    local name=$1
    shift
    local startMs endMs elapsedMs rc
    local thresholdMs=${PADM_REGRESSION_SLOW_THRESHOLD_MS:-5000}
    startMs=$(regressionNowMs)
    if [[ "${PADM_REGRESSION_VERBOSE:-}" == "1" ]]; then
        printf 'regression-start:%s\n' "${name}"
    fi
    set +e
    (
        trap - EXIT INT TERM
        set -e
        "$@"
    )
    rc=$?
    set -e
    if [[ "${rc}" -eq 0 ]]; then
        endMs=$(regressionNowMs)
        elapsedMs=$((endMs - startMs))
        if [[ "${PADM_REGRESSION_VERBOSE:-}" == "1" || "${name}" == total:* || "${elapsedMs}" -ge "${thresholdMs}" ]]; then
            printf 'regression-ok:%s:%sms\n' "${name}" "${elapsedMs}"
        fi
        return 0
    else
        endMs=$(regressionNowMs)
        elapsedMs=$((endMs - startMs))
        printf 'regression-fail:%s:%sms:rc=%s\n' "${name}" "${elapsedMs}" "${rc}" >&2
        return "${rc}"
    fi
}

regressionFindHasMatches() {
    local firstMatch
    firstMatch=$(find "$@" -print -quit 2>/dev/null) || return 1
    [[ -n "${firstMatch}" ]]
}

regressionExpectStatus() {
    local expected=$1 actual=0
    shift
    "$@" || actual=$?
    [[ "${actual}" == "${expected}" ]]
}

regressionExpectFailure() { ! "$@"; }
