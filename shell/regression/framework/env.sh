#!/usr/bin/env bash

if [[ "${PADM_REGRESSION_FRAMEWORK_ENV_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_REGRESSION_FRAMEWORK_ENV_LOADED=1

REGRESSION_FRAMEWORK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_FRAMEWORK_ROOT=$(cd -- "${REGRESSION_FRAMEWORK_DIR}/.." && pwd)

# shellcheck source=/dev/null
source "${REGRESSION_FRAMEWORK_ROOT}/bootstrap.sh"

if [[ -z "${PADM_REGRESSION_PROTECT_WORKTREE+x}" ]]; then
    export PADM_REGRESSION_PROTECT_WORKTREE=1
else
    export PADM_REGRESSION_PROTECT_WORKTREE
fi
if [[ -z "${PADM_REGRESSION_WORKTREE_ROOT:-}" ]]; then
    export PADM_REGRESSION_WORKTREE_ROOT="${PROJECT_ROOT}"
else
    export PADM_REGRESSION_WORKTREE_ROOT
fi
