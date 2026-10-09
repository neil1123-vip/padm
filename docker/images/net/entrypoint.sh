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

tproxy_state_text() {
    printf 'schema_version=2\ntoken=%s\nchain=%s\nport=%s\nmark=%s\ntable=%s\npref=30000\nroute_proto=186\nrule_proto=186\nrealm=%s\nphase=%s\n' \
        "$tp_token" "$tp_chain" "$tp_port" "$tp_mark" "$tp_mark" "$tp_realm" "$tp_phase"
}

tproxy_state_read() {
    tp_root=${1:-$STATE_ROOT}
    wireguard_state_directory "$tp_root" &&
        wireguard_private_file "$tp_root/tproxy.state" &&
        [ "$(stat -c '%h' "$tp_root/tproxy.state")" -eq 1 ] &&
        [ "$(stat -c '%s' "$tp_root/tproxy.state")" -le 512 ] || return 1
    tp_token=$(sed -n 's/^token=//p' "$tp_root/tproxy.state")
    tp_chain=$(sed -n 's/^chain=//p' "$tp_root/tproxy.state")
    tp_port=$(sed -n 's/^port=//p' "$tp_root/tproxy.state")
    tp_mark=$(sed -n 's/^mark=//p' "$tp_root/tproxy.state")
    tp_realm=$(sed -n 's/^realm=//p' "$tp_root/tproxy.state")
    tp_phase=$(sed -n 's/^phase=//p' "$tp_root/tproxy.state")
    printf '%s\n' "$tp_token" | grep -Eq '^[a-f0-9]{32}$' || return 1
    tp_expected_realm=$((0x$(printf '%s' "$tp_token" | cut -c29-32)))
    [ "$tp_expected_realm" -ne 0 ] || tp_expected_realm=1
    case "$tp_mark" in 0*|253|254|255) return 1 ;; esac
    [ "$tp_chain" = "padm-tproxy-$(printf '%s' "$tp_token" | cut -c1-12)" ] &&
        integer "$tp_port" && [ "$tp_port" -ge 1 ] && [ "$tp_port" -le 65535 ] &&
        integer "$tp_mark" && [ "$tp_mark" -ge 1 ] && [ "$tp_mark" -le 2147483647 ] &&
        integer "$tp_realm" && [ "$tp_realm" -ge 1 ] && [ "$tp_realm" -le 65535 ] &&
        [ "$tp_realm" = "$tp_expected_realm" ] &&
        { [ "$tp_phase" = intent ] || [ "$tp_phase" = active ]; } || return 1
    # 原始字节与固定格式比较，拒绝重复字段、额外内容和 NUL，绝不执行 state。
    tproxy_state_text | cmp -s - "$tp_root/tproxy.state"
}

tproxy_state_write() (
    umask 077
    tp_stage=$(mktemp "$STATE_ROOT/.tproxy-state.XXXXXX") || return 1
    trap 'rm -f "$tp_stage"' EXIT
    tproxy_state_text >"$tp_stage" && chmod 0600 "$tp_stage" &&
        mv -f "$tp_stage" "$STATE_ROOT/tproxy.state"
)

tproxy_audit() {
    python3 - "$tp_token" "$tp_chain" "$tp_port" "$tp_mark" "$tp_realm" \
        "${1:-partial}" "${tp_created:-}" "${2:-$tp_mark}" <<'PY'
import json
import shlex
import subprocess
import sys

token, chain, port, mark, realm, mode, created, target_mark = sys.argv[1:]
port, mark, realm, target_mark = int(port), int(mark), int(realm), int(target_mark)
comment = "padm-tproxy:" + token

def command(args, empty_table=False):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        if not (empty_table and result.returncode == 2 and result.stdout.strip() == "[]"
                and result.stderr == "Error: ipv4: FIB table does not exist.\nDump terminated\n"):
            raise ValueError("cannot inspect kernel resources")
    return result.stdout

def number(value):
    return int(value, 0) if isinstance(value, str) and value.startswith("0x") else int(value)

rules = json.loads(command(["ip", "-j", "-N", "-4", "rule", "show"]))
routes = json.loads(command(["ip", "-j", "-N", "-4", "route", "show", "table", str(mark)], True))
if target_mark != mark:
    if json.loads(command(["ip", "-j", "-N", "-4", "route", "show", "table", str(target_mark)], True)):
        raise ValueError("requested route table is already in use")
rule_present = False
for rule in rules:
    selected = number(rule.get("priority", -1)) == 30000 or number(rule.get("table", -1)) in {mark, target_mark}
    if "fwmark" in rule:
        mask = number(rule.get("fwmask", 0xffffffff))
        selected |= (mark & mask) == (number(rule["fwmark"]) & mask)
        selected |= (target_mark & mask) == (number(rule["fwmark"]) & mask)
        selected |= "not" in rule
    if not selected:
        continue
    expected = (set(rule) <= {"priority", "src", "fwmark", "fwmask", "table", "protocol"}
                and number(rule.get("priority", -1)) == 30000 and rule.get("src") == "all"
                and number(rule.get("fwmark", -1)) == mark
                and number(rule.get("fwmask", 0xffffffff)) == 0xffffffff
                and number(rule.get("table", -1)) == mark
                and number(rule.get("protocol", -1)) == 186)
    if mode == "empty" or rule_present or not expected:
        raise ValueError("foreign policy rule")
    rule_present = True
route_present = False
for route in routes:
    expected = (set(route) <= {"type", "dst", "dev", "protocol", "scope", "flags", "flow"}
                and number(route.get("type", -1)) == 2 and route.get("dst") == "default"
                and route.get("dev") == "lo" and number(route.get("protocol", -1)) == 186
                and number(route.get("scope", -1)) == 254 and route.get("flags", []) == []
                and set(route.get("flow", {})) == {"to"} and number(route["flow"]["to"]) == realm)
    if mode == "empty" or route_present or not expected:
        raise ValueError("foreign route")
    route_present = True

dump = command(["iptables", "-w", "-t", "mangle", "-S"])
present = [False] * 4
chain_present = False
chain_order = []
for line in dump.splitlines():
    args = shlex.split(line)
    if len(args) == 2 and args[0] == "-N" and (
            args[1] == "padm-tproxy" or
            (args[1].startswith("padm-tproxy-") and args[1] != chain)):
        raise ValueError("unverified TProxy chain")
    if args == ["-N", chain]:
        chain_present = True
        continue
    if not args or args[0] != "-A":
        continue
    own_chain = args[1] == chain
    own_target = "-j" in args and args[args.index("-j") + 1] == chain
    own_comment = "--comment" in args and args[args.index("--comment") + 1] == comment
    if not (own_chain or own_target or own_comment):
        continue
    if mode == "empty" or not own_comment:
        raise ValueError("foreign chain reference")
    values, modules = {}, []
    index = 2
    while index < len(args):
        key, value = args[index:index + 2]
        if key == "-m":
            modules.append(value)
        elif key in values:
            raise ValueError("duplicate rule option")
        else:
            values[key] = value
        index += 2
    base = {"--comment": comment}
    which = None
    if args[1] == "PREROUTING" and values == dict(base, **{"-j": chain}) and modules == ["comment"]:
        which = 0
    elif own_chain and values == dict(base, **{"--dst-type": "LOCAL", "-j": "RETURN"}) and sorted(modules) == ["addrtype", "comment"]:
        which = 1
    elif own_chain and values.get("-p") in {"tcp", "udp"} and sorted(modules) == ["comment"]:
        protocol = values["-p"]
        expected = dict(base, **{"-p": protocol, "-j": "TPROXY", "--on-port": str(port),
                                "--on-ip": "0.0.0.0", "--tproxy-mark": f"0x{mark:x}/0xffffffff"})
        if values == expected:
            which = 2 if protocol == "tcp" else 3
    if which is None or present[which]:
        raise ValueError("changed or duplicate chain rule")
    if own_chain:
        chain_order.append(which)
    present[which] = True
if chain_order != sorted(chain_order):
    raise ValueError("changed chain rule order")
if mode == "empty":
    if chain_present:
        raise ValueError("chain already exists")
elif chain_present and not any(present[1:]) and created != token:
    raise ValueError("empty chain has no verifiable owner")
elif not chain_present and any(present):
    raise ValueError("missing referenced chain")
if mode == "full" and not (chain_present and all(present) and route_present and rule_present):
    raise ValueError("incomplete TProxy resources")
print(" ".join(str(int(value)) for value in [*present, chain_present, rule_present, route_present]))
PY
}

tproxy_preflight() {
    (
    requested_port=$1
    requested_mark=$2
    ownership=${3:-unowned}
    ownership_root=${4:-$STATE_ROOT}
    integer "$requested_port" && [ "$requested_port" -ge 1 ] && [ "$requested_port" -le 65535 ] || die "invalid TProxy port"
    integer "$requested_mark" && [ "$requested_mark" -ge 1 ] &&
        [ "$requested_mark" -le 2147483647 ] || die "invalid TProxy mark"
    case "$requested_mark" in 0*|253|254|255) die "reserved or noncanonical TProxy route table" ;; esac
    need ip
    need iptables
    need python3
    [ "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true)" = 1 ] || die "IPv4 forwarding is disabled"
    iptables -w -t mangle -n -L >/dev/null 2>&1 || die "mangle table is unavailable"
    iptables -w -j TPROXY -h >/dev/null 2>&1 || die "TPROXY target is unavailable"
    if [ -e "$ownership_root/tproxy.state" ] || [ -L "$ownership_root/tproxy.state" ]; then
        [ "$ownership" = owned ] && tproxy_state_read "$ownership_root" &&
            tproxy_audit partial "$requested_mark" >/dev/null || die "TProxy ownership is unverified; refusing migration"
        # 旧资源要先由运行入口撤销；候选预检不修改它们。
    else
        tp_token=00000000000000000000000000000000
        tp_chain=padm-tproxy-000000000000
        tp_port=$requested_port tp_mark=$requested_mark tp_realm=1
        tproxy_audit empty >/dev/null || die "TProxy resources are already in use"
    fi
    )
}

tproxy_cleanup() (
    tp_expected_token=${1:-}
    tproxy_state_read "$STATE_ROOT" || return 1
    [ -z "$tp_expected_token" ] || [ "$tp_expected_token" = "$tp_token" ] || {
        echo "padm-net: TProxy owner was replaced; keeping resources and recovery state" >&2
        return 1
    }
    tp_presence=$(tproxy_audit partial) || {
        echo "padm-net: TProxy ownership changed; keeping resources and recovery state" >&2
        return 1
    }
    set -- $tp_presence
    tp_comment=padm-tproxy:$tp_token
    [ "$1" = 0 ] || iptables -w -t mangle -D PREROUTING -m comment --comment "$tp_comment" -j "$tp_chain" || return 1
    [ "$2" = 0 ] || iptables -w -t mangle -D "$tp_chain" -m addrtype --dst-type LOCAL -m comment --comment "$tp_comment" -j RETURN || return 1
    [ "$3" = 0 ] || iptables -w -t mangle -D "$tp_chain" -p tcp -m comment --comment "$tp_comment" -j TPROXY --on-port "$tp_port" --tproxy-mark "$tp_mark/0xffffffff" || return 1
    [ "$4" = 0 ] || iptables -w -t mangle -D "$tp_chain" -p udp -m comment --comment "$tp_comment" -j TPROXY --on-port "$tp_port" --tproxy-mark "$tp_mark/0xffffffff" || return 1
    [ "$5" = 0 ] || iptables -w -t mangle -X "$tp_chain" || return 1
    [ "$6" = 0 ] || ip -4 rule del pref 30000 fwmark "$tp_mark/0xffffffff" lookup "$tp_mark" protocol 186 || return 1
    [ "$7" = 0 ] || ip -4 route del local 0.0.0.0/0 dev lo table "$tp_mark" proto 186 realm "$tp_realm" || return 1
    # 最后再次确认资源已不存在，失败时保留可重试的原始 state。
    tproxy_audit empty >/dev/null && rm -f "$STATE_ROOT/tproxy.state"
)

tproxy_run() {
    requested_port=$1
    requested_mark=$2
    ownership=unowned
    [ ! -e "$STATE_ROOT/tproxy.state" ] && [ ! -L "$STATE_ROOT/tproxy.state" ] || ownership=owned
    tproxy_preflight "$requested_port" "$requested_mark" "$ownership"
    wireguard_state_directory "$STATE_ROOT" || die "TProxy state directory is unsafe"
    if [ "$ownership" = owned ]; then
        tproxy_cleanup || die "TProxy previous state could not be revoked"
    fi
    tp_port=$requested_port tp_mark=$requested_mark
    tp_token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [ "${#tp_token}" -eq 32 ] || die "TProxy random source failed"
    tp_chain=padm-tproxy-$(printf '%s' "$tp_token" | cut -c1-12)
    tp_realm=$((0x$(printf '%s' "$tp_token" | cut -c29-32)))
    [ "$tp_realm" -ne 0 ] || tp_realm=1
    tp_phase=intent tp_created='' start_signal=0
    tp_comment=padm-tproxy:$tp_token
    tproxy_audit empty >/dev/null || die "TProxy resources changed before start"
    trap 'tp_status=$?; trap - EXIT; if [ -e "$STATE_ROOT/tproxy.state" ] || [ -L "$STATE_ROOT/tproxy.state" ]; then tproxy_cleanup "${tp_token:-}" || tp_status=1; fi; exit "$tp_status"' EXIT
    trap 'start_signal=130' INT
    trap 'start_signal=143' TERM
    tproxy_state_write || die "cannot persist TProxy ownership"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    ip -4 route add local 0.0.0.0/0 dev lo table "$tp_mark" proto 186 realm "$tp_realm" || die "TProxy route failed to start"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    ip -4 rule add pref 30000 fwmark "$tp_mark/0xffffffff" lookup "$tp_mark" protocol 186 || die "TProxy rule failed to start"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    iptables -w -t mangle -N "$tp_chain" || die "TProxy chain failed to start"
    tp_created=$tp_token
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    iptables -w -t mangle -A "$tp_chain" -m addrtype --dst-type LOCAL -m comment --comment "$tp_comment" -j RETURN || die "TProxy local rule failed to start"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    iptables -w -t mangle -A "$tp_chain" -p tcp -m comment --comment "$tp_comment" -j TPROXY --on-port "$tp_port" --tproxy-mark "$tp_mark/0xffffffff" || die "TProxy TCP rule failed to start"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    iptables -w -t mangle -A "$tp_chain" -p udp -m comment --comment "$tp_comment" -j TPROXY --on-port "$tp_port" --tproxy-mark "$tp_mark/0xffffffff" || die "TProxy UDP rule failed to start"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    iptables -w -t mangle -I PREROUTING 1 -m comment --comment "$tp_comment" -j "$tp_chain" || die "TProxy hook failed to start"
    tproxy_audit full >/dev/null || die "TProxy ownership failed after start"
    tp_created=''
    tp_phase=active
    tproxy_state_write || die "cannot commit TProxy ownership"
    [ "$start_signal" -eq 0 ] || exit "$start_signal"
    wait_forever
}

tproxy_health() (
    requested_port=$1 requested_mark=$2
    tproxy_state_read "$STATE_ROOT" &&
        [ "$requested_port" = "$tp_port" ] && [ "$requested_mark" = "$tp_mark" ] &&
        [ "$tp_phase" = active ] && tproxy_audit full >/dev/null
)

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
