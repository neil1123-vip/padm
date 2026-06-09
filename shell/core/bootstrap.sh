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
source "${CORE_DIR}/routing_rules.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_ipv6.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_bt.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_warp.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_socks.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_vmess.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_access_control.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/routing_dns.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/entry_helpers.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/cores.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/core_templates.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/protocol_runtime.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/users.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/groups.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/subscription.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/output.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/output_protocols.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/accounts.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/accounts_protocols.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/control.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/wireguard_control.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/sync.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/traffic.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/state_maintenance.sh"
# shellcheck source=/dev/null
source "${SUB_DIR}/menu.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/manage.sh"
# shellcheck source=/dev/null
source "${CORE_DIR}/menu.sh"
