#!/usr/bin/env bash

listRegressionTlsChildSelectors() {
    printf '%s\n' \
        tls-failure-return \
        tls-custom-email-unsafe-address \
        tls-reinstall-rollback \
        tls-renew-failure-propagation
}

registerRegressionFunctionLeaf tls-failure-return runTlsFailureReturnRegression
registerRegressionFunctionLeaf tls-custom-email-unsafe-address runTlsCustomSSLEmailRejectsUnsafeAddressRegression
registerRegressionFunctionLeaf tls-reinstall-rollback runTlsReinstallRollbackRegression
registerRegressionFunctionLeaf tls-renew-failure-propagation runTlsRenewalFailurePropagationRegression

registerRegressionSequentialSelectorList tls listRegressionTlsChildSelectors
