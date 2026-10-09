#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
NET_IMAGE=${PADM_TEST_NET_IMAGE:?PADM_TEST_NET_IMAGE must reference an existing net image}
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv &&
    "${DOCKER_HOST:-}" == unix:///n/.tmp-fail2ban-real.*/docker.sock &&
    -S "${DOCKER_HOST#unix://}" ]] || exit 1
TEST_ROOT=$(mktemp -d /n/.tmp-tproxy-real.XXXXXX)
container=
cleanup() {
    local status=$?
    if [[ -n "${container}" ]]; then
        if [[ "${status}" -ne 0 ]]; then
            docker exec "${container}" cat /tmp/tproxy.log 2>/dev/null || true
            docker exec "${container}" iptables -w -t mangle -S 2>/dev/null || true
            docker exec "${container}" ip -j -N -4 rule show 2>/dev/null || true
            docker exec "${container}" ip -j -N -4 route show table all 2>/dev/null || true
        fi
        docker rm --force --volumes "${container}" >/dev/null || status=1
    fi
    [[ "${PADM_TEST_KEEP:-0}" != 1 ]] || {
        printf 'tproxy-test-root: %s\n' "${TEST_ROOT}" >&2
        return "${status}"
    }
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'tproxy-real: %s\n' "$*" >&2; exit 1; }

# daemon 和所有内核资源均属于外层隔离回归容器，不使用宿主网络或 Socket。
mkdir -p "${TEST_ROOT}/owner"
chmod 0750 "${TEST_ROOT}/owner"
container=$(docker create --network none --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 --security-opt no-new-privileges:true --init --read-only \
    --tmpfs /run:rw,nosuid,nodev,size=16m --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
    --mount "type=bind,source=${TEST_ROOT}/owner,target=/var/lib/padm/net" \
    --mount "type=bind,source=${TEST_ROOT}/owner,target=/run/padm-tproxy-owner,readonly" \
    --mount "type=bind,source=${PROJECT_ROOT}/docker/images/net/entrypoint.sh,target=/tmp/padm-entrypoint,readonly" \
    --entrypoint tail "${NET_IMAGE}" -f /dev/null)
docker start "${container}" >/dev/null
net() { docker exec "${container}" "$@"; }
entry() { net sh /tmp/padm-entrypoint "$@"; }
[[ "$(net sha256sum /tmp/padm-entrypoint | cut -d ' ' -f 1)" == \
    "$(sha256sum "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" | cut -d ' ' -f 1)" ]] ||
    fail 'container did not receive the current entrypoint'
net ip -j link show | jq -e 'map(.ifname) == ["lo"]' >/dev/null
net ip link set lo up

kernelSnapshot() {
    net iptables -w -t mangle -S || return 1
    net ip -j -N -4 rule show | jq -cS . || return 1
    net ip -j -N -4 route show table all | jq -cS . || return 1
}
assertKernel() {
    [[ "$(kernelSnapshot)" == "$1" ]] || fail "$2"
}
rejectEntry() {
    local status=0
    timeout --signal=TERM --kill-after=2 5 docker exec "${container}" \
        sh /tmp/padm-entrypoint "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 && "${status}" -ne 124 && "${status}" -ne 137 ]] ||
        fail "entrypoint did not promptly reject: $*"
}
startServer() {
    port=$1 mark=$2
    net rm -f /tmp/tproxy.pid /tmp/tproxy.status
    docker exec -d "${container}" sh -c '
      sh /tmp/padm-entrypoint tproxy "$1" "$2" </dev/null >/tmp/tproxy.log 2>&1 &
      server=$!
      printf "%s\n" "$server" >/tmp/tproxy.pid
      status=0
      wait "$server" || status=$?
      printf "%s\n" "$status" >/tmp/tproxy.status
    ' test "${port}" "${mark}"
    for ((attempt = 0; attempt < 100; attempt++)); do
        entry tproxy-health "${port}" "${mark}" >/dev/null 2>&1 && return 0
        ! net test -f /tmp/tproxy.status || fail 'service exited before readiness'
        sleep 0.05
    done
    fail 'service did not become healthy'
}
stopServer() {
    local expected=${1:-ok} status
    net sh -c 'kill -TERM "$(cat /tmp/tproxy.pid)"'
    for ((attempt = 0; attempt < 100; attempt++)); do
        if net test -f /tmp/tproxy.status; then
            status=$(net cat /tmp/tproxy.status)
            [[ ( "${expected}" == ok && "${status}" == 0 ) ||
                ( "${expected}" == rejected && "${status}" != 0 ) ]] ||
                fail "TERM returned ${status}, expected ${expected}"
            return 0
        fi
        sleep 0.05
    done
    fail 'service survived TERM'
}
readState() {
    state=$(net cat /var/lib/padm/net/tproxy.state | jq -Rne '
      [inputs | split("=")] as $pairs |
      if ($pairs | map(.[0])) ==
        ["schema_version","token","chain","port","mark","table","pref","route_proto","rule_proto","realm","phase"]
        and all($pairs[]; length == 2)
      then $pairs | map({key:.[0],value:.[1]}) | from_entries
      else error("invalid ownership state") end
    ') || fail 'service did not write the canonical ownership state'
    token=$(jq -er '.token | select(test("^[a-f0-9]{32}$"))' <<<"${state}")
    chain=$(jq -er '.chain' <<<"${state}")
    realm=$(jq -er '.realm' <<<"${state}")
    expected_realm=$((16#${token: -4}))
    (( expected_realm > 0 )) || expected_realm=1
    [[ "${chain}" == "padm-tproxy-${token:0:12}" && "${realm}" == "${expected_realm}" &&
        "$(net stat -c '%u:%a:%h' /var/lib/padm/net/tproxy.state)" == 0:600:1 ]] ||
        fail 'resource identity or state permissions are wrong'
    jq -e --arg port "${port}" --arg mark "${mark}" '
      .schema_version == "2" and .port == $port and .mark == $mark and .table == $mark and
      .pref == "30000" and .route_proto == "186" and .rule_proto == "186" and .phase == "active"
    ' <<<"${state}" >/dev/null || fail 'state did not preserve the active resource identity'
    net ip -j -N -4 route show table "${mark}" | jq -e --arg realm "${realm}" '
      length == 1 and (.[0] | (.type | tostring) == "2" and (.scope | tostring) == "254" and
        .dev == "lo" and (.protocol | tostring) == "186" and (.flow.to | tostring) == $realm)
    ' >/dev/null || fail 'owned route does not carry the recorded protocol and realm'
    net ip -j -N -4 rule show | jq -e --arg mark "${mark}" '
      [ .[] | select(.priority == 30000) ] | length == 1 and
      (.[0] | .src == "all" and (.table | tostring) == $mark and (.protocol | tostring) == "186")
    ' >/dev/null || fail 'owned rule does not carry the recorded preference and protocol'
}

# 独立链、策略规则和路由作为外部资源，正常启停必须逐字保留。
net iptables -w -t mangle -N outside-owner
net iptables -w -t mangle -A outside-owner -m comment --comment outside-owner -j RETURN
net iptables -w -t mangle -A PREROUTING -m comment --comment outside-owner -j outside-owner
net ip -4 rule add pref 30100 fwmark 254 table 240 protocol 187
net ip -4 route add 198.51.100.0/24 dev lo table 240 proto 187 realm 4321
baseline=$(kernelSnapshot)
entry preflight tproxy 31298 129 unowned
assertKernel "${baseline}" 'initial preflight changed external resources'
startServer 31298 129
readState
active=$(kernelSnapshot)
stateBefore=$(net sha256sum /var/lib/padm/net/tproxy.state)
rejectEntry preflight tproxy 31299 131 unowned
entry preflight tproxy 31299 131 owned /run/padm-tproxy-owner
assertKernel "${active}" 'readonly reconfigure preflight changed live resources'
[[ "$(net sha256sum /var/lib/padm/net/tproxy.state)" == "${stateBefore}" ]] ||
    fail 'readonly reconfigure preflight changed ownership state'
if net touch /run/padm-tproxy-owner/write-probe 2>/dev/null; then
    fail 'owner mount is not readonly'
fi
stopServer
! net test -e /var/lib/padm/net/tproxy.state || fail 'state survived successful TERM'
assertKernel "${baseline}" 'TERM changed external chain, rule or route'

# 旧标记不能授予固定同名链的归属。
net iptables -w -t mangle -N padm-tproxy
net sh -c 'umask 077; printf "port=31298\nmark=129\n" >/var/lib/padm/net/tproxy.state'
legacy=$(kernelSnapshot)
stateBefore=$(net sha256sum /var/lib/padm/net/tproxy.state)
rejectEntry tproxy 31298 129
rejectEntry preflight tproxy 31298 129 owned /run/padm-tproxy-owner
assertKernel "${legacy}" 'legacy rejection changed an external fixed chain'
[[ "$(net sha256sum /var/lib/padm/net/tproxy.state)" == "${stateBefore}" ]] ||
    fail 'legacy rejection removed recovery evidence'
net iptables -w -t mangle -X padm-tproxy
net rm /var/lib/padm/net/tproxy.state

# 本步不共享策略表，外部路由插入后拒绝撤销并保留恢复证据。
startServer 31298 129
readState
net ip -4 route add 203.0.113.0/24 dev lo table 129 proto 187 realm 4321
drift=$(kernelSnapshot)
stateBefore=$(net sha256sum /var/lib/padm/net/tproxy.state)
rejectEntry tproxy-health 31298 129
stopServer rejected
assertKernel "${drift}" 'table drift cleanup deleted owned or foreign resources'
[[ "$(net sha256sum /var/lib/padm/net/tproxy.state)" == "${stateBefore}" ]] ||
    fail 'table drift cleanup removed recovery evidence'
net ip -4 route del 203.0.113.0/24 dev lo table 129 proto 187 realm 4321
startServer 31299 131
readState
stopServer
assertKernel "${baseline}" 'reconfigure recovery left old resources or changed external resources'

# 健康检查拒绝缺失 TCP 规则，停止时可清理仍可精确确认归属的剩余资源。
startServer 31298 129
readState
net iptables -w -t mangle -D "${chain}" -p tcp -m comment --comment "padm-tproxy:${token}" \
    -j TPROXY --on-port "${port}" --tproxy-mark "${mark}/0xffffffff"
rejectEntry tproxy-health "${port}" "${mark}"
stopServer
! net test -e /var/lib/padm/net/tproxy.state || fail 'state survived partial resource cleanup'
assertKernel "${baseline}" 'missing TCP rule prevented precise cleanup or changed external resources'
printf 'docker-tproxy-real-ok\n'
