#!/usr/bin/env bash

dockerRealityStreamContractChecks() {
    local base="${TEST_ROOT}/stream-base.json" enabled="${TEST_ROOT}/stream-enabled.json"
    local invalid="${TEST_ROOT}/stream-invalid.json" nullSpec="${TEST_ROOT}/stream-null.json"
    local xhttp="${TEST_ROOT}/stream-xhttp.json" oldBundle="${TEST_ROOT}/stream-old-bundle"
    local upgrade="${TEST_ROOT}/stream-upgrade.json" mutation streamFile
    local streamRealityUri streamWsUri otherUri currentBundle websiteType version
    local malformed guardMessage='受管配置规格损坏或不安全，拒绝部署'
    local capture="${TEST_ROOT}/stream-edit-captured.json" alternate="${TEST_ROOT}/stream-alternate.json"

    streamEditContractRead() (
        local destination=$1
        shift
        trap 'dockerSetupCleanup; dockerReleaseDeploymentLock' EXIT
        dockerConfigureReleasePrepare() { return 0; }
        dockerConfigureReleaseValidate() { return 0; }
        dockerManifestImageReference() { printf 'fixture-image\n'; }
        dockerSetupRealityPublicKey() { cat >/dev/null; printf '%s\n' "${PUBLIC_KEY}"; }
        dockerConfigureApply() { cp "$1" "${destination}"; }
        # 编辑预览不是链接输出；私密文件保留冻结失败之前的预览。
        dockerEditCommand "$@" >"${TEST_ROOT}/stream-edit-preview"
    )
    streamMenuContractRead() (
        local input=$1
        : >"${TEST_ROOT}/stream-menu.calls"
        dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/stream-menu.calls"; }
        printf '%s' "${input}" | dockerMenuProtocols
    )
    streamContainerBoundary() {
        if [[ "$*" == 'info --format {{.ServerVersion}}' ]]; then
            printf '29.0.0\n'
            return 0
        fi
        printf '%s\n' "$*" >>"${calls}"
        case "$*" in
        "ps --filter label=io.padm.project=${PADM_DOCKER_PROJECT} --format {{.ID}}")
            printf 'aaaaaaaaaaaa\n' ;;
        "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx")
            printf 'aaaaaaaaaaaa\n' ;;
        "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray")
            printf 'bbbbbbbbbbbb\n' ;;
        "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx-stream")
            printf 'cccccccccccc\n' ;;
        'stop aaaaaaaaaaaa'|'stop bbbbbbbbbbbb'|'stop cccccccccccc'|\
        'stop aaaaaaaaaaaa bbbbbbbbbbbb'|'stop aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc') ;;
        *) return 1 ;;
        esac
    }
    streamRestoreContract() (
        local label=$1 original=$2 current=$3 transition=$4
        local calls="${TEST_ROOT}/stream-restore-${label}.calls" backup before expected actual=0
        local hostStop=0 action=${label#loopback-}
        newState "stream-restore-${label}" "${original}"
        if [[ "${action}" == rollback ]]; then
            dockerBackupConfiguration update || fail '共存回滚夹具备份失败'
        else
            dockerBackupConfiguration || fail "${label}: 共存恢复夹具备份失败"
        fi
        backup=${DOCKER_CONFIG_BACKUP}
        : >"${calls}"
        docker() { streamContainerBoundary "$@"; }
        dockerComposeRun() { printf 'compose %s\n' "$*" >>"${calls}"; }
        dockerRenewalScheduleInstall() { printf 'renewal\n' >>"${calls}"; }
        DOCKER_CONFIG_SWITCHED=1
        DOCKER_CONFIG_STREAM_TRANSITION=${transition}
        case "${current}" in
        corrupt) printf 'not-json\n' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ;;
        *) cp "${current}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ;;
        esac
        if jq -e '.reality_stream.host_website.network_mode == "host"' "${original}" >/dev/null ||
            { [[ "${current}" != corrupt ]] &&
                jq -e '.reality_stream.host_website.network_mode == "host"' "${current}" >/dev/null; }; then
            hostStop=1
        fi
        if [[ "${label}" == bad-backup ]]; then
            printf 'not-json\n' >"${backup}/config/spec.json"
            before=$(snapshot)
            if dockerRestoreConfiguration >"${STDOUT}" 2>"${STDERR}"; then
                fail '损坏共存备份被恢复'
            fi
            [[ ! -s "${calls}" && "$(snapshot)" == "${before}" ]] ||
                fail '损坏共存备份在拒绝前停服或写入'
            exit 0
        fi
        if [[ "${action}" == rollback ]]; then
            dockerCreateConfigurationCandidate &&
                dockerGenerateCandidate "${current}" "${DOCKER_CONFIG_CANDIDATE}" &&
                dockerInstallCandidate "${DOCKER_CONFIG_CANDIDATE}" "${backup}" &&
                dockerEnsureRuntimeDataPermissions &&
                dockerCleanupConfigurationCandidate || fail '共存回滚当前部署夹具失败'
            DOCKER_CONFIG_SWITCHED=0
            DOCKER_CONFIG_STREAM_TRANSITION=0
            : >"${calls}"
            dockerHostPreflight() { return 0; }
            dockerTrafficRuntimeCheck() { return 0; }
            dockerTrafficBeforeChange() { return 0; }
            dockerTrafficScheduleInstall() { return 0; }
            dockerRollbackCommand >"${STDOUT}" || fail '合法共存 update 备份无法通过命令回滚'
            dockerReleaseDeploymentLock
        elif [[ "${action}" == interrupted ]]; then
            (
                trap 'printf "%s %s\n" "${DOCKER_CONFIG_SWITCHED}" "${DOCKER_CONFIG_STREAM_TRANSITION}" >"${calls}.flags"' EXIT
                trap 'dockerCommandInterrupted 143' TERM
                kill -s TERM "${BASHPID}"
            ) || actual=$?
            [[ "${actual}" == 143 && "$(<"${calls}.flags")" == '0 0' ]] ||
                fail 'TERM 未沿生产处理器退出或完成共存恢复'
        else
            dockerRestoreConfiguration || fail "${label}: 合法共存备份无法恢复"
        fi
        if [[ "${action}" != interrupted ]]; then
            [[ "${DOCKER_CONFIG_SWITCHED}" == 0 && "${DOCKER_CONFIG_STREAM_TRANSITION}" == 0 &&
                "${DOCKER_CONFIG_STREAM_HOST_TRANSITION:-0}" == 0 ]] ||
                fail "${label}: 共存恢复未清除事务标记"
        fi
        cmp -s "${original}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" &&
            cmp -s "${backup}/compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json" &&
            cmp -s "${backup}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json" &&
            [[ "$(stat -c '%a %u' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")" == '600 0' ]] ||
            fail "${label}: 恢复未还原原规格、映射、权限或事务标记"
        expected="ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray"$'\nstop aaaaaaaaaaaa bbbbbbbbbbbb\n'"compose up -d --force-recreate --wait --wait-timeout ${PADM_DOCKER_HEALTH_TIMEOUT:-60}"$'\nrenewal'
        if [[ "${hostStop}" == 1 ]]; then
            expected="ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx-stream"$'\nstop aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc\n'"compose up -d --force-recreate --wait --wait-timeout ${PADM_DOCKER_HEALTH_TIMEOUT:-60}"$'\nrenewal'
        fi
        if [[ "${action}" == rollback ]]; then
            expected="ps --filter label=io.padm.project=${PADM_DOCKER_PROJECT} --format {{.ID}}"$'\n'"ps --filter label=io.padm.project=${PADM_DOCKER_PROJECT} --format {{.ID}}"$'\n'"${expected}"
        fi
        if [[ "$(<"${calls}")" != "${expected}" ]]; then
            printf 'stream-restore-actions:%s\nactual:\n%s\nexpected:\n%s\n' \
                "${label}" "$(<"${calls}")" "${expected}" >&2
            fail "${label}: 共存恢复没有精确释放 nginx/xray 或错误调用 down"
        fi
    )
    streamUpdateContractRead() (
        local requestedBundle=$1 reject=$2 calls="${TEST_ROOT}/stream-update.calls"
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        : >"${calls}"
        DOCKER_CONFIG_BACKUP=
        PADM_DOCKER_MANIFEST_FILE="${TEST_ROOT}/stream-update-manifest.json"
        PADM_DOCKER_MANIFEST_SHA256=$(jq -r '.release.manifest_sha256' "${enabled}")
        PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=fixture
        jq -n '{release:{commit:("f" * 40)}}' >"${PADM_DOCKER_MANIFEST_FILE}"
        dockerManifestPrepare() { return 0; }
        dockerStageReleaseBundle() { DOCKER_STAGED_BUNDLE_PATH=${requestedBundle}; }
        dockerRenewalBundleCheck() { return 0; }
        dockerPullManifestImages() { return 0; }
        dockerTrafficRuntimeCheck() { return 0; }
        dockerTrafficBeforeChange() { return 0; }
        dockerManifestReleaseVersion() { jq -r '.release.version' "${enabled}"; }
        dockerManifestImageReference() { jq -r --arg core "$1" '.images[$core]' "${enabled}"; }
        dockerManifestImageDigest() { printf 'sha256:%s\n' "${PADM_DOCKER_MANIFEST_SHA256}"; }
        dockerManifestConfigurationInputs() { jq -c '{release,images}' "${enabled}"; }
        dockerCandidateCompose() {
            shift
            printf '%s\n' "$*" >>"${calls}"
            [[ "${reject}" != nginx || "$*" != *'nginx -t' ]]
        }
        dockerTlsValidateCandidate() { return 0; }
        dockerValidateHostIntegrations() { return 0; }
        dockerUpdateCommand
    )
    streamFirstConfigureRestore() (
        local calls="${TEST_ROOT}/stream-first-restore.calls" candidate backup
        local tlsSource="${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
        export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/stream-first-restore"
        dockerInitializeStateRoot &&
            dockerStageBundle "${SOURCE_ROOT}" ffffffffffffffffffffffffffffffffffffffff &&
            dockerActivateStagedBundle &&
            dockerCleanupStagedBundle &&
            cp -a "${tlsSource}/." "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/" &&
            dockerCreateConfigurationCandidate || fail '首次共存恢复骨架夹具失败'
        candidate=${DOCKER_CONFIG_CANDIDATE}
        dockerGenerateCandidate "${enabled}" "${candidate}" &&
            dockerBackupConfiguration || fail '首次共存恢复候选或备份失败'
        backup=${DOCKER_CONFIG_BACKUP}
        [[ ! -e "${backup}/deployment.json" ]] || fail '首次共存恢复夹具已有旧部署'
        : >"${calls}"
        docker() { streamContainerBoundary "$@"; }
        dockerComposeRun() { printf 'compose %s\n' "$*" >>"${calls}"; }
        dockerTrafficScheduleRemove() { return 0; }
        dockerRenewalScheduleInstall() { printf 'renewal\n' >>"${calls}"; }
        dockerInstallCandidate "${candidate}" "${backup}" &&
            dockerRestoreConfiguration &&
            dockerCleanupConfigurationCandidate || fail '首次共存部署失败无法恢复骨架'
        [[ "${DOCKER_CONFIG_SWITCHED}" == 0 && "${DOCKER_CONFIG_STREAM_TRANSITION}" == 0 &&
            "$(<"${calls}")" == $'compose down\nrenewal' ]] ||
            fail '首次共存失败恢复没有全项目 down，可能遗留订阅或副核心容器'
        for file in deployment.json compose.json images.env config/spec.json config/nginx/stream/reality.conf; do
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/${file}" ]] || fail "首次共存恢复残留 ${file}"
        done
    )

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
    cp "${SOURCE_ROOT}/docker/contracts/configure.schema.json" "${oldBundle}/docker/contracts/configure.schema.json"
    jq 'del(.["x-padm-reality-stream-deployment"])' \
        "${oldBundle}/docker/contracts/configure.schema.json" >"${oldBundle}/schema.next"
    mv "${oldBundle}/schema.next" "${oldBundle}/docker/contracts/configure.schema.json"
    if dockerBundleSupportsSpec "${oldBundle}" "${enabled}" >/dev/null 2>"${STDERR}"; then
        fail '只有生成合同的旧 bundle 接受了共存部署'
    fi
    dockerBundleSupportsSpec "${oldBundle}" "${nullSpec}" || fail '旧部署合同拒绝无共存的 v3 规格'
    dockerRealityStreamDeploymentCheck "${enabled}" "${base}" "${nullSpec}" ||
        fail '当前控制包拒绝合法共存部署规格'

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
    runRead 0 stream-status bash -u "${CLI}" protocol stream-status
    grep -Fxq 'Reality 443 共存: 已启用' "${STDOUT}" &&
        grep -Fxq '网站 TLS 后端: nginx:8443' "${STDOUT}" &&
        grep -Fxq 'Reality 原后端: xray:24443' "${STDOUT}" &&
        grep -Fq 'proxy.example.com:443' "${STDOUT}" || fail '共存状态缺失有效或恢复端口'
    for mutation in "${UUID}" "${PRIVATE_KEY}" "${PUBLIC_KEY}" "${TOKEN}" abcdefgh; do
        ! grep -Fq "${mutation}" "${STDOUT}" || fail '共存状态暴露协议秘密'
    done
    runRead 0 stream-tls-consumers dockerTlsConsumers ws.example.com
    [[ "$(<"${STDOUT}")" == '["nginx"]' ]] || fail '受管共存 TLS 消费者识别错误'
    printf 'server {}\n' >"${PADM_DOCKER_INSTALL_DIR}/config/nginx/unmanaged.conf"
    runRead 1 stream-tls-extra-conf dockerTlsConsumers ws.example.com
    rm "${PADM_DOCKER_INSTALL_DIR}/config/nginx/unmanaged.conf"
    cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/stream-compose.saved"
    for mutation in /etc/nginx/stream.d/reality.conf /etc/nginx/nginx.conf; do
        jq --arg target "${mutation}" '.services.nginx.volumes += [{
          type:"bind",source:"/tmp/unmanaged.conf",target:$target,read_only:true}]' \
            "${TEST_ROOT}/stream-compose.saved" >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
        runRead 1 stream-tls-overlay dockerTlsConsumers ws.example.com
    done
    cp "${TEST_ROOT}/stream-compose.saved" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    if ! (
        calls="${TEST_ROOT}/stream-transition.calls"
        saved="${TEST_ROOT}/stream-deployment.saved"
        cp "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${saved}" || exit 1
        trap 'cp "${saved}" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"' EXIT
        docker() { streamContainerBoundary "$@"; }
        for owner in nginx xray; do
            jq --arg owner "${owner}" '.listeners[0].service = $owner |
              .listeners[1].public_port = 24444' "${saved}" \
                >"${PADM_DOCKER_INSTALL_DIR}/deployment.json" || exit 1
            : >"${calls}"
            dockerRealityStreamTransitionPrepare "${base}" || exit 1
            if [[ "${owner}" == nginx ]]; then id=aaaaaaaaaaaa; else id=bbbbbbbbbbbb; fi
            [[ "$(<"${calls}")" == \
                "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=${owner}"$'\n'"stop ${id}" ]] || exit 1
        done
        jq '.listeners |= map(.public_port = 24446)' "${saved}" \
            >"${PADM_DOCKER_INSTALL_DIR}/deployment.json" || exit 1
        : >"${calls}"
        dockerRealityStreamTransitionPrepare "${base}" && [[ ! -s "${calls}" ]] || exit 1
        jq '.listeners[0].service = "net-wireguard"' "${saved}" \
            >"${PADM_DOCKER_INSTALL_DIR}/deployment.json" || exit 1
        if dockerRealityStreamTransitionPrepare "${base}"; then exit 1; fi
        [[ ! -s "${calls}" ]]
    ); then
        fail '443 交接停止了非拥有者，遗漏旧拥有者或接受非法服务'
    fi
    runRead 15 stream-update-no-capability streamUpdateContractRead "${oldBundle}" capability
    [[ ! -s "${TEST_ROOT}/stream-update.calls" ]] ||
        fail '缺共存能力的更新包仍进入候选容器校验'
    runRead 15 stream-update-nginx-failure streamUpdateContractRead "${currentBundle}" nginx
    grep -Fq 'nginx -t' "${TEST_ROOT}/stream-update.calls" &&
        grep -Fq 'Nginx 候选配置校验失败' "${STDERR}" ||
        fail '共存更新没有在备份和停服前拒绝 Nginx 校验失败'
    streamRestoreContract corrupt-current "${enabled}" corrupt 1
    streamRestoreContract bad-backup "${enabled}" corrupt 1
    streamRestoreContract enable-failed "${base}" "${enabled}" 1
    streamRestoreContract disable-failed "${enabled}" "${base}" 0
    streamRestoreContract interrupted "${enabled}" corrupt 1
    streamRestoreContract rollback "${enabled}" "${base}" 0
    streamFirstConfigureRestore
    runRead 2 stream-status-extra dockerProtocolCommand stream-status vless-reality
    runRead 0 stream-edit-off streamEditContractRead "${capture}" --reality-stream off --preview
    jq -en --slurpfile before "${enabled}" --slurpfile after "${capture}" \
        '($before[0] | del(.reality_stream)) == $after[0]' >/dev/null ||
        fail '关闭共存专项草稿改写了其它字段'
    for mutation in \
        '.core.protocols[0].public_port = 24447' \
        '.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' \
        '.core.protocols[0].listener_id = "entry-reidentified" |
          .reality_stream.listener_id = "entry-reidentified"' \
        '.core.protocols[0].address_families = ["ipv4"] |
          .core.protocols[1].address_families = ["ipv4"]' \
        '.core.protocols[2].public_port = 443'; do
        jq "${mutation}" "${enabled}" >"${invalid}" || fail '共存冻结反例生成失败'
        rm -f "${capture}"
        runRead 15 stream-edit-frozen streamEditContractRead "${capture}" --spec "${invalid}" --preview
        [[ ! -e "${capture}" ]] || fail '共存冻结失败仍进入配置提交'
    done
    cp "${streamFile}" "${TEST_ROOT}/stream-conf.saved"
    printf '\n# 配置漂移\n' >>"${streamFile}"
    runRead 15 stream-config-drift dockerProtocolCommand links
    cp "${TEST_ROOT}/stream-conf.saved" "${streamFile}"
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
    runRead 0 stream-disabled-status dockerProtocolCommand stream-status
    [[ "$(<"${STDOUT}")" == 'Reality 443 共存: 未启用' ]] || fail '关闭状态输出错误'
    runRead 0 stream-edit-enable streamEditContractRead "${capture}" \
        --reality-stream vless-reality vless-ws --preview
    jq -en --slurpfile expected "${enabled}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '开启共存专项草稿不精确'
    runRead 15 stream-edit-wrong-type streamEditContractRead "${capture}" \
        --reality-stream entry-other vless-ws --preview
    runRead 2 stream-edit-import-combined streamEditContractRead "${capture}" \
        --reality-stream vless-reality vless-ws --spec "${base}" --preview
    runRead 0 stream-menu-back streamMenuContractRead $'6\n0\n0\n'
    [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == 'protocol list' ]] ||
        fail '协议第 6 项返回仍调用修改动作'
    runRead 0 stream-menu-cancel streamMenuContractRead $'6\n2\n0\n0\n0\n'
    [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == $'protocol list\nprotocol list' ]] ||
        fail '共存菜单取消仍提交编辑'
    runRead 0 stream-menu-status streamMenuContractRead $'6\n1\n0\n0\n'
    [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == $'protocol list\nprotocol stream-status' ]] ||
        fail '共存菜单状态调用错误'
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
    jq '.core.protocols[2] |= (.id = 1 | del(.grpc))' "${enabled}" >"${alternate}" ||
        fail '更换默认 Reality 夹具生成失败'
    newState stream-edit-alternate "${alternate}"
    runRead 0 stream-edit-change streamEditContractRead "${capture}" \
        --reality-stream entry-other vless-ws --preview
    jq -en --slurpfile before "${alternate}" --slurpfile after "${capture}" '
      ($before[0] | del(.reality_stream)) == ($after[0] | del(.reality_stream)) and
      $after[0].reality_stream == {listener_id:"entry-other",website_listener_id:"vless-ws"}
    ' >/dev/null || fail '更换默认 Reality 改写了身份或原端口'
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
    local hostSpec="${TEST_ROOT}/stream-host.json" hostPure="${TEST_ROOT}/stream-host-pure.json"
    local hostV4="${TEST_ROOT}/stream-host-v4.json" hostV6="${TEST_ROOT}/stream-host-v6.json"
    local hostXhttp="${TEST_ROOT}/stream-host-xhttp.json" hostOldBundle="${TEST_ROOT}/stream-host-old-bundle"
    jq '.reality_stream = {listener_id:"vless-reality",host_website:{
      domains:["site.example.com","www.site.example.com"],address:"host.docker.internal",port:8443}}' \
        "${base}" >"${hostSpec}" || fail '宿主网站规格生成失败'
    jq '.core.protocols |= map(select(.listener_id == "vless-reality")) |
      .tls = null | .subscription.enabled = false' "${hostSpec}" >"${hostPure}" ||
        fail '纯 Reality 宿主网站规格生成失败'
    jq '.reality_stream.host_website.address = "192.168.10.20"' "${hostPure}" >"${hostV4}"
    jq '.reality_stream.host_website.address = "2001:db8::20"' "${hostPure}" >"${hostV6}"
    jq '.core.protocols |= map(select(.id == 2)) | .tls = null | .subscription.enabled = false |
      .reality_stream = {listener_id:"entry-xhttp",host_website:{
        domains:["site.example.com","www.site.example.com"],address:"host.docker.internal",port:8443}}' \
        "${xhttp}" >"${hostXhttp}" || fail 'XHTTP 宿主网站规格生成失败'
    for mutation in "${hostSpec}" "${hostPure}" "${hostV4}" "${hostV6}" "${hostXhttp}"; do
        dockerConfigureSpecValidate "${mutation}" || fail "合法宿主网站规格被拒绝: ${mutation}"
    done
    for mutation in \
        '.reality_stream.website_listener_id = "vless-ws"' \
        '.reality_stream.extra = true' \
        '.reality_stream.host_website.extra = true' \
        '.reality_stream.listener_id = "entry-missing"' \
        '.reality_stream.host_website.domains = []' \
        '.reality_stream.host_website.domains = ["site.example.com","site.example.com"]' \
        '.reality_stream.host_website.domains = ["SITE.example.com"]' \
        '.reality_stream.host_website.domains = ["www.example.com"]' \
        '.reality_stream.host_website.domains = [range(17) | "site" + tostring + ".example.com"]' \
        '.reality_stream.host_website.domains = ["bad_name.example.com"]' \
        '.reality_stream.host_website.port = 443' \
        '.reality_stream.host_website.port = 15443' \
        '.reality_stream.host_website.port = "8443"' \
        '.reality_stream.host_website.port = 0' \
        '.reality_stream.host_website.port = 65536' \
        '.reality_stream.host_website.port = 24443' \
        '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
          firewall_rules:[],devices:["wg-padm"],schedules:[],
          settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
        jq "${mutation}" "${hostPure}" >"${invalid}" || fail '非法宿主网站规格生成失败'
        if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
            fail "非法宿主网站规格被接受: ${mutation}"
        fi
    done
    for mutation in \
        localhost website.example.com 127.0.0.1 127.1.2.3 0.0.0.0 224.0.0.1 \
        169.254.1.1 192.168.001.2 256.1.2.3 :: ::1 ff02::1 fe80::1 \
        ::ffff:127.0.0.1 2001:::20 '[2001:db8::20]'; do
        jq --arg address "${mutation}" '.reality_stream.host_website.address = $address' \
            "${hostPure}" >"${invalid}" || fail '非法宿主地址规格生成失败'
        if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
            fail "非法宿主网站地址被接受: ${mutation}"
        fi
    done
    jq '.core.protocols += [(.core.protocols[0] |
      .listener_id = "entry-other" | .public_port = 443)]' "${hostPure}" >"${invalid}"
    if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
        fail '宿主网站共存接受第三入口占用 443'
    fi
    jq '.reality_stream.host_website.domains = ["ws.example.com"]' "${hostSpec}" >"${invalid}"
    if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
        fail '宿主网站共存接受与受管 TLS 相同的 SNI'
    fi
    mkdir -p "${hostOldBundle}/docker"
    cp -R "${SOURCE_ROOT}/docker/contracts" "${hostOldBundle}/docker/contracts"
    jq 'del(.["x-padm-reality-stream-host-website"])' \
        "${hostOldBundle}/docker/contracts/configure.schema.json" >"${hostOldBundle}/schema.next"
    mv "${hostOldBundle}/schema.next" "${hostOldBundle}/docker/contracts/configure.schema.json"
    dockerBundleSupportsSpec "${hostOldBundle}" "${enabled}" ||
        fail '旧共存包不能再使用受管网站绑定'
    if dockerBundleSupportsSpec "${hostOldBundle}" "${hostPure}" >/dev/null 2>"${STDERR}"; then
        fail '旧共存包接受没有宿主网站能力的绑定'
    fi
    newState stream-host "${hostPure}"
    streamFile="${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf"
    grep -Eq 'site[.]example[.]com[[:space:]]+padm_website;' "${streamFile}" &&
        grep -Eq 'www[.]site[.]example[.]com[[:space:]]+padm_website;' "${streamFile}" &&
        grep -Eq 'server[[:space:]]+host[.]docker[.]internal:8443;' "${streamFile}" ||
        fail '宿主网站多域名或 host-gateway 后端生成错误'
    grep -Eq 'listen[[:space:]]+8080;' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" &&
        ! grep -Eq 'ssl_certificate(_key)?[[:space:]]' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/default.conf" ||
        fail '纯宿主网站缺少健康监听或生成了网站 TLS 终止'
    jq -e '.services.xray.ports == [] and
      .services.nginx.ports == ["0.0.0.0:443:15443/tcp","[::]:443:15443/tcp"] and
      .services.nginx.extra_hosts == ["host.docker.internal:host-gateway"] and
      .services.nginx.profiles == ["nginx"] and
      .services.nginx.depends_on.xray.condition == "service_healthy" and
      (.services | has("subscription") | not) and
      all(.services.nginx.volumes[]; .target != "/etc/padm/secrets/tls") and
      all(.services.xray.volumes[]; .target != "/etc/padm/secrets/tls")
    ' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '纯 Reality 宿主网站缺少 Nginx/443/gateway 或错误挂载网站证书'
    jq -e '.compose.profiles | index("nginx") != null' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null &&
        jq -e '.listeners | length == 1 and .[0].service == "nginx" and
          .[0].public_port == 443 and .[0].container_port == 15443' \
            "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail '纯 Reality 宿主网站部署记录漏掉 Nginx 投影'
    runRead 0 stream-host-links dockerProtocolCommand links vless-reality
    [[ "$(<"${STDOUT}")" == "${streamRealityUri}" ]] || fail '宿主网站 Reality 链接未投影 443'
    runRead 0 stream-host-status dockerProtocolCommand stream-status
    grep -Fq 'site.example.com' "${STDOUT}" && grep -Fq 'www.site.example.com' "${STDOUT}" &&
        grep -Fq 'host.docker.internal:8443' "${STDOUT}" && grep -Fq 'proxy.example.com:443' "${STDOUT}" ||
        fail '宿主网站状态缺少域名、实际后端或公网端口'
    for mutation in "${UUID}" "${PRIVATE_KEY}" "${PUBLIC_KEY}" "${TOKEN}"; do
        ! grep -Fq "${mutation}" "${STDOUT}" || fail '宿主网站状态暴露秘密'
    done
    runRead 0 stream-host-no-tls-consumer dockerTlsConsumers site.example.com
    [[ "$(<"${STDOUT}")" == '[]' ]] || fail '宿主网站被误识别为容器证书消费者'
    cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/stream-host-compose.saved"
    for mutation in '.services.nginx.extra_hosts = []' '.services.nginx.network_mode = "host"'; do
        jq "${mutation}" "${TEST_ROOT}/stream-host-compose.saved" \
            >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
        runRead 1 stream-host-bridge-drift dockerTlsConsumers site.example.com
    done
    cp "${TEST_ROOT}/stream-host-compose.saved" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    runRead 15 stream-host-old-update streamUpdateContractRead "${hostOldBundle}" capability
    [[ ! -s "${TEST_ROOT}/stream-update.calls" ]] || fail '旧包宿主网站更新仍进入候选容器校验'
    newState stream-host-v4 "${hostV4}"
    grep -Eq 'server[[:space:]]+192[.]168[.]10[.]20:8443;' \
        "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" &&
        jq -e '(.services.nginx.extra_hosts // []) == []' \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail 'IPv4 宿主网站后端错误或增加多余 gateway'
    newState stream-host-v6 "${hostV6}"
    grep -Fq '[2001:db8::20]:8443' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" &&
        jq -e '(.services.nginx.extra_hosts // []) == []' \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail 'IPv6 宿主网站后端缺少方括号或增加多余 gateway'
    newState stream-host-xhttp "${hostXhttp}"
    runRead 0 stream-host-xhttp-links dockerProtocolCommand links entry-xhttp
    grep -Fq 'proxy.example.com:443?' "${STDOUT}" &&
        grep -Fq '&type=xhttp&host=www.example.com&path=%2Fstream-xhttp&mode=auto' "${STDOUT}" ||
        fail '宿主网站 XHTTP 链接投影错误'
    newState stream-host-edit "${base}"
    runRead 0 stream-host-edit-enable streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com,www.site.example.com host.docker.internal 8443 --preview
    jq -en --slurpfile expected "${hostSpec}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '宿主网站专项编辑改写其它字段'
    runRead 0 stream-host-edit-normalized-domains streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality ' SITE.Example.COM , ,WWW.SITE.Example.COM, ' host.docker.internal 8443 --preview
    jq -en --slurpfile expected "${hostSpec}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '宿主网站 CLI 域名未归一大小写、空白和空项'
    rm -f "${capture}"
    runRead 15 stream-host-edit-duplicate-domains streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com,SITE.EXAMPLE.COM host.docker.internal 8443 --preview
    [[ ! -e "${capture}" ]] || fail '宿主网站 CLI 归一后的重复域名仍进入配置提交'
    runRead 2 stream-host-edit-combined streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com host.docker.internal 8443 \
        --reality-stream off --preview
    runRead 2 stream-host-edit-port streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com host.docker.internal invalid --preview
    newState stream-managed-to-host "${enabled}"
    runRead 0 stream-managed-to-host streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com,www.site.example.com host.docker.internal 8443 --preview
    jq -en --slurpfile expected "${hostSpec}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '受管网站切换宿主网站改写了绑定以外字段'
    newState stream-host-edit-off "${hostSpec}"
    runRead 0 stream-host-to-managed streamEditContractRead "${capture}" \
        --reality-stream vless-reality vless-ws --preview
    jq -en --slurpfile expected "${enabled}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '宿主网站切换受管网站改写了绑定以外字段'
    for mutation in \
        '.core.protocols[0].public_port = 24447' \
        '.core.protocols |= map(select(.listener_id != "vless-reality"))' \
        '.reality_stream.host_website.port = 8450'; do
        jq "${mutation}" "${hostSpec}" >"${invalid}" || fail '宿主网站编辑冻结反例生成失败'
        rm -f "${capture}"
        runRead 15 stream-host-edit-import-frozen streamEditContractRead "${capture}" --spec "${invalid}" --preview
        [[ ! -e "${capture}" ]] || fail '宿主网站普通导入改写绑定、原端口或删除入口后仍提交'
    done
    runRead 0 stream-host-edit-disable streamEditContractRead "${capture}" --reality-stream off --preview
    jq -en --slurpfile expected "${base}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '宿主网站关闭未精确撤销绑定'
    for mutation in \
        $'6\n4\n0\n0\n0\n' \
        $'6\n4\nvless-reality\n0\n0\n0\n' \
        $'6\n4\nvless-reality\nsite.example.com\n0\n0\n0\n' \
        $'6\n4\nvless-reality\nsite.example.com\nhost.docker.internal\n0\n0\n0\n' \
        $'6\n4\n' \
        $'6\n4\nvless-reality\n' \
        $'6\n4\nvless-reality\nsite.example.com\n' \
        $'6\n4\nvless-reality\nsite.example.com\nhost.docker.internal\n'; do
        runRead 0 stream-host-menu-cancel streamMenuContractRead "${mutation}"
        [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == $'protocol list\nprotocol list' ]] ||
            fail '宿主网站菜单输入取消或 EOF 仍发起编辑'
    done
    runRead 0 stream-host-menu-enable streamMenuContractRead \
        $'6\n4\nvless-reality\nsite.example.com,www.site.example.com\nhost.docker.internal\n8443\n0\n0\n'
    [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == \
        $'protocol list\nprotocol list\nedit --reality-stream-host vless-reality site.example.com,www.site.example.com host.docker.internal 8443' ]] ||
        fail '宿主网站菜单未传递完整专项参数'

    # host 网络只用于专用 stream 入口，核心及网站管理链保持 bridge。
    local loopback="${TEST_ROOT}/stream-loopback.json" loopPure="${TEST_ROOT}/stream-loopback-pure.json"
    local loopV6="${TEST_ROOT}/stream-loopback-v6.json" loop443="${TEST_ROOT}/stream-loopback-443.json"
    local loopXhttp="${TEST_ROOT}/stream-loopback-xhttp.json"
    local loopOldBundle="${TEST_ROOT}/stream-loopback-old-bundle" loopMain
    jq '.reality_stream.host_website += {address:"127.0.0.1",network_mode:"host"}' \
        "${hostSpec}" >"${loopback}" || fail '回环网站混合规格生成失败'
    jq '.core.protocols |= map(select(.listener_id == "vless-reality")) |
      .core.protocols[0].address_families = ["ipv4"] |
      .tls = null | .subscription.enabled = false' "${loopback}" >"${loopPure}" ||
        fail '回环网站纯 Reality 规格生成失败'
    jq '.reality_stream.host_website.address = "::1" |
      .core.protocols[0].address_families = ["ipv6"]' "${loopPure}" >"${loopV6}" ||
        fail 'IPv6 回环网站规格生成失败'
    jq '.core.protocols[0].public_port = 443' "${loopPure}" >"${loop443}" ||
        fail '默认 443 回环网站规格生成失败'
    jq '.reality_stream.host_website += {address:"127.0.0.1",network_mode:"host"}' \
        "${hostXhttp}" >"${loopXhttp}" || fail 'XHTTP 回环网站规格生成失败'
    for mutation in "${loopback}" "${loopPure}" "${loopV6}" "${loop443}" "${loopXhttp}"; do
        dockerConfigureSpecValidate "${mutation}" || fail "合法回环网站规格被拒绝: ${mutation}"
    done
    for mutation in \
        '.reality_stream.host_website.network_mode = "bridge"' \
        '.reality_stream.host_website.network_mode = "HOST"' \
        '.reality_stream.host_website.network_mode = null' \
        '.reality_stream.host_website.address = "host.docker.internal"' \
        '.reality_stream.host_website.address = "localhost"' \
        '.reality_stream.host_website.address = "127.1.2.3"' \
        '.reality_stream.host_website.address = "::ffff:127.0.0.1"' \
        '.reality_stream.host_website.address = "[::1]"' \
        '.reality_stream.host_website.address = "192.168.10.20"' \
        '.reality_stream.host_website.port = 443' \
        '.reality_stream.host_website.port = 15443' \
        '.reality_stream.host_website.port = 24443' \
        '.core.protocols[2].public_port = 15443'; do
        jq "${mutation}" "${loopback}" >"${invalid}" || fail '非法回环网站规格生成失败'
        if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
            fail "非法回环网站规格被接受: ${mutation}"
        fi
    done
    jq 'del(.reality_stream.host_website.network_mode)' "${loopPure}" >"${invalid}"
    if dockerConfigureSpecValidate "${invalid}" >/dev/null 2>"${STDERR}"; then
        fail '无显式 host 模式的旧规格接受回环网站地址'
    fi
    mkdir -p "${loopOldBundle}/docker"
    cp -R "${SOURCE_ROOT}/docker/contracts" "${loopOldBundle}/docker/contracts"
    jq 'del(.["x-padm-reality-stream-host-network"])' \
        "${loopOldBundle}/docker/contracts/configure.schema.json" >"${loopOldBundle}/schema.next"
    mv "${loopOldBundle}/schema.next" "${loopOldBundle}/docker/contracts/configure.schema.json"
    dockerBundleSupportsSpec "${loopOldBundle}" "${hostPure}" &&
        dockerBundleSupportsSpec "${loopOldBundle}" "${enabled}" ||
        fail '旧 d1 控制包不再支持可路由宿主网站或受管网站'
    if dockerBundleSupportsSpec "${loopOldBundle}" "${loopPure}" >/dev/null 2>"${STDERR}"; then
        fail '旧 d1 控制包缺少 host-network 能力仍接受回环绑定'
    fi
    dockerRealityStreamDeploymentCheck "${loopback}" "${loopPure}" "${loopV6}" ||
        fail '当前控制包拒绝回环网站部署规格'
    newState stream-loopback "${loopPure}"
    streamFile="${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf"
    loopMain="${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/host-main"
    grep -Eq 'server[[:space:]]+127[.]0[.]0[.]1:8443;' "${streamFile}" &&
        grep -Eq 'server[[:space:]]+127[.]0[.]0[.]1:15443;' "${streamFile}" &&
        grep -Eq 'listen[[:space:]]+0[.]0[.]0[.]0:443;' "${streamFile}" &&
        ! grep -Eq 'listen[[:space:]]+\[::\]:443;' "${streamFile}" &&
        ! grep -Eq 'server[[:space:]]+xray:' "${streamFile}" ||
        fail 'IPv4 回环网站或固定 Reality 中转生成错误'
    [[ -s "${loopMain}" ]] &&
        grep -Fq 'include /etc/nginx/stream.d/reality.conf;' "${loopMain}" &&
        grep -Eq '^user[[:space:]]+padm[[:space:]]+padm;' "${loopMain}" &&
        ! grep -Eq '(^|[[:space:]])http[[:space:]]*\{|listen[[:space:]]+.*8080' "${loopMain}" ||
        fail 'host stream 主配置缺失、引用错误或带入 HTTP 健康监听'
    jq -e '.services["nginx-stream"] as $stream |
      .services.xray.ports == ["127.0.0.1:15443:24443/tcp"] and
      .services.xray.network_mode == null and
      (.services | has("nginx") | not) and
      $stream.network_mode == "host" and $stream.profiles == ["nginx-stream"] and
      $stream.ports == null and $stream.user == "0:0" and
      $stream.cap_drop == ["ALL"] and
      ($stream.cap_add | sort) == ["KILL","NET_BIND_SERVICE","SETGID","SETUID"] and
      $stream.command == ["-c","/etc/nginx/stream.d/host-main","-g","daemon off;"] and
      $stream.healthcheck.test == ["CMD","/usr/sbin/nginx","-t","-c","/etc/nginx/stream.d/host-main"] and
      $stream.depends_on.xray.condition == "service_healthy" and
      $stream.labels["io.padm.component"] == "nginx-stream" and
      ($stream.volumes | length) == 1 and
      $stream.volumes[0].target == "/etc/nginx/stream.d" and
      $stream.volumes[0].read_only == true and
      ($stream.volumes[0].source | endswith("/config/nginx/stream")) and
      (.services | has("subscription") | not)' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '回环 stream 权限、隔离、健康或固定中转 Compose 合同错误'
    jq -e '(.compose.profiles | sort) == ["core-xray","nginx-stream"] and
      (.listeners | length) == 1 and .listeners[0].service == "nginx-stream" and
      .listeners[0].public_port == 443 and .listeners[0].container_port == 443 and
      .listeners[0].address_families == ["ipv4"]' \
        "${PADM_DOCKER_INSTALL_DIR}/deployment.json" >/dev/null ||
        fail '回环入口部署记录仍使用 bridge Nginx 或旧容器端口'
    runRead 0 stream-loopback-links dockerProtocolCommand links vless-reality
    [[ "$(<"${STDOUT}")" == "${streamRealityUri}" ]] || fail '回环网站 Reality 链接未投影 443'
    runRead 0 stream-loopback-status dockerProtocolCommand stream-status
    grep -Fxq '网站网络: host（回环）' "${STDOUT}" &&
        grep -Fq '127.0.0.1:8443' "${STDOUT}" || fail '回环网站状态未显示显式 host 网络及实际后端'
    runRead 0 stream-loopback-no-tls dockerTlsConsumers site.example.com
    [[ "$(<"${STDOUT}")" == '[]' ]] || fail '回环宿主网站被误识别为容器 TLS 消费者'
    cp "${PADM_DOCKER_INSTALL_DIR}/compose.json" "${TEST_ROOT}/stream-loop-compose.saved"
    for mutation in \
        '.services["nginx-stream"].network_mode = "bridge"' \
        '.services["nginx-stream"].volumes += [{
          type:"bind",source:"/tmp/unmanaged",target:"/etc/nginx/nginx.conf",read_only:true}]' \
        '.services["nginx-stream"].cap_add = ["NET_ADMIN"]' \
        '.services.xray.ports = ["0.0.0.0:15443:24443/tcp"]'; do
        jq "${mutation}" "${TEST_ROOT}/stream-loop-compose.saved" \
            >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
        runRead 15 stream-loop-compose-drift dockerProtocolCommand links
    done
    cp "${TEST_ROOT}/stream-loop-compose.saved" "${PADM_DOCKER_INSTALL_DIR}/compose.json"
    cp "${loopMain}" "${TEST_ROOT}/stream-loop-main.saved"
    printf '\nhttp { server { listen 8080; } }\n' >>"${loopMain}"
    runRead 15 stream-loop-main-drift dockerProtocolCommand links
    cp "${TEST_ROOT}/stream-loop-main.saved" "${loopMain}"
    newState stream-loopback-v6 "${loopV6}"
    grep -Fq '[::1]:8443' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" &&
        grep -Eq 'listen[[:space:]]+\[::\]:443' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" &&
        ! grep -Eq 'listen[[:space:]]+(0[.]0[.]0[.]0:)?443;' "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/reality.conf" &&
        jq -e '.services.xray.ports == ["127.0.0.1:15443:24443/tcp"]' \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail 'IPv6-only 入口没有限定地址族、网站回环或固定 IPv4 内部中转'
    newState stream-loopback-443 "${loop443}"
    jq -e '.services.xray.ports == ["127.0.0.1:15443:443/tcp"]' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail 'Reality 原端口 443 与 host stream 公网 443 发生错误映射'
    newState stream-loopback-xhttp "${loopXhttp}"
    runRead 0 stream-loopback-xhttp-links dockerProtocolCommand links entry-xhttp
    grep -Fq 'proxy.example.com:443?' "${STDOUT}" &&
        grep -Fq '&type=xhttp&host=www.example.com&path=%2Fstream-xhttp&mode=auto' "${STDOUT}" ||
        fail '回环网站 XHTTP 链接或参数错误'
    newState stream-loopback-mixed "${loopback}"
    jq -e '.services.nginx.network_mode == null and
      .services.nginx.ports == ["[::]:24444:8443/tcp","0.0.0.0:24444:8443/tcp"] and
      all(.services.nginx.volumes[]; .target != "/etc/nginx/stream.d") and
      .services.nginx.depends_on.subscription.condition == "service_healthy" and
      .services.subscription.network_mode == null and .services.subscription.ports == null and
      .services.xray.ports == ["0.0.0.0:24445:24445/tcp","[::]:24445:24445/tcp",
        "127.0.0.1:15443:24443/tcp"]' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail '回环 stream 改写了其它协议、受管 Nginx 或订阅 bridge 网络'
    runRead 0 stream-loopback-managed-tls dockerTlsConsumers ws.example.com
    [[ "$(<"${STDOUT}")" == '["nginx"]' ]] || fail '回环混合部署误改受管网站 TLS 消费者'
    cp "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/host-main" "${TEST_ROOT}/stream-loop-main.saved"
    printf '\nhttp { server { listen 8080; } }\n' >>"${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/host-main"
    runRead 1 stream-loopback-tls-main-drift dockerTlsConsumers ws.example.com
    cp "${TEST_ROOT}/stream-loop-main.saved" "${PADM_DOCKER_INSTALL_DIR}/config/nginx/stream/host-main"
    if ! (
        calls="${TEST_ROOT}/stream-loop-candidate.calls"
        : >"${calls}"
        dockerCandidateCompose() { shift; printf '%s\n' "$*" >>"${calls}"; }
        dockerRealityStreamHostProbe() { printf 'host-probe %s\n' "$2" >>"${calls}"; }
        dockerTlsValidateCandidate() { return 0; }
        dockerValidateHostIntegrations() { return 0; }
        dockerCreateConfigurationCandidate &&
            dockerGenerateCandidate "${loopback}" "${DOCKER_CONFIG_CANDIDATE}" &&
            dockerValidateCandidate "${loopback}" "${DOCKER_CONFIG_CANDIDATE}" &&
            grep -Fxq 'run --rm --no-deps nginx-stream -t -c /etc/nginx/stream.d/host-main' "${calls}" &&
            [[ "$(tail -n 1 "${calls}")" == 'host-probe backend' ]] &&
            dockerCleanupConfigurationCandidate
    ); then
        fail 'host stream 候选未校验专用 Nginx 主配置及回环网站 TLS'
    fi
    if ! (
        local probeReject=0 calls="${TEST_ROOT}/stream-loop-probe.calls"
        docker() { [[ "$*" == 'info --format {{.ServerVersion}}' ]] && printf '29.0.0\n'; }
        dockerRealityProbeRun() {
            [[ "$#" == 17 && "$1" == 45 && "$2" == --network && "$3" == host &&
                "$4" == --user && "$5" == 0:0 && "$6" == --cap-add &&
                "$7" == NET_BIND_SERVICE && "$8" == --entrypoint && "$9" == python3 &&
                "${10}" == "$(jq -r '.images.ops' "${loopback}")" && "${11}" == -c &&
                "${14}" == 127.0.0.1 && "${15}" == 8443 &&
                "${16}" == '["site.example.com","www.site.example.com"]' &&
                "${17}" == '["ipv4","ipv6"]' ]] || return 1
            printf '%s\n' "${13}" >>"${calls}"
            printf '%s\n' "${12}" >"${TEST_ROOT}/stream-loop-probe.py"
            [[ "${probeReject}" == 0 ]]
        }
        : >"${calls}"
        dockerRealityStreamHostProbe "${loopback}" backend &&
            dockerRealityStreamHostProbe "${loopback}" ports &&
            [[ "$(<"${calls}")" == $'backend\nports' ]] &&
            grep -Fq 'ssl.create_default_context()' "${TEST_ROOT}/stream-loop-probe.py" &&
            grep -Fq 'server_hostname=domain' "${TEST_ROOT}/stream-loop-probe.py" &&
            grep -Fq 'socket.IPV6_V6ONLY, 1' "${TEST_ROOT}/stream-loop-probe.py" &&
            grep -Fq 'connection.bind(("127.0.0.1", 15443))' "${TEST_ROOT}/stream-loop-probe.py" || exit 1
        probeReject=1
        if dockerRealityStreamHostProbe "${loopback}" backend >"${STDOUT}" 2>"${STDERR}"; then exit 1; fi
        [[ ! -s "${STDOUT}" ]] &&
            grep -Fq '宿主回环网站 TLS 或 host 网络端口检查失败: backend' "${STDERR}" || exit 1
        : >"${calls}"
        dockerRealityStreamHostProbe "${hostPure}" backend && [[ ! -s "${calls}" ]]
    ); then
        fail 'host 网络探测缺少专用权限、TLS SNI、IPv6/中转绑定或没有保留失败'
    fi
    if ! (
        local engineVersion=27.5.1
        docker() { [[ "$*" == 'info --format {{.ServerVersion}}' ]] && printf '%s\n' "${engineVersion}"; }
        if dockerRealityStreamHostRuntimeCheck >"${STDOUT}" 2>"${STDERR}"; then exit 1; fi
        grep -Fq 'Docker Engine 28' "${STDERR}" || exit 1
        for engineVersion in 28.0.0 29.8.2 30.0.0; do dockerRealityStreamHostRuntimeCheck || exit 1; done
        for engineVersion in '' unknown 27.99.99; do
            if dockerRealityStreamHostRuntimeCheck >/dev/null 2>"${STDERR}"; then exit 1; fi
        done
    ); then
        fail '宿主回环入口接受无法保证 loopback 隔离的旧 Engine'
    fi
    runRead 15 stream-loopback-old-update streamUpdateContractRead "${loopOldBundle}" capability
    [[ ! -s "${TEST_ROOT}/stream-update.calls" ]] || fail '旧 d1 控制包更新回环部署仍进入候选校验'
    if ! (
        calls="${TEST_ROOT}/stream-loop-transition.calls"
        : >"${calls}"
        docker() { streamContainerBoundary "$@"; }
        dockerRealityStreamTransitionPrepare "${hostPure}" &&
            [[ "$(<"${calls}")" == \
                "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx-stream"$'\nstop aaaaaaaaaaaa bbbbbbbbbbbb cccccccccccc' ]]
    ); then
        fail 'host stream 关闭交接没有精确释放 443 拥有者'
    fi
    streamRestoreContract loopback-enable-failed "${base}" "${loopback}" 1
    streamRestoreContract loopback-disable-failed "${loopback}" "${base}" 0
    streamRestoreContract loopback-corrupt-current "${loopback}" corrupt 1
    streamRestoreContract loopback-interrupted "${loopback}" corrupt 1
    streamRestoreContract loopback-rollback "${loopback}" "${base}" 0
    newState stream-loopback-edit "${base}"
    runRead 0 stream-loopback-edit streamEditContractRead "${capture}" \
        --reality-stream-loopback vless-reality site.example.com,www.site.example.com 127.0.0.1 8443 --preview
    jq -en --slurpfile expected "${loopback}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '回环网站 CLI 改写了专项绑定以外字段'
    runRead 0 stream-loopback-normalized streamEditContractRead "${capture}" \
        --reality-stream-loopback vless-reality ' SITE.Example.COM , ,WWW.SITE.Example.COM, ' 127.0.0.1 8443 --preview
    jq -en --slurpfile expected "${loopback}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '回环网站 CLI 域名未按既有规则归一'
    runRead 2 stream-loopback-edit-combined streamEditContractRead "${capture}" \
        --reality-stream-loopback vless-reality site.example.com 127.0.0.1 8443 --reality-stream off --preview
    runRead 2 stream-loopback-edit-import streamEditContractRead "${capture}" \
        --reality-stream-loopback vless-reality site.example.com 127.0.0.1 8443 --spec "${base}" --preview
    for mutation in 0 443 15443 invalid; do
        runRead 2 stream-loopback-edit-port streamEditContractRead "${capture}" \
            --reality-stream-loopback vless-reality site.example.com 127.0.0.1 "${mutation}" --preview
    done
    newState stream-loopback-edit-frozen "${loopback}"
    for mutation in \
        '.core.protocols[0].public_port = 24447' \
        '.core.protocols[0].address_families = ["ipv4"]' \
        '.reality_stream.host_website.network_mode = "bridge"' \
        '.reality_stream.host_website.address = "::1"'; do
        jq "${mutation}" "${loopback}" >"${invalid}"
        rm -f "${capture}"
        runRead 15 stream-loopback-import-frozen streamEditContractRead "${capture}" --spec "${invalid}" --preview
        [[ ! -e "${capture}" ]] || fail '回环网站普通导入绕过入口或绑定冻结'
    done
    runRead 0 stream-loopback-to-routed streamEditContractRead "${capture}" \
        --reality-stream-host vless-reality site.example.com,www.site.example.com host.docker.internal 8443 --preview
    jq -en --slurpfile expected "${hostSpec}" --slurpfile actual "${capture}" \
        '$expected[0] == $actual[0]' >/dev/null || fail '回环转 bridge 网站仍残留 host 网络字段'
    for mutation in \
        $'6\n5\n0\n0\n0\n' \
        $'6\n5\nvless-reality\n0\n0\n0\n' \
        $'6\n5\nvless-reality\nsite.example.com\n0\n0\n0\n' \
        $'6\n5\nvless-reality\nsite.example.com\n127.0.0.1\n0\n0\n0\n' \
        $'6\n5\n' \
        $'6\n5\nvless-reality\n' \
        $'6\n5\nvless-reality\nsite.example.com\n' \
        $'6\n5\nvless-reality\nsite.example.com\n127.0.0.1\n'; do
        runRead 0 stream-loopback-menu-cancel streamMenuContractRead "${mutation}"
        [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == $'protocol list\nprotocol list' ]] ||
            fail '回环网站菜单取消或 EOF 仍发起专项编辑'
    done
    runRead 0 stream-loopback-menu-enable streamMenuContractRead \
        $'6\n5\nvless-reality\nsite.example.com,www.site.example.com\n127.0.0.1\n8443\n0\n0\n'
    [[ "$(<"${TEST_ROOT}/stream-menu.calls")" == \
        $'protocol list\nprotocol list\nedit --reality-stream-loopback vless-reality site.example.com,www.site.example.com 127.0.0.1 8443' ]] ||
        fail '回环网站菜单未传递完整专项参数'
    printf 'docker-reality-stream-contract-ok\n'
}
