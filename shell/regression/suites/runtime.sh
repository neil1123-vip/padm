#!/usr/bin/env bash

REGRESSION_RUNTIME_SUITE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_RUNTIME_SUITE_DIR}/../framework/runtime.sh"
PADM_REGRESSION_SOURCE_ONLY=1 source "${REGRESSION_RUNTIME_SUITE_DIR}/../subscription_groups_legacy.sh"

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

    runRegressionStep runtime-core runRuntimeAndRealityRegression &&
        runRegressionStep runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression &&
        runRegressionStep runtime-auto-install-reality-route runAutoInstallRealityRouteRegression &&
        runRegressionStep runtime-tempdir runRuntimeTempDirRegression &&
        runRegressionStep reality-candidates runRegressionRealityCandidatesSuiteRoot &&
        runRegressionStep reality-config runRealityConfigRegression
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

registerRegressionFunctionLeaf runtime-core runRuntimeAndRealityRegression
registerRegressionFunctionLeaf runtime-autoread-unset-auto-install runAutoReadUnsetAutoInstallRegression
registerRegressionFunctionLeaf runtime-auto-install-reality-route runAutoInstallRealityRouteRegression
registerRegressionFunctionLeaf runtime-tempdir runRuntimeTempDirRegression
registerRegressionFunctionLeaf regression-runtime-parallel-composition runRegressionRuntimeParallelCompositionRegression

registerRegressionAggregateRunnerParallel runtime runRegressionRuntimeSuiteRoot \
    $(listRegressionRuntimeChildSelectors)
