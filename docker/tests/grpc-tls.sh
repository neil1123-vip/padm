#!/usr/bin/env bash
set -euo pipefail

# 只串接一次已验收协议链，新增 Xray 的两类 gRPC TLS 边界。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/httpupgrade.sh"
dockerConfigureTestFixture
for protocol in 24 25; do
    backend=31301; scheme=vless; [[ "${protocol}" != 25 ]] || { backend=31304; scheme=trojan; }
    spec="${TEST_ROOT}/grpc-tls-${protocol}.json"
    jq --argjson protocol "${protocol}" --argjson backend "${backend}" --arg manifest "${CONFIGURE_MANIFEST_SHA}" \
        --arg identity "${CONFIGURE_IDENTITY}" --slurpfile release "${CONFIGURE_MANIFEST}" '
      .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
      .images = ($release[0].images | with_entries(.value = .value.reference)) |
      .core.protocols[0] |= (.id = $protocol | .listener_id = "entry-grpc-"+($protocol|tostring) |
        .name = "gRPC:"+($protocol|tostring) |
        .grpc_tls = {domain:.httpupgrade.domain,service_name:"padm_grpc-1",backend_port:$backend,tls_port:8443} |
        del(.httpupgrade))
    ' "${HTTPUPGRADE_SPEC}" >"${spec}"
    dockerConfigureSpecValidate "${spec}" || fail "${protocol}: 有效 gRPC TLS 合同被拒绝"
    for mutation in \
        '.tls = null' \
        '.core.type = "sing-box" | .core.protocols[0].core = "sing-box"' \
        '.core.protocols[0].grpc_tls.domain = "other.example.com"' \
        '.core.protocols[0].grpc_tls.domain += "\n" | .tls.domain = .core.protocols[0].grpc_tls.domain' \
        'del(.core.protocols[0].grpc_tls)' \
        'del(.core.protocols[0].grpc_tls.backend_port)' \
        'del(.core.protocols[0].grpc_tls.tls_port)' \
        '.core.protocols[0].grpc_tls.service_name = ""' \
        '.core.protocols[0].grpc_tls.service_name = ("a"*65)' \
        '.core.protocols[0].grpc_tls.service_name = "bad/name"' \
        '.core.protocols[0].grpc_tls.service_name = "bad.name"' \
        '.core.protocols[0].grpc_tls.service_name += "\n"' \
        '.core.protocols[0].grpc_tls.extra = true' \
        '.core.protocols[0].grpc_tls.backend_port = 10085' \
        '.core.protocols[0].grpc_tls.tls_port = 8080' \
        '.core.protocols[0].uuid += "\n"' \
        '.core.protocols[0].flow = "xtls-rprx-vision"' \
        '.core.protocols[0].grpc = {service_name:"other"}' \
        '.subscription.enabled = true' \
        '.host_integrations = [{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
          devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
        jq "${mutation}" "${spec}" >"${TEST_ROOT}/invalid-grpc-tls.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-grpc-tls.json" 2>/dev/null; then
            fail "${protocol}: gRPC TLS 接受非法合同: ${mutation}"
        fi
    done
    for version in 1 2; do
        jq --argjson version "${version}" '.schema_version = $version | del(.core.secondary_type) |
          .core.protocols |= map(del(.core) |
            if $version == 1 then del(.listener_id, .grpc_tls.backend_port, .grpc_tls.tls_port) else . end)' \
            "${spec}" >"${TEST_ROOT}/invalid-grpc-tls.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-grpc-tls.json" 2>/dev/null; then
            fail "${protocol}: 旧版本 ${version} 接受 gRPC TLS"
        fi
    done
    cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} "${COMPAT_BUNDLE}/docker/contracts/"
    dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" || fail "${protocol}: 当前 bundle 拒绝 gRPC TLS"
    for mutation in \
        '(.protocols[] | select(.id == $protocol) | .status) = "deferred"' \
        '.protocols |= map(select(.id != $protocol))' \
        '(.protocols[] | select(.id == $protocol) | .cores) = ["sing-box"]'; do
        jq --argjson protocol "${protocol}" "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
            >"${COMPAT_BUNDLE}/docker/contracts/features.json"
        if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" 2>/dev/null; then
            fail "${protocol}: 不兼容 bundle 接受 gRPC TLS"
        fi
    done
    cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
    jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" 2>/dev/null; then
        fail "${protocol}: 旧规格 bundle 接受 gRPC TLS"
    fi
    if [[ "${protocol}" == 24 ]]; then
        uri="vless://${UUID}@[2001:db8::1]:24444?encryption=none&security=tls&sni=ws.example.com&type=grpc&alpn=h2&serviceName=padm_grpc-1#gRPC%3A24"
    else
        uri="trojan://${UUID}@[2001:db8::1]:24444?peer=ws.example.com&fp=chrome&sni=ws.example.com&type=grpc&alpn=h2&serviceName=padm_grpc-1#gRPC%3A25"
    fi
    printf '%s\n' "${uri}" >"${TEST_ROOT}/grpc-tls-${protocol}.uri"
    newState "grpc-tls-${protocol}" "${spec}"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${protocol}: gRPC TLS 部署基线不匹配"
    jq -e --argjson protocol "${protocol}" '.compose.profiles == ["core-xray","nginx"] and
      .core.protocol_ids == [$protocol] and .listeners == [{
        listener_id:("entry-grpc-"+($protocol|tostring)),service:"nginx",public_port:24444,
        container_port:8443,transport:"tcp",address_families:["ipv4","ipv6"]}]' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail "${protocol}: gRPC TLS 监听拓扑错误"
    jq -e '.services.xray.ports == [] and .services.nginx.ports ==
      ["0.0.0.0:24444:8443/tcp","[::]:24444:8443/tcp"] and
      .services.nginx.depends_on == {xray:{condition:"service_healthy"}} and
      any(.services.nginx.volumes[]; .target == "/etc/padm/secrets/tls" and .read_only) and
      all(.services.xray.volumes[]; .target != "/etc/padm/secrets/tls") and
      (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${protocol}: gRPC TLS 证书终止、端口或依赖错误"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" --arg scheme "${scheme}" --arg file "${file}" \
            --argjson protocol "${protocol}" --argjson backend "${backend}" '
          any(.inbounds[]; .tag == ("entry-grpc-"+($protocol|tostring)) and .protocol == $scheme and
            .listen == "0.0.0.0" and .port == $backend and
            .settings == (if $protocol == 24 then {decryption:"none",clients:[{
              id:$uuid,email:(if $file == "users.base" then "gRPC:24" else $uuid end)}]}
              else {clients:[{password:$uuid,email:$uuid}]} end) and
            .streamSettings == {network:"grpc",security:"none",grpcSettings:{serviceName:"padm_grpc-1"}})' \
            "${PADM_DOCKER_INSTALL_DIR}/config/xray/${file}" >/dev/null ||
            fail "${protocol}: gRPC TLS ${file} 配置错误"
    done
    for text in 'http2 on;' 'location ^~ /padm_grpc-1/ {' "grpc_pass grpc://xray:${backend};" \
        'grpc_set_header Host ws.example.com;' 'client_max_body_size 0;' 'client_body_timeout 5d;' \
        'grpc_read_timeout 5d;' 'grpc_send_timeout 5d;'; do
        grep -qF "${text}" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
            fail "${protocol}: Nginx gRPC 缺少 ${text}"
    done
    ! grep -Eq 'proxy_pass|rewrite |proxy_protocol' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail "${protocol}: gRPC 反代混入 HTTP/路径重写或 PROXY protocol"
    runRead 0 "grpc-tls-${protocol}-links" dockerProtocolCommand links "entry-grpc-${protocol}"
    [[ "$(<"${STDOUT}")" == "${uri}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
        fail "${protocol}: gRPC TLS URI 不精确"
    runRead 0 "grpc-tls-${protocol}-list" dockerProtocolCommand list
    label='VLESS gRPC TLS'; [[ "${protocol}" != 25 ]] || label='Trojan gRPC TLS'
    grep -qxF "entry-grpc-${protocol}  xray  ${label}  [2001:db8::1]:24444  [ipv4,ipv6]  gRPC:${protocol}" \
        "${STDOUT}" || fail "${protocol}: gRPC TLS 概览错误"
    ! grep -Fq "${UUID}" "${STDOUT}" || fail "${protocol}: gRPC TLS 概览暴露账号"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${TEST_ROOT}/saved-grpc-tls.json"
    for field in uuid service transport; do
        jq --arg field "${field}" --argjson protocol "${protocol}" '
          .inbounds |= map(if .streamSettings.network != "grpc" then .
            elif $field == "uuid" then
              if $protocol == 24 then .settings.clients[0].id = "22222222-2222-4222-8222-222222222222"
              else .settings.clients[0].password = "wrong" end
            elif $field == "service" then .streamSettings.grpcSettings.serviceName = "changed"
            else .streamSettings.network = "tcp" end)' "${TEST_ROOT}/saved-grpc-tls.json" \
            >"${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
        runRead 15 "grpc-tls-${protocol}-${field}-drift" dockerProtocolCommand links "entry-grpc-${protocol}"
    done
    cp "${TEST_ROOT}/saved-grpc-tls.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" "${TEST_ROOT}/saved-grpc-tls-nginx.conf"
    sed 's|/padm_grpc-1/|/changed/|' "${TEST_ROOT}/saved-grpc-tls-nginx.conf" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    runRead 15 "grpc-tls-${protocol}-nginx-drift" dockerProtocolCommand links "entry-grpc-${protocol}"
    cp "${TEST_ROOT}/saved-grpc-tls-nginx.conf" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
done
# 两类 gRPC、WS 与 HTTPUpgrade 共用 TLS，后端还须避让 Xray 的直接入口。
jq --slurpfile trojan "${TEST_ROOT}/grpc-tls-25.json" \
    --slurpfile old "${TEST_ROOT}/mixed-httpupgrade.json" --slurpfile reality "${TEST_ROOT}/v3.json" '
  .core.secondary_type = "sing-box" | .subscription.enabled = true |
  .core.protocols[0] |= (.public_port = 24450 | .grpc_tls.tls_port = 8446) |
  .core.protocols += [($trojan[0].core.protocols[0] | .public_port = 24451 | .grpc_tls.tls_port = 8447)] +
    $old[0].core.protocols + [($reality[0].core.protocols[] | select(.id == 1) | .public_port = 31302)]
' "${TEST_ROOT}/grpc-tls-24.json" >"${TEST_ROOT}/mixed-grpc-tls.json"
for mutation in \
    '.core.protocols[0].grpc_tls.backend_port = .core.protocols[3].websocket.backend_port' \
    '.core.protocols[0].grpc_tls.backend_port = 31302' \
    '.core.protocols[1].grpc_tls.backend_port = .core.protocols[0].grpc_tls.backend_port' \
    '.core.protocols[0].grpc_tls.tls_port = .core.protocols[2].httpupgrade.tls_port'; do
    jq "${mutation}" "${TEST_ROOT}/mixed-grpc-tls.json" >"${TEST_ROOT}/invalid-grpc-tls.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-grpc-tls.json" 2>/dev/null; then
        fail "混合 gRPC TLS 接受内部端口冲突: ${mutation}"
    fi
done
newState grpc-tls-mixed "${TEST_ROOT}/mixed-grpc-tls.json"
jq -e '.services.nginx.depends_on == {"sing-box":{condition:"service_healthy"},
  subscription:{condition:"service_healthy"},xray:{condition:"service_healthy"}}' \
    "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null || fail '混合 gRPC TLS 依赖错误'
for protocol in 24 25; do
    uri=$(<"${TEST_ROOT}/grpc-tls-${protocol}.uri")
    port=24450; [[ "${protocol}" != 25 ]] || port=24451
    grep -qxF "${uri//:24444?/:${port}?}" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" ||
        fail "${protocol}: 混合订阅漏掉 gRPC TLS"
done
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${quota}" \
    >"${TEST_ROOT}/quota-grpc-tls.json"
jq -e 'all(.inbounds[] | select(.protocol == "vless" or .protocol == "trojan" or .protocol == "vmess");
  .settings.clients == [])' "${TEST_ROOT}/quota-grpc-tls.json" >/dev/null || fail '混合 gRPC TLS 未共享 UUID 额度'
enabled=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${enabled}" \
    >"${TEST_ROOT}/enabled-grpc-tls.json"
cmp -s "${TEST_ROOT}/enabled-grpc-tls.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" ||
    fail 'gRPC TLS 解除额度改变认证或 serviceName'
cp "${TEST_ROOT}/mixed-grpc-tls.json" "${TEST_ROOT}/grpc-tls-edit.json"
printf '9\nentry-grpc-24\n1\n24452\n9\nentry-grpc-25\n1\n24453\n8\n' |
    dockerEditFields "${TEST_ROOT}/grpc-tls-edit.json" >"${STDOUT}" || fail '混合 gRPC TLS 复制失败'
jq -e '(.core.protocols[6] | .id == 24 and .grpc_tls.backend_port == 31303 and .grpc_tls.tls_port == 8448) and
  (.core.protocols[7] | .id == 25 and .grpc_tls.backend_port == 31305 and .grpc_tls.tls_port == 8449)' \
    "${TEST_ROOT}/grpc-tls-edit.json" >/dev/null || fail 'gRPC TLS 复制未避让直接入口或共享 TLS 池'
printf '10\nvless-ws\n10\nentry-vmess\n10\nentry-httpupgrade\n8\n' |
    dockerEditFields "${TEST_ROOT}/grpc-tls-edit.json" >"${STDOUT}" || fail '混合删除传统 HTTP 入口失败'
jq -e '.tls.domain == "ws.example.com" and .subscription.enabled == false and
  .core.secondary_type == null and any(.core.protocols[]; .id == 24) and any(.core.protocols[]; .id == 25)' \
    "${TEST_ROOT}/grpc-tls-edit.json" >/dev/null || fail '删除 HTTP 入口撤销仍需 gRPC TLS 的证书引用'
printf '10\nentry-1\n10\nentry-grpc-24\n10\nentry-2\n10\nentry-grpc-25\n8\n' |
    dockerEditFields "${TEST_ROOT}/grpc-tls-edit.json" >"${STDOUT}" || fail '删除最后 gRPC TLS 入口失败'
jq -e '.tls == null and .subscription.enabled == false and (.core.protocols | length) == 1 and
  .core.protocols[0].id == 1' "${TEST_ROOT}/grpc-tls-edit.json" >/dev/null ||
    fail '删除最后 gRPC TLS 未撤销 TLS 规格引用'
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 24) | .public_port) = 24454' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-grpc-tls.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-grpc-tls.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 && "$(liveSnapshot)" == "${before}" ]] ||
    fail "gRPC TLS 失败事务返回 ${actual} 或改变两核配置/TLS/统计"
IMAGE_DIGEST=$(printf '9%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail 'gRPC TLS 混合更新失败'
runRead 0 grpc-tls-updated-links dockerProtocolCommand links entry-grpc-24
expected_uri=$(<"${TEST_ROOT}/grpc-tls-24.uri")
[[ "$(<"${STDOUT}")" == "${expected_uri//:24444?/:24450?}" ]] || fail '更新改变 gRPC TLS URI'
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail 'gRPC TLS 混合回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail 'gRPC TLS 更新回滚改变配置或统计'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'gRPC TLS 回归遗留部署锁'
printf 'docker-grpc-tls-regression-ok\n'
