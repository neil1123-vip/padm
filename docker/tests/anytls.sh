#!/usr/bin/env bash
set -euo pipefail

# 串接已有完整协议基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/hysteria2.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
ANYTLS_SPEC="${TEST_ROOT}/anytls.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.protocols[0] |= (del(.hy2) | .id = 4 | .listener_id = "entry-anytls" |
    .public_port = 28443 | .name = "AnyTLS" | .anytls = {domain:"ws.example.com"})
' "${HY2_SPEC}" >"${ANYTLS_SPEC}"
dockerConfigureSpecValidate "${ANYTLS_SPEC}" || fail 'AnyTLS 有效合同被拒绝'

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = null' \
    '.core.protocols[0].anytls.domain = "other.example.com"' \
    '.core.protocols[0].anytls.domain += "\n" | .tls.domain = .core.protocols[0].anytls.domain' \
    '.core.protocols[0].anytls.domain = "bad/domain" | .tls.domain = "bad/domain"' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].anytls.extra = true' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].hy2 = {domain:"ws.example.com"}' \
    '.core.protocols[0].public_port = 10087' \
    '.subscription.enabled = true' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${ANYTLS_SPEC}" >"${TEST_ROOT}/invalid-anytls.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-anytls.json" 2>/dev/null; then
        fail "AnyTLS 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${ANYTLS_SPEC}" >"${TEST_ROOT}/invalid-anytls.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-anytls.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 AnyTLS"
    fi
done

cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${ANYTLS_SPEC}" || fail '当前 bundle 拒绝 AnyTLS'
for mutation in \
    '(.protocols[] | select(.id == 4) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 4))' \
    '(.protocols[] | select(.id == 4) | .cores) = ["xray"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${ANYTLS_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 AnyTLS: ${mutation}"
    fi
done

ANYTLS_URI="anytls://${UUID}@[2001:db8::1]:28443?security=tls&sni=ws.example.com#AnyTLS"
# AnyTLS 只读导出不依赖发布开关；HTTPS 发布仍由 Xray WS TLS 提供。
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "xray" | .subscription.enabled = true |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${ANYTLS_SPEC}" >"${TEST_ROOT}/published-anytls.json"
newState anytls-published "${TEST_ROOT}/published-anytls.json"
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${ANYTLS_URI}"$'\n'"${WS_URI}" ]] ||
    fail 'WS 发布没有精确包含 AnyTLS 与 WS 链接'
jq -e '(.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"]' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail 'AnyTLS 与 WS 发布拓扑错误'

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
    ' "${ANYTLS_SPEC}" >"${TEST_ROOT}/topology-anytls.json"
    newState "anytls-${topology}" "${TEST_ROOT}/topology-anytls.json"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:28443:28443/tcp","[::]:28443:28443/tcp"] and
      any(.services["sing-box"].volumes[];
        .target == "/etc/padm/secrets/tls" and .read_only == true) and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: AnyTLS TCP 双栈、TLS 挂载或 Nginx 拓扑错误"
    jq -e 'any(.listeners[]; .listener_id == "entry-anytls" and .service == "sing-box" and
      .transport == "tcp" and .public_port == .container_port)' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: AnyTLS 未记录 TCP 监听"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: AnyTLS 部署基线不匹配"
    jq -e --arg uuid "${UUID}" '.inbounds[] | select(.type == "anytls") |
      .tag == "entry-anytls" and .listen_port == 28443 and
      .users == [{name:$uuid,password:$uuid}] and
      .tls == {enabled:true,server_name:"ws.example.com",
        certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
        key_path:"/etc/padm/secrets/tls/ws.example.com.key"}' \
        "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" >/dev/null ||
        fail "${topology}: AnyTLS 账号或 TLS 生成错误"
done
runRead 0 anytls-links dockerProtocolCommand links entry-anytls
[[ "$(<"${STDOUT}")" == "${ANYTLS_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'AnyTLS 单链接不精确或混入额外输出'
runRead 0 anytls-list dockerProtocolCommand list
grep -qxF 'entry-anytls  sing-box  AnyTLS  [2001:db8::1]:28443  [ipv4,ipv6]  AnyTLS' "${STDOUT}" ||
    fail '概览没有 AnyTLS 标签或入口'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'AnyTLS 概览暴露 UUID/密码'
cp "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" "${TEST_ROOT}/saved-anytls-core.json"
jq '(.inbounds[] | select(.type == "anytls") | .users[0].password) = "changed-password"' \
    "${TEST_ROOT}/saved-anytls-core.json" >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
runRead 15 anytls-core-drift dockerProtocolCommand links entry-anytls
cp "${TEST_ROOT}/saved-anytls-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/saved-anytls-deployment.json"
jq '(.listeners[] | select(.listener_id == "entry-anytls") | .transport) = "udp"' \
    "${TEST_ROOT}/saved-anytls-deployment.json" >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
runRead 15 anytls-transport-drift dockerProtocolCommand links entry-anytls
cp "${TEST_ROOT}/saved-anytls-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
jq '.core.protocols[0].server = "proxy.example.com" | .subscription.enabled = true' \
    "${ANYTLS_SPEC}" >"${TEST_ROOT}/dns-anytls.json"
dockerGenerateSubscription "${TEST_ROOT}/dns-anytls.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "anytls://${UUID}@proxy.example.com:28443?security=tls&sni=ws.example.com#AnyTLS" ]] ||
    fail 'AnyTLS 域名入口链接不精确'

# 同 UUID 跨核心共享账号与额度，删除账号不能改变 AnyTLS 的 TLS 参数。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    accounts=$(dockerTrafficAccounts "${core}")
    jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
        fail "${core}: AnyTLS 重建独立统计账号"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-anytls-${core}.json"
done
jq -e --arg uuid "${UUID}" 'all(.inbounds[] | select(.type == "anytls"); .users == [] and
  .tls.enabled == true and (.tls | has("alpn") | not)) and
  .experimental.v2ray_api.stats.users == [$uuid]' \
    "${TEST_ROOT}/quota-anytls-sing-box.json" >/dev/null || fail 'AnyTLS 未执行共享账号额度'
jq -e 'all(.inbounds[] | select(.protocol == "vless"); .settings.clients == [])' \
    "${TEST_ROOT}/quota-anytls-xray.json" >/dev/null || fail 'AnyTLS 同 UUID 未对 Xray 执行额度'

# AnyTLS 只占 TCP；同端口 UDP 不应误报，自有 TCP 监听可以复用。
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 28443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    if dockerConfigurePortsAvailable "${ANYTLS_SPEC}" 2>/dev/null; then
        fail 'AnyTLS 漏检 TCP 占用'
    fi
    dockerCurrentOwnsPort() { [[ "$1" == 28443 && "$2" == tcp ]]; }
    dockerConfigurePortsAvailable "${ANYTLS_SPEC}" || fail '自有 AnyTLS TCP 监听不能被复用'
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 28443 ]]; }
    dockerConfigurePortsAvailable "${ANYTLS_SPEC}" || fail 'AnyTLS 把 UDP 占用误判为 TCP'
)

before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 4) | .public_port) = 28444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-anytls.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-anytls.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "AnyTLS 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'AnyTLS 失败恢复改变证书、配置或累计流量'

IMAGE_DIGEST=$(printf '4%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'AnyTLS 混合双核心更新失败'
runRead 0 anytls-updated-links dockerProtocolCommand links entry-anytls
[[ "$(<"${STDOUT}")" == "${ANYTLS_URI}" ]] || fail '更新改变 AnyTLS 链接'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'AnyTLS 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'AnyTLS 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'AnyTLS 回归遗留部署锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail 'AnyTLS 回归遗留候选'
printf 'docker-anytls-regression-ok\n'
