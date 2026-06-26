#!/usr/bin/env bash

REGRESSION_FAST_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_FAST_SCRIPT="${REGRESSION_FAST_SUITE_DIR}/../subscription_groups_fast.sh"

registerRegressionScriptLeaf fast "${REGRESSION_FAST_SCRIPT}" fast
registerRegressionScriptLeaf platform-hot "${REGRESSION_FAST_SCRIPT}" platform
