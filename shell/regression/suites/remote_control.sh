#!/usr/bin/env bash

REGRESSION_REMOTE_CONTROL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"

runRegressionRemoteControl() {
    runParallelRegressionRunners \
        "${TMP_DIR}/remote-control-default" \
        smoke runRegressionRemoteControlSmoke \
        contract runRegressionRemoteControlContract \
        deep runRegressionRemoteControlDeep
}

runRegressionRemoteControlSuiteRoot() {
    runRegressionRemoteControl
}

while read -r selector runner; do
    registerRegressionFunctionLeaf "${selector}" "${runner}"
done <<'EOF'
remote-control-smoke-core runRegressionRemoteControlSmokeCore
remote-control-smoke-refresh-apply-basic runRegressionRemoteControlSmokeRefreshApplyBasic
remote-control-smoke-refresh-apply-prepare runRegressionRemoteControlSmokeRefreshApplyPrepare
remote-control-smoke-refresh-apply-failure runRegressionRemoteControlSmokeRefreshApplyFailure
remote-control-smoke-refresh-restore runRegressionRemoteControlSmokeRefreshRestore
remote-control-smoke-refresh-reconcile runRegressionRemoteControlSmokeRefreshReconcile
remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess
remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail
remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail
remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback
remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction
remote-control-contract-server-response runRegressionRemoteControlContractServerResponse
remote-control-deep runRegressionRemoteControlDeep
EOF

listRegressionRemoteControlChildSelectors() {
    printf '%s\n' \
        remote-control-smoke \
        remote-control-contract \
        remote-control-deep
}

registerRegressionAggregateParallel remote-control-smoke-refresh-apply \
    remote-control-smoke-refresh-apply-basic \
    remote-control-smoke-refresh-apply-prepare \
    remote-control-smoke-refresh-apply-failure
registerRegressionAggregateParallel remote-control-smoke-refresh \
    remote-control-smoke-refresh-apply \
    remote-control-smoke-refresh-restore \
    remote-control-smoke-refresh-reconcile
registerRegressionAggregateParallel remote-control-smoke \
    remote-control-smoke-core \
    remote-control-smoke-refresh
registerRegressionAggregateParallel remote-control-contract-service-install \
    remote-control-contract-service-install-success \
    remote-control-contract-service-install-systemctl-fail \
    remote-control-contract-service-install-health-fail \
    remote-control-contract-service-install-health-rollback \
    remote-control-contract-service-install-token-transaction
registerRegressionAggregateParallel remote-control-contract \
    remote-control-contract-service-install \
    remote-control-contract-server-response
registerRegressionAggregateRunnerParallel remote-control runRegressionRemoteControlSuiteRoot \
    $(listRegressionRemoteControlChildSelectors)
