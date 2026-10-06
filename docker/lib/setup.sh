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

dockerSetupGenerateSpec() {
    local core=$1 protocols=$2 server=$3 families=$4 realityPort=$5 target=$6 targetPort=$7 sni=$8
    local domain=$9 wsPort=${10} subscription=${11} output=${12} secondaryCore=${13:-} secondaryPort=${14:-8444}
    local hy2Mode=${15:-bbr} hy2Up=${16:-100} hy2Down=${17:-50} hy2Obfs=${18:-false} hy2Masquerade=${19:-}
    local xrayImage opsImage uuid token shortId= privateKey= publicKey= keyPair derivedPair derivedPublic wsPath= inputsFile obfsPassword=
    xrayImage=$(dockerManifestImageReference xray) || return 1
    opsImage=$(dockerManifestImageReference ops) || return 1
    uuid=$(dockerSetupTool "${xrayImage}" uuid 2>/dev/null) || return 1
    [[ "${uuid}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]] || return 1
    token=$(dockerSetupRandomHex "${opsImage}" 32) || return 1
    if [[ ( "${protocols}" != 2 && "${protocols}" != 6 ) || -n "${secondaryCore}" ]]; then
        keyPair=$(dockerSetupTool "${xrayImage}" x25519 2>/dev/null) || return 1
        privateKey=$(awk '/^PrivateKey:/ { print $2; exit }' <<<"${keyPair}")
        publicKey=$(awk '/^Password \(PublicKey\):/ { print $3; exit } /^PublicKey:/ { print $2; exit }' <<<"${keyPair}")
        [[ "${privateKey}" =~ ^[A-Za-z0-9_-]{43}$ && "${publicKey}" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
        derivedPair=$(printf '%s\n' "${privateKey}" |
            dockerSetupRealityPublicKey "${opsImage}") || return 1
        derivedPublic=${derivedPair}
        [[ "${derivedPublic}" == "${publicKey}" ]] || return 1
        shortId=$(dockerSetupRandomHex "${opsImage}" 8) || return 1
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 4 ]]; then
        wsPath=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    if [[ "${protocols}" == 6 && "${hy2Obfs}" == true ]]; then
        obfsPassword=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    inputsFile="${output}.credentials"
    # 秘密只经私密文件交给 jq，不放进宿主进程参数或 Docker Cmd。
    (
        umask 077
        printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "${uuid}" "${privateKey}" "${publicKey}" \
            "${shortId}" "${wsPath}" "${token}" "${obfsPassword}" >"${inputsFile}"
    ) || return 1
    dockerManifestConfigurationInputs | jq \
        --arg core "${core}" --argjson protocols "${protocols}" --arg server "${server}" \
        --argjson families "${families}" --argjson realityPort "${realityPort:-443}" \
        --arg target "${target}" --argjson targetPort "${targetPort:-443}" --arg sni "${sni}" \
        --arg domain "${domain}" --argjson wsPort "${wsPort:-443}" \
        --arg secondaryCore "${secondaryCore}" --argjson secondaryPort "${secondaryPort}" \
        --arg hy2Mode "${hy2Mode}" --argjson hy2Up "${hy2Up}" --argjson hy2Down "${hy2Down}" \
        --arg hy2Masquerade "${hy2Masquerade}" \
        --rawfile credentials "${inputsFile}" --argjson subscription "${subscription}" '
      ($credentials | split("\n")) as $secrets |
      $secrets[0] as $uuid | $secrets[1] as $privateKey | $secrets[2] as $publicKey |
      $secrets[3] as $shortId | $secrets[4] as $wsPath | $secrets[5] as $token |
      $secrets[6] as $obfsPassword |
      . + {schema_version: 3, core: {type: $core,
        secondary_type: (if $secondaryCore == "" then null else $secondaryCore end), protocols: [
        (if $protocols != 2 and $protocols != 6 then {
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
        (if $protocols == 2 or $protocols == 3 then {
          id: 21, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "vless-ws", name: "main-ws", uuid: $uuid,
          websocket: {domain: $domain, path: $wsPath, backend_port: 31297, tls_port: 8443}
        } else empty end),
        (if $protocols == 6 then {
          id: 3, core: $core, server: $server, public_port: $wsPort, address_families: $families,
          listener_id: "entry-hysteria2", name: "main-hysteria2", uuid: $uuid,
          hy2: {domain: $domain, bandwidth_mode: $hy2Mode, up_mbps: $hy2Up, down_mbps: $hy2Down,
            obfs: (if $obfsPassword == "" then null else {type: "salamander", password: $obfsPassword} end),
            masquerade: $hy2Masquerade}
        } else empty end),
        (if $secondaryCore != "" then {
          id: 1, core: $secondaryCore, server: $server, public_port: $secondaryPort, address_families: $families,
          listener_id: "entry-secondary-reality", name: "secondary-reality", uuid: $uuid,
          reality: {server_name: $sni, target_host: $target, target_port: $targetPort,
            private_key: $privateKey, public_key: $publicKey, short_id: $shortId}
        } else empty end)]},
        tls: (if $protocols == 2 or $protocols == 3 or $protocols == 6 then {domain: $domain} else null end),
        subscription: {enabled: $subscription, token: $token}, host_integrations: []}
    ' >"${output}" || return 1
    rm -f -- "${inputsFile}" || return 1
    chmod 0600 "${output}" && dockerConfigureSpecValidate "${output}"
}

dockerSetupStageCertificate() {
    local candidate=$1 mode=$2 domain=$3 cert=$4 key=$5 email=$6 provider=$7 credentials=$8
    local root opsImage extension
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
            dockerError '所选域名没有完整受管证书，请选择导入或 DNS-01'
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
    3)
        credentials=$(dockerResolveRegularFile "${credentials}") &&
            dockerPrivateFileIsRestricted "${credentials}" || {
            dockerError 'DNS 凭据必须为仅允许持有者读取的普通文件'
            return 1
        }
        chmod 0750 "${candidate}" "${candidate}/tls" "${candidate}/acme" || return 1
        if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
            chown -R "${PADM_DOCKER_CONTAINER_UID}:${PADM_DOCKER_CONTAINER_GID}" \
                "${candidate}/tls" "${candidate}/acme" || return 1
            chown "0:${PADM_DOCKER_CONTAINER_GID}" "${candidate}" || return 1
        fi
        dockerAcmeRun "${opsImage}" "${credentials}" "${candidate}/acme" "${candidate}/tls" \
            --issue --dns "${provider}" -d "${domain}" --accountemail "${email}" >/dev/null 2>&1 &&
            dockerAcmeRun "${opsImage}" "${credentials}" "${candidate}/acme" "${candidate}/tls" \
                --install-cert -d "${domain}" \
                --fullchain-file "/var/lib/padm/tls-output/${domain}.crt" \
                --key-file "/var/lib/padm/tls-output/${domain}.key" >/dev/null 2>&1 || {
            dockerError '候选 DNS-01 申请或证书导出失败，现有证书和配置未修改'
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
    local root currentDomain domain choice answer cert= key= email= provider= credentials= action
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
        dockerError '当前部署没有 TLS 域名，请先配置 WS TLS 或 Hysteria2 入口'
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
    printf '%s\n' '1. 查看/校验受管证书' '2. 导入证书轮换' '3. DNS-01 申请' '4. DNS-01 续期' \
        '5. 自动续期状态' '6. 启用自动续期' '7. 停用自动续期' '0. 返回'
    dockerSetupRead choice '证书操作: ' || return 0
    [[ "${choice}" =~ ^[1-7]$ ]] || return "${PADM_DOCKER_RC_USAGE}"
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
        3) action=DNS-01申请 ;;
        4) action=DNS-01续期 ;;
        6) action=启用自动续期 ;;
        esac
        dockerSetupRead email 'ACME 邮箱（0 取消）: ' || return 0
        dockerSetupRead provider 'DNS provider（dns_*，0 取消）: ' || return 0
        dockerSetupRead credentials 'DNS 凭据文件（0 取消）: ' || return 0
        dockerEmailIsValid "${email}" && [[ "${provider}" =~ ^dns_[a-z0-9_]+$ ]] &&
            [[ -n "${credentials}" ]] || return "${PADM_DOCKER_RC_USAGE}"
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
            --dns "${provider}" --credentials "${credentials}"
        ;;
    5) dockerRenewalCommand status ;;
    6)
        dockerRenewalCommand enable --domain "${domain}" --email "${email}" \
            --dns "${provider}" --credentials "${credentials}"
        ;;
    7) dockerRenewalCommand disable --domain "${domain}" ;;
    esac
}

dockerSetupCommand() {
    local manifest= bundle= controlBundle= coreChoice core protocols=1 server familyChoice families
    local secondaryCore= secondaryPort=8444
    local realityPort=443 target= targetPort=443 sni= domain= wsPort=443 tlsMode= cert= key=
    local hy2Mode=bbr hy2Up=100 hy2Down=50 hy2Obfs=false hy2Masquerade=
    local email= provider= credentials= subscription=false answer= root candidate status=0
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
        dockerSetupRead protocols '协议 [1=Reality Vision, 2=WS TLS, 3=两者, 4=Reality XHTTP, 5=Reality gRPC, 0=取消]: ' 1 || return 0
        [[ "${protocols}" =~ ^[1-5]$ ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    2|4)
        core=sing-box
        [[ "${coreChoice}" != 4 ]] || secondaryCore=xray
        dockerSetupRead protocols '协议 [1=Reality Vision, 5=Reality gRPC, 6=Hysteria2, 0=取消]: ' 1 || return 0
        [[ "${protocols}" == 1 || "${protocols}" == 5 || "${protocols}" == 6 ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    dockerSetupRead server '服务器域名或 IP（0 取消）: ' || return 0
    [[ -n "${server}" ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerSetupRead familyChoice '地址族 [1=IPv4, 2=IPv6, 3=双栈, 默认 1]: ' 1 || return 0
    case "${familyChoice}" in
    1) families='["ipv4"]' ;;
    2) families='["ipv6"]' ;;
    3) families='["ipv4","ipv6"]' ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    if [[ ( "${protocols}" != 2 && "${protocols}" != 6 ) || -n "${secondaryCore}" ]]; then
        if [[ "${protocols}" != 2 && "${protocols}" != 6 ]]; then
            dockerSetupRead realityPort '主核心 Reality 入口端口 [443]: ' 443 || return 0
        fi
        dockerSetupRead target 'Reality 目标域名（0 取消）: ' || return 0
        dockerSetupRead targetPort 'Reality 目标端口 [443]: ' 443 || return 0
        dockerSetupRead sni "Reality SNI [${target}]: " "${target}" || return 0
        dockerDomainIsValid "${target}" && dockerDomainIsValid "${sni}" ||
            return "${PADM_DOCKER_RC_USAGE}"
    fi
    if [[ -n "${secondaryCore}" ]]; then
        dockerSetupRead secondaryPort "副核心 ${secondaryCore} Reality 入口端口 [8444]: " 8444 || return 0
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 ]]; then
        [[ "${protocols}" != 3 ]] || wsPort=8443
        if [[ "${protocols}" == 6 ]]; then
            dockerSetupRead domain 'Hysteria2 TLS 域名（0 取消）: ' || return 0
        else
            dockerSetupRead domain 'WS TLS 域名（0 取消）: ' || return 0
        fi
        dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
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
        else
            dockerSetupRead wsPort "WS TLS 入口端口 [${wsPort}]: " "${wsPort}" || return 0
        fi
        dockerSetupRead tlsMode '证书 [1=已有受管, 2=导入, 3=DNS-01, 0=取消]: ' 1 || return 0
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
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        if [[ "${protocols}" != 6 ]]; then
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
        { [[ "${protocols}" != 2 && "${protocols}" != 6 && "${secondaryPort}" == "${realityPort}" ]] ||
          [[ ( "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 ) && "${secondaryPort}" == "${wsPort}" ]]; }; then
        dockerError '主副核心不能使用同一入口端口'
        return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    printf '\n核心: %s\n协议组合: %s\n服务器: %s\n地址族: %s\n' "${core}" "${protocols}" "${server}" "${families}"
    [[ "${protocols}" == 2 || "${protocols}" == 6 ]] ||
        printf 'Reality: %s -> %s:%s，SNI %s\n' "${realityPort}" "${target}" "${targetPort}" "${sni}"
    if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
        printf 'WS TLS: %s:%s，证书方式 %s，订阅 %s\n' "${domain}" "${wsPort}" "${tlsMode}" "${subscription}"
    elif [[ "${protocols}" == 6 ]]; then
        printf 'Hysteria2: %s:%s/udp，证书方式 %s，拥塞 %s，服务端上行/下行 %s/%s Mbps，混淆 %s\n' \
            "${domain}" "${wsPort}" "${tlsMode}" "${hy2Mode}" "${hy2Up}" "${hy2Down}" "${hy2Obfs}"
    fi
    [[ -z "${secondaryCore}" ]] || printf '副核心: %s，Reality 入口端口 %s\n' "${secondaryCore}" "${secondaryPort}"
    printf '确认后将验证发布、生成账号参数并配置服务。\n'
    dockerSetupRead answer '确认首次配置？[y/N]: ' n || return 0
    case "${answer}" in y|Y|yes|YES) ;; *) printf '已取消首次配置。\n'; return 0 ;; esac
    dockerLockInstalledDeployment || return $?
    dockerSetupUnconfigured || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    candidate=$(mktemp -d "${root}/.setup.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_SETUP_CANDIDATE=${candidate}
    chmod 0700 "${candidate}" || return "${PADM_DOCKER_RC_STATE}"
    dockerSetupGenerateSpec "${core}" "${protocols}" "${server}" "${families}" "${realityPort}" \
        "${target}" "${targetPort}" "${sni}" "${domain}" "${wsPort}" "${subscription}" \
        "${candidate}/spec.json" "${secondaryCore}" "${secondaryPort}" \
        "${hy2Mode}" "${hy2Up}" "${hy2Down}" "${hy2Obfs}" "${hy2Masquerade}" || {
        dockerError '账号参数生成或规格校验失败，未提交配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureReleaseValidate "${candidate}/spec.json" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ "${protocols}" == 2 || "${protocols}" == 3 || "${protocols}" == 6 ]]; then
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
      [($old | paths(scalars)), ($new | paths(scalars))] | unique |
      .[] as $path |
      select(($old | getpath($path)) != ($new | getpath($path))) |
      ($path | map(tostring) | join(".")) | "  修改: \(.)"
    ' || return 1
    jq -r '.core.protocols[] |
      "  入口 \(.listener_id // (.id | tostring))，核心 \(.core // "未迁移")，协议 \(.id): \(.server):\(.public_port) [\(.address_families | join(","))]"' \
        "${draft}"
}

dockerProtocolCommand() (
    local action=${1:-} listener= root workspace original normalized selected status
    [[ "$#" -gt 0 ]] && shift
    case "${action}" in
    list) [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}" ;;
    links)
        [[ "$#" -le 1 && "${1:-}" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
        listener=${1:-}
        ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    DOCKER_SETUP_CANDIDATE=
    # 读取只持有短期锁，独立清理工作目录，不把锁带回菜单等待输入。
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
        chmod 0600 "${original}" &&
        dockerEditBaselineValidate "${original}" "${workspace}" &&
        dockerConfigureSpecMigrate "${original}" "${normalized}" &&
        chmod 0600 "${normalized}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == list ]]; then
        jq -r 'def authority: if contains(":") then "[\(.)]" else . end;
          .core.protocols[] |
          "\(.listener_id)  \(.core)  \(if .id == 1 then "Reality Vision"
            elif .id == 2 then "Reality XHTTP" elif .id == 26 then "Reality gRPC"
            elif .id == 3 then "Hysteria2" else "WS TLS" end)  \(.server | authority):\(.public_port)  [\(.address_families | join(","))]  \(.name)"' \
            "${normalized}"
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
    # 命令标准输出只含 URI，便于直接导入或复制，不混入菜单说明。
    dockerGenerateSubscription "${selected}" /dev/stdout
)

dockerEditFields() {
    local draft=$1 choice protocol listener field value= defaultValue= valueFile="${1}.value" temporary="${1}.next"
    local sourceCore targetCore coreChoice primaryCore targetProtocol obfsChoice opsImage
    while :; do
        printf '\n1. 入口端口\n2. 服务器地址\n3. 地址族\n4. 节点名称\n5. Reality 目标/SNI\n6. WS 路径\n7. 订阅开关\n8. 验证并预览\n9. 复制入口\n10. 删除入口\n11. 安装其它 Reality 传输入口\n12. Reality 传输参数\n13. Hysteria2 参数\n0. 取消\n'
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
            if [[ "${protocol}" == 21 && ( "${choice}" == 1 || "${choice}" == 9 || "${choice}" == 10 ) ]] &&
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
                  elif any(.core.protocols[]; .id == 3) then .subscription.enabled = false
                  else .tls = null | .subscription.enabled = false end |
                  .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null)
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
                if [[ ( "${targetProtocol}" == 21 || "${targetProtocol}" == 2 ) && "${targetCore}" != xray ]]; then
                    dockerError 'WS TLS 和 Reality XHTTP 入口仅支持 Xray，不能复制到 sing-box'
                    return 1
                fi
                if [[ "${targetProtocol}" == 3 && "${targetCore}" != sing-box ]]; then
                    dockerError 'Hysteria2 入口仅支持 sing-box，不能复制到 Xray'
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
                    if .id == 21 then
                      ([$r.core.protocols[] | if .id == 21 then .websocket.backend_port else .public_port end] +
                       [$r.host_integrations[] | select(.type == "tproxy") | .settings.port] + [10085]) as $used |
                      .websocket.backend_port = first(range(31297; 65536) | . as $p | select(($used | index($p)) == null)) |
                      [$r.core.protocols[] | select(.id == 21) | .websocket.tls_port] as $tls |
                      .websocket.tls_port = first(range(8443; 65536) | . as $p | select(($tls | index($p)) == null))
                    else . end) as $new |
                  .core.protocols += [$new] |
                  .core.type as $primary |
                  .core.secondary_type = ([.core.protocols[] | select(.core != $primary) | .core] | first // null)
                ' "${draft}" >"${temporary}" 2>/dev/null || return 1
            else
            case "${choice}" in
            1)
                if [[ "${protocol}" == 21 ]] &&
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
            6) [[ "${protocol}" == 21 ]] || return 1; field=websocket.path ;;
            12)
                if [[ "${protocol}" == 2 ]]; then
                    dockerSetupRead value 'XHTTP 参数 [1=路径, 2=Host, 3=模式]: ' || return 3
                    case "${value}" in 1) field=xhttp.path ;; 2) field=xhttp.host ;; 3) field=xhttp.mode ;; *) return 1 ;; esac
                elif [[ "${protocol}" == 26 ]]; then
                    field=grpc.service_name
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
            else
                dockerSetupRead value '新值（空输入保留，0 取消）: ' "${defaultValue}" || return 3
            fi
            # 输入值可能含账号或 WS 路径，只经私密文件传给 jq。
            printf '%s' "${value}" >"${valueFile}" || return 1
            chmod 0600 "${valueFile}" || return 1
            jq --arg key "${listener}" --arg field "${field}" --rawfile value "${valueFile}" '
              (if $field == "public_port" or $field == "reality.target_port" or
                  $field == "hy2.up_mbps" or $field == "hy2.down_mbps" then ($value | tonumber)
               elif $field == "hy2.obfs" then
                 if $value == "" then null else {type: "salamander", password: $value} end
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
    local privateKey publicKey derivedKey opsImage version normalized
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
    [[ "${mode}" != interactive || ( -t 0 && -t 1 ) ]] || {
        dockerError '非交互编辑需要 --preview 或 --confirm PADM-DOCKER-EDIT'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
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
    dockerEditBaselineValidate "${original}" "${workspace}" || return "${PADM_DOCKER_RC_STATE}"
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
      (([$before[0].core.protocols[] | select(.id == 21) | .public_port] | sort) !=
       ([$after[0].core.protocols[] | select(.id == 21) | .public_port] | sort))
    ' >/dev/null 2>&1; then
        dockerError '带 Fail2ban 的 WS 入口端口需联动封禁规则，本阶段未开放端口或入口数量修改'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerConfigureSpecMigrate "${draft}" "${draft}.v3" &&
        mv -f -- "${draft}.v3" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    # 旧规格先接入，不能同时把未经证明的字段改动当作无损导入。
    if [[ "${mode}" == interactive && -z "${specFile}" && "${imported}" -eq 0 ]]; then
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
    dockerConfigureSpecValidate "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    dockerEditPreview "${original}" "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    [[ "${imported}" -eq 0 ]] || printf '完整原始规格已匹配，确认后接入受管输入。\n'
    if [[ -z "${manifest}" ]]; then
        version=$(jq -r '.release.version' "${original}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return "${PADM_DOCKER_RC_STATE}"
        # 编辑验证当前部署版本，不被 latest 的新发布隐式升级或阻断。
        manifest="${PADM_DOCKER_RELEASE_MANIFEST_URL_DEFAULT%/latest/download/release-manifest.json}/download/v${version}/release-manifest.json"
    fi
    dockerConfigureReleasePrepare "${manifest}" "${bundle}" "${controlBundle}" || return $?
    dockerConfigureReleaseValidate "${draft}" || return "${PADM_DOCKER_RC_MANIFEST}"
    jq -en --slurpfile before "${normalized}" --slurpfile after "${draft}" '
      def fixed: del(.server, .public_port, .address_families, .name,
        .reality.target_host, .reality.target_port, .reality.server_name, .websocket.path,
        .xhttp.path, .xhttp.host, .xhttp.mode, .grpc.service_name,
        .hy2.bandwidth_mode, .hy2.up_mbps, .hy2.down_mbps, .hy2.obfs, .hy2.masquerade);
      def reality: .id == 1 or .id == 2 or .id == 26;
      def shared: fixed | del(.listener_id, .core, .id, .xhttp, .grpc);
      def root: del(.core.protocols, .core.secondary_type, .tls, .subscription.enabled);
      $before[0] as $old | $after[0] as $new |
      [$old.core.protocols[].listener_id] as $oldIds |
      [$new.core.protocols[].listener_id] as $newIds |
      # 分次提交新增与删除，防止借同凭据入口绕过已有身份和内部端口冻结。
      ((($oldIds - $newIds) | length) == 0 or (($newIds - $oldIds) | length) == 0) and
      ($old | root) == ($new | root) and
      $new.tls == (if any($new.core.protocols[]; .id == 21 or .id == 3) then $old.tls else null end) and
      all($new.core.protocols[];
        . as $entry | [$old.core.protocols[] | select(.listener_id == $entry.listener_id)] as $existing |
        if ($existing | length) == 1 then ($existing[0] | fixed) == ($entry | fixed)
        else
          ((($entry.id == 1 or $entry.id == 26) and ($entry.core == "xray" or $entry.core == "sing-box")) or
           ($entry.id == 2 and $entry.core == "xray") or
           ($entry.id == 3 and $entry.core == "sing-box") or
           ($entry.id == 21 and $entry.core == "xray")) and
          any($old.core.protocols[];
            .listener_id as $sourceId | any($new.core.protocols[]; .listener_id == $sourceId) and
            (if reality and ($entry | reality) then shared == ($entry | shared)
            else
              (fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port)) ==
              ($entry | fixed | del(.listener_id, .core, .websocket.backend_port, .websocket.tls_port))
            end))
        end)
    ' >/dev/null 2>&1 || {
        dockerError '仅支持现有入口编辑、复制、Reality 传输派生和删除；账号、密钥、已有入口身份、内部端口与核心、主核心、证书和发布不能改写'
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
    dockerConfigureApply "${draft}" '' '' "${mode}"
}
