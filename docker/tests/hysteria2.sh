#!/usr/bin/env bash
set -euo pipefail

# 包含协议与 Reality 基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
HY2_SPEC="${TEST_ROOT}/hysteria2.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.type = "sing-box" | .core.secondary_type = null |
  .core.protocols = [(.core.protocols[0] |
    del(.reality) | .id = 3 | .core = "sing-box" | .listener_id = "entry-hy2" |
    .public_port = 27443 | .name = "Hysteria2" |
    .hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:50,
      obfs:null,masquerade:""})] |
  .tls = {domain:"ws.example.com"}
' "${REALITY_SPEC}" >"${HY2_SPEC}"
dockerConfigureSpecValidate "${HY2_SPEC}" || fail 'Hysteria2 有效合同被拒绝'

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = null' \
    '.core.protocols[0].hy2.domain = "other.example.com"' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].hy2.extra = true' \
    '.core.protocols[0].hy2.bandwidth_mode = "auto"' \
    '.core.protocols[0].hy2.up_mbps = 0' \
    '.core.protocols[0].hy2.down_mbps = 1.5' \
    '.core.protocols[0].hy2.up_mbps = 1000001' \
    '.core.protocols[0].hy2.obfs = {type:"gecko",password:"0123456789abcdef"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"short"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"0123456789abcde\n"}' \
    '.core.protocols[0].hy2.obfs = {type:"salamander",password:"0123456789abcdef",extra:true}' \
    '.core.protocols[0].hy2.masquerade = "http://www.example.com/"' \
    '.core.protocols[0].hy2.masquerade = "https://user@www.example.com/"' \
    '.core.protocols[0].hy2.masquerade = "https://www.example.com/\n"' \
    '.core.protocols[0].hy2.masquerade = "https://www.example.com/?token=secret"' \
    '.subscription.enabled = true' \
    '.core.protocols[0].public_port = 10087'; do
    jq "${mutation}" "${HY2_SPEC}" >"${TEST_ROOT}/invalid-hy2.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-hy2.json" 2>/dev/null; then
        fail "Hysteria2 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${HY2_SPEC}" >"${TEST_ROOT}/invalid-hy2.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-hy2.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 Hysteria2"
    fi
done

for topology in single secondary primary; do
    jq --arg topology "${topology}" --slurpfile reality "${REALITY_SPEC}" '
      if $topology == "single" then .
      else
        .core.secondary_type = "xray" |
        .core.protocols += [$reality[0].core.protocols[0]] |
        if $topology == "secondary" then
          .core.type = "xray" | .core.secondary_type = "sing-box"
        else . end
      end
    ' "${HY2_SPEC}" >"${TEST_ROOT}/topology-hy2.json"
    newState "hy2-${topology}" "${TEST_ROOT}/topology-hy2.json"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:27443:27443/udp","[::]:27443:27443/udp"] and
      any(.services["sing-box"].volumes[];
        .target == "/etc/padm/secrets/tls" and .read_only == true) and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: UDP 双栈、TLS 挂载或 Nginx 拓扑错误"
    jq -e 'any(.listeners[]; .listener_id == "entry-hy2" and .service == "sing-box" and
      .transport == "udp" and .public_port == .container_port)' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: Hysteria2 未记录 UDP 监听"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: UDP 部署基线不匹配"
done

BASE="${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base"
jq -e --arg uuid "${UUID}" '.inbounds[] | select(.type == "hysteria2") |
  .users == [{name:$uuid,password:$uuid}] and .ignore_client_bandwidth == true and
  (has("up_mbps") or has("down_mbps") or has("obfs") or has("masquerade") | not) and
  .tls == {enabled:true,server_name:"ws.example.com",alpn:["h3"],
    certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
    key_path:"/etc/padm/secrets/tls/ws.example.com.key"}' "${BASE}" >/dev/null ||
    fail 'Hysteria2 BBR 配置或账号/TLS 生成错误'
HY2_URI="hysteria2://${UUID}@[2001:db8::1]:27443?peer=ws.example.com&insecure=0&sni=ws.example.com&alpn=h3#Hysteria2"
runRead 0 hy2-links dockerProtocolCommand links entry-hy2
[[ "$(<"${STDOUT}")" == "${HY2_URI}" ]] || fail 'Hysteria2 单链接不精确或泄漏额外输出'
runRead 0 hy2-list dockerProtocolCommand list
grep -Fq 'sing-box  Hysteria2' "${STDOUT}" || fail '概览没有 Hysteria2 标签'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'Hysteria2 概览暴露 UUID/密码'

jq '.core.protocols[0].hy2 |= (.bandwidth_mode = "brutal" |
  .obfs = {type:"salamander",password:"0123456789abcdef"} |
  .masquerade = "https://www.example.com/path-1")' \
    "${HY2_SPEC}" >"${TEST_ROOT}/brutal-hy2.json"
dockerConfigureSpecValidate "${TEST_ROOT}/brutal-hy2.json"
dockerGenerateSingBoxConfig "${TEST_ROOT}/brutal-hy2.json" "${TEST_ROOT}/brutal-core.json"
jq -e '.inbounds[0] | .up_mbps == 100 and .down_mbps == 50 and
  (has("ignore_client_bandwidth") | not) and
  .obfs == {type:"salamander",password:"0123456789abcdef"} and
  .masquerade == "https://www.example.com/path-1"' "${TEST_ROOT}/brutal-core.json" >/dev/null ||
    fail 'Hysteria2 Brutal/混淆/伪装生成错误'
jq '.subscription.enabled = true' "${TEST_ROOT}/brutal-hy2.json" >"${TEST_ROOT}/local-hy2.json"
dockerGenerateSubscription "${TEST_ROOT}/local-hy2.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "${HY2_URI//#Hysteria2/}&upmbps=50&downmbps=100&obfs=salamander&obfs-password=0123456789abcdef#Hysteria2" ]] ||
    fail 'Hysteria2 带宽方向或混淆链接不精确'
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender sing-box "${BASE}" "${quota}" >"${TEST_ROOT}/quota-hy2.json"
jq -e 'all(.inbounds[] | select(.type == "hysteria2"); .users == [])' \
    "${TEST_ROOT}/quota-hy2.json" >/dev/null || fail 'Hysteria2 未执行共享账号额度'
accounts=$(dockerTrafficAccounts sing-box)
jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
    fail 'Hysteria2 为同 UUID 重建独立统计账号'

# UDP 占用不能漏报，属于当前部署的 UDP 监听仍可在事务中复用。
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 27443 ]]; }
    if dockerConfigurePortsAvailable "${HY2_SPEC}" 2>/dev/null; then
        fail 'Hysteria2 漏检 UDP 占用'
    fi
    dockerCurrentOwnsPort() { [[ "$1" == 27443 && "$2" == udp ]]; }
    dockerConfigurePortsAvailable "${HY2_SPEC}" || fail '自有 UDP 监听不能被复用'
)

liveSnapshot() {
    find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
        "${PADM_DOCKER_INSTALL_DIR}/secrets" -type f -exec sha256sum {} + | LC_ALL=C sort
    sha256sum "${PADM_DOCKER_INSTALL_DIR}/"{deployment.json,compose.json,images.env}
}
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 3) | .public_port) = 27444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-hy2.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-hy2.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "Hysteria2 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Hysteria2 失败恢复改变证书、配置或累计流量'

IMAGE_DIGEST=$(printf '3%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'Hysteria2 混合双核心更新失败'
runRead 0 hy2-updated-links dockerProtocolCommand links entry-hy2
[[ "$(<"${STDOUT}")" == "${HY2_URI}" ]] || fail '更新改变 Hysteria2 链接'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'Hysteria2 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Hysteria2 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Hysteria2 回归遗留部署锁'
printf 'docker-hysteria2-regression-ok\n'
