#!/usr/bin/env bash

REGRESSION_LEGACY_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REGRESSION_LEGACY_SCRIPT="${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_LEGACY_SUITE_DIR}/../subscription_groups_legacy.sh"

restoreLegacyRealityRegressionStubs() {
    realityTargetDetector() {
        printf '%s\n' fake-xray
    }

    currentRealityNetworkProfile() {
        printf '203.0.113.10\tAS64500\tExampleNet\n'
    }

    resolveRealityTargetIPv4() {
        printf '192.0.2.1\n'
    }

    lookupRealityTargetAsn() {
        case "$1" in
        198.51.100.*)
            printf 'AS64501\tRemoteNet\n'
            ;;
        *)
            printf 'AS64500\tExampleNet\n'
            ;;
        esac
    }
}

restoreLegacyRealityRegressionStubs

while read -r selector runner; do
    registerRegressionScriptLeaf "${selector}" "${REGRESSION_LEGACY_SCRIPT}" "${runner}"
done <<'EOF'
EOF
