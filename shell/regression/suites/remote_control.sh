#!/usr/bin/env bash

REGRESSION_REMOTE_CONTROL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"

runRegressionRemoteControlSuiteSelector() {
    case "$1" in
    remote-control-smoke) runRegressionRemoteControlSmoke ;;
    remote-control-contract) runRegressionRemoteControlContract ;;
    remote-control-deep) runRegressionRemoteControlDeep ;;
    *) return 2 ;;
    esac
}

runRegressionRemoteControl() {
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionRemoteControlSuiteSelector \
        runFrameworkParallelRegressionSelectorList "${TMP_DIR}/remote-control-default-${BASHPID:-$$}" \
        listRegressionRemoteControlChildSelectors
}

runRegressionRemoteControlSuiteRoot() {
    runRegressionRemoteControl
}

registerRegressionFunctionLeaf remote-control-smoke-core runRegressionRemoteControlSmokeCore
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-basic runRegressionRemoteControlSmokeRefreshApplyBasic
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-prepare runRegressionRemoteControlSmokeRefreshApplyPrepare
registerRegressionFunctionLeaf remote-control-smoke-refresh-apply-failure runRegressionRemoteControlSmokeRefreshApplyFailure
registerRegressionFunctionLeaf remote-control-smoke-refresh-restore runRegressionRemoteControlSmokeRefreshRestore
registerRegressionFunctionLeaf remote-control-smoke-refresh-reconcile runRegressionRemoteControlSmokeRefreshReconcile
registerRegressionFunctionLeaf remote-control-contract-service-install-success runRegressionRemoteControlContractServiceInstallSuccess
registerRegressionFunctionLeaf remote-control-contract-service-install-systemctl-fail runRegressionRemoteControlContractServiceInstallSystemctlFail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-fail runRegressionRemoteControlContractServiceInstallHealthFail
registerRegressionFunctionLeaf remote-control-contract-service-install-health-rollback runRegressionRemoteControlContractServiceInstallHealthRollback
registerRegressionFunctionLeaf remote-control-contract-service-install-token-transaction runRegressionRemoteControlContractServiceInstallTokenTransaction
registerRegressionFunctionLeaf remote-control-contract-server-response runRegressionRemoteControlContractServerResponse
registerRegressionFunctionLeaf remote-control-deep runRegressionRemoteControlDeep

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
