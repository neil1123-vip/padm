#!/usr/bin/env bash
set -euo pipefail

# 串接已有完整协议基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/shadowsocks.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
TUIC_SPEC="${TEST_ROOT}/tuic.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .core.protocols[0] |= (del(.hy2) | .id = 31 | .listener_id = "entry-tuic" |
    .public_port = 31443 | .name = "TUIC:test" |
    .tuic = {domain:"ws.example.com",congestion_control:"cubic",
      auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false})
' "${HY2_SPEC}" >"${TUIC_SPEC}"
dockerConfigureSpecValidate "${TUIC_SPEC}" || fail 'TUIC 有效合同被拒绝'

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = null' \
    '.core.protocols[0].tuic.domain = "other.example.com"' \
    'del(.core.protocols[0].tuic)' \
    '.core.protocols[0].tuic = null' \
    '.core.protocols[0].tuic.extra = true' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].hy2 = {domain:"ws.example.com",bandwidth_mode:"bbr",
      up_mbps:100,down_mbps:50,obfs:null,masquerade:""}' \
    '.core.protocols[0].tuic.congestion_control = "reno"' \
    '.core.protocols[0].tuic.congestion_control += "\n"' \
    '.core.protocols[0].tuic.zero_rtt_handshake = "false"' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].public_port = 10087' \
    '.subscription.enabled = true' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${TUIC_SPEC}" >"${TEST_ROOT}/invalid-tuic.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-tuic.json" 2>/dev/null; then
        fail "TUIC 接受非法合同: ${mutation}"
    fi
done
for field in domain congestion_control auth_timeout heartbeat zero_rtt_handshake; do
    # jq 变量由 --arg 传入，不使用 Shell 展开。
    # shellcheck disable=SC2016
    for mutation in 'del(.core.protocols[0].tuic[$field])' \
        '.core.protocols[0].tuic[$field] = null'; do
        jq --arg field "${field}" "${mutation}" "${TUIC_SPEC}" >"${TEST_ROOT}/invalid-tuic.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-tuic.json" 2>/dev/null; then
            fail "TUIC 接受缺失 ${field}: ${mutation}"
        fi
    done
done
for field in auth_timeout heartbeat; do
    for value in '' 0s 01s 1.5s 1000000s -1s 1d 1 '1s2m' $'3s\n'; do
        jq --arg field "${field}" --arg value "${value}" \
            '.core.protocols[0].tuic[$field] = $value' \
            "${TUIC_SPEC}" >"${TEST_ROOT}/invalid-tuic.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-tuic.json" 2>/dev/null; then
            fail "TUIC 接受非法 ${field}: ${value}"
        fi
    done
    for value in 1ms 999999s 1m 1h; do
        jq --arg field "${field}" --arg value "${value}" \
            '.core.protocols[0].tuic[$field] = $value' \
            "${TUIC_SPEC}" >"${TEST_ROOT}/duration-tuic.json"
        dockerConfigureSpecValidate "${TEST_ROOT}/duration-tuic.json" ||
            fail "TUIC 拒绝有效 ${field}: ${value}"
    done
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${TUIC_SPEC}" >"${TEST_ROOT}/invalid-tuic.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-tuic.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 TUIC"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TUIC_SPEC}" || fail '当前 bundle 拒绝 TUIC'
for mutation in \
    '(.protocols[] | select(.id == 31) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 31))' \
    '(.protocols[] | select(.id == 31) | .cores) = ["xray"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TUIC_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 TUIC: ${mutation}"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TUIC_SPEC}" 2>/dev/null; then
    fail '旧规格 bundle 接受 TUIC'
fi

TUIC_URI="tuic://${UUID}:${UUID}@[2001:db8::1]:31443?congestion_control=cubic&alpn=h3&sni=ws.example.com&udp_relay_mode=native&allow_insecure=0#TUIC%3Atest"
for algorithm in cubic new_reno bbr; do
    jq --arg algorithm "${algorithm}" '.core.protocols[0].tuic |=
      (.congestion_control = $algorithm | .zero_rtt_handshake = true)' \
        "${TUIC_SPEC}" >"${TEST_ROOT}/algorithm-tuic.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/algorithm-tuic.json"
    dockerGenerateSingBoxConfig "${TEST_ROOT}/algorithm-tuic.json" "${TEST_ROOT}/generated-tuic.json"
    jq -e --arg uuid "${UUID}" --arg algorithm "${algorithm}" '
      .inbounds[0] | .type == "tuic" and .congestion_control == $algorithm and
      .users == [{name:$uuid,uuid:$uuid,password:$uuid}] and
      .auth_timeout == "3s" and .heartbeat == "10s" and .zero_rtt_handshake == true and
      .tls == {enabled:true,server_name:"ws.example.com",alpn:["h3"],
        certificate_path:"/etc/padm/secrets/tls/ws.example.com.crt",
        key_path:"/etc/padm/secrets/tls/ws.example.com.key"}
    ' "${TEST_ROOT}/generated-tuic.json" >/dev/null || fail "TUIC ${algorithm} 配置生成错误"
    jq '.subscription.enabled = true' "${TEST_ROOT}/algorithm-tuic.json" >"${TEST_ROOT}/uri-tuic.json"
    dockerGenerateSubscription "${TEST_ROOT}/uri-tuic.json" "${STDOUT}"
    [[ "$(<"${STDOUT}")" == "${TUIC_URI/congestion_control=cubic/congestion_control=${algorithm}}" ]] ||
        fail "TUIC ${algorithm} URI 不精确或包含服务端专用参数"
done
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "xray" | .subscription.enabled = true |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${TUIC_SPEC}" >"${TEST_ROOT}/published-tuic.json"
newState tuic-published "${TEST_ROOT}/published-tuic.json"
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${TUIC_URI}"$'\n'"${WS_URI}" ]] ||
    fail 'WS 发布没有精确包含 TUIC 与 WS 链接'

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
    ' "${TUIC_SPEC}" >"${TEST_ROOT}/topology-tuic.json"
    newState "tuic-${topology}" "${TEST_ROOT}/topology-tuic.json"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:31443:31443/udp","[::]:31443:31443/udp"] and
      any(.services["sing-box"].volumes[];
        .target == "/etc/padm/secrets/tls" and .read_only == true) and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: TUIC UDP 双栈、TLS 挂载或 Nginx 拓扑错误"
    jq -e '[.listeners[] | select(.listener_id == "entry-tuic")] |
      length == 1 and .[0].service == "sing-box" and .[0].transport == "udp" and
      .[0].public_port == 31443 and .[0].container_port == 31443 and
      .[0].address_families == ["ipv4","ipv6"]' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail "${topology}: TUIC UDP 监听错误"
    dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: TUIC 部署基线不匹配"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" '
          any(.inbounds[]; .type == "tuic" and .tag == "entry-tuic" and .listen_port == 31443 and
            .users == [{name:$uuid,uuid:$uuid,password:$uuid}] and
            .congestion_control == "cubic" and .auth_timeout == "3s" and
            .heartbeat == "10s" and .zero_rtt_handshake == false)
        ' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/${file}" >/dev/null ||
            fail "${topology}: TUIC ${file} 账号或参数错误"
    done
done
runRead 0 tuic-links dockerProtocolCommand links entry-tuic
[[ "$(<"${STDOUT}")" == "${TUIC_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'TUIC 单链接不精确或混入额外输出'
runRead 0 tuic-list dockerProtocolCommand list
grep -qxF 'entry-tuic  sing-box  TUIC  [2001:db8::1]:31443  [ipv4,ipv6]  TUIC:test' "${STDOUT}" ||
    fail '概览没有 TUIC 标签或入口'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'TUIC 概览暴露 UUID/密码'
cp "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" "${TEST_ROOT}/saved-tuic-core.json"
for mutation in \
    '(.inbounds[] | select(.type == "tuic") | .users[0].uuid) = "22222222-2222-4222-8222-222222222222"' \
    '(.inbounds[] | select(.type == "tuic") | .users[0].password) = "changed-password"' \
    '(.inbounds[] | select(.type == "tuic") | .users[0].name) = "changed-account"' \
    '(.inbounds[] | select(.type == "tuic") | .congestion_control) = "bbr"' \
    '(.inbounds[] | select(.type == "tuic") | .auth_timeout) = "4s"' \
    '(.inbounds[] | select(.type == "tuic") | .heartbeat) = "11s"' \
    '(.inbounds[] | select(.type == "tuic") | .zero_rtt_handshake) = true'; do
    jq "${mutation}" "${TEST_ROOT}/saved-tuic-core.json" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    runRead 15 tuic-core-drift dockerProtocolCommand links entry-tuic
done
cp "${TEST_ROOT}/saved-tuic-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/saved-tuic-deployment.json"
jq '(.listeners[] | select(.listener_id == "entry-tuic") | .transport) = "tcp"' \
    "${TEST_ROOT}/saved-tuic-deployment.json" >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
runRead 15 tuic-transport-drift dockerProtocolCommand links entry-tuic
cp "${TEST_ROOT}/saved-tuic-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
jq '.core.protocols[0].server = "proxy.example.com" | .subscription.enabled = true' \
    "${TUIC_SPEC}" >"${TEST_ROOT}/dns-tuic.json"
dockerGenerateSubscription "${TEST_ROOT}/dns-tuic.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "${TUIC_URI//@\[2001:db8::1\]/@proxy.example.com}" ]] ||
    fail 'TUIC 域名入口链接不精确'

# 同 UUID 跨核心共享额度，空 users 不得留下 TUIC 认证账号。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    accounts=$(dockerTrafficAccounts "${core}")
    jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
        fail "${core}: TUIC 重建独立统计账号"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-tuic-${core}.json"
done
jq -e --arg uuid "${UUID}" 'all(.inbounds[] | select(.type == "tuic"); .users == []) and
  .experimental.v2ray_api.stats.users == [$uuid]' "${TEST_ROOT}/quota-tuic-sing-box.json" >/dev/null ||
    fail 'TUIC 额度耗尽后保留可用账号或丢失统计身份'
jq -e 'all(.inbounds[] | select(.protocol == "vless"); .settings.clients == [])' \
    "${TEST_ROOT}/quota-tuic-xray.json" >/dev/null || fail 'TUIC 同 UUID 未对 Xray 执行额度'
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender sing-box "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" "${quota}" \
    >"${TEST_ROOT}/enabled-tuic.json"
jq -e --arg uuid "${UUID}" 'any(.inbounds[]; .type == "tuic" and
  .users == [{name:$uuid,uuid:$uuid,password:$uuid}])' "${TEST_ROOT}/enabled-tuic.json" >/dev/null ||
    fail 'TUIC 解除额度后未恢复原始账号'
# 生产端口检查会间接调用下面的夹具函数。
# shellcheck disable=SC2329
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 31443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    dockerConfigurePortsAvailable "${TUIC_SPEC}" || fail 'TUIC 错误拒绝同端口 TCP 监听'
    dockerUdpPortIsListening() { [[ "$1" == 31443 ]]; }
    if dockerConfigurePortsAvailable "${TUIC_SPEC}" 2>/dev/null; then fail 'TUIC 漏检 UDP 占用'; fi
    dockerCurrentOwnsPort() { [[ "$1" == 31443 && "$2" == udp ]]; }
    dockerConfigurePortsAvailable "${TUIC_SPEC}" || fail '自有 TUIC UDP 监听不能复用'
)

before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 31) | .public_port) = 31444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-tuic.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-tuic.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "TUIC 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'TUIC 失败恢复改变证书、账号、配置或累计流量'
IMAGE_DIGEST=$(printf '7%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'TUIC 混合双核心更新失败'
runRead 0 tuic-updated-links dockerProtocolCommand links entry-tuic
[[ "$(<"${STDOUT}")" == "${TUIC_URI}" ]] || fail '更新改变 TUIC 链接'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'TUIC 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'TUIC 更新回滚改变配置或统计状态'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'TUIC 回归遗留部署锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail 'TUIC 回归遗留候选'
printf 'docker-tuic-regression-ok\n'
