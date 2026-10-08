#!/bin/sh
set -eu

STATE_ROOT=/var/lib/padm/net
die() { echo "padm-net: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
integer() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }
wait_forever() {
    stop=0
    child=
    trap 'stop=1; [ -z "$child" ] || kill "$child" 2>/dev/null || true' INT TERM
    [ "${start_signal:-0}" -eq 0 ] || stop=1
    while [ "$stop" -eq 0 ]; do
        sleep 86400 &
        child=$!
        [ "$stop" -eq 0 ] || kill "$child" 2>/dev/null || true
        wait "$child" || true
        wait "$child" 2>/dev/null || true
        child=
    done
}

wireguard_private_file() {
    [ -f "$1" ] && [ ! -L "$1" ] &&
        [ "$(stat -c '%u:%a' "$1")" = 0:600 ]
}

wireguard_state_directory() {
    [ -d "$1" ] && [ ! -L "$1" ] &&
        [ "$(stat -c '%u' "$1")" = 0 ] || return 1
    mode=$(stat -c '%a' "$1") || return 1
    [ "$((0$mode & 0022))" -eq 0 ]
}

wireguard_snapshot_safe() {
    [ -d "$STATE_ROOT/wireguard" ] && [ ! -L "$STATE_ROOT/wireguard" ] &&
        [ "$(stat -c '%u:%a' "$STATE_ROOT/wireguard")" = 0:700 ] &&
        wireguard_private_file "$STATE_ROOT/wireguard/wg-padm.conf" &&
        ! grep -Eiq '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown|SaveConfig|DNS)[[:space:]]*=' \
            "$STATE_ROOT/wireguard/wg-padm.conf"
}

wireguard_link_index() {
    ip -o link show dev "$1" 2>/dev/null | awk -F: 'NR == 1 {gsub(/ /, "", $1); print $1}'
}

wireguard_identity() (
    interface=$1
    [ "$interface" = wg-padm ] || exit 1
    link=$(ip -o link show dev "$interface" 2>/dev/null) || exit 1
    index=$(printf '%s\n' "$link" | awk -F: 'NR == 1 {gsub(/ /, "", $1); print $1}')
    alias=$(printf '%s\n' "$link" | awk '{for (i=1; i<NF; i++) if ($i=="alias") {sub(/\\$/, "", $(i+1)); print $(i+1)}}')
    public_key=$(wg show "$interface" public-key 2>/dev/null) || exit 1
    integer "$index" && [ "$index" -gt 0 ] || exit 1
    [ -z "$alias" ] ||
        printf '%s\n' "$alias" | grep -Eq '^padm-wireguard-[a-f0-9]{32}$' || exit 1
    printf '%s\n' "$public_key" | grep -Eq '^[A-Za-z0-9+/]{43}=$' || exit 1
    printf 'schema_version=2\ninterface=wg-padm\nifindex=%s\npublic_key=%s\nalias=%s\n' \
        "$index" "$public_key" "$alias"
)

wireguard_owned() (
    state_root=${2:-$STATE_ROOT}
    state=$state_root/wireguard.state
    wireguard_state_directory "$state_root" || exit 1
    wireguard_private_file "$state" && [ "$(stat -c '%s' "$state")" -le 512 ] || exit 1
    identity=$(wireguard_identity "$1") || exit 1
    printf '%s\n' "$identity" | grep -Eq '^alias=padm-wireguard-[a-f0-9]{32}$' || exit 1
    [ "$(cat "$state")" = "$identity" ]
)

wireguard_preflight() {
    config=$1
    interface=$2
    ownership=${3:-unowned}
    ownership_root=${4:-$STATE_ROOT}
    need ip
    need wg
    need wg-quick
    [ -f "$config" ] && [ ! -L "$config" ] || die "WireGuard config is not a regular file"
    [ "$(basename "$config")" = "$interface.conf" ] || die "WireGuard config name does not match interface"
    if grep -Eiq '^[[:space:]]*(PreUp|PostUp|PreDown|PostDown|SaveConfig|DNS)[[:space:]]*=' "$config"; then
        die "WireGuard hooks, DNS and SaveConfig are not allowed"
    fi
    wg-quick strip "$config" >/dev/null 2>&1 || die "WireGuard config cannot be parsed"
    wg-quick strip "$config" 2>/dev/null | awk '
        /^[[:space:]]*PrivateKey[[:space:]]*=/ {
            count++; key=$0; sub(/^[^=]*=[[:space:]]*/, "", key); sub(/[[:space:]]*$/, "", key)
        }
        END {if (count == 1) print key; else exit 1}
    ' | wg pubkey >/dev/null 2>&1 || die "WireGuard private key is missing or invalid"
    case "$interface" in wg-padm) ;; *) die "unexpected WireGuard interface" ;; esac
    if ip link show dev "$interface" >/dev/null 2>&1; then
        [ "$ownership" = owned ] && wireguard_owned "$interface" "$ownership_root" ||
            die "WireGuard interface ownership is unverified; stop the previous owner before migration"
    fi
    random=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
    [ "${#random}" -eq 16 ] || die "WireGuard preflight random source failed"
    check="pdw$(printf '%s' "$random" | cut -c1-12)"
    check_index=
    cleanup_check() {
        [ -n "$check_index" ] &&
            [ "$(wireguard_link_index "$check")" = "$check_index" ] || return 0
        ip link delete dev "$check" >/dev/null 2>&1
    }
    probe_signal=0
    trap 'probe_signal=1' INT TERM
    ip link add dev "$check" type wireguard >/dev/null 2>&1 ||
        die "WireGuard kernel module is unavailable"
    check_index=$(wireguard_link_index "$check")
    integer "$check_index" && [ "$check_index" -gt 0 ] ||
        die "cannot identify WireGuard preflight interface"
    cleanup_check || die "cannot remove WireGuard preflight interface"
    [ "$probe_signal" -eq 0 ] || exit 130
    trap - INT TERM
}

wireguard_cleanup() (
    interface=$1
    wireguard_state_directory "$STATE_ROOT" || return 1
    [ ! -L "$STATE_ROOT/wireguard" ] && [ ! -L "$STATE_ROOT/wireguard.state" ] || return 1
    if [ -e "$STATE_ROOT/wireguard" ]; then
        [ "$(stat -c '%u:%a' "$STATE_ROOT/wireguard")" = 0:700 ] || return 1
    fi
    if ip link show dev "$interface" >/dev/null 2>&1; then
        wireguard_owned "$interface" || {
            echo "padm-net: WireGuard ownership changed; keeping interface and recovery state" >&2
            return 1
        }
        saved_config=$STATE_ROOT/wireguard/wg-padm.conf
        wireguard_snapshot_safe || return 1
        # 撤销必须使用启动快照，不能按更新后的配置清理旧路由。
        wg-quick down "$saved_config" >/dev/null 2>&1 || return 1
        if ip link show dev "$interface" >/dev/null 2>&1; then
            return 1
        fi
    fi
    rm -f "$STATE_ROOT/wireguard.state" "$STATE_ROOT/wireguard/wg-padm.conf"
    rmdir "$STATE_ROOT/wireguard" 2>/dev/null || true
)

wireguard_start_cleanup() (
    wireguard_snapshot_safe || return 1
    current=$(wireguard_identity "$interface") || return 1
    [ "$current" = "$start_identity" ] || [ "$current" = "$marked_identity" ] || {
        echo "padm-net: WireGuard startup ownership changed; keeping interface and recovery state" >&2
        return 1
    }
    wg-quick down "$saved_config" >/dev/null 2>&1 || return 1
    wireguard_cleanup "$interface"
)

wireguard_run() {
    config=$1
    interface=$2
    wireguard_preflight "$config" "$interface" owned
    wireguard_state_directory "$STATE_ROOT" || die "WireGuard state directory is unsafe"
    [ ! -L "$STATE_ROOT/wireguard" ] && [ ! -L "$STATE_ROOT/wireguard.state" ] &&
        { [ ! -e "$STATE_ROOT/wireguard.state" ] || [ -f "$STATE_ROOT/wireguard.state" ]; } ||
        die "WireGuard recovery path is unsafe"
    if [ -e "$STATE_ROOT/wireguard" ]; then
        [ "$(stat -c '%u:%a' "$STATE_ROOT/wireguard")" = 0:700 ] ||
            die "WireGuard recovery directory is unsafe"
    fi
    wireguard_cleanup "$interface" || die "WireGuard previous state could not be revoked"
    trap 'wireguard_cleanup "$interface" || exit 1' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir -p "$STATE_ROOT/wireguard"
    chmod 0700 "$STATE_ROOT/wireguard"
    saved_config=$STATE_ROOT/wireguard/wg-padm.conf
    (umask 077; cp "$config" "$saved_config")
    chmod 0600 "$saved_config"
    random=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [ "${#random}" -eq 32 ] || die "WireGuard ownership random source failed"
    alias=padm-wireguard-$random
    up_pid=
    start_signal=0
    trap 'start_signal=130; [ -z "$up_pid" ] || kill -TERM "$up_pid" 2>/dev/null || true' INT
    trap 'start_signal=143; [ -z "$up_pid" ] || kill -TERM "$up_pid" 2>/dev/null || true' TERM
    wg-quick up "$saved_config" >/dev/null 2>&1 &
    up_pid=$!
    [ "$start_signal" -eq 0 ] || kill -TERM "$up_pid" 2>/dev/null || true
    up_status=0
    wait "$up_pid" || up_status=$?
    if [ "$start_signal" -ne 0 ]; then
        up_status=0
        wait "$up_pid" 2>/dev/null || up_status=$?
    fi
    up_pid=
    if [ "$up_status" -ne 0 ]; then
        # wg-quick 自己回滚未完成的启动，不按同名接口猜测归属。
        if ! ip link show dev "$interface" >/dev/null 2>&1; then
            wireguard_cleanup "$interface" || true
        fi
        [ "$start_signal" -eq 0 ] || exit "$start_signal"
        die "WireGuard interface failed to start"
    fi
    start_identity=$(wireguard_identity "$interface") ||
        die "cannot identify newly started WireGuard interface"
    marked_identity=$(printf '%s\n' "$start_identity" | sed "s/^alias=.*/alias=$alias/")
    trap 'wireguard_start_cleanup || exit 1' EXIT
    ip link set dev "$interface" alias "$alias" ||
        die "cannot mark WireGuard interface ownership"
    state_stage=$(mktemp "$STATE_ROOT/.wireguard-state.XXXXXX")
    trap 'rm -f "$state_stage"; wireguard_start_cleanup || exit 1' EXIT
    (identity=$(wireguard_identity "$interface") &&
        [ "$identity" = "$marked_identity" ] &&
        printf '%s\n' "$identity") >"$state_stage"
    mv -f "$state_stage" "$STATE_ROOT/wireguard.state"
    trap 'wireguard_cleanup "$interface" || exit 1' EXIT
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    wait_forever
}

wireguard_health() {
    interface=$1
    need ip
    need wg
    wireguard_owned "$interface"
}

fail2ban_preflight() {
    ports=$1
    need fail2ban-client
    need iptables
    case "$ports" in ''|*[!0-9,]*|,*|*,|*,,*) die "invalid Fail2ban port list" ;; esac
    [ -f /var/log/padm/nginx/access.log ] && [ ! -L /var/log/padm/nginx/access.log ] ||
        die "Nginx access log is missing"
    iptables -w -n -L DOCKER-USER >/dev/null 2>&1 || die "DOCKER-USER chain is unavailable"
    if grep -qx 'allowipv6 = yes' /etc/fail2ban/fail2ban.local; then
        need ip6tables
        ip6tables -w -n -L DOCKER-USER >/dev/null 2>&1 || die "IPv6 DOCKER-USER chain is unavailable"
    fi
    fail2ban-client -t >/dev/null 2>&1 || die "Fail2ban configuration is invalid"
}

mark_rule_present() {
    mark_hex=$(printf '%x' "$1")
    ip rule show | grep -Eq "fwmark[[:space:]]+(0x)?$mark_hex(/|[[:space:]])"
}

fail2ban_cleanup() {
    old_ifs=$IFS
    IFS=,
    for port in $1; do
        iptables -w -D DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport "$port" -j padm-f2b >/dev/null 2>&1 || true
        ip6tables -w -D DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport "$port" -j padm-f2b >/dev/null 2>&1 || true
    done
    IFS=$old_ifs
    iptables -w -F padm-f2b >/dev/null 2>&1 || true
    iptables -w -X padm-f2b >/dev/null 2>&1 || true
    ip6tables -w -F padm-f2b >/dev/null 2>&1 || true
    ip6tables -w -X padm-f2b >/dev/null 2>&1 || true
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
    stopped=0
    trap 'stopped=1; fail2ban-client stop >/dev/null 2>&1 || kill "$server" >/dev/null 2>&1 || true' INT TERM
    status=0
    wait "$server" || status=$?
    if [ "$stopped" -eq 1 ]; then
        status=0
        wait "$server" || status=$?
    fi
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
    need ip6tables
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
