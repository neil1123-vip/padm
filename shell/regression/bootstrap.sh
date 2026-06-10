#!/usr/bin/env bash
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

export PADM_SUBSCRIPTION_GROUPS_DIR="${TMP_DIR}/subscribe_groups"
export PADM_SUBSCRIBE_LOCAL_DIR="${TMP_DIR}/subscribe_local"
export PADM_VLESS_ENCRYPTION_STATE_FILE="${TMP_DIR}/vless_encryption.json"
export PADM_REALITY_TARGET_RESULTS_FILE="${TMP_DIR}/reality_targets_results.tsv"
export PADM_REALITY_TARGET_SCAN_FILE="${PADM_REALITY_TARGET_RESULTS_FILE}"
export PADM_REALITY_TARGET_BLOCKED_FILE="${TMP_DIR}/reality_target_blocked.tsv"
export PADM_SUPPRESS_PROGRESS=1

echoContent() {
    if [[ -n "${REGRESSION_ECHO_LOG:-}" ]]; then
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

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/version.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/platform.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocols.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/runtime.sh"
padmRegisterCleanupPath "${TMP_DIR}"
padmInstallCleanupTrap
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/reality_targets.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/singbox.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_rules.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_ipv6.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_bt.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_warp.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_socks.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_vmess.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_access_control.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/routing_dns.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/cores.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/core_templates.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/nginx.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/network.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/entry_helpers.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/users.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/groups.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/subscription.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/output.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/output_protocols.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/accounts.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/accounts_protocols.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/control.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/sync.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/traffic.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/state_maintenance.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/subscription/menu.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/adapters.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/manage.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/state.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/tls.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/shell/core/menu.sh"

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
