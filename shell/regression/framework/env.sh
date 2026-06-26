#!/usr/bin/env bash

if [[ "${PADM_REGRESSION_FRAMEWORK_ENV_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_REGRESSION_FRAMEWORK_ENV_LOADED=1

REGRESSION_FRAMEWORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_FRAMEWORK_ROOT=$(cd -- "${REGRESSION_FRAMEWORK_DIR}/.." && pwd)

# shellcheck source=/dev/null
source "${REGRESSION_FRAMEWORK_ROOT}/bootstrap.sh"
