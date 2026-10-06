#!/usr/bin/env bash
set -euo pipefail

# 串接已有完整协议基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/tuic.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
TROJAN_SPEC="${TEST_ROOT}/trojan.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.protocols[0] |= (del(.hy2) | .id = 28 | .listener_id = "entry-trojan" |
    .public_port = 32443 | .name = "Trojan:test" | .trojan = {domain:"ws.example.com"})
' "${HY2_SPEC}" >"${TROJAN_SPEC}"
for core in xray sing-box; do
    jq --arg core "${core}" '.core.type = $core | .core.protocols[0].core = $core' \
        "${TROJAN_SPEC}" >"${TEST_ROOT}/valid-trojan-${core}.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/valid-trojan-${core}.json" ||
        fail "${core}: Trojan 有效合同被拒绝"
done
for mutation in \
    '.tls = null' \
    '.core.protocols[0].trojan.domain = "other.example.com"' \
    '.core.protocols[0].trojan.domain = "bad/domain" | .tls.domain = "bad/domain"' \
    '.core.protocols[0].trojan.domain += "\n" | .tls.domain = .core.protocols[0].trojan.domain' \
    'del(.core.protocols[0].trojan)' \
    'del(.core.protocols[0].trojan.domain)' \
    '.core.protocols[0].trojan = null' \
    '.core.protocols[0].trojan.extra = true' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",
      up_mbps:100,down_mbps:50,obfs:null,masquerade:""}' \
    '.core.protocols[0].public_port = 10087' \
    '.subscription.enabled = true' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${TROJAN_SPEC}" >"${TEST_ROOT}/invalid-trojan.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-trojan.json" 2>/dev/null; then
        fail "Trojan 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${TROJAN_SPEC}" >"${TEST_ROOT}/invalid-trojan.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-trojan.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 Trojan"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TROJAN_SPEC}" || fail '当前 bundle 拒绝 Trojan'
for mutation in \
    '(.protocols[] | select(.id == 28) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 28))' \
    '(.protocols[] | select(.id == 28) | .cores) = ["xray"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TROJAN_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 Trojan: ${mutation}"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TROJAN_SPEC}" 2>/dev/null; then
    fail '旧规格 bundle 接受 Trojan'
fi

TROJAN_URI="trojan://${UUID}@[2001:db8::1]:32443?peer=ws.example.com&fp=chrome&sni=ws.example.com&alpn=http%2F1.1#Trojan%3Atest"
# 本地输出独立于 HTTPS 发布；混合 WS 时才启用 Nginx/订阅服务。
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "xray" | .subscription.enabled = true |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${TROJAN_SPEC}" >"${TEST_ROOT}/published-trojan.json"
newState trojan-published "${TEST_ROOT}/published-trojan.json"
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${TROJAN_URI}"$'\n'"${WS_URI}" ]] ||
    fail 'WS 发布没有精确包含 Trojan 与 WS 链接'
jq -e '(.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"]' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail 'Trojan 与 WS 发布拓扑错误'

for topology in xray sing-box dual-xray dual-sing; do
    jq --arg topology "${topology}" '
      if $topology == "xray" then .core.type = "xray" | .core.protocols[0].core = "xray"
      elif $topology == "sing-box" then .
      else
        .core.type = "xray" | .core.secondary_type = "sing-box" |
        .core.protocols += [(.core.protocols[0] |
          .listener_id = "entry-trojan-xray" | .core = "xray" | .public_port = 32444)] |
        if $topology == "dual-sing" then .core.type = "sing-box" | .core.secondary_type = "xray" else . end
      end
    ' "${TROJAN_SPEC}" >"${TEST_ROOT}/topology-trojan.json"
    newState "trojan-${topology}" "${TEST_ROOT}/topology-trojan.json"
    dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: Trojan 部署基线不匹配"
    jq -e '(.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: direct Trojan 启动了无关 Nginx"
    jq -e 'all(.listeners[]; .transport == "tcp" and .public_port == .container_port and
      .address_families == ["ipv4","ipv6"])' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: Trojan 监听不是 TCP 双栈"
    for core in $(dockerTrafficCore); do
        port=32443; listener=entry-trojan
        if [[ "${core}" == xray && "${topology}" == dual-* ]]; then port=32444; listener=entry-trojan-xray; fi
        jq -e --arg core "${core}" --argjson port "${port}" '
          .services[$core].ports == [("0.0.0.0:"+($port|tostring)+":"+($port|tostring)+"/tcp"),
            ("[::]:"+($port|tostring)+":"+($port|tostring)+"/tcp")] and
          any(.services[$core].volumes[]; .target == "/etc/padm/secrets/tls" and .read_only)
        ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
            fail "${topology}/${core}: Trojan TLS 挂载或端口错误"
        dockerTrafficAccounts "${core}" | jq -e --arg uuid "${UUID}" '
          length == 1 and .[0].account == $uuid' >/dev/null || fail "${core}: Trojan 未复用 UUID 账号"
        for file in users.base config.json; do
            jq -e --arg core "${core}" --arg uuid "${UUID}" --arg listener "${listener}" --argjson port "${port}" '
              if $core == "xray" then
                any(.inbounds[]; .protocol == "trojan" and .tag == $listener and .port == $port and
                  .settings.clients == [{email:$uuid,password:$uuid}] and
                  (.settings | has("fallbacks") | not) and
                  .streamSettings == {network:"tcp",security:"tls",tlsSettings:{
                    serverName:"ws.example.com",alpn:["http/1.1"],rejectUnknownSni:true,minVersion:"1.2",
                    certificates:[{certificateFile:"/etc/padm/secrets/tls/ws.example.com.crt",
                      keyFile:"/etc/padm/secrets/tls/ws.example.com.key"}]}})
              else
                any(.inbounds[]; .type == "trojan" and .tag == $listener and .listen == "::" and
                  .listen_port == $port and .users == [{name:$uuid,password:$uuid}] and
                  (. | has("fallback") | not) and
                  .tls == {enabled:true,server_name:"ws.example.com",alpn:["http/1.1"],
                    certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
                    key_path:"/etc/padm/secrets/tls/ws.example.com.key"})
              end
            ' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/${file}" >/dev/null ||
                fail "${topology}/${core}: Trojan ${file} 账号或 direct TLS 配置错误"
        done
    done
done
runRead 0 trojan-links dockerProtocolCommand links entry-trojan
[[ "$(<"${STDOUT}")" == "${TROJAN_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'Trojan 单链接不精确或混入额外输出'
runRead 0 trojan-list dockerProtocolCommand list
grep -qxF 'entry-trojan  sing-box  Trojan direct  [2001:db8::1]:32443  [ipv4,ipv6]  Trojan:test' \
    "${STDOUT}" || fail '概览没有 Trojan direct 标签或入口'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'Trojan 概览暴露密码'
for core in xray sing-box; do
    cp "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" "${TEST_ROOT}/saved-trojan-${core}.json"
    for field in password identity tls; do
        jq --arg core "${core}" --arg field "${field}" '
          .inbounds |= map(if .protocol == "trojan" or .type == "trojan" then
            if $core == "xray" then
              if $field == "password" then .settings.clients[0].password = "changed-password"
              elif $field == "identity" then .settings.clients[0].email = "changed-account"
              else .streamSettings.tlsSettings.certificates[0].keyFile = "/wrong.key" end
            else
              if $field == "password" then .users[0].password = "changed-password"
              elif $field == "identity" then .users[0].name = "changed-account"
              else .tls.server_name = "other.example.com" end
            end else . end)
        ' "${TEST_ROOT}/saved-trojan-${core}.json" \
            >"${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json"
        runRead 15 "trojan-${core}-${field}-drift" dockerProtocolCommand links entry-trojan
    done
    cp "${TEST_ROOT}/saved-trojan-${core}.json" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json"
done
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/saved-trojan-deployment.json"
jq '(.listeners[] | select(.listener_id == "entry-trojan") | .transport) = "udp"' \
    "${TEST_ROOT}/saved-trojan-deployment.json" >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
runRead 15 trojan-transport-drift dockerProtocolCommand links entry-trojan
cp "${TEST_ROOT}/saved-trojan-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
jq '.core.protocols[0].server = "proxy.example.com" | .subscription.enabled = true' \
    "${TROJAN_SPEC}" >"${TEST_ROOT}/dns-trojan.json"
dockerGenerateSubscription "${TEST_ROOT}/dns-trojan.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "${TROJAN_URI//@\[2001:db8::1\]/@proxy.example.com}" ]] ||
    fail 'Trojan 域名入口链接不精确'

# password 不作为统计 ID；两核心必须共享 UUID 额度且保留受管 TLS。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-trojan-${core}.json"
    jq -e --arg core "${core}" '
      if $core == "xray" then
        all(.inbounds[] | select(.protocol == "trojan"); .settings.clients == [] and .streamSettings.security == "tls")
      else all(.inbounds[] | select(.type == "trojan"); .users == [] and .tls.enabled) end
    ' "${TEST_ROOT}/quota-trojan-${core}.json" >/dev/null || fail "${core}: Trojan 未执行共享额度"
    enabled=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
    dockerTrafficRender "${core}" "${base}" "${enabled}" >"${TEST_ROOT}/enabled-trojan-${core}.json"
    cmp -s "${TEST_ROOT}/enabled-trojan-${core}.json" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" ||
        fail "${core}: Trojan 解除额度改变账号或 TLS"
done
# 生产端口检查间接调用夹具函数；同端口 UDP 不应误判为 TCP。
# shellcheck disable=SC2329
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 32443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    if dockerConfigurePortsAvailable "${TROJAN_SPEC}" 2>/dev/null; then fail 'Trojan 漏检 TCP 占用'; fi
    dockerCurrentOwnsPort() { [[ "$1" == 32443 && "$2" == tcp ]]; }
    dockerConfigurePortsAvailable "${TROJAN_SPEC}" || fail '自有 Trojan TCP 监听不能复用'
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 32443 ]]; }
    dockerConfigurePortsAvailable "${TROJAN_SPEC}" || fail 'Trojan 错误拒绝同端口 UDP 监听'
)
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.listener_id == "entry-trojan") | .public_port) = 32445' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-trojan.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-trojan.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "Trojan 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Trojan 失败恢复改变证书、账号、配置或累计流量'
IMAGE_DIGEST=$(printf '8%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'Trojan 双核心更新失败'
runRead 0 trojan-updated-links dockerProtocolCommand links entry-trojan
[[ "$(<"${STDOUT}")" == "${TROJAN_URI}" ]] || fail '更新改变 Trojan 链接'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'Trojan 双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Trojan 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Trojan 回归遗留部署锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail 'Trojan 回归遗留候选'
printf 'docker-trojan-regression-ok\n'
