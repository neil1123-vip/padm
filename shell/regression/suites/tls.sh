#!/usr/bin/env bash

REGRESSION_TLS_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_TLS_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionTlsSuiteRoot() {
    runRegressionStep tls-failure-return runTlsFailureReturnRegression &&
        runRegressionStep tls-reinstall-rollback runTlsReinstallRollbackRegression &&
        runRegressionStep tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression
}

listRegressionTlsChildSelectors() {
    printf '%s\n' \
        tls-failure-return \
        tls-reinstall-rollback \
        tls-renew-failure-propagation
}

while read -r selector runner; do
    registerRegressionFunctionLeaf "${selector}" "${runner}"
done <<'EOF'
tls-failure-return runTlsFailureReturnRegression
tls-reinstall-rollback runTlsReinstallRollbackRegression
tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression
EOF

registerRegressionAggregateRunnerSequential tls runRegressionTlsSuiteRoot \
    $(listRegressionTlsChildSelectors)
