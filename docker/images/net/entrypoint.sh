#!/bin/sh
set -eu

STATE_ROOT=/var/lib/padm/net
die() { echo "padm-net: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
integer() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
wait_forever() {
    stop=0
    trap 'stop=1' INT TERM
    while [ "$stop" -eq 0 ]; do
        sleep 86400 &
        child=$!
        wait "$child" || true
    done
}

wireguard_preflight() {
    config=$1
    interface=$2
    ownership=${3:-unowned}
    need ip
    need wg
    need wg-quick
    [ -f "$config" ] && [ ! -L "$config" ] || die "WireGuard config is not a regular file"
    wg-quick strip "$config" >/dev/null 2>&1 || die "WireGuard config cannot be parsed"
    case "$interface" in wg-padm) ;; *) die "unexpected WireGuard interface" ;; esac
    if ip link show dev "$interface" >/dev/null 2>&1; then
        [ "$ownership" = owned ] || die "WireGuard interface already exists"
    fi
    check="pdw$$"
    cleanup_check() { ip link delete dev "$check" >/dev/null 2>&1 || true; }
    trap 'cleanup_check; exit 130' INT TERM
    ip link add dev "$check" type wireguard >/dev/null 2>&1 || {
        trap - INT TERM
        die "WireGuard kernel module is unavailable"
    }
    ip link delete dev "$check" >/dev/null 2>&1 || {
        trap - INT TERM
        die "cannot remove WireGuard preflight interface"
    }
    trap - INT TERM
}

wireguard_cleanup() {
    config=$1
    interface=$2
    wg-quick down "$config" >/dev/null 2>&1 || ip link delete dev "$interface" >/dev/null 2>&1 || true
    rm -f "$STATE_ROOT/wireguard.state"
}

wireguard_run() {
    config=$1
    interface=$2
    wireguard_preflight "$config" "$interface" owned
    if [ -f "$STATE_ROOT/wireguard.state" ]; then
        wireguard_cleanup "$config" "$interface"
    elif ip link show dev "$interface" >/dev/null 2>&1; then
        die "WireGuard interface is not owned by padm"
    fi
    printf 'interface=%s\n' "$interface" >"$STATE_ROOT/wireguard.state"
    if ! wg-quick up "$config" >/dev/null 2>&1; then
        wireguard_cleanup "$config" "$interface"
        die "WireGuard interface failed to start"
    fi
    trap 'wireguard_cleanup "$config" "$interface"' INT TERM EXIT
    wait_forever
}

wireguard_health() {
    interface=$1
    need ip
    need wg
    ip link show dev "$interface" >/dev/null 2>&1 || exit 1
    wg show "$interface" >/dev/null 2>&1
}

fail2ban_preflight() {
    ports=$1
    need fail2ban-client
    need iptables
    case "$ports" in ''|*[!0-9,]*|,*|*,|*,,*) die "invalid Fail2ban port list" ;; esac
    [ -f /var/log/padm/nginx/access.log ] && [ ! -L /var/log/padm/nginx/access.log ] ||
        die "Nginx access log is missing"
    iptables -w -n -L DOCKER-USER >/dev/null 2>&1 || die "DOCKER-USER chain is unavailable"
    fail2ban-client -t >/dev/null 2>&1 || die "Fail2ban configuration is invalid"
}

mark_rule_present() {
    mark_hex=$(printf '%x' "$1")
    ip rule show | grep -Eq "fwmark[[:space:]]+(0x)?$mark_hex(/|[[:space:]])"
}

fail2ban_cleanup() {
    ports=$1
    iptables -w -D DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport "$ports" -j padm-f2b >/dev/null 2>&1 || true
    iptables -w -F padm-f2b >/dev/null 2>&1 || true
    iptables -w -X padm-f2b >/dev/null 2>&1 || true
}

fail2ban_run() {
    ports=$1
    fail2ban_preflight "$ports"
    if [ -f "$STATE_ROOT/fail2ban.state" ]; then
        old_ports=$(sed -n 's/^ports=//p' "$STATE_ROOT/fail2ban.state")
        [ -n "$old_ports" ] && fail2ban_cleanup "$old_ports"
    fi
    printf 'ports=%s\n' "$ports" >"$STATE_ROOT/fail2ban.state"
    fail2ban-server -f -x -s /run/fail2ban/fail2ban.sock &
    server=$!
    trap 'fail2ban-client stop >/dev/null 2>&1 || kill "$server" >/dev/null 2>&1 || true' INT TERM
    status=0
    wait "$server" || status=$?
    fail2ban_cleanup "$ports"
    rm -f "$STATE_ROOT/fail2ban.state"
    return "$status"
}

fail2ban_health() {
    need fail2ban-client
    fail2ban-client ping >/dev/null 2>&1
}

tun_preflight() {
    need ip
    need nft
    [ -c /dev/net/tun ] || die "/dev/net/tun is unavailable"
    nft list ruleset >/dev/null 2>&1 || die "nftables is unavailable"
    check="pdt$$"
    cleanup_check() { ip link delete dev "$check" >/dev/null 2>&1 || true; }
    trap 'cleanup_check; exit 130' INT TERM
    ip tuntap add dev "$check" mode tun >/dev/null 2>&1 || {
        trap - INT TERM
        die "TUN device cannot be created"
    }
    ip link delete dev "$check" >/dev/null 2>&1 || {
        trap - INT TERM
        die "cannot remove TUN preflight interface"
    }
    trap - INT TERM
}

tproxy_preflight() {
    port=$1
    mark=$2
    ownership=${3:-unowned}
    integer "$port" && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "invalid TProxy port"
    integer "$mark" && [ "$mark" -ge 1 ] || die "invalid TProxy mark"
    need ip
    need iptables
    [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true)" = 1 ] || die "IPv4 forwarding is disabled"
    iptables -w -t mangle -n -L >/dev/null 2>&1 || die "mangle table is unavailable"
    iptables -w -j TPROXY -h >/dev/null 2>&1 || die "TPROXY target is unavailable"
    if iptables -w -t mangle -n -L padm-tproxy >/dev/null 2>&1; then
        [ "$ownership" = owned ] || die "padm-tproxy chain is already present"
    fi
    if mark_rule_present "$mark"; then
        [ "$ownership" = owned ] || die "TProxy mark is already in use"
    fi
}

tproxy_cleanup() {
    mark=$2
    while iptables -w -t mangle -C PREROUTING -j padm-tproxy >/dev/null 2>&1; do
        iptables -w -t mangle -D PREROUTING -j padm-tproxy >/dev/null 2>&1 || break
    done
    iptables -w -t mangle -F padm-tproxy >/dev/null 2>&1 || true
    iptables -w -t mangle -X padm-tproxy >/dev/null 2>&1 || true
    ip rule del fwmark "$mark/0xffffffff" lookup "$mark" >/dev/null 2>&1 || true
    ip route flush table "$mark" >/dev/null 2>&1 || true
    rm -f "$STATE_ROOT/tproxy.state"
}

tproxy_run() {
    port=$1
    mark=$2
    ownership=unowned
    [ -f "$STATE_ROOT/tproxy.state" ] && ownership=owned
    tproxy_preflight "$port" "$mark" "$ownership"
    if [ -f "$STATE_ROOT/tproxy.state" ]; then
        old_port=$(sed -n 's/^port=//p' "$STATE_ROOT/tproxy.state")
        old_mark=$(sed -n 's/^mark=//p' "$STATE_ROOT/tproxy.state")
        [ -n "$old_port" ] && [ -n "$old_mark" ] && tproxy_cleanup "$old_port" "$old_mark"
    fi
    printf 'port=%s\nmark=%s\n' "$port" "$mark" >"$STATE_ROOT/tproxy.state"
    if ! {
        ip route add local 0.0.0.0/0 dev lo table "$mark"
        ip rule add fwmark "$mark/0xffffffff" lookup "$mark"
        iptables -w -t mangle -N padm-tproxy
        iptables -w -t mangle -A padm-tproxy -m addrtype --dst-type LOCAL -j RETURN
        iptables -w -t mangle -A padm-tproxy -p tcp -j TPROXY --on-port "$port" --tproxy-mark "$mark/0xffffffff"
        iptables -w -t mangle -A padm-tproxy -p udp -j TPROXY --on-port "$port" --tproxy-mark "$mark/0xffffffff"
        iptables -w -t mangle -I PREROUTING 1 -j padm-tproxy
    }; then
        tproxy_cleanup "$port" "$mark"
        die "TProxy firewall rules failed to start"
    fi
    trap 'tproxy_cleanup "$port" "$mark"' INT TERM EXIT
    wait_forever
}

tproxy_health() {
    port=$1
    mark=$2
    integer "$port" && integer "$mark" || exit 1
    iptables -w -t mangle -n -L padm-tproxy >/dev/null 2>&1 || exit 1
    mark_rule_present "$mark"
}

case "${1:-idle}" in
idle)
    exec tail -f /dev/null
    ;;
health)
    need fail2ban-client
    need ip
    need iptables
    need nft
    need wg
    ;;
preflight)
    shift
    case "${1:-}" in
    wireguard) shift; wireguard_preflight "$@" ;;
    fail2ban) shift; fail2ban_preflight "$@" ;;
    tun) shift; tun_preflight "$@" ;;
    tproxy) shift; tproxy_preflight "$@" ;;
    *) die "unsupported preflight" ;;
    esac
    ;;
wireguard)
    shift; [ "$#" -eq 2 ] || die "wireguard requires config and interface"; wireguard_run "$@"
    ;;
fail2ban)
    shift; [ "$#" -eq 1 ] || die "fail2ban requires ports"; fail2ban_run "$@"
    ;;
tproxy)
    shift; [ "$#" -eq 2 ] || die "tproxy requires port and mark"; tproxy_run "$@"
    ;;
wireguard-health)
    shift; [ "$#" -eq 1 ] || exit 1; wireguard_health "$@"
    ;;
fail2ban-health)
    fail2ban_health
    ;;
tproxy-health)
    shift; [ "$#" -eq 2 ] || exit 1; tproxy_health "$@"
    ;;
exec)
    shift
    [ "$#" -gt 0 ] || die "net exec requires a command"
    exec "$@"
    ;;
*)
    die "unsupported net command: $1"
    ;;
esac
