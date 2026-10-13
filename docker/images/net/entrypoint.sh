#!/bin/sh
set -eu

STATE_ROOT=/var/lib/padm/net
# 默认入口固定为 WS；其它范围只能由显式内部命令选择。
fb_scope=ws fb_state=fail2ban.state fb_prefix=padm-f2b- fb_stage_prefix=.fail2ban-state fb_target=
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

fail2ban_ports_valid() {
    python3 - "$1" <<'PY'
import sys
ports = sys.argv[1].split(",")
if not (1 <= len(ports) <= 16 and len(set(ports)) == len(ports)
        and all(port.isascii() and port.isdigit() and str(int(port)) == port
                and 1 <= int(port) <= 65535 for port in ports)):
    raise SystemExit(1)
PY
}

fail2ban_control_scope() {
    fb_scope=control fb_state=fail2ban-control.state fb_prefix=padm-f2bc-
    fb_stage_prefix=.fail2ban-control-state fb_target=
}

fail2ban_ssh_scope() {
    fb_scope=ssh fb_state=fail2ban-ssh.state fb_prefix=padm-f2bs-
    fb_stage_prefix=.fail2ban-ssh-state fb_target=
}

fail2ban_ssh_parameters_valid() {
    python3 - "$1" "$2" <<'PY'
import ipaddress
import sys
target, port = sys.argv[1:]
try:
    address = ipaddress.ip_address(target)
    if (str(address) != target or "%" in target or address.is_unspecified
            or address.is_loopback or address.is_link_local or address.is_multicast
            or getattr(address, "ipv4_mapped", None)
            or (address.version == 4 and (int(address) >> 24 == 0 or int(address) >> 24 >= 224))
            or not port.isascii() or not port.isdigit() or str(int(port)) != port
            or not 1 <= int(port) <= 65535):
        raise ValueError("invalid SSH target or port")
except ValueError:
    raise SystemExit(1)
PY
}

fail2ban_ssh_preflight() (
    [ "$#" -ge 2 ] && [ "$#" -le 4 ] || exit 1
    requested_target=$1 requested_ports=$2 ownership=${3:-unowned} ownership_root=${4:-$STATE_ROOT}
    case "$ownership" in owned|unowned) ;; *) exit 1 ;; esac
    fail2ban_ssh_scope
    need python3
    need iptables
    need ip6tables
    fail2ban_ssh_parameters_valid "$requested_target" "$requested_ports" || exit 1
    requested_ipv6=no
    case "$requested_target" in *:*) requested_ipv6=yes ;; esac
    if [ -e "$ownership_root/$fb_state" ] || [ -L "$ownership_root/$fb_state" ]; then
        [ "$ownership" = owned ] && fail2ban_state_read "$ownership_root" &&
            [ "$fb_target" = "$requested_target" ] && [ "$fb_ports" = "$requested_ports" ] &&
            fail2ban_resources audit || exit 1
    else
        fb_root=$ownership_root fb_target=$requested_target fb_ports=$requested_ports fb_ipv6=$requested_ipv6
        fb_token=00000000000000000000000000000000 fb_chain=${fb_prefix}000000000000
        fail2ban_resources empty
    fi
)

fail2ban_ssh_clean() (
    [ "$#" -eq 2 ] || exit 1
    # 与控制面 clean 相同，只证明停止后 state 和规则为空，不负责撤销。
    fail2ban_ssh_preflight "$1" "$2" unowned
)

fail2ban_ssh_configuration_valid() {
    python3 - "$1" "$2" <<'PY'
import configparser
import sys

target, port = sys.argv[1:]
def read(path):
    config = configparser.ConfigParser(interpolation=None)
    with open(path, encoding="ascii") as handle:
        config.read_file(handle)
    return config

try:
    filter_config = read("/etc/fail2ban/filter.d/padm-ssh.conf")
    if (filter_config.defaults() or filter_config.sections() != ["Definition"]
            or dict(filter_config["Definition"]) != {
                "datepattern": "{^LN-BEG}%%Y-%%m-%%d %%H:%%M:%%S[ ]",
                "failregex": "^padm-ssh source=<HOST>$", "ignoreregex": ""}):
        raise ValueError("SSH filter changed")
    server_config = read("/etc/fail2ban/fail2ban.local")
    if (server_config.defaults() or server_config.sections() != ["Definition"]
            or dict(server_config["Definition"]) != {
                "allowipv6": "yes" if ":" in target else "no",
                "logtarget": "STDOUT", "socket": "/run/fail2ban/fail2ban.sock",
                "pidfile": "/run/fail2ban/fail2ban.pid", "dbfile": "None"}):
        raise ValueError("SSH daemon configuration changed")
    jail = read("/etc/fail2ban/jail.d/padm.local")
    defaults = dict(jail.defaults())
    limits = {"maxretry": (1, 20), "findtime": (60, 86400), "bantime": (60, 604800)}
    if (set(defaults) != {"backend", *limits} or defaults["backend"] != "polling"
            or jail.sections() != ["sshd", "sshd-ddos", "padm-sshd"]):
        raise ValueError("SSH jail configuration changed")
    for key, (minimum, maximum) in limits.items():
        value = defaults[key]
        if not value.isascii() or not value.isdigit() or str(int(value)) != value or not minimum <= int(value) <= maximum:
            raise ValueError("SSH jail limits changed")
    for section in ("sshd", "sshd-ddos"):
        if dict(jail[section]) != dict(defaults, enabled="false"):
            raise ValueError("native SSH jail enabled")
    if dict(jail["padm-sshd"]) != dict(defaults, enabled="true", filter="padm-ssh",
            logpath="/run/padm/ssh-collector/auth.log", port=port,
            action=f'padm-ssh-input[port="{port}", protocol=tcp]'):
        raise ValueError("SSH jail source changed")
except (OSError, UnicodeError, configparser.Error, ValueError) as error:
    print(f"padm-net: SSH configuration refused: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

fail2ban_ssh_health() (
    fail2ban_ssh_scope
    need fail2ban-client
    fail2ban_state_read "$STATE_ROOT" &&
        fail2ban_resources guard &&
        fail2ban-client status padm-sshd >/dev/null 2>&1 &&
        fail2ban_resources health
)

fail2ban_control_parameters_valid() {
    python3 - "$1" "$2" <<'PY'
import ipaddress
import sys
target, port = sys.argv[1:]
try:
    address = ipaddress.IPv4Address(target)
    networks = [ipaddress.ip_network(value) for value in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")]
    if (str(address) != target or not any(address in network for network in networks)
            or not port.isascii() or not port.isdigit() or str(int(port)) != port
            or not 1024 <= int(port) <= 65535):
        raise ValueError("invalid control target or port")
except ValueError:
    raise SystemExit(1)
PY
}

fail2ban_control_clean() (
    [ "$#" -eq 2 ] || exit 1
    fail2ban_control_scope
    need python3
    need iptables
    fail2ban_control_parameters_valid "$1" "$2" || exit 1
    # 停服时接口可不存在；这里只读证明本范围的 state 和内核资源为空。
    fb_root=$STATE_ROOT fb_target=$1 fb_ports=$2 fb_ipv6=no
    fb_token=00000000000000000000000000000000 fb_chain=${fb_prefix}000000000000
    fail2ban_resources empty
)

fail2ban_control_precheck() {
    need ip
    fail2ban_control_parameters_valid "$1" "$2" || die "invalid control Fail2ban target or port"
    fb_interface=$(ip -j -d link show dev wg-padm) || die "cannot inspect wg-padm interface"
    printf '%s\n' "$fb_interface" | python3 -c '
import json, sys
links = json.load(sys.stdin)
if not (len(links) == 1 and links[0].get("ifname") == "wg-padm"
        and links[0].get("linkinfo", {}).get("info_kind") == "wireguard"):
    raise SystemExit(1)
' || die "control Fail2ban requires an actual wg-padm WireGuard interface"
    fb_addresses=$(ip -j -4 address show dev wg-padm) || die "cannot inspect wg-padm control address"
    printf '%s\n' "$fb_addresses" | python3 -c '
import json, sys
addresses = json.load(sys.stdin)
if not any(item.get("ifname") == "wg-padm" and any(address.get("family") == "inet"
        and address.get("local") == sys.argv[1] for address in item.get("addr_info", []))
        for item in addresses):
    raise SystemExit(1)
' "$1" || die "control Fail2ban target is not an actual wg-padm address"
    python3 - <<'PY'
import os
import stat
from pathlib import Path
root = Path("/var/log/padm/control")
for parent in (root, *root.parents):
    metadata = parent.lstat()
    if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022
            or (parent == root and (metadata.st_gid != 10001 or stat.S_IMODE(metadata.st_mode) != 0o750))):
        raise SystemExit(1)
for name, uid in (("auth.log", 10001), ("auth.lock", 0), ("source.receipt", 10001)):
    path = root / name
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        opened, current = os.fstat(descriptor), path.lstat()
        if (not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1 or opened.st_uid != uid
                or opened.st_gid != 10001 or stat.S_IMODE(opened.st_mode) != 0o640
                or (opened.st_dev, opened.st_ino) != (current.st_dev, current.st_ino)):
            raise SystemExit(1)
    finally:
        os.close(descriptor)
PY
}

fail2ban_state_text() {
    if [ "$fb_scope" = control ]; then
        printf 'schema_version=1\ntoken=%s\nchain=%s\nports=%s\nipv6=no\ntarget=%s\n' \
            "$fb_token" "$fb_chain" "$fb_ports" "$fb_target"
    elif [ "$fb_scope" = ssh ]; then
        printf 'schema_version=1\ntoken=%s\nchain=%s\nports=%s\nipv6=%s\ntarget=%s\n' \
            "$fb_token" "$fb_chain" "$fb_ports" "$fb_ipv6" "$fb_target"
    else
        printf 'schema_version=2\ntoken=%s\nchain=%s\nports=%s\nipv6=%s\n' \
            "$fb_token" "$fb_chain" "$fb_ports" "$fb_ipv6"
    fi
}

fail2ban_state_read() {
    fb_root=${1:-$STATE_ROOT}
    wireguard_state_directory "$fb_root" &&
        wireguard_private_file "$fb_root/$fb_state" &&
        [ "$(stat -c '%h' "$fb_root/$fb_state")" -eq 1 ] &&
        [ "$(stat -c '%s' "$fb_root/$fb_state")" -le 512 ] || return 1
    fb_token=$(sed -n 's/^token=//p' "$fb_root/$fb_state")
    fb_chain=$(sed -n 's/^chain=//p' "$fb_root/$fb_state")
    fb_ports=$(sed -n 's/^ports=//p' "$fb_root/$fb_state")
    fb_ipv6=$(sed -n 's/^ipv6=//p' "$fb_root/$fb_state")
    if [ "$fb_scope" = control ]; then
        fb_target=$(sed -n 's/^target=//p' "$fb_root/$fb_state")
        [ "$fb_ipv6" = no ] && fail2ban_control_parameters_valid "$fb_target" "$fb_ports" || return 1
    elif [ "$fb_scope" = ssh ]; then
        fb_target=$(sed -n 's/^target=//p' "$fb_root/$fb_state")
        fail2ban_ssh_parameters_valid "$fb_target" "$fb_ports" || return 1
        case "$fb_target:$fb_ipv6" in
        *:*:yes) ;;
        *:no) case "$fb_target" in *:*) return 1 ;; esac ;;
        *) return 1 ;;
        esac
    fi
    printf '%s\n' "$fb_token" | grep -Eq '^[a-f0-9]{32}$' &&
        [ "$fb_chain" = "$fb_prefix$(printf '%s' "$fb_token" | cut -c1-12)" ] &&
        fail2ban_ports_valid "$fb_ports" &&
        { [ "$fb_ipv6" = yes ] || [ "$fb_ipv6" = no ]; } || return 1
    # 固定字节格式拒绝重复字段、额外内容和 NUL，绝不执行 state。
    fail2ban_state_text | cmp -s - "$fb_root/$fb_state"
}

fail2ban_state_write() (
    umask 077
    fb_stage=$(mktemp "$STATE_ROOT/$fb_stage_prefix.XXXXXX") || return 1
    trap 'rm -f "$fb_stage"' EXIT
    fail2ban_state_text >"$fb_stage" && chmod 0600 "$fb_stage" &&
        mv -f "$fb_stage" "$STATE_ROOT/$fb_state"
)

fail2ban_resources() {
    python3 - "$fb_root" "$fb_token" "$fb_chain" "$fb_ports" "$fb_ipv6" "$fb_scope" "$fb_target" "$@" <<'PY'
import ipaddress
import os
import shlex
import stat
import subprocess
import sys
import json
import re
import time

root, token, chain, ports, ipv6, scope, target, operation = sys.argv[1:9]
tool = sys.argv[9] if len(sys.argv) > 9 else ""
address = sys.argv[10] if len(sys.argv) > 10 else ""
ports = ports.split(",")
control, ssh = scope == "control", scope == "ssh"
input_scope = control or ssh
tools = (["ip6tables" if ipv6 == "yes" else "iptables"] if ssh else
         ["iptables"] + (["ip6tables"] if not control and
         (ipv6 == "yes" or (operation == "audit" and tool == "yes")) else []))
prefix = "padm-f2bs" if ssh else "padm-f2bc" if control else "padm-f2b"
parent = "INPUT" if input_scope else "DOCKER-USER"
comment = prefix + ":" + token
state_name = "fail2ban-ssh.state" if ssh else "fail2ban-control.state" if control else "fail2ban.state"
state = (f"schema_version={1 if input_scope else 2}\ntoken={token}\nchain={chain}\n"
         f"ports={','.join(ports)}\nipv6={ipv6}\n" + (f"target={target}\n" if input_scope else "")).encode()
created = set()

def collector_guard():
    directory = "/run/padm/ssh-collector"
    expected = os.environ.get("PADM_SSH_COLLECTOR_TOKEN", "")
    unit = os.environ.get("PADM_SSH_COLLECTOR_UNIT", "")
    expected_target = os.environ.get("PADM_SSH_COLLECTOR_TARGET", "")
    expected_port = os.environ.get("PADM_SSH_COLLECTOR_PORT", "")
    if (not re.fullmatch("[a-f0-9]{32}", expected)
            or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@:-]*\.service", unit)
            or len(unit) > 255 or expected_target != target or expected_port != ",".join(ports)):
        raise ValueError("SSH collector parameters changed")
    path = "/"
    for part in directory.split("/")[1:]:
        path = os.path.join(path, part)
        metadata = os.lstat(path)
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0
                or metadata.st_mode & 0o022):
            raise ValueError("unsafe SSH collector directory")
    if stat.S_IMODE(metadata.st_mode) != 0o700:
        raise ValueError("unsafe SSH collector directory mode")
    if not os.statvfs(directory).f_flag & os.ST_RDONLY:
        raise ValueError("SSH collector guard mount is writable")
    descriptor = os.open(directory + "/guard.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    with os.fdopen(descriptor, "rb") as handle:
        before = os.fstat(handle.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != 0
                or stat.S_IMODE(before.st_mode) != 0o600 or before.st_nlink != 1
                or before.st_size > 4096):
            raise ValueError("unsafe SSH collector guard")
        data = handle.read(4097)
        after = os.fstat(handle.fileno())
    if ((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
            != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
        raise ValueError("SSH collector guard changed while reading")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate SSH collector guard field")
            result[key] = value
        return result
    guard = json.loads(data, object_pairs_hook=unique)
    with open("/proc/sys/kernel/random/boot_id", encoding="ascii") as handle:
        boot = handle.read().strip().replace("-", "")
    if (not isinstance(guard, dict) or set(guard) != {
            "schema", "token", "unit", "target", "port", "boot", "invocation", "monotonic_ns"}
            or type(guard["schema"]) is not int or guard["schema"] != 1
            or guard["token"] != expected or guard["unit"] != unit
            or guard["target"] != target or type(guard["port"]) is not int
            or ports != [str(guard["port"])] or guard["boot"] != boot
            or not re.fullmatch("[a-f0-9]{32}", boot)
            or not isinstance(guard["invocation"], str)
            or not re.fullmatch("[a-f0-9]{32}", guard["invocation"])
            or guard["invocation"] == "0" * 32
            or type(guard["monotonic_ns"]) is not int
            or not 0 <= time.monotonic_ns() - guard["monotonic_ns"] <= 10_000_000_000):
        raise ValueError("SSH collector guard expired or changed")

def hook(port):
    if input_scope:
        mask = "/128" if ssh and ipv6 == "yes" else "/32"
        return ["-d", target + mask, "-p", "tcp", "--dport", port,
                "-m", "conntrack", "--ctstate", "NEW",
                "-m", "comment", "--comment", comment, "-j", chain]
    return ["-p", "tcp", "-m", "conntrack", "--ctstate", "NEW", "--ctorigdstport", port,
            "-m", "comment", "--comment", comment, "-j", chain]

def owner():
    directory = os.lstat(root)
    if not stat.S_ISDIR(directory.st_mode) or directory.st_uid != 0 or directory.st_mode & 0o022:
        raise ValueError("unsafe ownership directory")
    path = os.path.join(root, state_name)
    if operation == "empty":
        if os.path.lexists(path):
            raise ValueError("unexpected ownership state")
        return
    current = os.lstat(path)
    if (not stat.S_ISREG(current.st_mode) or current.st_uid != 0
            or stat.S_IMODE(current.st_mode) != 0o600 or current.st_nlink != 1
            or current.st_size > 512):
        raise ValueError("unsafe ownership state")
    with open(path, "rb") as stream:
        if stream.read() != state:
            raise ValueError("ownership state was replaced")

def command(table, args, write=False):
    if write:
        owner()
    result = subprocess.run([table, "-w", *args], text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "firewall command failed")
    return result.stdout

def audit():
    if ssh and operation in {"start", "ban", "check", "guard"}:
        collector_guard()
    owner()
    snapshots = {}
    if ssh:
        # 两个 INPUT 范围尚无共享 owner 合同；写入前跨地址族拒绝控制面资源。
        for table in ("iptables", "ip6tables"):
            snapshots[table] = command(table, ["-S"])
            for line in snapshots[table].splitlines():
                args = shlex.split(line)
                if any(value == "padm-f2bc" or value.startswith(("padm-f2bc-", "padm-f2bc:"))
                       for value in args):
                    raise ValueError("control INPUT ownership conflicts with SSH")
                if table not in tools and any(
                        value == "padm-f2bs" or value.startswith(("padm-f2bs-", "padm-f2bs:"))
                        for value in args):
                    raise ValueError("SSH resources exist in the wrong address family")
    result = {}
    strict_order = operation != "empty"
    for table in tools:
        empty_table = operation == "empty" or (not ssh and table == "ip6tables" and ipv6 == "no")
        present, sentinel, hooks, bans, contents = False, False, [], [], []
        hook_positions = []
        rule_index = 0
        snapshot = snapshots[table] if ssh else command(table, ["-S"])
        for line in snapshot.splitlines():
            args = shlex.split(line)
            if args == ["-N", chain]:
                present = True
                continue
            if len(args) == 2 and args[0] == "-N" and (
                    args[1] == prefix or args[1].startswith(prefix + "-")):
                raise ValueError("unverified Fail2ban chain")
            if len(args) < 2 or args[0] != "-A":
                continue
            if args[1] == parent:
                rule_index += 1
            own_chain = args[1] == chain
            own_target = any(key in args and args[args.index(key) + 1] == chain
                             for key in ("-j", "-g"))
            own_comment = "--comment" in args and args[args.index("--comment") + 1] == comment
            if not (own_chain or own_target or own_comment):
                continue
            if empty_table or not own_comment:
                raise ValueError("foreign Fail2ban chain reference")
            values, modules = {}, []
            index = 2
            while index < len(args):
                if index + 1 >= len(args):
                    raise ValueError("malformed firewall rule")
                key, value = args[index:index + 2]
                if key == "-m":
                    modules.append(value)
                elif key in values:
                    raise ValueError("duplicate firewall option")
                else:
                    values[key] = value
                index += 2
            base = {"--comment": comment}
            mask = "/128" if ssh and ipv6 == "yes" else "/32"
            if (input_scope and args[1] == parent
                    and sorted(modules) in (["comment", "conntrack"], ["comment", "conntrack", "tcp"])
                    and values.get("--dport") in ports
                    and values == dict(base, **{"-d": target + mask, "-p": "tcp",
                       "--dport": values["--dport"], "--ctstate": "NEW", "-j": chain})):
                port = values["--dport"]
                if port in hooks:
                    raise ValueError("duplicate Fail2ban hook")
                hooks.append(port)
                hook_positions.append(rule_index - 1)
            elif (not input_scope and args[1] == parent and sorted(modules) == ["comment", "conntrack"]
                    and values.get("--ctorigdstport") in ports
                    and values == dict(base, **{"-p": "tcp", "--ctstate": "NEW",
                       "--ctorigdstport": values["--ctorigdstport"], "-j": chain})):
                port = values["--ctorigdstport"]
                if port in hooks:
                    raise ValueError("duplicate Fail2ban hook")
                hooks.append(port)
                hook_positions.append(rule_index - 1)
            elif (own_chain and modules == ["comment"]
                  and values == dict(base, **{"-j": "RETURN"}) and not sentinel):
                sentinel = True
                contents.append("sentinel")
            elif own_chain and modules == ["comment"] and set(values) == {"-s", "--comment", "-j"} and values["-j"] == "DROP":
                network = ipaddress.ip_network(values["-s"])
                if (network.prefixlen != network.max_prefixlen
                        or network.version != (4 if table == "iptables" else 6)
                        or str(network.network_address) in bans):
                    raise ValueError("changed or duplicate Fail2ban ban")
                bans.append(str(network.network_address))
                contents.append("ban")
            else:
                raise ValueError("changed Fail2ban rule")
        if present and not sentinel and table not in created:
            raise ValueError("chain has no verifiable owner")
        if sentinel and contents[-1:] != ["sentinel"]:
            raise ValueError("Fail2ban sentinel order changed")
        if not present and (sentinel or hooks or bans):
            raise ValueError("missing referenced Fail2ban chain")
        if strict_order and present and hooks and table not in created:
            if hooks != list(reversed(ports)) or hook_positions != list(range(len(ports))):
                raise ValueError("Fail2ban hooks are not at the chain head")
        if empty_table and present:
            raise ValueError("Fail2ban chain already exists")
        result[table] = (present, sentinel, hooks, bans)
    if ssh:
        owner()
    return result

def mutate(table, args):
    audit()
    command(table, args, True)

def stop(table):
    present, sentinel, hooks, bans = audit()[table]
    if not present:
        return
    created.add(table)
    for port in hooks:
        mutate(table, ["-D", parent, *hook(port)])
    for ip in bans:
        mutate(table, ["-D", chain, "-s", ip, "-m", "comment", "--comment", comment, "-j", "DROP"])
    if sentinel:
        mutate(table, ["-D", chain, "-m", "comment", "--comment", comment, "-j", "RETURN"])
    try:
        mutate(table, ["-X", chain])
    except Exception:
        # 删除链失败时恢复所有权标记，重试不能依赖无标记空链。
        if audit()[table] == (True, False, [], []):
            mutate(table, ["-A", chain, "-m", "comment", "--comment", comment, "-j", "RETURN"])
        raise
    created.discard(table)

try:
    if operation == "guard":
        if not ssh:
            raise ValueError("collector guard is only valid for SSH")
        collector_guard()
        raise SystemExit(0)
    if operation in {"empty", "audit", "health", "cleanup"}:
        resources = audit()
        if operation == "health" and any((present or input_scope) and (not present or not sentinel or set(hooks) != set(ports))
                for present, sentinel, hooks, _ in resources.values()):
            raise ValueError("incomplete Fail2ban resources")
        if operation == "cleanup":
            for table in tools:
                stop(table)
            if any(present for present, _, _, _ in audit().values()):
                raise ValueError("Fail2ban resources survived cleanup")
    else:
        if tool not in tools or operation not in {"start", "stop", "flush", "check", "ban", "unban"}:
            raise ValueError("invalid Fail2ban action")
        if operation in {"ban", "unban"}:
            ip = ipaddress.ip_address(address)
            if "%" in address or ip.version != (4 if tool == "iptables" else 6):
                raise ValueError("invalid Fail2ban address family")
            address = str(ip)
        elif address:
            raise ValueError("unexpected Fail2ban address")
        present, sentinel, hooks, bans = audit()[tool]
        if operation == "start":
            if not (present and sentinel and set(hooks) == set(ports)):
                stop(tool)
                try:
                    mutate(tool, ["-N", chain])
                    created.add(tool)
                    mutate(tool, ["-A", chain, "-m", "comment", "--comment", comment, "-j", "RETURN"])
                    for port in ports:
                        mutate(tool, ["-I", parent, "1", *hook(port)])
                except Exception:
                    stop(tool)
                    raise
        elif operation == "stop":
            stop(tool)
        elif operation == "flush":
            for ip in bans:
                mutate(tool, ["-D", chain, "-s", ip, "-m", "comment", "--comment", comment, "-j", "DROP"])
        elif not (present and sentinel and set(hooks) == set(ports)):
            raise ValueError("incomplete Fail2ban action resources")
        elif operation == "ban" and address not in bans:
            mutate(tool, ["-I", chain, "1", "-s", address, "-m", "comment", "--comment", comment, "-j", "DROP"])
        elif operation == "unban" and address in bans:
            mutate(tool, ["-D", chain, "-s", address, "-m", "comment", "--comment", comment, "-j", "DROP"])
except Exception as error:
    print(f"padm-net: Fail2ban ownership/action refused: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
}

fail2ban_preflight() (
    if [ "$fb_scope" = control ]; then
        [ "$#" -ge 2 ] && [ "$#" -le 4 ] || die "control Fail2ban preflight requires target and port"
        requested_target=$1 requested_ports=$2
        ownership=${3:-unowned} ownership_root=${4:-$STATE_ROOT}
    else
        requested_ports=$1
        ownership=${2:-unowned}
        ownership_root=${3:-$STATE_ROOT}
    fi
    need fail2ban-client
    need iptables
    need python3
    fail2ban_ports_valid "$requested_ports" || die "invalid Fail2ban port list"
    requested_ipv6=no
    if [ "$fb_scope" = control ]; then
        fail2ban_control_precheck "$requested_target" "$requested_ports" ||
            die "control Fail2ban log or address precheck failed"
        iptables -w -n -L INPUT >/dev/null 2>&1 || die "INPUT chain is unavailable"
        grep -qx 'allowipv6 = no' /etc/fail2ban/fail2ban.local &&
            ! grep -Eq '^allowipv6[[:space:]]*=[[:space:]]*yes' /etc/fail2ban/fail2ban.local ||
            die "control Fail2ban must disable IPv6"
    else
        [ -f /var/log/padm/nginx/access.log ] && [ ! -L /var/log/padm/nginx/access.log ] ||
            die "Nginx access log is missing"
        iptables -w -n -L DOCKER-USER >/dev/null 2>&1 || die "DOCKER-USER chain is unavailable"
        if grep -qx 'allowipv6 = yes' /etc/fail2ban/fail2ban.local; then
            requested_ipv6=yes
            need ip6tables
            ip6tables -w -n -L DOCKER-USER >/dev/null 2>&1 || die "IPv6 DOCKER-USER chain is unavailable"
        fi
    fi
    fail2ban-client -t >/dev/null 2>&1 || die "Fail2ban configuration is invalid"
    if [ -e "$ownership_root/$fb_state" ] || [ -L "$ownership_root/$fb_state" ]; then
        [ "$ownership" = owned ] && fail2ban_state_read "$ownership_root" &&
            fail2ban_resources audit "$requested_ipv6" || die "Fail2ban ownership is unverified; refusing migration"
        # 候选只读核验旧 owner，旧资源只能由运行入口精确撤销。
    else
        fb_root=$ownership_root fb_ports=$requested_ports fb_ipv6=$requested_ipv6
        fb_target=${requested_target:-}
        fb_token=00000000000000000000000000000000 fb_chain=${fb_prefix}000000000000
        fail2ban_resources empty || die "Fail2ban resources are already in use"
    fi
)

fail2ban_cleanup() (
    expected_token=${1:-}
    fail2ban_state_read "$STATE_ROOT" || return 1
    cleanup_token=$fb_token
    { [ -z "$expected_token" ] || [ "$cleanup_token" = "$expected_token" ]; } &&
        fail2ban_resources cleanup || {
        echo "padm-net: Fail2ban ownership changed; keeping resources and recovery state" >&2
        return 1
    }
    fail2ban_state_read "$STATE_ROOT" &&
        [ "$fb_token" = "$cleanup_token" ] &&
        rm -f "$STATE_ROOT/$fb_state"
)

fail2ban_action() (
    [ "$#" -ge 4 ] && [ "$#" -le 5 ] && [ "$4" = -w ] || die "invalid Fail2ban action arguments"
    action=$1 expected_token=$2 table=$3 address=${5:-}
    printf '%s\n' "$expected_token" | grep -Eq '^[a-f0-9]{32}$' &&
        fail2ban_state_read "$STATE_ROOT" && [ "$fb_token" = "$expected_token" ] ||
        die "Fail2ban action owner was replaced"
    fail2ban_resources "$action" "$table" "$address"
)

fail2ban_ssh_watch() {
    ssh_watch_parent=$1 ssh_watch_sleep=
    trap - EXIT INT TERM USR1
    trap '[ -z "$ssh_watch_sleep" ] || { kill -TERM "$ssh_watch_sleep" 2>/dev/null || true; wait "$ssh_watch_sleep" 2>/dev/null || true; }; exit 0' TERM
    while :; do
        sleep 1 &
        ssh_watch_sleep=$!
        wait "$ssh_watch_sleep" || return 1
        ssh_watch_sleep=
        if ! fail2ban_resources guard; then
            echo "padm-net: SSH collector guard failed; stopping current jail" >&2
            # 监督只通知持有 server 子进程的入口，由入口停止并等待当前实例。
            kill -USR1 "$ssh_watch_parent" 2>/dev/null || return 1
            return 0
        fi
    done
}

fail2ban_ssh_watch_stop() {
    [ -n "${ssh_watch:-}" ] || return 0
    kill -TERM "$ssh_watch" 2>/dev/null || true
    wait "$ssh_watch" 2>/dev/null || true
    ssh_watch=
}

fail2ban_run() {
    if [ "$fb_scope" = ssh ]; then
        requested_unit=$1 requested_target=$2 requested_ports=$3
        [ "$requested_unit" = "${PADM_SSH_COLLECTOR_UNIT:-}" ] &&
            [ "$requested_target" = "${PADM_SSH_COLLECTOR_TARGET:-}" ] &&
            [ "$requested_ports" = "${PADM_SSH_COLLECTOR_PORT:-}" ] ||
            die "SSH collector command parameters changed"
        need python3
        need fail2ban-client
        fail2ban_ssh_configuration_valid "$requested_target" "$requested_ports" &&
            fail2ban-client -t >/dev/null 2>&1 || die "SSH jail configuration is invalid"
        fb_root=$STATE_ROOT fb_target=$requested_target fb_ports=$requested_ports
        fb_token=00000000000000000000000000000000 fb_chain=${fb_prefix}000000000000
        case "$requested_target" in *:*) fb_ipv6=yes ;; *) fb_ipv6=no ;; esac
        fail2ban_resources guard || die "SSH collector guard is not ready"
    elif [ "$fb_scope" = control ]; then
        requested_target=$1 requested_ports=$2
    else
        requested_ports=$1
    fi
    ownership=unowned
    [ ! -e "$STATE_ROOT/$fb_state" ] && [ ! -L "$STATE_ROOT/$fb_state" ] || ownership=owned
    if [ "$fb_scope" = ssh ]; then
        fail2ban_ssh_preflight "$requested_target" "$requested_ports" "$ownership"
    elif [ "$fb_scope" = control ]; then
        fail2ban_preflight "$requested_target" "$requested_ports" "$ownership"
    else
        fail2ban_preflight "$requested_ports" "$ownership"
    fi
    wireguard_state_directory "$STATE_ROOT" || die "Fail2ban state directory is unsafe"
    if [ "$ownership" = owned ]; then
        fail2ban_cleanup || die "Fail2ban previous state could not be revoked"
    fi
    fb_root=$STATE_ROOT fb_ports=$requested_ports fb_ipv6=no
    if [ "$fb_scope" = ssh ]; then
        fb_target=$requested_target
        case "$requested_target" in *:*) fb_ipv6=yes ;; esac
    elif [ "$fb_scope" = control ]; then
        fb_target=$requested_target
    else
        grep -qx 'allowipv6 = yes' /etc/fail2ban/fail2ban.local && fb_ipv6=yes
    fi
    fb_token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    [ "${#fb_token}" -eq 32 ] || die "Fail2ban random source failed"
    fb_chain=$fb_prefix$(printf '%s' "$fb_token" | cut -c1-12)
    fail2ban_resources empty || die "Fail2ban resources changed before start"
    run_token=$fb_token
    if [ "$fb_scope" = ssh ]; then
        unset PADM_FAIL2BAN_TOKEN PADM_FAIL2BAN_CONTROL_TOKEN
        PADM_FAIL2BAN_SSH_TOKEN=$run_token
        export PADM_FAIL2BAN_SSH_TOKEN
        fail2ban_resources guard || die "SSH collector guard changed before start"
    elif [ "$fb_scope" = control ]; then
        unset PADM_FAIL2BAN_TOKEN
        PADM_FAIL2BAN_CONTROL_TOKEN=$run_token
        export PADM_FAIL2BAN_CONTROL_TOKEN
    else
        unset PADM_FAIL2BAN_CONTROL_TOKEN
        PADM_FAIL2BAN_TOKEN=$run_token
        export PADM_FAIL2BAN_TOKEN
    fi
    server= stopped=0 ssh_watch=
    trap 'fb_status=$?; trap - EXIT; fail2ban_ssh_watch_stop; if [ -e "$STATE_ROOT/$fb_state" ] || [ -L "$STATE_ROOT/$fb_state" ]; then fail2ban_cleanup "$run_token" || fb_status=1; fi; exit "$fb_status"' EXIT
    trap 'stopped=1; [ -z "$server" ] || { fail2ban-client stop >/dev/null 2>&1 || kill -TERM "$server" >/dev/null 2>&1 || true; }' INT TERM
    if [ "$fb_scope" = ssh ]; then
        trap 'stopped=1; [ -z "$server" ] || { fail2ban-client stop >/dev/null 2>&1 || kill -TERM "$server" >/dev/null 2>&1 || true; }' USR1
    fi
    fail2ban_state_write || die "cannot persist Fail2ban ownership"
    [ "$stopped" -eq 0 ] || return 0
    fail2ban-server -f -x -s /run/fail2ban/fail2ban.sock &
    server=$!
    [ "$stopped" -eq 0 ] || { fail2ban-client stop >/dev/null 2>&1 || kill -TERM "$server" >/dev/null 2>&1 || true; }
    if [ "$fb_scope" = ssh ] && [ "$stopped" -eq 0 ]; then
        fail2ban_ssh_watch "$$" &
        ssh_watch=$!
    fi
    status=0
    wait "$server" || status=$?
    if [ "$stopped" -eq 1 ]; then
        status=0
        wait "$server" 2>/dev/null || status=$?
    fi
    server=
    fail2ban_ssh_watch_stop
    return "$status"
}

fail2ban_health() (
    need fail2ban-client
    fail2ban-client ping >/dev/null 2>&1 &&
        fail2ban_state_read "$STATE_ROOT" && fail2ban_resources health
)

port_hopping_preflight() {
    [ "$#" -eq 3 ] || die "port hopping preflight requires start, end and target port"
    port_hopping_resources preflight "$@"
}

port_hopping_resources() {
    if [ "${1:-}" = run ] || [ "${1:-}" = probe ] || [ "${1:-}" = guarded ]; then
        set -- exec python3 /dev/fd/3 "$STATE_ROOT" "$@"
    else
        set -- python3 /dev/fd/3 "$STATE_ROOT" "$@"
    fi
    "$@" 3<<'PY'
import datetime
import fcntl
import hashlib
import ipaddress
import json
import os
import re
import select
import shlex
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time

root, operation, *parameters = sys.argv[1:]
state_path = os.path.join(root, "port-hopping.state")
keys = ("schema_version", "token", "chain", "start", "end", "target_port", "ipv4", "ipv6", "phase")
state = state_identity = lock = None
cleared, created = set(), set()
stopped = False

def stop(_signum, _frame):
    global stopped
    stopped = True

def port(value):
    if not re.fullmatch(r"[1-9][0-9]{0,4}", value) or int(value) > 65535:
        raise ValueError("invalid or noncanonical UDP port")
    return int(value)

def parameters_valid(start, end, target_port, ipv4=None, ipv6=None):
    first, last, target = map(port, (start, end, target_port))
    if first > last or first <= target <= last:
        raise ValueError("UDP range is reversed or includes its target port")
    for address, version in ((ipv4, 4), (ipv6, 6)):
        if address is None:
            continue
        parsed = ipaddress.ip_address(address)
        if (parsed.version != version or str(parsed) != address or "%" in address
                or parsed.is_unspecified or parsed.is_multicast or parsed.is_loopback
                or parsed.is_link_local or getattr(parsed, "ipv4_mapped", None)):
            raise ValueError("invalid or noncanonical port hopping destination")

def overlaps(value, first, last):
    for item in value.split(","):
        ends = item.split(":")
        if len(ends) not in {1, 2}:
            raise ValueError("unverified NAT port selector")
        low, high = port(ends[0]), port(ends[-1])
        if low > high:
            raise ValueError("reversed NAT port selector")
        if low <= last and high >= first:
            return True
    return False

def nat_conflicts(dump, first, last):
    chains, rules = set(), []
    for line in dump.splitlines():
        args = shlex.split(line)
        if args[:1] == ["-N"] and len(args) == 2:
            chains.add(args[1])
        elif args[:1] == ["-P"] and len(args) == 3:
            chains.add(args[1])
        elif args[:1] == ["-A"] and len(args) >= 4:
            rules.append(args)
        else:
            raise ValueError("unverified NAT listing")
        if any(value.startswith(("padm-hop", "PADM_HOP")) for value in args):
            raise ValueError("unverified existing port hopping owner")
    for args in rules:
        values, index = {}, 2
        while index < len(args):
            key = args[index]
            if key in {"!", "--random", "--random-fully", "--persistent"}:
                index += 1
                continue
            if index + 1 >= len(args) or not key.startswith("-"):
                raise ValueError("unverified NAT rule option")
            if key != "-m":
                if key in values:
                    raise ValueError("duplicate NAT rule option")
                values[key] = args[index + 1]
            index += 2
        target = values.get("-j", values.get("-g"))
        if target in chains or target in {"ACCEPT", "RETURN", "DROP", "REJECT",
                                         "SNAT", "MASQUERADE", "LOG", "NFLOG"}:
            continue
        if target not in {"DNAT", "REDIRECT", "NETMAP"}:
            raise ValueError("unverified NAT target")
        # 地址、接口和来源限制不授予共享范围；仅协议或端口取反会使范围证明失效。
        negated = {args[index + 1] for index, value in enumerate(args[:-1]) if value == "!"}
        if not negated & {"-p", "--protocol", "--dport", "--destination-port", "--dports"}:
            if values.get("-p") in {"tcp", "6"}:
                continue
            selected = [values[key] for key in ("--dport", "--destination-port", "--dports")
                        if key in values]
            if len(selected) == 1 and not overlaps(selected[0], first, last):
                continue
        raise ValueError("UDP range conflicts with existing NAT translation")

def backend():
    for tool in ("iptables", "ip6tables"):
        if "(nf_tables)" not in command([tool, "--version"]):
            raise ValueError("port hopping requires the verified iptables-nft backend")

def preflight(start, end, target_port):
    parameters_valid(start, end, target_port)
    if os.path.lexists(state_path):
        raise ValueError("existing port hopping state requires verified ownership")
    conflicts(start, end)

def conflicts(start, end, owned=False):
    first, last = int(start), int(end)
    # shortcut: 仅核验 iptables-nft 布局，接入其它后端前补齐其冲突与归属合同。
    backend()
    dumps = {tool: command([tool, "-w", "-t", "nat", "-S"])
             for tool in ("iptables", "ip6tables")}
    if owned and not all(all(value) for value in audit(dumps).values()):
        raise ValueError("port hopping conflict check requires complete owned resources")
    for tool in ("iptables", "ip6tables"):
        dump = dumps[tool]
        if owned:
            address = ipv4 if tool == "iptables" else ipv6
            expected = (["-N", chain], *rules(address))
            # 只扣除同一快照中已经精确核验的自有资源，外来正文逐行保留。
            dump = "\n".join(line for line in dump.splitlines() if shlex.split(line) not in expected)
        nat_conflicts(dump, first, last)
    ruleset = json.loads(command(["nft", "-j", "list", "ruleset"]))
    for item in ruleset["nftables"]:
        current = item.get("chain", {})
        if current.get("type") == "nat" and (
                current.get("family") not in {"ip", "ip6"} or
                current.get("table") != "nat" or
                current.get("name") not in {"PREROUTING", "INPUT", "OUTPUT", "POSTROUTING"}):
            raise ValueError("native nft NAT layout has no verified conflict contract")
        rule = item.get("rule", {})
        if rule.get("table") == "nat" and any(
                not isinstance(expression, dict) or len(expression) != 1 or
                not set(expression) <= {"match", "counter", "xt", "jump", "goto", "return",
                                         "accept", "drop", "reject", "log"}
                for expression in rule.get("expr", [])):
            raise ValueError("native nft NAT expression has no verified conflict contract")
    for family in ("ip", "ip6"):
        path = f"/proc/net/{family}_tables_names"
        if os.path.exists(path):
            with open(path, encoding="ascii") as source:
                if "nat" in source.read().splitlines():
                    dump = command([f"{family}tables-legacy-save", "-t", "nat"])
                    if any(line.startswith(("-A ", ":")) for line in dump.splitlines()):
                        raise ValueError("legacy NAT coexistence is unverified")
    for line in command(["ss", "-H", "-u", "-a", "-n"]).splitlines():
        fields = line.split()
        if len(fields) != 5 or ":" not in fields[3]:
            raise ValueError("unverified UDP listener listing")
        bound = port(fields[3].rsplit(":", 1)[1])
        if first <= bound <= last:
            raise ValueError("UDP range conflicts with a host listener")
    if owned and not all(all(value) for value in audit().values()):
        raise ValueError("port hopping resources changed during conflict check")

def identity(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_size,
            metadata.st_mtime_ns, metadata.st_ctime_ns)

def directory():
    metadata = os.lstat(root)
    if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0
            or metadata.st_gid != 0 or metadata.st_mode & 0o022):
        raise ValueError("unsafe port hopping ownership directory")

def private_file(metadata, size):
    if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0
            or metadata.st_gid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600
            or metadata.st_nlink != 1 or metadata.st_size > size):
        raise ValueError("unsafe port hopping ownership file")

def read_state():
    directory()
    descriptor = os.open(state_path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    with os.fdopen(descriptor, "rb") as stream:
        before = os.fstat(stream.fileno())
        private_file(before, 512)
        data = stream.read(513)
        after = os.fstat(stream.fileno())
    current = os.lstat(state_path)
    if identity(before) != identity(after) or identity(after) != identity(current):
        raise ValueError("port hopping ownership changed while reading")
    return data, identity(current)

def owner():
    data, metadata = read_state()
    if data != state or metadata != state_identity:
        raise ValueError("port hopping owner was replaced")
    lock_owner()

def lock_owner():
    directory()
    if lock is not None:
        current = os.lstat(os.path.join(root, ".port-hopping.lock"))
        private_file(current, 0)
        if identity(current) != lock_identity:
            raise ValueError("port hopping lock was replaced")

def acquire_lock():
    global lock, lock_identity
    directory()
    descriptor = os.open(os.path.join(root, ".port-hopping.lock"),
                         os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, 0o600)
    lock = os.fdopen(descriptor, "rb+")
    private_file(os.fstat(lock.fileno()), 0)
    current = os.lstat(os.path.join(root, ".port-hopping.lock"))
    if identity(current) != identity(os.fstat(lock.fileno())):
        raise ValueError("port hopping lock was replaced")
    lock_identity = identity(current)
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

def state_text():
    values = ("1", token, chain, start, end, target_port, ipv4, ipv6, phase)
    return "".join(f"{key}={value}\n" for key, value in zip(keys, values)).encode("ascii")

def load_state(expected_token=None):
    global state, state_identity, token, chain, start, end, target_port, ipv4, ipv6, phase, tools, comment
    data, metadata = read_state()
    lines = data.decode("ascii").splitlines()
    if len(lines) != len(keys) or any(not line.startswith(key + "=") for key, line in zip(keys, lines)):
        raise ValueError("unverified port hopping state format")
    values = [line.split("=", 1)[1] for line in lines]
    schema, token, chain, start, end, target_port, ipv4, ipv6, phase = values
    if (schema != "1" or not re.fullmatch("[a-f0-9]{32}", token)
            or expected_token is not None and token != expected_token
            or chain != "padm-hop-" + token[:12] or phase not in {"intent", "active"}
            or data != state_text()):
        raise ValueError("unverified port hopping state owner")
    parameters_valid(start, end, target_port, ipv4, ipv6)
    state, state_identity = data, metadata
    comment = "padm-hop:" + token
    tools = (("iptables", ipv4), ("ip6tables", ipv6))

def commit_state():
    global state, state_identity
    expected = state_text()
    descriptor, stage = tempfile.mkstemp(prefix=".port-hopping-state.", dir=root)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            private_file(os.fstat(stream.fileno()), 512)
            stream.write(expected)
            stream.flush()
            os.fsync(stream.fileno())
            staged_identity = identity(os.fstat(stream.fileno()))
        if state is None:
            lock_owner()
            if os.path.lexists(state_path):
                raise ValueError("port hopping state appeared before commit")
        else:
            owner()
        os.replace(stage, state_path)
        data, metadata = read_state()
        if data != expected or metadata[:3] != staged_identity[:3]:
            raise ValueError("port hopping committed owner was replaced")
        state, state_identity = data, metadata
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    finally:
        if os.path.lexists(stage):
            os.unlink(stage)

def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=5)
    if result.returncode or result.stderr.strip():
        raise RuntimeError(result.stderr.strip() or "cannot inspect port hopping resources")
    return result.stdout

def rules(address):
    destination = address + ("/32" if ":" not in address else "/128")
    target = f"{address}:{target_port}" if ":" not in address else f"[{address}]:{target_port}"
    selector = start if start == end else f"{start}:{end}"
    base = ["-d", destination, "-p", "udp", "-m", "udp", "--dport", selector,
            "-m", "comment", "--comment", comment]
    return (["-A", "PREROUTING", *base, "-j", chain],
            ["-A", chain, *base, "-j", "DNAT", "--to-destination", target],
            ["-A", chain, "-m", "comment", "--comment", comment, "-j", "RETURN"])

def audit(dumps=None):
    owner()
    result = {}
    for tool, address in tools:
        expected = rules(address)
        present = [False, False, False]
        chain_present, prerouting, order = False, [], []
        chains, policies = set(), set()
        dump = dumps[tool] if dumps is not None else command([tool, "-w", "-t", "nat", "-S"])
        for line in dump.splitlines():
            args = shlex.split(line)
            if args[:1] in (["-P"], ["-N"]):
                if (len(args) != (3 if args[0] == "-P" else 2) or args[1] in chains):
                    raise ValueError("unverified NAT chain listing")
                chains.add(args[1])
                if args[0] == "-P":
                    policies.add(args[1])
                if args == ["-N", chain]:
                    chain_present = True
                    continue
            elif args[:1] == ["-A"] and len(args) >= 4:
                if args[1] == "PREROUTING":
                    prerouting.append(args)
                if (args[1] == chain or chain in args or
                        any(value.startswith(("padm-hop", "PADM_HOP")) for value in args)):
                    if args not in expected:
                        raise ValueError("changed or foreign port hopping rule")
                    which = expected.index(args)
                    if present[which]:
                        raise ValueError("duplicate port hopping rule")
                    present[which] = True
                    if args[1] == chain:
                        order.append(which)
                    continue
            else:
                raise ValueError("unverified NAT rule listing")
            if any(value.startswith(("padm-hop", "PADM_HOP")) for value in args):
                raise ValueError("unverified other port hopping owner")
        if not {"PREROUTING", "INPUT", "OUTPUT", "POSTROUTING"} <= policies:
            raise ValueError("incomplete NAT chain listing")
        if (order != sorted(order) or (present[0] and prerouting[:1] != [expected[0]])
                or (present[0] and not present[1]) or (present[1] and not present[2])
                or (any(present) and not chain_present)):
            raise ValueError("changed port hopping resource order or topology")
        if chain_present and not present[2] and not (tool in cleared | created and not any(present)):
            raise ValueError("empty or unmarked port hopping chain has no verifiable owner")
        result[tool] = (chain_present, *present)
    owner()
    return result

def write(tool, args):
    audit()
    owner()
    command([tool, "-w", "-t", "nat", *args])

def health():
    if phase != "active" or not all(all(value) for value in audit().values()):
        raise ValueError("port hopping is not active with complete dual-stack resources")

def clean():
    global state, state_identity
    for tool, address in tools:
        for index, rule in enumerate(rules(address)):
            if audit()[tool][index + 1]:
                write(tool, ["-D", *rule[1:]])
                if index == 2:
                    cleared.add(tool)
        if audit()[tool][0]:
            try:
                write(tool, ["-X", chain])
            except (OSError, RuntimeError, subprocess.SubprocessError):
                # 当前进程刚删的 sentinel 可补回；跨进程同名空链仍拒绝。
                if audit()[tool][0] and tool in cleared:
                    write(tool, rules(address)[2])
                    cleared.remove(tool)
                raise
        cleared.discard(tool)
        created.discard(tool)
    if any(any(value) for value in audit().values()):
        raise ValueError("port hopping resources remain after cleanup")
    owner()
    os.unlink(state_path)
    state = state_identity = None

def local_addresses(ipv4, ipv6):
    addresses = json.loads(command(["ip", "-j", "address", "show"]))
    local = {item["local"] for interface in addresses for item in interface["addr_info"]}
    if not {ipv4, ipv6} <= local:
        raise ValueError("port hopping destinations are not current local addresses")

def probe_stop(signum, _frame):
    print("padm-net: port hopping probe interrupted", file=sys.stderr)
    sys.exit(128 + signum)

def frame_bytes(eof):
    deadline = time.monotonic() + 20
    data = b""
    while True:
        if operation == "guarded":
            guarded_signal_check()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ValueError("port hopping probe request timed out")
        if not select.select([0], [], [], min(remaining, 0.1) if operation == "guarded"
                             else remaining)[0]:
            continue
        # 中间帧逐字节读，保留下一阶段输入；只读请求仍必须等 EOF。
        chunk = os.read(0, 1)
        if operation == "guarded":
            guarded_signal_check()
        if not chunk:
            if not eof:
                raise ValueError("port hopping guarded input closed before its gate")
            break
        data += chunk
        if len(data) > 4096:
            raise ValueError("port hopping probe request is oversized")
        if not eof and chunk == b"\n":
            break
    return data

def frame_value(data):
    if not data.endswith(b"\n") or data.count(b"\n") != 1 or b"\0" in data or b"\r" in data:
        raise ValueError("port hopping probe requires exactly one LF terminated request")

    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate port hopping probe request key")
            result[key] = value
        return result

    return json.loads(data[:-1].decode("ascii"), object_pairs_hook=unique)

def probe_request(nonce, host, eof=True):
    data = frame_bytes(eof)
    request = frame_value(data)
    expected = {"v", "nonce", "parent_pid", "parent_lock_sha256", "startup_sha256",
                "child_id", "image_id", "target"}
    if (not isinstance(request, dict) or set(request) != expected
            or type(request["v"]) is not int or request["v"] != 1
            or request["nonce"] != nonce or type(request["parent_pid"]) is not int
            or request["parent_pid"] <= 1):
        raise ValueError("unverified port hopping probe request")

    def text(value, pattern):
        return isinstance(value, str) and re.fullmatch(pattern, value) is not None

    for key in ("parent_lock_sha256", "startup_sha256", "child_id"):
        if not text(request[key], r"[a-f0-9]{64}"):
            raise ValueError("invalid port hopping probe identity or digest")
    if not text(request["image_id"], r"sha256:[a-f0-9]{64}"):
        raise ValueError("unverified port hopping probe child")
    target = request["target"]
    expected = {"container_id", "image_id", "started_at", "restart_count", "listener_id",
                "range_start", "range_end", "target_port", "ipv4", "ipv6"}
    if (not isinstance(target, dict) or set(target) != expected
            or not text(target["container_id"], r"[a-f0-9]{64}")
            or not text(target["image_id"], r"sha256:[a-f0-9]{64}")
            or not text(target["started_at"], r"[0-9]{4}-[0-9]{2}-[0-9]{2}T"
                        r"[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,9})?Z")
            or type(target["restart_count"]) is not int or target["restart_count"] < 0
            or not text(target["listener_id"], r"[A-Za-z0-9][A-Za-z0-9_.-]{0,127}")
            or any(type(target[key]) is not int for key in
                   ("range_start", "range_end", "target_port"))
            or [target["range_start"], target["range_end"], target["target_port"],
                target["ipv4"], target["ipv6"]] != [*map(int, parameters[:3]), *parameters[3:]]):
        raise ValueError("unverified port hopping probe target")
    datetime.datetime.strptime(target["started_at"][:19], "%Y-%m-%dT%H:%M:%S")
    return request, hashlib.sha256(data[:-1]).hexdigest()

def probe():
    parameters_valid(*parameters)
    signal.signal(signal.SIGTERM, probe_stop)
    signal.signal(signal.SIGINT, probe_stop)
    local_addresses(*parameters[3:])
    acquire_lock()
    preflight(*parameters[:3])
    lock_owner()
    host = socket.gethostname()
    if not re.fullmatch(r"[a-f0-9]{12}", host):
        raise ValueError("unverified port hopping probe hostname")
    nonce = os.urandom(32).hex()
    print(json.dumps({"v": 1, "phase": "challenge", "nonce": nonce, "host": host},
                     separators=(",", ":")), flush=True)
    request, digest = probe_request(nonce, host)
    preflight(*parameters[:3])
    local_addresses(*parameters[3:])
    lock_owner()
    if os.path.lexists(state_path):
        raise ValueError("port hopping state appeared during probe")
    print(json.dumps({"v": 1, "phase": "ack", "nonce": nonce,
                      "child_id": request["child_id"], "request_sha256": digest},
                     separators=(",", ":")), flush=True)

def install_rules():
    for tool, address in tools:
        if stopped:
            return False
        write(tool, ["-N", chain])
        created.add(tool)
        if stopped:
            return False
        write(tool, rules(address)[2])
        created.remove(tool)
        if stopped:
            return False
        write(tool, ["-I", chain, "1", *rules(address)[1][2:]])
        if stopped:
            return False
        write(tool, ["-I", "PREROUTING", "1", *rules(address)[0][2:]])
    return True

def guarded_stop(signum, _frame):
    global stopped, stop_signal
    stopped, stop_signal = True, signum

def guarded_signal_check():
    if stopped:
        print("padm-net: port hopping guarded interrupted", file=sys.stderr)
        raise SystemExit(128 + stop_signal)

def guarded_gate(phase, action, request, digest):
    guarded_signal_check()
    nonce = os.urandom(32).hex()
    value = {"v": 1, "phase": phase, "nonce": nonce,
             "child_id": request["child_id"], "request_sha256": digest}
    print(json.dumps(value, separators=(",", ":")), flush=True)
    received = frame_value(frame_bytes(False))
    if (not isinstance(received, dict) or type(received.get("v")) is not int
            or received != {**value, "phase": action}):
        raise ValueError("port hopping guarded phase or binding mismatch")
    guarded_signal_check()
    return nonce

def guarded():
    global token, chain, start, end, target_port, ipv4, ipv6, phase, tools, comment, stop_signal
    parameters_valid(*parameters)
    stop_signal = 0
    signal.signal(signal.SIGTERM, guarded_stop)
    signal.signal(signal.SIGINT, guarded_stop)
    local_addresses(*parameters[3:])
    acquire_lock()
    preflight(*parameters[:3])
    lock_owner()
    host = socket.gethostname()
    if not re.fullmatch(r"[a-f0-9]{12}", host):
        raise ValueError("unverified port hopping guarded hostname")
    guarded_signal_check()
    nonce = os.urandom(32).hex()
    print(json.dumps({"v": 1, "phase": "challenge", "nonce": nonce, "host": host},
                     separators=(",", ":")), flush=True)
    request, digest = probe_request(nonce, host, eof=False)
    preflight(*parameters[:3])
    local_addresses(*parameters[3:])
    lock_owner()
    guarded_gate("ready", "write", request, digest)
    # shortcut: 仅验有限子协议，接持续启用前须由同锁父端复验真实启动版本。
    preflight(*parameters[:3])
    local_addresses(*parameters[3:])
    lock_owner()
    guarded_signal_check()
    start, end, target_port, ipv4, ipv6 = parameters
    token = os.urandom(16).hex()
    chain, comment = "padm-hop-" + token[:12], "padm-hop:" + token
    tools = (("iptables", ipv4), ("ip6tables", ipv6))
    phase = "intent"
    try:
        commit_state()
        install_rules()
        guarded_signal_check()
        conflicts(start, end, owned=True)
        local_addresses(ipv4, ipv6)
        owner()
        guarded_gate("written", "finalize", request, digest)
        conflicts(start, end, owned=True)
        local_addresses(ipv4, ipv6)
        owner()
        guarded_signal_check()
        phase = "active"
        commit_state()
        conflicts(start, end, owned=True)
        local_addresses(ipv4, ipv6)
        owner()
        nonce = guarded_gate("active", "close", request, digest)
        if frame_bytes(True):
            raise ValueError("port hopping guarded close contains extra input")
        guarded_signal_check()
    finally:
        # 整条写命令返回并记账后才响应信号；外来冲突不阻断精确自有回收。
        if state is not None:
            clean()
    guarded_signal_check()
    if os.path.lexists(state_path):
        raise ValueError("port hopping guarded state remains after cleanup")
    lock_owner()
    guarded_signal_check()
    print(json.dumps({"v": 1, "phase": "closed", "nonce": nonce,
                      "child_id": request["child_id"], "request_sha256": digest},
                     separators=(",", ":")), flush=True)
    guarded_signal_check()

def run():
    global token, chain, start, end, target_port, ipv4, ipv6, phase, tools, comment
    parameters_valid(*parameters)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    acquire_lock()
    backend()
    if os.path.lexists(state_path):
        load_state()
        if parameters != [start, end, target_port, ipv4, ipv6]:
            raise ValueError("port hopping tuple migration is unverified")
        audit()
        clean()
    if stopped:
        return
    start, end, target_port, ipv4, ipv6 = parameters
    lock_owner()
    preflight(start, end, target_port)
    local_addresses(ipv4, ipv6)
    if stopped:
        return
    token = os.urandom(16).hex()
    chain, comment = "padm-hop-" + token[:12], "padm-hop:" + token
    tools = (("iptables", ipv4), ("ip6tables", ipv6))
    phase = "intent"
    try:
        commit_state()
        if not install_rules():
            return
        conflicts(start, end, owned=True)
        if stopped:
            return
        phase = "active"
        commit_state()
        conflicts(start, end, owned=True)
        while not stopped:
            time.sleep(0.1)
    finally:
        # 信号只置标志；整条命令返回后记账，回收过程不被再次中断。
        if state is not None:
            clean()

try:
    lengths = {"preflight": 3, "run": 5, "probe": 5, "guarded": 5,
               "audit": 1, "health": 1, "clean": 1}
    if operation not in lengths or len(parameters) != lengths[operation]:
        raise ValueError("invalid port hopping operation or parameters")
    if operation == "preflight":
        preflight(*parameters)
    elif operation == "run":
        run()
    elif operation == "probe":
        probe()
    elif operation == "guarded":
        guarded()
    else:
        if not re.fullmatch("[a-f0-9]{32}", parameters[0]):
            raise ValueError("invalid port hopping owner token")
        load_state(parameters[0])
        if operation == "clean":
            acquire_lock()
        backend()
        audit()
        if operation == "health":
            health()
        elif operation == "clean":
            clean()
except (ValueError, KeyError, TypeError, UnicodeError, OSError, RuntimeError, subprocess.SubprocessError) as error:
    print(f"padm-net: port hopping {operation} refused: {error}", file=sys.stderr)
    sys.exit(1)
PY
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
    own_target = any(option in args and args[args.index(option) + 1] == chain
                     for option in ("-j", "-g"))
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
    fail2ban-control) shift; fail2ban_control_scope; fail2ban_preflight "$@" ;;
    fail2ban-ssh) shift; fail2ban_ssh_preflight "$@" ;;
    tun) shift; tun_preflight "$@" ;;
    tproxy) shift; tproxy_preflight "$@" ;;
    port-hopping) shift; port_hopping_preflight "$@" ;;
    *) die "unsupported preflight" ;;
    esac
    ;;
wireguard)
    shift; [ "$#" -eq 2 ] || die "wireguard requires config and interface"; wireguard_run "$@"
    ;;
fail2ban)
    shift; [ "$#" -eq 1 ] || die "fail2ban requires ports"; fail2ban_run "$@"
    ;;
fail2ban-control)
    shift; [ "$#" -eq 2 ] || die "fail2ban-control requires target and port"
    fail2ban_control_scope; fail2ban_run "$@"
    ;;
fail2ban-ssh)
    shift; [ "$#" -eq 3 ] || die "fail2ban-ssh requires unit, target and port"
    fail2ban_ssh_scope; fail2ban_run "$@"
    ;;
tproxy)
    shift; [ "$#" -eq 2 ] || die "tproxy requires port and mark"; tproxy_run "$@"
    ;;
port-hopping)
    shift; [ "$#" -eq 5 ] || die "port hopping requires start, end, target and both addresses"
    port_hopping_resources run "$@"
    ;;
port-hopping-probe)
    shift; [ "$#" -eq 5 ] || die "port hopping probe requires start, end, target and both addresses"
    port_hopping_resources probe "$@"
    ;;
port-hopping-guarded)
    shift; [ "$#" -eq 5 ] || die "port hopping guarded requires start, end, target and both addresses"
    port_hopping_resources guarded "$@"
    ;;
port-hopping-audit|port-hopping-health|port-hopping-clean)
    operation=${1#port-hopping-}
    shift; [ "$#" -eq 1 ] || die "port hopping resources requires owner token"
    port_hopping_resources "$operation" "$1"
    ;;
wireguard-health)
    shift; [ "$#" -eq 1 ] || exit 1; wireguard_health "$@"
    ;;
fail2ban-health)
    fail2ban_health
    ;;
fail2ban-action)
    shift; fail2ban_action "$@"
    ;;
fail2ban-control-health)
    shift; [ "$#" -eq 0 ] || exit 1; fail2ban_control_scope; fail2ban_health
    ;;
fail2ban-control-clean)
    shift; fail2ban_control_clean "$@"
    ;;
fail2ban-control-action)
    shift; fail2ban_control_scope; fail2ban_action "$@"
    ;;
fail2ban-ssh-health)
    shift; [ "$#" -eq 0 ] || exit 1; fail2ban_ssh_health
    ;;
fail2ban-ssh-clean)
    shift; fail2ban_ssh_clean "$@"
    ;;
fail2ban-ssh-action)
    shift; fail2ban_ssh_scope; fail2ban_action "$@"
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
