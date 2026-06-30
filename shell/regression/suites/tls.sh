#!/usr/bin/env bash

REGRESSION_TLS_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionTlsLegacyLeafWithCompat() (
    # Re-source legacy TLS fixtures in an isolated subshell so later suite
    # loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runTlsFailureReturnCompatRegression() { runRegressionTlsLegacyLeafWithCompat runTlsFailureReturnRegression; }
runTlsReinstallRollbackCompatRegression() { runRegressionTlsLegacyLeafWithCompat runTlsReinstallRollbackRegression; }
runTlsRenewalFailurePropagationCompatRegression() { runRegressionTlsLegacyLeafWithCompat runTlsRenewalFailurePropagationRegression; }

runRegressionTlsSuiteRoot() {
    runRegressionStep tls-failure-return runTlsFailureReturnCompatRegression &&
        runRegressionStep tls-reinstall-rollback runTlsReinstallRollbackCompatRegression &&
        runRegressionStep tls-renew-failure-propagation runTlsRenewalFailurePropagationCompatRegression
}

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
        tls-reinstall-rollback \
        tls-renew-failure-propagation
}

registerRegressionFunctionLeaf tls-failure-return runTlsFailureReturnCompatRegression
registerRegressionFunctionLeaf tls-reinstall-rollback runTlsReinstallRollbackCompatRegression
registerRegressionFunctionLeaf tls-renew-failure-propagation runTlsRenewalFailurePropagationCompatRegression
registerRegressionFunctionLeaf regression-tls-legacy-tmpdir-isolation runRegressionTlsLegacyTmpDirIsolationRegression

registerRegressionAggregateRunnerSequential tls runRegressionTlsSuiteRoot \
    $(listRegressionTlsChildSelectors)
