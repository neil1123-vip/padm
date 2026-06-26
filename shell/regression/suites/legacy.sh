#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_LEGACY_SCRIPT="${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_LEGACY_SCRIPT}" "${runner}"
done <<'EOF'
fast-reality fast-reality
ui ui
routing routing
subscription subscription
runtime runtime
reality-candidates reality-candidates
reality-stream reality-stream
transaction transaction
transaction-system transaction-system
EOF

registerRegressionFunctionLeaf platform-io runRegressionPlatformIo
registerRegressionFunctionLeaf tls runRegressionTls
registerRegressionFunctionLeaf ui-smoke runRegressionMenuSmoke
registerRegressionFunctionLeaf routing-socks5-udp-associate runSocks5UdpAssociateRegression

registerRegressionAggregateSequential all \
    routing \
    subscription \
    runtime \
    transaction \
    remote-control \
    ui
registerRegressionAlias full all
registerRegressionAlias ci all
