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
        for path in "${TEST_ROOT}"/*.log; do [[ ! -f "${path}" ]] || cat -- "${path}" >&2; done
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

# host 仅为外层隔离回归容器；真实流量矩阵沿用已完成探针，这里验证生产门禁。
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
docker run --rm --network none --entrypoint sh "${netImage}" \
    -c 'python3 --version; nft --version; ip -V; ls -ld /usr/local/lib/padm; ls -l /usr/local/lib/padm/tun-resources.py'
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
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
nft add rule inet sing-box output counter comment tun-real-drift
drift=$(snapshot)
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
