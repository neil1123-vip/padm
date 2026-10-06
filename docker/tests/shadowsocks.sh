#!/usr/bin/env bash
set -euo pipefail

# 串接已有完整协议基线，CI 只运行本入口，避免重复回归。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/naive.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
# 独立记录完整 Docker 参数，避免只读检查清空事件日志后漏掉先前事务。
docker() { printf '%s\n' "$@" >>"${TEST_ROOT}/shadowsocks-docker-argv"; command docker "$@"; }
SS_SPEC="${TEST_ROOT}/shadowsocks.json"
SS_SERVER_PASSWORD='AAECAwQFBgcICQoLDA0ODw=='
SS_USER_PASSWORD='+/v7+/v7+/v7+/v7+/v7+w=='
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --arg serverPassword "${SS_SERVER_PASSWORD}" --arg userPassword "${SS_USER_PASSWORD}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .tls = null |
  .core.protocols[0] |= (del(.naive) | .id = 30 | .listener_id = "entry-shadowsocks" |
    .server = "2001:db8::1" | .public_port = 30443 | .name = "Shadowsocks:2022" |
    .shadowsocks = {method:"2022-blake3-aes-128-gcm",
      server_password:$serverPassword,user_password:$userPassword})
' "${NAIVE_SPEC}" >"${SS_SPEC}"
dockerConfigureSpecValidate "${SS_SPEC}" || fail 'Shadowsocks 有效合同被拒绝'

for mutation in \
    '.core.protocols[0].core = "xray" | .core.type = "xray"' \
    '.tls = {domain:"ws.example.com"}' \
    'del(.core.protocols[0].shadowsocks)' \
    '.core.protocols[0].shadowsocks = null' \
    'del(.core.protocols[0].shadowsocks.method)' \
    '.core.protocols[0].shadowsocks.method = "2022-blake3-aes-256-gcm"' \
    '.core.protocols[0].shadowsocks.method = "aes-128-gcm"' \
    '.core.protocols[0].shadowsocks.method += "\n"' \
    '.core.protocols[0].shadowsocks.extra = true' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].network = "tcp"' \
    '.core.protocols[0].naive = {domain:"ws.example.com"}' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].public_port = 10087' \
    '.subscription.enabled = true' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${SS_SPEC}" >"${TEST_ROOT}/invalid-shadowsocks.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-shadowsocks.json" 2>/dev/null; then
        fail "Shadowsocks 接受非法合同: ${mutation}"
    fi
done
for field in server_password user_password; do
    for mutation in \
        'del(.core.protocols[0].shadowsocks[$field])' \
        '.core.protocols[0].shadowsocks[$field] = null' \
        '.core.protocols[0].shadowsocks[$field] = 123' \
        '.core.protocols[0].shadowsocks[$field] = ""' \
        '.core.protocols[0].shadowsocks[$field] = ("A"*20)' \
        '.core.protocols[0].shadowsocks[$field] = (("A"*23)+"=")' \
        '.core.protocols[0].shadowsocks[$field] |= rtrimstr("=")' \
        '.core.protocols[0].shadowsocks[$field] |= sub("w==$"; "x==")' \
        '.core.protocols[0].shadowsocks[$field] = ("_"+("A"*20)+"A==")' \
        '.core.protocols[0].shadowsocks[$field] += "\n"' \
        '.core.protocols[0].shadowsocks[$field] += "\u0000"'; do
        jq --arg field "${field}" "${mutation}" "${SS_SPEC}" >"${TEST_ROOT}/invalid-shadowsocks.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-shadowsocks.json" 2>/dev/null; then
            fail "Shadowsocks 接受非法 ${field}: ${mutation}"
        fi
    done
done
# 16 字节密钥最后一组只能使用四种 canonical padding 位。
for tail in A Q g w; do
    jq --arg tail "${tail}" '.core.protocols[0].shadowsocks.server_password = (("A"*21)+$tail+"==")' \
        "${SS_SPEC}" >"${TEST_ROOT}/canonical-shadowsocks.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/canonical-shadowsocks.json" ||
        fail "Shadowsocks 拒绝有效 Base64 padding 位: ${tail}"
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id) else . end)' \
        "${SS_SPEC}" >"${TEST_ROOT}/invalid-shadowsocks.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-shadowsocks.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 Shadowsocks"
    fi
done

cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${SS_SPEC}" || fail '当前 bundle 拒绝 Shadowsocks'
for mutation in \
    '(.protocols[] | select(.id == 30) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 30))' \
    '(.protocols[] | select(.id == 30) | .cores) = ["xray"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${SS_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 Shadowsocks: ${mutation}"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${SS_SPEC}" 2>/dev/null; then
    fail '旧规格 bundle 接受 Shadowsocks'
fi

SS_URI="ss://2022-blake3-aes-128-gcm:AAECAwQFBgcICQoLDA0ODw%3D%3D%3A%2B%2Fv7%2B%2Fv7%2B%2Fv7%2B%2Fv7%2B%2Fv7%2Bw%3D%3D@[2001:db8::1]:30443#Shadowsocks%3A2022"
URI_SPEC="${TEST_ROOT}/uri-shadowsocks.json"
jq '.subscription.enabled = true' "${SS_SPEC}" >"${URI_SPEC}"
# 生产生成器只能通过文件读取新密钥，不能把新密钥放进 jq 或 Docker argv。
(
    jq() { printf '%s\n' "$@" >>"${TEST_ROOT}/shadowsocks-jq-argv"; command jq "$@"; }
    dockerGenerateSingBoxConfig "${SS_SPEC}" "${TEST_ROOT}/generated-shadowsocks.json"
    dockerGenerateSubscription "${URI_SPEC}" "${STDOUT}"
)
[[ "$(<"${STDOUT}")" == "${SS_URI}" ]] || fail 'Shadowsocks SIP002 URI 编码不精确'
for secret in "${SS_SERVER_PASSWORD}" "${SS_USER_PASSWORD}"; do
    ! grep -Fq "${secret}" "${TEST_ROOT}/shadowsocks-jq-argv" ||
        fail 'Shadowsocks 生成器把新密钥放入 argv'
done
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "xray" | .subscription.enabled = true | .tls = $ws[0].tls |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${SS_SPEC}" >"${TEST_ROOT}/published-shadowsocks.json"
newState shadowsocks-published "${TEST_ROOT}/published-shadowsocks.json"
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${SS_URI}"$'\n'"${WS_URI}" ]] ||
    fail 'WS 发布没有精确包含 Shadowsocks 与 WS 链接'
jq -e '(.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"]' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail 'Shadowsocks 与 WS 发布拓扑错误'

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
    ' "${SS_SPEC}" >"${TEST_ROOT}/topology-shadowsocks.json"
    newState "shadowsocks-${topology}" "${TEST_ROOT}/topology-shadowsocks.json"
    jq -e '(.services["sing-box"].ports | sort) ==
      (["0.0.0.0:30443:30443/tcp","[::]:30443:30443/tcp",
        "0.0.0.0:30443:30443/udp","[::]:30443:30443/udp"] | sort) and
      all(.services["sing-box"].volumes[]; .target != "/etc/padm/secrets/tls") and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${topology}: Shadowsocks TCP/UDP 双栈或无 TLS 拓扑错误"
    jq -e '[.listeners[] | select(.listener_id == "entry-shadowsocks") |
      {service,public_port,container_port,transport,address_families}] | sort_by(.transport) ==
      [{service:"sing-box",public_port:30443,container_port:30443,transport:"tcp",
        address_families:["ipv4","ipv6"]},
       {service:"sing-box",public_port:30443,container_port:30443,transport:"udp",
        address_families:["ipv4","ipv6"]}]' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail "${topology}: Shadowsocks 未记录同入口的 TCP 与 UDP 监听"
    dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ||
        fail "${topology}: Shadowsocks 双传输监听合同被拒绝"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${topology}: Shadowsocks 部署基线不匹配"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" --arg serverPassword "${SS_SERVER_PASSWORD}" \
            --arg userPassword "${SS_USER_PASSWORD}" '
          .inbounds[] | select(.type == "shadowsocks") |
          .tag == "entry-shadowsocks" and .listen_port == 30443 and
          .method == "2022-blake3-aes-128-gcm" and .password == $serverPassword and
          .users == [{name:$uuid,password:$userPassword}] and
          (has("network") or has("tls") | not)' \
            "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/${file}" >/dev/null ||
            fail "${topology}: Shadowsocks ${file} 的方法、账号或双传输生成错误"
    done
done
runRead 0 shadowsocks-links dockerProtocolCommand links entry-shadowsocks
[[ "$(<"${STDOUT}")" == "${SS_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'Shadowsocks 单链接不精确或混入额外输出'
runRead 0 shadowsocks-list dockerProtocolCommand list
grep -qxF 'entry-shadowsocks  sing-box  Shadowsocks  [2001:db8::1]:30443  [ipv4,ipv6]  Shadowsocks:2022' "${STDOUT}" ||
    fail '概览没有 Shadowsocks 标签或入口'
for secret in "${UUID}" "${SS_SERVER_PASSWORD}" "${SS_USER_PASSWORD}"; do
    ! grep -Fq "${secret}" "${STDOUT}" || fail 'Shadowsocks 概览暴露账号或密钥'
done
cp "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" "${TEST_ROOT}/saved-shadowsocks-core.json"
for mutation in \
    '(.inbounds[] | select(.type == "shadowsocks") | .password) = "AAAAAAAAAAAAAAAAAAAAAA=="' \
    '(.inbounds[] | select(.type == "shadowsocks") | .users[0].password) = "AAAAAAAAAAAAAAAAAAAAAA=="' \
    '(.inbounds[] | select(.type == "shadowsocks") | .users[0].name) = "changed-account"' \
    '(.inbounds[] | select(.type == "shadowsocks") | .network) = "tcp"'; do
    jq "${mutation}" "${TEST_ROOT}/saved-shadowsocks-core.json" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
    runRead 15 shadowsocks-core-drift dockerProtocolCommand links entry-shadowsocks
done
cp "${TEST_ROOT}/saved-shadowsocks-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json"
cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${TEST_ROOT}/saved-shadowsocks-deployment.json"
jq '.listeners += [.listeners[] | select(.listener_id == "entry-shadowsocks" and .transport == "udp")]' \
    "${TEST_ROOT}/saved-shadowsocks-deployment.json" >"${TEST_ROOT}/duplicate-shadowsocks-deployment.json"
if dockerDeploymentFileValidate "${TEST_ROOT}/duplicate-shadowsocks-deployment.json"; then
    fail 'Shadowsocks 接受重复的 listener_id/transport'
fi
for mutation in \
    '.listeners |= map(select(.listener_id != "entry-shadowsocks" or .transport != "udp"))' \
    '.listeners += [.listeners[] | select(.listener_id == "entry-shadowsocks" and .transport == "udp")]'; do
    jq "${mutation}" "${TEST_ROOT}/saved-shadowsocks-deployment.json" \
        >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    runRead 15 shadowsocks-transport-drift dockerProtocolCommand links entry-shadowsocks
done
cp "${TEST_ROOT}/saved-shadowsocks-deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/saved-shadowsocks-compose.json"
jq '.services["sing-box"].ports |= map(select(endswith("/udp") | not))' \
    "${TEST_ROOT}/saved-shadowsocks-compose.json" >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
runRead 15 shadowsocks-udp-mapping-drift dockerProtocolCommand links entry-shadowsocks
cp "${TEST_ROOT}/saved-shadowsocks-compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
jq '.core.protocols[0].server = "proxy.example.com" | .subscription.enabled = true' \
    "${SS_SPEC}" >"${TEST_ROOT}/dns-shadowsocks.json"
dockerGenerateSubscription "${TEST_ROOT}/dns-shadowsocks.json" "${STDOUT}"
[[ "$(<"${STDOUT}")" == "${SS_URI//@\[2001:db8::1\]/@proxy.example.com}" ]] ||
    fail 'Shadowsocks 域名入口链接不精确'

# 同 UUID 跨核心共享额度；空 users 必须移除 SS 入站，避免退回 server key 单用户模式。
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    base="${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base"
    accounts=$(dockerTrafficAccounts "${core}")
    jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' <<<"${accounts}" >/dev/null ||
        fail "${core}: Shadowsocks 重建独立统计账号"
    dockerTrafficRender "${core}" "${base}" "${quota}" >"${TEST_ROOT}/quota-shadowsocks-${core}.json"
done
jq -e --arg uuid "${UUID}" 'all(.inbounds[]; .type != "shadowsocks") and
  .experimental.v2ray_api.stats.users == [$uuid]' "${TEST_ROOT}/quota-shadowsocks-sing-box.json" >/dev/null ||
    fail 'Shadowsocks 额度耗尽后留下可用的 server key 入站或丢失统计账号'
jq -e 'all(.inbounds[] | select(.protocol == "vless"); .settings.clients == [])' \
    "${TEST_ROOT}/quota-shadowsocks-xray.json" >/dev/null || fail 'Shadowsocks 同 UUID 未对 Xray 执行额度'
dockerGenerateSingBoxConfig "${REALITY_SPEC}" "${TEST_ROOT}/reality-for-shadowsocks.json"
jq --slurpfile reality "${TEST_ROOT}/reality-for-shadowsocks.json" '
  .inbounds += [$reality[0].inbounds[] | select(.type == "vless")]
' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" >"${TEST_ROOT}/mixed-shadowsocks-base.json"
dockerTrafficRender sing-box "${TEST_ROOT}/mixed-shadowsocks-base.json" "${quota}" \
    >"${TEST_ROOT}/mixed-shadowsocks-quota.json"
jq -e 'all(.inbounds[]; .type != "shadowsocks") and
  any(.inbounds[]; .type == "vless" and .users == [])' "${TEST_ROOT}/mixed-shadowsocks-quota.json" >/dev/null ||
    fail 'Shadowsocks 超额处理误移除其它协议入站'
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender sing-box "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" "${quota}" \
    >"${TEST_ROOT}/enabled-shadowsocks.json"
jq -e --arg uuid "${UUID}" --arg serverPassword "${SS_SERVER_PASSWORD}" --arg userPassword "${SS_USER_PASSWORD}" '
  any(.inbounds[]; .type == "shadowsocks" and .password == $serverPassword and
    .users == [{name:$uuid,password:$userPassword}] and (has("network") | not)) and
  .experimental.v2ray_api.stats.users == [$uuid]' "${TEST_ROOT}/enabled-shadowsocks.json" >/dev/null ||
    fail 'Shadowsocks 解除额度后未恢复原始密钥、账号和双传输'

# TCP、UDP 分别检查占用；仅拥有其中一个监听不能绕过另一传输的冲突。
(
    dockerCurrentOwnsPort() { return 1; }
    dockerTcpPortIsListening() { [[ "$1" == 30443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    if dockerConfigurePortsAvailable "${SS_SPEC}" 2>/dev/null; then fail 'Shadowsocks 漏检 TCP 占用'; fi
    dockerTcpPortIsListening() { return 1; }
    dockerUdpPortIsListening() { [[ "$1" == 30443 ]]; }
    if dockerConfigurePortsAvailable "${SS_SPEC}" 2>/dev/null; then fail 'Shadowsocks 漏检 UDP 占用'; fi
    dockerCurrentOwnsPort() { [[ "$1" == 30443 && "$2" == tcp ]]; }
    if dockerConfigurePortsAvailable "${SS_SPEC}" 2>/dev/null; then fail '自有 TCP 隐藏外部 UDP 占用'; fi
    dockerCurrentOwnsPort() { [[ "$1" == 30443 && "$2" == udp ]]; }
    dockerTcpPortIsListening() { [[ "$1" == 30443 ]]; }
    dockerUdpPortIsListening() { return 1; }
    if dockerConfigurePortsAvailable "${SS_SPEC}" 2>/dev/null; then fail '自有 UDP 隐藏外部 TCP 占用'; fi
    dockerCurrentOwnsPort() { [[ "$1" == 30443 && ( "$2" == tcp || "$2" == udp ) ]]; }
    dockerConfigurePortsAvailable "${SS_SPEC}" || fail '自有 Shadowsocks 双传输监听不能被复用'
)

before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 30) | .public_port) = 30444' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-shadowsocks.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-shadowsocks.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 ]] || fail "Shadowsocks 双核心失败事务返回 ${actual}，预期 14"
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Shadowsocks 失败恢复改变账号、配置或累计流量'

IMAGE_DIGEST=$(printf '6%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'Shadowsocks 混合双核心更新失败'
runRead 0 shadowsocks-updated-links dockerProtocolCommand links entry-shadowsocks
[[ "$(<"${STDOUT}")" == "${SS_URI}" ]] || fail '更新改变 Shadowsocks 链接'
dockerDeploymentFileValidate "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ||
    fail 'Shadowsocks 更新丢失双传输合同'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'Shadowsocks 混合双核心回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'Shadowsocks 更新回滚改变配置或统计状态'
for secret in "${SS_SERVER_PASSWORD}" "${SS_USER_PASSWORD}"; do
    ! grep -Fq "${secret}" "${TEST_ROOT}/shadowsocks-docker-argv" || fail 'Shadowsocks 把密钥传入 Docker argv'
done
unset -f docker
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Shadowsocks 回归遗留部署锁'
[[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 -name '.candidate.*' -print -quit)" ]] ||
    fail 'Shadowsocks 回归遗留候选'
printf 'docker-shadowsocks-regression-ok\n'
