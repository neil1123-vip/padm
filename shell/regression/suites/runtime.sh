#!/usr/bin/env bash

REGRESSION_RUNTIME_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_RUNTIME_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh" --reuse

runRegressionRuntimeLegacyLeafWithCompat() (
    # Re-source legacy runtime fixtures in an isolated subshell so later suite
    # loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRegressionRuntimeSuiteRoot() {
    if [[ "${PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE:-}" == "all" ]]; then
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-4}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-light-${BASHPID:-$$}" \
            listRegressionRuntimeLightChildSelectors
        PADM_REGRESSION_PARALLEL_JOBS="${PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS:-${PADM_REGRESSION_PARALLEL_JOBS:-2}}" \
            runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-heavy-${BASHPID:-$$}" \
            listRegressionRuntimeHeavyChildSelectors
        return
    fi

    runFrameworkParallelRegressionSelectorList "${TMP_DIR}/runtime-parallel-${BASHPID:-$$}" \
        listRegressionRuntimeChildSelectors
}

listRegressionRuntimeLightChildSelectors() {
    printf '%s\n' \
        runtime-core \
        runtime-autoread-unset-auto-install \
        runtime-auto-install-reality-route \
        runtime-tempdir
}

listRegressionRuntimeHeavyChildSelectors() {
    printf '%s\n' \
        reality-candidates \
        reality-config
}

listRegressionRuntimeChildSelectors() {
    listRegressionRuntimeLightChildSelectors
    listRegressionRuntimeHeavyChildSelectors
}

runRegressionRuntimeParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-runtime-parallel-composition.log"

    : >"${callLog}"

    runRegressionAllSelector() {
        local selector=$1
        printf '%s-start\n' "${selector}" >>"${callLog}"
        case "${selector}" in
        runtime-core)
            runFrameworkWaitForFile "${TMP_DIR}/runtime-tempdir-started"
            ;;
        runtime-tempdir)
            : >"${TMP_DIR}/runtime-tempdir-started"
            ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionRuntimeSuiteRoot

    runFrameworkAssertSelectorListLogged "${callLog}" listRegressionRuntimeChildSelectors
    awk '
        $0 == "runtime-core-start" { coreStart = NR }
        $0 == "runtime-tempdir-start" { tempdirStart = NR }
        $0 == "runtime-core-finish" { coreFinish = NR }
        $0 == "runtime-autoread-unset-auto-install-finish" { autoreadFinish = NR }
        $0 == "runtime-auto-install-reality-route-finish" { routeFinish = NR }
        $0 == "runtime-tempdir-finish" { tempdirFinish = NR }
        $0 == "reality-candidates-start" { candidatesStart = NR }
        $0 == "reality-config-start" { configStart = NR }
        END {
            exit !(coreStart && tempdirStart && coreFinish && autoreadFinish && routeFinish && tempdirFinish &&
                candidatesStart && configStart && tempdirStart < coreFinish &&
                coreFinish < candidatesStart && autoreadFinish < candidatesStart &&
                routeFinish < candidatesStart && tempdirFinish < candidatesStart &&
                coreFinish < configStart && autoreadFinish < configStart &&
                routeFinish < configStart && tempdirFinish < configStart)
        }
    ' "${callLog}"

    : >"${callLog}"
    rm -f "${TMP_DIR}/runtime-tempdir-started"
    PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionAllSelector PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS=1 PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS=1 runRegressionRuntimeSuiteRoot
    awk '
        $0 == "runtime-core-finish" { coreFinish = NR }
        $0 == "runtime-autoread-unset-auto-install-start" { autoreadStart = NR }
        $0 == "runtime-autoread-unset-auto-install-finish" { autoreadFinish = NR }
        $0 == "runtime-auto-install-reality-route-start" { routeStart = NR }
        $0 == "reality-candidates-finish" { candidatesFinish = NR }
        $0 == "reality-config-start" { configStart = NR }
        END {
            exit !(coreFinish && autoreadStart && autoreadFinish && routeStart && candidatesFinish && configStart &&
                coreFinish < autoreadStart && autoreadFinish < routeStart && candidatesFinish < configStart)
        }
    ' "${callLog}"
)

runRegressionRuntimeLegacyTmpDirIsolationRegression() (
    set -euo pipefail
    local originalTmpDir="${TMP_DIR}"

    # Simulate later suite loads re-sourcing bootstrap and drifting TMP_DIR.
    source "${REGRESSION_RUNTIME_SUITE_DIR}/../bootstrap.sh"
    [[ "${TMP_DIR}" != "${originalTmpDir}" ]]

    PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain runtime-auto-install-reality-route
)

registerRegressionFunctionLeaf runtime-core runRegressionRuntimeLegacyLeafWithCompat runRuntimeAndRealityRegression
registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runRegressionRuntimeLegacyLeafWithCompat runAutoReadUnsetAutoInstallRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runRegressionRuntimeLegacyLeafWithCompat runAutoInstallRealityRouteRegression
registerRegressionFunctionLeaf runtime-tempdir runRegressionRuntimeLegacyLeafWithCompat runRuntimeTempDirRegression
registerRegressionFunctionLeaf regression-runtime-parallel-composition runRegressionRuntimeParallelCompositionRegression
registerRegressionFunctionLeaf regression-runtime-legacy-tmpdir-isolation runRegressionRuntimeLegacyTmpDirIsolationRegression

registerRegressionAggregateRunner parallel runtime runRegressionRuntimeSuiteRoot \
    $(listRegressionRuntimeChildSelectors)
