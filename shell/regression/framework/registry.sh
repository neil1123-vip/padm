#!/usr/bin/env bash

if [[ "${PADM_REGRESSION_FRAMEWORK_REGISTRY_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_REGRESSION_FRAMEWORK_REGISTRY_LOADED=1

declare -ag PADM_REGRESSION_REGISTERED_SELECTORS=()
declare -Ag PADM_REGRESSION_SELECTOR_KIND=()
declare -Ag PADM_REGRESSION_SELECTOR_RUNNER=()
declare -Ag PADM_REGRESSION_SELECTOR_RUNNER_ARGS=()
declare -Ag PADM_REGRESSION_SELECTOR_CHILDREN=()
declare -Ag PADM_REGRESSION_SELECTOR_MODE=()

registerRegressionSelector() {
    local selector=$1

    if [[ -n "${PADM_REGRESSION_SELECTOR_KIND[${selector}]:-}" ]]; then
        printf 'duplicate regression selector: %s\n' "${selector}" >&2
        return 1
    fi

    PADM_REGRESSION_REGISTERED_SELECTORS+=("${selector}")
}

registerRegressionFunctionLeaf() {
    local selector=$1
    local runner=$2
    shift 2

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=function
    PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]=${runner}
    PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAggregateRunner() {
    local mode=$1
    local selector=$2
    local runner=$3
    shift 3

    case "${mode}" in
    parallel|sequential) ;;
    *)
        printf 'unknown regression aggregate runner mode: %s\n' "${mode}" >&2
        return 2
        ;;
    esac

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate-runner
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=${mode}
    PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]=${runner}
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAggregateRunnerWithArgs() {
    local mode=$1
    local selector=$2
    local runner=$3
    shift 3
    local arg
    local -a runnerArgs=()
    local -a children=()
    local parseChildren=0

    for arg in "$@"; do
        if (( parseChildren )); then
            children+=("${arg}")
            continue
        fi
        if [[ "${arg}" == "--" ]]; then
            parseChildren=1
            continue
        fi
        runnerArgs+=("${arg}")
    done

    registerRegressionAggregateRunner "${mode}" "${selector}" "${runner}" "${children[@]}" || return 1
    PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]=$(printf '%s\n' "${runnerArgs[@]}")
}

registerRegressionSequentialSelectorList() {
    local selector=$1
    local selectorListFn=$2
    registerRegressionAggregateRunnerWithArgs sequential "${selector}" \
        runFrameworkSequentialRegressionSelectorList "${selectorListFn}" -- $("${selectorListFn}")
}

registerRegressionParallelSelectorList() {
    local selector=$1
    local runner=$2
    local orchestrationRoot=$3
    local selectorListFn=$4
    shift 4
    registerRegressionAggregateRunnerWithArgs parallel "${selector}" "${runner}" \
        "${orchestrationRoot}" "${selectorListFn}" "$@" -- $("${selectorListFn}")
}

validateRegressionRegistry() {
    local selector
    local kind
    local children
    local child

    for selector in "${PADM_REGRESSION_REGISTERED_SELECTORS[@]}"; do
        kind=${PADM_REGRESSION_SELECTOR_KIND["${selector}"]}
        case "${kind}" in
        function)
            [[ -n "${PADM_REGRESSION_SELECTOR_RUNNER[${selector}]:-}" ]]
            ;;
        aggregate-runner)
            [[ -n "${PADM_REGRESSION_SELECTOR_RUNNER[${selector}]:-}" ]]
            children=${PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]:-}
            while IFS= read -r child; do
                [[ -n "${child}" ]] || continue
                if [[ -z "${PADM_REGRESSION_SELECTOR_KIND[${child}]:-}" ]]; then
                    printf 'missing child selector for %s: %s\n' "${selector}" "${child}" >&2
                    return 1
                fi
            done <<<"${children}"
            ;;
        *)
            printf 'unknown selector kind for %s: %s\n' "${selector}" "${kind}" >&2
            return 1
            ;;
        esac
    done

    PADM_REGRESSION_REGISTRY_VALIDATED=1
}

renderRegressionUsage() {
    local selector

    printf 'usage: %s <selector>\n' "${0##*/}" >&2
    printf 'selectors:\n' >&2
    for selector in "${PADM_REGRESSION_REGISTERED_SELECTORS[@]}"; do
        printf '  %s\n' "${selector}" >&2
    done
}

runRegisteredRegressionSelector() {
    local selector=$1
    local kind=${PADM_REGRESSION_SELECTOR_KIND["${selector}"]:-}
    local runner
    local child
    local runnerArgs
    local -a runnerArgv=()

    case "${kind}" in
    function|aggregate-runner)
        runner=${PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]}
        runnerArgs=${PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]:-}
        while IFS= read -r child; do
            [[ -n "${child}" ]] || continue
            runnerArgv+=("${child}")
        done <<<"${runnerArgs}"
        "${runner}" "${runnerArgv[@]}"
        ;;
    *)
        printf 'unknown regression selector: %s\n' "${selector}" >&2
        return 2
        ;;
    esac
}

runRegisteredRegressionMain() {
    local selector=${1:-fast}
    local status=0
    local hadErrexit=0

    case $- in
    *e*) hadErrexit=1 ;;
    esac
    set +e
    (
        trap - EXIT ERR INT TERM
        set -e
        [[ 1 == 0 ]]
        exit 0
    )
    status=$?
    if (( hadErrexit )); then
        set -e
    fi
    if (( status == 0 )); then
        printf 'runRegisteredRegressionMain cannot run from a conditional command context\n' >&2
        return 2
    fi
    status=0

    if [[ "${PADM_REGRESSION_REGISTRY_VALIDATED:-}" != "1" ]]; then
        validateRegressionRegistry || return 1
    fi

    if [[ -z "${PADM_REGRESSION_SELECTOR_KIND[${selector}]:-}" ]]; then
        renderRegressionUsage
        return 2
    fi

    if (( hadErrexit )); then
        set +e
    fi
    runRegressionStep "total:${selector}" runRegisteredRegressionSelector "${selector}"
    status=$?
    if (( hadErrexit )); then
        set -e
    fi
    if (( status != 0 )); then
        return "${status}"
    fi
    if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
        echo "subscription-groups-regression-ok:${selector}"
    fi
}
