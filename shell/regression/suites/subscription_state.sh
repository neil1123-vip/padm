#!/usr/bin/env bash

REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_SUBSCRIPTION_STATE_FULL_SCRIPT="${REGRESSION_SUBSCRIPTION_STATE_SUITE_DIR}/../subscription_groups_subscription_state_full.sh"

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_SUBSCRIPTION_STATE_FULL_SCRIPT}" "${runner}"
done <<'EOF'
subscription-state-serial subscription-state-serial
subscription-state-structure subscription-state-structure
subscription-state-structure-foundation subscription-state-structure-foundation
subscription-state-structure-foundation-add-remove subscription-state-structure-foundation-add-remove
subscription-state-structure-foundation-credential subscription-state-structure-foundation-credential
subscription-state-structure-foundation-normalize subscription-state-structure-foundation-normalize
subscription-state-structure-foundation-init-transaction subscription-state-structure-foundation-init-transaction
subscription-state-structure-foundation-serial subscription-state-structure-foundation-serial
subscription-state-structure-migration subscription-state-structure-migration
subscription-state-structure-source subscription-state-structure-source
subscription-state-structure-source-credential subscription-state-structure-source-credential
subscription-state-structure-source-status subscription-state-structure-source-status
subscription-state-structure-source-remove subscription-state-structure-source-remove
subscription-state-structure-source-serial subscription-state-structure-source-serial
subscription-state-structure-serial subscription-state-structure-serial
subscription-state-quota subscription-state-quota
subscription-state-quota-traffic subscription-state-quota-traffic
subscription-state-quota-traffic-summary subscription-state-quota-traffic-summary
subscription-state-quota-traffic-invalid-input subscription-state-quota-traffic-invalid-input
subscription-state-quota-traffic-apply subscription-state-quota-traffic-apply
subscription-state-quota-traffic-serial subscription-state-quota-traffic-serial
subscription-state-quota-menu-preview-fail subscription-state-quota-menu-preview-fail
subscription-state-quota-menu-tx subscription-state-quota-menu-tx
subscription-state-quota-menu-tx-rollback subscription-state-quota-menu-tx-rollback
subscription-state-quota-menu-tx-serial subscription-state-quota-menu-tx-serial
subscription-state-quota-partial-sync subscription-state-quota-partial-sync
subscription-state-quota-partial-sync-apply-failure subscription-state-quota-partial-sync-apply-failure
subscription-state-quota-partial-sync-plan subscription-state-quota-partial-sync-plan
subscription-state-quota-partial-sync-config subscription-state-quota-partial-sync-config
subscription-state-quota-partial-sync-serial subscription-state-quota-partial-sync-serial
subscription-state-quota-serial subscription-state-quota-serial
subscription-state-remote-restore subscription-state-remote-restore
subscription-state-remote-restore-self-reference subscription-state-remote-restore-self-reference
subscription-state-remote-restore-self-reference-plan subscription-state-remote-restore-self-reference-plan
subscription-state-remote-restore-self-reference-sync subscription-state-remote-restore-self-reference-sync
subscription-state-remote-restore-self-reference-serial subscription-state-remote-restore-self-reference-serial
subscription-state-remote-restore-state-write subscription-state-remote-restore-state-write
subscription-state-remote-restore-legacy-menu subscription-state-remote-restore-legacy-menu
subscription-state-remote-restore-serial subscription-state-remote-restore-serial
subscription-state-support subscription-state-support
subscription-state-sync-rollback subscription-state-sync-rollback
subscription-state-sync-rollback-serial subscription-state-sync-rollback-serial
subscription-sync-tempdir subscription-sync-tempdir
subscription-sync-rollback-failure subscription-sync-rollback-failure
subscription-sync-rollback-failure-serial subscription-sync-rollback-failure-serial
subscription-sync-rollback-config-restore-failure subscription-sync-rollback-config-restore-failure
subscription-sync-restore-dir-failure subscription-sync-restore-dir-failure
subscription-sync-reload-rollback subscription-sync-reload-rollback
subscription-group-sync-rollback subscription-group-sync-rollback
subscription-group-sync-rollback-serial subscription-group-sync-rollback-serial
subscription-group-sync-apply-failure subscription-group-sync-apply-failure
subscription-group-sync-reconcile-rollback subscription-group-sync-reconcile-rollback
subscription-group-sync-remote-failure subscription-group-sync-remote-failure
subscription-sync-reconcile-early-exit subscription-sync-reconcile-early-exit
subscription-groups-restore-failure subscription-groups-restore-failure
EOF

registerRegressionAggregateParallel subscription-state-core \
    subscription-state-structure \
    subscription-state-quota \
    subscription-state-remote-restore
registerRegressionAggregateParallel subscription-state \
    subscription-state-core \
    subscription-state-support \
    subscription-state-sync-rollback
