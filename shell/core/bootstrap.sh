#!/usr/bin/env bash
# Shared bootstrap for the installer
set -o pipefail

CORE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${CORE_DIR}/../.." && pwd)
SUB_DIR=${PROJECT_ROOT}/shell/subscription

# shellcheck source=/dev/null
source "${CORE_DIR}/locale.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/platform.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/runtime.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/version.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/protocols.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/reality_targets.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/services.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/state.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/adapters.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/network.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/nginx.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/tls.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/singbox.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/entry_helpers.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/cores.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/protocol_runtime.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/users.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/groups.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/subscription.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/control.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/manage.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/menu.sh"
