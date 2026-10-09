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
    if [[ "${protocols}" == 6 && "${hy2Obfs}" == true ]]; then
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
        --arg hy2Masquerade "${hy2Masquerade}" \
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
            obfs: (if $obfsPassword == "" then null else {type: "salamander", password: $obfsPassword} end),
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
        '8. 启用 Nginx HTTP-01 入口' '9. 关闭 Nginx HTTP-01 入口' '0. 返回'
    dockerSetupRead choice '证书操作: ' || return 0
    [[ "${choice}" =~ ^[1-9]$ ]] || return "${PADM_DOCKER_RC_USAGE}"
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
    local targetMode probeInputs releasePrepared=0
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
    [[ -t 0 && -t 1 ]] || { dockerError '首次配置需要交互终端'; return "${PADM_DOCKER_RC_USAGE}"; }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    dockerSetupUnconfigured || return "${PADM_DOCKER_RC_CONFLICT}"
    printf '\nDocker 首次配置\n'
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
            dockerSetupRead answer '启用 Salamander 混淆（确认后随机密码）？[y/N]: ' n || return 0
            case "${answer}" in
            y|Y|yes|YES) hy2Obfs=true ;;
            n|N|no|NO) hy2Obfs=false ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
            dockerSetupRead hy2Masquerade '伪装 HTTPS 地址（空输入不启用，0 取消）: ' || return 0
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
    dockerSetupRead answer '确认首次配置？[y/N]: ' n || return 0
    case "${answer}" in y|Y|yes|YES) ;; *) printf '已取消首次配置。\n'; return 0 ;; esac
    dockerLockInstalledDeployment || return $?
    dockerSetupUnconfigured || return "${PADM_DOCKER_RC_CONFLICT}"
    if [[ "${releasePrepared}" -eq 0 ]]; then
        dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    [[ -n "${candidate}" ]] || candidate=$(mktemp -d "${root}/.setup.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${candidate}
    chmod 0700 "${candidate}" || return "${PADM_DOCKER_RC_STATE}"
    dockerSetupGenerateSpec "${core}" "${protocols}" "${server}" "${families}" "${realityPort}" \
        "${target}" "${targetPort}" "${sni}" "${domain}" "${wsPort}" "${subscription}" \
        "${candidate}/spec.json" "${secondaryCore}" "${secondaryPort}" \
        "${hy2Mode}" "${hy2Up}" "${hy2Down}" "${hy2Obfs}" "${hy2Masquerade}" \
        "${tuicCongestion}" "${tuicAuthTimeout}" "${tuicHeartbeat}" "${tuicZeroRtt}" || {
        dockerError '账号参数生成或规格校验失败，未提交配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureReleaseValidate "${candidate}/spec.json" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 || "${protocols}" == 7 || "${protocols}" == 8 || "${protocols}" == 10 || "${protocols}" == 11 || "${protocols}" == 12 || "${protocols}" == 13 || "${protocols}" == 14 || "${protocols}" == 15 || "${protocols}" == 16 || "${protocols}" == 17 ]]; then
        dockerSetupStageCertificate "${candidate}" "${tlsMode}" "${domain}" "${cert}" "${key}" \
            "${email}" "${provider}" "${credentials}" || return "${PADM_DOCKER_RC_STATE}"
        dockerConfigureApply "${candidate}/spec.json" "${candidate}/tls" "${candidate}/acme" || status=$?
    else
        dockerConfigureApply "${candidate}/spec.json" || status=$?
    fi
    return "${status}"
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
        "${draft}"
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
    list|stream-status|routing-status) [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}" ;;
    links|alpn-status|targets|check-target|target-status|select-target|block-current-target)
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
    if [[ "${action}" == routing-status ]]; then
        jq '{enabled:(.routing != null), server:(.routing.socks5.server // null),
          port:(.routing.socks5.port // null),
          mode:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "domains" else "global" end),
          domain_rules:(.routing.socks5.domains // []),
          tcp:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "matched-socks5" else "socks5" end),
          udp:(if .routing.socks5 == null then "direct"
            elif .routing.socks5 | has("domains") then "matched-blocked" else "blocked" end)} +
          (if .routing.dns != null then {dns:{server:.routing.dns.server,
            port:.routing.dns.port,domain_rules:.routing.dns.domains}} else {} end) +
          (if .routing.hosts != null then {hosts:.routing.hosts} else {} end) +
          (if .routing.direct != null then {direct:{domain_rules:.routing.direct.domains}} else {} end) +
          (if .routing.block != null then {block:{domain_rules:.routing.block.domains}} else {} end) +
          (if .routing.block_ips != null then {block_ips:{ip_rules:.routing.block_ips.ips}} else {} end)' "${normalized}"
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

dockerEditFields() {
    local draft=$1 choice protocol listener field value= defaultValue= valueFile="${1}.value" temporary="${1}.next"
    local sourceCore targetCore coreChoice primaryCore targetProtocol obfsChoice opsImage zeroRttChoice
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
                jq --arg key "${listener}" '
                  .core.type as $primary |
                  .core.protocols |= map(select(.listener_id != $key)) |
                  if all(.core.protocols[]; .core != $primary) then error("主核心至少保留一个入口")
                  elif any(.core.protocols[]; .id == 21) then .
                  elif any(.core.protocols[]; .id == 3 or .id == 4 or .id == 5 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 28 or .id == 29 or .id == 31) then .subscription.enabled = false
                  else .tls = null | .subscription.enabled = false end |
                  .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null) |
                  if any(.core.protocols[]; .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29)
                  then . else del(.site, .tls.http01) end
                ' "${draft}" >"${temporary}" 2>/dev/null || {
                    dockerError '主核心至少保留一个入口；删除副核心的最后入口会关闭副核心'
                    return 1
                }
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
                jq --arg key "${listener}" --arg targetCore "${targetCore}" --argjson port "${value}" \
                    --argjson targetProtocol "${targetProtocol}" --argjson derive "$([[ "${choice}" == 11 ]] && printf true || printf false)" '
                  . as $r |
                  if (.core.protocols | length) >= 16 then error("最多16个入口") else . end |
                  first(range(1; 18) | "entry-\(.)" | . as $id |
                    select(all($r.core.protocols[]; .listener_id != $id))) as $newId |
                  (.core.protocols[] | select(.listener_id == $key)) as $source |
                  ($source | .listener_id = $newId | .core = $targetCore | .public_port = $port |
                    if $derive then
                      del(.xhttp, .grpc) | .id = $targetProtocol |
                      if .id == 2 then
                        .xhttp = {path: ("/" + $newId + "xhttp"), host: .reality.server_name, mode: "auto"}
                      elif .id == 26 then .grpc = {service_name: "grpc"} else . end
                    else . end |
                    if .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 then
                      (if .id == 23 then "httpupgrade"
                       elif .id == 24 or .id == 25 then "grpc_tls" else "websocket" end) as $transport |
                      ([$r.core.protocols[] | select(.core == $targetCore) |
                        if .id == 21 or .id == 22 then .websocket.backend_port
                        elif .id == 23 then .httpupgrade.backend_port
                        elif .id == 24 or .id == 25 then .grpc_tls.backend_port else .public_port end] +
                       [$r.host_integrations[] | select(.type == "tproxy") | .settings.port] +
                       [if $targetCore == "xray" then 10085 else 10087 end]) as $used |
                      .[$transport].backend_port = first(range(
                        (if .id == 23 then 31306 elif .id == 24 then 31301
                         elif .id == 25 then 31304 else 31297 end); 65536) |
                        . as $p | select(($used | index($p)) == null)) |
                      ([$r.core.protocols[] | if .id == 21 or .id == 22 then .websocket.tls_port
                        elif .id == 23 then .httpupgrade.tls_port
                        elif .id == 24 or .id == 25 then .grpc_tls.tls_port
                        elif .id == 27 or .id == 29 then .fallback_tls.http_port, .fallback_tls.http2_port
                        else empty end] + [8080]) as $tls |
                      .[$transport].tls_port = first(range(8443; 65536) | . as $p | select(($tls | index($p)) == null))
                    else . end) as $new |
                  .core.protocols += [$new] |
                  .core.type as $primary |
                  .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null)
                ' "${draft}" >"${temporary}" 2>/dev/null || return 1
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
                dockerSetupRead value 'Hysteria2 参数 [1=拥塞模式, 2=服务端上行 Mbps, 3=服务端下行 Mbps, 4=混淆, 5=伪装 HTTPS 地址]: ' || return 3
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
                if [[ "${defaultValue}" == null ]]; then defaultValue=1; else defaultValue=2; fi
                dockerSetupRead obfsChoice 'Salamander 混淆 [1=关闭, 2=启用或修改密码，空输入保留]: ' "${defaultValue}" || return 3
                case "${obfsChoice}" in
                1) value= ;;
                2)
                    defaultValue=$(jq -r --arg key "${listener}" '
                      .core.protocols[] | select(.listener_id == $key) | .hy2.obfs.password // ""
                    ' "${draft}") || return 1
                    printf '混淆密码（16..128 位字母/数字/_/-，空输入保留或随机生成，0 取消）: '
                    IFS= read -r -s value || return 3
                    printf '\n'
                    [[ "${value}" != 0 ]] || return 3
                    value=${value:-${defaultValue}}
                    if [[ -z "${value}" ]]; then
                        opsImage=$(dockerResolveOpsImage) || return 1
                        value=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
                    fi
                    [[ "${value}" =~ ^[A-Za-z0-9_-]{16,128}$ ]] || return 1
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
                dockerSetupRead value '伪装 HTTPS 地址（空输入保留，off 关闭，0 取消）: ' "${defaultValue}" || return 3
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
            jq --arg key "${listener}" --arg field "${field}" --rawfile value "${valueFile}" '
              (if $field == "public_port" or $field == "reality.target_port" or
                  $field == "hy2.up_mbps" or $field == "hy2.down_mbps" then ($value | tonumber)
               elif $field == "hy2.obfs" then
                 if $value == "" then null else {type: "salamander", password: $value} end
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

dockerEditCommand() {
    local specFile= manifest= bundle= controlBundle= mode=interactive root workspace original draft imported=0 status=0
    local privateKey publicKey derivedKey opsImage version normalized regenerateReality=
    local realityTarget= targetHost= targetPort= targetSni=
    local realityStream= streamListener= streamWebsite=
    local streamDomains= streamAddress= streamPort=8443
    local siteMode= siteSource= siteUrl=
    local alpnListener= alpnOrder=
    local http01= socks5= socks5File= socks5Domains= routingKind= routingFile= routingAction=
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
        --dns|--hosts|--direct|--block|--block-ips)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && -z "${routingKind}" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            routingKind=${1#--} routingFile=$2 routingAction=enable
            routingKind=${routingKind//-/_}
            shift 2
            ;;
        --dns-off|--hosts-off|--direct-off|--block-off|--block-ips-off)
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
    [[ "${mode}" != interactive || ( -t 0 && -t 1 ) ]] || {
        dockerError '非交互编辑需要 --preview 或 --confirm PADM-DOCKER-EDIT'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    [[ ( -z "${regenerateReality}" && -z "${realityTarget}" && -z "${realityStream}" &&
        -z "${siteMode}" && -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" ) ||
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
    dockerEditBaselineValidate "${original}" "${workspace}" "${alpnListener}" ||
        return "${PADM_DOCKER_RC_STATE}"
    normalized="${workspace}/normalized.json"
    dockerConfigureSpecMigrate "${original}" "${normalized}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ -n "${specFile}" && "${imported}" -eq 0 ]]; then
        specFile=$(dockerResolveRegularFile "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
        cp -- "${specFile}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    else
        cp -- "${original}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    fi
    chmod 0600 "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    jq -es 'length == 1 and (.[0] | type == "object")' "${draft}" >/dev/null 2>&1 ||
        return "${PADM_DOCKER_RC_STATE}"
    if jq -en --slurpfile before "${original}" --slurpfile after "${draft}" '
      any($before[0].host_integrations[]; .type == "fail2ban") and
      (([$before[0].core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) | .public_port] | sort) !=
       ([$after[0].core.protocols[] | select(.id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25) | .public_port] | sort))
    ' >/dev/null 2>&1; then
        dockerError '带 Fail2ban 的 WS 入口端口需联动封禁规则，本阶段未开放端口或入口数量修改'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerConfigureSpecMigrate "${draft}" "${draft}.v3" &&
        mv -f -- "${draft}.v3" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    # 旧规格先接入，不能同时把未经证明的字段改动当作无损导入。
    if [[ "${mode}" == interactive && -z "${specFile}" && "${imported}" -eq 0 &&
        -z "${regenerateReality}" && -z "${realityTarget}" && -z "${realityStream}" &&
        -z "${siteMode}" && -z "${alpnListener}" && -z "${http01}" && -z "${socks5}" &&
        -z "${routingKind}" ]]; then
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
        if [[ "${routingAction}" == enable ]]; then
            dockerEditPrivateInputCopy "${routingFile}" "${workspace}/${routingKind}.json" "${routingKind}" || {
                dockerError '路由输入须为 root 所有的 0600 单链接普通 JSON 文件，最多 64 KiB，祖先目录不得可写或含链接'
                return "${PADM_DOCKER_RC_STATE}"
            }
            jq --arg kind "${routingKind}" --slurpfile input "${workspace}/${routingKind}.json" \
                '.routing[$kind] = $input[0]' "${draft}" >"${draft}.next" 2>/dev/null
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
          .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29)
      else true end
    ' >/dev/null 2>&1 || {
        dockerError '站点管理需要已有 Nginx TLS 或 fallback 入口'
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
    if [[ -z "${manifest}" ]]; then
        version=$(jq -r '.release.version' "${original}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return "${PADM_DOCKER_RC_STATE}"
        # 编辑验证当前部署版本，不被 latest 的新发布隐式升级或阻断。
        manifest="${PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT%/latest/download/release-manifest.json}/download/v${version}/release-manifest.json"
    fi
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    dockerConfigureReleaseValidate "${draft}" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ -n "${regenerateReality}" ]]; then
        dockerEditRegenerateReality "${draft}" "${regenerateReality}" &&
            dockerConfigureSpecValidate "${draft}" || {
            dockerError 'Reality 参数生成或校验失败，未改写已安装配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
        printf '仅重生成入口 %s 的 Reality 密钥及 short ID；提交后需重新导入该入口链接。\n' "${regenerateReality}"
    fi
    dockerEditPreview "${original}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    [[ -z "${alpnListener}" ]] ||
        printf '入口 %s 的 TLS ALPN 将设为 %s；仅允许该 ALPN 字段漂移，其它配置须与规格一致。\n' "${alpnListener}" "${alpnOrder}"
    [[ -z "${siteSource}" ]] || printf '静态站点内容将使用已校验目录更新；源路径不会写入规格。\n'
    [[ "${imported}" -eq 0 ]] || printf '完整原始规格已匹配，确认后接入受管输入。\n'
    jq -en --arg regenerate "${regenerateReality}" --arg target "${realityTarget}" --arg stream "${realityStream}" \
        --arg site "${siteMode}" --arg alpn "${alpnListener}" --arg http01 "${http01}" \
        --arg socks5 "${socks5}" --arg routing_kind "${routingKind}" \
        --slurpfile before "${normalized}" --slurpfile after "${draft}" '
      def fixed: del(.server, .public_port, .address_families, .name,
        .reality.target_host, .reality.target_port, .reality.server_name, .websocket.path, .httpupgrade.path,
        .xhttp.path, .xhttp.host, .xhttp.mode, .grpc.service_name, .grpc_tls.service_name,
        .hy2.bandwidth_mode, .hy2.up_mbps, .hy2.down_mbps, .hy2.obfs, .hy2.masquerade,
        .tuic.congestion_control, .tuic.auth_timeout, .tuic.heartbeat, .tuic.zero_rtt_handshake) |
        if .listener_id == $regenerate then del(.reality.private_key, .reality.public_key, .reality.short_id) else . end;
      def reality: .id == 1 or .id == 2 or .id == 26;
      def shared: fixed | del(.listener_id, .core, .id, .xhttp, .grpc);
      def root: del(.core.protocols, .core.secondary_type, .tls, .subscription.enabled, .site);
      def special: .core.protocols |= map(
        if $regenerate != "" and .listener_id == $regenerate then
          del(.reality.private_key, .reality.public_key, .reality.short_id)
        elif $target != "" and .listener_id == $target then
          del(.reality.target_host, .reality.target_port, .reality.server_name)
        else . end);
      $before[0] as $old | $after[0] as $new |
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
      (if $socks5 != "" then
        ($old | del(.routing.socks5) | if .routing == {} then del(.routing) else . end) ==
          ($new | del(.routing.socks5) | if .routing == {} then del(.routing) else . end)
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
      ($old | root) == ($new | root) and
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
            (if reality and ($entry | reality) then shared == ($entry | shared)
            else
              (fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port,
                .httpupgrade.backend_port, .httpupgrade.tls_port, .grpc_tls.backend_port, .grpc_tls.tls_port)) ==
              ($entry | fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port,
                .httpupgrade.backend_port, .httpupgrade.tls_port, .grpc_tls.backend_port, .grpc_tls.tls_port))
            end))
        end)
       end)
    ' >/dev/null 2>&1 || {
        dockerError '仅支持路由/HTTP-01/站点专项管理与现有入口编辑、复制、Reality 传输派生和删除；账号、密钥、已有入口身份、内部端口与核心、主核心、证书和发布不能改写'
        return "${PADM_DOCKER_RC_STATE}"
    }
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
    DOCKER_CONFIG_RESTORE_ALPN_LISTENER=${alpnListener}
    dockerConfigureApply "${draft}" '' '' "${mode}" '' "${siteSource}"
}
