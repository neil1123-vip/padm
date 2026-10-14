#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
NET_IMAGE=${PADM_TEST_NET_IMAGE:?PADM_TEST_NET_IMAGE must reference an existing net image}
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv &&
    "${DOCKER_HOST:-}" == unix:///n/.tmp-fail2ban-real.*/docker.sock &&
    -S "${DOCKER_HOST#unix://}" ]] || exit 1
TEST_ROOT=$(mktemp -d /n/.tmp-tproxy-real.XXXXXX)
container=
coreContainer=
composeContainer=
clientContainer=
targetContainer=
originPid=
replyPid=
networks=()
cleanup() {
    local status=$? defaultNamespace
    for resource in "${originPid}" "${replyPid}"; do
        [[ -z "${resource}" ]] || {
            kill -TERM "${resource}" 2>/dev/null || true
            wait "${resource}" 2>/dev/null || true
        }
    done
    if [[ -n "${coreContainer}" ]]; then
        [[ "${status}" -eq 0 ]] || docker logs "${coreContainer}" >&2 || true
        docker rm --force --volumes "${coreContainer}" >/dev/null || status=1
    fi
    if [[ -n "${composeContainer}" ]]; then
        [[ "${status}" -eq 0 ]] || docker logs "${composeContainer}" >&2 || true
        docker rm --force --volumes "${composeContainer}" >/dev/null || status=1
    fi
    if [[ -n "${container}" ]]; then
        if [[ "${status}" -ne 0 ]]; then
            docker exec "${container}" cat /tmp/tproxy.log 2>/dev/null || true
            docker exec "${container}" iptables-save -c -t mangle 2>/dev/null || true
            docker exec "${container}" ip6tables-save -c -t mangle 2>/dev/null || true
            docker exec "${container}" iptables -w -t mangle -S 2>/dev/null || true
            docker exec "${container}" ip -j -N -4 rule show 2>/dev/null || true
            docker exec "${container}" ip -j -N -4 route show table all 2>/dev/null || true
        fi
        docker rm --force --volumes "${container}" >/dev/null || status=1
    fi
    for resource in "${clientContainer}" "${targetContainer}"; do
        [[ -z "${resource}" ]] || docker rm --force --volumes "${resource}" >/dev/null || status=1
    done
    for resource in "${networks[@]}"; do
        docker network rm "${resource}" >/dev/null || status=1
    done
    # host 服务会留下本次 daemon 的默认 nsfs 句柄；只释放指向当前隔离空间的挂载。
    defaultNamespace="${DOCKER_HOST#unix://}"
    defaultNamespace="${defaultNamespace%/docker.sock}/run/netns/default"
    if mountpoint -q "${defaultNamespace}"; then
        if [[ "$(findmnt -n -o FSTYPE --target "${defaultNamespace}")" == nsfs &&
            "$(stat -Lc '%i' "${defaultNamespace}")" == "$(stat -Lc '%i' /proc/self/ns/net)" ]]; then
            umount "${defaultNamespace}" || status=1
        else
            printf 'tproxy-real: unexpected default namespace mount: %s\n' "${defaultNamespace}" >&2
            status=1
        fi
    fi
    if [[ "${status}" -ne 0 ]]; then
        for resource in "${TEST_ROOT}"/*.log; do
            [[ ! -f "${resource}" ]] || cat -- "${resource}" >&2
        done
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
createRouter() {
    docker create --network "$1" "${@:2}" --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv6.conf.all.forwarding=1 \
    --security-opt no-new-privileges:true --init --read-only \
    --tmpfs /run:rw,nosuid,nodev,size=16m --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
    --mount "type=bind,source=${TEST_ROOT}/owner,target=/var/lib/padm/net" \
    --mount "type=bind,source=${TEST_ROOT}/owner,target=/run/padm-tproxy-owner,readonly" \
    --mount "type=bind,source=${PROJECT_ROOT}/docker/images/net/entrypoint.sh,target=/tmp/padm-entrypoint,readonly" \
    --entrypoint tail "${NET_IMAGE}" -f /dev/null
}
container=$(createRouter none)
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
    net ip6tables -w -t mangle -S || return 1
    net ip -j -N -6 rule show | jq -cS . || return 1
    net ip -j -N -6 route show table all | jq -cS . || return 1
}
assertKernel() {
    local actual
    actual=$(kernelSnapshot) || fail 'cannot inspect kernel baseline'
    if [[ "${actual}" != "$1" ]]; then
        diff -u <(printf '%s\n' "$1") <(printf '%s\n' "${actual}") >&2 || true
        fail "$2"
    fi
}
rejectEntry() {
    local status=0
    timeout --signal=TERM --kill-after=2 5 docker exec "${container}" \
        sh /tmp/padm-entrypoint "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 && "${status}" -ne 124 && "${status}" -ne 137 ]] ||
        fail "entrypoint did not promptly reject: $*"
}
startServer() {
    port=$1 mark=$2 family=${3:-ipv4} outputUid=${4:-}
    local -a runtimeArgs=("${port}" "${mark}" "${family}")
    [[ -z "${outputUid}" ]] || runtimeArgs+=(--output-uid "${outputUid}")
    net rm -f /tmp/tproxy.pid /tmp/tproxy.status
    docker exec -d "${container}" sh -c '
      sh /tmp/padm-entrypoint tproxy "$@" </dev/null >/tmp/tproxy.log 2>&1 &
      server=$!
      printf "%s\n" "$server" >/tmp/tproxy.pid
      status=0
      wait "$server" || status=$?
      printf "%s\n" "$status" >/tmp/tproxy.status
    ' test "${runtimeArgs[@]}"
    for ((attempt = 0; attempt < 100; attempt++)); do
        entry tproxy-health "${runtimeArgs[@]}" >/dev/null 2>&1 && return 0
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
        (["schema_version","token","chain","port","mark","table","pref","route_proto","rule_proto","realm","phase"] +
          if ($pairs[0][1] == "4") then ["family","output_uid"]
          elif ($pairs[0][1] == "3") then ["family"] else [] end)
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
    jq -e --arg port "${port}" --arg mark "${mark}" --arg family "${family}" --arg uid "${outputUid}" '
      .schema_version == (if $uid != "" then "4" elif $family == "ipv4" then "2" else "3" end) and
      (.output_uid // "") == $uid and
      (.family // "ipv4") == $family and .port == $port and .mark == $mark and .table == $mark and
      .pref == "30000" and .route_proto == "186" and .rule_proto == "186" and .phase == "active"
    ' <<<"${state}" >/dev/null || fail 'state did not preserve the active resource identity'
    if [[ "${family}" != ipv6 ]]; then
    net ip -j -N -4 route show table "${mark}" | jq -e --arg realm "${realm}" '
      length == 1 and (.[0] | (.type | tostring) == "2" and (.scope | tostring) == "254" and
        .dev == "lo" and (.protocol | tostring) == "186" and (.flow.to | tostring) == $realm)
    ' >/dev/null || fail 'owned route does not carry the recorded protocol and realm'
    net ip -j -N -4 rule show | jq -e --arg mark "${mark}" '
      [ .[] | select(.priority == 30000) ] | length == 1 and
      (.[0] | .src == "all" and (.table | tostring) == $mark and (.protocol | tostring) == "186")
    ' >/dev/null || fail 'owned rule does not carry the recorded preference and protocol'
    fi
    if [[ "${family}" != ipv4 ]]; then
        net ip -j -N -6 route show table "${mark}" | jq -e --argjson metric "${realm}" '
          length == 1 and (.[0] | (.type | tostring) == "2" and .dev == "lo" and
            (.protocol | tostring) == "186" and .metric == $metric and .pref == "medium")
        ' >/dev/null || fail 'IPv6 route did not preserve ownership metric'
        net ip -j -N -6 rule show | jq -e --arg mark "${mark}" '
          [.[] | select(.priority == 30000)] | length == 1 and
          (.[0] | .src == "all" and (.table | tostring) == $mark and (.protocol | tostring) == "186")
        ' >/dev/null || fail 'IPv6 policy rule has wrong identity'
    fi
}

# 独立链、策略规则和路由作为外部资源，正常启停必须逐字保留。
seedOutsideResources() {
    net iptables -w -t mangle -N outside-owner
    net iptables -w -t mangle -A outside-owner -m comment --comment outside-owner -j RETURN
    net iptables -w -t mangle -A PREROUTING -m comment --comment outside-owner -j outside-owner
    net iptables -w -t mangle -A OUTPUT -m comment --comment outside-owner -j outside-owner
    net ip -4 rule add pref 30100 fwmark 254 table 240 protocol 187
    net ip -4 route add 198.51.100.0/24 dev lo table 240 proto 187 realm 4321
    net ip6tables -w -t mangle -N outside-owner
    net ip6tables -w -t mangle -A outside-owner -m comment --comment outside-owner -j RETURN
    net ip6tables -w -t mangle -A PREROUTING -m comment --comment outside-owner -j outside-owner
    net ip6tables -w -t mangle -A OUTPUT -m comment --comment outside-owner -j outside-owner
    net ip -6 rule add pref 30100 fwmark 254 table 240 protocol 187
    net ip -6 route add fd40::/64 dev lo table 240 proto 187 metric 4321
}
seedOutsideResources
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

# 客户端、透明入口和目标分属独立网络空间；目标必须看到核心新建连接的来源。
for name in xray sing-box; do
    reference=$(jq -er --arg name "${name}" '.[$name].reference' /node-images.json)
    [[ "$(docker image inspect --format '{{.Id}}' "${reference}")" == \
        "$(jq -er --arg name "${name}" '.[$name].image_id' /node-images.json)" ]] ||
        fail "wrong offline ${name} image"
done
for number in 64 65; do
    identity=$(docker network create --internal --subnet "198.18.${number}.0/24" \
        --ipv6 --subnet "fd40:${number}::/64" \
        --opt com.docker.network.bridge.enable_ip_masquerade=false "tproxy-${number}-${TEST_ROOT##*/}")
    networks+=("${identity}")
done
# Docker 不允许将 none 容器接入桥；新空间复用同一 state 挂载并重建外部资源基线。
docker rm --force --volumes "${container}" >/dev/null
container=
container=$(createRouter "${networks[0]}" --ip 198.18.64.10 --ip6 fd40:64::10)
docker start "${container}" >/dev/null
docker network connect --ip 198.18.65.10 --ip6 fd40:65::10 "${networks[1]}" "${container}"
seedOutsideResources
clientContainer=$(docker run -d --network "${networks[0]}" --ip 198.18.64.20 --ip6 fd40:64::20 \
    --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges:true \
    --read-only --entrypoint tail "${NET_IMAGE}" -f /dev/null)
targetContainer=$(docker run -d --network "${networks[1]}" --ip 198.18.65.20 --ip6 fd40:65::20 \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --read-only --entrypoint tail "${NET_IMAGE}" -f /dev/null)
clientPid=$(docker inspect --format '{{.State.Pid}}' "${clientContainer}")
targetPid=$(docker inspect --format '{{.State.Pid}}' "${targetContainer}")
netPid=$(docker inspect --format '{{.State.Pid}}' "${container}")
for resource in "${container}" "${clientContainer}" "${targetContainer}"; do
    for ((attempt = 0; attempt < 100; attempt++)); do
        docker exec "${resource}" ip -j -6 address show | jq -e '
          all(.[].addr_info[]; .tentative != true and .dadfailed != true)
        ' >/dev/null && break
        sleep 0.05
    done
    (( attempt < 100 )) || fail 'IPv6 duplicate-address detection did not finish'
done
docker exec "${clientContainer}" ip route replace default via 198.18.64.10
docker exec "${clientContainer}" ip -6 route replace default via fd40:64::10
net ip route replace default via 198.18.65.1
for scope in default eth0 eth1; do
    nsenter --target "${netPid}" --net -- sysctl -q -w "net.ipv4.conf.${scope}.rp_filter=0"
done
for scope in all lo; do
    nsenter --target "${netPid}" --net -- sysctl -q -w \
        "net.ipv4.conf.${scope}.rp_filter=1" "net.ipv4.conf.${scope}.src_valid_mark=0" \
        "net.ipv4.conf.${scope}.route_localnet=0" "net.ipv4.conf.${scope}.accept_local=0"
done
mkdir "${TEST_ROOT}/proof"
nsenter --target "${targetPid}" --net -- python3 \
    "${PROJECT_ROOT}/docker/tests/tproxy-real-fixture.py" target "${TEST_ROOT}/proof" 18080 18081 53 \
    >"${TEST_ROOT}/origin.log" 2>&1 &
originPid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -f "${TEST_ROOT}/proof/ready" ]] || break
    kill -0 "${originPid}" || fail 'origin exited before readiness'
    sleep 0.05
done
[[ -f "${TEST_ROOT}/proof/ready" ]] || fail 'origin did not become ready'
command -v setpriv >/dev/null || fail 'setpriv is required for real UID OUTPUT acceptance'
chmod 0755 "${TEST_ROOT}"
mkdir "${TEST_ROOT}/replies"
chown 65534:65534 "${TEST_ROOT}/replies"
nsenter --target "${netPid}" --net -- setpriv --reuid 65534 --regid 65534 --clear-groups \
    --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- python3 \
    "${PROJECT_ROOT}/docker/tests/tproxy-real-fixture.py" target "${TEST_ROOT}/replies" 18090 18091 \
    >"${TEST_ROOT}/replies.log" 2>&1 &
replyPid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
    [[ ! -f "${TEST_ROOT}/replies/ready" ]] || break
    kill -0 "${replyPid}" || fail 'selected UID service exited before readiness'
    sleep 0.05
done
[[ -f "${TEST_ROOT}/replies/ready" ]] || fail 'selected UID service did not become ready'
baseline=$(kernelSnapshot)
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
fixture="${PROJECT_ROOT}/docker/tests/tproxy-real-fixture.py"

makeCoreConfig() {
    local core=$1 listenPort=$2 mark=$3 configDir=$4 family=${5:-ipv4} outputUid=${6:-}
    mkdir -p "${configDir}"
    jq -n --arg core "${core}" --argjson port "${listenPort}" --argjson mark "${mark}" \
      --arg family "${family}" --arg uid "${outputUid}" '
      {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
       core:{type:$core,secondary_type:null,protocols:[{
         id:1,core:$core,listener_id:"entry-reality",server:"proxy.example.com",public_port:35441,
         address_families:["ipv4"],name:"tproxy-test",uuid:"11111111-1111-4111-8111-111111111111",
         reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
           private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
           public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
       tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
       images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
         ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
       host_integrations:[{type:"tproxy",profile:"net-transparent",firewall_rules:["padm-tproxy"],
         devices:[],schedules:[],settings:({port:$port,mark:$mark} +
           (if $family == "ipv4" then {} else {family:$family} end) +
           (if $uid == "" then {} else {output_uid:($uid | tonumber)} end))}]}
    ' >"${configDir}/spec.json"
    dockerConfigureSpecValidate "${configDir}/spec.json"
    if [[ "${core}" == xray ]]; then
        dockerGenerateXrayConfig "${configDir}/spec.json" "${configDir}/base.json"
    else
        dockerGenerateSingBoxConfig "${configDir}/spec.json" "${configDir}/base.json"
    fi
    dockerTrafficRender "${core}" "${configDir}/base.json" '{"schema_version":1,"accounts":{}}' \
        >"${configDir}/rendered.json"
    # 只提高测试日志级别，监听与路由保持生成器的实际输出。
    jq --arg core "${core}" '
      if $core == "xray" then .log={loglevel:"debug",access:"/dev/stdout",error:"/dev/stderr"}
      else .log={level:"debug",timestamp:false} end
    ' "${configDir}/rendered.json" >"${configDir}/config.json"
}
startCore() {
    local core=$1 configDir=$2 image
    local -a args
    image=$(jq -er --arg core "${core}" '.[$core].reference' /node-images.json)
    if [[ "${core}" == xray ]]; then
        args=(run -c /etc/padm/tproxy/config.json)
    else
        args=(run -D /var/lib/padm/sing-box -c /etc/padm/tproxy/config.json)
    fi
    coreContainer=$(docker run -d --network "container:${container}" --user 0:0 \
        --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges:true --read-only \
        --tmpfs /tmp:rw,nosuid,nodev,size=16m --tmpfs /var/lib/padm/sing-box:rw,nosuid,nodev,size=16m \
        --mount "type=bind,source=${configDir},target=/etc/padm/tproxy,readonly" "${image}" "${args[@]}")
    for ((attempt = 0; attempt < 100; attempt++)); do
        if net ss -lnt | grep -qE "[[:space:]](0\\.0\\.0\\.0|\\*|\\[::\\]):${port}[[:space:]]"; then
            net ss -lnu | grep -qE "[[:space:]](0\\.0\\.0\\.0|\\*|\\[::\\]):${port}[[:space:]]" && return 0
        fi
        [[ "$(docker inspect --format '{{.State.Running}}' "${coreContainer}")" == true ]] ||
            fail "${core} exited before readiness"
        sleep 0.05
    done
    fail "${core} TProxy sockets did not become ready"
}
stopCore() {
    docker stop --time 5 "${coreContainer}" >/dev/null
    docker logs "${coreContainer}" >"${TEST_ROOT}/${core}-${port}.log" 2>&1
    docker rm --volumes "${coreContainer}" >/dev/null
    coreContainer=
}
trafficCounter() {
    local kind=$1 version=$2 target=$3 tool=iptables-save
    [[ "${version}" != 6 ]] || tool=ip6tables-save
    net "${tool}" -c -t mangle | awk -v comment="padm-tproxy:${token}" -v kind="${kind}" -v target="${target}" '
      index($0, comment) && index($0, "-p " kind " ") && index($0, "-j " target " ") {
        split($1, fields, ":"); sub(/^\[/, "", fields[1]); total += fields[1]
      }
      END { printf "%.0f\n", total }
    '
}
proofRows() {
    [[ ! -f "$1/$2.jsonl" ]] && printf '0\n' || jq -s 'length' "$1/$2.jsonl"
}
assertProof() {
    local kind=$1 directory=$2 before=$3 peer=$4
    jq -se --arg peer "${peer}" --argjson expected "$((before + 1))" --arg kind "${kind}" '
      length == $expected and .[-1].peer == $peer and
      (.[-1].payload | if $kind == "dns" then test("^[0-9a-f]+$")
        else . == ("tproxy-" + $kind + "-request") end)
    ' "${directory}/${kind}.jsonl" >/dev/null || fail "${kind} did not preserve the expected origin proof"
}
forwardCheck() {
    local kind=$1 targetPort=$2 version=${3:-4} before after rows
    local destination=198.18.65.20 peer=198.18.65.10
    if [[ "${version}" == 6 ]]; then destination=fd40:65::20 peer=fd40:65::10; fi
    rows=$(proofRows "${TEST_ROOT}/proof" "${kind}")
    before=$(trafficCounter "${kind}" "${version}" TPROXY)
    nsenter --target "${clientPid}" --net -- python3 "${fixture}" client "${kind}" "${destination}" "${targetPort}"
    after=$(trafficCounter "${kind}" "${version}" TPROXY)
    ((after > before)) || fail "${kind} bypassed TProxy"
    assertProof "${kind}" "${TEST_ROOT}/proof" "${rows}" "${peer}"
}
outputCheck() {
    local kind=$1 targetPort=$2 version=$3 uid=$4 captured=$5 transport=${1}
    local before after markedBefore markedAfter rows destination=198.18.65.20 peer=198.18.65.10
    [[ "${kind}" != dns ]] || transport=udp
    if [[ "${version}" == 6 ]]; then destination=fd40:65::20 peer=fd40:65::10; fi
    rows=$(proofRows "${TEST_ROOT}/proof" "${kind}")
    before=$(trafficCounter "${transport}" "${version}" TPROXY)
    markedBefore=$(trafficCounter "${transport}" "${version}" MARK)
    nsenter --target "${netPid}" --net -- setpriv --reuid "${uid}" --regid "${uid}" --clear-groups \
        --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- \
        python3 "${fixture}" client "${kind}" "${destination}" "${targetPort}"
    after=$(trafficCounter "${transport}" "${version}" TPROXY)
    markedAfter=$(trafficCounter "${transport}" "${version}" MARK)
    if [[ "${captured}" == yes ]]; then
        ((after > before && markedAfter > markedBefore)) || fail "${kind} selected UID bypassed OUTPUT/TProxy"
    else
        [[ "${after}" == "${before}" && "${markedAfter}" == "${markedBefore}" ]] ||
            fail "${kind} unselected/off UID was redirected"
    fi
    assertProof "${kind}" "${TEST_ROOT}/proof" "${rows}" "${peer}"
}
replyCheck() {
    local kind=$1 targetPort=$2 version=$3 scope=$4 before after markedBefore markedAfter rows
    local destination=198.18.64.10 peer=198.18.64.20
    local -a caller=(nsenter --target "${clientPid}" --net --)
    if [[ "${version}" == 6 ]]; then destination=fd40:64::10 peer=fd40:64::20; fi
    if [[ "${scope}" == local ]]; then
        peer=${destination}
        caller=(nsenter --target "${netPid}" --net -- setpriv --reuid 65534 --regid 65534 --clear-groups
            --bounding-set=-all --inh-caps=-all --ambient-caps=-all --)
    fi
    rows=$(proofRows "${TEST_ROOT}/replies" "${kind}")
    before=$(trafficCounter "${kind}" "${version}" TPROXY)
    markedBefore=$(trafficCounter "${kind}" "${version}" MARK)
    "${caller[@]}" python3 "${fixture}" client "${kind}" "${destination}" "${targetPort}"
    after=$(trafficCounter "${kind}" "${version}" TPROXY)
    markedAfter=$(trafficCounter "${kind}" "${version}" MARK)
    [[ "${after}" == "${before}" && "${markedAfter}" == "${markedBefore}" ]] ||
        fail "${kind} ${scope} request or selected UID service reply was redirected"
    assertProof "${kind}" "${TEST_ROOT}/replies" "${rows}" "${peer}"
}

for core in xray sing-box; do
    previousChain=
    previousToken=
    for tuple in '31298 129 ipv4' '31299 131 dual' '31300 132 ipv6'; do
        read -r port mark family <<<"${tuple}"
        configDir="${TEST_ROOT}/${core}-${port}"
        makeCoreConfig "${core}" "${port}" "${mark}" "${configDir}" "${family}" 65534
        startCore "${core}" "${configDir}"
        startServer "${port}" "${mark}" "${family}" 65534
        readState
        [[ -z "${previousToken}" || "${token}" != "${previousToken}" ]] ||
            fail 'parameter change reused previous ownership token'
        if [[ -n "${previousChain}" ]]; then
            ! net iptables -w -t mangle -S "${previousChain}" >/dev/null 2>&1 ||
                fail 'parameter change left previous owned chain'
        fi
        for version in $(case "${family}" in ipv4) echo 4 ;; ipv6) echo 6 ;; dual) echo '4 6' ;; esac); do
            outputCheck tcp 18080 "${version}" 65533 no
            outputCheck udp 18081 "${version}" 65533 no
            replyCheck tcp 18090 "${version}" local
            replyCheck udp 18091 "${version}" local
            replyCheck tcp 18090 "${version}" reply
            replyCheck udp 18091 "${version}" reply
            forwardCheck tcp 18080 "${version}"
            forwardCheck udp 18081 "${version}"
            outputCheck tcp 18080 "${version}" 65534 yes
            outputCheck udp 18081 "${version}" 65534 yes
            outputCheck dns 53 "${version}" 65534 yes
        done
        previousChain=${chain} previousToken=${token}
        stopServer
        ! net test -e /var/lib/padm/net/tproxy.state || fail 'off left ownership state'
        assertKernel "${baseline}" 'off changed outside resources or left old rules/routes'
        for version in $(case "${family}" in ipv4) echo 4 ;; ipv6) echo 6 ;; dual) echo '4 6' ;; esac); do
            outputCheck tcp 18080 "${version}" 65534 no
            outputCheck udp 18081 "${version}" 65534 no
        done
        stopCore
        grep -q 'tproxy-in' "${TEST_ROOT}/${core}-${port}.log" || fail 'missing TProxy core log'
        for destination in $(case "${family}" in ipv4) echo 198.18.65.20 ;; ipv6) echo fd40:65::20 ;; dual) echo '198.18.65.20 fd40:65::20' ;; esac); do
            grep -q "${destination}.*:18080" "${TEST_ROOT}/${core}-${port}.log" &&
                grep -q "${destination}.*:18081" "${TEST_ROOT}/${core}-${port}.log" &&
                grep -q "${destination}.*:53" "${TEST_ROOT}/${core}-${port}.log" ||
                fail "${core} did not record TCP, UDP and DNS destinations"
        done
        printf 'docker-tproxy-forwarding-ok: core=%s port=%s mark=%s family=%s prerouting=ok output_uid=65534 tcp=ok udp=ok dns=ok unselected=direct local=bypass reply=direct off=clean\n' \
            "${core}" "${port}" "${mark}" "${family}"
    done
done

# 真实 Compose 元数据必须通过生产归属校验；host 仅指向外层隔离回归网络空间。
metadataImage=${NET_IMAGE}
imageHash=$(docker run --rm --network none --entrypoint sha256sum "${metadataImage}" \
    /usr/local/bin/padm-entrypoint | cut -d ' ' -f 1)
if [[ "${imageHash}" != "$(sha256sum "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" | cut -d ' ' -f 1)" ]]; then
    mkdir "${TEST_ROOT}/metadata-image"
    cp -- "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" "${TEST_ROOT}/metadata-image/entrypoint.sh"
    printf 'FROM %s\nCOPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint\n' "${NET_IMAGE}" \
        >"${TEST_ROOT}/metadata-image/Dockerfile"
    docker build --pull=false --network none --tag padm-tproxy-real-net:fixture \
        "${TEST_ROOT}/metadata-image" >"${TEST_ROOT}/metadata-build.log" 2>&1
    metadataImage="padm-tproxy-real-net:fixture@$(docker image inspect \
        --format '{{.Descriptor.digest}}' padm-tproxy-real-net:fixture)"
    docker image inspect "${metadataImage}" >/dev/null
fi
root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config" "${root}/data/net/transparent" "${TEST_ROOT}/metadata-bundle"
chmod 0750 "${root}/data/net/transparent"
printf '%040d\n' 1 >"${TEST_ROOT}/metadata-bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/metadata-bundle"; }
jq --arg image "${metadataImage}" '.images.net=$image' "${TEST_ROOT}/xray-31298/spec.json" \
    >"${root}/config/spec.json"
dockerConfigureSpecValidate "${root}/config/spec.json"
dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
: >"${root}/images.env"
dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
dockerTProxyConfigurationCheck
hostSnapshot() {
    iptables -w -t mangle -S
    ip -j -N -4 rule show | jq -cS .
    ip -j -N -4 route show table all | jq -cS .
}
sysctl -q -w net.ipv4.ip_forward=1
iptables -w -t mangle -N tproxy-meta-outside
iptables -w -t mangle -A tproxy-meta-outside -m comment --comment tproxy-meta-outside -j RETURN
iptables -w -t mangle -A PREROUTING -m comment --comment tproxy-meta-outside -j tproxy-meta-outside
iptables -w -t mangle -A OUTPUT -m comment --comment tproxy-meta-outside -j tproxy-meta-outside
ip -4 rule add pref 30110 fwmark 245 table 242 protocol 187
ip -4 route add 198.51.101.0/24 dev lo table 242 proto 187 realm 4321
metadataBaseline=$(hostSnapshot)
docker compose --project-name "${PADM_DOCKER_PROJECT}" --project-directory "${root}" \
    --env-file "${root}/images.env" --file "${root}/compose.json" --profile net-transparent \
    up -d --no-deps --pull never net-transparent >"${TEST_ROOT}/metadata-compose.log" 2>&1
composeContainer=$(docker ps -aq --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
    --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False)
for ((attempt = 0; attempt < 100; attempt++)); do
    metadataCid=$(dockerTProxyContainer running 2>"${TEST_ROOT}/metadata-inspect.log") && break
    [[ "$(docker inspect --format '{{.State.Running}}' "${composeContainer}")" == true ]] ||
        fail 'Compose TProxy exited before ownership readiness'
    sleep 0.05
done
[[ "${metadataCid:-}" == "${composeContainer}" ]] ||
    fail 'real Compose metadata did not match production ownership helper'
docker container inspect "${composeContainer}" >"${TEST_ROOT}/metadata-inspect.json"
dockerTProxyDisablePrepare <(printf '{"host_integrations":[]}')
! docker container inspect "${composeContainer}" >/dev/null 2>&1 ||
    fail 'production disable did not remove the audited Compose container'
composeContainer=
[[ ! -e "${root}/data/net/transparent/tproxy.state" &&
    "$(hostSnapshot)" == "${metadataBaseline}" ]] ||
    fail 'production disable left state/rules or changed outside resources'
iptables -w -t mangle -D PREROUTING -m comment --comment tproxy-meta-outside -j tproxy-meta-outside
iptables -w -t mangle -D OUTPUT -m comment --comment tproxy-meta-outside -j tproxy-meta-outside
iptables -w -t mangle -F tproxy-meta-outside
iptables -w -t mangle -X tproxy-meta-outside
ip -4 rule del pref 30110 fwmark 245 table 242 protocol 187
ip -4 route del 198.51.101.0/24 dev lo table 242 proto 187 realm 4321
printf 'docker-tproxy-compose-owner-ok: inspect=running disable=clean outside=preserved\n'
printf 'docker-tproxy-real-ok\n'
