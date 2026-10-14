#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
NET_IMAGE=${PADM_TEST_NET_IMAGE:?PADM_TEST_NET_IMAGE must reference an existing net image}
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv &&
    "${DOCKER_HOST:-}" == unix:///n/.tmp-fail2ban-real.*/docker.sock &&
    -S "${DOCKER_HOST#unix://}" ]] || exit 1
TEST_ROOT=$(mktemp -d /n/.tmp-redirect-real.XXXXXX)
container=
coreContainer=
composeContainer=
clientContainer=
targetContainer=
originPid=
replyPid=
networks=()
cleanup() {
    local status=$? resource defaultNamespace
    for resource in "${originPid}" "${replyPid}"; do
        [[ -z "${resource}" ]] || {
            kill -TERM "${resource}" 2>/dev/null || true
            wait "${resource}" 2>/dev/null || true
        }
    done
    for resource in "${coreContainer}" "${composeContainer}" "${container}" "${clientContainer}" "${targetContainer}"; do
        [[ -z "${resource}" ]] || {
            [[ "${status}" -eq 0 ]] || docker logs "${resource}" >&2 || true
            docker rm --force --volumes "${resource}" >/dev/null || status=1
        }
    done
    for resource in "${networks[@]}"; do
        docker network rm "${resource}" >/dev/null || status=1
    done
    # 仅释放当前隔离 daemon 留下且指向本次网络空间的默认 nsfs 挂载。
    defaultNamespace="${DOCKER_HOST#unix://}"
    defaultNamespace="${defaultNamespace%/docker.sock}/run/netns/default"
    if mountpoint -q "${defaultNamespace}"; then
        if [[ "$(findmnt -n -o FSTYPE --target "${defaultNamespace}")" == nsfs &&
            "$(stat -Lc '%i' "${defaultNamespace}")" == "$(stat -Lc '%i' /proc/self/ns/net)" ]]; then
            umount "${defaultNamespace}" || status=1
        else
            printf 'redirect-real: unexpected default namespace mount: %s\n' "${defaultNamespace}" >&2
            status=1
        fi
    fi
    if [[ "${status}" -ne 0 ]]; then
        for resource in "${TEST_ROOT}"/*.log; do
            [[ ! -f "${resource}" ]] || cat -- "${resource}" >&2
        done
    fi
    [[ "${PADM_TEST_KEEP:-0}" != 1 ]] || {
        printf 'redirect-test-root: %s\n' "${TEST_ROOT}" >&2
        return "${status}"
    }
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() {
    [[ -z "${container}" ]] || {
        docker exec "${container}" cat /tmp/redirect.log >&2 2>/dev/null || true
        docker exec "${container}" iptables-save -c -t nat >&2 2>/dev/null || true
        docker exec "${container}" ip6tables-save -c -t nat >&2 2>/dev/null || true
    }
    printf 'redirect-real: %s\n' "$*" >&2
    exit 1
}

# 客户端、路由和目标各自隔离；真实流量复用已有 TCP/UDP 夹具。
fixture="${PROJECT_ROOT}/docker/tests/tproxy-real-fixture.py"
for name in xray sing-box; do
    reference=$(jq -er --arg name "${name}" '.[$name].reference' /node-images.json)
    [[ "$(docker image inspect --format '{{.Id}}' "${reference}")" == \
        "$(jq -er --arg name "${name}" '.[$name].image_id' /node-images.json)" ]] ||
        fail "wrong offline ${name} image"
done
for number in 66 67; do
    identity=$(docker network create --internal --subnet "198.18.${number}.0/24" \
        --ipv6 --subnet "fd40:${number}::/64" \
        --opt com.docker.network.bridge.enable_ip_masquerade=false "redirect-${number}-${TEST_ROOT##*/}")
    networks+=("${identity}")
done
mkdir "${TEST_ROOT}/owner"
chmod 0750 "${TEST_ROOT}/owner"
container=$(docker run -d --network "${networks[0]}" --ip 198.18.66.10 --ip6 fd40:66::10 \
    --cap-add NET_ADMIN --sysctl net.ipv4.ip_forward=1 --sysctl net.ipv6.conf.all.forwarding=1 \
    --security-opt no-new-privileges:true --init --read-only \
    --tmpfs /run:rw,nosuid,nodev,size=16m --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m \
    --mount "type=bind,source=${TEST_ROOT}/owner,target=/var/lib/padm/net" \
    --mount "type=bind,source=${PROJECT_ROOT}/docker/images/net/entrypoint.sh,target=/tmp/padm-entrypoint,readonly" \
    --entrypoint tail "${NET_IMAGE}" -f /dev/null)
docker network connect --ip 198.18.67.10 --ip6 fd40:67::10 "${networks[1]}" "${container}"
clientContainer=$(docker run -d --network "${networks[0]}" --ip 198.18.66.20 --ip6 fd40:66::20 \
    --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges:true \
    --read-only --entrypoint tail "${NET_IMAGE}" -f /dev/null)
targetContainer=$(docker run -d --network "${networks[1]}" --ip 198.18.67.20 --ip6 fd40:67::20 \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --read-only --entrypoint tail "${NET_IMAGE}" -f /dev/null)
clientPid=$(docker inspect --format '{{.State.Pid}}' "${clientContainer}")
targetPid=$(docker inspect --format '{{.State.Pid}}' "${targetContainer}")
netPid=$(docker inspect --format '{{.State.Pid}}' "${container}")
net() { docker exec "${container}" "$@"; }
entry() { net sh /tmp/padm-entrypoint "$@"; }
[[ "$(net sha256sum /tmp/padm-entrypoint | cut -d ' ' -f 1)" == \
    "$(sha256sum "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" | cut -d ' ' -f 1)" ]] ||
    fail 'container did not receive the current entrypoint'
for resource in "${container}" "${clientContainer}" "${targetContainer}"; do
    for ((attempt = 0; attempt < 100; attempt++)); do
        docker exec "${resource}" ip -j -6 address show | jq -e '
          all(.[].addr_info[]; .tentative != true and .dadfailed != true)
        ' >/dev/null && break
        sleep 0.05
    done
    (( attempt < 100 )) || fail 'IPv6 duplicate-address detection did not finish'
done
docker exec "${clientContainer}" ip route replace default via 198.18.66.10
docker exec "${clientContainer}" ip -6 route replace default via fd40:66::10
nsenter --target "${targetPid}" --net -- ip route replace 198.18.66.0/24 via 198.18.67.10
nsenter --target "${targetPid}" --net -- ip -6 route replace fd40:66::/64 via fd40:67::10
net ip route replace default via 198.18.67.1
command -v setpriv >/dev/null || fail 'setpriv is required for real UID OUTPUT acceptance'
chmod 0755 "${TEST_ROOT}"
mkdir "${TEST_ROOT}/proof" "${TEST_ROOT}/replies"
chown 65534:65534 "${TEST_ROOT}/replies"
nsenter --target "${targetPid}" --net -- python3 "${fixture}" target "${TEST_ROOT}/proof" 18080 18081 \
    >"${TEST_ROOT}/origin.log" 2>&1 &
originPid=$!
nsenter --target "${netPid}" --net -- setpriv --reuid 65534 --regid 65534 --clear-groups \
    --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- python3 \
    "${fixture}" target "${TEST_ROOT}/replies" 18090 18091 >"${TEST_ROOT}/replies.log" 2>&1 &
replyPid=$!
for proof in proof replies; do
    for ((attempt = 0; attempt < 100; attempt++)); do
        [[ ! -f "${TEST_ROOT}/${proof}/ready" ]] || break
        kill -0 "${originPid}" && kill -0 "${replyPid}" || fail 'target exited before readiness'
        sleep 0.05
    done
    [[ -f "${TEST_ROOT}/${proof}/ready" ]] || fail 'target did not become ready'
done
kernelSnapshot() {
    local tool version
    for tool in iptables ip6tables; do
        net "${tool}" -w -t nat -S || return 1
        net "${tool}" -w -t mangle -S || return 1
    done
    for version in 4 6; do
        net ip -j -N "-${version}" rule show | jq -cS . || return 1
        net ip -j -N "-${version}" route show table all | jq -cS . || return 1
    done
}
for tool in iptables ip6tables; do
    net "${tool}" -w -t nat -N outside-owner
    net "${tool}" -w -t nat -A outside-owner -m comment --comment outside-owner -j RETURN
    net "${tool}" -w -t nat -A PREROUTING -m comment --comment outside-owner -j outside-owner
    net "${tool}" -w -t nat -A OUTPUT -m comment --comment outside-owner -j outside-owner
done
baseline=$(kernelSnapshot)
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
makeCoreConfig() {
    local core=$1 configDir=$2
    mkdir "${configDir}"
    jq -n --arg core "${core}" --argjson port "${port}" --arg family "${family}" '
      {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
       core:{type:$core,secondary_type:null,protocols:[{
         id:1,core:$core,listener_id:"entry-reality",server:"proxy.example.com",public_port:35441,
         address_families:["ipv4"],name:"redirect-test",uuid:"11111111-1111-4111-8111-111111111111",
         reality:{server_name:"www.debian.org",target_host:"www.debian.org",target_port:443,
           private_key:"dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
           public_key:"hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",short_id:"1234"}}]},
       tls:null,subscription:{enabled:false,token:"0123456789abcdef"},
       images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
         ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
       host_integrations:[{type:"redirect",profile:"net-transparent",firewall_rules:["padm-redirect"],
         devices:[],schedules:[],settings:({port:$port,output_uid:65534} +
           (if $family == "ipv4" then {} else {family:$family} end))}]}
    ' >"${configDir}/spec.json"
    dockerConfigureSpecValidate "${configDir}/spec.json"
    if [[ "${core}" == xray ]]; then
        dockerGenerateXrayConfig "${configDir}/spec.json" "${configDir}/base.json"
    else
        dockerGenerateSingBoxConfig "${configDir}/spec.json" "${configDir}/base.json"
    fi
    dockerTrafficRender "${core}" "${configDir}/base.json" '{"schema_version":1,"accounts":{}}' \
        >"${configDir}/rendered.json"
    jq --arg core "${core}" '
      if $core == "xray" then .log={loglevel:"debug",access:"/dev/stdout",error:"/dev/stderr"}
      else .log={level:"debug",timestamp:false} end
    ' "${configDir}/rendered.json" >"${configDir}/config.json"
}
startCore() {
    local image
    local -a args
    image=$(jq -er --arg core "${core}" '.[$core].reference' /node-images.json)
    if [[ "${core}" == xray ]]; then args=(run -c /etc/padm/redirect/config.json)
    else args=(run -D /var/lib/padm/sing-box -c /etc/padm/redirect/config.json); fi
    coreContainer=$(docker run -d --network "container:${container}" --user 0:0 \
        --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges:true --read-only \
        --tmpfs /tmp:rw,nosuid,nodev,size=16m --tmpfs /var/lib/padm/sing-box:rw,nosuid,nodev,size=16m \
        --mount "type=bind,source=${configDir},target=/etc/padm/redirect,readonly" "${image}" "${args[@]}")
    for ((attempt = 0; attempt < 100; attempt++)); do
        if net ss -lnt | grep -qE "[[:space:]](0\\.0\\.0\\.0|\\*|\\[::\\]):${port}[[:space:]]"; then
            ! net ss -lnu | grep -qE "[[:space:]](0\\.0\\.0\\.0|\\*|\\[::\\]):${port}[[:space:]]" ||
                fail 'Redirect unexpectedly opened a UDP listener'
            return 0
        fi
        [[ "$(docker inspect --format '{{.State.Running}}' "${coreContainer}")" == true ]] ||
            fail "${core} exited before readiness"
        sleep 0.05
    done
    fail "${core} Redirect socket did not become ready"
}
startServer() {
    net rm -f /tmp/redirect.pid /tmp/redirect.status
    docker exec -d "${container}" sh -c '
      sh /tmp/padm-entrypoint redirect "$@" </dev/null >/tmp/redirect.log 2>&1 &
      server=$!
      printf "%s\n" "$server" >/tmp/redirect.pid
      status=0
      wait "$server" || status=$?
      printf "%s\n" "$status" >/tmp/redirect.status
    ' test "${port}" "${family}" --output-uid 65534
    for ((attempt = 0; attempt < 100; attempt++)); do
        entry redirect-health "${port}" "${family}" --output-uid 65534 >/dev/null 2>&1 && return 0
        ! net test -f /tmp/redirect.status || fail 'service exited before readiness'
        sleep 0.05
    done
    fail 'service did not become healthy'
}
stopServer() {
    net sh -c 'kill -TERM "$(cat /tmp/redirect.pid)"'
    for ((attempt = 0; attempt < 100; attempt++)); do
        if net test -f /tmp/redirect.status; then
            [[ "$(net cat /tmp/redirect.status)" == 0 ]] || fail 'TERM did not cleanly revoke Redirect'
            ! net test -e /var/lib/padm/net/redirect.state || fail 'successful stop left ownership state'
            [[ "$(kernelSnapshot)" == "${baseline}" ]] || fail 'stop changed external resources or left owned rules'
            return 0
        fi
        sleep 0.05
    done
    fail 'service survived TERM'
}
readState() {
    state=$(net cat /var/lib/padm/net/redirect.state | jq -Rne '
      [inputs | split("=")] as $pairs |
      if all($pairs[]; length == 2) and
        ($pairs | map(.[0]) | length) == ($pairs | map(.[0]) | unique | length)
      then $pairs | map({key:.[0],value:.[1]}) | from_entries
      else error("invalid ownership state") end
    ') || fail 'invalid ownership state'
    token=$(jq -er '.token | select(test("^[a-f0-9]{32}$"))' <<<"${state}")
    chain=$(jq -er '.chain' <<<"${state}")
    jq -e --arg port "${port}" --arg family "${family}" '
      .port == $port and .family == $family and .output_uid == "65534" and .phase == "active"
    ' <<<"${state}" >/dev/null || fail 'ownership state lost the requested scope'
    [[ "${chain}" == "padm-redirect-${token:0:10}" &&
        "$(net stat -c '%u:%a:%h' /var/lib/padm/net/redirect.state)" == 0:600:1 ]] ||
        fail 'ownership identity or permissions are wrong'
}
trafficCounter() {
    local version=$1 scope=$2 tool=iptables-save targetChain=${chain}
    [[ "${version}" != 6 ]] || tool=ip6tables-save
    [[ "${scope}" != output ]] || targetChain="${chain}-out"
    net "${tool}" -c -t nat | awk -v comment="padm-redirect:${token}" -v chain="${targetChain}" '
      index($0, comment) && index($0, "-A " chain " ") && index($0, "-j REDIRECT ") {
        split($1, fields, ":"); sub(/^\[/, "", fields[1]); total += fields[1]
      }
      END { printf "%.0f\n", total }
    '
}
probe() {
    local kind=$1 version=$2 scope=$3 captured=$4 uid=${5:-65534}
    local destination=198.18.67.20 peer=198.18.67.10 directory=proof targetPort=18080
    local beforePrerouting beforeOutput afterPrerouting afterOutput rows
    local -a caller=(nsenter --target "${clientPid}" --net --)
    [[ "${kind}" != udp ]] || targetPort=18081
    if [[ "${version}" == 6 ]]; then destination=fd40:67::20 peer=fd40:67::10; fi
    if [[ "${scope}" == output || "${scope}" == local ]]; then
        caller=(nsenter --target "${netPid}" --net -- setpriv --reuid "${uid}" --regid "${uid}"
            --clear-groups --bounding-set=-all --inh-caps=-all --ambient-caps=-all --)
    fi
    if [[ "${scope}" == local || "${scope}" == reply ]]; then
        destination=198.18.66.10 peer=198.18.66.20 directory=replies targetPort=18090
        [[ "${kind}" != udp ]] || targetPort=18091
        if [[ "${version}" == 6 ]]; then destination=fd40:66::10 peer=fd40:66::20; fi
        [[ "${scope}" != local ]] || peer=${destination}
    elif [[ "${kind}" == udp && "${scope}" == forward ]]; then
        peer=198.18.66.20
        [[ "${version}" != 6 ]] || peer=fd40:66::20
    fi
    rows=0
    [[ ! -f "${TEST_ROOT}/${directory}/${kind}.jsonl" ]] ||
        rows=$(jq -s 'length' "${TEST_ROOT}/${directory}/${kind}.jsonl")
    beforePrerouting=$(trafficCounter "${version}" forward)
    beforeOutput=$(trafficCounter "${version}" output)
    "${caller[@]}" python3 "${fixture}" client "${kind}" "${destination}" "${targetPort}"
    afterPrerouting=$(trafficCounter "${version}" forward)
    afterOutput=$(trafficCounter "${version}" output)
    if [[ "${captured}" == yes ]]; then
        if [[ "${scope}" == forward ]]; then
            ((afterPrerouting > beforePrerouting && afterOutput == beforeOutput)) ||
                fail 'TCP bypassed PREROUTING or core dial looped through OUTPUT'
        else
            ((afterOutput > beforeOutput && afterPrerouting == beforePrerouting)) ||
                fail 'selected UID TCP bypassed OUTPUT or looped through PREROUTING'
        fi
    else
        [[ "${afterPrerouting}" == "${beforePrerouting}" && "${afterOutput}" == "${beforeOutput}" ]] ||
            fail "${kind}/${scope}/${uid} unexpectedly captured by Redirect"
    fi
    jq -se --arg peer "${peer}" --arg kind "${kind}" --argjson rows "$((rows + 1))" '
      length == $rows and .[-1].peer == $peer and
      .[-1].payload == ("tproxy-" + $kind + "-request")
    ' "${TEST_ROOT}/${directory}/${kind}.jsonl" >/dev/null ||
        fail "${kind}/${scope} origin proof does not match the actual route"
}
for core in xray sing-box; do
    for tuple in '31298 ipv4' '31299 dual' '31300 ipv6'; do
        read -r port family <<<"${tuple}"
        configDir="${TEST_ROOT}/${core}-${port}"
        makeCoreConfig "${core}" "${configDir}"
        startCore
        startServer
        readState
        for version in $(case "${family}" in ipv4) echo 4 ;; ipv6) echo 6 ;; dual) echo '4 6' ;; esac); do
            probe tcp "${version}" output no 65533
            probe tcp "${version}" local no
            probe tcp "${version}" reply no
            probe tcp "${version}" forward yes
            probe tcp "${version}" output yes
            probe udp "${version}" forward no
            probe udp "${version}" output no
            probe udp "${version}" local no
            probe udp "${version}" reply no
        done
        stopServer
        for version in $(case "${family}" in ipv4) echo 4 ;; ipv6) echo 6 ;; dual) echo '4 6' ;; esac); do
            probe tcp "${version}" output no
        done
        docker stop --time 5 "${coreContainer}" >/dev/null
        docker logs "${coreContainer}" >"${TEST_ROOT}/${core}-${port}.log" 2>&1
        docker rm --volumes "${coreContainer}" >/dev/null
        coreContainer=
        grep -q 'redirect-in' "${TEST_ROOT}/${core}-${port}.log" || fail 'missing Redirect core log'
        printf 'docker-redirect-forwarding-ok: core=%s family=%s tcp=prerouting,uid-output udp=direct unselected=direct local=bypass reply=direct off=clean\n' \
            "${core}" "${family}"
    done
done

# 真实 Compose 归属、正常停止及外来 NAT 链保留沿生产管理入口验收。
metadataImage=${NET_IMAGE}
imageHash=$(docker run --rm --network none --entrypoint sha256sum "${metadataImage}" \
    /usr/local/bin/padm-entrypoint | cut -d ' ' -f 1)
if [[ "${imageHash}" != "$(sha256sum "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" | cut -d ' ' -f 1)" ]]; then
    mkdir "${TEST_ROOT}/metadata-image"
    cp -- "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" "${TEST_ROOT}/metadata-image/entrypoint.sh"
    printf 'FROM %s\nCOPY --chmod=0755 entrypoint.sh /usr/local/bin/padm-entrypoint\n' "${NET_IMAGE}" \
        >"${TEST_ROOT}/metadata-image/Dockerfile"
    docker build --pull=false --network none --tag padm-redirect-real-net:fixture \
        "${TEST_ROOT}/metadata-image" >"${TEST_ROOT}/metadata-build.log" 2>&1
    metadataImage="padm-redirect-real-net:fixture@$(docker image inspect \
        --format '{{.Descriptor.digest}}' padm-redirect-real-net:fixture)"
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
hostSnapshot() { iptables -w -t nat -S; ip6tables -w -t nat -S; }
sysctl -q -w net.ipv4.ip_forward=1
iptables -w -t nat -N redirect-meta-outside
iptables -w -t nat -A redirect-meta-outside -m comment --comment redirect-meta-outside -j RETURN
iptables -w -t nat -A PREROUTING -m comment --comment redirect-meta-outside -j redirect-meta-outside
iptables -w -t nat -A OUTPUT -m comment --comment redirect-meta-outside -j redirect-meta-outside
metadataBaseline=$(hostSnapshot)
docker compose --project-name "${PADM_DOCKER_PROJECT}" --project-directory "${root}" \
    --env-file "${root}/images.env" --file "${root}/compose.json" --profile net-transparent \
    up -d --no-deps --pull never net-transparent >"${TEST_ROOT}/metadata-compose.log" 2>&1
composeContainer=$(docker ps -aq --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
    --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False)
for ((attempt = 0; attempt < 100; attempt++)); do
    metadataCid=$(dockerTProxyContainer running 2>"${TEST_ROOT}/metadata-inspect.log") && break
    [[ "$(docker inspect --format '{{.State.Running}}' "${composeContainer}")" == true ]] ||
        fail 'Compose Redirect exited before ownership readiness'
    sleep 0.05
done
[[ "${metadataCid:-}" == "${composeContainer}" ]] ||
    fail 'real Compose metadata did not match production ownership helper'
docker container inspect "${composeContainer}" >"${TEST_ROOT}/metadata-inspect.json"
dockerTProxyDisablePrepare <(printf '{"host_integrations":[]}')
! docker container inspect "${composeContainer}" >/dev/null 2>&1 ||
    fail 'production disable did not remove the audited Compose container'
composeContainer=
[[ ! -e "${root}/data/net/transparent/redirect.state" && "$(hostSnapshot)" == "${metadataBaseline}" ]] ||
    fail 'production disable left state/rules or changed outside resources'
iptables -w -t nat -D PREROUTING -m comment --comment redirect-meta-outside -j redirect-meta-outside
iptables -w -t nat -D OUTPUT -m comment --comment redirect-meta-outside -j redirect-meta-outside
iptables -w -t nat -F redirect-meta-outside
iptables -w -t nat -X redirect-meta-outside
printf 'docker-redirect-compose-owner-ok: inspect=running disable=clean outside=preserved\n'
printf 'docker-redirect-real-ok\n'
