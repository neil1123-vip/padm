#!/usr/bin/env bash

REGRESSION_CASES_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

source "${REGRESSION_CASES_DIR}/shared.sh"
source "${REGRESSION_CASES_DIR}/fast.sh"
source "${REGRESSION_CASES_DIR}/protocol_capabilities.sh"
source "${REGRESSION_CASES_DIR}/platform.sh"
source "${REGRESSION_CASES_DIR}/routing.sh"
source "${REGRESSION_CASES_DIR}/runtime.sh"
source "${REGRESSION_CASES_DIR}/reality.sh"
source "${REGRESSION_CASES_DIR}/tls.sh"
source "${REGRESSION_CASES_DIR}/ui.sh"
source "${REGRESSION_CASES_DIR}/subscription.sh"
source "${REGRESSION_CASES_DIR}/transaction_core.sh"
source "${REGRESSION_CASES_DIR}/transaction_subscription.sh"
source "${REGRESSION_CASES_DIR}/transaction_system.sh"
source "${REGRESSION_CASES_DIR}/remote_control.sh"
source "${REGRESSION_CASES_DIR}/subscription_state.sh"