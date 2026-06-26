#!/usr/bin/env bash

REGRESSION_REMOTE_CONTROL_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_REMOTE_CONTROL_SCRIPT="${REGRESSION_REMOTE_CONTROL_SUITE_DIR}/../subscription_groups_remote_control.sh"

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_REMOTE_CONTROL_SCRIPT}" "${runner}"
done <<'EOF'
remote-control-smoke-core remote-control-smoke-core
remote-control-smoke-refresh-apply-basic remote-control-smoke-refresh-apply-basic
remote-control-smoke-refresh-apply-prepare remote-control-smoke-refresh-apply-prepare
remote-control-smoke-refresh-apply-failure remote-control-smoke-refresh-apply-failure
remote-control-smoke-refresh-restore remote-control-smoke-refresh-restore
remote-control-smoke-refresh-reconcile remote-control-smoke-refresh-reconcile
remote-control-contract-service-install-success remote-control-contract-service-install-success
remote-control-contract-service-install-systemctl-fail remote-control-contract-service-install-systemctl-fail
remote-control-contract-service-install-health-fail remote-control-contract-service-install-health-fail
remote-control-contract-service-install-health-rollback remote-control-contract-service-install-health-rollback
remote-control-contract-service-install-token-transaction remote-control-contract-service-install-token-transaction
remote-control-contract-server-response remote-control-contract-server-response
remote-control-deep remote-control-deep
EOF

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
registerRegressionAggregateParallel remote-control \
    remote-control-smoke \
    remote-control-contract
registerRegressionAlias remote-control-light remote-control
