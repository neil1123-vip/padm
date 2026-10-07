#!/usr/bin/env bash

dockerRealityStreamContractChecks() {
    local base="${TEST_ROOT}/stream-base.json" enabled="${TEST_ROOT}/stream-enabled.json"
    local invalid="${TEST_ROOT}/stream-invalid.json" nullSpec="${TEST_ROOT}/stream-null.json"
    local xhttp="${TEST_ROOT}/stream-xhttp.json" oldBundle="${TEST_ROOT}/stream-old-bundle"
    local upgrade="${TEST_ROOT}/stream-upgrade.json" mutation streamFile
    local streamRealityUri streamWsUri otherUri currentBundle websiteType version candidate
    local streamBackup malformed guardMessage='Reality 443 共存部署事务尚未交付'

    # 复用协议夹具和部署基线，只增加共存绑定，不重建凭据。
    jq '.core.protocols[0].server = "proxy.example.com" |
      .core.protocols[1].address_families = ["ipv6", "ipv4"] |
      .core.protocols += [(.core.protocols[0] |
        .id = 26 | .listener_id = "entry-other" | .public_port = 24445 |
        .name = "Other-gRPC" | .grpc = {service_name:"other"})]' \
        "${TEST_ROOT}/v3.json" >"${base}" || fail '共存原始规格生成失败'
    jq '.reality_stream = {listener_id:"vless-reality", website_listener_id:"vless-ws"}' \
        "${base}" >"${enabled}" || fail '共存规格生成失败'
    jq '.reality_stream = null' "${base}" >"${nullSpec}" || fail '空共存规格生成失败'
    dockerConfigureSpecValidate "${base}" &&
        dockerConfigureSpecValidate "${enabled}" &&
        dockerConfigureSpecValidate "${nullSpec}" || fail '合法共存或旧无字段规格被拒绝'
    for version in 1 2; do
        jq --argjson version "${version}" '
          .schema_version = $version | .reality_stream = null |
          if $version == 2 then
            .core.protocols |= map(
              .listener_id = (if .id == 1 then "vless-reality" else "vless-ws" end) |
              if .id == 21 then .websocket += {backend_port:31297,tls_port:8443} else . end)
          else . end
        ' "${SPEC}" >"${invalid}" || fail '旧版本空共存规格生成失败'
        jq 'del(.reality_stream)' "${invalid}" >"${invalid}.plain" &&
            dockerConfigureSpecValidate "${invalid}.plain" || fail "v${version} 原始正例无效"
        if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
            fail "v${version} 接受了仅 v3 支持的共存字段"
        fi
    done
    jq '.core.protocols |= map(
          if .listener_id == "vless-reality" then
            .id = 2 | .listener_id = "entry-xhttp" |
            .xhttp = {path:"/stream-xhttp",host:"www.example.com",mode:"auto"}
          elif .listener_id == "vless-ws" then .listener_id = "entry-site"
          else . end) |
        .reality_stream = {listener_id:"entry-xhttp",website_listener_id:"entry-site"}' \
        "${enabled}" >"${xhttp}" || fail 'XHTTP 共存规格生成失败'
    dockerConfigureSpecValidate "${xhttp}" || fail '合法 XHTTP 共存被拒绝'
    for websiteType in 22 23 24 25; do
        jq --argjson id "${websiteType}" '
          .subscription.enabled = false |
          .reality_stream.website_listener_id = "entry-site" |
          .core.protocols[1] |= (
            .websocket as $ws | .id = $id | .listener_id = "entry-site" |
            if $id == 23 then
              del(.websocket) | .httpupgrade = $ws | .httpupgrade.backend_port = 31306
            elif $id == 24 or $id == 25 then
              del(.websocket) |
              .grpc_tls = {domain:$ws.domain,service_name:"site",
                backend_port:(if $id == 24 then 31301 else 31304 end),tls_port:$ws.tls_port}
            else . end)
        ' "${enabled}" >"${invalid}" || fail '受管 TLS 类型夹具生成失败'
        dockerConfigureSpecValidate "${invalid}" || fail "合法受管 TLS ${websiteType} 共存被拒绝"
    done
    jq '.subscription.enabled = false | .core.secondary_type = "sing-box" |
        .reality_stream.website_listener_id = "entry-site" | .core.protocols[1] |= (
        .websocket as $ws | .id = 23 | .listener_id = "entry-site" | .core = "sing-box" | del(.websocket) |
        .httpupgrade = $ws | .httpupgrade.backend_port = 31306)' \
        "${enabled}" >"${upgrade}" || fail '副核心 TLS 共存规格生成失败'
    dockerConfigureSpecValidate "${upgrade}" || fail '副核心 TLS 共存被拒绝'

    for mutation in \
        '.reality_stream.listener_id = "entry-missing"' \
        '.reality_stream.website_listener_id = "entry-missing"' \
        '.reality_stream.website_listener_id = .reality_stream.listener_id' \
        '.reality_stream.listener_id = 1' \
        '.reality_stream.extra = true' \
        '.core.protocols[0].core = "sing-box" | .core.secondary_type = "sing-box"' \
        '.reality_stream.listener_id = "entry-other"' \
        '.reality_stream.website_listener_id = "entry-other"' \
        '.core.protocols[0].server = "different.example.com"' \
        '.core.protocols[1].address_families = ["ipv4"]' \
        '.core.protocols[0].reality.server_name = "WS.Example.Com"' \
        '.core.protocols[2].public_port = 443' \
        '.core.protocols[1].websocket.tls_port = 15443' \
        '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
          firewall_rules:[],devices:["wg-padm"],schedules:[],
          settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
        jq "${mutation}" "${enabled}" >"${invalid}" || fail '非法共存规格生成失败'
        if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
            fail "非法共存绑定或拓扑被接受: ${mutation}"
        fi
    done
    jq '.core.protocols += [{id:27,core:"xray",listener_id:"entry-fallback",
      server:"proxy.example.com",public_port:24446,address_families:["ipv4"],name:"Fallback",
      uuid:.core.protocols[0].uuid,
      fallback_tls:{domain:"ws.example.com",http_port:15443,http2_port:31302}}]' \
        "${enabled}" >"${invalid}" || fail 'fallback 冲突规格生成失败'
    if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
        fail 'stream 与 Nginx fallback 端口冲突未拒绝'
    fi

    mkdir -p "${oldBundle}/docker"
    cp -R "${SOURCE_ROOT}/docker/contracts" "${oldBundle}/docker/contracts"
    jq 'del(.properties.reality_stream)' "${oldBundle}/docker/contracts/configure.schema.json" \
        >"${oldBundle}/schema.next"
    mv "${oldBundle}/schema.next" "${oldBundle}/docker/contracts/configure.schema.json"
    dockerBundleSupportsSpec "${oldBundle}" "${base}" || fail '旧 bundle 不再接受旧无字段规格'
    for mutation in "${enabled}" "${nullSpec}"; do
        if dockerBundleSupportsSpec "${oldBundle}" "${mutation}" >/dev/null 2>"${STDERR}"; then
            fail '旧 schema bundle 接受了新增共存字段'
        fi
    done

    newState stream "${enabled}"
    currentBundle=$(dockerCurrentBundlePath)
    dockerBundleSupportsSpec "${currentBundle}" "${enabled}" || fail '当前 bundle 拒绝共存合同'
    streamFile="${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf"
    [[ -s "${streamFile}" ]] || fail '候选缺少受管 stream 配置'
    grep -Eq 'ws[.]example[.]com[[:space:]]+padm_website;' "${streamFile}" &&
        grep -Eq 'server[[:space:]]+127[.]0[.]0[.]1:8443;' "${streamFile}" &&
        grep -Eq 'default[[:space:]]+padm_reality;' "${streamFile}" &&
        grep -Eq 'server[[:space:]]+xray:24443;' "${streamFile}" &&
        grep -Eq 'listen[[:space:]]+15443;' "${streamFile}" &&
        grep -Fq 'ssl_preread on;' "${streamFile}" ||
        fail 'stream 目标、监听或 SNI 预读配置错误'
    ! grep -Eq '^[[:space:]]*proxy_protocol[[:space:]]+on;' "${streamFile}" ||
        fail 'stream 擅自发送 PROXY protocol'
    jq -e '
      .services.xray.ports == ["0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp"] and
      .services.nginx.ports == ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"] and
      .services.nginx.depends_on.xray.condition == "service_healthy" and
      any(.services.nginx.volumes[];
        .target == "/etc/nginx/stream.d" and .read_only == true and
        (.source | endswith("/config/nginx/stream")))
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '共存 Compose 映射、健康依赖或 stream 挂载错误'
    jq -e '
      [.listeners[] | select(.listener_id == "vless-reality" or .listener_id == "vless-ws")] |
      length == 2 and all(.[]; .service == "nginx" and .public_port == 443 and
        .container_port == 15443 and .transport == "tcp")
    ' "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail '共存部署记录没有使用有效公网映射'
    cp "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" "${TEST_ROOT}/stream-core.json"
    dockerGenerateSubscription "${base}" "${TEST_ROOT}/stream-original-links"
    otherUri=$(tail -n 1 "${TEST_ROOT}/stream-original-links")
    streamRealityUri=${REALITY_URI/\[2001:db8::1\]/proxy.example.com}
    streamRealityUri=${streamRealityUri/:24443/:443}
    streamWsUri=${WS_URI/:24444/:443}
    runRead 0 stream-links dockerProtocolCommand links
    [[ "$(<"${STDOUT}")" == "${streamRealityUri}"$'\n'"${streamWsUri}"$'\n'"${otherUri}" ]] ||
        fail '共存公开链接或未选入口发生错误'
    runRead 0 stream-selected-reality bash -u "${CLI}" protocol links vless-reality
    [[ "$(<"${STDOUT}")" == "${streamRealityUri}" ]] || fail '共存 Reality 单入口链接不精确'
    runRead 0 stream-selected-site dockerProtocolCommand links vless-ws
    [[ "$(<"${STDOUT}")" == "${streamWsUri}" ]] || fail '共存网站单入口链接不精确'
    runRead 0 stream-list dockerProtocolCommand list
    grep -Fq 'proxy.example.com:443' "${STDOUT}" &&
        grep -Fq 'proxy.example.com:24445' "${STDOUT}" || fail '列表未显示有效共存端口'
    cp "${streamFile}" "${TEST_ROOT}/stream-conf.saved"
    printf '\n# 配置漂移\n' >>"${streamFile}"
    runRead 15 stream-config-drift dockerProtocolCommand links
    cp "${TEST_ROOT}/stream-conf.saved" "${streamFile}"
    runRead 15 stream-apply-gated dockerConfigureApply "${enabled}" '' '' preview
    runRead 15 stream-disable-gated dockerConfigureApply "${base}" '' '' preview
    runRead 15 stream-compose-up-gated dockerComposeRun up -d
    grep -Fq "${guardMessage}" "${STDERR}" || fail 'Compose 启动未到达共存部署门禁'
    for mutation in up restart update; do
        runRead 15 "stream-public-${mutation}-gated" bash -u "${CLI}" "${mutation}"
        grep -Fq "${guardMessage}" "${STDERR}" || fail "公开 ${mutation} 未到达共存部署门禁"
    done
    dockerBackupConfiguration || fail '共存备份生成失败'
    streamBackup=${DOCKER_CONFIG_BACKUP}
    dockerValidateConfigurationBackup "${streamBackup}" || fail '共存恢复夹具不是有效备份'
    dockerCreateConfigurationCandidate || fail '关闭候选目录创建失败'
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${base}" "${candidate}" || fail '关闭候选生成失败'
    runRead 1 stream-install-current-gated dockerInstallCandidate "${candidate}" "${streamBackup}"
    grep -Fq "${guardMessage}" "${STDERR}" &&
        [[ "${DOCKER_CONFIG_SWITCHED}" == 0 ]] || fail '安装拒绝发生在文件切换之后'
    dockerCleanupConfigurationCandidate || fail '关闭候选清理失败'
    (
        DOCKER_CONFIG_BACKUP=${streamBackup}
        DOCKER_CONFIG_SWITCHED=1
        runRead 1 stream-restore-current-gated dockerRestoreConfiguration
        grep -Fq "${guardMessage}" "${STDERR}" || fail '备份恢复未到达共存部署门禁'
    )

    # 关闭投影只撤销绑定；原核心端口、凭据和未选入口保持原样。
    newState stream-disabled "${base}"
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" ]] ||
        fail '关闭投影仍生成 stream 配置'
    cmp -s "${TEST_ROOT}/stream-core.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" ||
        fail '共存投影改写了核心内部端口、凭据或账号'
    jq -e '
      .services.xray.ports == ["0.0.0.0:24443:24443/tcp","[::]:24443:24443/tcp",
        "0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp"] and
      .services.nginx.ports == ["[::]:24444:8443/tcp","0.0.0.0:24444:8443/tcp"] and
      all(.services.nginx.volumes[]; .target != "/etc/nginx/stream.d")
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '关闭投影没有恢复原宿主映射'
    runRead 0 stream-disabled-links dockerProtocolCommand links
    [[ "$(<"${STDOUT}")" == "$(<"${TEST_ROOT}/stream-original-links")" ]] ||
        fail '关闭投影没有恢复原公开链接'
    runRead 15 stream-enable-gated dockerConfigureApply "${enabled}" '' '' preview
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/stream-spec.saved"
    for malformed in malformed symlink multiple; do
        case "${malformed}" in
        malformed) printf 'not-json\n' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ;;
        symlink)
            rm "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
            ln -s "${TEST_ROOT}/stream-spec.saved" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
            ;;
        multiple)
            cat "${TEST_ROOT}/stream-spec.saved" "${TEST_ROOT}/stream-spec.saved" \
                >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
            ;;
        esac
        runRead 15 "stream-compose-${malformed}-gated" dockerComposeRun up -d
        grep -Fq "${guardMessage}" "${STDERR}" || fail "异常规格 ${malformed} 绕过部署门禁"
        rm "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        cp "${TEST_ROOT}/stream-spec.saved" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    done
    # 当前部署不含共存时，也必须拒绝候选和恢复点携带的共存绑定。
    cp -a "${streamBackup}" "${PADM_DOCKER_INSTALL_DIR}/backups/stream-source"
    streamBackup="${PADM_DOCKER_INSTALL_DIR}/backups/stream-source"
    dockerValidateConfigurationBackup "${streamBackup}" || fail '新根目录的共存备份夹具无效'
    dockerCreateConfigurationCandidate || fail '共存候选目录创建失败'
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerGenerateCandidate "${enabled}" "${candidate}" || fail '共存候选生成失败'
    runRead 1 stream-install-source-gated dockerInstallCandidate "${candidate}" "${streamBackup}"
    grep -Fq "${guardMessage}" "${STDERR}" &&
        [[ "${DOCKER_CONFIG_SWITCHED}" == 0 ]] || fail '共存候选拒绝发生在文件切换之后'
    dockerCleanupConfigurationCandidate || fail '共存候选清理失败'
    (
        DOCKER_CONFIG_BACKUP=${streamBackup}
        DOCKER_CONFIG_SWITCHED=1
        runRead 1 stream-restore-source-gated dockerRestoreConfiguration
        grep -Fq "${guardMessage}" "${STDERR}" || fail '共存恢复点未到达部署门禁'
    )
    newState stream-xhttp "${xhttp}"
    grep -Eq 'server[[:space:]]+xray:24443;' \
        "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" ||
        fail 'XHTTP 共存改变原内部监听'
    runRead 0 stream-xhttp-links dockerProtocolCommand links entry-xhttp
    grep -Fq 'proxy.example.com:443?' "${STDOUT}" &&
        grep -Fq '&type=xhttp&host=www.example.com&path=%2Fstream-xhttp&mode=auto' "${STDOUT}" ||
        fail 'XHTTP 共存链接错误'
    newState stream-upgrade "${upgrade}"
    jq -e '.services.nginx.depends_on.xray.condition == "service_healthy" and
      .services.nginx.depends_on["sing-box"].condition == "service_healthy"' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '副核心 TLS 共存缺少独立 Reality 健康依赖'
    if ! (
        calls="${TEST_ROOT}/stream-validate-compose.calls"
        : >"${calls}"
        dockerCandidateCompose() {
            local candidate=$1
            shift
            printf '%s\n' "$*" >>"${calls}"
        }
        dockerTlsValidateCandidate() { return 0; }
        dockerValidateHostIntegrations() { return 0; }
        validateStreamCandidate() {
            local spec=$1 label=$2 candidate line
            dockerCreateConfigurationCandidate || return 1
            candidate=${DOCKER_CONFIG_CANDIDATE}
            dockerGenerateCandidate "${spec}" "${candidate}" || return 1
            dockerValidateCandidate "${spec}" "${candidate}" || return 1
            line=$(grep 'nginx -t$' "${calls}" | tail -n 1) || return 1
            case "${label}" in
            enabled)
                [[ "${line}" == *'--add-host xray:127.0.0.1'* &&
                    "${line}" == *'--add-host subscription:127.0.0.1'* ]] || return 1
                ;;
            upgrade)
                [[ "${line}" == *'--add-host xray:127.0.0.1'* &&
                    "${line}" == *'--add-host sing-box:127.0.0.1'* &&
                    "${line}" != *'subscription'* ]] || return 1
                ;;
            disabled)
                [[ "${line}" != *'--add-host'* ]] || return 1
                ;;
            esac
            dockerCleanupConfigurationCandidate
        }
        validateStreamCandidate "${enabled}" enabled &&
            validateStreamCandidate "${upgrade}" upgrade &&
            validateStreamCandidate "${base}" disabled
    ); then
        fail '候选 Nginx 校验未按共存核心与订阅服务注入临时 hosts'
    fi
    printf 'docker-reality-stream-contract-ok\n'
}
