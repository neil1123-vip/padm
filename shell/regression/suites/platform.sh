#!/usr/bin/env bash

REGRESSION_PLATFORM_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_fast.sh"

_platform_hot_suite_def=$(declare -f runRegressionPlatform)
_platform_hot_suite_def="${_platform_hot_suite_def/runRegressionPlatform/runRegressionPlatformSuiteRoot}"

PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_PLATFORM_SUITE_DIR}/../subscription_groups_legacy.sh"

_platform_io_suite_def=$(declare -f runRegressionPlatformIo)
_platform_io_suite_def="${_platform_io_suite_def/runRegressionPlatformIo/runRegressionPlatformIoSuiteRoot}"

eval "${_platform_hot_suite_def}"
eval "${_platform_io_suite_def}"

unset _platform_hot_suite_def _platform_io_suite_def

registerRegressionFunctionLeaf platform-hot runRegressionPlatformSuiteRoot
registerRegressionFunctionLeaf platform-io runRegressionPlatformIoSuiteRoot
