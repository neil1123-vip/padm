#!/usr/bin/env bash
set -euo pipefail

# 串接已有完整协议基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/anytls.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
NAIVE_SPEC="${TEST_ROOT}/naive.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.protocols[0] |= (del(.anytls) | .id = 5 | .listener_id = "entry-naive" |
    .server = "ws.example.com" | .public_port = 29443 | .name = "Naive:Proxy" |
    .naive = {domain:"ws.example.com"})
' "${ANYTLS_SPEC}" >"${NAIVE_SPEC}"
dockerConfigureSpecValidate "${NAIVE_SPEC}" || fail 'NaiveProxy 有效合同被拒绝'

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = null' \
    '.tls.domain = "other.example.com"' \
    '.core.protocols[0].server = "proxy.example.com"' \
    '.core.protocols[0].server = "2001:db8::1"' \
    '.core.protocols[0].naive.domain = "other.example.com"' \
    '.core.protocols[0].naive.domain += "\n" |
      .tls.domain = .core.protocols[0].naive.domain |
      .core.protocols[0].server = .core.protocols[0].naive.domain' \
    '.core.protocols[0].naive.domain = "bad/domain" | .tls.domain = "bad/domain" |
      .core.protocols[0].server = "bad/domain"' \
    '.core.protocols[0].naive.domain = "" | .tls.domain = "" | .core.protocols[0].server = ""' \
    'del(.core.protocols[0].naive)' \
    'del(.core.protocols[0].naive.domain)' \
    '.core.protocols[0].naive = null' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].naive.extra = true' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].anytls = {domain:"ws.example.com"}' \
    '.core.protocols[0].public_port = 10087' \
    '.subscription.enabled = true' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${NAIVE_SPEC}" >"${TEST_ROOT}/invalid-naive.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-naive.json" 2>/dev/null; then
        fail "NaiveProxy 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${NAIVE_SPEC}" >"${TEST_ROOT}/invalid-naive.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-naive.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 NaiveProxy"
    fi
done

cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${NAIVE_SPEC}" || fail '当前 bundle 拒绝 NaiveProxy'
for mutation in \
    '(.protocols[] | select(.id == 5) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 5))' \
    '(.protocols[] | select(.id == 5) | .cores) = ["xray"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${NAIVE_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 NaiveProxy: ${mutation}"
    fi
done

NAIVE_URI="naive+https://${UUID}:${UUID}@ws.example.com:29443?padding=true#Naive%3AProxy"
# NaiveProxy 只读导出不依赖发布开关；HTTPS 发布仍由 Xray WS TLS 提供。
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "xray" | .subscription.enabled = true |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${NAIVE_SPEC}" >"${TEST_ROOT}/published-naive.json"
newState naive-published "${TEST_ROOT}/published-naive.json"
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${NAIVE_URI}"$'\n'"${WS_URI}" ]] ||
    fail 'WS 发布没有精确包含 NaiveProxy 与 WS 链接'
jq -e '(.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"]' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail 'NaiveProxy 与 WS 发布拓扑错误'

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
    ' "${NAIVE_SPEC}" >"${TEST_ROOT}/topology-naive.json"
    newState "naive-${topology}" "${TEST_ROOT}/topology-naive.json"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:29443:29443/tcp","[::]:29443:29443/tcp"] and
      any(.services["sing-box"].volumes[];
        .target == "/etc/padm/secrets/tls" and .read_only == true) and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: NaiveProxy TCP 双栈、TLS 挂载或 Nginx 拓扑错误"
    jq -e 'any(.listeners[]; .listener_id == "entry-naive" and .service == "sing-box" and
      .transport == "tcp" and .public_port == .container_port)' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: NaiveProxy 未记录 TCP 监听"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: NaiveProxy 部署基线不匹配"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" '.inbounds[] | select(.type == "naive") |
          .tag == "entry-naive" and .listen_port == 29443 and .network == "tcp" and
          .users == [{username:$uuid,password:$uuid}] and
          .tls == {enabled:true,server_name:"ws.example.com",
            certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
            key_path:"/etc/padm/secrets/tls/ws.example.com.key"}' \
            "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/${file}" >/dev/null ||
            fail "${topology}: NaiveProxy ${file} 的账号、TCP 或 TLS 生成错误"
    done
done
runRead 0 naive-links dockerProtocolCommand links entry-naive
[[ "$(<"${STDOUT}")" == "${NAIVE_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'NaiveProxy 单链接不精确或混入额外输出'
runRead 0 naive-list dockerProtocolCommand list
grep -qxF 'entry-naive  sing-box  NaiveProxy  ws.example.com:29443  [ipv4,ipv6]  Naive:Proxy' "${STDOUT}" ||
    fail '概览没有 NaiveProxy 标签或域名入口'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'NaiveProxy 概览暴露用户名或密码'
cp "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" "${TEST_ROOT}/saved-naive-core.json"
for mutation in \
    '(.inbounds[] | select(.type == "naive") | .users[0].password) = "changed-password"' \
    '(.inbounds[] | select(.type == "naive") | .users[0].username) = "changed-username"' \
    '(.inbounds[] | select(.type == "naive") | .users[0].name) = "unexpected-name"' \
    '(.inbounds[] | select(.type == "naive") | .network) = "udp"' \
    '(.inbounds[] | select(.type == "naive") | .tls.server_name) = "other.example.com"'; do
    jq "${mutation}" "${TEST_ROOT}/saved-naive-core.json" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    runRead 15 naive-core-drift dockerProtocolCommand links entry-naive
done
cp "${TEST_ROOT}/saved-naive-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/saved-naive-deployment.json"
jq '(.listeners[] | select(.listener_id == "entry-naive") | .transport) = "udp"' \
    "${TEST_ROOT}/saved-naive-deployment.json" >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
runRead 15 naive-transport-drift dockerProtocolCommand links entry-naive
cp "${TEST_ROOT}/saved-naive-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"

# username 同时是认证和统计标识；额度渲染不能补入 Naive 不支持的 name。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    accounts=$(dockerTrafficAccounts "${core}")
    jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
        fail "${core}: NaiveProxy 重建独立统计账号"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-naive-${core}.json"
done
jq -e --arg uuid "${UUID}" 'all(.inbounds[] | select(.type == "naive"); .users == [] and
  .network == "tcp" and .tls.enabled == true and (.tls | has("alpn") | not)) and
  .experimental.v2ray_api.stats.users == [$uuid]' \
    "${TEST_ROOT}/quota-naive-sing-box.json" >/dev/null || fail 'NaiveProxy 未执行共享账号额度'
jq -e 'all(.inbounds[] | select(.protocol == "vless"); .settings.clients == [])' \
    "${TEST_ROOT}/quota-naive-xray.json" >/dev/null || fail 'NaiveProxy 同 UUID 未对 Xray 执行额度'
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender sing-box "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" "${quota}" \
    >"${TEST_ROOT}/enabled-naive.json"
jq -e --arg uuid "${UUID}" 'all(.inbounds[] | select(.type == "naive");
  .users == [{username:$uuid,password:$uuid}] and .network == "tcp" and .tls.enabled == true) and
  .experimental.v2ray_api.stats.users == [$uuid]' "${TEST_ROOT}/enabled-naive.json" >/dev/null ||
    fail 'NaiveProxy 启用账号时改变认证字段或统一统计标识'

# NaiveProxy 只占 TCP；同端口 UDP 不应误报，自有 TCP 监听可以复用。
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 29443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    if dockerConfigurePortsAvailable "${NAIVE_SPEC}" 2>/dev/null; then
        fail 'NaiveProxy 漏检 TCP 占用'
    fi
    dockerCurrentOwnsPort() { [[ "$1" == 29443 && "$2" == tcp ]]; }
    dockerConfigurePortsAvailable "${NAIVE_SPEC}" || fail '自有 NaiveProxy TCP 监听不能被复用'
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 29443 ]]; }
    dockerConfigurePortsAvailable "${NAIVE_SPEC}" || fail 'NaiveProxy 把 UDP 占用误判为 TCP'
)

before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 5) | .public_port) = 29444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-naive.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-naive.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "NaiveProxy 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'NaiveProxy 失败恢复改变证书、配置或累计流量'

IMAGE_DIGEST=$(printf '5%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'NaiveProxy 混合双核心更新失败'
runRead 0 naive-updated-links dockerProtocolCommand links entry-naive
[[ "$(<"${STDOUT}")" == "${NAIVE_URI}" ]] || fail '更新改变 NaiveProxy 链接'
jq -e --arg uuid "${UUID}" 'any(.inbounds[]; .type == "naive" and
  .network == "tcp" and .users == [{username:$uuid,password:$uuid}])' \
    "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null ||
    fail '更新改变 NaiveProxy 认证字段或添加 name'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'NaiveProxy 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'NaiveProxy 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'NaiveProxy 回归遗留部署锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail 'NaiveProxy 回归遗留候选'
printf 'docker-naive-regression-ok\n'
