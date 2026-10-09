#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
[[ "$(id -u)" == 0 && "$(uname -s)" == Linux && -f /.dockerenv &&
    -f /node-images.json && -f /node-images.tar && -d /n ]] || exit 1
jq -e 'map(.ifname) == ["lo"]' < <(ip -j link show) >/dev/null
TEST_ROOT=$(mktemp -d /n/.tmp-fail2ban-real.XXXXXX)
daemon=
cleanup() {
    local status=$?
    if [[ -n "${daemon}" ]]; then
        kill -TERM "${daemon}" 2>/dev/null || true
        wait "${daemon}" 2>/dev/null || true
    fi
    [[ "${status}" -eq 0 ]] || cat "${TEST_ROOT}/daemon.log" >&2
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 嵌套 daemon 只操作隔离容器，复用离线 net 镜像，不挂宿主 Socket。
export DOCKER_HOST="unix://${TEST_ROOT}/docker.sock"
dockerd --host "${DOCKER_HOST}" --data-root "${TEST_ROOT}/docker" \
    --exec-root "${TEST_ROOT}/run" --pidfile "${TEST_ROOT}/daemon.pid" \
    --feature containerd-snapshotter=true --storage-driver overlayfs \
    --bridge none --iptables=false --ip6tables=false >"${TEST_ROOT}/daemon.log" 2>&1 &
daemon=$!
ready=0
for ((attempt = 0; attempt < 300; attempt++)); do
    if docker info >/dev/null 2>&1; then ready=1; break; fi
    sleep 0.1
done
[[ "${ready}" -eq 1 ]]
docker load --input /node-images.tar >/dev/null
PADM_TEST_NET_IMAGE=$(jq -er '.net.reference' /node-images.json)
export PADM_TEST_NET_IMAGE
[[ "$(docker image inspect --format '{{.Id}}' "${PADM_TEST_NET_IMAGE}")" == \
    "$(jq -er '.net.image_id' /node-images.json)" ]]
bash "${PROJECT_ROOT}/docker/tests/fail2ban-real.sh"
