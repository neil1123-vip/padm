#!/usr/bin/env bash
set -euo pipefail

# 只串接一次完整 VMess 基线，新增两核 HTTPUpgrade 的边界。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/vmess.sh"
dockerConfigureTestFixture
HTTPUPGRADE_SPEC="${TEST_ROOT}/httpupgrade.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .core.protocols[0] |= (.id = 23 | .listener_id = "entry-httpupgrade" |
    .name = "HTTPUpgrade:test" | .httpupgrade = (.websocket + {backend_port:31306}) |
    del(.websocket))
' "${VMESS_SPEC}" >"${HTTPUPGRADE_SPEC}"
for core in xray sing-box; do
    api_port=10085; [[ "${core}" != sing-box ]] || api_port=10087
    jq --arg core "${core}" '.core.type = $core | .core.protocols[0].core = $core' \
        "${HTTPUPGRADE_SPEC}" >"${TEST_ROOT}/valid-httpupgrade-${core}.json"
    dockerConfigureSpecValidate "${TEST_ROOT}/valid-httpupgrade-${core}.json" ||
        fail "${core}: HTTPUpgrade 有效合同被拒绝"
    for mutation in \
        '.tls = null' \
        '.core.protocols[0].httpupgrade.domain = "other.example.com"' \
        '.core.protocols[0].httpupgrade.domain += "\n" | .tls.domain = .core.protocols[0].httpupgrade.domain' \
        'del(.core.protocols[0].httpupgrade)' \
        'del(.core.protocols[0].httpupgrade.backend_port)' \
        'del(.core.protocols[0].httpupgrade.tls_port)' \
        '.core.protocols[0].httpupgrade.path = "/abcdefgh"' \
        '.core.protocols[0].httpupgrade.path = "bad/path"' \
        '.core.protocols[0].httpupgrade.path += "\n"' \
        '.core.protocols[0].httpupgrade.host = "other.example.com"' \
        '.core.protocols[0].httpupgrade.extra = true' \
        '.core.protocols[0].alterId = 1' \
        '.core.protocols[0].websocket = .core.protocols[0].httpupgrade' \
        '.core.protocols[0].uuid += "\n"' \
        ".core.protocols[0].httpupgrade.backend_port = ${api_port}" \
        '.core.protocols[0].httpupgrade.tls_port = 8080' \
        '.subscription.enabled = true' \
        '.host_integrations = [{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
          devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
        jq "${mutation}" "${TEST_ROOT}/valid-httpupgrade-${core}.json" >"${TEST_ROOT}/invalid-httpupgrade.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-httpupgrade.json" 2>/dev/null; then
            fail "${core}: HTTPUpgrade 接受非法合同: ${mutation}"
        fi
    done
done
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version = $version |
      del(.core.secondary_type) | .core.protocols |= map(del(.core) |
        if $version == 1 then del(.listener_id, .httpupgrade.backend_port, .httpupgrade.tls_port) else . end)' \
        "${HTTPUPGRADE_SPEC}" >"${TEST_ROOT}/invalid-httpupgrade.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-httpupgrade.json" 2>/dev/null; then
        fail "旧版本 ${version} 接受 HTTPUpgrade"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${HTTPUPGRADE_SPEC}" || fail '当前 bundle 拒绝 HTTPUpgrade'
for mutation in \
    '(.protocols[] | select(.id == 23) | .status) = "deferred"' \
    '.protocols |= map(select(.id != 23))' \
    '(.protocols[] | select(.id == 23) | .cores) = ["sing-box"]'; do
    jq "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/features.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${HTTPUPGRADE_SPEC}" 2>/dev/null; then
        fail "不兼容 bundle 接受 HTTPUpgrade: ${mutation}"
    fi
done
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${HTTPUPGRADE_SPEC}" 2>/dev/null; then
    fail '旧规格 bundle 接受 HTTPUpgrade'
fi
HTTPUPGRADE_JSON=$(jq -cn --arg uuid "${UUID}" '
  {v:"2",ps:"HTTPUpgrade:test",add:"2001:db8::1",port:"24444",id:$uuid,aid:"0",scy:"auto",
   net:"httpupgrade",type:"none",host:"ws.example.com",path:"/abcdefgh",tls:"tls",sni:"ws.example.com"}')
HTTPUPGRADE_URI="vmess://$(printf '%s' "${HTTPUPGRADE_JSON}" | base64 | tr -d '\n')"
for core in xray sing-box; do
    newState "httpupgrade-${core}" "${TEST_ROOT}/valid-httpupgrade-${core}.json"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${core}: HTTPUpgrade 部署基线不匹配"
    jq -e --arg core "${core}" '.compose.profiles == ["core-"+$core,"nginx"] and .core.protocol_ids == [23] and
      .listeners == [{listener_id:"entry-httpupgrade",service:"nginx",public_port:24444,
        container_port:8443,transport:"tcp",address_families:["ipv4","ipv6"]}]' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail "${core}: HTTPUpgrade 监听拓扑错误"
    jq -e --arg core "${core}" '.services[$core].ports == [] and
      .services.nginx.ports == ["0.0.0.0:24444:8443/tcp","[::]:24444:8443/tcp"] and
      (.services.nginx.depends_on | keys) == [$core] and
      any(.services.nginx.volumes[]; .target == "/etc/padm/secrets/tls" and .read_only) and
      (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${core}: HTTPUpgrade TLS 挂载、依赖或端口错误"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" --arg file "${file}" --arg core "${core}" '
          (if $file == "users.base" then "HTTPUpgrade:test" else $uuid end) as $name |
          if $core == "xray" then any(.inbounds[]; .tag == "entry-httpupgrade" and .protocol == "vmess" and
            .listen == "0.0.0.0" and .port == 31306 and
            .settings.clients == [{id:$uuid,email:$name,alterId:0}] and
            .streamSettings == {network:"httpupgrade",security:"none",
              httpupgradeSettings:{path:"/abcdefgh",host:"ws.example.com"}})
          else any(.inbounds[]; .tag == "entry-httpupgrade" and .type == "vmess" and
            .listen == "::" and .listen_port == 31306 and .users == [{uuid:$uuid,name:$name,alterId:0}] and
            .transport == {type:"httpupgrade",host:"ws.example.com",path:"/abcdefgh"} and .tls == null) end' \
            "${PADM_DOCKER_INSTALL_DIR}/config/${core}/${file}" >/dev/null ||
            fail "${core}: HTTPUpgrade ${file} 配置错误"
    done
    grep -qF 'location = /abcdefgh {' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail "${core}: Nginx 漏掉 HTTPUpgrade 精确路径"
    grep -qF "proxy_pass http://${core}:31306;" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail "${core}: Nginx upstream 核心归属错误"
    grep -qF 'proxy_set_header Host ws.example.com;' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail "${core}: HTTPUpgrade 反代 Host 未固定受管域名"
    dockerTrafficAccounts "${core}" | jq -e --arg uuid "${UUID}" 'length == 1 and .[0].account == $uuid' >/dev/null ||
        fail "${core}: HTTPUpgrade 未复用 UUID 账号"
    runRead 0 "httpupgrade-${core}-links" dockerProtocolCommand links entry-httpupgrade
    [[ "$(<"${STDOUT}")" == "${HTTPUPGRADE_URI}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
        fail "${core}: HTTPUpgrade URI 字段或输出不精确"
    runRead 0 "httpupgrade-${core}-list" dockerProtocolCommand list
    grep -qxF "entry-httpupgrade  ${core}  VMess HTTPUpgrade TLS  [2001:db8::1]:24444  [ipv4,ipv6]  HTTPUpgrade:test" \
        "${STDOUT}" || fail "${core}: HTTPUpgrade 概览错误"
    ! grep -Fq "${UUID}" "${STDOUT}" || fail "${core}: HTTPUpgrade 概览暴露 UUID"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" "${TEST_ROOT}/saved-httpupgrade.json"
    for field in uuid aid path host transport; do
        jq --arg core "${core}" --arg field "${field}" '
          .inbounds |= map(if .tag != "entry-httpupgrade" then .
            elif $core == "xray" then
              if $field == "uuid" then .settings.clients[0].id = "22222222-2222-4222-8222-222222222222"
              elif $field == "aid" then .settings.clients[0].alterId = 1
              elif $field == "path" then .streamSettings.httpupgradeSettings.path = "/changed"
              elif $field == "host" then .streamSettings.httpupgradeSettings.host = "other.example.com"
              else .streamSettings.network = "ws" end
            else
              if $field == "uuid" then .users[0].uuid = "22222222-2222-4222-8222-222222222222"
              elif $field == "aid" then .users[0].alterId = 1
              elif $field == "path" then .transport.path = "/changed"
              elif $field == "host" then .transport.host = "other.example.com"
              else .transport.type = "ws" end end)' "${TEST_ROOT}/saved-httpupgrade.json" \
            >"${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json"
        runRead 15 "httpupgrade-${core}-${field}-drift" dockerProtocolCommand links entry-httpupgrade
    done
    cp "${TEST_ROOT}/saved-httpupgrade.json" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" "${TEST_ROOT}/saved-httpupgrade-nginx.conf"
    sed 's|/abcdefgh|/changed|' "${TEST_ROOT}/saved-httpupgrade-nginx.conf" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    runRead 15 "httpupgrade-${core}-nginx-drift" dockerProtocolCommand links entry-httpupgrade
    cp "${TEST_ROOT}/saved-httpupgrade-nginx.conf" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
done
# 域名合同允许大小写；反代必须保留后端严格匹配使用的原始 Host。
jq '.tls.domain = "HttpUpgrade.Example.com" |
  .core.protocols[0].httpupgrade.domain = .tls.domain' "${HTTPUPGRADE_SPEC}" \
    >"${TEST_ROOT}/uppercase-httpupgrade.json"
dockerConfigureSpecValidate "${TEST_ROOT}/uppercase-httpupgrade.json" || fail '合法混合大小写 HTTPUpgrade 域名被拒绝'
dockerGenerateNginxConfig "${TEST_ROOT}/uppercase-httpupgrade.json" "${TEST_ROOT}/uppercase-httpupgrade.conf"
grep -qF 'proxy_set_header Host HttpUpgrade.Example.com;' "${TEST_ROOT}/uppercase-httpupgrade.conf" ||
    fail 'HTTPUpgrade 反代 Host 被规范为小写'
for core in xray sing-box; do
    jq --arg core "${core}" '.core.type = $core | .core.protocols[0].core = $core' \
        "${TEST_ROOT}/uppercase-httpupgrade.json" >"${TEST_ROOT}/uppercase-httpupgrade-${core}.json"
    if [[ "${core}" == xray ]]; then
        dockerGenerateXrayConfig "${TEST_ROOT}/uppercase-httpupgrade-${core}.json" "${TEST_ROOT}/uppercase-core.json"
    else
        dockerGenerateSingBoxConfig "${TEST_ROOT}/uppercase-httpupgrade-${core}.json" "${TEST_ROOT}/uppercase-core.json"
    fi
    jq -e --arg core "${core}" 'if $core == "xray" then
      any(.inbounds[]; .streamSettings.httpupgradeSettings.host == "HttpUpgrade.Example.com")
      else any(.inbounds[]; .transport.host == "HttpUpgrade.Example.com") end' \
        "${TEST_ROOT}/uppercase-core.json" >/dev/null || fail "${core}: HTTPUpgrade 后端 Host 大小写改变"
done
# 混合 21/22/23 共享 TLS 与发布，内部后端端口按核心隔离。
jq --slurpfile ws "${TEST_ROOT}/published-vmess.json" '
  .core.type = "xray" | .core.secondary_type = "sing-box" |
  .core.protocols[0] |= (.core = "sing-box" | .public_port = 24446 | .httpupgrade.tls_port = 8445) |
  .core.protocols += $ws[0].core.protocols | .subscription.enabled = true
' "${HTTPUPGRADE_SPEC}" >"${TEST_ROOT}/mixed-httpupgrade.json"
for field in backend_port tls_port; do
    jq --arg field "${field}" '
      if $field == "backend_port" then
        .core.protocols[0].core = "xray" | .core.secondary_type = null |
        .core.protocols[0].httpupgrade[$field] = .core.protocols[1].websocket[$field]
      else .core.protocols[0].httpupgrade[$field] = .core.protocols[1].websocket[$field] end
    ' "${TEST_ROOT}/mixed-httpupgrade.json" >"${TEST_ROOT}/invalid-httpupgrade.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-httpupgrade.json" 2>/dev/null; then
        fail "混合 WS/HTTPUpgrade 接受重复 ${field}"
    fi
done
newState httpupgrade-mixed "${TEST_ROOT}/mixed-httpupgrade.json"
jq -e '.services.nginx.depends_on == {
  "sing-box":{condition:"service_healthy"},subscription:{condition:"service_healthy"},
  xray:{condition:"service_healthy"}}' \
    "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null || fail '混合 Nginx 核心或订阅依赖错误'
mixed_uri="vmess://$(jq -cn --argjson uri "${HTTPUPGRADE_JSON}" '$uri | .port = "24446"' | tr -d '\n' | base64 | tr -d '\n')"
mixed_ws=${WS_URI//:24444?/:24445?}
mixed_ws=${mixed_ws//abcdefghws/vlessabcws}
[[ "$(<"${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}")" == \
    "${mixed_uri}"$'\n'"${VMESS_URI}"$'\n'"${mixed_ws}" ]] || fail '混合发布未精确包含 HTTPUpgrade/VMess/VLESS'
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
for core in xray sing-box; do
    dockerTrafficRender "${core}" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" "${quota}" \
        >"${TEST_ROOT}/quota-httpupgrade-${core}.json"
    jq -e --arg core "${core}" '
      if $core == "xray" then all(.inbounds[] | select(.protocol == "vmess" or .protocol == "vless"); .settings.clients == [])
      else all(.inbounds[] | select(.type == "vmess"); .users == []) end' \
        "${TEST_ROOT}/quota-httpupgrade-${core}.json" >/dev/null || fail "${core}: 混合入口未共享 UUID 额度"
    enabled=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
    dockerTrafficRender "${core}" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" "${enabled}" \
        >"${TEST_ROOT}/enabled-httpupgrade-${core}.json"
    cmp -s "${TEST_ROOT}/enabled-httpupgrade-${core}.json" "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" ||
        fail "${core}: HTTPUpgrade 解除额度改变身份或 transport"
done
cp "${TEST_ROOT}/mixed-httpupgrade.json" "${TEST_ROOT}/httpupgrade-edit.json"
printf '9\nentry-httpupgrade\n1\n24447\n9\nentry-httpupgrade\n2\n24448\n8\n' |
    dockerEditFields "${TEST_ROOT}/httpupgrade-edit.json" >"${STDOUT}" || fail '混合 HTTPUpgrade 同/跨核复制失败'
jq -e '.core.protocols[0] as $source |
  (.core.protocols[3] | .id == 23 and .core == "xray" and .uuid == $source.uuid and
    .httpupgrade.backend_port == 31306 and .httpupgrade.tls_port == 8446) and
  (.core.protocols[4] | .id == 23 and .core == "sing-box" and .uuid == $source.uuid and
    .httpupgrade.backend_port == 31307 and .httpupgrade.tls_port == 8447)' \
    "${TEST_ROOT}/httpupgrade-edit.json" >/dev/null || fail 'HTTPUpgrade 复制未隔离后端核心和共享 TLS 端口池'
printf '10\nvless-ws\n10\nentry-vmess\n8\n' |
    dockerEditFields "${TEST_ROOT}/httpupgrade-edit.json" >"${STDOUT}" || fail '混合删除 WS 失败'
jq -e '.tls.domain == "ws.example.com" and .subscription.enabled == false and
  all(.core.protocols[]; .id == 23)' "${TEST_ROOT}/httpupgrade-edit.json" >/dev/null ||
    fail '删除最后 VLESS/VMess 撤销了 HTTPUpgrade TLS 或保留发布'
jq --slurpfile before "${TEST_ROOT}/v3.json" '
  .core.protocols += [$before[0].core.protocols[] | select(.id == 1)]
' "${TEST_ROOT}/httpupgrade-edit.json" >"${TEST_ROOT}/httpupgrade-final-tls.json"
printf '10\nentry-1\n10\nentry-2\n10\nentry-httpupgrade\n8\n' |
    dockerEditFields "${TEST_ROOT}/httpupgrade-final-tls.json" >"${STDOUT}" || fail '删除最后 HTTPUpgrade TLS 入口失败'
jq -e '.tls == null and .subscription.enabled == false and .core.type == "xray" and
  .core.secondary_type == null and (.core.protocols | length) == 1 and .core.protocols[0].id == 1' \
    "${TEST_ROOT}/httpupgrade-final-tls.json" >/dev/null || fail '删除最后 HTTPUpgrade 未清 TLS 引用或副核心'
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 23) | .public_port) = 24449' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-httpupgrade.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-httpupgrade.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 && "$(liveSnapshot)" == "${before}" ]] ||
    fail "HTTPUpgrade 失败事务返回 ${actual} 或改变两核配置/TLS"
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'HTTPUpgrade 回归遗留部署锁'
printf 'docker-httpupgrade-regression-ok\n'
