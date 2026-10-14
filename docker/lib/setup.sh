#!/usr/bin/env bash

if [[ "${PADM_DOCKER_SETUP_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SETUP_LOADED=1
DOCKER_SETUP_CANDIDATE=

dockerSetupCleanup() {
    local root candidate=${DOCKER_SETUP_CANDIDATE:-}
    [[ -n "${candidate}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    # 挑战未恢复时保留挂载目录和恢复记录，不能把清理失败变成丢失恢复点。
    [[ -z "${DOCKER_ACME_RECOVERY:-}${DOCKER_ACME_CONTAINER:-}${DOCKER_ACME_WEBROOT:-}${DOCKER_ACME_STOPPED[*]:-}" ]] || {
        dockerError "ACME 挑战尚未恢复，保留配置候选: ${candidate}"
        return 1
    }
    dockerRemoveManagedTree "${root}" "${candidate}" || return 1
    DOCKER_SETUP_CANDIDATE=
}

dockerSetupUnconfigured() {
    local root path
    root=$(dockerInstallRoot) || return 1
    for path in deployment.json compose.json images.env config/spec.json; do
        if [[ -e "${root}/${path}" || -L "${root}/${path}" ]]; then
            dockerError '已有部署或配置记录，首次配置不会覆盖；请使用 edit 编辑或导入完整原始 spec'
            return 1
        fi
    done
}

dockerSetupReinstallAllowed() {
    local root
    root=$(dockerInstallRoot) || return 1
    dockerComposeFile >/dev/null &&
        dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerResolveRegularFile "${root}/config/spec.json" >/dev/null &&
        [[ -O "${root}/config/spec.json" ]] &&
        dockerPrivateFileIsRestricted "${root}/config/spec.json" || {
        dockerError '重装需要完整受管部署，请先使用 edit 导入完整原始规格'
        return 1
    }
    jq -e '.host_integrations == [] and .reality_stream == null and
      .port_hopping == null and .control == null and .control_sync == null' \
        "${root}/config/spec.json" >/dev/null || {
        dockerError '重新选择向导需要先停用宿主集成、共存、跳跃与控制角色；保留这些设置请使用 reinstall --spec'
        return 1
    }
}

dockerSetupRead() {
    local variable=$1 prompt=$2 default=${3:-} inputValue
    printf '%s' "${prompt}"
    IFS= read -r inputValue || return 1
    [[ "${inputValue}" != 0 ]] || return 1
    printf -v "${variable}" '%s' "${inputValue:-${default}}"
}

dockerSetupTool() {
    local image=$1
    shift
    docker run --rm --read-only --network none --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        "${image}" "$@"
}

dockerSetupRandomHex() {
    local image=$1 bytes=$2 value
    value=$(docker run --rm --read-only --network none --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint openssl "${image}" rand -hex "${bytes}" 2>/dev/null) || return 1
    [[ "${value}" =~ ^[a-f0-9]+$ && "${#value}" -eq "$((bytes * 2))" ]] || return 1
    printf '%s\n' "${value}"
}

dockerSetupRealityPublicKey() {
    local image=$1
    # 按 RFC 8410 编码交给 OpenSSL，经标准输入派生公钥，不把私钥展开到进程参数。
    docker run --rm -i --read-only --network none --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint python3 "${image}" -c '
import base64
import subprocess
import sys

private_key = base64.b64decode(sys.stdin.buffer.read().strip() + b"=", altchars=b"-_", validate=True)
if len(private_key) != 32:
    sys.exit(1)
result = subprocess.run(
    ["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
    input=bytes.fromhex("302e020100300506032b656e04220420") + private_key,
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
).stdout
if len(result) != 44 or result[:12] != bytes.fromhex("302a300506032b656e032100"):
    sys.exit(1)
print(base64.urlsafe_b64encode(result[12:]).decode("ascii").rstrip("="))
' 2>/dev/null
}

dockerSetupRealityKeyPair() {
    local xrayImage=$1 opsImage=$2 keyPair privateKey publicKey derivedPublic
    keyPair=$(dockerSetupTool "${xrayImage}" x25519 2>/dev/null) || return 1
    privateKey=$(awk '/^PrivateKey:/ { print $2; exit }' <<<"${keyPair}")
    publicKey=$(awk '/^Password \(PublicKey\):/ { print $3; exit } /^PublicKey:/ { print $2; exit }' <<<"${keyPair}")
    [[ "${privateKey}" =~ ^[A-Za-z0-9_-]{43}$ && "${publicKey}" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
    derivedPublic=$(printf '%s\n' "${privateKey}" | dockerSetupRealityPublicKey "${opsImage}") || return 1
    [[ "${derivedPublic}" == "${publicKey}" ]] || return 1
    printf '%s %s\n' "${privateKey}" "${publicKey}"
}

dockerEditRegenerateReality() {
    local draft=$1 listener=$2 xrayImage opsImage keyPair privateKey publicKey shortId
    local credentials="${1}.credentials" temporary="${1}.next"
    xrayImage=$(dockerManifestImageReference xray) || return 1
    opsImage=$(dockerManifestImageReference ops) || return 1
    keyPair=$(dockerSetupRealityKeyPair "${xrayImage}" "${opsImage}") || return 1
    read -r privateKey publicKey <<<"${keyPair}"
    shortId=$(dockerSetupRandomHex "${opsImage}" 8) || return 1
    # 重生成秘密只在私密草稿中流转，不传给进程参数或预览输出。
    (
        umask 077
        printf '%s\n%s\n%s\n' "${privateKey}" "${publicKey}" "${shortId}" >"${credentials}"
    ) || return 1
    jq --arg listener "${listener}" --rawfile credentials "${credentials}" '
      ($credentials | split("\n")) as $keys |
      .core.protocols |= map(if .listener_id != $listener then . else
        if .reality.private_key == $keys[0] or .reality.public_key == $keys[1] or .reality.short_id == $keys[2]
        then error("Reality 参数未更新") else
          .reality.private_key = $keys[0] | .reality.public_key = $keys[1] | .reality.short_id = $keys[2]
        end end)
    ' "${draft}" >"${temporary}" 2>/dev/null &&
        chmod 0600 "${temporary}" && mv -f -- "${temporary}" "${draft}" &&
        rm -f -- "${credentials}"
}

dockerSetupGenerateSpec() {
    local core=$1 protocols=$2 server=$3 families=$4 realityPort=$5 target=$6 targetPort=$7 sni=$8
    local domain=$9 wsPort=${10} subscription=${11} output=${12} secondaryCore=${13:-} secondaryPort=${14:-8444}
    local hy2Mode=${15:-bbr} hy2Up=${16:-100} hy2Down=${17:-50} hy2Obfs=${18:-false} hy2Masquerade=${19:-}
    local tuicCongestion=${20:-cubic} tuicAuthTimeout=${21:-3s} tuicHeartbeat=${22:-10s} tuicZeroRtt=${23:-false}
    local xrayImage opsImage singBoxImage uuid token shortId= privateKey= publicKey= keyPair wsPath= inputsFile obfsPassword=
    local serverPassword= userPassword= grpcService=
    [[ "${hy2Obfs}" == false || "${hy2Obfs}" == salamander || "${hy2Obfs}" == gecko ]] || return 1
    xrayImage=$(dockerManifestImageReference xray) || return 1
    opsImage=$(dockerManifestImageReference ops) || return 1
    uuid=$(dockerSetupTool "${xrayImage}" uuid 2>/dev/null) || return 1
    [[ "${uuid}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]] || return 1
    token=$(dockerSetupRandomHex "${opsImage}" 32) || return 1
    if [[ ( "${protocols}" != 2 && "${protocols}" != 6 && "${protocols}" != 7 && "${protocols}" != 8 && "${protocols}" != 9 && "${protocols}" != 10 && "${protocols}" != 11 && "${protocols}" != 12 && "${protocols}" != 13 && "${protocols}" != 14 && "${protocols}" != 15 && "${protocols}" != 16 && "${protocols}" != 17 ) || -n "${secondaryCore}" ]]; then
        keyPair=$(dockerSetupRealityKeyPair "${xrayImage}" "${opsImage}") || return 1
        read -r privateKey publicKey <<<"${keyPair}"
        shortId=$(dockerSetupRandomHex "${opsImage}" 8) || return 1
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 4 || "${protocols}" == 12 || "${protocols}" == 13 ]]; then
        wsPath=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    if [[ "${protocols}" == 14 || "${protocols}" == 15 ]]; then
        grpcService=$(dockerSetupRandomHex "${opsImage}" 8) || return 1
    fi
    if [[ "${protocols}" == 6 && "${hy2Obfs}" != false ]]; then
        obfsPassword=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    if [[ "${protocols}" == 9 ]]; then
        singBoxImage=$(dockerManifestImageReference sing-box) || return 1
        serverPassword=$(dockerSetupTool "${singBoxImage}" generate rand --base64 16 2>/dev/null) || return 1
        userPassword=$(dockerSetupTool "${singBoxImage}" generate rand --base64 16 2>/dev/null) || return 1
        [[ "${serverPassword}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ &&
            "${userPassword}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ ]] || return 1
    fi
    inputsFile="${output}.credentials"
    # 秘密只经私密文件交给 jq，不放进宿主进程参数或 Docker Cmd。
    (
        umask 077
        printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "${uuid}" "${privateKey}" "${publicKey}" \
            "${shortId}" "${wsPath}" "${token}" "${obfsPassword}" "${serverPassword}" "${userPassword}" "${grpcService}" >"${inputsFile}"
    ) || return 1
    dockerManifestConfigurationInputs | jq \
        --arg core "${core}" --argjson protocols "${protocols}" --arg server "${server}" \
        --argjson families "${families}" --argjson realityPort "${realityPort:-443}" \
        --arg target "${target}" --argjson targetPort "${targetPort:-443}" --arg sni "${sni}" \
        --arg domain "${domain}" --argjson wsPort "${wsPort:-443}" \
        --arg secondaryCore "${secondaryCore}" --argjson secondaryPort "${secondaryPort}" \
        --arg hy2Mode "${hy2Mode}" --argjson hy2Up "${hy2Up}" --argjson hy2Down "${hy2Down}" \
        --arg hy2Masquerade "${hy2Masquerade}" --arg hy2Obfs "${hy2Obfs}" \
        --arg tuicCongestion "${tuicCongestion}" --arg tuicAuthTimeout "${tuicAuthTimeout}" \
        --arg tuicHeartbeat "${tuicHeartbeat}" --argjson tuicZeroRtt "${tuicZeroRtt}" \
        --rawfile credentials "${inputsFile}" --argjson subscription "${subscription}" '
      ($credentials | split("\n")) as $secrets |
      $secrets[0] as $uuid | $secrets[1] as $privateKey | $secrets[2] as $publicKey |
      $secrets[3] as $shortId | $secrets[4] as $wsPath | $secrets[5] as $token |
      $secrets[6] as $obfsPassword | $secrets[7] as $serverPassword | $secrets[8] as $userPassword |
      $secrets[9] as $grpcService |
      . + {schema_version: 3, core: {type: $core,
        secondary_type: (if $secondaryCore == "" then null else $secondaryCore end), protocols: [
        (if $protocols != 2 and $protocols != 6 and $protocols != 7 and $protocols != 8 and $protocols != 9 and $protocols != 10 and $protocols != 11 and $protocols != 12 and $protocols != 13 and $protocols != 14 and $protocols != 15 and $protocols != 16 and $protocols != 17 then {
          id: (if $protocols == 4 then 2 elif $protocols == 5 then 26 else 1 end),
          core: $core, server: $server, public_port: $realityPort, address_families: $families,
          listener_id: (if $protocols == 4 then "entry-reality-xhttp"
            elif $protocols == 5 then "entry-reality-grpc" else "vless-reality" end),
          name: (if $protocols == 4 then "main-reality-xhttp"
            elif $protocols == 5 then "main-reality-grpc" else "main-reality" end), uuid: $uuid,
          reality: {server_name: $sni, target_host: $target, target_port: $targetPort,
            private_key: $privateKey, public_key: $publicKey, short_id: $shortId}
        } + (if $protocols == 4 then {xhttp: {path: ("/" + $wsPath), host: $sni, mode: "auto"}}
          elif $protocols == 5 then {grpc: {service_name: "grpc"}} else {} end) else empty end),
        (if $protocols == 2 or $protocols == 3 or $protocols == 12 then {
          id: (if $protocols == 12 then 22 else 21 end),
          core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: (if $protocols == 12 then "entry-vmess-ws" else "vless-ws" end),
          name: (if $protocols == 12 then "main-vmess-ws" else "main-ws" end), uuid: $uuid,
          websocket: {domain: $domain, path: $wsPath, backend_port: 31297, tls_port: 8443}
        } else empty end),
        (if $protocols == 13 then {
          id: 23, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-vmess-httpupgrade", name: "main-vmess-httpupgrade", uuid: $uuid,
          httpupgrade: {domain: $domain, path: $wsPath, backend_port: 31306, tls_port: 8443}
        } else empty end),
        (if $protocols == 14 or $protocols == 15 then {
          id: (if $protocols == 14 then 24 else 25 end),
          core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: (if $protocols == 14 then "entry-vless-grpc-tls" else "entry-trojan-grpc-tls" end),
          name: (if $protocols == 14 then "main-vless-grpc-tls" else "main-trojan-grpc-tls" end), uuid: $uuid,
          grpc_tls: {domain: $domain, service_name: $grpcService,
            backend_port: (if $protocols == 14 then 31301 else 31304 end), tls_port: 8443}
        } else empty end),
        (if $protocols == 16 or $protocols == 17 then {
          id: (if $protocols == 16 then 27 else 29 end),
          core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: (if $protocols == 16 then "entry-vless-tls-vision" else "entry-trojan-tls-fallback" end),
          name: (if $protocols == 16 then "main-vless-tls-vision" else "main-trojan-tls-fallback" end), uuid: $uuid,
          fallback_tls: {domain: $domain, http_port: 31300, http2_port: 31302}
        } else empty end),
        (if $protocols == 6 then {
          id: 3, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-hysteria2", name: "main-hysteria2", uuid: $uuid,
          hy2: {domain: $domain, bandwidth_mode: $hy2Mode, up_mbps: $hy2Up, down_mbps: $hy2Down,
            obfs: (if $obfsPassword == "" then null else {type: $hy2Obfs, password: $obfsPassword} end),
            masquerade: $hy2Masquerade}
        } else empty end),
        (if $protocols == 7 or $protocols == 8 then {
          id: (if $protocols == 7 then 4 else 5 end), core: $core, server: $server,
          public_port: $wsPort, address_families: $families,
          listener_id: (if $protocols == 7 then "entry-anytls" else "entry-naive" end),
          name: (if $protocols == 7 then "main-anytls" else "main-naive" end), uuid: $uuid
        } + (if $protocols == 7 then {anytls: {domain: $domain}} else {naive: {domain: $domain}} end)
        else empty end),
        (if $protocols == 9 then {
          id: 30, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-shadowsocks", name: "main-shadowsocks", uuid: $uuid,
          shadowsocks: {method: "2022-blake3-aes-128-gcm",
            server_password: $serverPassword, user_password: $userPassword}
        } else empty end),
        (if $protocols == 10 then {
          id: 31, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-tuic", name: "main-tuic", uuid: $uuid,
          tuic: {domain: $domain, congestion_control: $tuicCongestion, auth_timeout: $tuicAuthTimeout,
            heartbeat: $tuicHeartbeat, zero_rtt_handshake: $tuicZeroRtt}
        } else empty end),
        (if $protocols == 11 then {
          id: 28, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-trojan", name: "main-trojan", uuid: $uuid,
          trojan: {domain: $domain}
        } else empty end),
        (if $secondaryCore != "" then {
          id: 1, core: $secondaryCore, server: $server, public_port: $secondaryPort, address_families: $families,
          listener_id: "entry-secondary-reality", name: "secondary-reality", uuid: $uuid,
          reality: {server_name: $sni, target_host: $target, target_port: $targetPort,
            private_key: $privateKey, public_key: $publicKey, short_id: $shortId}
        } else empty end)]},
        tls: (if $protocols == 2 or $protocols == 3 or $protocols == 6 or $protocols == 7 or $protocols == 8 or $protocols == 10 or $protocols == 11 or $protocols == 12 or $protocols == 13 or $protocols == 14 or $protocols == 15 or $protocols == 16 or $protocols == 17 then {domain: $domain} else null end),
        subscription: {enabled: $subscription, token: $token}, host_integrations: []}
    ' >"${output}" || return 1
    rm -f -- "${inputsFile}" || return 1
    chmod 0600 "${output}" && dockerConfigureSpecValidate "${output}"
}

dockerSetupStageCertificate() {
    local candidate=$1 mode=$2 domain=$3 cert=$4 key=$5 email=$6 provider=$7 credentials=$8
    local root opsImage extension status=0
    local -a challengeArgs=() keyArgs=() issueKeyArgs=(--keylength 2048)
    root=$(dockerInstallRoot) || return 1
    opsImage=$(dockerManifestImageReference ops) || return 1
    for directory in tls acme; do
        mkdir -p "${candidate}/${directory}" || return 1
    done
    # 保留未选中的域名和 ACME 账户，候选失败不得覆盖已受管文件。
    for extension in secrets/tls data/acme; do
        if [[ -e "${root}/${extension}" || -L "${root}/${extension}" ]]; then
            [[ -d "${root}/${extension}" && ! -L "${root}/${extension}" &&
                -z "$(find "${root}/${extension}" -type l -print -quit)" ]] || return 1
            if [[ "${extension}" == secrets/tls ]]; then
                cp -a "${root}/${extension}/." "${candidate}/tls/" || return 1
            else
                cp -a "${root}/${extension}/." "${candidate}/acme/" || return 1
            fi
        fi
    done
    case "${mode}" in
    1)
        [[ -f "${candidate}/tls/${domain}.crt" && ! -L "${candidate}/tls/${domain}.crt" &&
            -f "${candidate}/tls/${domain}.key" && ! -L "${candidate}/tls/${domain}.key" ]] || {
            dockerError '所选域名没有完整受管证书，请选择导入或 ACME 申请'
            return 1
        }
        ;;
    2)
        cert=$(dockerResolveRegularFile "${cert}") &&
            key=$(dockerResolveRegularFile "${key}") &&
            dockerPrivateFileIsRestricted "${key}" || {
            dockerError '导入证书必须为普通文件，私钥仅允许持有者读取'
            return 1
        }
        cp -- "${cert}" "${candidate}/tls/${domain}.crt" &&
            cp -- "${key}" "${candidate}/tls/${domain}.key" || return 1
        ;;
    3|4)
        if [[ "${mode}" == 3 ]]; then
            credentials=$(dockerResolveRegularFile "${credentials}") &&
                dockerPrivateFileIsRestricted "${credentials}" || {
                dockerError 'DNS 凭据必须为仅允许持有者读取的普通文件'
                return 1
            }
            challengeArgs=(--dns "${provider}")
        else
            [[ "${provider}" == standalone && -z "${credentials}" ]] || return 1
            challengeArgs=(--standalone --httpport 8080)
        fi
        chmod 0750 "${candidate}" "${candidate}/tls" "${candidate}/acme" || return 1
        if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
            chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
                "${candidate}/tls" "${candidate}/acme" || return 1
            chown "0:${PADM_DOCKER_CONTAINER_GID}" "${candidate}" || return 1
        fi
        dockerAcmeChallengePrepare "${provider}" "${candidate}" || return 1
        if [[ ! -f "${candidate}/acme/${domain}/${domain}.conf" ]]; then
            keyArgs=(--ecc)
            issueKeyArgs=(--keylength ec-256)
        fi
        if dockerAcmeRun "${opsImage}" "${credentials}" "${candidate}/acme" "${candidate}/tls" \
            --issue "${challengeArgs[@]}" "${issueKeyArgs[@]}" -d "${domain}" --accountemail "${email}" >/dev/null 2>&1; then
            status=0
        else
            status=$?
        fi
        dockerAcmeChallengeRestore || return 1
        if [[ "${status}" != 0 ]]; then
            dockerError '候选 ACME 申请失败，现有证书和配置未修改'
            return 1
        fi
        dockerAcmeRun "${opsImage}" "${credentials}" "${candidate}/acme" "${candidate}/tls" \
                --install-cert -d "${domain}" "${keyArgs[@]}" \
            --fullchain-file "/var/lib/padm/tls-output/${domain}.crt" \
            --key-file "/var/lib/padm/tls-output/${domain}.key" >/dev/null 2>&1 || {
            dockerError '候选证书导出失败，现有证书和配置未修改'
            return 1
        }
        ;;
    *) return 1 ;;
    esac
    chmod 0640 "${candidate}/tls/${domain}.crt" &&
        chmod 0600 "${candidate}/tls/${domain}.key" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
        chown "0:${PADM_DOCKER_CONTAINER_GID}" "${candidate}" || return 1
        chown "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
            "${candidate}/tls" "${candidate}/tls/${domain}.crt" "${candidate}/tls/${domain}.key" || return 1
        chmod 0750 "${candidate}" "${candidate}/tls" || return 1
    fi
    dockerTlsValidateCandidate "${opsImage}" "${candidate}/tls" "${domain}"
}

dockerTlsManageCommand() {
    local root currentDomain domain choice method answer cert= key= email= provider= credentials= action
    local -a challengeArgs=()
    [[ "$#" -eq 0 && -t 0 && -t 1 ]] || {
        dockerError '证书管理需要交互终端，非交互操作请使用 tls 或 acme 命令'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    [[ -f "${root}/deployment.json" && ! -L "${root}/deployment.json" &&
        -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" &&
        -f "${root}/images.env" && ! -L "${root}/images.env" ]] || {
        dockerError '尚未完整配置 Docker 部署，请先使用首次配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    currentDomain=$(jq -er '.tls.domain | select(type == "string" and length > 0)' \
        "${root}/config/spec.json" 2>/dev/null) && dockerDomainIsValid "${currentDomain}" || {
        dockerError '当前部署没有 TLS 域名，请先配置 WS TLS、Hysteria2、AnyTLS、NaiveProxy 或 TUIC 入口'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureSpecValidate "${root}/config/spec.json" &&
        dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
            "${root}/deployment.json" "${root}/images.env" &&
        dockerResolveOpsImage >/dev/null || {
        dockerError '当前规格与部署或 ops 镜像不一致，不能管理证书'
        return "${PADM_DOCKER_RC_STATE}"
    }
    printf '\nDocker 证书管理\n当前 TLS 域名: %s\n' "${currentDomain}"
    printf '%s\n' '1. 查看/校验受管证书' '2. 导入证书轮换' '3. ACME 申请' '4. ACME 续期' \
        '5. 自动续期状态' '6. 启用自动续期' '7. 停用自动续期' \
        '8. 启用 Nginx HTTP-01 入口' '9. 关闭 Nginx HTTP-01 入口' \
        '10. 迁移入口 TLS 域名' '0. 返回'
    dockerSetupRead choice '证书操作: ' || return 0
    [[ "${choice}" =~ ^([1-9]|10)$ ]] || return "${PADM_DOCKER_RC_USAGE}"
    if [[ "${choice}" == 10 ]]; then
        dockerSetupRead domain '新的 TLS 域名（0 取消）: ' || return 0
        dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerSetupRead method '证书 [1=已有受管, 2=导入, 3=DNS-01, 4=HTTP-01 standalone, 0=取消]: ' 1 || return 0
        case "${method}" in
        1) challengeArgs=(--tls-existing) ;;
        2)
            dockerSetupRead cert '完整证书链文件（0 取消）: ' || return 0
            dockerSetupRead key '私钥文件（0 取消）: ' || return 0
            [[ -n "${cert}" && -n "${key}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            challengeArgs=(--tls-import "${cert}" "${key}")
            ;;
        3)
            dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
            dockerSetupRead provider 'DNS provider（dns_*，0 取消）: ' || return 0
            dockerSetupRead credentials 'DNS 凭据文件（0 取消）: ' || return 0
            challengeArgs=(--tls-dns "${email}" "${provider}" "${credentials}")
            ;;
        4)
            dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
            challengeArgs=(--tls-standalone "${email}")
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        dockerEditCommand --tls-migrate "${domain}" "${challengeArgs[@]}"
        return $?
    fi
    if [[ "${choice}" == 8 || "${choice}" == 9 ]]; then
        if [[ "${choice}" == 8 ]]; then action=enable; else action=disable; fi
        printf 'HTTP-01 入口只服务当前 TLS 域名 %s 的 ACME 验证；启用后持久监听公网 80，关闭后不再提供 webroot 验证。\n' "${currentDomain}"
        dockerEditCommand --http01 "${action}"
        return $?
    fi
    dockerSetupRead domain "证书域名 [${currentDomain}]（0 取消）: " "${currentDomain}" || return 0
    dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
    case "${choice}" in
    1) action=查看/校验 ;;
    2)
        action=导入轮换
        dockerSetupRead cert '完整证书链文件（0 取消）: ' || return 0
        dockerSetupRead key '私钥文件（0 取消）: ' || return 0
        [[ -n "${cert}" && -n "${key}" ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    3|4|6)
        case "${choice}" in
        3) action=ACME申请 ;;
        4) action=ACME续期 ;;
        6) action=启用自动续期 ;;
        esac
        dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
        dockerEmailIsValid "${email}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerSetupRead method '验证方式 [1=DNS-01, 2=HTTP-01 standalone, 3=HTTP-01 webroot，默认 1，0 取消]: ' 1 || return 0
        case "${method}" in
        1)
            dockerSetupRead provider 'DNS provider（dns_*，0 取消）: ' || return 0
            dockerSetupRead credentials 'DNS 凭据文件（0 取消）: ' || return 0
            [[ "${provider}" =~ ^dns_[a-z0-9_]+$ && -n "${credentials}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            challengeArgs=(--dns "${provider}" --credentials "${credentials}")
            ;;
        2)
            provider=standalone
            challengeArgs=(--standalone)
            printf 'HTTP-01 需要公网 80 可达；验证期间可能暂停本部署的 80 端口服务，并影响该容器内 HTTPS；不会停止无关 443 服务。\n'
            ;;
        3)
            [[ "${domain}" == "${currentDomain}" ]] &&
                jq -e '.tls.http01 == true' "${root}/config/spec.json" >/dev/null || {
                dockerError 'webroot 只支持当前 TLS 域名；请先显式启用 Nginx HTTP-01 入口'
                return "${PADM_DOCKER_RC_STATE}"
            }
            provider=webroot
            challengeArgs=(--webroot)
            printf 'HTTP-01 webroot 使用已启用的公网 80 入口，不暂停 Nginx 或其它 TLS 消费者。\n'
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        ;;
    5) action=自动续期状态 ;;
    7) action=停用自动续期 ;;
    esac
    printf '\n证书操作: %s\n域名: %s\n' "${action}" "${domain}"
    if [[ "${domain}" != "${currentDomain}" && "${choice}" -le 4 ]]; then
        printf '其他域名只保存或校验证书，不修改当前入口和部署。\n'
    fi
    dockerSetupRead answer '确认执行证书操作？[y/N]: ' n || return 0
    case "${answer}" in y|Y|yes|YES) ;; *) printf '已取消证书操作。\n'; return 0 ;; esac
    case "${choice}" in
    1) dockerTlsValidateCommand --domain "${domain}" ;;
    2) dockerTlsInstallCommand --domain "${domain}" --cert "${cert}" --key "${key}" ;;
    3|4)
        if [[ "${choice}" == 3 ]]; then action=issue; else action=renew; fi
        dockerAcmeCommand "${action}" --domain "${domain}" --email "${email}" \
            "${challengeArgs[@]}"
        ;;
    5) dockerRenewalCommand status ;;
    6)
        dockerRenewalCommand enable --domain "${domain}" --email "${email}" \
            "${challengeArgs[@]}"
        ;;
    7) dockerRenewalCommand disable --domain "${domain}" ;;
    esac
}

dockerSetupCommand() {
    local manifest= bundle= controlBundle= coreChoice core protocols=1 server familyChoice families
    local secondaryCore= secondaryPort=8444
    local realityPort=443 target= targetPort=443 sni= domain= wsPort=443 tlsMode= cert= key=
    local hy2Mode=bbr hy2Up=100 hy2Down=50 hy2Obfs=false hy2Masquerade=
    local tuicCongestion=cubic tuicAuthTimeout=3s tuicHeartbeat=10s tuicZeroRtt=false
    local email= provider= credentials= subscription=false answer= root candidate= status=0
    local targetMode probeInputs releasePrepared=0 reinstall=0 operation=首次配置 applyMode=configure sharesSource=''
    if [[ "${1:-}" == --reinstall ]]; then
        reinstall=1 operation=重装 applyMode=confirmed
        shift
    fi
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ -t 0 && -t 1 ]] || { dockerError "${operation}需要交互终端"; return "${PADM_DOCKER_RC_USAGE}"; }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${reinstall}" == 1 ]]; then
        dockerSetupReinstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
        printf '重装会重新生成账号、密钥和分享身份，替换全部入口、分享组与路由；原数据、证书及恢复快照保留。\n'
    else
        dockerSetupUnconfigured || return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    printf '\nDocker %s\n' "${operation}"
    dockerSetupRead coreChoice '核心 [1=Xray, 2=sing-box, 3=Xray+sing-box, 4=sing-box+Xray, 0=取消]: ' 1 || return 0
    case "${coreChoice}" in
    1|3)
        core=xray
        [[ "${coreChoice}" != 3 ]] || secondaryCore=sing-box
        dockerSetupRead protocols '协议 [1=Reality Vision, 2=WS TLS, 3=两者, 4=Reality XHTTP, 5=Reality gRPC, 11=Trojan direct, 12=VMess WS TLS, 13=VMess HTTPUpgrade TLS, 14=VLESS gRPC TLS, 15=Trojan gRPC TLS, 16=VLESS TLS Vision, 17=Trojan TLS fallback, 0=取消]: ' 1 || return 0
        [[ "${protocols}" =~ ^[1-5]$ || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    2|4)
        core=sing-box
        [[ "${coreChoice}" != 4 ]] || secondaryCore=xray
        dockerSetupRead protocols '协议 [1=Reality Vision, 5=Reality gRPC, 6=Hysteria2, 7=AnyTLS, 8=NaiveProxy, 9=Shadowsocks, 10=TUIC, 11=Trojan direct, 13=VMess HTTPUpgrade TLS, 0=取消]: ' 1 || return 0
        [[ "${protocols}" == 1 || "${protocols}" == 5 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 9 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 13 ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    [[ "${protocols}" != 8 ]] ||
        printf 'NaiveProxy 服务器必须与 TLS 域名一致，原生 naive+https URI 不支持独立 SNI。\n'
    dockerSetupRead server '服务器域名或 IP（0 取消）: ' || return 0
    [[ -n "${server}" ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerSetupRead familyChoice '地址族 [1=IPv4, 2=IPv6, 3=双栈, 默认 1]: ' 1 || return 0
    case "${familyChoice}" in
    1) families='["ipv4"]' ;;
    2) families='["ipv6"]' ;;
    3) families='["ipv4","ipv6"]' ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    if [[ ( "${protocols}" != 2 && "${protocols}" != 6 && "${protocols}" != 7 && "${protocols}" != 8 && "${protocols}" != 9 && "${protocols}" != 10 && "${protocols}" != 11 && "${protocols}" != 12 && "${protocols}" != 13 && "${protocols}" != 14 && "${protocols}" != 15 && "${protocols}" != 16 && "${protocols}" != 17 ) || -n "${secondaryCore}" ]]; then
        if [[ "${protocols}" != 2 && "${protocols}" != 6 && "${protocols}" != 7 && "${protocols}" != 8 && "${protocols}" != 9 && "${protocols}" != 10 && "${protocols}" != 11 && "${protocols}" != 12 && "${protocols}" != 13 && "${protocols}" != 14 && "${protocols}" != 15 && "${protocols}" != 16 && "${protocols}" != 17 ]]; then
            dockerSetupRead realityPort '主核心 Reality 入口端口 [443]: ' 443 || return 0
        fi
        printf '\nREALITY 目标站选择\n'
        printf '%s\n' '1. 检测候选后选择' '2. 手动输入'
        while :; do
            dockerSetupRead targetMode '请选择 [1]（0 取消）: ' 1 || return 0
            case "${targetMode}" in
            1)
                # 探测镜像必须来自已验签的发布，交互期间不持有部署锁。
                dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
                releasePrepared=1
                root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
                candidate=$(mktemp -d "${root}/.setup.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
                DOCKER_SETUP_CANDIDATE=${candidate}
                chmod 0700 "${candidate}" || return "${PADM_DOCKER_RC_STATE}"
                probeInputs=$(dockerManifestConfigurationInputs) || return "${PADM_DOCKER_RC_MANIFEST}"
                jq '{images:.images,core:{protocols:[]}}' <<<"${probeInputs}" \
                    >"${candidate}/target-probe.json" &&
                    chmod 0600 "${candidate}/target-probe.json" || return "${PADM_DOCKER_RC_STATE}"
                source "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/lib/reality-targets.sh" || return "${PADM_DOCKER_RC_STATE}"
                dockerRealityTargetAction "${candidate}/target-probe.json" candidates "${candidate}/target.json" || status=$?
                case "${status}" in
                2) ;;
                0|130|143) return "${status}" ;;
                *) return "${PADM_DOCKER_RC_STATE}" ;;
                esac
                status=0
                target=$(jq -er '.host' "${candidate}/target.json") &&
                    targetPort=$(jq -er '.port' "${candidate}/target.json") &&
                    sni=$(jq -er '.sni' "${candidate}/target.json") || return "${PADM_DOCKER_RC_STATE}"
                ;;
            2)
                dockerSetupRead target 'Reality 目标 host[:port]（回车或 0 取消）: ' || return 0
                [[ -n "${target}" ]] || return 0
                if [[ "${target}" == *:* ]]; then
                    targetPort=${target##*:}
                    target=${target%:*}
                fi
                sni=${target}
                ;;
            *) printf '无效选项，请重新选择。\n'; continue ;;
            esac
            break
        done
        dockerSetupRead sni "Reality SNI [${sni}]: " "${sni}" || return 0
        dockerDomainIsValid "${target}" && dockerDomainIsValid "${sni}" ||
            return "${PADM_DOCKER_RC_USAGE}"
    fi
    if [[ -n "${secondaryCore}" ]]; then
        dockerSetupRead secondaryPort "副核心 ${secondaryCore} Reality 入口端口 [8444]: " 8444 || return 0
    fi
    if [[ "${protocols}" == 9 ]]; then
        dockerSetupRead wsPort "Shadowsocks TCP/UDP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ]]; then
        [[ "${protocols}" != 3 ]] || wsPort=8443
        if [[ "${protocols}" == 6 ]]; then
            dockerSetupRead domain 'Hysteria2 TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 7 ]]; then
            dockerSetupRead domain 'AnyTLS TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 8 ]]; then
            dockerSetupRead domain "NaiveProxy TLS 域名 [${server}]（0 取消）: " "${server}" || return 0
        elif [[ "${protocols}" == 10 ]]; then
            dockerSetupRead domain 'TUIC TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 11 ]]; then
            dockerSetupRead domain 'Trojan TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 13 ]]; then
            dockerSetupRead domain 'HTTPUpgrade TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 14 || "${protocols}" == 15 ]]; then
            dockerSetupRead domain 'gRPC TLS 域名（0 取消）: ' || return 0
        elif [[ "${protocols}" == 16 || "${protocols}" == 17 ]]; then
            dockerSetupRead domain 'TCP TLS fallback 域名（0 取消）: ' || return 0
        else
            dockerSetupRead domain 'WS TLS 域名（0 取消）: ' || return 0
        fi
        dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${protocols}" == 8 && "${server}" != "${domain}" ]]; then
            dockerError 'NaiveProxy 服务器必须与 TLS 域名一致，原生 URI 不支持独立 SNI'
            return "${PADM_DOCKER_RC_USAGE}"
        fi
        if [[ "${protocols}" == 6 ]]; then
            dockerSetupRead wsPort "Hysteria2 UDP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
            dockerSetupRead hy2Mode '拥塞模式 [bbr=自适应, brutal=固定带宽，默认 bbr]: ' bbr || return 0
            [[ "${hy2Mode}" == bbr || "${hy2Mode}" == brutal ]] || return "${PADM_DOCKER_RC_USAGE}"
            dockerSetupRead hy2Up '服务端上行带宽 Mbps（服务端→客户端）[100]: ' 100 || return 0
            dockerSetupRead hy2Down '服务端下行带宽 Mbps（客户端→服务端）[50]: ' 50 || return 0
            for answer in "${hy2Up}" "${hy2Down}"; do
                [[ "${answer}" =~ ^[1-9][0-9]{0,6}$ && "${answer}" -le 1000000 ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
            done
            dockerSetupRead answer '混淆类型 [n=关闭, y=Salamander, gecko=Gecko，确认后随机密码]: ' n || return 0
            case "${answer}" in
            y|Y|yes|YES|salamander) hy2Obfs=salamander ;;
            gecko) hy2Obfs=gecko ;;
            n|N|no|NO) hy2Obfs=false ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
            dockerSetupRead hy2Masquerade '伪装 HTTPS 地址（空输入不启用，0 取消）: ' || return 0
            [[ "${hy2Masquerade}" != local ]] || {
                dockerError '本地网页请在首配完成后，先发布静态站点，再编辑已有 Hysteria2 入口设置 local'
                return "${PADM_DOCKER_RC_USAGE}"
            }
        elif [[ "${protocols}" == 7 ]]; then
            dockerSetupRead wsPort "AnyTLS TCP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 8 ]]; then
            dockerSetupRead wsPort "NaiveProxy TCP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 11 ]]; then
            dockerSetupRead wsPort "Trojan TCP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 13 ]]; then
            dockerSetupRead wsPort "HTTPUpgrade TLS 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 14 || "${protocols}" == 15 ]]; then
            dockerSetupRead wsPort "gRPC TLS 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 16 || "${protocols}" == 17 ]]; then
            dockerSetupRead wsPort "TCP TLS fallback 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        elif [[ "${protocols}" == 10 ]]; then
            dockerSetupRead wsPort "TUIC UDP 入口端口 [${wsPort}]: " "${wsPort}" || return 0
            dockerSetupRead tuicCongestion '拥塞控制 [cubic/bbr/new_reno，默认 cubic]: ' cubic || return 0
            [[ "${tuicCongestion}" == cubic || "${tuicCongestion}" == bbr || "${tuicCongestion}" == new_reno ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            dockerSetupRead tuicAuthTimeout '认证超时 auth_timeout [3s]: ' 3s || return 0
            dockerSetupRead tuicHeartbeat '心跳间隔 heartbeat [10s]: ' 10s || return 0
            for answer in "${tuicAuthTimeout}" "${tuicHeartbeat}"; do
                [[ "${answer}" =~ ^[1-9][0-9]{0,5}(ms|s|m|h)$ ]] || return "${PADM_DOCKER_RC_USAGE}"
            done
            dockerSetupRead answer '启用 0-RTT（会增加重放风险，默认关闭）？[y/N]: ' n || return 0
            case "${answer}" in
            y|Y|yes|YES) tuicZeroRtt=true ;;
            n|N|no|NO) tuicZeroRtt=false ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        else
            dockerSetupRead wsPort "WS TLS 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        fi
        dockerSetupRead tlsMode '证书 [1=已有受管, 2=导入, 3=DNS-01, 4=HTTP-01 standalone, 0=取消]: ' 1 || return 0
        case "${tlsMode}" in
        1) ;;
        2)
            dockerSetupRead cert '完整证书链文件（0 取消）: ' || return 0
            dockerSetupRead key '私钥文件（0 取消）: ' || return 0
            ;;
        3)
            dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
            dockerSetupRead provider 'DNS provider（dns_*，0 取消）: ' || return 0
            dockerSetupRead credentials 'DNS 凭据文件（0 取消）: ' || return 0
            dockerEmailIsValid "${email}" && [[ "${provider}" =~ ^dns_[a-z0-9_]+$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            ;;
        4)
            provider=standalone
            dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
            dockerEmailIsValid "${email}" || return "${PADM_DOCKER_RC_USAGE}"
            printf 'HTTP-01 需要域名解析到本机且公网 80 可达；确认后临时使用宿主 80，冲突时不停止无关服务。\n'
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
            dockerSetupRead answer '启用 HTTPS 订阅发布？[y/N]: ' n || return 0
            case "${answer}" in
            y|Y|yes|YES) subscription=true ;;
            n|N|no|NO) subscription=false ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        fi
    fi
    for answer in "${realityPort}" "${targetPort}" "${wsPort}" "${secondaryPort}"; do
        [[ "${answer}" =~ ^[1-9][0-9]{0,4}$ && "${answer}" -le 65535 ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
    done
    [[ "${protocols}" != 3 || "${realityPort}" != "${wsPort}" ]] ||
        { dockerError 'Reality 和 WS TLS 不能使用同一入口端口'; return "${PADM_DOCKER_RC_CONFLICT}"; }
    if [[ -n "${secondaryCore}" ]] &&
        { [[ "${protocols}" != 2 && "${protocols}" != 6 && "${protocols}" != 7 && "${protocols}" != 8 && "${protocols}" != 9 && "${protocols}" != 10 && "${protocols}" != 11 && "${protocols}" != 12 && "${protocols}" != 13 && "${protocols}" != 14 && "${protocols}" != 15 && "${protocols}" != 16 && "${protocols}" != 17 && "${secondaryPort}" == "${realityPort}" ]] ||
          [[ ( "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 9 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ) && "${secondaryPort}" == "${wsPort}" ]]; }; then
        dockerError '主副核心不能使用同一入口端口'
        return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    printf '\n核心: %s\n协议组合: %s\n服务器: %s\n地址族: %s\n' "${core}" "${protocols}" "${server}" "${families}"
    [[ "${protocols}" == 2 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 9 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ]] ||
        printf 'Reality: %s -> %s:%s，SNI %s\n' "${realityPort}" "${target}" "${targetPort}" "${sni}"
    if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
        printf 'WS TLS: %s:%s，证书方式 %s，订阅 %s\n' "${domain}" "${wsPort}" "${tlsMode}" "${subscription}"
    elif [[ "${protocols}" == 12 ]]; then
        printf 'VMess WS TLS: %s:%s，TLS 域名 %s，证书方式 %s\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 13 ]]; then
        printf 'VMess HTTPUpgrade TLS: %s:%s，TLS 域名 %s，证书方式 %s\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 14 ]]; then
        printf 'VLESS gRPC TLS: %s:%s，TLS 域名 %s，证书方式 %s\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 15 ]]; then
        printf 'Trojan gRPC TLS: %s:%s，TLS 域名 %s，证书方式 %s\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 16 ]]; then
        printf 'VLESS TLS Vision: %s:%s，TLS 域名 %s，证书方式 %s，fallback HTTP/HTTP2 31300/31302\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 17 ]]; then
        printf 'Trojan TLS fallback: %s:%s，TLS 域名 %s，证书方式 %s，fallback HTTP/HTTP2 31300/31302\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    elif [[ "${protocols}" == 6 ]]; then
        printf 'Hysteria2: %s:%s/udp，证书方式 %s，拥塞 %s，服务端上行/下行 %s/%s Mbps，混淆 %s\n' \
            "${domain}" "${wsPort}" "${tlsMode}" "${hy2Mode}" "${hy2Up}" "${hy2Down}" "${hy2Obfs}"
    elif [[ "${protocols}" == 7 ]]; then
        printf 'AnyTLS: %s:%s/tcp，证书方式 %s\n' "${domain}" "${wsPort}" "${tlsMode}"
    elif [[ "${protocols}" == 8 ]]; then
        printf 'NaiveProxy: %s:%s/tcp，证书方式 %s\n' "${domain}" "${wsPort}" "${tlsMode}"
    elif [[ "${protocols}" == 9 ]]; then
        printf 'Shadowsocks: %s:%s/tcp+udp，方法 2022-blake3-aes-128-gcm\n' "${server}" "${wsPort}"
    elif [[ "${protocols}" == 10 ]]; then
        printf 'TUIC: %s:%s/udp，证书方式 %s，拥塞 %s，认证超时 %s，心跳 %s，0-RTT %s\n' \
            "${domain}" "${wsPort}" "${tlsMode}" "${tuicCongestion}" "${tuicAuthTimeout}" "${tuicHeartbeat}" "${tuicZeroRtt}"
    elif [[ "${protocols}" == 11 ]]; then
        printf 'Trojan direct: %s:%s/tcp，TLS 域名 %s，证书方式 %s\n' "${server}" "${wsPort}" "${domain}" "${tlsMode}"
    fi
    [[ -z "${secondaryCore}" ]] || printf '副核心: %s，Reality 入口端口 %s\n' "${secondaryCore}" "${secondaryPort}"
    printf '确认后将验证发布、生成账号参数并配置服务。\n'
    if [[ "${reinstall}" == 1 ]]; then
        dockerSetupRead answer '确认重新选择核心和协议并替换全部入口、账号、分享组与路由？[y/N]: ' n || return 0
    else
        dockerSetupRead answer '确认首次配置？[y/N]: ' n || return 0
    fi
    case "${answer}" in y|Y|yes|YES) ;; *) printf '已取消%s。\n' "${operation}"; return 0 ;; esac
    dockerLockInstalledDeployment || return $?
    if [[ "${reinstall}" == 1 ]]; then
        dockerSetupReinstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
    else
        dockerSetupUnconfigured || return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    [[ -n "${candidate}" ]] || candidate=$(mktemp -d "${root}/.setup.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${candidate}
    chmod 0700 "${candidate}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${reinstall}" == 1 ]]; then
        cp -- "${root}/config/spec.json" "${candidate}/original.json" &&
            chmod 0600 "${candidate}/original.json" &&
            dockerEditBaselineValidate "${candidate}/original.json" "${candidate}" &&
            dockerControlRecoveryCheck || return "${PADM_DOCKER_RC_STATE}"
        # 重装撤销旧分享授权，避免相同账号或入口 ID 重新发布到旧 token。
        sharesSource="${candidate}/shares.json"
        dockerSubscriptionStateWrite "${sharesSource}" '{"schema_version":1,"groups":[]}' ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "${releasePrepared}" -eq 0 ]]; then
        dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    fi
    dockerSetupGenerateSpec "${core}" "${protocols}" "${server}" "${families}" "${realityPort}" \
        "${target}" "${targetPort}" "${sni}" "${domain}" "${wsPort}" "${subscription}" \
        "${candidate}/spec.json" "${secondaryCore}" "${secondaryPort}" \
        "${hy2Mode}" "${hy2Up}" "${hy2Down}" "${hy2Obfs}" "${hy2Masquerade}" \
        "${tuicCongestion}" "${tuicAuthTimeout}" "${tuicHeartbeat}" "${tuicZeroRtt}" || {
        dockerError '账号参数生成或规格校验失败，未提交配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureReleaseValidate "${candidate}/spec.json" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ "${reinstall}" == 1 ]]; then
        dockerAcmeWebrootTransitionValidate "${candidate}/spec.json" &&
            dockerControlSyncTransitionValidate "${candidate}/spec.json" &&
            dockerControlSyncScheduleSpecCheck "${candidate}/spec.json" &&
            dockerControlTransitionValidate "${candidate}/spec.json" &&
            dockerRealityStreamDeploymentCheck "${candidate}/spec.json" "${candidate}/original.json" &&
            dockerRealityTargetsValidate "${candidate}/spec.json" &&
            dockerHostIntegrationInputsValidate "${candidate}/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerTrafficRuntimeCheck "$(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${candidate}/spec.json")" ||
            return "${PADM_DOCKER_RC_HOST}"
        dockerConfigurePortsAvailable "${candidate}/spec.json" || return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ]]; then
        dockerSetupStageCertificate "${candidate}" "${tlsMode}" "${domain}" "${cert}" "${key}" \
            "${email}" "${provider}" "${credentials}" || return "${PADM_DOCKER_RC_STATE}"
        dockerConfigureApply "${candidate}/spec.json" "${candidate}/tls" "${candidate}/acme" "${applyMode}" '' '' '' "${sharesSource}" || status=$?
    else
        dockerConfigureApply "${candidate}/spec.json" '' '' "${applyMode}" '' '' '' "${sharesSource}" || status=$?
    fi
    return "${status}"
}

dockerReinstallCommand() {
    local specFile= manifest= bundle= controlBundle= mode=interactive modeSet=0
    local root workspace original normalized draft version
    local -a releaseArgs=()
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --spec|--manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --spec) [[ -z "${specFile}" ]] || return "${PADM_DOCKER_RC_USAGE}"; specFile=$2 ;;
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        --preview)
            [[ "${modeSet}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            mode=preview modeSet=1
            shift
            ;;
        --confirm)
            [[ "${modeSet}" == 0 && "$#" -ge 2 && "$2" == PADM-DOCKER-REINSTALL ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            mode=confirmed modeSet=1
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    if [[ -z "${specFile}" ]]; then
        [[ "${mode}" == interactive ]] || return "${PADM_DOCKER_RC_USAGE}"
        [[ -z "${manifest}" ]] || releaseArgs+=(--manifest "${manifest}")
        [[ -z "${bundle}" ]] || releaseArgs+=(--bundle "${bundle}")
        [[ -z "${controlBundle}" ]] || releaseArgs+=(--control-bundle "${controlBundle}")
        dockerSetupCommand --reinstall "${releaseArgs[@]}"
        return $?
    fi
    [[ "${mode}" != interactive || ( -t 0 && -t 1 ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerResolveRegularFile "${root}/config/spec.json" >/dev/null &&
        [[ -O "${root}/config/spec.json" ]] &&
        dockerPrivateFileIsRestricted "${root}/config/spec.json" || {
        dockerError '重装需要完整私密受管规格，不能从运行配置推测身份'
        return "${PADM_DOCKER_RC_STATE}"
    }
    specFile=$(dockerResolveRegularFile "${specFile}") &&
        [[ -O "${specFile}" ]] && dockerPrivateFileIsRestricted "${specFile}" || {
        dockerError '重装规格必须是 root 所有且仅允许持有者读取的普通文件'
        return "${PADM_DOCKER_RC_STATE}"
    }
    workspace=$(mktemp -d "${root}/.reinstall.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${workspace}
    chmod 0700 "${workspace}" || return "${PADM_DOCKER_RC_STATE}"
    original="${workspace}/original.json"
    normalized="${workspace}/normalized.json"
    draft="${workspace}/draft.json"
    cp -- "${root}/config/spec.json" "${original}" && chmod 0600 "${original}" &&
        cp -- "${specFile}" "${draft}" && chmod 0600 "${draft}" &&
        dockerConfigureSpecMigrate "${original}" "${normalized}" &&
        dockerConfigureSpecMigrate "${draft}" "${draft}.v3" &&
        mv -f -- "${draft}.v3" "${draft}" &&
        dockerEditBaselineValidate "${original}" "${workspace}" ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ -z "${manifest}" ]]; then
        version=$(jq -er '.release.version' "${draft}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return "${PADM_DOCKER_RC_STATE}"
        manifest="${PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT%/latest/download/release-manifest.json}/download/v${version}/release-manifest.json"
    fi
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    dockerConfigureReleaseValidate "${draft}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerSubscriptionStateWrite "${workspace}/shares.json" '{"schema_version":1,"groups":[]}' ||
        return "${PADM_DOCKER_RC_STATE}"
    printf '完整规格重装将替换所列核心、入口、账号和发布设置，并撤销全部旧分享组；原数据、证书及恢复快照保留。\n'
    dockerEditPreview "${normalized}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    dockerConfigureApply "${draft}" '' '' "${mode}" '' '' '' "${workspace}/shares.json"
}

dockerEditPreview() {
    local original=$1 draft=$2
    printf '\n配置差异（不显示账号、密钥、路径或 token 的值）：\n'
    jq -rn --slurpfile before "${original}" --slurpfile after "${draft}" '
      $before[0] as $old | $after[0] as $new |
      ([($old | paths(scalars)), ($new | paths(scalars))] | unique |
        .[] as $path |
        select(($old | getpath($path)) != ($new | getpath($path))) |
        ($path | map(tostring) | join(".")) | "  修改: \(.)"),
      (select($old.site != $new.site) |
        "  站点模式: \($old.site.mode // "legacy") -> \($new.site.mode // "legacy")")
    ' || return 1
    jq -r '.core.protocols[] |
      "  入口 \(.listener_id // (.id | tostring))，核心 \(.core // "未迁移")，协议 \(.id): \(.server):\(.public_port) [\(.address_families | join(","))]"' \
        "${draft}" || return 1
    jq -r '.cdn_entries[]? | "  CDN 入口 \(.listener_id): \(.addresses | join(","))"' "${draft}"
}

dockerEditPrivateInputCopy() (
    local input=$1 target=$2 kind=${3:-} cursor metadata mode resolved
    umask 077
    dockerPathIsSafeAbsolute "${input}" &&
        resolved=$(realpath -m -s -- "${input}" 2>/dev/null) &&
        [[ "${resolved}" == "${input}" && -f "${input}" && ! -L "${input}" ]] ||
        return 1
    metadata=$(stat -c '%u:%a:%h:%s' -- "${input}" 2>/dev/null) || return 1
    [[ "${metadata}" == 0:600:1:* && "${metadata##*:}" -le 65536 ]] || return 1
    cursor=$(dirname -- "${input}") || return 1
    while :; do
        [[ -d "${cursor}" && ! -L "${cursor}" ]] || return 1
        metadata=$(stat -c '%u:%a' -- "${cursor}" 2>/dev/null) || return 1
        [[ "${metadata}" == 0:* ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 022) == 0 )) || return 1
        [[ "${cursor}" != / ]] || break
        cursor=$(dirname -- "${cursor}") || return 1
    done
    cp -- "${input}" "${target}" 2>/dev/null &&
        chmod 0600 "${target}" &&
        [[ "$(stat -c '%s' -- "${target}")" -le 65536 ]] &&
        jq -es --arg kind "${kind}" '
          length == 1 and (.[0] | type == "object" and
          (if $kind == "socks5" then
             keys == (["password", "port", "server", "username"] +
               if has("domains") then ["domains"] else [] end | sort)
           elif $kind == "dns" then keys == ["domains", "port", "server"]
           elif $kind == "hosts" then length >= 1 and length <= 256
           elif $kind == "direct" or $kind == "block" then keys == ["domains"]
           elif $kind == "block_ips" then keys == ["ips"]
           elif $kind == "warp" then
             keys == ["domains", "family", "ipv6_address", "mode", "peer_public_key", "private_key", "reserved"]
           elif $kind == "http_relay" then
             keys == ["address_families", "core", "password", "port", "source_ips", "username"]
           elif $kind == "hy2_obfs" then
             keys == ["password"] and
             (.password | type == "string" and test("^[A-Za-z0-9_-]{16,128}\\z"))
           else false end))
        ' "${target}" >/dev/null 2>&1
)

dockerSocks5DomainsNormalize() {
    jq -ecn --arg input "$1" --slurpfile schema "$(dockerConfigureSchemaFile)" '
      $schema[0].properties.routing.properties.socks5.properties.domains as $contract |
      ($input | split(",") | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase |
        if contains(":") then . else "domain:" + . end)) |
      reduce .[] as $rule ([]; if index($rule) == null then . + [$rule] else . end) |
      select(length >= $contract.minItems and length <= $contract.maxItems and
        all(.[]; . as $rule | any($contract.items.anyOf[]; .pattern as $pattern | $rule | test($pattern))))
    ' 2>/dev/null
}

dockerProtocolCommand() (
    local action=${1:-} listener= root workspace original normalized selected status targetAction=
    local selectedHost selectedPort selectedSni
    local -a targetArgs=()
    [[ "$#" -gt 0 ]] && shift
    case "${action}" in
    list|stream-status|routing-status|port-alias-status|tproxy-status|redirect-status|tun-status) [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}" ;;
    links|cdn-status|xhttp-status|hy2-status|tuic-status|alpn-status|targets|check-target|target-status|select-target|block-current-target)
        [[ "$#" -le 1 && "${1:-}" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
        listener=${1:-}
        if [[ "${action}" == select-target ]]; then
            [[ -n "${listener}" && -t 0 && -t 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        fi
        [[ "${action}" != block-current-target || -n "${listener}" ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
        ;;
    refresh-targets)
        [[ "$#" -le 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        case "${1:-recommended}" in recommended|recommended_only|all) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
        targetAction=refresh targetArgs=("${1:-recommended}")
        ;;
    target-library)
        [[ "$#" -le 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
        case "${1:-all}" in all|same_asn|same_provider|local_network|scanner) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
        [[ "${2:-1}" =~ ^[1-9][0-9]{0,8}$ ]] || return "${PADM_DOCKER_RC_USAGE}"
        targetAction=library targetArgs=("${1:-all}" "${2:-1}")
        ;;
    blocked-targets)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        targetAction=blocked
        ;;
    block-target)
        [[ "$#" -eq 1 ]] && dockerDomainIsValid "$1" || return "${PADM_DOCKER_RC_USAGE}"
        targetAction=block targetArgs=("$1")
        ;;
    scan-targets|scan-targets-asn)
        [[ "$#" -le 1 && "${1:-}" != -* && -t 0 && -t 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${action}" == scan-targets ]]; then targetAction=scan-range; else targetAction=scan-asn; fi
        [[ "$#" -eq 0 ]] || targetArgs=("$1")
        ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    DOCKER_SETUP_CANDIDATE=
    # 只在读取部署快照时持锁，独立清理目录，不把锁带回菜单等待输入。
    trap 'status=$?; dockerSetupCleanup || { [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}; }; dockerReleaseDeploymentLock || { [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_LOCK}; }; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先使用首次配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerResolveRegularFile "${root}/config/spec.json" >/dev/null &&
        [[ -O "${root}/config/spec.json" ]] &&
        dockerPrivateFileIsRestricted "${root}/config/spec.json" || {
        dockerError '完整受管规格缺失或不安全，请先用 edit 导入完整原始输入'
        return "${PADM_DOCKER_RC_STATE}"
    }
    workspace=$(mktemp -d "${root}/.protocol.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${workspace}
    chmod 0700 "${workspace}" || return "${PADM_DOCKER_RC_STATE}"
    original="${workspace}/original.json"
    normalized="${workspace}/normalized.json"
    cp -- "${root}/config/spec.json" "${original}" &&
        chmod 0600 "${original}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == alpn-status ]]; then
        dockerManagedSpecMatchesDeployment "${original}" "${root}/deployment.json" "${root}/images.env" &&
            dockerFallbackAlpnStatus "${original}" "${workspace}" "${listener}" ||
            return "${PADM_DOCKER_RC_STATE}"
        return 0
    fi
    dockerEditBaselineValidate "${original}" "${workspace}" &&
        dockerConfigureSpecMigrate "${original}" "${normalized}" &&
        chmod 0600 "${normalized}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == tproxy-status || "${action}" == redirect-status ]]; then
        # 规格状态不冒充内核健康；运行验收仍由 validate 与服务健康检查提供。
        jq --arg kind "${action%-status}" '[.host_integrations[] | select(.type == $kind)][0] as $tproxy |
          {enabled:($tproxy != null),port:($tproxy.settings.port // null),
           family:($tproxy.settings.family // "ipv4"),hook:"PREROUTING"} +
          (if $kind == "tproxy" then {mark:($tproxy.settings.mark // null)} else {} end) +
          (if $tproxy.settings | has("output_uid") then
            {output_uid:$tproxy.settings.output_uid,hooks:["PREROUTING","OUTPUT"]}
           elif $tproxy.settings.output_all == true then
            {output_all:true,hooks:["PREROUTING","OUTPUT"],bypass_gid:10001}
           else {} end)' "${normalized}"
        return $?
    fi
    if [[ "${action}" == tun-status ]]; then
        jq '[.host_integrations[] | select(.type == "tun")][0] as $tun |
          {enabled:($tun != null),interface:($tun.settings.interface // null),
           address:($tun.settings.address // null),family:"ipv4",scope:"global",ipv6:"reject"}' "${normalized}"
        return $?
    fi
    if [[ "${action}" == hy2-status || "${action}" == tuic-status ]]; then
        jq --arg listener "${listener}" --arg kind "${action%-status}" '
          [.core.protocols[] | select(.core == "sing-box" and
            .id == (if $kind == "hy2" then 3 else 31 end)) |
            select($listener == "" or .listener_id == $listener) |
            {listener_id,protocol:.id,public_port} +
            (if $kind == "hy2" then
              (.hy2 | {bandwidth_mode,up_mbps,down_mbps,obfs_type:(.obfs.type // null),masquerade})
             else .tuic | {congestion_control,auth_timeout,heartbeat,zero_rtt_handshake} end)
          ] as $entries |
          if $listener != "" and ($entries | length) == 0 then error("入口不支持该协议管理")
          else {entries:$entries} end
        ' "${normalized}" || {
            dockerError 'Hy2/TUIC 管理只支持已有 v3 sing-box 协议 3/31 入口'
            return "${PADM_DOCKER_RC_STATE}"
        }
        return 0
    fi
    if [[ "${action}" == xhttp-status ]]; then
        jq --arg listener "${listener}" '
          [.core.protocols[] | select(.id == 2 and .core == "xray") |
            select($listener == "" or .listener_id == $listener) |
            {listener_id,protocol:.id,path:.xhttp.path,host:.xhttp.host,mode:.xhttp.mode,
             xmux:(.xhttp.xmux // {maxConcurrency:"16-32",
               hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"}),
             explicit:(.xhttp | has("xmux")),
             xPaddingBytes:(.xhttp.xPaddingBytes // "100-1000"),
             padding_explicit:(.xhttp | has("xPaddingBytes")),
             noGRPCHeader:(.xhttp.noGRPCHeader // false),
             noSSEHeader:(.xhttp.noSSEHeader // false),
             grpc_header_explicit:(.xhttp | has("noGRPCHeader")),
             sse_header_explicit:(.xhttp | has("noSSEHeader")),
             limits:(.xhttp |
               def effective($default): if . == null or . == 0 or . == "0-0" then $default else . end;
               {scMaxEachPostBytes:(.scMaxEachPostBytes | effective(1000000)),
                scMinPostsIntervalMs:(.scMinPostsIntervalMs | effective(30)),
                scMaxBufferedPosts:(.scMaxBufferedPosts | effective(30)),
                scStreamUpServerSecs:(.scStreamUpServerSecs | effective("20-80"))}),
             limits_explicit:(.xhttp | has("scMaxEachPostBytes") or has("scMinPostsIntervalMs") or
               has("scMaxBufferedPosts") or has("scStreamUpServerSecs"))}] as $entries |
          if $listener != "" and ($entries | length) == 0 then error("入口不支持 XHTTP 管理")
          else {entries:$entries} end
        ' "${normalized}" || {
            dockerError 'XHTTP 管理只支持已有 v3 Xray 协议 2 入口'
            return "${PADM_DOCKER_RC_STATE}"
        }
        return 0
    fi
    if [[ "${action}" == cdn-status ]]; then
        jq --arg listener "${listener}" '
          . as $request |
          [.core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) |
            select($listener == "" or .listener_id == $listener) |
            . as $entry |
            ([$request.cdn_entries[]? | select(.listener_id == $entry.listener_id)][0]) as $cdn |
            {listener_id,protocol:.id,server,overridden:($cdn != null),
             addresses:($cdn.addresses // [.server])}] as $entries |
          if $listener != "" and ($entries | length) == 0 then error("入口不支持 CDN 地址覆盖")
          else {enabled:has("cdn_entries"),entries:$entries} end
        ' "${normalized}" || {
            dockerError 'CDN 地址覆盖只支持已有协议 21/22/23/24/25 入口'
            return "${PADM_DOCKER_RC_STATE}"
        }
        return 0
    fi
    if [[ "${action}" == port-alias-status ]]; then
        jq '. as $request | {enabled:has("port_aliases"), aliases:[
          .port_aliases[]? | . as $alias |
          $request.core.protocols[] | select(.listener_id == $alias.listener_id) |
          {listener_id,core,public_port:$alias.public_port,share_default:($alias.share_default // false),
           transport:(if .id == 30 then ["tcp","udp"] elif .id == 3 or .id == 31 then ["udp"] else ["tcp"] end),
           address_families}]}' "${normalized}"
        return $?
    fi
    if [[ "${action}" == routing-status ]]; then
        jq --argjson region_defaults "${PADM_DOCKER_REGION_DEFAULT_DOMAINS}" '
          . as $request |
          # 区域合成与手工规则同属一个策略，先去重。
          [
            {policy:"direct",rules:((.routing.direct.domains // []) +
              (if .routing.region != null then
                $region_defaults + .routing.region.allow_domains else [] end) | unique)},
            {policy:"block",rules:((.routing.block.domains // []) +
              (if .routing.region.mode == "domain" or .routing.region.mode == "both"
                then ["geosite:cn"] else [] end) | unique)},
            {policy:"ipv6",rules:(.routing.ipv6.domains // [])},
            {policy:"warp",rules:(.routing.warp.domains // [])},
            {policy:"socks5",rules:(.routing.socks5.domains // [])}
          ] as $policies |
          [$policies | to_entries[] | . as $entry | .value.rules[] |
            {rule:.,policy:$entry.value.policy,rank:$entry.key}] |
          group_by(.rule) as $groups |
          ($groups | map(select(length > 1) | sort_by(.rank) |
            {rule:.[0].rule,policies:map(.policy),winner:.[0].policy})) as $overlaps |
          # 按域名层级查后缀索引，避免规则两两比较；不推断 keyword/GeoSite。
          INDEX($groups[]; .[0].rule) as $by_rule |
          [$groups[] | . as $narrow |
            (.[0].rule | capture("^(?<kind>full|domain):(?<name>.+)$")?) as $selector |
            ($selector.name | split(".")) as $labels |
            range((if $selector.kind == "full" then 0 else 1 end); $labels | length) as $start |
            ($by_rule["domain:" + ($labels[$start:] | join("."))] // []) as $broad |
            select($broad | length > 0) |
            ($narrow + $broad | unique_by(.policy) | sort_by(.rank)) as $entries |
            select($entries | length > 1) |
            {narrow_rule:$narrow[0].rule,broad_rule:$broad[0].rule,
             policies:($entries | map(.policy)),winner:$entries[0].policy}
          ] | sort_by(.narrow_rule,.broad_rule) as $coverages |
          # 只比较规范字符串的包含关系，不查询分类成员或预测解析结果。
          [$groups[] | select(.[0].rule | startswith("keyword:"))] as $keywords |
          [$groups[] | . as $narrow |
            (.[0].rule | capture("^(?<kind>full|domain|keyword):(?<name>.+)$")?) as $selector |
            $keywords[] | . as $broad |
            select($narrow[0].rule != $broad[0].rule and
              ($selector.name | contains($broad[0].rule | ltrimstr("keyword:")))) |
            ($narrow + $broad | unique_by(.policy) | sort_by(.rank)) as $entries |
            select($entries | length > 1) |
            {narrow_rule:$narrow[0].rule,broad_rule:$broad[0].rule,
             policies:($entries | map(.policy)),winner:$entries[0].policy}
          ] | sort_by(.narrow_rule,.broad_rule) as $keyword_coverages |
          $request |
          (.routing.block.domains // []) as $block |
          {enabled:(.routing != null), server:(.routing.socks5.server // null),
          port:(.routing.socks5.port // null),
          mode:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "domains" else "global" end),
          domain_rules:(.routing.socks5.domains // []),
          direct_block_overlaps:[(.routing.direct.domains // [])[] |
            . as $rule | select($block | index($rule) != null)],
          domain_rule_overlaps:$overlaps,
          domain_rule_coverages:$coverages,
          domain_rule_keyword_coverages:$keyword_coverages,
          tcp:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "matched-socks5" else "socks5" end),
          udp:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "matched-blocked" else "blocked" end)} +
          (if .routing.dns != null then {dns:{server:.routing.dns.server,
            port:.routing.dns.port,domain_rules:.routing.dns.domains}} else {} end) +
          (if .routing.hosts != null then {hosts:.routing.hosts} else {} end) +
          (if .routing.direct != null then {direct:{domain_rules:.routing.direct.domains}} else {} end) +
          (if .routing.block != null then {block:{domain_rules:.routing.block.domains}} else {} end) +
          (if .routing.block_ips != null then
            {block_ips:({ip_rules:.routing.block_ips.ips} +
              if .routing.block_ips.resolve_domains == true then {resolve_domains:true} else {} end)}
           else {} end) +
          (if .routing.block_bt == true then {block_bt:true} else {} end) +
          (if .routing.region != null then {region:(.routing.region +
            {default_allow_domains:$region_defaults})} else {} end) +
          (if .routing.ipv6 != null then {ipv6:.routing.ipv6} else {} end) +
          (if .routing.warp != null then {warp:{mode:.routing.warp.mode,
            family:.routing.warp.family,domains:.routing.warp.domains}} else {} end) +
          {http_relay:(if .relay.http != null then
            (.relay.http | {enabled:true,core,port,address_families,source_ips})
            else {enabled:false} end)}' "${normalized}"
        return $?
    fi
    if [[ "${action}" == list ]]; then
        jq -r 'def authority: if contains(":") then "[\(.)]" else . end;
          . as $request |
          .core.protocols[] |
          if $request.reality_stream != null and
            (.listener_id == $request.reality_stream.listener_id or .listener_id == $request.reality_stream.website_listener_id)
          then .public_port = 443 else . end |
          "\(.listener_id)  \(.core)  \(if .id == 1 then "Reality Vision"
            elif .id == 2 then "Reality XHTTP" elif .id == 26 then "Reality gRPC"
            elif .id == 3 then "Hysteria2" elif .id == 4 then "AnyTLS"
            elif .id == 5 then "NaiveProxy" elif .id == 30 then "Shadowsocks"
            elif .id == 31 then "TUIC" elif .id == 28 then "Trojan direct"
            elif .id == 22 then "VMess WS TLS"
            elif .id == 23 then "VMess HTTPUpgrade TLS"
            elif .id == 24 then "VLESS gRPC TLS"
            elif .id == 25 then "Trojan gRPC TLS"
            elif .id == 27 then "VLESS TCP TLS Vision"
            elif .id == 29 then "Trojan TCP TLS fallback"
            else "WS TLS" end)  \(.server | authority):\(.public_port)  [\(.address_families | join(","))]  \(.name)"' \
            "${normalized}"
        return $?
    fi
    if [[ "${action}" == stream-status ]]; then
        jq -r '
          if .reality_stream == null then
            "Reality 443 共存: 未启用"
          else
            .reality_stream as $stream |
            (.core.protocols[] | select(.listener_id == $stream.listener_id)) as $reality |
            "Reality 443 共存: 已启用",
            (if $stream.host_website != null then
              $stream.host_website as $website |
              "网站类型: 宿主网站",
              "网站网络: \(if $website.network_mode == "host" then "host（回环）" else "bridge（容器可达）" end)",
              "网站域名: \($website.domains | join(","))",
              "网站 TLS 后端: \(if $website.address | contains(":") then "[\($website.address)]" else $website.address end):\($website.port)"
             else
              (.core.protocols[] | select(.listener_id == $stream.website_listener_id)) as $website |
              ($website.websocket // $website.httpupgrade // $website.grpc_tls) as $tls |
              "网站类型: 受管 TLS",
              "网站入口: \($website.listener_id)，域名 \($tls.domain)",
              "网站 TLS 后端: nginx:\($tls.tls_port)"
             end),
            "默认 Reality: \($reality.listener_id)，\(if $reality.id == 1 then "Vision" else "XHTTP" end)",
            "Reality 原后端: xray:\($reality.public_port)",
            "公网入口: \(if $reality.server | contains(":") then "[\($reality.server)]" else $reality.server end):443 [\($reality.address_families | join(","))]"
          end
        ' "${normalized}"
        return $?
    fi
    if [[ -n "${targetAction}" ]]; then
        # 公共目标库不依赖所选入口；只操作 Docker 的目标状态，不改部署规格。
        source "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/lib/reality-targets.sh" || return "${PADM_DOCKER_RC_STATE}"
        dockerReleaseDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
        dockerRealityTargetAction "${normalized}" "${targetAction}" "${targetArgs[@]}"
        return $?
    fi
    selected="${workspace}/selected.json"
    # 分享链接是本地只读输出，不受 HTTPS 订阅发布开关影响；只改私密副本。
    jq --arg listener "${listener}" '
      .core.protocols |= map(select($listener == "" or .listener_id == $listener)) |
      if (.core.protocols | length) > 0 then . else error("入口 ID 不存在") end |
      .subscription.enabled = true
    ' "${normalized}" >"${selected}" 2>/dev/null || {
        dockerError '入口 ID 不存在，未输出链接'
        return "${PADM_DOCKER_RC_STATE}"
    }
    chmod 0600 "${selected}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == targets || "${action}" == check-target || "${action}" == target-status ||
        "${action}" == select-target || "${action}" == block-current-target ]]; then
        jq '.core.protocols |= map(select(.id == 1 or .id == 2 or .id == 26))' \
            "${selected}" >"${selected}.next" &&
            chmod 0600 "${selected}.next" && mv -f -- "${selected}.next" "${selected}" ||
            return "${PADM_DOCKER_RC_STATE}"
        jq -e '.core.protocols | length > 0' "${selected}" >/dev/null || {
            dockerError '没有匹配的 Reality 入口'
            return "${PADM_DOCKER_RC_STATE}"
        }
        if [[ "${action}" == targets ]]; then
            jq -r '.core.protocols[] |
              "\(.listener_id)  \(.core)  \(.reality.target_host):\(.reality.target_port)  SNI=\(.reality.server_name)"' \
                "${selected}"
            return $?
        fi
        source "${DOCKER_BUNDLE_SOURCE_ROOT}/docker/lib/reality-targets.sh" || return "${PADM_DOCKER_RC_STATE}"
        # 在线检测和分页选择只使用私密快照；等待期间不占用部署锁。
        dockerReleaseDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
        case "${action}" in
        target-status) dockerRealityTargetAction "${selected}" status; return $? ;;
        check-target)
            status=0
            dockerRealityTargetAction "${selected}" check || status=$?
            case "${status}" in
            0|130|143) return "${status}" ;;
            *) return "${PADM_DOCKER_RC_STATE}" ;;
            esac
            ;;
        block-current-target)
            selectedHost=$(jq -er 'if (.core.protocols | length) == 1 then
              .core.protocols[0].reality.target_host else error("需要唯一入口") end' "${selected}") ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerRealityTargetAction "${selected}" block "${selectedHost}"
            return $?
            ;;
        esac
        status=0
        dockerRealityTargetAction "${selected}" select "${workspace}/selection.json" || status=$?
        [[ "${status}" -eq 2 ]] || return "${status}"
        selectedHost=$(jq -er '.host' "${workspace}/selection.json") &&
            selectedPort=$(jq -er '.port' "${workspace}/selection.json") &&
            selectedSni=$(jq -er '.sni' "${workspace}/selection.json") || return "${PADM_DOCKER_RC_STATE}"
        dockerSetupCleanup || return "${PADM_DOCKER_RC_STATE}"
        # 独立 CLI 执行完整中断恢复并重新在线复测，不把缓存 A 级当作切换授权。
        bash "${root}/bundle/install-docker.sh" edit \
            --reality-target "${listener}" "${selectedHost}" "${selectedPort}" "${selectedSni}"
        return $?
    fi
    # 命令标准输出只含 URI，便于直接导入或复制，不混入菜单说明。
    dockerGenerateSubscription "${selected}" /dev/stdout
)

dockerEditHy2PasswordRead() {
    local variable=$1 draft=$2 listener=$3 password defaultPassword opsImage
    defaultPassword=$(jq -r --arg key "${listener}" '
      .core.protocols[] | select(.listener_id == $key) | .hy2.obfs.password // ""
    ' "${draft}") || return 1
    printf '混淆密码（16..128 位字母/数字/_/-，空输入保留或随机生成，0 取消）: '
    IFS= read -r -s password || return 3
    printf '\n'
    [[ "${password}" != 0 ]] || return 3
    password=${password:-${defaultPassword}}
    if [[ -z "${password}" ]]; then
        opsImage=$(dockerResolveOpsImage) || return 1
        password=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    [[ "${password}" =~ ^[A-Za-z0-9_-]{16,128}$ ]] || return 1
    printf -v "${variable}" '%s' "${password}"
}

dockerEditEntryRemove() {
    local draft=$1 listener=$2 output=$3
    jq -e --arg key "${listener}" '
      ([.core.protocols[] | select(.listener_id == $key)] | length) == 1 and
      all(.accounts[]?; .listeners != [$key]) and
      (.reality_stream == null or
        (.reality_stream.listener_id != $key and .reality_stream.website_listener_id != $key)) and
      (all(.host_integrations[]; .type != "fail2ban") or
        all(.core.protocols[] | select(.listener_id == $key);
          .id != 21 and .id != 22 and .id != 23 and .id != 24 and .id != 25))
    ' "${draft}" >/dev/null 2>&1 || {
        dockerError '删除需要唯一入口；请先处理账号最后关联、Reality 共存或 Fail2ban 保护'
        return 1
    }
    jq --arg key "${listener}" '
      .core.type as $primary |
      .core.protocols |= map(select(.listener_id != $key)) |
      if has("accounts") then
        .accounts |= map(.listeners |= map(select(. != $key)))
      else . end |
      if has("port_aliases") then
        .port_aliases |= map(select(.listener_id != $key)) |
        if .port_aliases == [] then del(.port_aliases) else . end
      else . end |
      if has("cdn_entries") then
        .cdn_entries |= map(select(.listener_id != $key)) |
        if .cdn_entries == [] then del(.cdn_entries) else . end
      else . end |
      if all(.core.protocols[]; .core != $primary) then error("主核心至少保留一个入口")
      elif any(.core.protocols[]; .id == 21) then .
      elif any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 28 or .id == 29 or .id == 31)
      then .subscription.enabled = false
      else .tls = null | .subscription.enabled = false end |
      .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null) |
      if any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29)
      then . else
        del(.tls.http01) |
        if .site.mode == "static" and any(.core.protocols[]; .id == 3)
        then . else del(.site) end
      end
    ' "${draft}" >"${output}" 2>/dev/null || {
        dockerError '主核心至少保留一个入口；删除副核心的最后入口会关闭副核心'
        return 1
    }
}

dockerEditEntryAdd() {
    local draft=$1 listener=$2 targetProtocol=$3 targetCore=$4 port=$5 action=$6 output=$7
    jq --arg key "${listener}" --arg targetCore "${targetCore}" --argjson port "${port}" \
        --argjson targetProtocol "${targetProtocol}" --arg action "${action}" \
        --slurpfile ssCredentials "${8:-/dev/null}" --arg tlsDomain "${9:-}" '
      def reality: . == 1 or . == 2 or . == 26;
      def nginx: . == 21 or . == 22 or . == 23 or . == 24 or . == 25;
      def available($start; $used):
        first(range($start; 65536) | . as $p | select(($used | index($p)) == null)) //
          error("没有空闲内部端口");
      def supported($id; $core):
        if $id == 1 or $id == 26 or $id == 23 or $id == 28
        then $core == "xray" or $core == "sing-box"
        elif $id == 2 or ($id | nginx) or $id == 27 or $id == 29 then $core == "xray"
        elif $id == 3 or $id == 4 or $id == 5 or $id == 30 or $id == 31 then $core == "sing-box"
        else false end;
      def ss_key: type == "string" and test("^[A-Za-z0-9+/]{21}[AQgw]==\\z");
      if $tlsDomain == "" then . else
        if $action != "protocol" or .tls != null or ($targetProtocol | reality) or $targetProtocol == 30
        then error("只能为新增 TLS 协议设置首个证书域名") else .tls = {domain:$tlsDomain} end
      end |
      . as $r |
      [.core.protocols[] | select(.listener_id == $key)] as $selected |
      if ($selected | length) != 1 or (.core.protocols | length) >= 16
      then error("需要唯一源入口且最多16个入口") else . end |
      $selected[0] as $source |
      if (supported($targetProtocol; $targetCore) | not) or
        ($targetCore != .core.type and (.host_integrations | length) != 0) or
        (($targetProtocol | nginx) and any(.host_integrations[]; .type == "fail2ban")) or
        ($action == "copy" and $targetProtocol != $source.id) or
        ($action == "derive" and
          (($source.id | reality | not) or ($targetProtocol | reality | not))) or
        ($action == "protocol" and (.schema_version != 3 or
          (($targetProtocol | reality) and ($source.id | reality | not)) or
          (($targetProtocol | reality | not) and $targetProtocol != 30 and
            ((.tls.domain | type) != "string" or .tls.domain == ""))))
      then error("协议、核心或 TLS 前提不支持") else . end |
      first(range(1; 18) | "entry-\(.)" | . as $id |
        select(all($r.core.protocols[]; .listener_id != $id))) as $newId |
      (if $action == "copy" or ($action == "protocol" and $targetProtocol == $source.id) then $source
       elif ($targetProtocol | reality) then
         $source | del(.xhttp, .grpc) | .id = $targetProtocol |
         if .id == 2 then
           .xhttp = {path: ("/" + $newId + "xhttp"), host: .reality.server_name, mode: "auto"} |
           if $source.id == 2 then .xhttp += ($source.xhttp | del(.path,.host,.mode)) else . end
         elif .id == 26 then .grpc = {service_name: "grpc"} else . end
       else
         ($source | {id:$targetProtocol,core:.core,server:.server,public_port:$port,
           address_families:.address_families,name:.name,uuid:.uuid}) +
         if $targetProtocol == 3 then
           {hy2:{domain:$r.tls.domain,bandwidth_mode:"bbr",up_mbps:100,down_mbps:50,
             obfs:null,masquerade:""}}
         elif $targetProtocol == 4 then {anytls:{domain:$r.tls.domain}}
         elif $targetProtocol == 5 then {server:$r.tls.domain,naive:{domain:$r.tls.domain}}
         elif $targetProtocol == 31 then
           {tuic:{domain:$r.tls.domain,congestion_control:"cubic",auth_timeout:"3s",
             heartbeat:"10s",zero_rtt_handshake:false}}
         elif $targetProtocol == 28 then {trojan:{domain:$r.tls.domain}}
         elif $targetProtocol == 21 or $targetProtocol == 22 then
           {websocket:{domain:$r.tls.domain,path:($newId+"path")}}
         elif $targetProtocol == 23 then {httpupgrade:{domain:$r.tls.domain,path:($newId+"path")}}
         elif $targetProtocol == 24 or $targetProtocol == 25 then
           {grpc_tls:{domain:$r.tls.domain,service_name:"grpc"}}
         elif $targetProtocol == 27 or $targetProtocol == 29 then
           {fallback_tls:{domain:$r.tls.domain}}
         elif $targetProtocol == 30 then
           ([$r.core.protocols[] | select(.id == 30 and .uuid == $source.uuid) |
             .shadowsocks][0] // null) as $existing |
           if $existing != null then {shadowsocks:$existing} else
             ([$r.core.protocols[] | select(.id == 30) |
               .shadowsocks.server_password,.shadowsocks.user_password] +
              [$r.accounts[]?.shadowsocks_password | select(. != null)]) as $used |
             # 占位仅校验草稿；真正提交前用验签后的随机输入完整重生成。
             ($ssCredentials[0] // (
               [limit(2; range(0; 1024) | tostring | ("0000000000" + .)[-10:] |
                 ("PADMSS" + .) | @base64 | . as $key | select(($used | index($key)) == null))] |
               {server_password:.[0],user_password:.[1]})) as $credentials |
             if ($credentials | keys) != ["server_password","user_password"] or
               ($credentials.server_password | ss_key | not) or
               ($credentials.user_password | ss_key | not) or
               $credentials.server_password == $credentials.user_password or
               any($used[]; . == $credentials.server_password or . == $credentials.user_password)
             then error("SS 输入无效或凭据冲突")
             else {shadowsocks:({method:"2022-blake3-aes-128-gcm"} + $credentials)} end
           end
         else error("目标协议不支持") end
       end |
       .listener_id = $newId | .core = $targetCore | .public_port = $port |
       # 核心内部监听与 Nginx 监听分别分配，复制和新增使用同一套冲突检查。
       if (.id | nginx) then
         (if .id == 23 then "httpupgrade"
          elif .id == 24 or .id == 25 then "grpc_tls" else "websocket" end) as $transport |
         ([$r.core.protocols[] | select(.core == $targetCore) |
           if .id == 21 or .id == 22 then .websocket.backend_port
           elif .id == 23 then .httpupgrade.backend_port
           elif .id == 24 or .id == 25 then .grpc_tls.backend_port else .public_port end] +
          [$r.host_integrations[] | select(.type == "tproxy" or .type == "redirect") | .settings.port] +
          [if $targetCore == "xray" then 10085 else 10087 end]) as $used |
         .[$transport].backend_port = available(
           (if .id == 23 then 31306 elif .id == 24 then 31301
            elif .id == 25 then 31304 else 31297 end); $used)
       else . end |
       if (.id | nginx) or
         (($action == "protocol" and $targetProtocol != $source.id) and (.id == 27 or .id == 29)) then
         ([$r.core.protocols[] |
           if .id == 21 or .id == 22 then .websocket.tls_port
           elif .id == 23 then .httpupgrade.tls_port
           elif .id == 24 or .id == 25 then .grpc_tls.tls_port
           elif .id == 27 or .id == 29 then .fallback_tls.http_port, .fallback_tls.http2_port
           else empty end] + [8080]) as $used |
         if .id == 27 or .id == 29 then
           .fallback_tls.http_port = available(31300; $used) |
           .fallback_tls.http2_port = available(31302; $used + [.fallback_tls.http_port])
         else
           (if .id == 23 then "httpupgrade"
            elif .id == 24 or .id == 25 then "grpc_tls" else "websocket" end) as $transport |
           .[$transport].tls_port = available(8443; $used)
         end
       else . end) as $new |
      .core.protocols += [$new] |
      if $action == "protocol" and $targetCore == .core.type then . else
        .core.type as $primary |
        .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null)
      end
    ' "${draft}" >"${output}" 2>/dev/null || {
        dockerError '新增需唯一源入口、空闲入口身份和匹配核心；跨核心拒绝宿主集成，TLS 协议沿用受管域名'
        return 1
    }
}

dockerEditFields() {
    local draft=$1 choice protocol listener field value= defaultValue= valueFile="${1}.value" temporary="${1}.next"
    local sourceCore targetCore coreChoice primaryCore targetProtocol obfsChoice= zeroRttChoice
    while :; do
        printf '\n1. 入口端口\n2. 服务器地址\n3. 地址族\n4. 节点名称\n5. Reality 目标/SNI\n6. WS/HTTPUpgrade 路径\n7. 订阅开关\n8. 验证并预览\n9. 复制入口\n10. 删除入口\n11. 安装其它 Reality 传输入口\n12. XHTTP/gRPC 参数\n13. Hysteria2 参数\n14. TUIC 参数\n0. 取消\n'
        dockerSetupRead choice '编辑项目: ' || return 3
        [[ "${choice}" != 8 ]] || return 0
        if [[ "${choice}" == 7 ]]; then
            dockerSetupRead value '启用 HTTPS 订阅？[y/N]: ' n || return 3
            case "${value}" in y|Y|yes|YES) value=true ;; n|N|no|NO) value=false ;; *) return 1 ;; esac
            jq --argjson enabled "${value}" '.subscription.enabled = $enabled' "${draft}" >"${temporary}" || return 1
        else
            jq -r '.core.protocols[] | "入口 \(.listener_id)，核心 \(.core)，协议 \(.id): \(.server):\(.public_port)"' "${draft}" || return 1
            dockerSetupRead listener '入口 ID（单入口也可填协议 ID，0 取消）: ' || return 3
            listener=$(jq -er --arg key "${listener}" '
              [.core.protocols[] | select(.listener_id == $key or (.id | tostring) == $key)] |
              if length == 1 then .[0].listener_id else error("入口选择不唯一") end
            ' "${draft}" 2>/dev/null) || return 1
            protocol=$(jq -r --arg key "${listener}" '.core.protocols[] | select(.listener_id == $key) | .id' "${draft}") || return 1
            if [[ "${choice}" == 1 || "${choice}" == 3 || "${choice}" == 10 ]] &&
                jq -e --arg key "${listener}" '.reality_stream != null and
                  (.reality_stream.listener_id == $key or .reality_stream.website_listener_id == $key)' \
                    "${draft}" >/dev/null; then
                dockerError 'Reality 443 共存绑定入口不能改原端口、地址族或删除；请先关闭共存'
                return 1
            fi
            if [[ ( "${protocol}" == 21 || "${protocol}" == 22 || "${protocol}" == 23 || "${protocol}" == 24 || "${protocol}" == 25 ) && ( "${choice}" == 1 || "${choice}" == 9 || "${choice}" == 10 ) ]] &&
                jq -e 'any(.host_integrations[]; .type == "fail2ban")' "${draft}" >/dev/null; then
                dockerError '带 Fail2ban 的 WS 入口需联动封禁规则，本阶段未开放端口或入口数量修改'
                return 1
            fi
            if [[ "${choice}" == 10 ]]; then
                dockerEditEntryRemove "${draft}" "${listener}" "${temporary}" || return 1
            elif [[ "${choice}" == 9 || "${choice}" == 11 ]]; then
                targetProtocol=${protocol}
                if [[ "${choice}" == 11 ]]; then
                    [[ "${protocol}" == 1 || "${protocol}" == 2 || "${protocol}" == 26 ]] || return 1
                    dockerSetupRead targetProtocol 'Reality 传输 [1=Vision, 2=XHTTP, 26=gRPC，0=取消]: ' "${protocol}" || return 3
                    [[ "${targetProtocol}" == 1 || "${targetProtocol}" == 2 || "${targetProtocol}" == 26 ]] || return 1
                fi
                sourceCore=$(jq -r --arg key "${listener}" '.core.protocols[] | select(.listener_id == $key) | .core' "${draft}") || return 1
                primaryCore=$(jq -r '.core.type' "${draft}") || return 1
                if [[ "${sourceCore}" == xray ]]; then defaultValue=1; else defaultValue=2; fi
                dockerSetupRead coreChoice "目标核心 [1=Xray, 2=sing-box，空输入保留 ${sourceCore}，0=取消]: " "${defaultValue}" || return 3
                case "${coreChoice}" in 1) targetCore=xray ;; 2) targetCore=sing-box ;; *) return 1 ;; esac
                if [[ ( "${targetProtocol}" == 21 || "${targetProtocol}" == 22 || "${targetProtocol}" == 24 || "${targetProtocol}" == 25 || "${targetProtocol}" == 27 || "${targetProtocol}" == 29 || "${targetProtocol}" == 2 ) && "${targetCore}" != xray ]]; then
                    dockerError 'WS TLS、gRPC TLS、TCP TLS fallback 和 Reality XHTTP 入口仅支持 Xray，不能复制到 sing-box'
                    return 1
                fi
                if [[ "${targetProtocol}" == 3 && "${targetCore}" != sing-box ]]; then
                    dockerError 'Hysteria2 入口仅支持 sing-box，不能复制到 Xray'
                    return 1
                fi
                if [[ "${targetProtocol}" == 4 && "${targetCore}" != sing-box ]]; then
                    dockerError 'AnyTLS 入口仅支持 sing-box，不能复制到 Xray'
                    return 1
                fi
                if [[ "${targetProtocol}" == 5 && "${targetCore}" != sing-box ]]; then
                    dockerError 'NaiveProxy 入口仅支持 sing-box，不能复制到 Xray'
                    return 1
                fi
                if [[ "${targetProtocol}" == 30 && "${targetCore}" != sing-box ]]; then
                    dockerError 'Shadowsocks 入口仅支持 sing-box，不能复制到 Xray'
                    return 1
                fi
                if [[ "${targetProtocol}" == 31 && "${targetCore}" != sing-box ]]; then
                    dockerError 'TUIC 入口仅支持复制到同一 sing-box 核心'
                    return 1
                fi
                if [[ "${targetCore}" != "${primaryCore}" ]] &&
                    jq -e '.host_integrations | length > 0' "${draft}" >/dev/null; then
                    dockerError '已有宿主集成尚未支持双核心共存，不能启用副核心'
                    return 1
                fi
                dockerSetupRead value '新入口端口（0 取消）: ' || return 3
                [[ "${value}" =~ ^[0-9]{1,5}$ ]] || return 1
                dockerEditEntryAdd "${draft}" "${listener}" "${targetProtocol}" "${targetCore}" "${value}" \
                    "$([[ "${choice}" == 11 ]] && printf derive || printf copy)" "${temporary}" || return 1
            else
            case "${choice}" in
            1)
                if [[ "${protocol}" == 21 || "${protocol}" == 22 || "${protocol}" == 23 || "${protocol}" == 24 || "${protocol}" == 25 ]] &&
                    jq -e 'any(.host_integrations[]; .type == "fail2ban")' "${draft}" >/dev/null; then
                    dockerError '带 Fail2ban 的 WS 入口端口需联动封禁规则，本阶段未开放端口修改'
                    return 1
                fi
                field=public_port
                ;;
            2) field=server ;;
            3) field=address_families ;;
            4) field=name ;;
            5)
                [[ "${protocol}" == 1 || "${protocol}" == 2 || "${protocol}" == 26 ]] || return 1
                dockerSetupRead value 'Reality 参数 [1=目标域名, 2=目标端口, 3=SNI]: ' || return 3
                case "${value}" in
                1) field=reality.target_host ;;
                2) field=reality.target_port ;;
                3) field=reality.server_name ;;
                *) return 1 ;;
                esac
                ;;
            6)
                if [[ "${protocol}" == 21 || "${protocol}" == 22 ]]; then field=websocket.path
                elif [[ "${protocol}" == 23 ]]; then field=httpupgrade.path
                else return 1; fi
                ;;
            12)
                if [[ "${protocol}" == 2 ]]; then
                    dockerSetupRead value 'XHTTP 参数 [1=路径, 2=Host, 3=模式]: ' || return 3
                    case "${value}" in 1) field=xhttp.path ;; 2) field=xhttp.host ;; 3) field=xhttp.mode ;; *) return 1 ;; esac
                elif [[ "${protocol}" == 26 ]]; then
                    field=grpc.service_name
                elif [[ "${protocol}" == 24 || "${protocol}" == 25 ]]; then
                    field=grpc_tls.service_name
                else
                    return 1
                fi
                ;;
            13)
                [[ "${protocol}" == 3 ]] || {
                    dockerError '仅支持编辑已有 Hysteria2 入口；安装新 Hysteria2 请导入完整 configure 规格'
                    return 1
                }
                dockerSetupRead value 'Hysteria2 参数 [1=拥塞模式, 2=服务端上行 Mbps, 3=服务端下行 Mbps, 4=混淆, 5=伪装 HTTPS/local]: ' || return 3
                case "${value}" in
                1) field=hy2.bandwidth_mode ;;
                2) field=hy2.up_mbps ;;
                3) field=hy2.down_mbps ;;
                4) field=hy2.obfs ;;
                5) field=hy2.masquerade ;;
                *) return 1 ;;
                esac
                ;;
            14)
                [[ "${protocol}" == 31 ]] || {
                    dockerError '仅支持编辑已有 TUIC 入口；安装新 TUIC 请导入完整 configure 规格'
                    return 1
                }
                dockerSetupRead value 'TUIC 参数 [1=拥塞控制, 2=认证超时, 3=心跳间隔, 4=0-RTT]: ' || return 3
                case "${value}" in
                1) field=tuic.congestion_control ;;
                2) field=tuic.auth_timeout ;;
                3) field=tuic.heartbeat ;;
                4) field=tuic.zero_rtt_handshake ;;
                *) return 1 ;;
                esac
                ;;
            *) return 1 ;;
            esac
            defaultValue=$(jq -r --arg key "${listener}" --arg field "${field}" '
              .core.protocols[] | select(.listener_id == $key) | getpath($field | split(".")) |
              if type == "array" then
                if . == ["ipv4"] then "1" elif . == ["ipv6"] then "2" else "3" end
              else tostring end
            ' "${draft}") || return 1
            if [[ "${field}" == hy2.obfs ]]; then
                defaultValue=$(jq -r --arg key "${listener}" '
                  .core.protocols[] | select(.listener_id == $key) | .hy2.obfs.type //
                    "off" | if . == "off" then "1" elif . == "gecko" then "3" else "2" end
                ' "${draft}") || return 1
                dockerSetupRead obfsChoice '混淆 [1=关闭, 2=Salamander, 3=Gecko，空输入保留]: ' "${defaultValue}" || return 3
                case "${obfsChoice}" in
                1) value= ;;
                2|3)
                    dockerEditHy2PasswordRead value "${draft}" "${listener}" || return $?
                    ;;
                *) return 1 ;;
                esac
            elif [[ "${field}" == address_families ]]; then
                dockerSetupRead value '地址族 [1=IPv4, 2=IPv6, 3=双栈，空输入保留]: ' "${defaultValue}" || return 3
                [[ "${value}" =~ ^[123]$ ]] || return 1
            elif [[ "${field}" == hy2.bandwidth_mode ]]; then
                dockerSetupRead value "拥塞模式 [bbr=自适应, brutal=固定带宽，空输入保留 ${defaultValue}]: " "${defaultValue}" || return 3
                [[ "${value}" == bbr || "${value}" == brutal ]] || return 1
            elif [[ "${field}" == hy2.masquerade ]]; then
                printf 'local 使用已发布的受管静态网页；请先在站点菜单发布目录或内置主题，并关闭混淆。\n'
                dockerSetupRead value '伪装 HTTPS 地址或 local（空输入保留，off 关闭，0 取消）: ' "${defaultValue}" || return 3
                [[ "${value}" != off ]] || value=
            elif [[ "${field}" == tuic.congestion_control ]]; then
                dockerSetupRead value "拥塞控制 [cubic/bbr/new_reno，空输入保留 ${defaultValue}]: " "${defaultValue}" || return 3
                [[ "${value}" == cubic || "${value}" == bbr || "${value}" == new_reno ]] || return 1
            elif [[ "${field}" == tuic.auth_timeout || "${field}" == tuic.heartbeat ]]; then
                dockerSetupRead value "时长 [正整数加 ms/s/m/h，空输入保留 ${defaultValue}]: " "${defaultValue}" || return 3
                [[ "${value}" =~ ^[1-9][0-9]{0,5}(ms|s|m|h)$ ]] || return 1
            elif [[ "${field}" == tuic.zero_rtt_handshake ]]; then
                zeroRttChoice=n
                [[ "${defaultValue}" == true ]] && zeroRttChoice=y
                dockerSetupRead value "0-RTT [y/n，开启会增加重放风险，空输入保留 ${zeroRttChoice}]: " "${zeroRttChoice}" || return 3
                case "${value}" in
                y|Y|yes|YES) value=true ;;
                n|N|no|NO) value=false ;;
                *) return 1 ;;
                esac
            elif [[ "${field}" == grpc_tls.service_name ]]; then
                dockerSetupRead value 'gRPC service_name（1..64 位字母/数字/_/-，空输入保留，0 取消）: ' "${defaultValue}" || return 3
                [[ "${value}" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || return 1
            else
                dockerSetupRead value '新值（空输入保留，0 取消）: ' "${defaultValue}" || return 3
            fi
            if [[ "${protocol}" == 5 && "${field}" == server ]] &&
                ! jq -e --arg key "${listener}" --arg server "${value}" '
                  .core.protocols[] | select(.listener_id == $key) | .naive.domain == $server
                ' "${draft}" >/dev/null; then
                dockerError 'NaiveProxy 服务器必须与 TLS 域名一致，原生 URI 不支持独立 SNI'
                return 1
            fi
            # 输入值可能含账号或 WS 路径，只经私密文件传给 jq。
            printf '%s' "${value}" >"${valueFile}" || return 1
            chmod 0600 "${valueFile}" || return 1
            jq --arg key "${listener}" --arg field "${field}" --arg obfsChoice "${obfsChoice}" \
                --rawfile value "${valueFile}" '
              (if $field == "public_port" or $field == "reality.target_port" or
                  $field == "hy2.up_mbps" or $field == "hy2.down_mbps" then ($value | tonumber)
               elif $field == "hy2.obfs" then
                 if $value == "" then null else
                   {type: (if $obfsChoice == "3" then "gecko" else "salamander" end), password: $value} end
               elif $field == "tuic.zero_rtt_handshake" then ($value | fromjson)
               elif $field == "address_families" then
                 if $value == "1" then ["ipv4"] elif $value == "2" then ["ipv6"] else ["ipv4","ipv6"] end
               else $value end) as $input |
              .core.protocols |= map(if .listener_id == $key then setpath($field | split("."); $input) else . end)
            ' "${draft}" >"${temporary}" 2>/dev/null || return 1
            fi
        fi
        chmod 0600 "${temporary}" && mv -f -- "${temporary}" "${draft}" || return 1
    done
}

dockerEditXhttpPaddingParse() {
    jq -cen --arg value "$1" '
      $value |
      if test("^[1-9][0-9]{0,3}\\z") then
        tonumber | if . <= 4096 then . else error("范围越界") end
      elif test("^[1-9][0-9]{0,3}-[1-9][0-9]{0,3}\\z") then
        . as $raw | split("-") | map(tonumber) |
        if .[0] <= .[1] and .[1] <= 4096 then $raw else error("范围越界或反转") end
      else error("不是规范正整数或范围") end
    ' 2>/dev/null
}

dockerEditXhttpLimitsParse() {
    jq -cen --arg post "$1" --arg interval "$2" --arg buffered "$3" --arg seconds "$4" '
      def integer:
        if test("^(0|[1-9][0-9]{0,9})\\z") then
          tonumber | if . <= 2147483647 then . else error("范围越界") end
        else error("不是规范非负整数") end;
      def seconds:
        if contains("-") then
          . as $raw | split("-") | map(integer) |
          if length == 2 and .[0] <= .[1] then $raw else error("范围反转") end
        else integer end;
      {scMaxEachPostBytes:($post | integer),scMinPostsIntervalMs:($interval | integer),
       scMaxBufferedPosts:($buffered | integer),scStreamUpServerSecs:($seconds | seconds)}
    ' 2>/dev/null
}

dockerEditTlsDomainChange() {
    local specFile=$1 domain=$2 target=$3
    dockerDomainIsValid "${domain}" || return 1
    jq --arg domain "${domain}" '
      ["websocket","httpupgrade","grpc_tls","hy2","anytls","naive",
       "fallback_tls","trojan","tuic"] as $fields |
      .tls.domain as $old |
      if ($old | type) != "string" or $old == $domain or
        (.host_integrations // []) != [] or .reality_stream != null or
        .port_hopping != null or .control != null or .control_sync != null
      then error("不支持此 TLS 域名迁移") else
        .tls.domain = $domain |
        .core.protocols |= map(
          . as $entry |
          if any($fields[]; . as $kind | $entry | has($kind)) then
            reduce $fields[] as $kind (.;
              if has($kind) then .[$kind].domain = $domain else . end) |
            if .server == $old then .server = $domain else . end
          else . end)
      end
    ' "${specFile}" >"${target}"
}

dockerEditCommand() {
    local specFile= manifest= bundle= controlBundle= mode=interactive root workspace original draft imported=0 status=0
    local privateKey publicKey derivedKey opsImage version normalized regenerateReality=
    local realityTarget= targetHost= targetPort= targetSni=
    local realityStream= streamListener= streamWebsite=
    local streamDomains= streamAddress= streamPort=8443
    local siteMode= siteSource= siteUrl= siteTemplate=
    local alpnListener= alpnOrder=
    local http01= socks5= socks5File= socks5Domains= routingKind= routingFile= routingAction=
    local routingServer= routingPort=
    local routingDomains='[]' routingOldDomains='[]' routingDomainsField=domains
    local routingOldIp= routingNewIp= routingHost=
    local httpRelay= httpRelayFile= httpRelayPort=0 httpRelaySources='[]'
    local tproxyAction= tproxyKind= transparentKind= tproxyPort=0 tproxyMark=0 tproxyFamily= tproxyOutput= tunAction=
    local portAlias= portAliasListener= portAliasPort= portAliasOldPort=
    local portHoppingAction= portHoppingListener= portHoppingStart=0 portHoppingEnd=0
    local portHoppingIpv4= portHoppingIpv6=
    local cdnAction= cdnListener= cdnAddresses=
    local xhttpAction= xhttpListener= xhttpPreset= xhttpValues='{}' xhttpPadding=null
    local xhttpNoGrpc=false xhttpNoSse=false xhttpLimits='{}'
    local protocolKind= protocolListener= protocolPatch='{}' protocolId=0
    local protocolPatchFile= hy2ObfsType= hy2ObfsFile= hy2ObfsPassword=
    local entryAction= entryListener= entryProtocol=0 entryPort=0 entryCore= entrySsCredentials=
    local entrySsGenerate=0 entrySsReady=0 entrySsServer= entrySsUser= entrySsImage= entrySsAttempt=
    local entryTlsDomain= entryTlsMode= entryTlsCert= entryTlsKey= entryTlsEmail=
    local entryTlsProvider= entryTlsCredentials= entryTlsSource= answer
    local tlsMigrateDomain=
    local regionMode= regionAllow='[]' regionAllowSet=0
    local ipv6Mode= ipv6Domains='[]' ipv6DomainsSet=0
    local warpFamily=
    local fail2banAction= fail2banType=fail2ban fail2banPorts= fail2banMaxRetry= fail2banFindTime= fail2banBanTime=
    local fail2banPortListener= fail2banNewPort=
    local fail2banSshUnit= fail2banSshTarget= fail2banSshPort=
    local DOCKER_CONFIG_RESTORE_ALPN_LISTENER=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --spec|--manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --spec) specFile=$2 ;;
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        --protocol-add)
            [[ "$#" -ge 4 && -n "$2" && "$2" != --* && -z "${entryAction}" &&
                "$3" =~ ^[1-9][0-9]?$ && "$4" =~ ^[1-9][0-9]{0,4}$ &&
                "$4" -le 65535 ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$3" in 1|2|3|4|5|21|22|23|24|25|26|27|28|29|30|31) ;;
                *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            entryAction=add entryListener=$2 entryProtocol=$3 entryPort=$4
            shift 4
            ;;
        --protocol-core)
            [[ "$#" -ge 2 && -z "${entryCore}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in xray|sing-box) entryCore=$2 ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            shift 2
            ;;
        --tls-domain)
            [[ "$#" -ge 2 && -z "${entryTlsDomain}" && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            entryTlsDomain=$2
            shift 2
            ;;
        --tls-migrate)
            [[ "$#" -ge 2 && -z "${tlsMigrateDomain}" && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            tlsMigrateDomain=$2
            shift 2
            ;;
        --tls-existing|--tls-import|--tls-dns|--tls-standalone)
            [[ -z "${entryTlsMode}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --tls-existing) entryTlsMode=1; shift ;;
            --tls-import)
                [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                entryTlsMode=2 entryTlsCert=$2 entryTlsKey=$3
                shift 3 ;;
            --tls-dns)
                [[ "$#" -ge 4 && -n "$4" && "$4" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                entryTlsMode=3 entryTlsEmail=$2 entryTlsProvider=$3 entryTlsCredentials=$4
                shift 4 ;;
            --tls-standalone)
                [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                entryTlsMode=4 entryTlsEmail=$2 entryTlsProvider=standalone
                shift 2 ;;
            esac
            ;;
        --protocol-remove|--protocol-rebuild)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${entryAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            entryAction=${1#--protocol-} entryListener=$2
            shift 2
            ;;
        --site-static|--site-redirect)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${siteMode}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "$1" == --site-static ]]; then
                siteMode=static siteSource=$2
            else
                siteMode=redirect siteUrl=$2
            fi
            shift 2
            ;;
        --site-template)
            [[ "$#" -ge 2 && -z "${siteMode}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in notes|photos|docs) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            siteMode=static siteTemplate=$2
            shift 2
            ;;
        --site-default)
            [[ -z "${siteMode}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            siteMode=default
            shift
            ;;
        --http01)
            [[ "$#" -ge 2 && -z "${http01}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in enable|disable) http01=$2 ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            shift 2
            ;;
        --socks5)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${socks5}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            socks5=enable socks5File=$2
            shift 2
            ;;
        --socks5-off)
            [[ -z "${socks5}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            socks5=disable
            shift
            ;;
        --socks5-domains)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${socks5}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            socks5Domains=$(dockerSocks5DomainsNormalize "$2") || return "${PADM_DOCKER_RC_USAGE}"
            socks5=domains
            shift 2
            ;;
        --socks5-global)
            [[ -z "${socks5}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            socks5=global
            shift
            ;;
        --dns-rules)
            [[ "$#" -ge 4 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* &&
                -n "$4" && "$4" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            [[ "$3" =~ ^[0-9]{1,5}$ ]] || return "${PADM_DOCKER_RC_USAGE}"
            [[ "$((10#$3))" -ge 1 && "$((10#$3))" -le 65535 ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=dns routingAction=rules routingServer=$2
            routingPort=$((10#$3))
            routingDomains=$(dockerSocks5DomainsNormalize "$4") ||
                return "${PADM_DOCKER_RC_USAGE}"
            shift 4
            ;;
        --dns-upstream|--socks5-upstream)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${routingKind}" &&
                "$3" =~ ^[0-9]{1,5}$ ]] || return "${PADM_DOCKER_RC_USAGE}"
            [[ "$((10#$3))" -ge 1 && "$((10#$3))" -le 65535 ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=${1#--} routingKind=${routingKind%-upstream}
            routingAction=upstream routingServer=$2 routingPort=$((10#$3))
            shift 3
            ;;
        --direct-domains|--block-domains|--direct-domains-add|--block-domains-add|--direct-domains-remove|--block-domains-remove|--dns-domains-add|--dns-domains-remove|--warp-domains-add|--warp-domains-remove|--ipv6-domains-add|--ipv6-domains-remove|--socks5-domains-add|--socks5-domains-remove)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=${1#--} routingAction=domains
            if [[ "${routingKind}" == *-add ]]; then
                routingKind=${routingKind%-add} routingAction=domains_add
            elif [[ "${routingKind}" == *-remove ]]; then
                routingKind=${routingKind%-remove} routingAction=domains_remove
            fi
            routingKind=${routingKind%-domains}
            routingDomains=$(dockerSocks5DomainsNormalize "$2") ||
                return "${PADM_DOCKER_RC_USAGE}"
            shift 2
            ;;
        --dns-domains-replace|--direct-domains-replace|--block-domains-replace|--warp-domains-replace|--ipv6-domains-replace|--region-allow-replace|--socks5-domains-replace)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && "$2" != *,* &&
                -n "$3" && "$3" != --* && "$3" != *,* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingAction=domains_replace
            if [[ "$1" == --region-allow-replace ]]; then
                routingKind=region routingDomainsField=allow_domains
            else
                routingKind=${1#--} routingKind=${routingKind%-domains-replace}
            fi
            routingOldDomains=$(dockerSocks5DomainsNormalize "$2") &&
                routingDomains=$(dockerSocks5DomainsNormalize "$3") &&
                jq -en --argjson old "${routingOldDomains}" --argjson domains "${routingDomains}" \
                    '($old | length) == 1 and ($domains | length) == 1' >/dev/null ||
                return "${PADM_DOCKER_RC_USAGE}"
            shift 3
            ;;
        --block-ips-add|--block-ips-remove)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=block_ips routingFile=$2
            if [[ "$1" == --block-ips-add ]]; then
                routingAction=ips_add
            else
                routingAction=ips_remove
            fi
            shift 2
            ;;
        --block-ips-replace)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && "$2" != *,* && "$2" != geoip:* &&
                -n "$3" && "$3" != --* && "$3" != *,* && "$3" != geoip:* &&
                -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=block_ips routingAction=ips_replace routingOldIp=$2 routingNewIp=$3
            shift 3
            ;;
        --block-ips-resolve|--block-ips-literal)
            [[ -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=block_ips routingAction=${1#--block-ips-}
            routingAction=ips_${routingAction}
            shift
            ;;
        --hosts-replace|--hosts-add)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && "$2" != *[[:space:]]* &&
                -n "$3" && "$3" != --* && "$3" != *[[:space:]]* &&
                -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingHost=$(jq -nr --arg host "$2" '$host | ascii_downcase') ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=hosts routingAction="host_${1#--hosts-}" routingNewIp=$3
            shift 3
            ;;
        --hosts-remove)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && "$2" != *[[:space:]]* &&
                -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingHost=$(jq -nr --arg host "$2" '$host | ascii_downcase') ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=hosts routingAction=host_remove
            shift 2
            ;;
        --http-relay)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${httpRelay}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            httpRelay=enable httpRelayFile=$2
            shift 2
            ;;
        --http-relay-off)
            [[ -z "${httpRelay}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            httpRelay=disable
            shift
            ;;
        --http-relay-port)
            [[ "$#" -ge 2 && -z "${httpRelay}" && "$2" =~ ^[0-9]{1,5}$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            httpRelayPort=$((10#$2))
            (( httpRelayPort >= 1 && httpRelayPort <= 65535 )) ||
                return "${PADM_DOCKER_RC_USAGE}"
            httpRelay=port
            shift 2
            ;;
        --http-relay-sources|--http-relay-sources-add|--http-relay-sources-remove)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${httpRelay}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            httpRelay=${1#--http-relay-}
            httpRelaySources=$(jq -ecn --arg input "$2" '
              $input | split(",") | map(gsub("^\\s+|\\s+$"; "")) |
              reduce .[] as $rule ([]; if index($rule) == null then . + [$rule] else . end) |
              select(length >= 1 and length <= 256 and all(.[]; . != ""))
            ' 2>/dev/null) || return "${PADM_DOCKER_RC_USAGE}"
            shift 2
            ;;
        --tproxy-enable|--tproxy-settings|--redirect-enable|--redirect-settings)
            transparentKind=${1#--}
            transparentKind=${transparentKind%%-*}
            [[ -z "${tproxyKind}" || "${tproxyKind}" == "${transparentKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${transparentKind}" == redirect ]]; then
                [[ "$#" -ge 2 && -z "${tproxyAction}" &&
                    "$2" =~ ^[1-9][0-9]{0,4}$ && "$2" -le 65535 ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                tproxyKind=redirect tproxyAction=${1#--redirect-} tproxyPort=$2
                shift 2
                continue
            fi
            [[ "$#" -ge 3 && -z "${tproxyAction}" &&
                "$2" =~ ^[1-9][0-9]{0,4}$ && "$2" -le 65535 &&
                "$3" =~ ^[1-9][0-9]{0,9}$ && "$3" -le 2147483647 &&
                "$3" != 253 && "$3" != 254 && "$3" != 255 ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            tproxyKind=tproxy tproxyAction=${1#--tproxy-} tproxyPort=$2 tproxyMark=$3
            shift 3
            ;;
        --tproxy-off|--redirect-off)
            transparentKind=${1#--}
            transparentKind=${transparentKind%%-*}
            [[ -z "${tproxyAction}" && ( -z "${tproxyKind}" || "${tproxyKind}" == "${transparentKind}" ) ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            tproxyKind=${transparentKind}
            tproxyAction=off
            shift
            ;;
        --tproxy-family|--redirect-family)
            transparentKind=${1#--}
            transparentKind=${transparentKind%%-*}
            [[ "$#" -ge 2 && -z "${tproxyFamily}" &&
                ( -z "${tproxyKind}" || "${tproxyKind}" == "${transparentKind}" ) &&
                ( "$2" == ipv4 || "$2" == ipv6 || "$2" == dual ) ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            tproxyKind=${transparentKind} tproxyFamily=$2
            shift 2
            ;;
        --tproxy-output-uid|--redirect-output-uid)
            transparentKind=${1#--}
            transparentKind=${transparentKind%%-*}
            [[ "$#" -ge 2 && -z "${tproxyOutput}" && "$2" =~ ^[1-9][0-9]{0,9}$ &&
                ( -z "${tproxyKind}" || "${tproxyKind}" == "${transparentKind}" ) &&
                "$2" -le 2147483647 && "$2" != 10001 ]] || return "${PADM_DOCKER_RC_USAGE}"
            tproxyKind=${transparentKind} tproxyOutput=$2
            shift 2
            ;;
        --tproxy-output-off|--redirect-output-off|--tproxy-output-all|--redirect-output-all)
            transparentKind=${1#--}
            transparentKind=${transparentKind%%-*}
            [[ -z "${tproxyOutput}" && ( -z "${tproxyKind}" || "${tproxyKind}" == "${transparentKind}" ) ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            tproxyKind=${transparentKind} tproxyOutput=${1##*-}
            shift
            ;;
        --tun-enable|--tun-off)
            [[ -z "${tunAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            tunAction=${1#--tun-}
            shift
            ;;
        --fail2ban-port)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${fail2banAction}" &&
                "$3" =~ ^[1-9][0-9]{0,4}$ && "$3" -le 65535 ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            fail2banAction=port fail2banPortListener=$2 fail2banNewPort=$3
            shift 3
            ;;
        --fail2ban-enable|--fail2ban-settings|--fail2ban-control-enable|--fail2ban-control-settings|--fail2ban-ssh-enable|--fail2ban-ssh-settings)
            local fail2banArgCount=5 retryInput= findInput= banInput=
            [[ -z "${fail2banAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            if [[ "$1" == --fail2ban-ssh-* ]]; then
                fail2banType=fail2ban-ssh fail2banArgCount=7
                fail2banAction=${1#--fail2ban-ssh-}
            elif [[ "$1" == --fail2ban-control-* ]]; then
                fail2banType=fail2ban-control fail2banArgCount=4
                fail2banAction=${1#--fail2ban-control-}
            else
                fail2banAction=${1#--fail2ban-}
            fi
            [[ "$#" -ge "${fail2banArgCount}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${fail2banType}" == fail2ban-ssh ]]; then
                [[ "${#2}" -le 255 && "$2" =~ ^[A-Za-z0-9][A-Za-z0-9_.@:-]*\.service$ &&
                    "$4" =~ ^[1-9][0-9]{0,4}$ ]] &&
                    ((10#$4 <= 65535)) || return "${PADM_DOCKER_RC_USAGE}"
                dockerFail2banSourceAddress "$3" >/dev/null ||
                    return "${PADM_DOCKER_RC_USAGE}"
                fail2banSshUnit=$2 fail2banSshTarget=$3 fail2banSshPort=$4
                retryInput=$5 findInput=$6 banInput=$7
            elif [[ "${fail2banType}" == fail2ban ]]; then
                [[ "$2" =~ ^[0-9]{1,5}(,[0-9]{1,5}){0,15}$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
                local -a fail2banPortValues=()
                local fail2banPort fail2banPortNumber fail2banPortList=
                IFS=',' read -r -a fail2banPortValues <<<"$2"
                for fail2banPort in "${fail2banPortValues[@]}"; do
                    fail2banPortNumber=$((10#${fail2banPort}))
                    (( fail2banPortNumber >= 1 && fail2banPortNumber <= 65535 )) ||
                        return "${PADM_DOCKER_RC_USAGE}"
                    [[ ",${fail2banPortList}," != *",${fail2banPortNumber},"* ]] ||
                        return "${PADM_DOCKER_RC_USAGE}"
                    fail2banPortList+="${fail2banPortList:+,}${fail2banPortNumber}"
                done
                fail2banPorts=${fail2banPortList}
                retryInput=$3 findInput=$4 banInput=$5
            else
                retryInput=$2 findInput=$3 banInput=$4
            fi
            [[ "${retryInput}" =~ ^[0-9]{1,2}$ ]] && fail2banMaxRetry=$((10#${retryInput})) &&
                (( fail2banMaxRetry >= 1 && fail2banMaxRetry <= 20 )) ||
                return "${PADM_DOCKER_RC_USAGE}"
            [[ "${findInput}" =~ ^[0-9]{1,5}$ ]] && fail2banFindTime=$((10#${findInput})) &&
                (( fail2banFindTime >= 60 && fail2banFindTime <= 86400 )) ||
                return "${PADM_DOCKER_RC_USAGE}"
            [[ "${banInput}" =~ ^[0-9]{1,6}$ ]] && fail2banBanTime=$((10#${banInput})) &&
                (( fail2banBanTime >= 60 && fail2banBanTime <= 604800 )) ||
                return "${PADM_DOCKER_RC_USAGE}"
            shift "${fail2banArgCount}"
            ;;
        --fail2ban-off|--fail2ban-control-off|--fail2ban-ssh-off)
            [[ -z "${fail2banAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            [[ "$1" != --fail2ban-control-off ]] || fail2banType=fail2ban-control
            [[ "$1" != --fail2ban-ssh-off ]] || fail2banType=fail2ban-ssh
            fail2banAction=off
            shift
            ;;
        --hy2-obfs|--hy2-masquerade)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* &&
                -z "${protocolKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            protocolKind=hy2 protocolId=3 protocolListener=$2
            if [[ "$1" == --hy2-masquerade ]]; then
                protocolPatch=$(jq -cn --arg value "$3" '{masquerade:(if $value == "off" then "" else $value end)}') ||
                    return "${PADM_DOCKER_RC_USAGE}"
                shift 3
            else
                case "$3" in off|salamander|gecko) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
                hy2ObfsType=$3 protocolPatch='{"obfs":null}'
                if [[ "${hy2ObfsType}" != off && "$#" -ge 4 && -n "$4" && "$4" != --* ]]; then
                    hy2ObfsFile=$4
                    shift 4
                else
                    shift 3
                fi
            fi
            ;;
        --hy2-bandwidth)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${protocolKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            protocolKind=hy2 protocolId=3 protocolListener=$2
            case "$3" in
            bbr)
                protocolPatch='{"bandwidth_mode":"bbr"}'
                shift 3
                ;;
            brutal)
                [[ "$#" -ge 5 && "$4" =~ ^[1-9][0-9]{0,6}$ && "$5" =~ ^[1-9][0-9]{0,6}$ &&
                    "$4" -le 1000000 && "$5" -le 1000000 ]] || return "${PADM_DOCKER_RC_USAGE}"
                protocolPatch=$(jq -cn --argjson up "$4" --argjson down "$5" \
                    '{bandwidth_mode:"brutal",up_mbps:$up,down_mbps:$down}') ||
                    return "${PADM_DOCKER_RC_USAGE}"
                shift 5
                ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
            ;;
        --tuic-congestion|--tuic-connection|--tuic-zero-rtt|--tuic-defaults)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${protocolKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            protocolKind=tuic protocolId=31 protocolListener=$2
            case "$1" in
            --tuic-congestion)
                [[ "$#" -ge 3 ]] || return "${PADM_DOCKER_RC_USAGE}"
                case "$3" in cubic|bbr|new_reno) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
                protocolPatch=$(jq -cn --arg value "$3" '{congestion_control:$value}') ||
                    return "${PADM_DOCKER_RC_USAGE}"
                shift 3
                ;;
            --tuic-connection)
                [[ "$#" -ge 4 && "$3" =~ ^[1-9][0-9]{0,5}(ms|s|m|h)$ &&
                    "$4" =~ ^[1-9][0-9]{0,5}(ms|s|m|h)$ ]] || return "${PADM_DOCKER_RC_USAGE}"
                protocolPatch=$(jq -cn --arg timeout "$3" --arg heartbeat "$4" \
                    '{auth_timeout:$timeout,heartbeat:$heartbeat}') || return "${PADM_DOCKER_RC_USAGE}"
                shift 4
                ;;
            --tuic-zero-rtt)
                [[ "$#" -ge 3 ]] || return "${PADM_DOCKER_RC_USAGE}"
                case "$3" in true|false) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
                protocolPatch=$(jq -cn --argjson value "$3" '{zero_rtt_handshake:$value}') ||
                    return "${PADM_DOCKER_RC_USAGE}"
                shift 3
                ;;
            --tuic-defaults)
                protocolPatch='{"congestion_control":"cubic","auth_timeout":"3s","heartbeat":"10s","zero_rtt_handshake":false}'
                shift 2
                ;;
            esac
            ;;
        --xhttp-mode)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            case "$3" in auto|packet-up|stream-up) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            xhttpValues=$(jq -cn --arg mode "$3" '{mode:$mode}') || return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=mode xhttpListener=$2
            shift 3
            ;;
        --xhttp-path-host)
            [[ "$#" -ge 4 && -n "$2" && "$2" != --* && -n "$3" && -n "$4" &&
                -z "${xhttpAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            xhttpValues=$(jq -cn --arg path "$3" --arg host "$4" '{path:$path,host:$host}') ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=path-host xhttpListener=$2
            shift 4
            ;;
        --xhttp-advanced)
            [[ "$#" -ge 9 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpPadding=$(dockerEditXhttpPaddingParse "$3") || return "${PADM_DOCKER_RC_USAGE}"
            xhttpLimits=$(dockerEditXhttpLimitsParse "$4" "$5" "$6" "$7") ||
                return "${PADM_DOCKER_RC_USAGE}"
            case "$8" in true|false) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            case "$9" in true|false) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            xhttpValues=$(jq -cn --argjson padding "${xhttpPadding}" --argjson limits "${xhttpLimits}" \
                --argjson noGrpc "$8" --argjson noSse "$9" \
                '$limits + {xPaddingBytes:$padding,noGRPCHeader:$noGrpc,noSSEHeader:$noSse}') ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=advanced xhttpListener=$2
            shift 9
            ;;
        --xhttp-defaults)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpValues='{"mode":"auto","xmux":{"maxConcurrency":"16-32","hMaxRequestTimes":"600-900","hMaxReusableSecs":"1800-3000"},"xPaddingBytes":"100-1000","noGRPCHeader":false,"noSSEHeader":false,"scMaxEachPostBytes":1000000,"scMinPostsIntervalMs":30,"scMaxBufferedPosts":30,"scStreamUpServerSecs":"20-80"}'
            xhttpAction=defaults xhttpListener=$2
            shift 2
            ;;
        --xhttp-limits)
            [[ "$#" -ge 6 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpLimits=$(dockerEditXhttpLimitsParse "$3" "$4" "$5" "$6") ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=limits xhttpListener=$2
            shift 6
            ;;
        --xhttp-limits-clear)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=limits-clear xhttpListener=$2
            shift 2
            ;;
        --xhttp-preset)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            case "$3" in daily|compatible|stream|single) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            xhttpAction=preset xhttpListener=$2 xhttpPreset=$3
            shift 3
            ;;
        --xhttp-xmux)
            [[ "$#" -ge 5 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpValues=$(jq -cen --arg concurrency "$3" --arg requests "$4" --arg seconds "$5" '
              def value($min):
                if test("^(0|[1-9][0-9]{0,9})\\z") then
                  tonumber | if . >= $min and . <= 2147483647 then . else error("范围越界") end
                elif test("^(0|[1-9][0-9]{0,9})-(0|[1-9][0-9]{0,9})\\z") then
                  . as $raw | split("-") | map(tonumber) |
                  if .[0] >= $min and .[0] <= .[1] and .[1] <= 2147483647
                  then $raw else error("范围越界或反转") end
                else error("不是规范整数或范围") end;
              {maxConcurrency:($concurrency | value(1)),hMaxRequestTimes:($requests | value(0)),
               hMaxReusableSecs:($seconds | value(0))}
            ' 2>/dev/null) || return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=xmux xhttpListener=$2
            shift 5
            ;;
        --xhttp-xmux-clear)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=clear xhttpListener=$2
            shift 2
            ;;
        --xhttp-padding)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpPadding=$(dockerEditXhttpPaddingParse "$3") || {
                dockerError 'XHTTP Padding 仅支持 1–4096 的整数或正序范围；Xray 的 0/0-0 表示缺省，恢复缺省请使用 --xhttp-padding-clear'
                return "${PADM_DOCKER_RC_USAGE}"
            }
            xhttpAction=padding xhttpListener=$2
            shift 3
            ;;
        --xhttp-padding-clear)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=padding-clear xhttpListener=$2
            shift 2
            ;;
        --xhttp-headers)
            [[ "$#" -ge 4 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            case "$3" in true|false) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            case "$4" in true|false) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            xhttpAction=headers xhttpListener=$2 xhttpNoGrpc=$3 xhttpNoSse=$4
            shift 4
            ;;
        --xhttp-headers-clear)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${xhttpAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            xhttpAction=headers-clear xhttpListener=$2
            shift 2
            ;;
        --cdn-entry)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* &&
                "${#3}" -le 4096 && -z "${cdnAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            cdnAction=set cdnListener=$2 cdnAddresses=$3
            shift 3
            ;;
        --cdn-entry-clear)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${cdnAction}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            cdnAction=clear cdnListener=$2
            shift 2
            ;;
        --port-alias|--port-alias-remove|--port-alias-default|--port-alias-replace)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* &&
                -z "${portAlias}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            portAlias=${1#--} portAliasListener=$2
            if [[ "${portAlias}" == port-alias-default && "$3" == base ]]; then
                portAliasPort=base
            else
                [[ "$3" =~ ^[0-9]{1,5}$ ]] || return "${PADM_DOCKER_RC_USAGE}"
                [[ "$((10#$3))" -ge 1 && "$((10#$3))" -le 65535 ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                portAliasPort=$((10#$3))
            fi
            if [[ "${portAlias}" == port-alias-replace ]]; then
                [[ "$#" -ge 4 && "$4" =~ ^[0-9]{1,5}$ ]] &&
                    ((10#$4 >= 1 && 10#$4 <= 65535)) || return "${PADM_DOCKER_RC_USAGE}"
                portAliasOldPort=${portAliasPort} portAliasPort=$((10#$4))
                shift 4
            else
                shift 3
            fi
            ;;
        --port-hopping)
            [[ "$#" -ge 6 && -z "${portHoppingAction}" &&
                -n "$2" && "$2" != --* &&
                "$3" =~ ^[1-9][0-9]{0,4}$ && "$4" =~ ^[1-9][0-9]{0,4}$ &&
                "$3" -le "$4" && "$4" -le 65535 &&
                -n "$5" && "$5" != --* && -n "$6" && "$6" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            portHoppingAction=set portHoppingListener=$2 portHoppingStart=$3 portHoppingEnd=$4
            portHoppingIpv4=$5 portHoppingIpv6=$6
            shift 6
            ;;
        --port-hopping-clear)
            [[ -z "${portHoppingAction}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            portHoppingAction=clear
            shift
            ;;
        --warp-domains)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingDomains=$(dockerSocks5DomainsNormalize "$2") || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=warp routingAction=warp_domains
            shift 2
            ;;
        --warp-global)
            [[ -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=warp routingAction=warp_global
            shift
            ;;
        --warp-family)
            [[ "$#" -ge 2 && -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in ipv4|ipv6) warpFamily=$2 ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            routingKind=warp routingAction=warp_family
            shift 2
            ;;
        --dns|--hosts|--direct|--block|--block-ips|--warp)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=${1#--} routingFile=$2 routingAction=enable
            routingKind=${routingKind//-/_}
            shift 2
            ;;
        --block-bt)
            [[ -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=block_bt routingAction=enable
            shift
            ;;
        --region|--region-mode)
            [[ "$#" -ge 2 && -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in both|domain|ip) regionMode=$2 ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            routingKind=region routingAction=enable
            [[ "$1" != --region-mode ]] || routingAction=mode
            shift 2
            ;;
        --region-allow)
            [[ "$#" -ge 2 && "${regionAllowSet}" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            if [[ -n "$2" ]]; then
                regionAllow=$(dockerSocks5DomainsNormalize "$2") || return "${PADM_DOCKER_RC_USAGE}"
            fi
            regionAllowSet=1
            shift 2
            ;;
        --region-allow-add|--region-allow-remove)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingDomains=$(dockerSocks5DomainsNormalize "$2") || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=region routingAction=${1#--region-}
            routingAction=${routingAction//-/_}
            shift 2
            ;;
        --ipv6)
            [[ "$#" -ge 2 && -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$2" in selective|global) ipv6Mode=$2 ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            routingKind=ipv6 routingAction=enable
            shift 2
            ;;
        --ipv6-domains)
            [[ "$#" -ge 2 && "${ipv6DomainsSet}" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            if [[ -n "$2" ]]; then
                ipv6Domains=$(dockerSocks5DomainsNormalize "$2") || return "${PADM_DOCKER_RC_USAGE}"
            fi
            ipv6DomainsSet=1
            shift 2
            ;;
        --dns-off|--hosts-off|--direct-off|--block-off|--block-ips-off|--block-bt-off|--region-off|--ipv6-off|--warp-off|--access-control-off)
            [[ -z "${routingKind}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            routingKind=${1#--} routingKind=${routingKind%-off} routingAction=disable
            routingKind=${routingKind//-/_}
            shift
            ;;
        --alpn)
            [[ "$#" -ge 3 && -n "$2" && "$2" != --* && -z "${alpnListener}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            alpnListener=$2 alpnOrder=$3
            case "${alpnOrder}" in h2,http/1.1|http/1.1,h2|http/1.1) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            shift 3
            ;;
        --regenerate-reality)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${regenerateReality}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            regenerateReality=$2
            shift 2
            ;;
        --reality-target)
            [[ "$#" -ge 5 && -n "$2" && "$2" != --* && -z "${realityTarget}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            realityTarget=$2 targetHost=$3 targetPort=$4 targetSni=$5
            dockerDomainIsValid "${targetHost}" && dockerDomainIsValid "${targetSni}" &&
                [[ "${targetPort}" =~ ^[1-9][0-9]{0,4}$ && "${targetPort}" -le 65535 ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            shift 5
            ;;
        --reality-stream)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${realityStream}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "$2" == off ]]; then
                realityStream=off
                shift 2
            else
                [[ "$#" -ge 3 && -n "$3" && "$3" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
                realityStream=on streamListener=$2 streamWebsite=$3
                shift 3
            fi
            ;;
        --reality-stream-host)
            [[ "$#" -ge 5 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* &&
                -n "$4" && "$4" != --* && "$5" =~ ^[1-9][0-9]{0,4}$ && "$5" -le 65535 &&
                -z "${realityStream}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            realityStream=host streamListener=$2 streamDomains=$3 streamAddress=$4 streamPort=$5
            shift 5
            ;;
        --reality-stream-loopback)
            [[ "$#" -ge 5 && -n "$2" && "$2" != --* && -n "$3" && "$3" != --* &&
                ( "$4" == 127.0.0.1 || "$4" == ::1 ) &&
                "$5" =~ ^[1-9][0-9]{0,4}$ && "$5" -le 65535 && "$5" != 443 && "$5" != 15443 &&
                -z "${realityStream}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            realityStream=loopback streamListener=$2 streamDomains=$3 streamAddress=$4 streamPort=$5
            shift 5
            ;;
        --preview)
            [[ "${mode}" == interactive ]] || return "${PADM_DOCKER_RC_USAGE}"
            mode=preview
            shift
            ;;
        --confirm)
            [[ "${mode}" == interactive && "${2:-}" == PADM-DOCKER-EDIT ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            mode=confirmed
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ "${regionAllowSet}" -eq 0 || ( "${routingKind}" == region && "${routingAction}" == enable ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    [[ "${ipv6DomainsSet}" -eq 0 || ( "${routingKind}" == ipv6 && "${routingAction}" == enable ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    if [[ "${routingKind}" == ipv6 && "${routingAction}" == enable ]]; then
        [[ ( "${ipv6Mode}" == selective && "${ipv6Domains}" != '[]' ) ||
            ( "${ipv6Mode}" == global && "${ipv6Domains}" == '[]' ) ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
    fi
    [[ ( -z "${regenerateReality}" && -z "${realityTarget}" && -z "${realityStream}" ) || -z "${specFile}" ]] &&
        [[ -z "${regenerateReality}" || ( -z "${realityTarget}" && -z "${realityStream}" ) ]] &&
        [[ -z "${realityTarget}" || -z "${realityStream}" ]] || {
        dockerError 'Reality 专项编辑不能与规格导入或另一专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${siteMode}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" ) ]] || {
        dockerError '站点专项编辑不能与规格导入或 Reality 专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${alpnListener}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" ) ]] || {
        dockerError 'ALPN 专项编辑不能与规格导入、站点或 Reality 专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${http01}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" && -z "${alpnListener}" ) ]] || {
        dockerError 'HTTP-01 专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${socks5}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${routingKind}" ) ]] || {
        dockerError '路由专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${routingKind}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" ) ]] || {
        dockerError '路由专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${httpRelay}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" && -z "${routingKind}" ) ]] || {
        dockerError 'HTTP 中继专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${portAlias}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" ) ]] || {
        dockerError '额外入口端口专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${fail2banAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" ) ]] || {
        dockerError 'Fail2ban 专项动作不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${cdnAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" ) ]] || {
        dockerError 'CDN 地址专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${xhttpAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" ) ]] || {
        dockerError 'XHTTP 专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${portHoppingAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" && -z "${xhttpAction}" ) ]] || {
        dockerError '端口跳跃专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${tproxyFamily}" || "${tproxyAction}" == enable || "${tproxyAction}" == settings ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    [[ -z "${tproxyOutput}" || "${tproxyAction}" == settings ||
        ( "${tproxyAction}" == enable && "${tproxyOutput}" != off ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    [[ -z "${tproxyAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tunAction}" ) ]] || {
        dockerError '透明代理专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${tunAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tproxyAction}" ) ]] || {
        dockerError 'TUN 专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${protocolKind}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tproxyAction}" && -z "${tunAction}" ) ]] || {
        dockerError 'Hy2/TUIC 专项编辑不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${entryAction}" || ( -z "${specFile}" && -z "${regenerateReality}" &&
        -z "${realityTarget}" && -z "${realityStream}" && -z "${siteMode}" &&
        -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${fail2banAction}" && -z "${cdnAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tproxyAction}" && -z "${tunAction}" &&
        -z "${protocolKind}" ) ]] || {
        dockerError '协议入口专项不能与规格导入或其它专项动作组合'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ -n "${tlsMigrateDomain}" ]]; then
        [[ -n "${entryTlsMode}" &&
            -z "${specFile}" && -z "${entryAction}" && -z "${entryTlsDomain}" &&
            -z "${regenerateReality}${realityTarget}${realityStream}${siteMode}${alpnListener}" &&
            -z "${http01}${socks5}${routingKind}${httpRelay}${portAlias}${fail2banAction}" &&
            -z "${cdnAction}${xhttpAction}${portHoppingAction}${tproxyAction}${tunAction}${protocolKind}" ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
        dockerDomainIsValid "${tlsMigrateDomain}" || return "${PADM_DOCKER_RC_USAGE}"
        entryTlsDomain=${tlsMigrateDomain}
    fi
    [[ -z "${entryCore}" || "${entryAction}" == add ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    if [[ -n "${entryTlsDomain}${entryTlsMode}" && -z "${tlsMigrateDomain}" ]]; then
        [[ "${entryAction}" == add ]] || return "${PADM_DOCKER_RC_USAGE}"
        case "${entryProtocol}" in 1|2|26|30) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    [[ "${mode}" != interactive || ( -t 0 && -t 1 ) ]] || {
        dockerError '非交互编辑需要 --preview 或 --confirm PADM-DOCKER-EDIT'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ -z "${hy2ObfsType}" || "${hy2ObfsType}" == off || "${mode}" == interactive ||
        -n "${hy2ObfsFile}" ]] || {
        dockerError '非交互开启 Hy2 混淆需要 root 私密 JSON 密码文件'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${protocolKind}" == tuic ]] &&
        jq -e '.zero_rtt_handshake == true' <<<"${protocolPatch}" >/dev/null 2>&1; then
        printf '启用 TUIC 0-RTT 会增加重放攻击风险，默认关闭。\n'
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    [[ ( -z "${regenerateReality}" && -z "${realityTarget}" && -z "${realityStream}" &&
        -z "${siteMode}" && -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${cdnAction}" && -z "${fail2banAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tproxyAction}" && -z "${tunAction}" &&
        -z "${protocolKind}" && -z "${entryAction}" && -z "${tlsMigrateDomain}" ) ||
        -f "${root}/config/spec.json" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ ! -e "${root}/config/spec.json" && ! -L "${root}/config/spec.json" && -z "${specFile}" ]]; then
        if [[ "${mode}" == interactive ]]; then
            dockerSetupRead specFile '完整原始 spec 文件（0 取消）: ' || return 0
        else
            dockerError '缺少受管规格，请用 --spec 导入完整原始输入；不会从运行配置伪造规格'
            return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    workspace=$(mktemp -d "${root}/.edit.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${workspace}
    chmod 0700 "${workspace}" || return "${PADM_DOCKER_RC_STATE}"
    original="${workspace}/original.json"
    draft="${workspace}/draft.json"
    if [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        dockerResolveRegularFile "${root}/config/spec.json" >/dev/null &&
            [[ -O "${root}/config/spec.json" ]] &&
            dockerPrivateFileIsRestricted "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
        cp -- "${root}/config/spec.json" "${original}" || return "${PADM_DOCKER_RC_STATE}"
    else
        specFile=$(dockerResolveRegularFile "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
        cp -- "${specFile}" "${original}" || return "${PADM_DOCKER_RC_STATE}"
        imported=1
    fi
    chmod 0600 "${original}" || return "${PADM_DOCKER_RC_STATE}"
    normalized="${workspace}/normalized.json"
    dockerConfigureSpecMigrate "${original}" "${normalized}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ -n "${specFile}" && "${imported}" -eq 0 ]]; then
        specFile=$(dockerResolveRegularFile "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
        cp -- "${specFile}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    else
        cp -- "${normalized}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    fi
    chmod 0600 "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    jq -es 'length == 1 and (.[0] | type == "object")' "${draft}" >/dev/null 2>&1 ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ "${fail2banAction}" == enable || "${fail2banAction}" == settings ]]; then
        if { [[ "${fail2banType}" == fail2ban-ssh ]] &&
            jq -e 'any(.host_integrations[]; .type == "fail2ban-control")' "${draft}" >/dev/null; } ||
            { [[ "${fail2banType}" == fail2ban-control ]] &&
            jq -e 'any(.host_integrations[]; .type == "fail2ban-ssh")' "${draft}" >/dev/null; }; then
            dockerError 'SSH 与控制面 INPUT 防护暂不支持共存，未修改配置'
            return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    if jq -en --slurpfile before "${original}" --slurpfile after "${draft}" '
      any($before[0].host_integrations[]; .type == "fail2ban") and
      (([$before[0].core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) | .public_port] | sort) !=
       ([$after[0].core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) | .public_port] | sort))
    ' >/dev/null 2>&1; then
        dockerError '带 Fail2ban 的 WS 入口端口需联动封禁规则，本阶段未开放端口或入口数量修改'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${specFile}" && "${imported}" -eq 0 ]]; then
        dockerConfigureSpecMigrate "${draft}" "${draft}.v3" &&
            mv -f -- "${draft}.v3" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    fi
    # 旧规格先接入，不能同时把未经证明的字段改动当作无损导入。
    if [[ "${mode}" == interactive && -z "${specFile}" && "${imported}" -eq 0 &&
        -z "${regenerateReality}" && -z "${realityTarget}" && -z "${realityStream}" &&
        -z "${siteMode}" && -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" && -z "${httpRelay}" && -z "${portAlias}" &&
        -z "${cdnAction}" && -z "${fail2banAction}" && -z "${xhttpAction}" &&
        -z "${portHoppingAction}" && -z "${tproxyAction}" && -z "${tunAction}" &&
        -z "${protocolKind}" && -z "${entryAction}" && -z "${tlsMigrateDomain}" ]]; then
        dockerEditFields "${draft}" || status=$?
        if [[ "${status}" -eq 3 ]]; then
            printf '已取消配置编辑。\n'
            return 0
        elif [[ "${status}" -ne 0 ]]; then
            dockerError '编辑输入无效或草稿写入失败，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    jq -es 'length == 1 and (.[0] | type == "object")' "${draft}" >/dev/null 2>&1 ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ -n "${tlsMigrateDomain}" ]]; then
        case "${entryTlsMode}" in
        3)
            dockerEmailIsValid "${entryTlsEmail}" &&
                [[ "${entryTlsProvider}" =~ ^dns_[a-z0-9_]+$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            entryTlsCredentials=$(dockerResolveRegularFile "${entryTlsCredentials}") &&
                dockerRenewalCredentialsValidate "${entryTlsCredentials}" ||
                return "${PADM_DOCKER_RC_STATE}" ;;
        4) dockerEmailIsValid "${entryTlsEmail}" || return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        dockerEditTlsDomainChange "${draft}" "${tlsMigrateDomain}" "${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'TLS 域名迁移需要不同的已有 TLS 域名，且暂不支持宿主集成、共存、跳跃或控制角色'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${entryAction}" ]]; then
        jq -e --arg listener "${entryListener}" --arg action "${entryAction}" '
          (.schema_version == 3 or $action == "add") and
          ([.core.protocols[] | select(.listener_id == $listener)] | length) == 1
        ' "${normalized}" >/dev/null 2>&1 &&
            { [[ "${entryAction}" == add ]] ||
                jq -e '.schema_version == 3' "${original}" >/dev/null; } || {
            dockerError '协议新增需要受管规格和唯一入口 ID，删除与重建仍需要 v3 部署'
            return "${PADM_DOCKER_RC_STATE}"
        }
        if [[ "${entryAction}" == add ]]; then
            entryCore=${entryCore:-$(jq -er --arg listener "${entryListener}" '
              .core.protocols[] | select(.listener_id == $listener) | .core
            ' "${draft}")} || return "${PADM_DOCKER_RC_STATE}"
            if jq -e '.tls != null' "${normalized}" >/dev/null; then
                [[ -z "${entryTlsDomain}${entryTlsMode}" ]] || {
                    dockerError '已有 TLS 部署沿用原域名；证书更新请使用证书管理'
                    return "${PADM_DOCKER_RC_USAGE}"
                }
            else
                case "${entryProtocol}" in
                1|2|26|30) ;;
                *)
                    if [[ "${mode}" == interactive ]]; then
                        [[ -n "${entryTlsDomain}" ]] ||
                            dockerSetupRead entryTlsDomain '新增协议的 TLS 域名（0 取消）: ' || return 0
                        [[ -n "${entryTlsMode}" ]] ||
                            dockerSetupRead entryTlsMode '证书 [1=已有受管, 2=导入, 3=DNS-01, 4=HTTP-01 standalone, 0=取消]: ' 1 || return 0
                        case "${entryTlsMode}" in
                        1) ;;
                        2)
                            [[ -n "${entryTlsCert}" ]] ||
                                dockerSetupRead entryTlsCert '完整证书链文件（0 取消）: ' || return 0
                            [[ -n "${entryTlsKey}" ]] ||
                                dockerSetupRead entryTlsKey '私钥文件（0 取消）: ' || return 0 ;;
                        3)
                            [[ -n "${entryTlsEmail}" ]] ||
                                dockerSetupRead entryTlsEmail 'ACME 邮箱（0 取消）: ' || return 0
                            [[ -n "${entryTlsProvider}" ]] ||
                                dockerSetupRead entryTlsProvider 'DNS provider（dns_*，0 取消）: ' || return 0
                            [[ -n "${entryTlsCredentials}" ]] ||
                                dockerSetupRead entryTlsCredentials 'DNS 凭据文件（0 取消）: ' || return 0 ;;
                        4)
                            entryTlsProvider=standalone
                            [[ -n "${entryTlsEmail}" ]] ||
                                dockerSetupRead entryTlsEmail 'ACME 邮箱（0 取消）: ' || return 0 ;;
                        *) return "${PADM_DOCKER_RC_USAGE}" ;;
                        esac
                    fi
                    [[ -n "${entryTlsDomain}" && -n "${entryTlsMode}" ]] || {
                        dockerError '新增首个 TLS 协议需要 --tls-domain 和证书来源'
                        return "${PADM_DOCKER_RC_STATE}"
                    }
                    dockerDomainIsValid "${entryTlsDomain}" || return "${PADM_DOCKER_RC_USAGE}"
                    case "${entryTlsMode}" in
                    1|2) ;;
                    3)
                        dockerEmailIsValid "${entryTlsEmail}" &&
                            [[ "${entryTlsProvider}" =~ ^dns_[a-z0-9_]+$ ]] ||
                            return "${PADM_DOCKER_RC_USAGE}"
                        entryTlsCredentials=$(dockerResolveRegularFile "${entryTlsCredentials}") &&
                            dockerRenewalCredentialsValidate "${entryTlsCredentials}" || {
                            dockerError 'DNS 凭据必须为私密普通文件，内容须符合现有 ACME 环境变量约束'
                            return "${PADM_DOCKER_RC_STATE}"
                        } ;;
                    4)
                        dockerEmailIsValid "${entryTlsEmail}" || return "${PADM_DOCKER_RC_USAGE}"
                        printf 'HTTP-01 需要域名解析到本机且公网 80 可达；确认后临时使用宿主 80，冲突时不停止无关服务。\n' ;;
                    *) return "${PADM_DOCKER_RC_USAGE}" ;;
                    esac
                    ;;
                esac
            fi
            if [[ "${entryProtocol}" == 30 ]] && ! jq -e --arg listener "${entryListener}" '
              (.core.protocols[] | select(.listener_id == $listener) | .uuid) as $uuid |
              any(.core.protocols[]; .id == 30 and .uuid == $uuid)
            ' "${normalized}" >/dev/null; then
                entrySsGenerate=1
            fi
            dockerEditEntryAdd "${draft}" "${entryListener}" "${entryProtocol}" "${entryCore}" \
                "${entryPort}" protocol "${draft}.next" '' "${entryTlsDomain}" &&
                chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
                return "${PADM_DOCKER_RC_STATE}"
        elif [[ "${entryAction}" == remove ]]; then
            dockerEditEntryRemove "${draft}" "${entryListener}" "${draft}.next" &&
                chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
                return "${PADM_DOCKER_RC_STATE}"
        else
            printf '保留入口 %s 的完整参数和身份，重新生成部署；配置事务可能统一重建所有核心。\n' "${entryListener}"
        fi
    fi
    if [[ -n "${tproxyAction}" ]]; then
        jq --arg action "${tproxyAction}" --argjson port "${tproxyPort}" --argjson mark "${tproxyMark}" \
            --arg kind "${tproxyKind:-tproxy}" --arg family "${tproxyFamily}" --arg output "${tproxyOutput}" '
          [.host_integrations[] | select(.type == $kind)] as $current |
          ({port:$port} + (if $kind == "tproxy" then {mark:$mark} else {} end) +
            (if $family != "" then {family:$family}
            elif $action == "settings" and ($current[0].settings // {} | has("family")) then
              {family:$current[0].settings.family}
            else {} end) +
            (if $output == "off" then {}
             elif $output == "all" then {output_all:true}
             elif $output != "" then {output_uid:($output | tonumber)}
             elif $action == "settings" and $current[0].settings.output_all == true then
               {output_all:true}
             elif $action == "settings" and ($current[0].settings // {} | has("output_uid")) then
               {output_uid:$current[0].settings.output_uid}
             else {} end)) as $settings |
          if $action == "off" then
            if ($current | length) != 1 then error("透明代理未启用")
            else .host_integrations |= map(select(.type != $kind)) end
          else
            if .core.secondary_type != null or (.host_integrations | length) != ($current | length) or
              any(.core.protocols[]; .id != 1 and .id != 2 and .id != 26)
            then error("透明代理仅支持单核心 Reality，不能与其它宿主集成共存")
            elif $action == "enable" then
              if ($current | length) != 0 then error("透明代理已启用") else
                .host_integrations += [{type:$kind,profile:"net-transparent",
                  firewall_rules:["padm-" + $kind],devices:[],schedules:[],settings:$settings}]
              end
            elif ($current | length) != 1 or $current[0].settings == $settings
            then error("透明代理未启用或参数没有变化")
            else .host_integrations |= map(if .type == $kind then .settings = $settings else . end)
            end
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError '透明代理动作需要匹配当前状态和不同参数；仅支持单核心 Reality，不能与其它宿主集成共存'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${tunAction}" ]]; then
        jq --arg action "${tunAction}" '
          [.host_integrations[] | select(.type == "tun")] as $current |
          if $action == "off" then
            if ($current | length) != 1 then error("TUN 未启用")
            else .host_integrations |= map(select(.type != "tun")) end
          elif ($current | length) != 0 then error("TUN 已启用")
          else .host_integrations += [{type:"tun",profile:"net-transparent",
            firewall_rules:["sing-box-auto-redirect"],devices:["/dev/net/tun"],schedules:[],
            settings:{interface:"padm-tun",address:"198.18.0.1/30"}}] end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'TUN 动作需要匹配当前启用状态'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ "${fail2banAction}" == port ]]; then
        dockerFail2banSourcePlan "${draft}" >/dev/null || return "${PADM_DOCKER_RC_STATE}"
        jq --arg listener "${fail2banPortListener}" --argjson port "${fail2banNewPort}" '
          [.core.protocols[] | select(.id == 21)] as $entries |
          if (.host_integrations | length) != 1 or .host_integrations[0].type != "fail2ban" or
            (.host_integrations[0].settings.ports | length) != 1 or
            ($entries | length) != 1 or $entries[0].listener_id != $listener or
            .host_integrations[0].settings.ports != [$entries[0].public_port] or
            $entries[0].public_port == $port or
            (.port_aliases // [] | length) != 0 or .reality_stream != null
          then error("only one direct protected WS listener is supported")
          else
            .core.protocols |= map(if .listener_id == $listener then .public_port = $port else . end) |
            .host_integrations[0].settings.ports = [$port]
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError '端口联动仅支持一个直接受管 WS 21 入口、一个 Fail2ban 集成和一个保护端口，新端口必须不同；不支持别名、Reality 共存或其它宿主集成'
            return "${PADM_DOCKER_RC_STATE}"
        }
    elif [[ "${fail2banAction}" == off ]]; then
        jq -e --arg type "${fail2banType}" 'any(.host_integrations[]; .type == $type)' "${draft}" >/dev/null || {
            dockerError '当前规格未启用受管 Fail2ban 站点扫描防护'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --arg type "${fail2banType}" '.host_integrations |= map(select(.type != $type))' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ "${fail2banAction}" == enable ]]; then
        jq -e --arg type "${fail2banType}" 'all(.host_integrations[]; .type != $type)' "${draft}" >/dev/null || {
            dockerError '当前规格已启用受管 Fail2ban 站点扫描防护，不能重复启用'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --arg type "${fail2banType}" --arg ports "${fail2banPorts}" --argjson max_retry "${fail2banMaxRetry}" \
            --argjson find_time "${fail2banFindTime}" --argjson ban_time "${fail2banBanTime}" \
            --arg unit "${fail2banSshUnit}" --arg target "${fail2banSshTarget}" --arg port "${fail2banSshPort}" '
          ($ports | if . == "" then [] else split(",") | map(tonumber) end) as $ports |
          .host_integrations += [{
            type:$type, profile:("net-" + $type),
            firewall_rules:[if $type == "fail2ban" then "DOCKER-USER" else "INPUT" end],
            devices:[], schedules:[],
            settings:({max_retry:$max_retry,find_time:$find_time,ban_time:$ban_time} +
              if $type == "fail2ban" then {log_file:"access.log",ports:$ports}
              elif $type == "fail2ban-ssh" then {unit:$unit,target:$target,port:($port | tonumber)}
              else {} end)
          }]
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ "${fail2banAction}" == settings ]]; then
        jq -e --arg type "${fail2banType}" '([.host_integrations[] | select(.type == $type)] | length) == 1' \
            "${draft}" >/dev/null || {
            dockerError '当前规格未启用受管 Fail2ban 站点扫描防护，不能修改参数'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --arg type "${fail2banType}" --arg ports "${fail2banPorts}" --argjson max_retry "${fail2banMaxRetry}" \
            --argjson find_time "${fail2banFindTime}" --argjson ban_time "${fail2banBanTime}" \
            --arg unit "${fail2banSshUnit}" --arg target "${fail2banSshTarget}" --arg port "${fail2banSshPort}" '
          ($ports | if . == "" then [] else split(",") | map(tonumber) end) as $ports |
          .host_integrations |= map(
            if .type == $type then
              (if $type == "fail2ban" then .settings.ports = $ports else . end) |
              (if $type == "fail2ban-ssh" then
                .settings.unit = $unit | .settings.target = $target | .settings.port = ($port | tonumber)
               else . end) |
              .settings.max_retry = $max_retry |
              .settings.find_time = $find_time |
              .settings.ban_time = $ban_time
            else . end)
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${protocolKind}" ]]; then
        jq -e --arg listener "${protocolListener}" --argjson id "${protocolId}" '
          .schema_version == 3 and
          ([.core.protocols[] | select(.listener_id == $listener and .id == $id and .core == "sing-box")] | length) == 1
        ' "${draft}" >/dev/null 2>&1 || {
            dockerError 'Hy2/TUIC 管理只支持已有 v3 sing-box 协议 3/31 入口，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
        protocolPatchFile="${workspace}/protocol-patch.json"
        if [[ -n "${hy2ObfsType}" && "${hy2ObfsType}" != off ]]; then
            if [[ -n "${hy2ObfsFile}" ]]; then
                dockerEditPrivateInputCopy "${hy2ObfsFile}" "${workspace}/hy2-obfs.json" hy2_obfs || {
                    dockerError 'Hy2 混淆密码须为 root 0600 单链接私密 JSON 的唯一 password 字段，16..128 位字母/数字/_/-'
                    return "${PADM_DOCKER_RC_STATE}"
                }
            else
                dockerEditHy2PasswordRead hy2ObfsPassword "${draft}" "${protocolListener}" || {
                    status=$?
                    [[ "${status}" -ne 3 ]] || return 0
                    return "${PADM_DOCKER_RC_STATE}"
                }
                printf '%s' "${hy2ObfsPassword}" | jq -Rs '{password:.}' >"${workspace}/hy2-obfs.json" &&
                    chmod 0600 "${workspace}/hy2-obfs.json" || return "${PADM_DOCKER_RC_STATE}"
                hy2ObfsPassword=
            fi
            # 补丁仅经私密文件进入 jq；兼容门禁只使用公开字段键。
            jq --arg type "${hy2ObfsType}" '{obfs:{type:$type,password:.password}}' \
                "${workspace}/hy2-obfs.json" >"${protocolPatchFile}" ||
                return "${PADM_DOCKER_RC_STATE}"
        else
            printf '%s\n' "${protocolPatch}" >"${protocolPatchFile}" || return "${PADM_DOCKER_RC_STATE}"
        fi
        chmod 0600 "${protocolPatchFile}" || return "${PADM_DOCKER_RC_STATE}"
        if [[ "${protocolKind}" == hy2 ]] &&
            jq -e '.masquerade == "local"' "${protocolPatchFile}" >/dev/null; then
            jq -e --arg listener "${protocolListener}" '.site.mode == "static" and
              any(.core.protocols[]; .listener_id == $listener and .hy2.obfs == null)' \
                "${draft}" >/dev/null &&
                dockerSiteStateValidate "${original}" "${root}" || {
                dockerError 'local 需要已发布的受管静态网页及关闭混淆，不自动修改站点或其它参数'
                return "${PADM_DOCKER_RC_STATE}"
            }
        fi
        jq --arg kind "${protocolKind}" --arg listener "${protocolListener}" \
            --slurpfile patch "${protocolPatchFile}" '
          .core.protocols |= map(if .listener_id == $listener then .[$kind] += $patch[0] else . end)
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'Hy2/TUIC 管理只支持已有 v3 sing-box 协议 3/31 入口，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${xhttpAction}" ]]; then
        jq --arg listener "${xhttpListener}" --arg action "${xhttpAction}" \
            --arg preset "${xhttpPreset}" --argjson values "${xhttpValues}" --argjson padding "${xhttpPadding}" \
            --argjson noGrpc "${xhttpNoGrpc}" --argjson noSse "${xhttpNoSse}" --argjson limits "${xhttpLimits}" '
          if .schema_version != 3 or
            ([.core.protocols[] | select(.listener_id == $listener and .id == 2 and .core == "xray")] | length) != 1
          then error("入口不支持 XHTTP 管理")
          else .core.protocols |= map(if .listener_id == $listener then
            if $action == "clear" then del(.xhttp.xmux)
            elif $action == "xmux" then .xhttp.xmux = $values
            elif $action == "mode" or $action == "path-host" or $action == "advanced" or $action == "defaults"
              then .xhttp += $values
            elif $action == "padding" then .xhttp.xPaddingBytes = $padding
            elif $action == "padding-clear" then del(.xhttp.xPaddingBytes)
            elif $action == "headers" then .xhttp.noGRPCHeader = $noGrpc | .xhttp.noSSEHeader = $noSse
            elif $action == "headers-clear" then del(.xhttp.noGRPCHeader,.xhttp.noSSEHeader)
            elif $action == "limits" then .xhttp += $limits
            elif $action == "limits-clear" then
              del(.xhttp.scMaxEachPostBytes,.xhttp.scMinPostsIntervalMs,
                .xhttp.scMaxBufferedPosts,.xhttp.scStreamUpServerSecs)
            else
              .xhttp.mode = (if $preset == "compatible" then "packet-up"
                elif $preset == "stream" then "stream-up" else "auto" end) |
              .xhttp.xmux = {maxConcurrency:(if $preset == "single" then 1 else "16-32" end),
                hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000"}
            end
          else . end) end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'XHTTP 管理只支持已有 v3 Xray 协议 2 入口，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${cdnAction}" ]]; then
        jq --arg listener "${cdnListener}" --arg action "${cdnAction}" --arg addresses "${cdnAddresses}" '
          if ([.core.protocols[] | select(.listener_id == $listener and
            (.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25))] | length) != 1 then
            error("入口不支持 CDN 地址覆盖")
          elif $action == "clear" then
            if has("cdn_entries") then
              .cdn_entries |= map(select(.listener_id != $listener)) |
              if .cdn_entries == [] then del(.cdn_entries) else . end
            else . end
          else
            .cdn_entries = ((.cdn_entries // []) | map(select(.listener_id != $listener))) +
              [{listener_id:$listener,addresses:($addresses | split(","))}]
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'CDN 地址覆盖只支持已有协议 21/22/23/24/25 入口，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${portHoppingAction}" ]]; then
        # 专项只改持久规格，地址与支持范围统一交给完整规格校验。
        jq --arg action "${portHoppingAction}" --arg listener "${portHoppingListener}" \
            --argjson start "${portHoppingStart}" --argjson end "${portHoppingEnd}" \
            --arg ipv4 "${portHoppingIpv4}" --arg ipv6 "${portHoppingIpv6}" '
          if $action == "clear" then del(.port_hopping)
          else .port_hopping = {listener_id:$listener,range_start:$start,range_end:$end,
            ipv4:$ipv4,ipv6:$ipv6} end
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${portAlias}" ]]; then
        jq --arg listener "${portAliasListener}" --arg port "${portAliasPort}" \
            --arg old_port "${portAliasOldPort}" --arg action "${portAlias}" '
          ($port | if . == "base" then null else tonumber end) as $port |
          if any(.core.protocols[]; .listener_id == $listener) then .
          else error("入口 ID 不存在") end |
          if $action == "port-alias" then
            if any(.port_aliases[]?; .listener_id == $listener and .public_port == $port) then .
            else .port_aliases = ((.port_aliases // []) + [{listener_id:$listener,public_port:$port}]) end
          elif $action == "port-alias-remove" then
            if any(.port_aliases[]?; .listener_id == $listener and .public_port == $port) then
              .port_aliases |= map(select(.listener_id != $listener or .public_port != $port)) |
              if .port_aliases == [] then del(.port_aliases) else . end
            else error("额外端口不存在") end
          elif $action == "port-alias-replace" then
            ($old_port | tonumber) as $old |
            if $old != $port and any(.port_aliases[]?;
              .listener_id == $listener and .public_port == $old) then
              .port_aliases |= map(if .listener_id == $listener and .public_port == $old
                then .public_port = $port else . end)
            else error("旧额外端口不存在或端口没有变化") end
          else
            if $port == null or any(.port_aliases[]?; .listener_id == $listener and .public_port == $port) then
              if has("port_aliases") then
                .port_aliases |= map(if .listener_id == $listener then
                  del(.share_default) |
                  if .public_port == $port then .share_default = true else . end
                else . end)
              else . end
            else error("默认分享端口必须是该入口已有的额外端口") end
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError '额外入口端口不存在或候选写入失败，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ "${httpRelay}" == enable ]]; then
        dockerEditPrivateInputCopy "${httpRelayFile}" "${workspace}/http-relay.json" http_relay || {
            dockerError 'HTTP 中继输入须为 root 所有的 0600 单链接普通 JSON 文件，最多 64 KiB，祖先目录不得可写或含链接'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --slurpfile relay "${workspace}/http-relay.json" '.relay.http = $relay[0]' \
            "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ "${httpRelay}" == disable ]]; then
        jq 'del(.relay.http) | if .relay == {} then del(.relay) else . end' \
            "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ -n "${httpRelay}" ]]; then
        jq -e '.relay.http != null' "${draft}" >/dev/null || {
            dockerError '请先导入有效的 HTTP 中继配置，再修改端口或来源允许名单'
            return "${PADM_DOCKER_RC_STATE}"
        }
        if [[ "${httpRelay}" != port ]]; then
            # 输入先独立校验，合并或删除不能掩盖坏地址；保留字面值与次序。
            jq --argjson sources "${httpRelaySources}" '.relay.http.source_ips = $sources' \
                "${draft}" >"${workspace}/http-relay-input.json" &&
                chmod 0600 "${workspace}/http-relay-input.json" ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerConfigureSpecValidate "${workspace}/http-relay-input.json" || {
                dockerError 'HTTP 中继来源只接受 1–256 条合法字面 IPv4/IPv6 或 CIDR'
                return "${PADM_DOCKER_RC_USAGE}"
            }
        fi
        jq --arg action "${httpRelay}" --argjson port "${httpRelayPort}" \
            --argjson sources "${httpRelaySources}" '
          .relay.http as $old |
          if $action == "port" then .relay.http.port = $port
          elif $action == "sources" then .relay.http.source_ips = $sources
          elif $action == "sources-add" then
            .relay.http.source_ips = (reduce $sources[] as $rule ($old.source_ips;
              if index($rule) == null then . + [$rule] else . end))
          elif ($sources - $old.source_ips | length) != 0 then
            error("待删除来源必须全部存在于当前 HTTP 中继允许名单")
          else .relay.http.source_ips = ($old.source_ips - $sources) end |
          if (.relay.http.source_ips | length) < 1 then
            error("来源允许名单不能删空，请显式关闭 HTTP 中继")
          elif (.relay.http.source_ips | length) > 256 then
            error("合并后来源允许名单超过 256 项")
          elif .relay.http == $old then error("HTTP 中继配置没有变化")
          else . end
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError 'HTTP 中继端口或来源允许名单更新失败，未提交配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ "${socks5}" == enable ]]; then
        dockerEditPrivateInputCopy "${socks5File}" "${workspace}/socks5.json" socks5 || {
            dockerError 'SOCKS5 输入须为 root 所有的 0600 单链接普通 JSON 文件，最多 64 KiB，祖先目录不得可写或含链接'
            return "${PADM_DOCKER_RC_STATE}"
        }
        # 凭据仅从私有快照导入，不进入参数或配置预览。
        jq --slurpfile socks5 "${workspace}/socks5.json" '.routing.socks5 = $socks5[0]' \
            "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ "${socks5}" == disable ]]; then
        jq 'del(.routing.socks5) | if .routing == {} then del(.routing) else . end' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    elif [[ "${socks5}" == domains || "${socks5}" == global ]]; then
        jq -e '.routing.socks5 != null' "${draft}" >/dev/null || {
            dockerError '请先启用认证 SOCKS5 出站，再替换域名规则或恢复全局'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --arg action "${socks5}" --argjson domains "${socks5Domains:-[]}" '
          if $action == "global" then del(.routing.socks5.domains)
          else .routing.socks5.domains = $domains end
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${routingKind}" ]]; then
        if [[ "${routingAction}" == host_replace || "${routingAction}" == host_add ]]; then
            # 用临时完整规格复用精确域名与可路由字面地址校验，不扩展 hosts 合同。
            jq --arg host "${routingHost}" --arg ip "${routingNewIp}" \
                '.routing.hosts = {($host):$ip}' \
                "${draft}" >"${workspace}/hosts_input.json" &&
                chmod 0600 "${workspace}/hosts_input.json" ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerConfigureSpecValidate "${workspace}/hosts_input.json" || {
                dockerError 'hosts 单项管理只接受精确域名和单个可路由字面 IPv4/IPv6，未提交配置'
                return "${PADM_DOCKER_RC_USAGE}"
            }
            if [[ "${routingAction}" == host_add ]]; then
                jq -e --arg host "${routingHost}" '
                  ((.routing.hosts // {}) | has($host) | not) and
                  ((.routing.hosts // {}) | length < 256)
                ' "${draft}" >/dev/null || {
                    dockerError 'hosts 追加要求精确域名尚不存在且合并后不超过 256 项'
                    return "${PADM_DOCKER_RC_STATE}"
                }
            else
                jq -e --arg host "${routingHost}" '
                  .routing.hosts | type == "object" and has($host)
                ' "${draft}" >/dev/null || {
                    dockerError 'hosts 单项替换要求该精确域名已存在，不能新增映射或启用 hosts'
                    return "${PADM_DOCKER_RC_STATE}"
                }
            fi
        elif [[ "${routingAction}" == host_remove ]]; then
            dockerDomainIsValid "${routingHost}" || {
                dockerError 'hosts 删除只接受单个精确 FQDN，未提交配置'
                return "${PADM_DOCKER_RC_USAGE}"
            }
            jq -e --arg host "${routingHost}" '
              .routing.hosts | type == "object" and has($host)
            ' "${draft}" >/dev/null || {
                dockerError 'hosts 删除要求该精确域名已存在，不能操作未启用或缺失映射'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingAction}" == ips_resolve || "${routingAction}" == ips_literal ]]; then
            jq -e --arg action "${routingAction}" '
              (.routing.block_ips.ips | type == "array" and length > 0) and
              ((.routing.block_ips.resolve_domains == true) != ($action == "ips_resolve"))
            ' "${draft}" >/dev/null || {
                dockerError 'IP 阻断模式切换要求已有手工名单且模式有变化'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingAction}" == ips_replace ]]; then
            # 仅临时校验输入去重，同值留给状态检查；实际名单保留字面值和次序。
            jq --arg old "${routingOldIp}" --arg new "${routingNewIp}" \
                '.routing.block_ips = {ips:([$old,$new] | unique)}' \
                "${draft}" >"${workspace}/block_ips_input.json" &&
                chmod 0600 "${workspace}/block_ips_input.json" ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerConfigureSpecValidate "${workspace}/block_ips_input.json" || {
                dockerError 'IP/CIDR 单条替换只接受两个合法字面地址或前缀，未提交配置'
                return "${PADM_DOCKER_RC_USAGE}"
            }
            jq -e '.routing.block_ips.ips | type == "array" and length > 0' "${draft}" >/dev/null || {
                dockerError 'IP/CIDR 单条替换要求已有非空手工阻断名单，不能操作区域合成规则'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingAction}" == domains_replace ]]; then
            jq -e --arg kind "${routingKind}" --arg field "${routingDomainsField}" '
              (.routing[$kind][$field] | type == "array" and length > 0) and
              (if $kind == "warp" or $kind == "ipv6" then
                .routing[$kind].mode == "selective" else true end)
            ' "${draft}" >/dev/null || {
                if [[ "${routingKind}" == region ]]; then
                    dockerError '区域自定义直连例外单条替换要求已有非空自定义名单，不能操作固定默认例外'
                else
                    dockerError '域名单条替换要求已有非空名单；WARP/IPv6 还须已启用选择性分流'
                fi
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingAction}" == upstream ]]; then
            jq -e --arg kind "${routingKind}" --arg server "${routingServer}" \
                --argjson port "${routingPort}" '
              .routing[$kind] != null and
              (.routing[$kind].server != $server or .routing[$kind].port != $port)
            ' "${draft}" >/dev/null || {
                dockerError '上游编辑要求已启用对应的 DNS/SOCKS5 配置且地址或端口有变化'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingKind}" == socks5 ]]; then
            jq -e '.routing.socks5.domains | type == "array" and length > 0' "${draft}" >/dev/null || {
                dockerError 'SOCKS5 域名增删要求已有非空选择性名单，未启用或全局模式不支持'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ "${routingKind}" == dns &&
            ( "${routingAction}" == domains_add || "${routingAction}" == domains_remove ) ]]; then
            jq -e '.routing.dns != null' "${draft}" >/dev/null || {
                dockerError '请先启用有效的 DNS 分流，再增删域名规则'
                return "${PADM_DOCKER_RC_STATE}"
            }
        elif [[ ( "${routingKind}" == warp || "${routingKind}" == ipv6 ) &&
            ( "${routingAction}" == domains_add || "${routingAction}" == domains_remove ) ]]; then
            # 增量管理仅操作已有选择性名单；删空由共享分支关闭对应策略。
            jq -e --arg kind "${routingKind}" '.routing[$kind].mode == "selective"' "${draft}" >/dev/null || {
                dockerError 'WARP/IPv6 域名增删要求已启用对应的选择性分流，未启用或全局模式不支持'
                return "${PADM_DOCKER_RC_STATE}"
            }
        fi
        if [[ "${routingKind}" == access_control ]]; then
            # 一次候选移除访问控制，保留独立的 BT 与出站、解析配置。
            jq '
              if .routing.direct != null or .routing.block != null or
                .routing.block_ips != null or .routing.region != null then
                del(.routing.direct,.routing.block,.routing.block_ips,.routing.region) |
                if .routing == {} then del(.routing) else . end
              else error("当前未启用可移除的访问控制，未提交配置") end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == warp && "${routingAction}" == warp_* ]]; then
            jq -e '.routing.warp != null' "${draft}" >/dev/null || {
                dockerError '请先导入有效的 WARP 配置，再修改域名、全局模式或地址族'
                return "${PADM_DOCKER_RC_STATE}"
            }
            # 日常编辑只改选择策略，账号、隧道地址与保留字节沿用原私有输入。
            jq --arg action "${routingAction}" --arg family "${warpFamily}" \
                --argjson domains "${routingDomains}" '
              if $action == "warp_family" then .routing.warp.family = $family
              elif $action == "warp_global" then .routing.warp.mode = "global" | .routing.warp.domains = []
              else .routing.warp.mode = "selective" | .routing.warp.domains = $domains end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == block_bt && "${routingAction}" == enable ]]; then
            jq '.routing.block_bt = true' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == ips_resolve || "${routingAction}" == ips_literal ]]; then
            jq --arg action "${routingAction}" '
              if $action == "ips_resolve" then .routing.block_ips.resolve_domains = true
              else del(.routing.block_ips.resolve_domains) end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == region && "${routingAction}" == enable ]]; then
            jq --arg mode "${regionMode}" --argjson allow "${regionAllow}" \
                '.routing.region = {mode:$mode,allow_domains:$allow}' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == region && "${routingAction}" == mode ]]; then
            jq -e --arg mode "${regionMode}" \
                '.routing.region != null and .routing.region.mode != $mode' "${draft}" >/dev/null || {
                dockerError '区域模式切换要求已有区域策略且新模式不同；自定义例外保持'
                return "${PADM_DOCKER_RC_STATE}"
            }
            jq --arg mode "${regionMode}" '.routing.region.mode = $mode' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == region && "${routingAction}" == allow_* ]]; then
            jq -e '.routing.region != null' "${draft}" >/dev/null || {
                dockerError '请先启用区域策略，再增删自定义直连例外'
                return "${PADM_DOCKER_RC_STATE}"
            }
            # 只操作自定义名单，默认例外由生成器保持，删空后仍保留区域模式。
            jq --arg action "${routingAction}" --argjson domains "${routingDomains}" '
              .routing.region.allow_domains as $existing |
              if $action == "allow_add" then
                (reduce $domains[] as $rule ($existing;
                  if index($rule) == null then . + [$rule] else . end)) as $merged |
                if ($merged | length) <= 256 then .routing.region.allow_domains = $merged
                else error("自定义直连例外合并后超过 256 项，未提交配置") end
              elif ($domains - $existing | length) != 0 then
                error("待删除规则必须全部存在于区域自定义直连例外，未提交配置")
              else .routing.region.allow_domains = ($existing - $domains) end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingKind}" == ipv6 && "${routingAction}" == enable ]]; then
            jq --arg mode "${ipv6Mode}" --argjson domains "${ipv6Domains}" \
                '.routing.ipv6 = {mode:$mode,domains:$domains}' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == host_replace ]]; then
            jq --arg host "${routingHost}" --arg ip "${routingNewIp}" '
              if .routing.hosts[$host] == $ip then
                error("hosts 新地址不能与当前地址相同，未提交配置")
              else .routing.hosts[$host] = $ip end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == host_add ]]; then
            jq --arg host "${routingHost}" --arg ip "${routingNewIp}" \
                '.routing.hosts = ((.routing.hosts // {}) + {($host):$ip})' \
                "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == host_remove ]]; then
            jq --arg host "${routingHost}" '
              del(.routing.hosts[$host]) |
              if .routing.hosts == {} then del(.routing.hosts) else . end |
              if .routing == {} then del(.routing) else . end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == domains_replace ]]; then
            jq --arg kind "${routingKind}" --arg field "${routingDomainsField}" --argjson old "${routingOldDomains}" \
                --argjson domains "${routingDomains}" '
              .routing[$kind][$field] as $existing |
              if ($existing | map(select(. == $old[0])) | length) != 1 then
                error("待替换旧规则必须恰好存在于当前所选手工域名名单一次，未提交配置")
              elif ($existing | index($domains[0])) != null then
                error("新规则不能与当前所选手工域名名单中的规则重复，未提交配置")
              else .routing[$kind][$field] =
                ($existing | map(if . == $old[0] then $domains[0] else . end)) end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == domains_add ]]; then
            jq --arg kind "${routingKind}" --argjson domains "${routingDomains}" '
              (reduce $domains[] as $rule ((.routing[$kind].domains // []);
                if index($rule) == null then . + [$rule] else . end)) as $merged |
              if ($merged | length) <= 256 then .routing[$kind].domains = $merged
              else error("合并后域名规则超过 256 项，未提交配置") end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == domains_remove ]]; then
            jq --arg kind "${routingKind}" --argjson domains "${routingDomains}" '
              (.routing[$kind].domains // []) as $existing |
              if ($domains - $existing | length) != 0 then
                error("待删除规则必须全部存在于当前所选手工域名名单，未提交配置")
              else
                .routing[$kind].domains = ($existing - $domains) |
                if .routing[$kind].domains == [] then del(.routing[$kind]) else . end |
                if .routing == {} then del(.routing) else . end
              end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == ips_replace ]]; then
            jq --arg old "${routingOldIp}" --arg new "${routingNewIp}" '
              .routing.block_ips.ips as $existing |
              if ($existing | map(select(. == $old)) | length) != 1 then
                error("待替换旧 IP/CIDR 必须恰好存在于当前手工阻断名单一次，未提交配置")
              elif ($existing | index($new)) != null then
                error("新 IP/CIDR 不能与当前手工阻断名单中的规则重复，未提交配置")
              else .routing.block_ips.ips =
                ($existing | map(if . == $old then $new else . end)) end
            ' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == ips_add || "${routingAction}" == ips_remove ]]; then
            dockerEditPrivateInputCopy "${routingFile}" "${workspace}/block_ips.json" block_ips || {
                dockerError 'IP/CIDR 增量输入须为 root 所有的 0600 单链接普通 JSON 文件，最多 64 KiB，且必须是合法 block_ips 规格'
                return "${PADM_DOCKER_RC_STATE}"
            }
            # 先把增量输入放入临时完整规格，复用统一 schema 检查，避免合并时吞掉坏值。
            jq --slurpfile input "${workspace}/block_ips.json" \
                '.routing.block_ips = $input[0]' "${draft}" >"${workspace}/block_ips_input.json" 2>/dev/null &&
                chmod 0600 "${workspace}/block_ips_input.json" &&
                dockerConfigureSpecValidate "${workspace}/block_ips_input.json" || {
                dockerError 'IP/CIDR 增量输入不符合现有 block_ips 合同，未提交配置'
                return "${PADM_DOCKER_RC_STATE}"
            }
            if [[ "${routingAction}" == ips_add ]]; then
                jq --slurpfile input "${workspace}/block_ips.json" '
                  (.routing.block_ips.ips // []) as $existing |
                  (reduce $input[0].ips[] as $rule ($existing;
                    if index($rule) == null then . + [$rule] else . end)) as $merged |
                  if ($merged | length) <= 256 then
                    .routing.block_ips.ips = $merged
                  else error("合并后 IP/CIDR 阻断规则超过 256 项，未提交配置") end
                ' "${draft}" >"${draft}.next"
            else
                jq --slurpfile input "${workspace}/block_ips.json" '
                  (.routing.block_ips.ips // []) as $existing |
                  if (($input[0].ips - $existing) | length) != 0 then
                    error("待删除 IP/CIDR 规则必须全部存在于当前阻断名单，未提交配置")
                  else
                    ($existing - $input[0].ips) as $remaining |
                    if ($remaining | length) == 0 then
                      del(.routing.block_ips) |
                      if .routing == {} then del(.routing) else . end
                    else
                      .routing.block_ips.ips = $remaining
                    end
                  end
                ' "${draft}" >"${draft}.next"
            fi
        elif [[ "${routingAction}" == domains ]]; then
            jq --arg kind "${routingKind}" --argjson domains "${routingDomains}" \
                '.routing[$kind].domains = $domains' "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == upstream ]]; then
            jq --arg kind "${routingKind}" --arg server "${routingServer}" --argjson port "${routingPort}" \
                '.routing[$kind].server = $server | .routing[$kind].port = $port' \
                "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == rules ]]; then
            jq --arg server "${routingServer}" --argjson port "${routingPort}" \
                --argjson domains "${routingDomains}" \
                '.routing.dns = {server:$server,port:$port,domains:$domains}' \
                "${draft}" >"${draft}.next"
        elif [[ "${routingAction}" == enable ]]; then
            dockerEditPrivateInputCopy "${routingFile}" "${workspace}/${routingKind}.json" "${routingKind}" || {
                dockerError '路由输入须为 root 所有的 0600 单链接普通 JSON 文件，最多 64 KiB，祖先目录不得可写或含链接'
                return "${PADM_DOCKER_RC_STATE}"
            }
            jq --arg kind "${routingKind}" --slurpfile input "${workspace}/${routingKind}.json" \
                '.routing[$kind] = ($input[0] +
                  if $kind == "block_ips" and .routing.block_ips.resolve_domains == true then
                    {resolve_domains:true} else {} end)' "${draft}" >"${draft}.next" 2>/dev/null
        else
            jq --arg kind "${routingKind}" 'del(.routing[$kind]) |
              if .routing == {} then del(.routing) else . end' "${draft}" >"${draft}.next"
        fi &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${http01}" ]]; then
        jq -e 'any(.core.protocols[];
          .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29)' \
            "${normalized}" >/dev/null || {
            dockerError 'HTTP-01 入口管理需要已有受管 Nginx TLS 或 fallback 入口'
            return "${PADM_DOCKER_RC_STATE}"
        }
        jq --arg action "${http01}" '
          if $action == "enable" then .tls.http01 = true else del(.tls.http01) end
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${alpnListener}" ]]; then
        jq --arg listener "${alpnListener}" --arg order "${alpnOrder}" '
          .core.protocols |= map(if .listener_id == $listener then
            .fallback_tls.alpn = ($order | split(",")) else . end)
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -n "${siteMode}" ]]; then
        if [[ -n "${siteTemplate}" ]]; then
            dockerSiteTemplateInputsValidate "${original}" "${siteTemplate}" "$(dockerCurrentBundlePath)" ||
                return "${PADM_DOCKER_RC_STATE}"
        fi
        [[ -z "${siteSource}" ]] ||
            siteSource=$(dockerSiteSourceValidate "${siteSource}") || return "${PADM_DOCKER_RC_STATE}"
        jq --arg mode "${siteMode}" --arg url "${siteUrl}" '
          .site = if $mode == "redirect" then {mode:$mode, url:$url} else {mode:$mode} end
        ' "${draft}" >"${draft}.next" &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    jq -en --arg mode "${siteMode}" --slurpfile before "${normalized}" --slurpfile after "${draft}" '
      if $mode != "" or $before[0].site != $after[0].site then
        any($before[0].core.protocols[];
          .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29 or
          (.id == 3 and .core == "sing-box" and
            ($mode == "static" or ($mode == "" and $after[0].site == null and
              all($after[0].core.protocols[];
                .id != 3 and .id != 21 and .id != 22 and .id != 23 and .id != 24 and
                .id != 25 and .id != 27 and .id != 29)))))
      else true end
    ' >/dev/null 2>&1 || {
        dockerError '站点管理需要已有 Nginx TLS/fallback 入口；Hysteria2 仅支持受管静态网页'
        return "${PADM_DOCKER_RC_STATE}"
    }
    if [[ -n "${realityStream}" ]]; then
        jq --arg action "${realityStream}" --arg listener "${streamListener}" --arg website "${streamWebsite}" \
            --arg domains "${streamDomains}" --arg address "${streamAddress}" --argjson port "${streamPort}" '
          if $action == "off" then del(.reality_stream) else
            [.core.protocols[] | select(.listener_id == $listener and .core == "xray" and (.id == 1 or .id == 2))] as $realities |
            if ($realities | length) != 1 then error("共存需要唯一 Xray Reality Vision/XHTTP 入口")
            elif $action == "host" or $action == "loopback" then
              .reality_stream = {listener_id:$listener, host_website:{
                domains:($domains | split(",") | map(gsub("^\\s+|\\s+$"; "") | ascii_downcase) | map(select(. != ""))),
                address:$address, port:$port}} |
              if $action == "loopback" then .reality_stream.host_website.network_mode = "host" else . end
            else
              [.core.protocols[] | select(.listener_id == $website and
                (.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25))] as $websites |
              if ($websites | length) != 1 then error("共存需要唯一 TLS 入口")
              else .reality_stream = {listener_id:$listener, website_listener_id:$website} end
            end
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError '共存需要指定已有 Xray Reality Vision/XHTTP 入口与有效网站输入'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${realityTarget}" ]]; then
        jq --arg listener "${realityTarget}" --arg host "${targetHost}" --argjson port "${targetPort}" \
            --arg sni "${targetSni}" '
          [.core.protocols[] | select(.listener_id == $listener and (.id == 1 or .id == 2 or .id == 26))] as $selected |
          if ($selected | length) != 1 then error("不是唯一 Reality 入口") else
            .core.protocols |= map(if .listener_id == $listener then
              .reality.target_host = $host | .reality.target_port = $port | .reality.server_name = $sni
            else . end)
          end
        ' "${draft}" >"${draft}.next" 2>/dev/null &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" || {
            dockerError '目标站设置需要指定一个已有 Reality 入口 ID'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    # 删除最后一个 Nginx 入口时只清理 HTTP-01 开关，不丢掉其它 TLS 入口的域名。
    jq --slurpfile before "${normalized}" 'if $before[0].tls.http01 == true and
      all(.core.protocols[];
        .id != 21 and .id != 22 and .id != 23 and .id != 24 and .id != 25 and .id != 27 and .id != 29)
      then del(.tls.http01) else . end' "${draft}" >"${draft}.next" &&
        chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerConfigureSpecValidate "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${fail2banType}" == fail2ban &&
        ( "${fail2banAction}" == enable || "${fail2banAction}" == settings || "${fail2banAction}" == port ) ]]; then
        dockerFail2banSourcePlan "${draft}" >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerAcmeWebrootTransitionValidate "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ -n "${regenerateReality}" ]]; then
        regenerateReality=$(jq -er --arg listener "${regenerateReality}" '
          [.core.protocols[] | select(.listener_id == $listener and (.id == 1 or .id == 2 or .id == 26))] |
          if length == 1 then .[0].listener_id else error("不是唯一 Reality 入口") end
        ' "${draft}" 2>/dev/null) || {
            dockerError 'Reality 参数重生成需要指定一个已有 Reality 入口 ID'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    # 取消与非法草稿先结束；合法输入仍须先核对在线基线，再准备发布或生成凭据。
    dockerEditCompatibilityValidate "${normalized}" "${draft}" || return $?
    dockerEditBaselineValidate "${original}" "${workspace}" "${alpnListener}" ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ -z "${manifest}" ]]; then
        version=$(jq -r '.release.version' "${original}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return "${PADM_DOCKER_RC_STATE}"
        # 编辑验证当前部署版本，不被 latest 的新发布隐式升级或阻断。
        manifest="${PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT%/latest/download/release-manifest.json}/download/v${version}/release-manifest.json"
    fi
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" "${siteTemplate}" || return $?
    if [[ -n "${siteTemplate}" ]]; then
        dockerSiteTemplateInputsValidate "${draft}" "${siteTemplate}" "${DOCKER_STAGED_BUNDLE_PATH:-}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerConfigureReleaseValidate "${draft}" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ "${entrySsGenerate}" == 1 ]]; then
        entrySsImage=$(dockerManifestImageReference sing-box) || return "${PADM_DOCKER_RC_MANIFEST}"
        entrySsCredentials="${workspace}/entry-ss.json"
        # 两份秘密只经候选内的 0600 文件进入 jq，兼容复验固定复用同一份输入。
        for entrySsAttempt in {1..32}; do
            entrySsServer=$(dockerSetupTool "${entrySsImage}" generate rand --base64 16 2>/dev/null) &&
                entrySsUser=$(dockerSetupTool "${entrySsImage}" generate rand --base64 16 2>/dev/null) || {
                dockerError 'Shadowsocks 密钥生成失败，未改写已安装配置'
                return "${PADM_DOCKER_RC_STATE}"
            }
            [[ "${entrySsServer}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ &&
                "${entrySsUser}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ ]] || {
                dockerError 'Shadowsocks 密钥格式无效，未改写已安装配置'
                return "${PADM_DOCKER_RC_STATE}"
            }
            (
                umask 077
                printf '%s\n%s\n' "${entrySsServer}" "${entrySsUser}" |
                    jq -Rs 'split("\n") | {server_password:.[0],user_password:.[1]}' >"${entrySsCredentials}"
            ) || return "${PADM_DOCKER_RC_STATE}"
            entrySsServer= entrySsUser=
            if dockerEditEntryAdd "${normalized}" "${entryListener}" "${entryProtocol}" "${entryCore}" \
                "${entryPort}" protocol "${draft}.next" "${entrySsCredentials}"; then
                entrySsReady=1
                break
            fi
        done
        [[ "${entrySsReady}" == 1 ]] &&
            chmod 0600 "${draft}.next" && mv -f -- "${draft}.next" "${draft}" &&
            dockerConfigureSpecValidate "${draft}" || {
            dockerError 'Shadowsocks 密钥冲突或候选校验失败，未改写已安装配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    if [[ -n "${regenerateReality}" ]]; then
        dockerEditRegenerateReality "${draft}" "${regenerateReality}" &&
            dockerConfigureSpecValidate "${draft}" || {
            dockerError 'Reality 参数生成或校验失败，未改写已安装配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
        printf '仅重生成入口 %s 的 Reality 密钥及 short ID；提交后需重新导入该入口链接。\n' "${regenerateReality}"
    fi
    dockerEditPreview "${original}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    # 发布准备、重生成与预览之后再冻结草稿，保留提交前的最后一道兼容门禁。
    dockerEditCompatibilityValidate "${normalized}" "${draft}" || return $?
    [[ -z "${alpnListener}" ]] ||
        printf '入口 %s 的 TLS ALPN 将设为 %s；仅允许该 ALPN 字段漂移，其它配置须与规格一致。\n' "${alpnListener}" "${alpnOrder}"
    [[ -z "${siteSource}" ]] || printf '静态站点内容将使用已校验目录更新；源路径不会写入规格。\n'
    [[ -z "${siteTemplate}" ]] || printf '静态站点内容将使用受管 %s 内置模板更新；主题不写入规格。\n' "${siteTemplate}"
    [[ "${imported}" -eq 0 ]] || printf '完整原始规格已匹配，确认后接入受管输入。\n'
    opsImage=$(dockerManifestImageReference ops) || return "${PADM_DOCKER_RC_MANIFEST}"
    while IFS=$'\t' read -r privateKey publicKey; do
        [[ -n "${privateKey}" ]] || continue
        derivedKey=$(printf '%s\n' "${privateKey}" | dockerSetupRealityPublicKey "${opsImage}") || derivedKey=
        [[ "${derivedKey}" == "${publicKey}" ]] || {
            dockerError 'Reality 公私钥不匹配，拒绝提交'
            return "${PADM_DOCKER_RC_STATE}"
        }
    done < <(jq -r '.core.protocols[] | select(.id == 1 or .id == 2 or .id == 26) |
      [.reality.private_key, .reality.public_key] | @tsv' "${draft}")
    if [[ -n "${entryTlsMode}" ]]; then
        if [[ -n "${tlsMigrateDomain}" ]]; then
            printf 'TLS 域名迁移至 %s，证书方式: %s；保留账号、分享 token 和累计，客户端需重新导入链接；自动续期登记须另行管理。\n' \
                "${entryTlsDomain}" "${entryTlsMode}"
        else
            printf '新增 TLS 域名: %s，证书方式: %s；保留已有入口、账号授权和订阅状态。\n' \
                "${entryTlsDomain}" "${entryTlsMode}"
        fi
        if [[ "${entryTlsMode}" == 3 || "${entryTlsMode}" == 4 ]]; then
            # 申请前先完成无证书即可验证的门禁；预览和取消不触发 CA 或暂停服务。
            dockerControlRecoveryCheck &&
                dockerControlSyncTransitionValidate "${draft}" &&
                dockerControlSyncScheduleSpecCheck "${draft}" &&
                dockerControlTransitionValidate "${draft}" &&
                dockerRealityTargetsValidate "${draft}" &&
                dockerHostIntegrationInputsValidate "${draft}" ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerTrafficRuntimeCheck "$(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${draft}")" ||
                return "${PADM_DOCKER_RC_HOST}"
            dockerConfigurePortsAvailable "${draft}" || return "${PADM_DOCKER_RC_CONFLICT}"
            [[ "${entryTlsMode}" != 4 ]] ||
                printf 'HTTP-01 需要域名解析到本机且公网 80 可达；确认后临时使用宿主 80，冲突时不停止无关服务。\n'
            if [[ "${mode}" == preview ]]; then
                if [[ -n "${tlsMigrateDomain}" ]]; then
                    printf 'TLS 域名迁移计划已校验；预览未申请证书或提交，证书及完整候选将在确认后验证。\n'
                else
                    printf '新增协议计划已校验；预览未申请证书或提交，证书及完整候选将在确认后验证。\n'
                fi
                return 0
            fi
            if [[ "${mode}" == interactive ]]; then
                dockerSetupRead answer '确认申请证书并在完整候选验证后提交？[y/N]: ' n || answer=n
                case "${answer}" in
                y|Y|yes|YES) mode=confirmed ;;
                *) printf '已取消配置编辑。\n'; return 0 ;;
                esac
            fi
        fi
        entryTlsSource="${workspace}/certificate"
        mkdir -m 0700 "${entryTlsSource}" &&
            dockerSetupStageCertificate "${entryTlsSource}" "${entryTlsMode}" "${entryTlsDomain}" \
                "${entryTlsCert}" "${entryTlsKey}" "${entryTlsEmail}" \
                "${entryTlsProvider}" "${entryTlsCredentials}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    DOCKER_CONFIG_RESTORE_ALPN_LISTENER=${alpnListener}
    dockerConfigureApply "${draft}" "${entryTlsSource:+${entryTlsSource}/tls}" \
        "${entryTlsSource:+${entryTlsSource}/acme}" "${mode}" '' "${siteSource}" "${siteTemplate}"
}

dockerEditCompatibilityValidate() {
    local editBefore=$1 editAfter=$2
    if [[ -n "${tlsMigrateDomain:-}" ]]; then
        # 固定新域名从原规格重算全量结果，不允许把额外漂移混入迁移。
        dockerEditTlsDomainChange "${editBefore}" "${tlsMigrateDomain}" "${editAfter}.expected" &&
            chmod 0600 "${editAfter}.expected" &&
            jq -e --slurpfile expected "${editAfter}.expected" '. == $expected[0]' \
                "${editAfter}" >/dev/null 2>&1 || {
            dockerError 'TLS 域名迁移仅允许本次域名及关联地址变更，其它完整规格必须保持'
            return "${PADM_DOCKER_RC_STATE}"
        }
        return 0
    fi
    if [[ "${entryAction:-}" == add || "${entryAction:-}" == rebuild ]]; then
        jq -en --slurpfile before "${editBefore}" --slurpfile after "${editAfter}" '
          $before[0].release == $after[0].release and $before[0].images == $after[0].images
        ' >/dev/null 2>&1 || return "${PADM_DOCKER_RC_MANIFEST}"
        if [[ "${entryAction}" == add ]]; then
            # 从原规格再生成唯一允许的追加结果，不能用豁免字段放行其它入口或根字段漂移。
            dockerEditEntryAdd "${editBefore}" "${entryListener}" "${entryProtocol}" "${entryCore}" \
                "${entryPort}" protocol "${editAfter}.expected" "${entrySsCredentials:-}" "${entryTlsDomain:-}" &&
                chmod 0600 "${editAfter}.expected" &&
                jq -e --slurpfile expected "${editAfter}.expected" '. == $expected[0]' \
                    "${editAfter}" >/dev/null 2>&1 || {
                dockerError '协议新增仅允许追加本次生成的一个入口，其它规格必须完整保持'
                return "${PADM_DOCKER_RC_STATE}"
            }
        else
            jq -en --slurpfile before "${editBefore}" --slurpfile after "${editAfter}" '
              $before[0] == $after[0]
            ' >/dev/null 2>&1 || {
                dockerError '协议重建必须保留完整规格、账号、身份和参数'
                return "${PADM_DOCKER_RC_STATE}"
            }
        fi
        return 0
    fi
    # 专项上下文沿用调用者的 Bash 局部变量；普通编辑与独立合同使用空默认值。
    jq -en --arg regenerate "${regenerateReality:-}" --arg target "${realityTarget:-}" --arg stream "${realityStream:-}" \
        --arg site "${siteMode:-}" --arg alpn "${alpnListener:-}" --arg http01 "${http01:-}" \
        --arg socks5 "${socks5:-}" --arg routing_kind "${routingKind:-}" \
        --arg routing_action "${routingAction:-}" --arg routing_domains_field "${routingDomainsField:-domains}" \
        --arg routing_host "${routingHost:-}" --arg routing_ip "${routingNewIp:-}" \
        --arg http_relay "${httpRelay:-}" \
        --arg tproxy_action "${tproxyAction:-}" \
        --arg tproxy_kind "${tproxyKind:-tproxy}" \
        --arg tun_action "${tunAction:-}" \
        --arg port_alias "${portAlias:-}" \
        --arg alias_listener "${portAliasListener:-}" --arg alias_port "${portAliasPort:-}" \
        --arg alias_old_port "${portAliasOldPort:-}" \
        --arg port_hopping "${portHoppingAction:-}" \
        --arg cdn_listener "${cdnListener:-}" \
        --arg xhttp_listener "${xhttpListener:-}" --arg xhttp_action "${xhttpAction:-}" \
        --arg protocol_kind "${protocolKind:-}" --arg protocol_listener "${protocolListener:-}" \
        --argjson protocol_patch "${protocolPatch:-"{}"}" \
        --arg fail2ban_action "${fail2banAction:-}" \
        --arg fail2ban_type "${fail2banType:-fail2ban}" \
        --arg fail2ban_listener "${fail2banPortListener:-}" \
        --slurpfile before "${editBefore}" --slurpfile after "${editAfter}" '
      def fixed: del(.server, .public_port, .address_families, .name,
        .reality.target_host, .reality.target_port, .reality.server_name, .websocket.path, .httpupgrade.path,
        .xhttp.path, .xhttp.host, .xhttp.mode, .grpc.service_name, .grpc_tls.service_name,
        .hy2.bandwidth_mode, .hy2.up_mbps, .hy2.down_mbps, .hy2.obfs, .hy2.masquerade,
        .tuic.congestion_control, .tuic.auth_timeout, .tuic.heartbeat, .tuic.zero_rtt_handshake) |
        if .listener_id == $regenerate then del(.reality.private_key, .reality.public_key, .reality.short_id) else . end;
      def reality: .id == 1 or .id == 2 or .id == 26;
      def shared: fixed | del(.listener_id, .core, .id, .xhttp, .grpc);
      def root: del(.core.protocols, .core.secondary_type, .tls, .subscription.enabled, .site);
      def without_fail2ban:
        .host_integrations |= map(select(.type != $fail2ban_type));
      def without_fail2ban_settings:
        .host_integrations |= map(if .type == $fail2ban_type then
          del(.settings.ports, .settings.max_retry, .settings.find_time, .settings.ban_time) |
          if $fail2ban_type == "fail2ban-ssh" then del(.settings.unit, .settings.target, .settings.port) else . end
          else . end);
      def without_cdn:
        if has("cdn_entries") then
          .cdn_entries |= map(select(.listener_id != $cdn_listener)) |
          if .cdn_entries == [] then del(.cdn_entries) else . end
        else . end;
      def special: .core.protocols |= map(
        if $regenerate != "" and .listener_id == $regenerate then
          del(.reality.private_key, .reality.public_key, .reality.short_id)
        elif $target != "" and .listener_id == $target then
          del(.reality.target_host, .reality.target_port, .reality.server_name)
        else . end);
      $before[0] as $old | $after[0] as $new |
      if $old.release != $new.release or $old.images != $new.images
      then "" | halt_error(16) else . end |
      [$old.core.protocols[].listener_id] as $oldIds |
      [$new.core.protocols[].listener_id] as $newIds |
      ($old.tls.http01 == $new.tls.http01 or
        all($new.core.protocols[];
          .id != 21 and .id != 22 and .id != 23 and .id != 24 and .id != 25 and .id != 27 and .id != 29) or
        ($old | del(.tls.http01)) == ($new | del(.tls.http01))) and
      # 保留共存绑定的原端口与地址族，关闭时恢复直连不能依赖已被改写的输入。
      ($old.reality_stream == null or
        all($old.core.protocols[] |
          select(.listener_id == $old.reality_stream.listener_id or .listener_id == $old.reality_stream.website_listener_id);
          . as $bound | any($new.core.protocols[];
            .listener_id == $bound.listener_id and .core == $bound.core and
            .public_port == $bound.public_port and .address_families == $bound.address_families))) and
       (if $tun_action != "" then
        def without_tun: .host_integrations |= map(select(.type != "tun"));
        if $tun_action == "enable" then
          ([$old.host_integrations[] | select(.type == "tun")] | length) == 0 and
          ([$new.host_integrations[] | select(.type == "tun")] | length) == 1 and
          ($old | without_tun) == ($new | without_tun)
        else $new == ($old | without_tun) end
       elif $tproxy_action != "" then
        def without_tproxy: .host_integrations |= map(select(.type != $tproxy_kind));
        def without_tproxy_settings:
          .host_integrations |= map(if .type == $tproxy_kind then del(.settings.port,.settings.mark,.settings.family,.settings.output_uid,.settings.output_all) else . end);
        if $tproxy_action == "settings" then
          ([$old.host_integrations[] | select(.type == $tproxy_kind)] | length) == 1 and
          ([$new.host_integrations[] | select(.type == $tproxy_kind)] | length) == 1 and
          ($old | without_tproxy_settings) == ($new | without_tproxy_settings)
        elif $tproxy_action == "enable" then
          ([$old.host_integrations[] | select(.type == $tproxy_kind)] | length) == 0 and
          ([$new.host_integrations[] | select(.type == $tproxy_kind)] | length) == 1 and
          ($old | without_tproxy) == ($new | without_tproxy)
        else
          $new == ($old | without_tproxy)
        end
       elif $port_hopping != "" then
        ($old | del(.port_hopping)) == ($new | del(.port_hopping))
       elif $fail2ban_action == "port" then
         # 端口专项只豁免选中入口公开端口与唯一 jail 的保护端口，其余规格逐字冻结。
         def without_fail2ban_port:
           .core.protocols |= map(if .listener_id == $fail2ban_listener then del(.public_port) else . end) |
           .host_integrations |= map(if .type == "fail2ban" then del(.settings.ports) else . end);
         ($old | without_fail2ban_port) == ($new | without_fail2ban_port)
        elif $fail2ban_action == "off" then
        $new.host_integrations == [$old.host_integrations[] | select(.type != $fail2ban_type)] and
        ($old | del(.host_integrations)) == ($new | del(.host_integrations))
       elif $fail2ban_action == "enable" then
        ([$old.host_integrations[] | select(.type == $fail2ban_type)] | length) == 0 and
        ([$new.host_integrations[] | select(.type == $fail2ban_type)] | length) == 1 and
        ($old | without_fail2ban) == ($new | without_fail2ban)
       elif $fail2ban_action == "settings" then
        ([$old.host_integrations[] | select(.type == $fail2ban_type)] | length) == 1 and
        ([$new.host_integrations[] | select(.type == $fail2ban_type)] | length) == 1 and
        ($old | without_fail2ban_settings) == ($new | without_fail2ban_settings)
       elif $protocol_kind != "" then
        # 可信解析的补丁键只豁免选中字段，身份、其它字段及其它入口保持冻结。
        def without_protocol_patch:
          .core.protocols |= map(if .listener_id == $protocol_listener then
            .[$protocol_kind] |= delpaths($protocol_patch | keys | map([.]))
            else . end);
        ($old | without_protocol_patch) == ($new | without_protocol_patch)
       elif $xhttp_listener != "" then
        # 每个专项只豁免自己的字段，其余高级参数冻结。
        def without_xhttp:
          .core.protocols |= map(if .listener_id == $xhttp_listener then
            if $xhttp_action == "mode" then del(.xhttp.mode)
            elif $xhttp_action == "path-host" then del(.xhttp.path,.xhttp.host)
            elif $xhttp_action == "advanced" then
              del(.xhttp.xPaddingBytes,.xhttp.noGRPCHeader,.xhttp.noSSEHeader,
                .xhttp.scMaxEachPostBytes,.xhttp.scMinPostsIntervalMs,
                .xhttp.scMaxBufferedPosts,.xhttp.scStreamUpServerSecs)
            elif $xhttp_action == "defaults" then
              del(.xhttp.mode,.xhttp.xmux,.xhttp.xPaddingBytes,.xhttp.noGRPCHeader,.xhttp.noSSEHeader,
                .xhttp.scMaxEachPostBytes,.xhttp.scMinPostsIntervalMs,
                .xhttp.scMaxBufferedPosts,.xhttp.scStreamUpServerSecs)
            elif $xhttp_action == "preset" then del(.xhttp.mode, .xhttp.xmux)
            elif $xhttp_action == "padding" or $xhttp_action == "padding-clear" then del(.xhttp.xPaddingBytes)
            elif $xhttp_action == "headers" or $xhttp_action == "headers-clear" then del(.xhttp.noGRPCHeader,.xhttp.noSSEHeader)
            elif $xhttp_action == "limits" or $xhttp_action == "limits-clear" then
              del(.xhttp.scMaxEachPostBytes,.xhttp.scMinPostsIntervalMs,
                .xhttp.scMaxBufferedPosts,.xhttp.scStreamUpServerSecs)
            else del(.xhttp.xmux) end
          else . end);
        ($old | without_xhttp) == ($new | without_xhttp)
       elif $cdn_listener != "" then
        ($old | without_cdn) == ($new | without_cdn)
       elif $port_alias == "port-alias-replace" then
        $new == ($old | .port_aliases |= map(
          if .listener_id == $alias_listener and .public_port == ($alias_old_port | tonumber)
          then .public_port = ($alias_port | tonumber) else . end))
       elif $port_alias != "" then
        ($old | del(.port_aliases)) == ($new | del(.port_aliases))
       elif $http_relay == "port" then
        ($old | del(.relay.http.port)) == ($new | del(.relay.http.port))
       elif ($http_relay | startswith("sources")) then
        ($old | del(.relay.http.source_ips)) == ($new | del(.relay.http.source_ips))
       elif $http_relay != "" then
        ($old | del(.relay.http) | if .relay == {} then del(.relay) else . end) ==
          ($new | del(.relay.http) | if .relay == {} then del(.relay) else . end)
       elif $socks5 != "" then
        ($old | del(.routing.socks5) | if .routing == {} then del(.routing) else . end) ==
          ($new | del(.routing.socks5) | if .routing == {} then del(.routing) else . end)
       elif $routing_kind == "access_control" then
        $routing_action == "disable" and
        $new == ($old | del(.routing.direct,.routing.block,.routing.block_ips,.routing.region) |
          if .routing == {} then del(.routing) else . end)
        elif $routing_action == "upstream" then
         # 上游编辑只豁免地址和端口，域名名单、认证及其它配置冻结。
         ($old | del(.routing[$routing_kind].server,.routing[$routing_kind].port)) ==
           ($new | del(.routing[$routing_kind].server,.routing[$routing_kind].port))
        elif $routing_action == "domains_replace" then
         ($old | del(.routing[$routing_kind][$routing_domains_field])) ==
           ($new | del(.routing[$routing_kind][$routing_domains_field]))
        elif $routing_action == "ips_replace" then
         ($old | del(.routing.block_ips.ips)) == ($new | del(.routing.block_ips.ips))
        elif $routing_action == "ips_resolve" or $routing_action == "ips_literal" then
         ($old | del(.routing.block_ips.resolve_domains)) ==
           ($new | del(.routing.block_ips.resolve_domains))
        elif $routing_action == "host_replace" then
         ($old | del(.routing.hosts[$routing_host])) == ($new | del(.routing.hosts[$routing_host]))
        elif $routing_action == "host_add" then
         $new == ($old | .routing.hosts = ((.routing.hosts // {}) + {($routing_host):$routing_ip}))
        elif $routing_action == "host_remove" then
         $new == ($old | del(.routing.hosts[$routing_host]) |
           if .routing.hosts == {} then del(.routing.hosts) else . end |
           if .routing == {} then del(.routing) else . end)
       elif $routing_kind == "warp" and ($routing_action | startswith("warp_")) then
        def without_warp_edit:
          if $routing_action == "warp_family" then del(.routing.warp.family)
          else del(.routing.warp.mode, .routing.warp.domains) end;
        ($old | without_warp_edit) == ($new | without_warp_edit)
       elif $routing_kind == "region" and ($routing_action | startswith("allow_")) then
        ($old | del(.routing.region.allow_domains)) == ($new | del(.routing.region.allow_domains))
       elif $routing_kind == "region" and $routing_action == "mode" then
        ($old | del(.routing.region.mode)) == ($new | del(.routing.region.mode))
       elif $routing_kind == "socks5" then
        # 非空只豁免域名；删空只能关闭出站，不能改凭据或转成全局代理。
        if $new.routing.socks5 == null then
          $routing_action == "domains_remove" and
          $new == ($old | del(.routing.socks5) | if .routing == {} then del(.routing) else . end)
        else
          ($old | del(.routing.socks5.domains)) == ($new | del(.routing.socks5.domains))
        end
       elif $routing_kind != "" then
        ($old | del(.routing[$routing_kind]) | if .routing == {} then del(.routing) else . end) ==
          ($new | del(.routing[$routing_kind]) | if .routing == {} then del(.routing) else . end)
       elif $http01 != "" then
        ($old | del(.tls.http01)) == ($new | del(.tls.http01))
       elif $site != "" then
        ($old | del(.site)) == ($new | del(.site))
       elif $alpn != "" then
        def without_alpn: .core.protocols |= map(if .listener_id == $alpn then
          del(.fallback_tls.alpn) else . end);
        ($old | without_alpn) == ($new | without_alpn)
       elif $stream != "" then
        ($old | del(.reality_stream)) == ($new | del(.reality_stream))
       else
      (if $regenerate != "" or $target != "" then
        ($old | special) == ($new | special)
       else true end) and
      # 分次提交新增与删除，防止借同凭据入口绕过已有身份和内部端口冻结。
      ((($oldIds - $newIds) | length) == 0 or (($newIds - $oldIds) | length) == 0) and
      # 普通编辑只随入口删除清理别名，不允许借规格导入新增或更换公开别名。
      ([($old.port_aliases // [])[] | select(.listener_id as $id | ($newIds | index($id)) != null)] | sort_by(.listener_id,.public_port)) ==
        (($new.port_aliases // []) | sort_by(.listener_id,.public_port)) and
      ([($old.cdn_entries // [])[] | select(.listener_id as $id | ($newIds | index($id)) != null)] | sort_by(.listener_id)) ==
        (($new.cdn_entries // []) | sort_by(.listener_id)) and
      # 删除入口只裁剪账号关联，账号身份、凭据与其它字段仍冻结。
      ($old | if has("accounts") then
        .accounts |= map(.listeners |= map(select(. as $id | ($newIds | index($id)) != null)))
        else . end | root | del(.port_aliases, .cdn_entries)) ==
        ($new | root | del(.port_aliases, .cdn_entries)) and
      ($new.tls | del(.http01)) == (if any($new.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29 or .id == 3 or .id == 4 or .id == 5 or .id == 28 or .id == 31) then ($old.tls | del(.http01)) else null end) and
      all($new.core.protocols[];
        . as $entry | [$old.core.protocols[] | select(.listener_id == $entry.listener_id)] as $existing |
        if ($existing | length) == 1 then ($existing[0] | fixed) == ($entry | fixed)
        else
          ((($entry.id == 1 or $entry.id == 26) and ($entry.core == "xray" or $entry.core == "sing-box")) or
           ($entry.id == 2 and $entry.core == "xray") or
           ($entry.id == 3 and $entry.core == "sing-box") or
           ($entry.id == 4 and $entry.core == "sing-box") or
           ($entry.id == 5 and $entry.core == "sing-box") or
           ($entry.id == 28 and ($entry.core == "xray" or $entry.core == "sing-box")) or
           (($entry.id == 27 or $entry.id == 29) and $entry.core == "xray") or
           ($entry.id == 30 and $entry.core == "sing-box") or
           ($entry.id == 31 and $entry.core == "sing-box") or
           ($entry.id == 23 and ($entry.core == "xray" or $entry.core == "sing-box")) or
           (($entry.id == 21 or $entry.id == 22 or $entry.id == 24 or $entry.id == 25) and $entry.core == "xray")) and
          any($old.core.protocols[];
            .listener_id as $sourceId | any($new.core.protocols[]; .listener_id == $sourceId) and
            (if reality and ($entry | reality) then
              shared == ($entry | shared) and
              ($entry.id != 2 or
                ((.xhttp // {}) | del(.path,.host,.mode)) ==
                  (($entry.xhttp // {}) | del(.path,.host,.mode)))
            else
              (fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port,
                .httpupgrade.backend_port, .httpupgrade.tls_port, .grpc_tls.backend_port, .grpc_tls.tls_port)) ==
              ($entry | fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port,
                .httpupgrade.backend_port, .httpupgrade.tls_port, .grpc_tls.backend_port, .grpc_tls.tls_port))
            end))
        end)
       end)
    ' >/dev/null 2>&1 || {
        if [[ "$?" -eq "${PADM_DOCKER_RC_MANIFEST}" ]]; then
            dockerError '配置中的版本、签名摘要或镜像与已安装发布输入不一致'
            return "${PADM_DOCKER_RC_MANIFEST}"
        fi
        dockerError '仅支持已开放的专项管理与现有入口编辑、复制、Reality 传输派生和删除；账号、密钥、已有入口身份、内部端口与核心、主核心、证书和发布不能改写'
        return "${PADM_DOCKER_RC_STATE}"
    }
}
