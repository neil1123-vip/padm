#!/bin/sh
set -eu

# 只在 NET_ADMIN 的隔离网络空间运行，不使用宿主网络或发布端口。
entrypoint=${PADM_TEST_ENTRYPOINT:?PADM_TEST_ENTRYPOINT is required}
test_root=$(mktemp -d /tmp/padm-wireguard-real.XXXXXX)
state_root=/var/lib/padm/net
server=
cleanup() {
    [ -z "$server" ] || kill -TERM "$server" 2>/dev/null || true
    [ -z "$server" ] || wait "$server" 2>/dev/null || true
    ip link delete dev wg-padm 2>/dev/null || true
    rm -rf "$test_root"
}
trap cleanup EXIT
fail() { cat "$test_root/service.log" >&2; echo "wireguard-real: $*" >&2; exit 1; }
mkdir -p "$state_root"
chmod 0750 "$state_root"
umask 077
wg genkey >"$test_root/private"
public_key=$(wg pubkey <"$test_root/private")
write_config() {
    {
        printf '[Interface]\nPrivateKey = '
        cat "$test_root/private"
        printf 'Address = %s/30\nListenPort = 51820\nTable = off\n' "$1"
    } >"$test_root/wg-padm.conf"
}
start_server() {
    sh "$entrypoint" wireguard "$test_root/wg-padm.conf" wg-padm >"$test_root/service.log" 2>&1 &
    server=$!
    for attempt in $(seq 1 100); do
        if sh "$entrypoint" wireguard-health wg-padm >/dev/null 2>&1 &&
            cmp -s "$test_root/wg-padm.conf" "$state_root/wireguard/wg-padm.conf"; then
            return 0
        fi
        kill -0 "$server" 2>/dev/null || fail "service exited before readiness"
        sleep 0.05
    done
    fail "service did not become ready"
}
stop_server() {
    kill -TERM "$server"
    wait "$server" || fail "TERM cleanup failed"
    server=
    ! ip link show dev wg-padm >/dev/null 2>&1 || fail "interface survived TERM"
    [ ! -e "$state_root/wireguard.state" ] || fail "state survived TERM"
    [ ! -e "$state_root/wireguard/wg-padm.conf" ] || fail "private snapshot survived TERM"
}

write_config 10.231.0.1
start_server
[ "$(stat -c '%u:%a' "$state_root/wireguard.state")" = 0:600 ] || fail "unsafe marker"
[ "$(stat -c '%u:%a' "$state_root/wireguard/wg-padm.conf")" = 0:600 ] || fail "unsafe snapshot"
[ "$(wg show wg-padm public-key)" = "$public_key" ] || fail "wrong public key"
grep -Eq '^alias=padm-wireguard-[a-f0-9]{32}$' "$state_root/wireguard.state" || fail "missing alias"
stop_server

# 旧式标记和同公钥都不足以证明外部接口属于本项目。
ip link add dev wg-padm type wireguard
wg set wg-padm private-key "$test_root/private"
ip link set dev wg-padm alias outside-owner
printf 'interface=wg-padm\n' >"$state_root/wireguard.state"
if sh "$entrypoint" wireguard "$test_root/wg-padm.conf" wg-padm >"$test_root/service.log" 2>&1; then
    fail "legacy marker accepted an active external interface"
fi
ip -o link show dev wg-padm | grep -q 'alias outside-owner' || fail "external interface changed"
ip link delete dev wg-padm
start_server

# 异常退出后用原快照撤销，再应用新的输入。
kill -KILL "$server"
wait "$server" 2>/dev/null || true
server=
write_config 10.232.0.1
start_server
ip -o address show dev wg-padm | grep -q '10.232.0.1/30' || fail "restart lost new address"
cmp "$test_root/wg-padm.conf" "$state_root/wireguard/wg-padm.conf" || fail "snapshot was not refreshed"
stop_server

# 健康与撤销都拒绝在运行期间被替换的同名接口。
start_server
ip link delete dev wg-padm
ip link add dev wg-padm type wireguard
wg set wg-padm private-key "$test_root/private"
ip link set dev wg-padm alias outside-owner
if sh "$entrypoint" wireguard-health wg-padm >/dev/null 2>&1; then fail "replacement is healthy"; fi
kill -TERM "$server"
if wait "$server"; then fail "replacement cleanup reported success"; fi
server=
ip -o link show dev wg-padm | grep -q 'alias outside-owner' || fail "replacement was deleted"
[ -f "$state_root/wireguard.state" ] || fail "replacement removed recovery evidence"
ip link delete dev wg-padm
start_server
stop_server

# wg-quick 自身失败回滚，不留下接口或本次私有候选。
write_config invalid-address
if sh "$entrypoint" wireguard "$test_root/wg-padm.conf" wg-padm >"$test_root/service.log" 2>&1; then
    fail "invalid address started"
fi
! ip link show dev wg-padm >/dev/null 2>&1 || fail "failed startup left interface"
[ ! -e "$state_root/wireguard/wg-padm.conf" ] || fail "failed startup left private input"
printf 'wireguard-real-regression-ok\n'
