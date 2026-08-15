#!/usr/bin/env bash

if [[ "${PADM_REGRESSION_FRAMEWORK_RUNTIME_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_REGRESSION_FRAMEWORK_RUNTIME_LOADED=1

cleanupRegressionProcessGroups() {
    local pid

    trap - EXIT INT TERM
    for pid in "$@"; do
        [[ -n "${pid}" ]] || continue
        kill -TERM -- "-${pid}" >/dev/null 2>&1 || true
    done
    for pid in "$@"; do
        [[ -n "${pid}" ]] || continue
        kill -KILL -- "-${pid}" >/dev/null 2>&1 || true
    done
    for pid in "$@"; do
        [[ -n "${pid}" ]] || continue
        wait "${pid}" 2>/dev/null || true
    done
}

runParallelRegressionRunners() (
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a runners=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local status=0
    local hadErrexit=0
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

    set -m
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'cleanupRegressionProcessGroups "${pids[@]}"' EXIT

    case $- in
    *e*) hadErrexit=1 ;;
    esac

    set +e
    for i in "${!runners[@]}"; do
        (
            trap - EXIT INT TERM
            set +m
            set -e
            runRegressionStep "total:${labels[$i]}" "${runners[$i]}"
        ) >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done

    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
        pids[$i]=
    done
    if (( hadErrexit )); then
        set -e
    else
        set +e
    fi

    for i in "${!logs[@]}"; do
        [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
        if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
            status=${statuses[$i]}
        fi
    done

    trap - EXIT INT TERM
    return "${status}"
)

runFrameworkParallelRegressionSelectors() (
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a selectors=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local -a rcFiles=()
    local -a completed=()
    local selectorRunner="${PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER:-runRegisteredRegressionMain}"
    local selectorMode="${PADM_REGRESSION_PARALLEL_SELECTOR_MODE:-selectors}"
    local status=0
    local maxJobs="${PADM_REGRESSION_PARALLEL_JOBS:-0}"
    local nextIndex=0
    local running=0
    local hadErrexit=0
    local i
    local madeProgress

    if [[ $# -eq 0 ]]; then
        printf 'runFrameworkParallelRegressionSelectors expects at least one selector\n' >&2
        return 2
    fi

    mkdir -p "${orchestrationRoot}"
    case "${selectorMode}" in
    pairs)
        if (( $# % 2 != 0 )); then
            printf 'runFrameworkParallelRegressionSelectors expects label/selector pairs\n' >&2
            return 2
        fi
        while [[ $# -gt 0 ]]; do
            labels+=("$1")
            selectors+=("$2")
            logs+=("${orchestrationRoot}/$1.log")
            rcFiles+=("${orchestrationRoot}/$1.rc")
            shift 2
        done
        ;;
    selectors)
        ;;
    *)
        printf 'unknown parallel selector mode: %s\n' "${selectorMode}" >&2
        return 2
        ;;
    esac

    if [[ "${#selectors[@]}" -eq 0 ]]; then
        while [[ $# -gt 0 ]]; do
            labels+=("$1")
            selectors+=("$1")
            logs+=("${orchestrationRoot}/$1.log")
            rcFiles+=("${orchestrationRoot}/$1.rc")
            shift
        done
    fi

    if ! [[ "${maxJobs}" =~ ^[0-9]+$ ]] || [[ "${maxJobs}" -le 0 ]]; then
        maxJobs=${#selectors[@]}
    fi

    set -m
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'cleanupRegressionProcessGroups "${pids[@]}"' EXIT

    case $- in
    *e*) hadErrexit=1 ;;
    esac

    set +e
    while [[ "${nextIndex}" -lt "${#selectors[@]}" || "${running}" -gt 0 ]]; do
        while [[ "${nextIndex}" -lt "${#selectors[@]}" && "${running}" -lt "${maxJobs}" ]]; do
            i=${nextIndex}
            (
                trap - EXIT INT TERM
                set +m
                rc=0
                set +e
                runRegressionStep "${labels[$i]}" "${selectorRunner}" "${selectors[$i]}"
                rc=$?
                printf '%s\n' "${rc}" >"${rcFiles[$i]}"
                exit "${rc}"
            ) >"${logs[$i]}" 2>&1 &
            pids[$i]=$!
            completed[$i]=0
            nextIndex=$((nextIndex + 1))
            running=$((running + 1))
        done

        madeProgress=
        for ((i = 0; i < nextIndex; i++)); do
            if [[ "${completed[$i]:-0}" -eq 0 && -f "${rcFiles[$i]}" ]]; then
                statuses[$i]=$(<"${rcFiles[$i]}")
                wait "${pids[$i]}" >/dev/null 2>&1
                pids[$i]=
                completed[$i]=1
                [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
                if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
                    status=${statuses[$i]}
                fi
                running=$((running - 1))
                madeProgress=1
            elif [[ "${completed[$i]:-0}" -eq 0 ]] && ! kill -0 "${pids[$i]}" 2>/dev/null; then
                wait "${pids[$i]}"
                statuses[$i]=$?
                pids[$i]=
                completed[$i]=1
                [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
                if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
                    status=${statuses[$i]}
                fi
                running=$((running - 1))
                madeProgress=1
            fi
        done
        if [[ -z "${madeProgress}" ]]; then
            sleep 0.05
        fi
    done
    if (( hadErrexit )); then
        set -e
    else
        set +e
    fi

    trap - EXIT INT TERM
    return "${status}"
)

runFrameworkParallelRegressionSelectorList() {
    local orchestrationRoot=$1
    local selectorListFn=$2
    shift 2
    local -a selectors=()
    local -a selectorPairs=()
    local selector

    mapfile -t selectors < <("${selectorListFn}" "$@")
    for selector in "${selectors[@]}"; do
        [[ -n "${selector}" ]] || continue
        selectorPairs+=("${selector}" "${selector}")
    done

    PADM_REGRESSION_PARALLEL_SELECTOR_MODE=pairs \
        runFrameworkParallelRegressionSelectors "${orchestrationRoot}" \
        "${selectorPairs[@]}"
}

runFrameworkParallelCompositionContract() (
    set -euo pipefail
    local suiteSelector=$1
    local waitingSelector=$2
    local signalingSelector=$3
    local callLog="${TMP_DIR}/regression-${suiteSelector}-parallel-composition.log"
    local startMarker="${TMP_DIR}/regression-${suiteSelector}-parallel-started"

    : >"${callLog}"
    rm -f "${startMarker}"

    runRegressionParallelCompositionProbe() {
        local selector=$1

        printf '%s-start\n' "${selector}" >>"${callLog}"
        if [[ "${selector}" == "${waitingSelector}" ]]; then
            for _ in 1 2 3 4 5 6 7 8 9 10; do
                [[ -f "${startMarker}" ]] && break
                sleep 0.05
            done
        elif [[ "${selector}" == "${signalingSelector}" ]]; then
            : >"${startMarker}"
        fi
        printf '%s-finish\n' "${selector}" >>"${callLog}"
    }

    PADM_REGRESSION_SUPPRESS_DONE=1 \
        PADM_REGRESSION_PARALLEL_SELECTOR_RUNNER=runRegressionParallelCompositionProbe \
        runRegisteredRegressionMain "${suiteSelector}"
    awk -v waiting="${waitingSelector}" -v signaling="${signalingSelector}" '
        $0 == waiting "-start" { waitingStart = NR }
        $0 == signaling "-start" { signalingStart = NR }
        $0 == waiting "-finish" { waitingFinish = NR }
        END { exit !(waitingStart && signalingStart && waitingFinish && signalingStart < waitingFinish) }
    ' "${callLog}"
)

runFrameworkParallelRegressionSelectorListWithJobs() {
    local orchestrationRoot=$1
    local selectorListFn=$2
    local jobs=
    local effectiveJobs=

    shift 2
    if [[ $# -gt 0 ]]; then
        jobs=$1
        shift
    fi

    effectiveJobs="${PADM_REGRESSION_PARALLEL_JOBS:-${jobs}}"
    if [[ -n "${effectiveJobs}" ]]; then
        PADM_REGRESSION_PARALLEL_JOBS="${effectiveJobs}" \
            runFrameworkParallelRegressionSelectorList "${orchestrationRoot}" "${selectorListFn}" "$@"
        return
    fi

    runFrameworkParallelRegressionSelectorList "${orchestrationRoot}" "${selectorListFn}" "$@"
}

runFrameworkSequentialRegressionSelectorList() {
    local selectorListFn=$1
    local status=0
    local hadErrexit=0
    shift
    local -a selectors=()
    local selector

    mapfile -t selectors < <("${selectorListFn}" "$@")
    case $- in
    *e*) hadErrexit=1; set +e ;;
    esac
    for selector in "${selectors[@]}"; do
        [[ -n "${selector}" ]] || continue
        PADM_REGRESSION_SUPPRESS_DONE=1 runRegisteredRegressionMain "${selector}"
        status=$?
        if (( status != 0 )); then
            break
        fi
    done
    if (( hadErrexit )); then
        set -e
    fi
    return "${status}"
}
