#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv &&
    "${DOCKER_HOST:-}" == unix:///n/.tmp-fail2ban-real.*/docker.sock &&
    -S "${DOCKER_HOST#unix://}" ]] || exit 1
TEST_ROOT=$(mktemp -d /n/.tmp-tun-real.XXXXXX)
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_HEALTH_TIMEOUT=30
export PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
cleanup() {
    local status=$? ids defaultNamespace
    ids=$(docker ps -aq --filter label=com.docker.compose.project=padm-docker) || status=1
    if [[ -n "${ids}" ]]; then
        if [[ "${status}" -ne 0 ]]; then
            while IFS= read -r id; do docker logs "${id}" >&2 || true; done <<<"${ids}"
        fi
        docker rm --force --volumes ${ids} >/dev/null || status=1
    fi
    defaultNamespace="${DOCKER_HOST#unix://}"
    defaultNamespace="${defaultNamespace%/docker.sock}/run/netns/default"
    if mountpoint -q "${defaultNamespace}"; then
        [[ "$(findmnt -n -o FSTYPE --target "${defaultNamespace}")" == nsfs &&
            "$(stat -Lc '%i' "${defaultNamespace}")" == "$(stat -Lc '%i' /proc/self/ns/net)" ]] &&
            umount "${defaultNamespace}" || status=1
    fi
    if [[ "${status}" -ne 0 ]]; then
        for path in "${TEST_ROOT}"/*.log "${TEST_ROOT}"/icmp-*-diagnosis.json; do
            if [[ -f "${path}" ]]; then
                printf 'tun-real-evidence: %s\n' "${path}" >&2
                cat -- "${path}" >&2
            fi
        done
        [[ ! -f "${root}/data/net/transparent/tun.state" ]] ||
            cat -- "${root}/data/net/transparent/tun.state" >&2
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'printf "tun-real-fail: line=%s rc=%s\n" "${LINENO}" "$?" >&2' ERR
fail() { printf 'tun-real: %s\n' "$*" >&2; exit 1; }

# host 仅为外层隔离回归容器；生命周期门禁与真实流量均在其中验证。
[[ -c /dev/net/tun ]] || {
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 0600 /dev/net/tun
}
ip link set lo up
mkdir -p "${TEST_ROOT}/net-image" "${TEST_ROOT}/bundle"
cp -- "${PROJECT_ROOT}/docker/images/net/"{entrypoint.sh,tun-resources.py} "${TEST_ROOT}/net-image/"
printf 'FROM %s\nRUN mkdir -p /usr/local/lib/padm && chmod 0755 /usr/local/lib/padm\nCOPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint\nCOPY --chmod=0644 tun-resources.py /usr/local/lib/padm/tun-resources.py\n' \
    "${PADM_TEST_NET_IMAGE:?}" >"${TEST_ROOT}/net-image/Dockerfile"
docker build --pull=false --network none --tag padm-tun-real-net:fixture \
    "${TEST_ROOT}/net-image" >"${TEST_ROOT}/build.log" 2>&1
netImage="padm-tun-real-net:fixture@$(docker image inspect \
    --format '{{.Descriptor.digest}}' padm-tun-real-net:fixture)"
singImage=$(jq -er '."sing-box".reference' /node-images.json)
[[ "$(docker image inspect --format '{{.Id}}' "${singImage}")" == "$(jq -er '."sing-box".image_id' /node-images.json)" ]] ||
    fail 'wrong offline sing-box image'
docker run --rm --network none "${singImage}" version >"${TEST_ROOT}/sing-box-version.log"
cat -- "${TEST_ROOT}/sing-box-version.log"
expectedVersion=$(sed -n 's/^PADM_LOCK_SING_BOX_VERSION=v//p' "${PROJECT_ROOT}/versions.lock")
grep -Fxq "sing-box version ${expectedVersion}" "${TEST_ROOT}/sing-box-version.log" ||
    fail 'TUN test core does not match versions.lock'
docker run --rm --network none --entrypoint sh "${netImage}" \
    -c 'python3 --version; nft --version; ip -V; ls -ld /usr/local/lib/padm; ls -l /usr/local/lib/padm/tun-resources.py'
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
# 核心仅在 trace 记录 ICMP 发包缺权；夹具与基线统一开启，生产模板仍为 warn。
eval "$(declare -f dockerGenerateSingBoxConfig |
    sed '1s/dockerGenerateSingBoxConfig/tunRealGenerateSingBoxConfig/')"
dockerGenerateSingBoxConfig() {
    local rendered
    tunRealGenerateSingBoxConfig "$@" || return 1
    rendered=$(jq '.log.level = "trace"' "$2") || return 1
    printf '%s\n' "${rendered}" >"$2"
}
printf '%040d\n' 1 >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerInitializeStateRoot
mkdir -p "${root}/config/sing-box" "${root}/data/sing-box" "${root}/data/net/transparent"
chmod 0750 "${root}/data/net/transparent"
jq -n --arg sing "${singImage}" --arg net "${netImage}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:1,core:"sing-box",listener_id:"entry-reality",server:"proxy.example.com",public_port:35441,
     address_families:["ipv4"],name:"tun-test",uuid:"11111111-1111-4111-8111-111111111111",
     reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
       private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
       public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
   tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries |
     .["sing-box"]=$sing | .net=$net),
   host_integrations:[{type:"tun",profile:"net-transparent",firewall_rules:["sing-box-auto-redirect"],
     devices:["/dev/net/tun"],schedules:[],settings:{interface:"padm-tun",address:"198.18.0.1/30"}}]}
' >"${root}/config/spec.json"
dockerConfigureSpecValidate "${root}/config/spec.json"
dockerGenerateSingBoxConfig "${root}/config/spec.json" "${TEST_ROOT}/base.json"
dockerTrafficRender sing-box "${TEST_ROOT}/base.json" '{"schema_version":1,"accounts":{}}' \
    >"${root}/config/sing-box/config.json"
dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
dockerTunConfigurationCheck

nft add table inet outside_tun
nft add chain inet outside_tun keep
nft add rule inet outside_tun keep counter comment outside-tun
ip link add outside-tun type dummy
ip link set outside-tun up
ip -4 rule add pref 30110 fwmark 245 table 242 protocol 187
ip -4 route add 198.51.101.0/24 dev lo table 242 proto 187 realm 4321
snapshot() {
    ip -j -d link show | jq -cS 'map(del(.stats,.stats64))'
    ip -j -N -4 route show table all | jq -cS .
    ip -j -N -6 route show table all | jq -cS .
    ip -j -N -4 rule show | jq -cS .
    ip -j -N -6 rule show | jq -cS .
    nft -j -a list ruleset | jq -cS .
}
compareSnapshots() {
    # 报文会推进计数器，复用生产比较语义；原始快照仍保留计数和 handle。
    python3 - "${PROJECT_ROOT}" "$1" "$2" <<'PY'
import json
import pathlib
import runpy
import sys

stable = runpy.run_path(str(pathlib.Path(sys.argv[1]) / "docker/images/net/tun-resources.py"))["stable"]
before, after = [
    [json.loads(line) for line in pathlib.Path(path).read_text().splitlines()]
    for path in sys.argv[2:]
]
assert stable(before) == stable(after), "network resources changed"
for left, right in zip(before[-1]["nftables"], after[-1]["nftables"]):
    if left != right:
        rule = right["rule"]
        print(json.dumps({"snapshot": pathlib.Path(sys.argv[3]).name,
                          "table": rule["table"], "chain": rule["chain"], "handle": rule["handle"],
                          "before": [e["counter"] for e in left["rule"]["expr"] if "counter" in e],
                          "after": [e["counter"] for e in rule["expr"] if "counter" in e]},
                         sort_keys=True))
PY
}
baseline=$(snapshot)
nft add rule inet outside_tun keep queue num 100 bypass
queueBaseline=$(snapshot)
if dockerComposeRun up --no-deps sing-box >"${TEST_ROOT}/queue-conflict.log" 2>&1; then
    fail 'TUN accepted a foreign NFQUEUE 100 consumer'
fi
[[ "$(snapshot)" == "${queueBaseline}" &&
    ! -e "${root}/data/net/transparent/tun.state" ]] ||
    fail 'NFQUEUE rejection changed resources or created ownership'
handle=$(nft -j -a list chain inet outside_tun keep |
    jq -er '.nftables[] | .rule? // empty | select(any(.expr[]; has("queue"))) | .handle')
nft delete rule inet outside_tun keep handle "${handle}"
[[ "$(snapshot)" == "${baseline}" ]] || fail 'queue fixture did not restore the baseline'
dockerComposeRun up --no-deps sing-box >"${TEST_ROOT}/up.log" 2>&1
cid=$(dockerTunContainer running)
stateFile="${root}/data/net/transparent/tun.state"
jq -e --arg cid "${cid}" '.phase == "active" and .cid == $cid' "${stateFile}" >/dev/null
token=$(jq -er .token "${stateFile}")
stateHash=$(sha256sum "${stateFile}")
dockerValidateHostIntegrations "${root}/config/spec.json" "${root}"
[[ "$(sha256sum "${stateFile}")" == "${stateHash}" ]] ||
    fail 'read-only candidate preflight changed the live owner'

# 本测试插入的规则只有恢复后才允许重启，拒绝时容器及归属证据保持原样。
snapshot >"${TEST_ROOT}/drift-before.log"
nft add rule inet sing-box output counter comment tun-real-drift
snapshot >"${TEST_ROOT}/drift-after.log"
drift=$(<"${TEST_ROOT}/drift-after.log")
if compareSnapshots "${TEST_ROOT}/drift-before.log" "${TEST_ROOT}/drift-after.log" \
    >"${TEST_ROOT}/drift-compare.log" 2>&1; then
    fail 'snapshot comparison accepted an added nft rule'
fi
stateHash=$(sha256sum "${stateFile}")
if dockerComposeRun restart --no-deps sing-box >"${TEST_ROOT}/drift.log" 2>&1; then
    fail 'restart accepted foreign nft drift'
fi
[[ "$(snapshot)" == "${drift}" && "$(sha256sum "${stateFile}")" == "${stateHash}" &&
    "$(docker inspect --format '{{.State.Running}}' "${cid}")" == true ]] ||
    fail 'drift rejection changed resources, evidence or core'
handle=$(nft -j -a list chain inet sing-box output |
    jq -er '.nftables[] | .rule? | select(.comment == "tun-real-drift") | .handle')
nft delete rule inet sing-box output handle "${handle}"
dockerComposeRun restart --no-deps sing-box >"${TEST_ROOT}/restart.log" 2>&1
nextCid=$(dockerTunContainer running)
[[ "${nextCid}" != "${cid}" && "$(jq -er .token "${stateFile}")" != "${token}" ]] ||
    fail 'restart reused the previous container or ownership token'
dockerComposeRun down >"${TEST_ROOT}/down.log" 2>&1
[[ ! -e "${stateFile}" && "$(snapshot)" == "${baseline}" ]] ||
    fail 'normal down did not restore the baseline or preserve outside resources'
printf 'docker-tun-compose-ok: bind=verified drift=rejected restart=new-owner off=clean outside=preserved\n'

(
    # 只在外层隔离命名空间构造真实远端，不挂宿主网络或修改生产 sysctl。
    targetServer=
    pingRange=$(</proc/sys/net/ipv4/ping_group_range)
    cleanupIcmp() {
        local status=$?
        printf '%s\n' "${pingRange}" >/proc/sys/net/ipv4/ping_group_range || status=1
        dockerComposeRun down >"${TEST_ROOT}/icmp-clean.log" 2>&1 || status=1
        if [[ "${status}" -ne 0 ]]; then
            printf 'tun-icmp-failure: IPv6 addresses and local routes\n' >&2
            ip -j -6 addr show dev icmp-uplink | jq -c . >&2 || true
            ip -j -N -6 route show table all |
                jq -c 'map(select(.dev == "icmp-uplink" or .dev == "padm-tun"))' >&2 || true
        fi
        if [[ -n "${targetServer}" ]]; then
            kill -TERM "${targetServer}" 2>/dev/null || true
            wait "${targetServer}" 2>/dev/null || true
        fi
        ip link del icmp-uplink || status=1
        ip netns del padm-icmp-target || status=1
        exit "${status}"
    }
    ip netns add padm-icmp-target
    ip link add icmp-uplink type veth peer name icmp-peer
    trap cleanupIcmp EXIT
    ip link set icmp-peer netns padm-icmp-target
    # IPv4 夹具不生成 IPv6 链路地址，避免 DAD 完成后改变已采集的资源基线。
    ip link set icmp-uplink addrgenmode none
    ip netns exec padm-icmp-target ip link set icmp-peer addrgenmode none
    ip addr add 192.0.2.1/30 dev icmp-uplink
    ip link set icmp-uplink up
    ip netns exec padm-icmp-target ip link set lo up
    ip netns exec padm-icmp-target ip addr add 192.0.2.2/30 dev icmp-peer
    ip netns exec padm-icmp-target ip link set icmp-peer up
    ip netns exec padm-icmp-target ip addr add 203.0.113.200/32 dev lo
    ip route add default via 192.0.2.2 dev icmp-uplink
    ip netns exec padm-icmp-target python3 "${PROJECT_ROOT}/docker/tests/tun-icmp-real.py" \
        serve "${TEST_ROOT}/icmp-ready" >"${TEST_ROOT}/icmp-target.log" 2>&1 &
    targetServer=$!
    for attempt in {1..50}; do
        [[ ! -f "${TEST_ROOT}/icmp-ready" ]] || break
        kill -0 "${targetServer}"
        sleep 0.1
    done
    [[ -f "${TEST_ROOT}/icmp-ready" ]] || fail 'ICMP target did not become ready'
    for mode in direct filtered denied; do
        if [[ "${mode}" != denied ]]; then
            printf '0 2147483647\n' >/proc/sys/net/ipv4/ping_group_range
        else
            printf '10001 10001\n' >/proc/sys/net/ipv4/ping_group_range
        fi
        if [[ "${mode}" == filtered ]]; then
            # 权限允许但远端不回应时，不能用本地合成回复冒充 Echo 可达。
            ip netns exec padm-icmp-target nft add table inet icmp_target
            ip netns exec padm-icmp-target nft \
                'add chain inet icmp_target input { type filter hook input priority 0; policy accept; }'
            ip netns exec padm-icmp-target nft add rule inet icmp_target input \
                ip daddr 203.0.113.200 icmp type echo-request counter drop
        fi
        dockerComposeRun up --no-deps sing-box >"${TEST_ROOT}/icmp-${mode}-up.log" 2>&1
        cid=$(dockerTunContainer running)
        diagnosticState=$(sha256sum "${stateFile}")
        snapshot >"${TEST_ROOT}/icmp-${mode}-diagnosis-before.log"
        dockerTunDiagnose "${root}/config/spec.json" "${TEST_ROOT}" \
            >"${TEST_ROOT}/icmp-${mode}-diagnosis.json"
        jq -e --arg mode "${mode}" '.enabled and .runtime == "observed" and .policy == "direct" and
          .uid == 0 and .gid == 0 and .net_raw_effective == false and
          .ping_group_allowed == ($mode != "denied") and
          .socket_probe == "not_tested" and .echo_roundtrip == "not_tested" and
          .capture == "not_verified"' "${TEST_ROOT}/icmp-${mode}-diagnosis.json" >/dev/null ||
            fail 'ICMP diagnosis did not observe the actual core identity'
        snapshot >"${TEST_ROOT}/icmp-${mode}-diagnosis-after.log"
        [[ "$(sha256sum "${stateFile}")" == "${diagnosticState}" ]] ||
            fail 'ICMP diagnosis changed ownership evidence'
        if ! compareSnapshots "${TEST_ROOT}/icmp-${mode}-diagnosis-before.log" \
            "${TEST_ROOT}/icmp-${mode}-diagnosis-after.log"; then
            diff -u "${TEST_ROOT}/icmp-${mode}-diagnosis-before.log" \
                "${TEST_ROOT}/icmp-${mode}-diagnosis-after.log" >&2 || true
            fail 'ICMP diagnosis changed network resources'
        fi
        docker exec --env LD_PRELOAD= "${cid}" sh -c \
            'grep -E "^(Gid|Groups|CapEff):" /proc/1/status' \
            >"${TEST_ROOT}/icmp-${mode}-caps.log"
        python3 - "${TEST_ROOT}/icmp-${mode}-caps.log" <<'PY'
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
assert len(lines) == 3, lines
status = dict(line.split(":", 1) for line in lines)
assert not int(status["CapEff"], 16) & (1 << 13), status
assert int(status["Gid"].split()[1]) == 0 and 10001 not in map(int, status["Groups"].split()), status
PY
        snapshot >"${TEST_ROOT}/icmp-${mode}-traffic-before.log"
        python3 "${PROJECT_ROOT}/docker/tests/tun-icmp-real.py" "${mode}" |
            tee "${TEST_ROOT}/icmp-${mode}.log"
        snapshot >"${TEST_ROOT}/icmp-${mode}-traffic-after.log"
        ! cmp -s "${TEST_ROOT}/icmp-${mode}-traffic-before.log" \
            "${TEST_ROOT}/icmp-${mode}-traffic-after.log" ||
            fail 'live traffic did not update the raw snapshot'
        compareSnapshots "${TEST_ROOT}/icmp-${mode}-traffic-before.log" \
            "${TEST_ROOT}/icmp-${mode}-traffic-after.log"
        printf 'docker-tun-snapshot-control-ok: mode=%s raw=changed resources=unchanged\n' "${mode}"
        if [[ "${mode}" == filtered ]]; then
            ip netns exec padm-icmp-target nft -j list table inet icmp_target \
                >"${TEST_ROOT}/icmp-filtered-target.log"
            jq -e '[.nftables[] | .rule? // empty | .expr[] | .counter? // empty] |
              length == 1 and .[0].packets == 1' "${TEST_ROOT}/icmp-filtered-target.log" >/dev/null ||
                fail 'filtered Echo did not reach the target drop rule exactly once'
            ip netns exec padm-icmp-target nft delete table inet icmp_target
            printf 'docker-tun-icmp-filtered-ok: target-drop=1 echo-replies=0 tcp=ok udp=ok\n'
        fi
        if [[ "${mode}" == denied ]]; then
            docker logs "${cid}" >"${TEST_ROOT}/icmp-denied-core.log" 2>&1
            grep -Eiq 'permission denied|operation not permitted' "${TEST_ROOT}/icmp-denied-core.log" ||
                fail 'denied Echo had no core permission error'
        fi
        dockerComposeRun down >"${TEST_ROOT}/icmp-${mode}-down.log" 2>&1
        [[ ! -e "${stateFile}" ]] || fail 'ICMP scenario left TUN ownership'
    done
)
[[ "$(snapshot)" == "${baseline}" ]] || fail 'ICMP scenarios did not restore the network baseline'
printf 'docker-tun-icmp-real-ok: raw=absent direct=remote filtered=no-reply denied=no-wire tcp=ok udp=ok diagnosis=read-only\n'

# SIGKILL 不等同于核心正常清理，后续 down 必须保留现场供人工核对。
dockerComposeRun up --no-deps sing-box >"${TEST_ROOT}/kill-up.log" 2>&1
cid=$(dockerTunContainer running)
docker kill --signal KILL "${cid}" >/dev/null
stateHash=$(sha256sum "${stateFile}")
killed=$(snapshot)
if dockerComposeRun down >"${TEST_ROOT}/kill-down.log" 2>&1; then
    fail 'down accepted an abnormal core exit'
fi
[[ "$(snapshot)" == "${killed}" && "$(sha256sum "${stateFile}")" == "${stateHash}" &&
    "$(docker inspect --format '{{.State.ExitCode}}' "${cid}")" == 137 ]] ||
    fail 'abnormal exit rejection changed resources, evidence or container'
printf 'docker-tun-real-ok: abnormal-exit=rejected evidence=preserved\n'
