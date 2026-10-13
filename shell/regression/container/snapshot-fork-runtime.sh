#!/usr/bin/env bash

padmSnapshotForkStart() {
    local directory sourceDirectory deadline
    sourceDirectory=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd -P) || return 1
    directory=$(mktemp -d "${TMPDIR:-/tmp}/snapshot-fork.XXXXXX") || return 1
    chmod 0700 "${directory}" || return 1
    gcc -O2 -Wall -Wextra "${sourceDirectory}/snapshot-fork-client.c" \
        -o "${directory}/client" || return 1
    export PADM_SNAPSHOT_FORK_CLIENT="${directory}/client"
    export PADM_SNAPSHOT_FORK_SOCKET="${directory}/socket"
    command python3 "${sourceDirectory}/snapshot-fork-server.py" \
        "${PADM_SNAPSHOT_FORK_SOCKET}" /work/docker/lib/services.sh \
        >"${directory}/server.log" 2>&1 &
    PADM_SNAPSHOT_FORK_PID=$!
    export PADM_SNAPSHOT_FORK_PID
    deadline=$((SECONDS + 5))
    while [[ ! -f "${PADM_SNAPSHOT_FORK_SOCKET}.ready" ]]; do
        if ! kill -0 "${PADM_SNAPSHOT_FORK_PID}" 2>/dev/null || ((SECONDS >= deadline)); then
            cat -- "${directory}/server.log" >&2
            kill "${PADM_SNAPSHOT_FORK_PID}" 2>/dev/null || true
            return 1
        fi
        sleep 0.01
    done
    if ! command python3 "${sourceDirectory}/snapshot-fork-test.py" \
        "${PADM_SNAPSHOT_FORK_CLIENT}" /work/docker/lib/services.sh; then
        kill "${PADM_SNAPSHOT_FORK_PID}" 2>/dev/null || true
        return 1
    fi
    export PADM_SNAPSHOT_PREVIOUS_BASH_ENV=${BASH_ENV:-}
    export BASH_ENV="${sourceDirectory}/snapshot-fork-runtime.sh"
}

if [[ -n "${PADM_SNAPSHOT_PREVIOUS_BASH_ENV:-}" &&
    "${PADM_SNAPSHOT_PREVIOUS_BASH_ENV}" != "${BASH_SOURCE[0]}" ]]; then
    # shellcheck source=/dev/null
    source "${PADM_SNAPSHOT_PREVIOUS_BASH_ENV}"
fi

python3() {
    if [[ "${FUNCNAME[1]:-}" == dockerPortHoppingTargetSnapshot && "$#" == 7 && "$1" == - &&
        ( "${BASH_SOURCE[-1]:-}" == /work/docker/tests/port-hopping-start.sh ||
          "${BASH_SOURCE[-1]:-}" == /work/docker/tests/port-hopping-target.sh ) &&
        -x "${PADM_SNAPSHOT_FORK_CLIENT:-}" ]]; then
        "${PADM_SNAPSHOT_FORK_CLIENT}" "$@"
    else
        command python3 "$@"
    fi
}
