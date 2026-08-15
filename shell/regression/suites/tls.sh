#!/usr/bin/env bash

REGRESSION_TLS_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionTlsLegacyLeafWithCompat() (
    source "${REGRESSION_TLS_SUITE_DIR}/../legacy_context.sh"
    "$@"
)

runRegressionTlsLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_TLS_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain tls-renew-failure-propagation
)

listRegressionTlsChildSelectors() {
    printf '%s\n' \
        tls-failure-return \
        tls-custom-email-unsafe-address \
        tls-reinstall-rollback \
        tls-renew-failure-propagation
}

registerRegressionFunctionLeaf tls-failure-return runRegressionTlsLegacyLeafWithCompat runTlsFailureReturnRegression
registerRegressionFunctionLeaf tls-custom-email-unsafe-address runRegressionTlsLegacyLeafWithCompat runTlsCustomSSLEmailRejectsUnsafeAddressRegression
registerRegressionFunctionLeaf tls-reinstall-rollback runRegressionTlsLegacyLeafWithCompat runTlsReinstallRollbackRegression
registerRegressionFunctionLeaf tls-renew-failure-propagation runRegressionTlsLegacyLeafWithCompat runTlsRenewalFailurePropagationRegression
registerRegressionFunctionLeaf regression-tls-legacy-tmpdir-isolation runRegressionTlsLegacyTmpDirIsolationRegression

registerRegressionSequentialSelectorList tls listRegressionTlsChildSelectors
