#!/usr/bin/env bash

REGRESSION_RUNTIME_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_RUNTIME_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"

runRegressionRuntimeLegacyLeafWithCompat() (
    # Re-source legacy runtime fixtures in an isolated subshell so later suite
    # loads cannot leave source-time TMP_DIR-derived paths stale.
    PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"
    "$@"
)

runRuntimeAndRealityCompatRegression() { runRegressionRuntimeLegacyLeafWithCompat runRuntimeAndRealityRegression; }
runAutoReadUnsetAutoInstallCompatRegression() { runRegressionRuntimeLegacyLeafWithCompat runAutoReadUnsetAutoInstallRegression; }
runAutoInstallRealityRouteCompatRegression() { runRegressionRuntimeLegacyLeafWithCompat runAutoInstallRealityRouteRegression; }
runRuntimeTempDirCompatRegression() { runRegressionRuntimeLegacyLeafWithCompat runRuntimeTempDirRegression; }

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
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${TMP_DIR}/runtime-tempdir-started" ]] && break
                sleep 0.05
            done
            ;;
        runtime-tempdir)
            : >"${TMP_DIR}/runtime-tempdir-started"
            ;;
        esac
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }
    runRuntimeAndRealityRegression() { runRegressionAllSelector runtime-core; }
    runAutoReadUnsetAutoInstallRegression() { runRegressionAllSelector runtime-autoread-unset-auto-install; }
    runAutoInstallRealityRouteRegression() { runRegressionAllSelector runtime-auto-install-reality-route; }
    runRuntimeTempDirRegression() { runRegressionAllSelector runtime-tempdir; }
    runRegressionRealityCandidatesSuiteRoot() { runRegressionAllSelector reality-candidates; }
    runRealityConfigRegression() { runRegressionAllSelector reality-config; }

    PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all runRegressionRuntimeSuiteRoot

    for selector in \
        runtime-core \
        runtime-autoread-unset-auto-install \
        runtime-auto-install-reality-route \
        runtime-tempdir \
        reality-candidates \
        reality-config; do
        grep -qx "${selector}-start" "${callLog}"
        grep -qx "${selector}-finish" "${callLog}"
    done
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
    PADM_REGRESSION_RUNTIME_RESOURCE_PROFILE=all PADM_REGRESSION_RUNTIME_LIGHT_PARALLEL_JOBS=1 PADM_REGRESSION_RUNTIME_HEAVY_PARALLEL_JOBS=1 runRegressionRuntimeSuiteRoot
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

registerRegressionFunctionLeaf runtime-core runRuntimeAndRealityCompatRegression
registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallCompatRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteCompatRegression
registerRegressionFunctionLeaf runtime-tempdir runRuntimeTempDirCompatRegression
registerRegressionFunctionLeaf regression-runtime-parallel-composition runRegressionRuntimeParallelCompositionRegression
registerRegressionFunctionLeaf regression-runtime-legacy-tmpdir-isolation runRegressionRuntimeLegacyTmpDirIsolationRegression

registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \
    $(listRegressionRuntimeChildSelectors)
