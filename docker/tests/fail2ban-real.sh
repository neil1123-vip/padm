#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
NET_IMAGE=${PADM_TEST_NET_IMAGE:?PADM_TEST_NET_IMAGE must reference an existing net image}
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-real.XXXXXX")
cleanup() {
    if [[ "${PADM_TEST_KEEP:-0}" == 1 ]]; then
        printf 'fail2ban-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

# 只测试隔离网络空间中的 action，不操作宿主 DOCKER-USER。
export DOCKER_BUNDLE_SOURCE_ROOT=${PROJECT_ROOT}
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
mkdir -p "${TEST_ROOT}/config/net/fail2ban" "${TEST_ROOT}/logs/nginx"
jq -n '{
  core: {protocols: [
    {id: 21, public_port: 24444, address_families: ["ipv4"]},
    {id: 21, public_port: 24445, address_families: ["ipv4"]}]},
  host_integrations: [{type: "fail2ban",
    settings: {ports: [24444, 24445], max_retry: 6, find_time: 600, ban_time: 3600}}]
}' >"${TEST_ROOT}/spec.json"
dockerGenerateFail2banConfig "${TEST_ROOT}/spec.json" "${TEST_ROOT}"
grep -qx 'allowipv6 = no' "${TEST_ROOT}/config/net/fail2ban/fail2ban.local"
cp "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" "${TEST_ROOT}/entrypoint.sh"
cp "${TEST_ROOT}/config/net/fail2ban/fail2ban.local" "${TEST_ROOT}/ipv4.local"
jq '.core.protocols[1].address_families += ["ipv6"]' "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/dual.json"
dockerGenerateFail2banConfig "${TEST_ROOT}/dual.json" "${TEST_ROOT}"
grep -qx 'allowipv6 = yes' "${TEST_ROOT}/config/net/fail2ban/fail2ban.local"

MOUNT_ROOT=${TEST_ROOT}
if command -v cygpath >/dev/null 2>&1; then
    MOUNT_ROOT=$(cygpath -m "${TEST_ROOT}")
fi
for family in ipv4 dual; do
    config="${MOUNT_ROOT}/config/net/fail2ban/fail2ban.local"
    [[ "${family}" != ipv4 ]] || config="${MOUNT_ROOT}/ipv4.local"
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker run --rm -i --network none \
        --cap-add NET_ADMIN --security-opt no-new-privileges:true --read-only \
        --tmpfs /run:rw --tmpfs /tmp:rw --tmpfs /var/lib/padm/net:rw \
        -e "PADM_TEST_FAMILY=${family}" \
        --mount "type=bind,source=${MOUNT_ROOT},target=/test,readonly" \
        --mount "type=bind,source=${config},target=/etc/fail2ban/fail2ban.local,readonly" \
        --mount "type=bind,source=${MOUNT_ROOT}/config/net/fail2ban/padm.local,target=/etc/fail2ban/jail.d/padm.local,readonly" \
        --mount "type=bind,source=${MOUNT_ROOT}/config/net/fail2ban/padm-nginx.conf,target=/etc/fail2ban/filter.d/padm-nginx.conf,readonly" \
        --mount "type=bind,source=${MOUNT_ROOT}/config/net/fail2ban/padm-docker-user.conf,target=/etc/fail2ban/action.d/padm-docker-user.conf,readonly" \
        --mount "type=bind,source=${MOUNT_ROOT}/logs/nginx,target=/var/log/padm/nginx,readonly" \
        --entrypoint sh "${NET_IMAGE}" -s <<'EOF'
set -eu
fail() { cat /tmp/fail2ban.log >&2; echo "$*" >&2; exit 1; }
wait_ready() {
    for attempt in $(seq 1 100); do
        fail2ban-client status padm-nginx >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    fail "Fail2ban did not become ready"
}
wait_rule() {
    for attempt in $(seq 1 100); do
        "$1" -w -C padm-f2b -s "$2" -j DROP >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    fail "missing $1 ban for $2"
}
wait_unban() {
    for attempt in $(seq 1 100); do
        if ! "$1" -w -C padm-f2b -s "$2" -j DROP >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    fail "$1 unban left its rule for $2"
}
assert_hooks() {
    for port in 24444 24445; do
        "$1" -w -C DOCKER-USER -p tcp -m conntrack --ctstate NEW \
            --ctorigdstport "$port" -j padm-f2b || fail "missing $1 hook for $port"
    done
}
start_server() {
    sh /test/entrypoint.sh fail2ban 24444,24445 >/tmp/fail2ban.log 2>&1 &
    server=$!
    wait_ready
}
stop_server() {
    kill -TERM "$server"
    wait "$server" || fail "entrypoint failed on TERM"
    for table in iptables ip6tables; do
        if "$table" -w -n -L padm-f2b >/dev/null 2>&1; then
            fail "$table chain survived TERM"
        fi
        for port in 24444 24445; do
            if "$table" -w -C DOCKER-USER -p tcp -m conntrack --ctstate NEW \
                --ctorigdstport "$port" -j padm-f2b >/dev/null 2>&1; then
                fail "$table hook survived TERM"
            fi
        done
    done
    [ ! -e /var/lib/padm/net/fail2ban.state ] || fail "ownership state survived TERM"
}

iptables -w -N DOCKER-USER
fail2ban-client -t
if [ "$PADM_TEST_FAMILY" = dual ]; then
    if sh /test/entrypoint.sh preflight fail2ban 24444,24445 >/tmp/preflight.log 2>&1; then
        echo "dual-stack preflight accepted a missing IPv6 chain" >&2
        exit 1
    fi
    grep -q 'IPv6 DOCKER-USER chain is unavailable' /tmp/preflight.log
    ip6tables -w -N DOCKER-USER
fi
sh /test/entrypoint.sh preflight fail2ban 24444,24445
# 模拟上次异常退出留下的旧端口，确认清理不覆盖本次启动参数。
iptables -w -N padm-f2b
iptables -w -I DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport 23444 -j padm-f2b
printf 'ports=23444\n' >/var/lib/padm/net/fail2ban.state
start_server
grep -qx 'ports=24444,24445' /var/lib/padm/net/fail2ban.state
if iptables -w -C DOCKER-USER -p tcp -m conntrack --ctstate NEW \
    --ctorigdstport 23444 -j padm-f2b >/dev/null 2>&1; then
    fail "stale published port survived startup"
fi
# 第二个 hook 失败时必须撤销第一个 hook 和新链，后续封禁仍可重试。
iptables_command=$(command -v iptables)
mkdir -p /var/lib/padm/net/bin
printf '%s\n' "$iptables_command" >/var/lib/padm/net/iptables-command
cat >/var/lib/padm/net/bin/iptables <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>/var/lib/padm/net/iptables.calls
case " $* " in
*" -I DOCKER-USER "*" --ctorigdstport 24445 "*)
    if [ -f /var/lib/padm/net/reject-second-port ]; then
        rm /var/lib/padm/net/reject-second-port
        touch /var/lib/padm/net/rejected-second-port
        exit 1
    fi
    ;;
esac
exec "$(cat /var/lib/padm/net/iptables-command)" "$@"
SH
fail2ban-client set padm-nginx action padm-docker-user iptables 'sh /var/lib/padm/net/bin/iptables -w'
touch /var/lib/padm/net/reject-second-port
fail2ban-client set padm-nginx banip 192.0.2.9
rolled_back=0
for attempt in $(seq 1 100); do
    if [ -f /var/lib/padm/net/rejected-second-port ] &&
        ! iptables -w -n -L padm-f2b >/dev/null 2>&1; then
        rolled_back=1
        break
    fi
    sleep 0.1
done
if [ "$rolled_back" -ne 1 ]; then
    [ ! -f /var/lib/padm/net/iptables.calls ] || cat /var/lib/padm/net/iptables.calls >&2
    iptables -w -S >&2
    fail "partial actionstart was not rolled back"
fi
fail2ban-client set padm-nginx action padm-docker-user iptables 'iptables -w'
fail2ban-client set padm-nginx banip 192.0.2.7
wait_rule iptables 192.0.2.7
assert_hooks iptables
if [ "$PADM_TEST_FAMILY" = dual ]; then
    fail2ban-client set padm-nginx banip 2001:db8::7
    wait_rule ip6tables 2001:db8::7
    assert_hooks ip6tables
fi
fail2ban-client set padm-nginx unbanip 192.0.2.7
wait_unban iptables 192.0.2.7
fail2ban-client set padm-nginx banip 192.0.2.7
wait_rule iptables 192.0.2.7
stop_server
start_server
wait_rule iptables 192.0.2.7
assert_hooks iptables
if [ "$PADM_TEST_FAMILY" = dual ]; then
    wait_rule ip6tables 2001:db8::7
    assert_hooks ip6tables
    fail2ban-client status padm-nginx >/tmp/jail-status
    grep -Fq '192.0.2.7' /tmp/jail-status || fail "status omitted the IPv4 ban"
    grep -Fq '2001:db8::7' /tmp/jail-status || fail "status omitted the IPv6 ban"
    fail2ban-client set padm-nginx unbanip 2001:db8::7
    wait_unban ip6tables 2001:db8::7
    fail2ban-client status padm-nginx >/tmp/jail-status
    grep -Fq '192.0.2.7' /tmp/jail-status || fail "IPv6 unban changed the IPv4 ban"
    if grep -Fq '2001:db8::7' /tmp/jail-status; then
        fail "status retained the unbanned IPv6 address"
    fi
fi
stop_server
printf 'fail2ban-real-%s-ok\n' "$PADM_TEST_FAMILY"
EOF
done
