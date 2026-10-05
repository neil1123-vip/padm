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
            dockerError '已有部署或配置记录，首次配置不会覆盖；请使用完整 spec 配置或等待编辑/导入功能'
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

dockerSetupGenerateSpec() {
    local core=$1 protocols=$2 server=$3 families=$4 realityPort=$5 target=$6 targetPort=$7 sni=$8
    local domain=$9 wsPort=${10} subscription=${11} output=${12}
    local xrayImage opsImage uuid token shortId= privateKey= publicKey= keyPair derivedPair derivedPublic wsPath= inputsFile
    xrayImage=$(dockerManifestImageReference xray) || return 1
    opsImage=$(dockerManifestImageReference ops) || return 1
    uuid=$(dockerSetupTool "${xrayImage}" uuid 2>/dev/null) || return 1
    [[ "${uuid}" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]] || return 1
    token=$(dockerSetupRandomHex "${opsImage}" 32) || return 1
    if [[ "${protocols}" == 1 || "${protocols}" == 3 ]]; then
        keyPair=$(dockerSetupTool "${xrayImage}" x25519 2>/dev/null) || return 1
        privateKey=$(awk '/^PrivateKey:/ { print $2; exit }' <<<"${keyPair}")
        publicKey=$(awk '/^Password \(PublicKey\):/ { print $3; exit } /^PublicKey:/ { print $2; exit }' <<<"${keyPair}")
        [[ "${privateKey}" =~ ^[A-Za-z0-9_-]{43}$ && "${publicKey}" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
        # 按 RFC 8410 编码交给 OpenSSL，经标准输入派生公钥，不把私钥展开到进程参数。
        derivedPair=$(printf '%s\n' "${privateKey}" |
            docker run --rm -i --read-only --network none --cap-drop ALL \
                --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
                --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
                --entrypoint python3 "${opsImage}" -c '
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
' \
                2>/dev/null) || return 1
        derivedPublic=${derivedPair}
        [[ "${derivedPublic}" == "${publicKey}" ]] || return 1
        shortId=$(dockerSetupRandomHex "${opsImage}" 8) || return 1
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
        wsPath=$(dockerSetupRandomHex "${opsImage}" 16) || return 1
    fi
    inputsFile="${output}.credentials"
    # 秘密只经私密文件交给 jq，不放进宿主进程参数或 Docker Cmd。
    (
        umask 077
        printf '%s\n%s\n%s\n%s\n%s\n%s\n' "${uuid}" "${privateKey}" "${publicKey}" \
            "${shortId}" "${wsPath}" "${token}" >"${inputsFile}"
    ) || return 1
    dockerManifestConfigurationInputs | jq \
        --arg core "${core}" --argjson protocols "${protocols}" --arg server "${server}" \
        --argjson families "${families}" --argjson realityPort "${realityPort:-443}" \
        --arg target "${target}" --argjson targetPort "${targetPort:-443}" --arg sni "${sni}" \
        --arg domain "${domain}" --argjson wsPort "${wsPort:-443}" \
        --rawfile credentials "${inputsFile}" --argjson subscription "${subscription}" '
      ($credentials | split("\n")) as $secrets |
      $secrets[0] as $uuid | $secrets[1] as $privateKey | $secrets[2] as $publicKey |
      $secrets[3] as $shortId | $secrets[4] as $wsPath | $secrets[5] as $token |
      . + {schema_version: 1, core: {type: $core, protocols:
        (if $protocols == 1 or $protocols == 3 then [{
          id: 1, server: $server, public_port: $realityPort, address_families: $families,
          name: "main-reality", uuid: $uuid,
          reality: {server_name: $sni, target_host: $target, target_port: $targetPort,
            private_key: $privateKey, public_key: $publicKey, short_id: $shortId}
        }] else [] end) +
        (if $protocols == 2 or $protocols == 3 then [{
          id: 21, server: $server, public_port: $wsPort, address_families: $families,
          name: "main-ws", uuid: $uuid, websocket: {domain: $domain, path: $wsPath}
        }] else [] end)},
        tls: (if $protocols == 2 or $protocols == 3 then {domain: $domain} else null end),
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

dockerSetupCommand() {
    local manifest= bundle= controlBundle= coreChoice core protocols=1 server familyChoice families
    local realityPort=443 target= targetPort=443 sni= domain= wsPort=443 tlsMode= cert= key=
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
    dockerSetupRead coreChoice '核心 [1=Xray, 2=sing-box, 0=取消]: ' 1 || return 0
    case "${coreChoice}" in
    1)
        core=xray
        dockerSetupRead protocols '协议 [1=Reality, 2=WS TLS, 3=两者, 0=取消]: ' 1 || return 0
        [[ "${protocols}" == 1 || "${protocols}" == 2 || "${protocols}" == 3 ]] || return "${PADM_DOCKER_RC_USAGE}"
        ;;
    2) core=sing-box ;;
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
    if [[ "${protocols}" == 1 || "${protocols}" == 3 ]]; then
        dockerSetupRead realityPort 'Reality 入口端口 [443]: ' 443 || return 0
        dockerSetupRead target 'Reality 目标域名（0 取消）: ' || return 0
        dockerSetupRead targetPort 'Reality 目标端口 [443]: ' 443 || return 0
        dockerSetupRead sni "Reality SNI [${target}]: " "${target}" || return 0
        dockerDomainIsValid "${target}" && dockerDomainIsValid "${sni}" ||
            return "${PADM_DOCKER_RC_USAGE}"
    fi
    if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
        [[ "${protocols}" != 3 ]] || wsPort=8443
        dockerSetupRead domain 'WS TLS 域名（0 取消）: ' || return 0
        dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerSetupRead wsPort "WS TLS 入口端口 [${wsPort}]: " "${wsPort}" || return 0
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
        dockerSetupRead answer '启用 HTTPS 订阅发布？[y/N]: ' n || return 0
        case "${answer}" in
        y|Y|yes|YES) subscription=true ;;
        n|N|no|NO) subscription=false ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    fi
    for answer in "${realityPort}" "${targetPort}" "${wsPort}"; do
        [[ "${answer}" =~ ^[1-9][0-9]{0,4}$ && "${answer}" -le 65535 ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
    done
    [[ "${protocols}" != 3 || "${realityPort}" != "${wsPort}" ]] ||
        { dockerError 'Reality 和 WS TLS 不能使用同一入口端口'; return "${PADM_DOCKER_RC_CONFLICT}"; }
    printf '\n核心: %s\n协议组合: %s\n服务器: %s\n地址族: %s\n' "${core}" "${protocols}" "${server}" "${families}"
    [[ "${protocols}" == 2 ]] || printf 'Reality: %s -> %s:%s，SNI %s\n' "${realityPort}" "${target}" "${targetPort}" "${sni}"
    [[ "${protocols}" == 1 ]] || printf 'WS TLS: %s:%s，证书方式 %s，订阅 %s\n' "${domain}" "${wsPort}" "${tlsMode}" "${subscription}"
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
        "${candidate}/spec.json" || {
        dockerError '账号参数生成或规格校验失败，未提交配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureReleaseValidate "${candidate}/spec.json" || return "${PADM_DOCKER_RC_MANIFEST}"
    if [[ "${protocols}" == 2 || "${protocols}" == 3 ]]; then
        dockerSetupStageCertificate "${candidate}" "${tlsMode}" "${domain}" "${cert}" "${key}" \
            "${email}" "${provider}" "${credentials}" || return "${PADM_DOCKER_RC_STATE}"
        dockerConfigureApply "${candidate}/spec.json" "${candidate}/tls" "${candidate}/acme" || status=$?
    else
        dockerConfigureApply "${candidate}/spec.json" || status=$?
    fi
    return "${status}"
}
