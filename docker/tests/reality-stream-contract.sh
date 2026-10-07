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
        printf '%s\n' "$*" >>"${calls}"
        case "$*" in
        "ps --filter label=io.padm.project=${PADM_DOCKER_PROJECT} --format {{.ID}}")
            printf 'aaaaaaaaaaaa\n' ;;
        "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx")
            printf 'aaaaaaaaaaaa\n' ;;
        "ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray")
            printf 'bbbbbbbbbbbb\n' ;;
        'stop aaaaaaaaaaaa'|'stop bbbbbbbbbbbb'|'stop aaaaaaaaaaaa bbbbbbbbbbbb') ;;
        *) return 1 ;;
        esac
    }
    streamRestoreContract() (
        local label=$1 original=$2 current=$3 transition=$4
        local calls="${TEST_ROOT}/stream-restore-${label}.calls" backup before expected actual=0
        newState "stream-restore-${label}" "${original}"
        if [[ "${label}" == rollback ]]; then
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
        if [[ "${label}" == rollback ]]; then
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
        elif [[ "${label}" == interrupted ]]; then
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
        if [[ "${label}" != interrupted ]]; then
            [[ "${DOCKER_CONFIG_SWITCHED}" == 0 && "${DOCKER_CONFIG_STREAM_TRANSITION}" == 0 ]] ||
                fail "${label}: 共存恢复未清除事务标记"
        fi
        cmp -s "${original}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" &&
            cmp -s "${backup}/compose.json" "${PADM_DOCKER_INSTALL_DIR}/compose.json" &&
            cmp -s "${backup}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json" &&
            [[ "$(stat -c '%a %u' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")" == '600 0' ]] ||
            fail "${label}: 恢复未还原原规格、映射、权限或事务标记"
        expected="ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=nginx"$'\n'"ps -q --filter label=com.docker.compose.project=${PADM_DOCKER_PROJECT} --filter label=com.docker.compose.service=xray"$'\nstop aaaaaaaaaaaa bbbbbbbbbbbb\n'"compose up -d --force-recreate --wait --wait-timeout ${PADM_DOCKER_HEALTH_TIMEOUT:-60}"$'\nrenewal'
        if [[ "${label}" == rollback ]]; then
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
    printf 'docker-reality-stream-contract-ok\n'
}
