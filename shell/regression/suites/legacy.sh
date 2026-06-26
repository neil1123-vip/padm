#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_LEGACY_SCRIPT="${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_LEGACY_SCRIPT}" "${runner}"
done <<'EOF'
fast-reality fast-reality
platform-io platform-io
tls tls
ui ui
ui-smoke menu-smoke
ui-full menu-smoke-full
routing routing
routing-socks5-udp-associate routing-socks5-udp-associate
subscription subscription
subscription-output subscription-output
subscription-remote subscription-remote-fetch
subscription-tx subscription-write-transaction
runtime runtime
runtime-core runtime-core
runtime-auto-install-reality-route runtime-auto-install-reality-route
reality-candidates reality-candidates
reality-candidates-fast reality-candidates-fast
reality-candidates-full reality-candidates-full
reality-config reality-config
reality-stream reality-stream
transaction transaction
transaction-core transaction-core
transaction-subscription transaction-subscription
transaction-system transaction-system
EOF

registerRegressionAggregateSequential all \
    routing \
    subscription \
    runtime \
    transaction \
    remote-control \
    ui
registerRegressionAlias full all
registerRegressionAlias ci all
