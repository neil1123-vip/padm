#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

PADM_REGRESSION_SUPPRESS_DONE=1 \
    bash "${SCRIPT_DIR}/../subscription_groups_regression.sh" protocol-capabilities
echo "protocol-capabilities-regression-ok"
