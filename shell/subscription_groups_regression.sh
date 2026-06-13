#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
regressionName=${1:-fast}

case "${regressionName}" in
fast | platform)
    exec bash "${SCRIPT_DIR}/regression/subscription_groups_fast.sh" "$@"
    ;;
remote-control)
    exec bash "${SCRIPT_DIR}/regression/subscription_groups_remote_control.sh" remote-control
    ;;
remote-control-smoke | remote-control-contract | remote-control-light | remote-control-deep)
    exec bash "${SCRIPT_DIR}/regression/subscription_groups_remote_control.sh" "$@"
    ;;
subscription-state | subscription-state-* | subscription-sync-tempdir | subscription-sync-rollback-failure | subscription-sync-reconcile-early-exit | subscription-groups-restore-failure)
    exec bash "${SCRIPT_DIR}/regression/subscription_groups_subscription_state.sh" "$@"
    ;;
*)
    exec bash "${SCRIPT_DIR}/regression/subscription_groups_legacy.sh" "$@"
    ;;
esac
