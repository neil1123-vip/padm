#!/usr/bin/env bash

if [[ "${PADM_REGRESSION_FRAMEWORK_RUNTIME_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_REGRESSION_FRAMEWORK_RUNTIME_LOADED=1

runParallelRegressionRunners() {
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a runners=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local status=0
    local i

    if [[ $# -eq 0 || $(( $# % 2 )) -ne 0 ]]; then
        printf 'runParallelRegressionRunners expects label/runner pairs\n' >&2
        return 2
    fi

    mkdir -p "${orchestrationRoot}"
    while [[ $# -gt 0 ]]; do
        labels+=("$1")
        runners+=("$2")
        logs+=("${orchestrationRoot}/$1.log")
        shift 2
    done

    set +e
    for i in "${!runners[@]}"; do
        (
            trap - EXIT INT TERM
            set -e
            runRegressionStep "total:${labels[$i]}" "${runners[$i]}"
        ) >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done

    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
    done
    set -e

    for i in "${!logs[@]}"; do
        [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
        if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
            status=${statuses[$i]}
        fi
    done

    return "${status}"
}

runParallelRegressionSelectors() {
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a selectors=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local status=0
    local i

    if [[ $# -eq 0 || $(( $# % 2 )) -ne 0 ]]; then
        printf 'runParallelRegressionSelectors expects label/selector pairs\n' >&2
        return 2
    fi

    mkdir -p "${orchestrationRoot}"
    while [[ $# -gt 0 ]]; do
        labels+=("$1")
        selectors+=("$2")
        logs+=("${orchestrationRoot}/$1.log")
        shift 2
    done

    set +e
    for i in "${!selectors[@]}"; do
        (
            trap - EXIT INT TERM
            set -e
            PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selectors[$i]}"
        ) >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done

    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
    done
    set -e

    for i in "${!logs[@]}"; do
        [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
        if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
            status=${statuses[$i]}
        fi
    done

    return "${status}"
}
