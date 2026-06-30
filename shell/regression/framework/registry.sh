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
declare -Ag PADM_REGRESSION_SELECTOR_ALIAS=()

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

registerRegressionAggregateRunnerParallel() {
    local selector=$1
    local runner=$2
    shift 2

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate-runner
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=parallel
    PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]=${runner}
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAggregateRunnerSequential() {
    local selector=$1
    local runner=$2
    shift 2

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate-runner
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=sequential
    PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]=${runner}
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAggregateParallel() {
    local selector=$1
    shift

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=parallel
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAggregateSequential() {
    local selector=$1
    shift

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=aggregate
    PADM_REGRESSION_SELECTOR_MODE["${selector}"]=sequential
    PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]=$(printf '%s\n' "$@")
}

registerRegressionAlias() {
    local selector=$1
    local target=$2

    registerRegressionSelector "${selector}" || return 1
    PADM_REGRESSION_SELECTOR_KIND["${selector}"]=alias
    PADM_REGRESSION_SELECTOR_ALIAS["${selector}"]=${target}
}

validateRegressionRegistry() {
    local selector
    local kind
    local target
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
        aggregate)
            children=${PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]:-}
            while IFS= read -r child; do
                [[ -n "${child}" ]] || continue
                if [[ -z "${PADM_REGRESSION_SELECTOR_KIND[${child}]:-}" ]]; then
                    printf 'missing child selector for %s: %s\n' "${selector}" "${child}" >&2
                    return 1
                fi
            done <<<"${children}"
            ;;
        alias)
            target=${PADM_REGRESSION_SELECTOR_ALIAS["${selector}"]:-}
            if [[ -z "${target}" || -z "${PADM_REGRESSION_SELECTOR_KIND[${target}]:-}" ]]; then
                printf 'missing alias target for %s: %s\n' "${selector}" "${target}" >&2
                return 1
            fi
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
    local -a childPairs=()

    case "${kind}" in
    function)
        runner=${PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]}
        runnerArgs=${PADM_REGRESSION_SELECTOR_RUNNER_ARGS["${selector}"]:-}
        while IFS= read -r child; do
            [[ -n "${child}" ]] || continue
            runnerArgv+=("${child}")
        done <<<"${runnerArgs}"
        "${runner}" "${runnerArgv[@]}"
        ;;
    aggregate-runner)
        runner=${PADM_REGRESSION_SELECTOR_RUNNER["${selector}"]}
        "${runner}"
        ;;
    aggregate)
        if [[ "${PADM_REGRESSION_SELECTOR_MODE[${selector}]}" == "parallel" ]]; then
            while IFS= read -r child; do
                [[ -n "${child}" ]] || continue
                childPairs+=("${child}" "${child}")
            done <<<"${PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]}"
            runParallelRegressionSelectors "${TMP_DIR}/${selector}-parallel-${BASHPID:-$$}" "${childPairs[@]}"
        else
            while IFS= read -r child; do
                [[ -n "${child}" ]] || continue
                PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${child}"
            done <<<"${PADM_REGRESSION_SELECTOR_CHILDREN["${selector}"]}"
        fi
        ;;
    alias)
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${PADM_REGRESSION_SELECTOR_ALIAS["${selector}"]}"
        ;;
    *)
        printf 'unknown regression selector: %s\n' "${selector}" >&2
        return 2
        ;;
    esac
}

runRegisteredRegressionMain() {
    local selector=${1:-fast}

    if [[ "${PADM_REGRESSION_REGISTRY_VALIDATED:-}" != "1" ]]; then
        validateRegressionRegistry || return 1
    fi

    if [[ -z "${PADM_REGRESSION_SELECTOR_KIND[${selector}]:-}" ]]; then
        renderRegressionUsage
        return 2
    fi

    runRegressionStep "total:${selector}" runRegisteredRegressionSelector "${selector}"
    if [[ "${PADM_REGRESSION_SUPPRESS_DONE:-}" != "1" ]]; then
        echo "subscription-groups-regression-ok:${selector}"
    fi
}
