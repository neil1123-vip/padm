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
    python3 /opt/padm/subscription/control_server.py --check
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
subscription-health)
    exec python3 /opt/padm/subscription/control_server.py --health \
        "${PADM_SUBSCRIPTION_HEALTH_URL:-http://127.0.0.1:8081/healthz}"
    ;;
tls-check)
    shift
    [ "$#" -eq 3 ] || {
        echo 'usage: tls-check CERT KEY DOMAIN' >&2
        exit 64
    }
    cert=$1
    key=$2
    domain=$3
    cert_public="/tmp/padm-cert-public.$$"
    key_public="/tmp/padm-key-public.$$"
    test -f "${cert}" && test ! -L "${cert}"
    test -f "${key}" && test ! -L "${key}"
    openssl x509 -in "${cert}" -pubkey -noout >"${cert_public}"
    openssl pkey -in "${key}" -pubout >"${key_public}"
    cmp -s "${cert_public}" "${key_public}"
    openssl x509 -in "${cert}" -noout -checkhost "${domain}" >/dev/null
    ;;
*)
    echo "unsupported ops command: $1" >&2
    exit 64
    ;;
esac
