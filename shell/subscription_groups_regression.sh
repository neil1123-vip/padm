#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/framework/env.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/framework/runtime.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/framework/registry.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/fast.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/all.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/runtime.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/contracts.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/legacy.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/remote_control.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/regression/suites/subscription_state.sh"

restoreLegacyRealityRegressionStubs

runRegisteredRegressionMain "${1:-fast}"
