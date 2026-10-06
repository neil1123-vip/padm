#!/usr/bin/env bash
set -euo pipefail

# 完整协议基线只串接一次，CI 不重复运行前置入口。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/trojan.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
VMESS_SPEC="${TEST_ROOT}/vmess.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .subscription.enabled = false |
  .core.protocols = [.core.protocols[] | select(.id == 21) |
    .id = 22 | .listener_id = "entry-vmess" | .server = "2001:db8::1" |
    .address_families = ["ipv4","ipv6"] | .name = "VMess:test"]
' "${TEST_ROOT}/v3.json" >"${VMESS_SPEC}"
dockerConfigureSpecValidate "${VMESS_SPEC}" || fail 'VMess 有效合同被拒绝'
for mutation in \
    '.tls = null' \
    '.core.type = "sing-box" | .core.protocols[0].core = "sing-box"' \
    '.core.protocols[0].websocket.domain = "other.example.com"' \
    '.core.protocols[0].websocket.domain += "\n" | .tls.domain = .core.protocols[0].websocket.domain' \
    'del(.core.protocols[0].websocket)' \
    'del(.core.protocols[0].websocket.backend_port)' \
    'del(.core.protocols[0].websocket.tls_port)' \
    '.core.protocols[0].websocket.path = "bad/path"' \
    '.core.protocols[0].websocket.path += "\n"' \
    '.core.protocols[0].websocket.extra = true' \
    '.core.protocols[0].alterId = 1' \
    '.core.protocols[0].extra = true' \
    '.core.protocols[0].uuid += "\n"' \
    '.core.protocols[0].websocket.backend_port = 10085' \
    '.core.protocols[0].websocket.tls_port = 8080' \
    '.subscription.enabled = true'; do
    jq "${mutation}" "${VMESS_SPEC}" >"${TEST_ROOT}/invalid-vmess.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-vmess.json" 2>/dev/null; then
        fail "VMess 接受非法合同: ${mutation}"
    fi
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id, .websocket.backend_port, .websocket.tls_port) else . end)' \
        "${VMESS_SPEC}" >"${TEST_ROOT}/invalid-vmess.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-vmess.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 VMess"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${VMESS_SPEC}" || fail '当前 bundle 拒绝 VMess'
for mutation in \
    '(.protocols[] | select(.id == 22) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 22))' \
    '(.protocols[] | select(.id == 22) | .cores) = ["sing-box"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${VMESS_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 VMess: ${mutation}"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${VMESS_SPEC}" 2>/dev/null; then
    fail '旧规格 bundle 接受 VMess'
fi
VMESS_JSON=$(jq -cn --arg uuid "${UUID}" '
  {v:"2",ps:"VMess:test",add:"2001:db8::1",port:"24444",id:$uuid,aid:"0",scy:"auto",
   net:"ws",type:"none",host:"ws.example.com",path:"/abcdefghws",tls:"tls",sni:"ws.example.com"}')
VMESS_URI="vmess://$(printf '%s' "${VMESS_JSON}" | base64 | tr -d '\n')"

# 新入口与已有 VLESS 共用 Nginx，但单 VMess 不开放 HTTPS 发布。
newState vmess-single "${VMESS_SPEC}"
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
    fail 'VMess 部署基线不匹配'
jq -e '.compose.profiles == ["core-xray","nginx"] and .core.protocol_ids == [22] and
  .listeners == [{listener_id:"entry-vmess",service:"nginx",public_port:24444,
    container_port:8443,transport:"tcp",address_families:["ipv4","ipv6"]}]' \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail 'VMess 监听拓扑错误'
jq -e '.services.xray.ports == [] and
  .services.nginx.ports == ["0.0.0.0:24444:8443/tcp","[::]:24444:8443/tcp"] and
  any(.services.nginx.volumes[]; .target == "/etc/padm/secrets/tls" and .read_only) and
  (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
    fail 'VMess TLS 挂载或端口错误'
for file in users.base config.json; do
    jq -e --arg uuid "${UUID}" --arg file "${file}" '
      any(.inbounds[]; .tag == "entry-vmess" and .protocol == "vmess" and
        .listen == "0.0.0.0" and .port == 31297 and
        .settings.clients == [{id:$uuid,email:(if $file == "users.base" then "VMess:test" else $uuid end),alterId:0}] and
        .streamSettings == {network:"ws",security:"none",wsSettings:{path:"/abcdefghws"}})' \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/${file}" >/dev/null || fail "VMess ${file} 配置错误"
done
grep -qF 'location = /abcdefghws {' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
    fail 'Nginx 漏掉 VMess WS 路径'
grep -qF 'proxy_pass http://xray:31297;' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
    fail 'Nginx 漏掉 VMess 内部端口'
dockerTrafficAccounts xray | jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' >/dev/null ||
    fail 'VMess 未复用 UUID 账号'
runRead 0 vmess-links dockerProtocolCommand links entry-vmess
[[ "$(<"${STDOUT}")" == "${VMESS_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
    fail 'VMess Base64 JSON 链接不精确或混入额外输出'
printf '%s' "${VMESS_URI#vmess://}" | base64 -d | jq -e --arg uuid "${UUID}" '
  . == {v:"2",ps:"VMess:test",add:"2001:db8::1",port:"24444",id:$uuid,aid:"0",scy:"auto",
    net:"ws",type:"none",host:"ws.example.com",path:"/abcdefghws",tls:"tls",sni:"ws.example.com"}' >/dev/null ||
    fail 'VMess 分享字段或 aid 错误'
runRead 0 vmess-list dockerProtocolCommand list
grep -qxF 'entry-vmess  xray  VMess WS TLS  [2001:db8::1]:24444  [ipv4,ipv6]  VMess:test' \
    "${STDOUT}" || fail 'VMess 概览标签错误'
! grep -Fq "${UUID}" "${STDOUT}" || fail 'VMess 概览暴露 UUID'
cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${TEST_ROOT}/saved-vmess.json"
for field in uuid aid path; do
    jq --arg field "${field}" '
      .inbounds |= map(if .protocol == "vmess" then
        if $field == "uuid" then .settings.clients[0].id = "22222222-2222-4222-8222-222222222222"
        elif $field == "aid" then .settings.clients[0].alterId = 1
        else .streamSettings.wsSettings.path = "/changed" end else . end)' \
        "${TEST_ROOT}/saved-vmess.json" >"${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    runRead 15 "vmess-${field}-drift" dockerProtocolCommand links entry-vmess
done
cp "${TEST_ROOT}/saved-vmess.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" "${TEST_ROOT}/saved-vmess-nginx.conf"
sed 's|/abcdefghws|/changedws|' "${TEST_ROOT}/saved-vmess-nginx.conf" \
    >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
runRead 15 vmess-nginx-drift dockerProtocolCommand links entry-vmess
cp "${TEST_ROOT}/saved-vmess-nginx.conf" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${quota}" \
    >"${TEST_ROOT}/quota-vmess.json"
jq -e 'all(.inbounds[] | select(.protocol == "vmess"); .settings.clients == [] and
  .streamSettings.network == "ws")' "${TEST_ROOT}/quota-vmess.json" >/dev/null || fail 'VMess 未执行额度'
enabled=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${enabled}" \
    >"${TEST_ROOT}/enabled-vmess.json"
cmp -s "${TEST_ROOT}/enabled-vmess.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" ||
    fail 'VMess 解除额度改变用户或 WS 配置'
jq --slurpfile ws "${TEST_ROOT}/v3.json" '
  .subscription.enabled = true | .core.protocols += [
    $ws[0].core.protocols[] | select(.id == 21) | .public_port = 24445 |
    .websocket += {path:"vlessabc",backend_port:31298,tls_port:8444}]
' "${VMESS_SPEC}" >"${TEST_ROOT}/published-vmess.json"
host_integration='.host_integrations = [{type:"fail2ban",profile:"net-fail2ban",
  firewall_rules:["DOCKER-USER"],devices:[],schedules:[],
  settings:{log_file:"access.log",ports:[24445],max_retry:6,find_time:600,ban_time:3600}}]'
jq "${host_integration} | .core.protocols |= map(select(.id == 21))" \
    "${TEST_ROOT}/published-vmess.json" >"${TEST_ROOT}/host-vless.json"
dockerConfigureSpecValidate "${TEST_ROOT}/host-vless.json" || fail '有效 VLESS Fail2ban 基线被拒绝'
jq "${host_integration}" "${TEST_ROOT}/published-vmess.json" >"${TEST_ROOT}/invalid-vmess.json"
if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-vmess.json" 2>/dev/null; then
    fail '混合 VLESS/VMess 接受宿主 Fail2ban 集成'
fi
for field in backend_port tls_port; do
    jq --arg field "${field}" '
      .core.protocols[1].websocket[$field] = .core.protocols[0].websocket[$field]
    ' "${TEST_ROOT}/published-vmess.json" >"${TEST_ROOT}/invalid-vmess.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-vmess.json" 2>/dev/null; then
        fail "混合 VLESS/VMess 接受重复 ${field}"
    fi
done
newState vmess-published "${TEST_ROOT}/published-vmess.json"
expected_ws=${WS_URI//:24444?/:24445?}
expected_ws=${expected_ws//abcdefghws/vlessabcws}
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == "${VMESS_URI}"$'\n'"${expected_ws}" ]] ||
    fail '混合发布未精确包含 VMess 和 VLESS'
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${quota}" \
    >"${TEST_ROOT}/quota-mixed-vmess.json"
jq -e 'all(.inbounds[] | select(.protocol == "vmess" or .protocol == "vless"); .settings.clients == [])' \
    "${TEST_ROOT}/quota-mixed-vmess.json" >/dev/null || fail 'VMess/VLESS 未共享 UUID 额度'
# 两类 WS 共用端口池；删最后 VLESS 只关发布，不撤销 VMess 的 TLS。
cp "${TEST_ROOT}/published-vmess.json" "${TEST_ROOT}/vmess-edit-draft.json"
printf '9\nentry-vmess\n1\n24447\n8\n' |
    dockerEditFields "${TEST_ROOT}/vmess-edit-draft.json" >"${STDOUT}" || fail '混合 WS 复制失败'
jq -e '.core.protocols[2] | .id == 22 and .websocket.backend_port == 31299 and .websocket.tls_port == 8445' \
    "${TEST_ROOT}/vmess-edit-draft.json" >/dev/null || fail '混合 WS 复制复用了已有内部端口'
printf '10\nvless-ws\n8\n' |
    dockerEditFields "${TEST_ROOT}/vmess-edit-draft.json" >"${STDOUT}" || fail '删除最后 VLESS 失败'
jq -e '.tls.domain == "ws.example.com" and .subscription.enabled == false and
  all(.core.protocols[]; .id == 22)' "${TEST_ROOT}/vmess-edit-draft.json" >/dev/null ||
    fail '删除最后 VLESS 撤销了 VMess TLS 或保留发布'
jq --slurpfile before "${TEST_ROOT}/v3.json" '
  .core.protocols += [$before[0].core.protocols[] | select(.id == 1)]' \
    "${TEST_ROOT}/vmess-edit-draft.json" >"${TEST_ROOT}/vmess-final-tls.json"
printf '10\nentry-1\n10\nentry-vmess\n8\n' |
    dockerEditFields "${TEST_ROOT}/vmess-final-tls.json" >"${STDOUT}" || fail '删除最后 VMess TLS 入口失败'
jq -e '.tls == null and .subscription.enabled == false and
  (.core.protocols | length) == 1 and .core.protocols[0].id == 1' \
    "${TEST_ROOT}/vmess-final-tls.json" >/dev/null || fail '删除最后 VMess 未撤销 TLS 规格引用'
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 22) | .public_port) = 24446' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-vmess.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-vmess.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 && "$(liveSnapshot)" == "${before}" ]] ||
    fail "VMess 失败事务返回 ${actual} 或改变了配置"
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'VMess 回归遗留部署锁'
printf 'docker-vmess-regression-ok\n'
