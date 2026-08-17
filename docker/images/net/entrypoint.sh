#!/bin/sh
set -eu

case "${1:-idle}" in
idle)
    exec tail -f /dev/null
    ;;
health)
    command -v fail2ban-client >/dev/null
    command -v ip >/dev/null
    command -v iptables >/dev/null
    command -v nft >/dev/null
    command -v wg >/dev/null
    ;;
exec)
    shift
    if [ "$#" -eq 0 ]; then
        echo "net exec requires a command" >&2
        exit 64
    fi
    exec "$@"
    ;;
*)
    echo "unsupported net command: $1" >&2
    exit 64
    ;;
esac
