#!/bin/sh
set -eu

case "${1:-idle}" in
idle)
    exec tail -f /dev/null
    ;;
health)
    python3 --version >/dev/null
    openssl version >/dev/null
    test -x /opt/acme/acme.sh
    ;;
acme)
    shift
    exec /opt/acme/acme.sh --home "${PADM_ACME_HOME:-/var/lib/padm/acme}" "$@"
    ;;
subscription)
    shift
    script=${PADM_SUBSCRIPTION_SERVER:-/opt/padm/subscription/control_server.py}
    if [ ! -f "${script}" ]; then
        echo "subscription control server is not installed: ${script}" >&2
        exit 66
    fi
    exec python3 "${script}" "$@"
    ;;
*)
    echo "unsupported ops command: $1" >&2
    exit 64
    ;;
esac
