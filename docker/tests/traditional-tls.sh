#!/usr/bin/env bash
set -euo pipefail

# 已验收链只执行一次，补充两种直接 TLS/fallback 入口。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/grpc-tls.sh"
dockerConfigureTestFixture
for protocol in 27 29; do
    spec="${TEST_ROOT}/traditional-tls-${protocol}.json"
    jq --argjson protocol "${protocol}" --arg manifest "${CONFIGURE_MANIFEST_SHA}" \
        --arg identity "${CONFIGURE_IDENTITY}" --slurpfile release "${CONFIGURE_MANIFEST}" '
      .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
      .images = ($release[0].images | with_entries(.value = .value.reference)) |
      .core.protocols[0] |= (.id = $protocol | .listener_id = "entry-fallback-"+($protocol|tostring) |
        .name = "fallback:"+($protocol|tostring) |
        .fallback_tls = {domain:.httpupgrade.domain,http_port:31300,http2_port:31302} |
        del(.httpupgrade))
    ' "${HTTPUPGRADE_SPEC}" >"${spec}"
    dockerConfigureSpecValidate "${spec}" || fail "${protocol}: 有效传统 TLS 合同被拒绝"
    for mutation in \
        '.tls = null' \
        '.core.type = "sing-box" | .core.protocols[0].core = "sing-box"' \
        '.core.protocols[0].fallback_tls.domain = "other.example.com"' \
        '.core.protocols[0].fallback_tls.domain += "\n" | .tls.domain = .core.protocols[0].fallback_tls.domain' \
        'del(.core.protocols[0].fallback_tls)' \
        'del(.core.protocols[0].fallback_tls.http_port)' \
        'del(.core.protocols[0].fallback_tls.http2_port)' \
        '.core.protocols[0].fallback_tls.http_port = .core.protocols[0].fallback_tls.http2_port' \
        '.core.protocols[0].fallback_tls.http_port = 8080' \
        '.core.protocols[0].fallback_tls.http2_port = 8080' \
        '.core.protocols[0].fallback_tls.http_port = 0' \
        '.core.protocols[0].fallback_tls.http2_port = 65536' \
        '.core.protocols[0].fallback_tls.http_port = "31300"' \
        '.core.protocols[0].fallback_tls.extra = true' \
        '.core.protocols[0].uuid += "\n"' \
        '.core.protocols[0].flow = "xtls-rprx-vision"' \
        '.core.protocols[0].trojan = {domain:"ws.example.com"}' \
        '.core.protocols[0].public_port = 10085' \
        '.subscription.enabled = true' \
        '.host_integrations = [{type:"wireguard",profile:"net-wireguard",firewall_rules:[],
          devices:["wg-padm"],schedules:[],settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
        jq "${mutation}" "${spec}" >"${TEST_ROOT}/invalid-traditional-tls.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-traditional-tls.json" 2>/dev/null; then
            fail "${protocol}: 传统 TLS 接受非法合同: ${mutation}"
        fi
    done
    for version in 1 2; do
        jq --argjson version "${version}" '.schema_version = $version | del(.core.secondary_type) |
          .core.protocols |= map(del(.core) |
            if $version == 1 then del(.listener_id) else . end)' \
            "${spec}" >"${TEST_ROOT}/invalid-traditional-tls.json"
        if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-traditional-tls.json" 2>/dev/null; then
            fail "${protocol}: 旧版本 ${version} 接受传统 TLS"
        fi
    done
    cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} "${COMPAT_BUNDLE}/docker/contracts/"
    dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" || fail "${protocol}: 当前 bundle 拒绝传统 TLS"
    for mutation in \
        '(.protocols[] | select(.id == $protocol) | .status) = "deferred"' \
        '.protocols |= map(select(.id != $protocol))' \
        '(.protocols[] | select(.id == $protocol) | .cores) = ["sing-box"]'; do
        jq --argjson protocol "${protocol}" "${mutation}" "${PROJECT_ROOT}/docker/contracts/features.json" \
            >"${COMPAT_BUNDLE}/docker/contracts/features.json"
        if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" 2>/dev/null; then
            fail "${protocol}: 不兼容 bundle 接受传统 TLS"
        fi
    done
    cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/"
    jq '.properties.schema_version.enum = [1,2]' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
        >"${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
    if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${spec}" 2>/dev/null; then
        fail "${protocol}: 旧规格 bundle 接受传统 TLS"
    fi
    if [[ "${protocol}" == 27 ]]; then
        uri="vless://${UUID}@[2001:db8::1]:24444?encryption=none&flow=xtls-rprx-vision&security=tls&sni=ws.example.com&fp=chrome&alpn=h2%2Chttp%2F1.1&type=tcp#fallback%3A27"
    else
        uri="trojan://${UUID}@[2001:db8::1]:24444?peer=ws.example.com&security=tls&fp=chrome&sni=ws.example.com&alpn=h2%2Chttp%2F1.1&type=tcp#fallback%3A29"
    fi
    printf '%s\n' "${uri}" >"${TEST_ROOT}/traditional-tls-${protocol}.uri"
    newState "traditional-tls-${protocol}" "${spec}"
    dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" ||
        fail "${protocol}: 传统 TLS 部署基线不匹配"
    jq -e --argjson protocol "${protocol}" '.compose.profiles == ["core-xray","nginx"] and
      .core.protocol_ids == [$protocol] and .listeners == [{
        listener_id:("entry-fallback-"+($protocol|tostring)),service:"xray",public_port:24444,
        container_port:24444,transport:"tcp",address_families:["ipv4","ipv6"]}]' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null || fail "${protocol}: 传统 TLS 监听拓扑错误"
    jq -e '.services.xray.ports == ["0.0.0.0:24444:24444/tcp","[::]:24444:24444/tcp"] and
      .services.nginx.ports == [] and (.services.xray.depends_on // {}) == {} and
      (.services.nginx.depends_on // {}) == {} and
      any(.services.xray.volumes[]; .target == "/etc/padm/secrets/tls" and .read_only) and
      all(.services.nginx.volumes[]; .target != "/etc/padm/secrets/tls") and
      (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${protocol}: 传统 TLS 证书终止、端口或依赖错误"
    [[ "$(dockerTlsConsumers ws.example.com)" == '["xray"]' &&
        "$(dockerTlsConsumers unused.example.com)" == '[]' ]] ||
        fail "${protocol}: 明文 fallback 被误算为 TLS 消费者"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" \
        "${TEST_ROOT}/saved-traditional-consumer-nginx.conf"
    cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" \
        "${TEST_ROOT}/saved-traditional-consumer-compose.json"
    for mutation in inline-cert include-site secret-alias; do
        cp "${TEST_ROOT}/saved-traditional-consumer-nginx.conf" \
            "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
        cp "${TEST_ROOT}/saved-traditional-consumer-compose.json" \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json"
        case "${mutation}" in
        inline-cert)
            printf '\nserver { listen 31400 ssl; ssl_certificate /etc/padm/secrets/tls/ws.example.com.crt; }\n' \
                >>"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
            ;;
        include-site)
            printf '\ninclude /etc/nginx/http.d/site.inc;\n' \
                >>"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
            printf 'server {}\n' >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/site.inc"
            ;;
        secret-alias)
            jq '.services.nginx.volumes += [{type:"bind",
              source:"${PADM_DOCKER_ROOT}/secrets/tls",target:"/alt",read_only:true}]' \
                "${PADM_DOCKER_INSTALL_DIR}/compose.json" \
                >"${TEST_ROOT}/mutated-traditional-compose.json"
            cp "${TEST_ROOT}/mutated-traditional-compose.json" \
                "${PADM_DOCKER_INSTALL_DIR}/compose.json"
            ;;
        esac
        if dockerTlsConsumers ws.example.com >"${TEST_ROOT}/consumer-rejected.log" 2>&1; then
            fail "${protocol}: fallback TLS 消费者接受 ${mutation}"
        fi
        rm -f -- "${PADM_DOCKER_INSTALL_DIR}/config/nginx/site.inc"
    done
    for change in \
        '(.services.nginx.volumes[] | select(.target == "/srv/padm") | .target) = "/etc/nginx"' \
        '(.services.nginx.volumes[] | select(.target == "/etc/nginx/http.d") | .read_only) = false' \
        '.services.nginx.volumes += [.services.nginx.volumes[1]]' \
        '(.services.nginx.volumes[] | select(.target == "/srv/padm") | .type) = "volume"'; do
        cp "${TEST_ROOT}/saved-traditional-consumer-nginx.conf" \
            "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
        jq "${change}" "${TEST_ROOT}/saved-traditional-consumer-compose.json" \
            >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
        if dockerTlsConsumers ws.example.com >"${TEST_ROOT}/consumer-rejected.log" 2>&1; then
            fail "${protocol}: fallback TLS 消费者接受不安全挂载: ${change}"
        fi
    done
    cp "${TEST_ROOT}/saved-traditional-consumer-nginx.conf" \
        "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    cp "${TEST_ROOT}/saved-traditional-consumer-compose.json" \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    for file in users.base config.json; do
        jq -e --arg uuid "${UUID}" --arg file "${file}" --argjson protocol "${protocol}" '
          any(.inbounds[]; .tag == ("entry-fallback-"+($protocol|tostring)) and
            .protocol == (if $protocol == 27 then "vless" else "trojan" end) and
            .listen == "::" and .port == 24444 and
            .settings == ((if $protocol == 27 then {decryption:"none",clients:[{
              id:$uuid,email:(if $file == "users.base" then "fallback:27" else $uuid end),flow:"xtls-rprx-vision"}]}
              else {clients:[{password:$uuid,email:$uuid}]} end) + {fallbacks:[
                {dest:"nginx:31300",xver:1},{alpn:"h2",dest:"nginx:31302",xver:1}]}) and
            .streamSettings == {network:"tcp",security:"tls",tlsSettings:{
              serverName:"ws.example.com",alpn:["h2","http/1.1"],rejectUnknownSni:true,minVersion:"1.2",
              certificates:[{certificateFile:"/etc/padm/secrets/tls/ws.example.com.crt",
                keyFile:"/etc/padm/secrets/tls/ws.example.com.key"}]}})' \
            "${PADM_DOCKER_INSTALL_DIR}/config/xray/${file}" >/dev/null ||
            fail "${protocol}: 传统 TLS ${file} 配置错误"
    done
    for text in 'listen 31300 proxy_protocol;' 'listen [::]:31300 proxy_protocol;' \
        'listen 31302 proxy_protocol;' 'listen [::]:31302 proxy_protocol;' 'http2 on;' \
        'server_name ws.example.com;' 'root /srv/padm;' 'location = / {' \
        'try_files /index.html @padm_fallback;' 'try_files $uri =404;'; do
        grep -qF "${text}" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
            fail "${protocol}: Nginx fallback 缺少 ${text}"
    done
    [[ "$(grep -cF 'http2 on;' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf")" == 1 ]] ||
        fail "${protocol}: h1 后端错误启用 h2"
    ! grep -Eq 'ssl_certificate|proxy_pass|grpc_pass|rewrite ' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail "${protocol}: fallback 后端意外终止 TLS 或反代核心"
    runRead 0 "traditional-tls-${protocol}-links" dockerProtocolCommand links "entry-fallback-${protocol}"
    [[ "$(<"${STDOUT}")" == "${uri}" && "$(wc -l <"${STDOUT}")" == 1 ]] ||
        fail "${protocol}: 传统 TLS URI 不精确"
    runRead 0 "traditional-tls-${protocol}-list" dockerProtocolCommand list
    label='VLESS TCP TLS Vision'; [[ "${protocol}" != 29 ]] || label='Trojan TCP TLS fallback'
    grep -qxF "entry-fallback-${protocol}  xray  ${label}  [2001:db8::1]:24444  [ipv4,ipv6]  fallback:${protocol}" \
        "${STDOUT}" || fail "${protocol}: 传统 TLS 概览错误"
    ! grep -Fq "${UUID}" "${STDOUT}" || fail "${protocol}: 传统 TLS 概览暴露账号"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${TEST_ROOT}/saved-traditional-tls.json"
    for field in uuid fallback alpn sni flow; do
        jq --arg field "${field}" --argjson protocol "${protocol}" '
          .inbounds |= map(if .protocol != "vless" and .protocol != "trojan" then .
            elif $field == "uuid" then
              if $protocol == 27 then .settings.clients[0].id = "22222222-2222-4222-8222-222222222222"
              else .settings.clients[0].password = "wrong" end
            elif $field == "fallback" then .settings.fallbacks[0].xver = 0
            elif $field == "alpn" then .streamSettings.tlsSettings.alpn = ["http/1.1"]
            elif $field == "sni" then .streamSettings.tlsSettings.serverName = "other.example.com"
            else .settings.clients[0].flow = "wrong" end)' "${TEST_ROOT}/saved-traditional-tls.json" \
            >"${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
        runRead 15 "traditional-tls-${protocol}-${field}-drift" dockerProtocolCommand links "entry-fallback-${protocol}"
    done
    cp "${TEST_ROOT}/saved-traditional-tls.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" "${TEST_ROOT}/saved-traditional-nginx.conf"
    sed 's/31302 proxy_protocol/31303 proxy_protocol/g' "${TEST_ROOT}/saved-traditional-nginx.conf" \
        >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
    runRead 15 "traditional-tls-${protocol}-nginx-drift" dockerProtocolCommand links "entry-fallback-${protocol}"
    cp "${TEST_ROOT}/saved-traditional-nginx.conf" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf"
done
# fallback 与 WS/gRPC 共享 Nginx 端口池，核心公开入口仍按核心避让 API。
jq --slurpfile trojan "${TEST_ROOT}/traditional-tls-29.json" \
    --slurpfile old "${TEST_ROOT}/mixed-grpc-tls.json" '
  .core.secondary_type = "sing-box" | .subscription.enabled = true |
  .core.protocols[0].public_port = 24460 |
  .core.protocols += [($trojan[0].core.protocols[0] | .public_port = 24461 |
    .fallback_tls.http_port = 31310 | .fallback_tls.http2_port = 31312)] + $old[0].core.protocols
' "${TEST_ROOT}/traditional-tls-27.json" >"${TEST_ROOT}/mixed-traditional-tls.json"
jq '.core.protocols[1].fallback_tls = .core.protocols[0].fallback_tls' \
    "${TEST_ROOT}/mixed-traditional-tls.json" >"${TEST_ROOT}/shared-traditional-tls.json"
dockerConfigureSpecValidate "${TEST_ROOT}/shared-traditional-tls.json" ||
    fail '传统 TLS 拒绝完整相同的 fallback 端口对'
dockerGenerateNginxConfig "${TEST_ROOT}/shared-traditional-tls.json" "${TEST_ROOT}/shared-traditional-nginx.conf"
[[ "$(grep -cF 'listen 31300 proxy_protocol;' "${TEST_ROOT}/shared-traditional-nginx.conf")" == 1 &&
    "$(grep -cF 'listen 31302 proxy_protocol;' "${TEST_ROOT}/shared-traditional-nginx.conf")" == 1 ]] ||
    fail '共享 fallback 端口对生成重复 Nginx listener'
for mutation in \
    '.core.protocols[0].fallback_tls.http_port = .core.protocols[1].fallback_tls.http2_port' \
    '.core.protocols[0].fallback_tls.http2_port = .core.protocols[2].grpc_tls.tls_port' \
    '.core.protocols[1].fallback_tls.http_port = .core.protocols[0].fallback_tls.http_port' \
    '.core.protocols[0].public_port = .core.protocols[2].grpc_tls.backend_port'; do
    jq "${mutation}" "${TEST_ROOT}/mixed-traditional-tls.json" >"${TEST_ROOT}/invalid-traditional-tls.json"
    if dockerConfigureSpecValidate "${TEST_ROOT}/invalid-traditional-tls.json" 2>/dev/null; then
        fail "混合传统 TLS 接受端口冲突: ${mutation}"
    fi
done
newState traditional-tls-mixed "${TEST_ROOT}/mixed-traditional-tls.json"
dockerTlsConsumers ws.example.com | jq -e 'sort == ["nginx","xray"]' >/dev/null ||
    fail '混合传统 TLS 消费者未包含核心和 Nginx'
jq -e '.services.nginx.depends_on == {"sing-box":{condition:"service_healthy"},
  subscription:{condition:"service_healthy"},xray:{condition:"service_healthy"}} and
  (.services.xray.depends_on // {}) == {}' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
    fail '混合传统 TLS 引入循环依赖'
for protocol in 27 29; do
    uri=$(<"${TEST_ROOT}/traditional-tls-${protocol}.uri")
    port=24460; [[ "${protocol}" != 29 ]] || port=24461
    grep -qxF "${uri//:24444?/:${port}?}" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" ||
        fail "${protocol}: 混合订阅漏掉传统 TLS"
done
quota=$(jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{
  ($uuid):{name:"shared",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${quota}" \
    >"${TEST_ROOT}/quota-traditional-tls.json"
jq -e 'all(.inbounds[] | select(.protocol == "vless" or .protocol == "trojan" or .protocol == "vmess");
  .settings.clients == [])' "${TEST_ROOT}/quota-traditional-tls.json" >/dev/null ||
    fail '混合传统 TLS 未共享 UUID 额度'
enabled=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 0' <<<"${quota}")
dockerTrafficRender xray "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" "${enabled}" \
    >"${TEST_ROOT}/enabled-traditional-tls.json"
cmp -s "${TEST_ROOT}/enabled-traditional-tls.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" ||
    fail '传统 TLS 解除额度改变认证、Vision 或 fallback'
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
jq '(.core.protocols[] | select(.id == 27) | .public_port) = 24462' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${TEST_ROOT}/changed-traditional-tls.json"
actual=0
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureReleasePrepare "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}"
    dockerConfigureApply "${TEST_ROOT}/changed-traditional-tls.json" "" "" confirmed
) >"${STDOUT}" 2>"${STDERR}" || actual=$?
[[ "${actual}" == 14 && "$(liveSnapshot)" == "${before}" ]] ||
    fail "传统 TLS 失败事务返回 ${actual} 或改变核心、fallback、证书、统计"
IMAGE_DIGEST=$(printf '8%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
(
    trap 'dockerCleanupConfigurationCandidate; dockerCleanupStagedBundle; dockerManifestCleanup; dockerReleaseDeploymentLock' EXIT
    dockerUpdateCommand --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
) >"${STDOUT}" 2>"${STDERR}" || fail '传统 TLS 混合更新失败'
for protocol in 27 29; do
    runRead 0 "traditional-tls-${protocol}-updated-links" dockerProtocolCommand links "entry-fallback-${protocol}"
    expected_uri=$(<"${TEST_ROOT}/traditional-tls-${protocol}.uri")
    port=24460; [[ "${protocol}" != 29 ]] || port=24461
    [[ "$(<"${STDOUT}")" == "${expected_uri//:24444?/:${port}?}" ]] ||
        fail "${protocol}: 更新改变传统 TLS URI"
done
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerRollbackCommand
) >"${STDOUT}" 2>"${STDERR}" || fail '传统 TLS 混合回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail '传统 TLS 更新回滚改变核心、fallback、证书或统计'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '传统 TLS 回归遗留部署锁'
printf 'docker-traditional-tls-regression-ok\n'
