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
docker() { cat >"${TEST_ROOT}/fail2ban-audit.py"; }
dockerFail2banRuntimeAudit aaaaaaaaaaaa
unset -f docker
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
chmod 0755 "${TEST_ROOT}/entrypoint.sh"
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
        --tmpfs /run:rw --tmpfs /tmp:rw --tmpfs /var/lib/padm/net:rw,exec \
        -e "PADM_TEST_FAMILY=${family}" \
        --mount "type=bind,source=${MOUNT_ROOT},target=/test,readonly" \
        --mount "type=bind,source=${MOUNT_ROOT}/entrypoint.sh,target=/usr/local/bin/padm-entrypoint,readonly" \
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
        "$1" -w -C "$chain" -s "$2" -m comment --comment "padm-f2b:$token" -j DROP >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    fail "missing $1 ban for $2"
}
wait_unban() {
    for attempt in $(seq 1 100); do
        if ! "$1" -w -C "$chain" -s "$2" -m comment --comment "padm-f2b:$token" -j DROP >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    fail "$1 unban left its rule for $2"
}
assert_hooks() {
    for port in 24444 24445; do
        "$1" -w -C DOCKER-USER -p tcp -m conntrack --ctstate NEW \
            --ctorigdstport "$port" -m comment --comment "padm-f2b:$token" -j "$chain" ||
            fail "missing $1 hook for $port"
    done
}
start_server() {
    sh /test/entrypoint.sh fail2ban 24444,24445 >/tmp/fail2ban.log 2>&1 &
    server=$!
    wait_ready
    token=$(sed -n 's/^token=//p' /var/lib/padm/net/fail2ban.state)
    chain=$(sed -n 's/^chain=//p' /var/lib/padm/net/fail2ban.state)
    python3 /test/fail2ban-audit.py || fail "canonical loaded actions were rejected"
}
stop_server() {
    cp /var/lib/padm/net/fail2ban.state /tmp/stopped-owner.state
    kill -TERM "$server"
    wait "$server" || fail "entrypoint failed on TERM"
    for table in iptables ip6tables; do
        if "$table" -w -n -L "$chain" >/dev/null 2>&1; then
            fail "$table chain survived TERM"
        fi
        for port in 24444 24445; do
            if "$table" -w -C DOCKER-USER -p tcp -m conntrack --ctstate NEW \
                --ctorigdstport "$port" -m comment --comment "padm-f2b:$token" -j "$chain" >/dev/null 2>&1; then
                fail "$table hook survived TERM"
            fi
        done
    done
    [ ! -e /var/lib/padm/net/fail2ban.state ] || fail "ownership state survived TERM"
    [ -s /var/lib/padm/net/fail2ban.sqlite3 ] || fail "TERM removed the persistent SQLite"
    sqlite_before=$(sha256sum /var/lib/padm/net/fail2ban.sqlite3)
    sh /test/entrypoint.sh preflight fail2ban 24444,24445 unowned ||
        fail "stop cleanup proof rejected an empty owner"
    [ "$(sha256sum /var/lib/padm/net/fail2ban.sqlite3)" = "$sqlite_before" ] ||
        fail "stop cleanup proof changed the persistent SQLite"
}
reject_stop_proof() {
    iptables-save | sed '/^#/d' >/tmp/proof-kernel.before
    ip6tables-save | sed '/^#/d' >>/tmp/proof-kernel.before
    sha256sum /var/lib/padm/net/fail2ban.sqlite3 >/tmp/proof-state.before
    if [ -e /var/lib/padm/net/fail2ban.state ]; then
        sha256sum /var/lib/padm/net/fail2ban.state >>/tmp/proof-state.before
    fi
    if sh /test/entrypoint.sh preflight fail2ban 24444,24445 unowned >/tmp/proof.log 2>&1; then
        fail "stop cleanup proof accepted residual state or kernel resources"
    fi
    iptables-save | sed '/^#/d' >/tmp/proof-kernel.after
    ip6tables-save | sed '/^#/d' >>/tmp/proof-kernel.after
    sha256sum /var/lib/padm/net/fail2ban.sqlite3 >/tmp/proof-state.after
    if [ -e /var/lib/padm/net/fail2ban.state ]; then
        sha256sum /var/lib/padm/net/fail2ban.state >>/tmp/proof-state.after
    fi
    cmp /tmp/proof-kernel.before /tmp/proof-kernel.after ||
        fail "rejected stop cleanup proof changed kernel resources"
    cmp /tmp/proof-state.before /tmp/proof-state.after ||
        fail "rejected stop cleanup proof removed owner evidence or SQLite"
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
# 旧 state 和固定名链没有所有权证据，启动必须拒绝且不修改资源。
iptables -w -N padm-f2b
iptables -w -I DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport 23444 -j padm-f2b
printf 'ports=23444\n' >/var/lib/padm/net/fail2ban.state
chmod 0600 /var/lib/padm/net/fail2ban.state
iptables-save | sed '/^#/d' > /tmp/legacy.before
if sh /test/entrypoint.sh fail2ban 24444,24445 >/tmp/fail2ban.log 2>&1; then
    fail "legacy ownership state was accepted"
fi
iptables-save | sed '/^#/d' > /tmp/legacy.after
cmp /tmp/legacy.before /tmp/legacy.after || fail "legacy refusal changed firewall rules"
grep -qx 'ports=23444' /var/lib/padm/net/fail2ban.state
iptables -w -D DOCKER-USER -p tcp -m conntrack --ctstate NEW --ctorigdstport 23444 -j padm-f2b
iptables -w -X padm-f2b
rm /var/lib/padm/net/fail2ban.state
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
chmod 0700 /var/lib/padm/net/bin/iptables
start_server
grep -qx 'ports=24444,24445' /var/lib/padm/net/fail2ban.state
sh /usr/local/bin/padm-entrypoint fail2ban-action stop "$token" iptables -w
touch /var/lib/padm/net/reject-second-port
if PATH="/var/lib/padm/net/bin:$PATH" sh /usr/local/bin/padm-entrypoint \
    fail2ban-action start "$token" iptables -w >/tmp/injected.log 2>&1; then
    cat /tmp/injected.log >&2
    [ ! -f /var/lib/padm/net/iptables.calls ] || cat /var/lib/padm/net/iptables.calls >&2
    fail "second hook failure was accepted"
fi
rolled_back=0
for attempt in $(seq 1 100); do
    if [ -f /var/lib/padm/net/rejected-second-port ] &&
        ! iptables -w -n -L "$chain" >/dev/null 2>&1; then
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
fail2ban-client set padm-nginx banip 192.0.2.7
wait_rule iptables 192.0.2.7
assert_hooks iptables
if [ "$PADM_TEST_FAMILY" = dual ]; then
    fail2ban-client set padm-nginx banip 2001:db8::7
    wait_rule ip6tables 2001:db8::7
    assert_hooks ip6tables
fi
python3 /test/fail2ban-audit.py || fail "active loaded actions were rejected"
# 内核规则漂移时只读门禁须拒绝，不触碰封禁票据或规则。
iptables -w -I "$chain" 1 -s 192.0.2.99 -j DROP
iptables-save | sed '/^#/d' > /tmp/owner.before
fail2ban-client get padm-nginx banip > /tmp/bans.before
if sh /usr/local/bin/padm-entrypoint fail2ban-health; then
    fail "foreign kernel rule passed the maintenance ownership gate"
fi
iptables-save | sed '/^#/d' > /tmp/owner.after
fail2ban-client get padm-nginx banip > /tmp/bans.after
cmp /tmp/owner.before /tmp/owner.after || fail "owner audit changed firewall rules"
cmp /tmp/bans.before /tmp/bans.after || fail "owner audit changed ban tickets"
iptables -w -D "$chain" -s 192.0.2.99 -j DROP
sh /usr/local/bin/padm-entrypoint fail2ban-health || fail "restored owner was rejected"
# 改写已加载动作但不执行它，审计须拒绝且保留当前封禁。
python3 - <<'PY'
import os
import subprocess
from fail2ban.client.csocket import CSocket

def query(*args):
    with_socket = CSocket("/run/fail2ban/fail2ban.sock")
    try:
        response = with_socket.send(list(args))
    finally:
        with_socket.close()
    if response[0] != 0:
        raise RuntimeError("Fail2ban test query failed")
    return response[1]

def snapshot():
    rules = tuple(tuple(line for line in subprocess.check_output(
        [tool], text=True).splitlines() if not line.startswith("#"))
        for tool in ("iptables-save", "ip6tables-save"))
    return rules + (tuple(sorted(query("get", "padm-nginx", "banip"))),)

def rejected():
    before = snapshot()
    result = subprocess.run(["python3", "/test/fail2ban-audit.py"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode != 0, "loaded action drift was accepted"
    after = snapshot()
    assert after == before, ("read-only audit changed bans or firewall rules", before, after)
    assert not os.path.exists("/tmp/fail2ban-audit-executed"), \
        "audit executed a changed action"

action = "padm-docker-user"
properties = query("get", "padm-nginx", "actionproperties", action)
for name in properties:
    if name.startswith("action") or name in ("iptables", "iptables?family=inet6",
                                            "protocol", "port"):
        original = query("get", "padm-nginx", "action", action, name)
        if not isinstance(original, str):
            continue
        query("set", "padm-nginx", "action", action, name,
              "touch /tmp/fail2ban-audit-executed")
        try:
            rejected()
        finally:
            query("set", "padm-nginx", "action", action, name, original)
query("set", "padm-nginx", "addaction", "foreign")
try:
    rejected()
finally:
    query("set", "padm-nginx", "delaction", "foreign")
original_cache = query("get", "padm-nginx", "action", action, "_properties")
for name, value in (
        ("actionunban", "touch /tmp/fail2ban-audit-executed"),
        ("actionunban?family=inet6", "touch /tmp/fail2ban-audit-executed"),
        ("__families", ["foreign"])):
    poisoned_cache = dict(original_cache)
    poisoned_cache[name] = value
    query("set", "padm-nginx", "action", action, "_CommandAction__properties",
          poisoned_cache)
    try:
        rejected()
    finally:
        query("set", "padm-nginx", "action", action, "_CommandAction__properties",
              original_cache)
assert subprocess.run(["python3", "/test/fail2ban-audit.py"]).returncode == 0, \
    "restored loaded actions were rejected"
PY
fail2ban-client set padm-nginx unbanip 192.0.2.7
wait_unban iptables 192.0.2.7
fail2ban-client set padm-nginx banip 192.0.2.7
wait_rule iptables 192.0.2.7
stop_server
# 停止后的只读证明拒绝残留 state 或链，SQLite 中的真实封禁票据留给恢复启动。
cp /tmp/stopped-owner.state /var/lib/padm/net/fail2ban.state
chmod 0600 /var/lib/padm/net/fail2ban.state
reject_stop_proof
rm /var/lib/padm/net/fail2ban.state
iptables -w -N "$chain"
iptables -w -A "$chain" -m comment --comment "padm-f2b:$token" -j RETURN
reject_stop_proof
iptables -w -D "$chain" -m comment --comment "padm-f2b:$token" -j RETURN
iptables -w -X "$chain"
sh /test/entrypoint.sh preflight fail2ban 24444,24445 unowned
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
