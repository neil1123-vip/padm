#!/usr/bin/env bash

PADM_CLEANUP_PATHS=()
PADM_CLEANUP_TRAP_INSTALLED=

padmResolveCleanupPath() {
    local path=$1
    local parent base
    [[ -n "${path}" ]] || return 1
    if [[ "${path}" != /* ]]; then
        parent=$(dirname -- "${path}")
        base=$(basename -- "${path}")
        parent=$(cd -- "${parent}" 2>/dev/null && pwd -P) || return 1
        printf '%s\n' "${parent}/${base}"
        return 0
    fi
    printf '%s\n' "${path}"
}

padmInstallCleanupTrap() {
    if [[ -n "${PADM_CLEANUP_TRAP_INSTALLED}" ]]; then
        return 0
    fi
    PADM_CLEANUP_TRAP_INSTALLED=1
    trap 'padmCleanupTempPaths' EXIT
    trap 'padmCleanupTempPaths INT' INT
    trap 'padmCleanupTempPaths TERM' TERM
}

padmRegisterCleanupPath() {
    local path=$1
    local resolvedPath=
    [[ -n "${path}" ]] || return 0
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    PADM_CLEANUP_PATHS+=("${resolvedPath:-${path}}")
}

padmUnregisterCleanupPath() {
    local path=$1
    local kept=()
    local item
    for item in "${PADM_CLEANUP_PATHS[@]}"; do
        [[ "${item}" == "${path}" ]] || kept+=("${item}")
    done
    PADM_CLEANUP_PATHS=("${kept[@]}")
}

padmCreateTempPath() {
    local resultVar=$1
    shift
    local path
    path=$(mktemp "$@") || return 1
    padmInstallCleanupTrap
    padmRegisterCleanupPath "${path}"
    printf -v "${resultVar}" '%s' "${path}"
}

padmCreateTempFileForTarget() {
    local resultVar=$1
    local targetFile=$2
    local label=${3:-tmp}
    local targetDir targetName
    targetDir=$(dirname -- "${targetFile}")
    targetName=$(basename -- "${targetFile}")
    mkdir -p "${targetDir}" || return 1
    padmCreateTempPath "${resultVar}" "${targetDir}/.${targetName}.${label}.XXXXXX"
}

padmTmpFilePath() {
    local fileName=$1
    local tmpBase="${TMPDIR:-/tmp}"
    printf '%s\n' "${tmpBase%/}/${fileName}"
}

padmForgetCleanupPath() {
    local path=$1
    local resolvedPath=
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    padmUnregisterCleanupPath "${resolvedPath:-${path}}"
}

padmRemoveCleanupPath() {
    local path=$1
    local resolvedPath=
    resolvedPath=$(padmResolveCleanupPath "${path}" 2>/dev/null || true)
    rm -rf -- "${resolvedPath:-${path}}" >/dev/null 2>&1 || true
    padmUnregisterCleanupPath "${resolvedPath:-${path}}"
}

commitGeneratedFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=$3

    if [[ -n "${mode}" ]]; then
        chmod "${mode}" "${tmpFile}" || return 1
    fi
    mv "${tmpFile}" "${targetFile}" && padmForgetCleanupPath "${tmpFile}"
}

commitGeneratedJsonFile() {
    local tmpFile=$1
    local targetFile=$2
    local mode=${3:-644}

    jq empty "${tmpFile}" >/dev/null 2>&1 && commitGeneratedFile "${tmpFile}" "${targetFile}" "${mode}"
}

writeGeneratedJsonFile() {
    local targetFile=$1
    local tmpPrefix=$2
    local tmpFile

    padmCreateTempPath tmpFile "$(padmTmpFilePath "${tmpPrefix}.XXXXXX")" || return 1
    cat >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    commitGeneratedJsonFile "${tmpFile}" "${targetFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
}

padmCleanupTempPaths() {
    local status=$?
    local signal=${1:-}
    local index
    trap - EXIT INT TERM
    for ((index=${#PADM_CLEANUP_PATHS[@]} - 1; index >= 0; index--)); do
        [[ -n "${PADM_CLEANUP_PATHS[index]}" ]] || continue
        rm -rf -- "${PADM_CLEANUP_PATHS[index]}" >/dev/null 2>&1 || true
    done
    if [[ -n "${signal}" ]]; then
        case "${signal}" in
        INT) exit 130 ;;
        TERM) exit 143 ;;
        esac
    fi
    exit "${status}"
}

installUserCrontabContent() {
    local tmpFile

    padmCreateTempPath tmpFile "$(padmTmpFilePath "padm-crontab.XXXXXX")" || return 1
    printf '%s\n' "$1" | sed '/^$/d' >"${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    crontab "${tmpFile}" || { padmRemoveCleanupPath "${tmpFile}"; return 1; }
    padmRemoveCleanupPath "${tmpFile}"
}

parseInstallArgs() {
    local value
    local valueVar

    AUTO_INSTALL=
    AUTO_INSTALL_TYPE=
    AUTO_CORE=
    AUTO_PROTOCOLS=
    AUTO_DOMAIN=
    AUTO_PORT=
    AUTO_TLS_CA=
    AUTO_DNS_API=
    AUTO_DNS_API_TYPE=
    AUTO_DNS_API_WILDCARD=
    AUTO_CLOUDFLARE_API_TOKEN=${PADM_CLOUDFLARE_API_TOKEN:-${CLOUDFLARE_API_TOKEN:-${CF_Token:-}}}
    AUTO_CLOUDFLARE_ZONE_ID=${PADM_CLOUDFLARE_ZONE_ID:-${CF_Zone_ID:-}}
    AUTO_ALIYUN_API_KEY=
    AUTO_ALIYUN_API_SECRET=
    AUTO_REUSE_LAST=
    AUTO_CLEAN_ACME=
    AUTO_REALITY_DOMAIN=
    AUTO_REALITY_TARGET=
    AUTO_REALITY_SERVER_NAME=
    AUTO_ENTRY_HOST=
    AUTO_SUBSCRIBE_PORT=
    AUTO_INSTALL_NGINX=
    AUTO_UUID=
    AUTO_USER=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --install-type)
            valueVar=AUTO_INSTALL_TYPE
            ;;
        --core)
            valueVar=AUTO_CORE
            ;;
        --protocols)
            valueVar=AUTO_PROTOCOLS
            ;;
        --domain)
            valueVar=AUTO_DOMAIN
            ;;
        --port)
            valueVar=AUTO_PORT
            ;;
        --tls-ca)
            valueVar=AUTO_TLS_CA
            ;;
        --dns-api)
            valueVar=AUTO_DNS_API
            ;;
        --dns-api-type)
            valueVar=AUTO_DNS_API_TYPE
            ;;
        --dns-api-wildcard)
            valueVar=AUTO_DNS_API_WILDCARD
            ;;
        --cloudflare-api-token)
            valueVar=AUTO_CLOUDFLARE_API_TOKEN
            ;;
        --cloudflare-zone-id)
            valueVar=AUTO_CLOUDFLARE_ZONE_ID
            ;;
        --aliyun-api-key)
            valueVar=AUTO_ALIYUN_API_KEY
            ;;
        --aliyun-api-secret)
            valueVar=AUTO_ALIYUN_API_SECRET
            ;;
        --reuse-last)
            valueVar=AUTO_REUSE_LAST
            ;;
        --clean-acme)
            valueVar=AUTO_CLEAN_ACME
            ;;
        --reality-domain)
            valueVar=AUTO_REALITY_DOMAIN
            ;;
        --reality-target)
            valueVar=AUTO_REALITY_TARGET
            ;;
        --reality-server-name)
            valueVar=AUTO_REALITY_SERVER_NAME
            ;;
        --entry-host)
            valueVar=AUTO_ENTRY_HOST
            ;;
        --subscribe-port)
            valueVar=AUTO_SUBSCRIBE_PORT
            ;;
        --install-nginx)
            valueVar=AUTO_INSTALL_NGINX
            ;;
        --uuid)
            valueVar=AUTO_UUID
            ;;
        --user)
            valueVar=AUTO_USER
            ;;
        --help)
            showInstallArgsHelp
            exit 0
            ;;
        *)
            shift
            continue
            ;;
        esac

        AUTO_INSTALL=true
        if [[ $# -ge 2 && "${2}" != --* ]]; then
            value=$2
            shift 2
        else
            value=
            shift
        fi
        printf -v "${valueVar}" '%s' "${value}"
        valueVar=
    done
}

showInstallArgsHelp() {
    cat <<EOF
┌─ padm 非交互安装参数 ──────────────────────────────
│ 用法: bash install.sh [RenewTLS|UpdateGeo|SyncSubscriptionGroups|SubscriptionControl|InstallSubscription] [options]
├─ 新人三步走
│ 1. 推荐直连: bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443
│ 2. 推荐 CDN: bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.ibm.com:443
│ 3. 安装后: 运行 padm -> 订阅与用户；未初始化先选主控或被控，主控走 发布订阅 / 多服务器协同，被控走 接入主控 / 查看本机状态
├─ 交互菜单路径
│ 安装与重装: 含新手选择指引，推荐直连/CDN/无域名 Reality、NaiveProxy、自定义安装、传统 TLS 兼容安装
│ 订阅与用户: 按角色切成三态；未初始化先选主控/被控，主控和被控分别进入独立首页
│ 协议与入口: REALITY、XHTTP、Hysteria2、Tuic、入口端口和 CDN 入口
│ 站点与证书: 传统 TLS fallback 站点、302、ALPN 和证书
│ 路由与访问控制: 分流、BT、域名/IP 阻断、直连例外和区域阻断
│ 核心与服务: Xray/sing-box 生命周期、配置校验、服务控制和日志
│ 系统与脚本: 更新 padm、网络优化和宿主机辅助项
├─ 正式子命令
│ bash install.sh InstallSubscription --subscribe-port 39778 --install-nginx yes
│ 仅安装或更新 HTTPS 订阅发布服务，适合自动化验收；需要已有核心协议配置
├─ 关键概念
│ TLS 域名/端口: 普通 TLS 协议入口；当前不作为新人首选，传统 TLS 类协议存在更高识别风险
│ Reality entry: 客户端实际连接地址，通常是自有域名、CDN 入口或服务器 IP
│ Reality target: REALITY 伪装目标站，建议使用真实大型 HTTPS 站点，端口默认 443
│ Reality SNI: REALITY 握手 SNI，默认等于 target host
├─ 常用示例
│ bash install.sh --install-type custom --core xray --protocols 7 --entry-host node.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com
│ bash install.sh --install-type custom --core xray --protocols 12 --entry-host cdn.example.com --reality-target www.ibm.com:443 --reality-server-name www.ibm.com
│ bash install.sh --install-type reality --core xray --reality-target www.ibm.com:443 --reuse-last no
├─ 参数
│ --install-type <install|custom|reality>  安装类型；无自动参数时进入交互菜单；有其它自动参数时默认 custom
│ --core <xray|sing-box|1|2>              安装核心
│ --protocols <ids>                       自定义安装协议编号，例如 0,1,7
│ --domain <domain>                       TLS 域名
│ --port <port>                           TLS 入口端口，默认 443
│ --tls-ca <letsencrypt|zerossl|buypass>  证书 CA，默认 letsencrypt
│ --dns-api <yes|no|y|n>                  是否使用 DNS API 申请证书
│ --dns-api-type <cloudflare|aliyun|1|2>   DNS API 服务商，默认 cloudflare
│ --dns-api-wildcard <yes|no|y|n>          DNS API 是否申请 *.根域名 通配符证书
│ --cloudflare-api-token <token>           Cloudflare API Token，也可用 PADM_CLOUDFLARE_API_TOKEN
│ --cloudflare-zone-id <zone_id>           可选，也可用 PADM_CLOUDFLARE_ZONE_ID
│ --aliyun-api-key <key>                   阿里云 DNS AccessKey ID，也可用 PADM_ALIYUN_API_KEY
│ --aliyun-api-secret <secret>             阿里云 DNS AccessKey Secret，也可用 PADM_ALIYUN_API_SECRET
│ --reuse-last <yes|no|y|n>               是否复用上次安装配置
│ --clean-acme <yes|no|y|n>               清空上次配置时是否清理 acme
│ --reality-domain <yes|no|y|n>           仅选 Reality 时入口是否使用自有域名
│ --reality-target <host[:port]>          REALITY 伪装目标站，默认推荐 www.ibm.com:443
│ --reality-server-name <sni>             REALITY SNI，默认等于 target host
│ --entry-host <host>                     客户端实际连接地址，默认使用 --domain 或公网 IP
│ --subscribe-port <port>                 订阅服务端口
│ --install-nginx <yes|no|y|n>            订阅需要 nginx 时是否自动安装
│ --uuid <uuid>                           初始用户 UUID，默认随机生成
│ --user <name>                           初始用户名，默认随机生成
└──────────────────────────────────────────────────
EOF
}

normalizeYesNo() {
    case "$1" in
    y | Y | yes | YES | Yes | true | TRUE | True | 1)
        printf 'y'
        ;;
    n | N | no | NO | No | false | FALSE | False | 0)
        printf 'n'
        ;;
    *)
        printf 'n'
        ;;
    esac
}

autoConfirm() {
    local key=$1
    local prompt=$2
    local defaultValue=${3:-n}
    local resultVar=$4
    local input=
    local suffix='[y/N]：'

    [[ "$(normalizeYesNo "${defaultValue}")" == "y" ]] && suffix='[Y/n]：'
    autoRead "${key}" "${prompt}${suffix}" input
    if [[ -z "${input}" ]]; then
        input=${defaultValue}
    fi
    printf -v "${resultVar}" '%s' "$(normalizeYesNo "${input}")"
}

autoValueForKey() {
    case "$1" in
    main_menu)
        printf '1'
        ;;
    install_type)
        case "${AUTO_INSTALL_TYPE}" in
        custom | any | 任意组合 | 2)
            printf '5'
            ;;
        reality | reality-only | no-domain-reality | 3)
            printf '3'
            ;;
        install | full | traditional | 1)
            printf '5'
            ;;
        *)
            printf '4'
            ;;
        esac
        ;;
    core)
        case "${AUTO_CORE}" in
        sing-box | singbox | 2)
            printf '2'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    protocols)
        printf '%s' "${AUTO_PROTOCOLS}"
        ;;
    core_init_uuid)
        if [[ -z "${AUTO_UUID:-}" ]]; then
            AUTO_UUID=$(generateRandomUuidValue)
        fi
        printf '%s' "${AUTO_UUID}"
        ;;
    core_init_username)
        if [[ -z "${AUTO_USER:-}" ]]; then
            [[ -n "${AUTO_UUID:-}" ]] || AUTO_UUID=$(generateRandomUuidValue)
            AUTO_USER=$(defaultRandomUserNameFromUuid "${AUTO_UUID}")
        fi
        printf '%s' "${AUTO_USER}"
        ;;
    domain)
        printf '%s' "${AUTO_DOMAIN}"
        ;;
    port | singbox_custom_port | reality_port | xhttp_port)
        printf '%s' "${AUTO_PORT}"
        ;;
    tls_ca)
        case "${AUTO_TLS_CA}" in
        zerossl | ZeroSSL | 2)
            printf '2'
            ;;
        buypass | Buypass | 3)
            printf '3'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    dns_api)
        normalizeYesNo "${AUTO_DNS_API}"
        ;;
    dns_api_type)
        case "${AUTO_DNS_API_TYPE}" in
        aliyun | Aliyun | alibaba | 2)
            printf '2'
            ;;
        *)
            printf '1'
            ;;
        esac
        ;;
    dns_api_wildcard)
        normalizeYesNo "${AUTO_DNS_API_WILDCARD}"
        ;;
    singbox_reinstall | xray_reinstall)
        printf 'y'
        ;;
    core_download_retry)
        printf 'y'
        ;;
    nginx_grpc_reinstall)
        printf 'y'
        ;;
    cloudflare_api_token)
        printf '%s' "${AUTO_CLOUDFLARE_API_TOKEN:-${PADM_CLOUDFLARE_API_TOKEN:-}}"
        ;;
    cloudflare_zone_id)
        printf '%s' "${AUTO_CLOUDFLARE_ZONE_ID:-${PADM_CLOUDFLARE_ZONE_ID:-}}"
        ;;
    aliyun_api_key)
        printf '%s' "${AUTO_ALIYUN_API_KEY:-${PADM_ALIYUN_API_KEY:-}}"
        ;;
    aliyun_api_secret)
        printf '%s' "${AUTO_ALIYUN_API_SECRET:-${PADM_ALIYUN_API_SECRET:-}}"
        ;;
    reuse_last)
        normalizeYesNo "${AUTO_REUSE_LAST}"
        ;;
    clean_acme)
        normalizeYesNo "${AUTO_CLEAN_ACME}"
        ;;
    reality_domain)
        if [[ "$(normalizeYesNo "${AUTO_REALITY_DOMAIN}")" == "y" ]]; then
            printf '2'
        else
            printf '1'
        fi
        ;;
    reality_target)
        printf '%s' "${AUTO_REALITY_TARGET}"
        ;;
    reality_server_name)
        printf '%s' "${AUTO_REALITY_SERVER_NAME}"
        ;;
    entry_host)
        printf '%s' "${AUTO_ENTRY_HOST}"
        ;;
    subscribe_port)
        printf '%s' "${AUTO_SUBSCRIBE_PORT}"
        ;;
    reality_stream_enable)
        normalizeYesNo "${AUTO_REALITY_STREAM_ENABLE}"
        ;;
    reality_stream_domains)
        printf '%s' "${AUTO_REALITY_STREAM_DOMAINS}"
        ;;
    reality_stream_default_protocol)
        printf '%s' "${AUTO_REALITY_STREAM_DEFAULT_PROTOCOL}"
        ;;
    reality_stream_website_port)
        printf '%s' "${AUTO_REALITY_STREAM_WEBSITE_PORT}"
        ;;
    reality_stream_vision_port)
        printf '%s' "${AUTO_REALITY_STREAM_VISION_PORT}"
        ;;
    reality_stream_xhttp_port)
        printf '%s' "${AUTO_REALITY_STREAM_XHTTP_PORT}"
        ;;
    install_nginx)
        normalizeYesNo "${AUTO_INSTALL_NGINX}"
        ;;
    esac
}

generateRandomUuidValue() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        printf '%04x%04x-%04x-%04x-%04x-%04x%04x%04x\n' "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM" "$RANDOM"
    fi
}

defaultRandomUserNameFromUuid() {
    local uuid=${1:-}
    local prefix
    if [[ -z "${uuid}" ]]; then
        uuid=$(generateRandomUuidValue)
    fi
    prefix=${uuid%%-*}
    prefix=${prefix,,}
    printf 'padm-%s\n' "${prefix}"
}

autoReadAllowsEmptyValue() {
    case "$1" in
    port | singbox_custom_port | reality_port | xhttp_port | hysteria_port | tuic_port | reality_target | reality_server_name | entry_host | subscribe_port | cloudflare_zone_id | reality_stream_website_port | reality_stream_vision_port | reality_stream_xhttp_port | hysteria_download_speed | hysteria_upload_speed)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

autoInstallSummaryValue() {
    case "$1" in
    cloudflare_api_token | cloudflare_zone_id | aliyun_api_key | aliyun_api_secret)
        if [[ -n "$2" ]]; then
            printf '********'
        else
            printf '未设置'
        fi
        ;;
    *)
        printf '%s' "${2:-未设置}"
        ;;
    esac
}

showAutoInstallSummary() {
    [[ -n "${AUTO_INSTALL}" ]] || return 0
    [[ -z "${AUTO_INSTALL_SUMMARY_SHOWN:-}" ]] || return 0
    AUTO_INSTALL_SUMMARY_SHOWN=true

    statusCard "自动安装摘要" \
        "安装类型：$(autoInstallSummaryValue install_type "${AUTO_INSTALL_TYPE:-custom}")" \
        "核心：$(autoInstallSummaryValue core "${AUTO_CORE:-xray}")" \
        "协议：$(autoInstallSummaryValue protocols "${AUTO_PROTOCOLS:-默认推荐}")" \
        "UUID：$(autoInstallSummaryValue uuid "${AUTO_UUID:-随机生成}")" \
        "用户名：$(autoInstallSummaryValue user "${AUTO_USER:-随机生成}")" \
        "TLS 域名：$(autoInstallSummaryValue domain "${AUTO_DOMAIN:-未设置}")" \
        "入口地址：$(autoInstallSummaryValue entry_host "${AUTO_ENTRY_HOST:-自动推导}")" \
        "REALITY target：$(autoInstallSummaryValue reality_target "${AUTO_REALITY_TARGET:-默认推荐}")" \
        "订阅端口：$(autoInstallSummaryValue subscribe_port "${AUTO_SUBSCRIBE_PORT:-按安装流程选择}")"
}

formatReadPrompt() {
    case "$1" in
    "请选择:")
        printf '请选择编号：'
        ;;
    "请输入:")
        printf '请输入：'
        ;;
    *)
        printf '%s' "$1"
        ;;
    esac
}

autoRead() {
    local key=$1
    local prompt=$2
    local resultVar=$3
    local value=

    prompt=$(formatReadPrompt "${prompt}")

    if [[ -n "${AUTO_INSTALL}" && ( "${key}" != "install_type" || -n "${AUTO_INSTALL_TYPE}" ) ]]; then
        value=$(autoValueForKey "${key}")
        if [[ -n "${value}" ]]; then
            showAutoInstallSummary
            printf -v "${resultVar}" '%s' "${value}"
            return
        elif autoReadAllowsEmptyValue "${key}"; then
            printf -v "${resultVar}" '%s' ""
            return
        fi
    fi

    read -r -p "${prompt}" "${resultVar}"
}

argumentHasValue() {
    [[ $# -ge 2 && -n "${2}" && "${2}" != -* ]]
}

downloadFileOptionHasValue() {
    [[ $# -ge 3 && -n "${2}" && "${2}" != -* ]]
}

downloadFile() {
    local outputDir=
    local outputFile=
    local url=
    local args=(-c -q)
    local outputParent=
    local outputName=
    local tmpFile=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -P)
            if downloadFileOptionHasValue "$@"; then
                outputDir=$2
                shift 2
            else
                shift
            fi
            ;;
        -O)
            if downloadFileOptionHasValue "$@"; then
                outputFile=$2
                shift 2
            else
                shift
            fi
            ;;
        *)
            url=$1
            shift
            ;;
        esac
    done

    if [[ -n "${wgetShowProgressStatus:-}" ]]; then
        args+=("${wgetShowProgressStatus}")
    fi
    if [[ -n "${outputDir}" ]]; then
        wget "${args[@]}" -P "${outputDir}" "${url}"
    elif [[ -n "${outputFile}" ]]; then
        outputParent=$(dirname -- "${outputFile}")
        outputName=$(basename -- "${outputFile}")
        padmCreateTempPath tmpFile "${outputParent}/.${outputName}.download.XXXXXX" || return 1
        if wget "${args[@]}" -O "${tmpFile}" "${url}" && [[ -s "${tmpFile}" ]]; then
            mv "${tmpFile}" "${outputFile}"
            padmForgetCleanupPath "${tmpFile}"
        else
            padmRemoveCleanupPath "${tmpFile}"
            return 1
        fi
    else
        wget "${args[@]}" "${url}"
    fi
}

fetchUrlToStdout() {
    local url=$1
    local maxAttempts=${2:-3}
    local attempt=1

    while [[ ${attempt} -le ${maxAttempts} ]]; do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsSL --connect-timeout 10 --max-time 30 "${url}"; then
                return 0
            fi
        fi
        if command -v wget >/dev/null 2>&1; then
            if wget -qO- "${url}"; then
                return 0
            fi
        fi
        if [[ ${attempt} -lt ${maxAttempts} ]]; then
            sleep 1
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

validateGitHubReleaseTag() {
    [[ "$1" =~ ^[A-Za-z0-9._+-]{1,128}$ ]]
}

githubReleaseAssetDirectUrl() {
    local repo=$1
    local version=$2
    local assetName=$3
    printf 'https://github.com/%s/releases/download/%s/%s\n' "${repo}" "${version}" "${assetName}"
}

downloadGitHubReleaseAsset() {
    local outputDir=
    local repo=
    local version=
    local assetName=
    local metadata=
    local downloadUrl=
    local digest=
    local outputPath=
    local expectedSha256=
    local actualSha256=
    local usedMetadata=true

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -P)
            if argumentHasValue "$@"; then
                outputDir=$2
                shift 2
            else
                shift
            fi
            ;;
        *)
            if [[ -z "${repo}" ]]; then
                repo=$1
            elif [[ -z "${version}" ]]; then
                version=$1
            else
                assetName=$1
            fi
            shift
            ;;
        esac
    done

    if [[ -z "${outputDir}" || -z "${repo}" || -z "${version}" || -z "${assetName}" ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "下载参数不完整"
        menuClose
        return 1
    fi
    if ! validateGitHubReleaseTag "${version}"; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 版本格式异常: ${version}"
        menuClose
        return 1
    fi
    if [[ "${assetName}" == *"/"* || "${assetName}" == *".."* ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 资产名称异常: ${assetName}"
        menuClose
        return 1
    fi

    mkdir -p "${outputDir}"
    metadata=$(fetchUrlToStdout "https://api.github.com/repos/${repo}/releases/tags/${version}" 3 | jq -c --arg name "${assetName}" '.assets[]? | select(.name == $name) | {url:.browser_download_url, digest:(.digest // "")}' | head -1) || metadata=
    if [[ -n "${metadata}" ]]; then
        downloadUrl=$(jq -r '.url // empty' <<<"${metadata}" 2>/dev/null)
        digest=$(jq -r '.digest // empty' <<<"${metadata}" 2>/dev/null)
    fi
    if [[ -z "${downloadUrl}" ]]; then
        usedMetadata=false
        downloadUrl=$(githubReleaseAssetDirectUrl "${repo}" "${version}" "${assetName}")
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "Release 元数据暂不可用，已回退直链下载: ${assetName}"
        menuClose
    fi
    outputPath="${outputDir%/}/${assetName}"
    if ! downloadFile -P "${outputDir}" "${downloadUrl}"; then
        return 1
    fi
    if [[ "${digest}" == sha256:* ]]; then
        if ! command -v sha256sum >/dev/null 2>&1; then
            echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
            menuLine "缺少 sha256sum，无法校验下载文件"
            menuClose
            return 1
        fi
        expectedSha256=${digest#sha256:}
        actualSha256=$(sha256sum "${outputPath}" | awk '{print $1}')
        if [[ "${actualSha256}" != "${expectedSha256}" ]]; then
            echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
            menuLine "下载文件 sha256 校验失败: ${assetName}"
            menuClose
            rm -f "${outputPath}"
            return 1
        fi
        echoContent title "\n┌─ GitHub Release 校验 ──────────────────────────────"
        menuLine "sha256 校验通过: ${assetName}"
        menuClose
    elif [[ "${usedMetadata}" == "true" ]]; then
        echoContent title "\n┌─ GitHub Release 下载 ──────────────────────────────"
        menuLine "GitHub 未提供 sha256 digest，已完成精确资产匹配下载: ${assetName}"
        menuClose
    fi
}

# 初始化安装目录
mkdirTools() {
    local dir status=0
    local dirs=(
        /etc/padm/tls
        /etc/padm/subscribe_local/default
        /etc/padm/subscribe_local/clashMeta
        /etc/padm/subscribe_remote/default
        /etc/padm/subscribe_remote/clashMeta
        /etc/padm/subscribe/default
        /etc/padm/subscribe/clashMetaProfiles
        /etc/padm/subscribe/clashMeta
        /etc/padm/subscribe/sing-box
        /etc/padm/subscribe/sing-box_profiles
        /etc/padm/subscribe_local/sing-box
        /etc/padm/xray/conf
        /etc/padm/xray/reality_scan
        /etc/padm/xray/tmp
        /etc/systemd/system/
        "$(padmTmpFilePath padm-tls)"
        /etc/padm/warp
        /etc/padm/sing-box/conf/config
        /usr/share/nginx/html/
    )
    for dir in "${dirs[@]}"; do
        mkdir -p "${dir}" || status=1
    done
    return "${status}"
}

# 检查 root 权限
checkRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        echoContent red "\n请使用 Root 用户执行脚本"
        exit 1
    fi
}

# 安全执行命令并限制超时
runWithTimeout() {
    local timeoutSeconds=$1
    shift
    local commandString="$*"
    local maxAttempts=1
    local attempt=1
    local status=0

    if [[ "${release}" == "ubuntu" || "${release}" == "debian" ]] && [[ "${commandString}" =~ (apt-get|dpkg) ]]; then
        maxAttempts=3
    fi

    while [[ ${attempt} -le ${maxAttempts} ]]; do
        if [[ ${maxAttempts} -gt 1 ]]; then
            waitAptProcess
        fi

        if command -v timeout >/dev/null 2>&1; then
            timeout "${timeoutSeconds}s" bash -lc "${commandString}"
            status=$?
        else
            bash -lc "${commandString}"
            status=$?
        fi

        if [[ ${status} -eq 0 ]]; then
            return 0
        fi

        if [[ ${attempt} -lt ${maxAttempts} ]]; then
            echoContent title "\n┌─ 软件包命令重试 ───────────────────────────────────"
            menuLine "软件包命令执行失败，等待后重试 (${attempt}/${maxAttempts})"
            menuClose
            sleep 5
        fi
        attempt=$((attempt + 1))
    done

    return ${status}
}

# 等待 apt/dpkg 进程结束
waitAptProcess() {
    if [[ "${release}" != "ubuntu" && "${release}" != "debian" ]]; then
        return
    fi

    local waitCount=0
    local lockFiles=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
    while true; do
        local lockPids=
        lockPids=$(lsof -t "${lockFiles[@]}" 2>/dev/null | sort -u | tr '\n' ' ')
        if [[ -z "${lockPids// }" ]]; then
            return
        fi

        if [[ ${waitCount} -ge 36 ]]; then
            echoContent title "\n┌─ apt/dpkg 锁占用 ─────────────────────────────────"
            menuLine "检测到 apt/dpkg 锁仍在占用，请等待系统软件包任务结束后重新执行脚本"
            menuLine "占用锁的进程: ${lockPids}"
            menuClose
            exit 1
        fi

        if [[ ${waitCount} == 0 ]]; then
            echoContent title "\n┌─ apt/dpkg 锁等待 ─────────────────────────────────"
            menuLine "检测到 apt/dpkg 锁正在占用，等待其结束"
            menuClose
        fi

        sleep 5
        waitCount=$((waitCount + 1))
    done
}

padmIsSafeAbsolutePath() {
    local targetPath=$1
    if [[ -z "${targetPath}" || "${targetPath}" != /* || "${targetPath}" == "/" ||
        "${targetPath}" == "/." || "${targetPath}" == "/.." ||
        "${targetPath}" == */./* || "${targetPath}" == */. ||
        "${targetPath}" == */../* || "${targetPath}" == */.. ]]; then
        return 1
    fi
}

padmShowUnsafePathError() {
    local title=$1
    echoContent title "\n┌─ ${title} ─────────────────────────────────────────"
    menuLine "目标路径异常，已终止"
    menuClose
}

# 安全清理目录内容
cleanDirectoryContent() {
    local targetPath=$1
    local resolvedPath
    if ! padmIsSafeAbsolutePath "${targetPath}"; then
        padmShowUnsafePathError "清理目录"
        return 1
    fi
    mkdir -p "${targetPath}" || return 1
    resolvedPath=$(cd -- "${targetPath}" && pwd -P) || return 1
    if [[ -z "${resolvedPath}" || "${resolvedPath}" == "/" ]]; then
        padmShowUnsafePathError "清理目录"
        return 1
    fi
    find "${resolvedPath}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
}


# 检查版本号
checkVersionNotEmpty() {
    if [[ -z "$1" || "$1" == "null" ]]; then
        echoContent title "\n┌─ 版本获取 ─────────────────────────────────────────"
        menuLine "获取版本失败，请稍后重试"
        menuClose
        exit 1
    fi
}


# 初始化随机字符串
initRandomPath() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..4}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    customPath=${initCustomPath}
}


# 生成随机数
randomNum() {
    if [[ "${release}" == "alpine" ]]; then
        local ranNum=
        ranNum="$(shuf -i "$1"-"$2" -n 1)"
        echo "${ranNum}"
    else
        echo $((RANDOM % ($2 - $1 + 1) + $1))
    fi
}
