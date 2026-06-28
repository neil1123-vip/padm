#!/usr/bin/env bash
set -euo pipefail

SUBSCRIPTION_STATE_SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUBSCRIPTION_STATE_FULL_SCRIPT_PATH="${SUBSCRIPTION_STATE_SCRIPT_DIR}/subscription_groups_subscription_state_full.sh"
# shellcheck source=/dev/null
PADM_REGRESSION_SOURCE_ONLY=1 source "${SUBSCRIPTION_STATE_FULL_SCRIPT_PATH}"

if [[ "${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

printf 'use shell/subscription_groups_regression.sh <selector>\n' >&2
exit 2
