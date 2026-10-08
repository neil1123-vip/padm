#!/usr/bin/env bash

if [[ "${PADM_DOCKER_RENEWAL_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_RENEWAL_LOADED=1
readonly PADM_DOCKER_RENEWAL_SCHEMA=3
DOCKER_RENEWAL_STAGE=
DOCKER_RENEWAL_DOMAIN=
DOCKER_RENEWAL_SWITCHED=0

dockerRenewalCredentialsValidate() {
    local file=$1 line name count=0
    local -A seen=()
    [[ -f "${file}" && ! -L "${file}" ]] && dockerPrivateFileIsRestricted "${file}" || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line=${line%$'\r'}
        [[ -n "${line}" && "${line}" != \#* ]] || continue
        [[ "${line}" == *=* ]] || return 1
        name=${line%%=*}
        [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
        case "${name}" in
        PATH|HOME|ENV|BASH_ENV|IFS|SHELLOPTS|BASHOPTS|CDPATH|GLOBIGNORE|PS4|DEBUG|TMPDIR|PYTHON*|LD_*|PADM_*|LE_*|ACME_*|Le_*) return 1 ;;
        esac
        [[ -z "${seen[${name}]:-}" ]] || return 1
        seen[${name}]=1
        count=$((count + 1))
    done <"${file}"
    [[ "${count}" -gt 0 ]]
}

dockerRenewalRegistryValidate() {
    local directory=$1 entry domain request provider
    [[ ! -L "${directory}" ]] || return 1
    [[ -e "${directory}" ]] || return 0
    [[ -d "${directory}" && "$(stat -c '%u:%g:%a' "${directory}")" == 0:0:700 ]] || return 1
    while IFS= read -r entry; do
        domain=${entry##*/}
        dockerDomainIsValid "${domain}" &&
            [[ -d "${entry}" && ! -L "${entry}" && "$(stat -c '%u:%g:%a' "${entry}")" == 0:0:700 ]] ||
            return 1
        request="${entry}/request.json"
        [[ -f "${request}" && ! -L "${request}" &&
            "$(stat -c '%u:%g:%a' "${request}")" == 0:0:600 ]] || return 1
        jq -es --arg domain "${domain}" '
          length == 1 and (.[0] |
            type == "object" and keys == ["domain","email","enabled","provider","schema_version"] and
            .domain == $domain and
            (.enabled | type == "boolean") and (.email | type == "string") and
            (.provider | type == "string") and
            ((.schema_version == 1 and (.provider | test("^dns_[a-z0-9_]+$"))) or
              (.schema_version == 2 and .provider == "standalone") or
              (.schema_version == 3 and .provider == "webroot")))
        ' "${request}" >/dev/null 2>&1 &&
            dockerEmailIsValid "$(jq -r '.email' "${request}")" || return 1
        provider=$(jq -r '.provider' "${request}") || return 1
        if [[ "${provider}" == standalone || "${provider}" == webroot ]]; then
            [[ "$(find "${entry}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]] || return 1
        else
            [[ "$(find "${entry}" -mindepth 1 -maxdepth 1 | wc -l)" -eq 2 &&
                "$(stat -c '%u:%g:%a' "${entry}/credentials.env")" == 0:0:600 ]] &&
                dockerRenewalCredentialsValidate "${entry}/credentials.env" || return 1
        fi
    done < <(find "${directory}" -mindepth 1 -maxdepth 1 -print)
}

dockerRenewalEnabled() {
    local directory=$1 file
    [[ -d "${directory}" ]] || return 1
    while IFS= read -r file; do
        jq -e '.enabled == true' "${file}" >/dev/null && return 0
    done < <(find "${directory}" -mindepth 2 -maxdepth 2 -name request.json -print)
    return 1
}

dockerRenewalBundleCheck() {
    local bundle=$1 root registry request schema=1 enabledSchema bundleSchema
    root=$(dockerInstallRoot) || return 1
    registry="${root}/secrets/renewal"
    dockerTrafficSafePath "${root}" "${registry}" &&
        dockerRenewalRegistryValidate "${registry}" || return 1
    dockerRenewalEnabled "${registry}" || return 0
    while IFS= read -r request; do
        enabledSchema=$(jq -r 'if .enabled == true then .schema_version else 0 end' "${request}") || return 1
        [[ "${enabledSchema}" -le "${schema}" ]] || schema=${enabledSchema}
    done < <(find "${registry}" -mindepth 2 -maxdepth 2 -name request.json -print)
    [[ -f "${bundle}/docker/lib/renewal.sh" && ! -L "${bundle}/docker/lib/renewal.sh" ]] &&
        bundleSchema=$(sed -nE 's/^readonly PADM_DOCKER_RENEWAL_SCHEMA=([1-9][0-9]{0,5})$/\1/p' "${bundle}/docker/lib/renewal.sh") &&
        [[ "${bundleSchema}" =~ ^[1-9][0-9]{0,5}$ && "${bundleSchema}" -ge "${schema}" ]] || {
        dockerError '目标控制 bundle 不支持已启用的续期输入，请先停用自动续期或选择兼容版本'
        return 1
    }
}

dockerRenewalAccountCheck() {
    local root=$1 domain=$2 provider=$3 directory config webroot=$3
    dockerTrafficSafePath "${root}" "${root}/data/acme" || return 1
    case "${provider}" in
    standalone) webroot=no ;;
    webroot)
        webroot=/var/lib/padm/acme-webroot
        dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
            [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] &&
            jq -es --arg domain "${domain}" '
              length == 1 and (.[0] |
              .schema_version == 3 and .tls.http01 == true and .tls.domain == $domain and
              any(.core.protocols[];
                .id == 21 or .id == 22 or .id == 23 or .id == 24 or .id == 25 or .id == 27 or .id == 29))
            ' "${root}/config/spec.json" >/dev/null 2>&1 || {
            dockerError 'webroot 自动续期需要当前 TLS 域名已显式启用受管 Nginx HTTP-01 入口'
            return 1
        }
        ;;
    esac
    # 与 ACME 调用保持一致：有 RSA 账户就只校验 RSA，否则才选 ECC。
    for directory in "${root}/data/acme/${domain}" "${root}/data/acme/${domain}_ecc"; do
        config="${directory}/${domain}.conf"
        [[ -e "${config}" || -L "${config}" ]] || continue
        dockerTrafficSafePath "${root}" "${config}" &&
            [[ -f "${config}" && ! -L "${config}" &&
                "$(grep -c '^Le_Domain=' "${config}")" == 1 &&
                "$(grep -c '^Le_Webroot=' "${config}")" == 1 ]] &&
            grep -qxF "Le_Domain='${domain}'" "${config}" &&
            grep -qxF "Le_Webroot='${webroot}'" "${config}" && return 0
        break
    done
    dockerError '该域名没有匹配验证方式的受管 ACME 账户，请先完成 ACME 申请'
    return 1
}

dockerAcmeWebrootTransitionValidate() {
    local candidate=$1 root oldSpec oldEnabled oldDomain newEnabled=false newDomain= request registry
    [[ -n "${candidate}" && ! -L "${candidate}" &&
        ( ! -e "${candidate}" || -f "${candidate}" ) ]] || return 1
    root=$(dockerInstallRoot) || return 1
    oldSpec="${root}/config/spec.json"
    dockerTrafficSafePath "${root}" "${oldSpec}" || return 1
    [[ -e "${oldSpec}" || -L "${oldSpec}" ]] || return 0
    [[ -f "${oldSpec}" && ! -L "${oldSpec}" ]] || return 1
    oldEnabled=$(jq -rs 'if length == 1 and (.[0] | type == "object") then .[0].tls.http01 == true
      else error("不是完整受管规格") end' "${oldSpec}") || return 1
    [[ "${oldEnabled}" == true ]] || return 0
    oldDomain=$(jq -r '.tls.domain // empty' "${oldSpec}") || return 1
    dockerDomainIsValid "${oldDomain}" || return 1
    # 早期回滚快照没有 spec，等同关闭入口；仍须经过现有续期登记保护。
    if [[ -f "${candidate}" ]]; then
        newEnabled=$(jq -rs 'if length == 1 and (.[0] | type == "object") then .[0].tls.http01 == true
          else error("不是完整受管规格") end' "${candidate}") || return 1
        newDomain=$(jq -r '.tls.domain // empty' "${candidate}") || return 1
    fi
    [[ "${newEnabled}" == true && "${newDomain}" == "${oldDomain}" ]] && return 0
    registry="${root}/secrets/renewal"
    dockerTrafficSafePath "${root}" "${registry}" &&
        dockerRenewalRegistryValidate "${registry}" || {
        dockerError '自动续期登记不安全，不能关闭或迁移 HTTP-01 入口'
        return 1
    }
    request="${registry}/${oldDomain}/request.json"
    if [[ -f "${request}" ]] &&
        jq -e '.enabled == true and .provider == "webroot"' "${request}" >/dev/null; then
        dockerError '当前域名仍启用 webroot 自动续期，请先停用自动续期再关闭或迁移 HTTP-01 入口'
        return 1
    fi
    return 0
}

dockerRenewalInterrupted() {
    local root stage=${DOCKER_RENEWAL_STAGE:-} target
    [[ -n "${stage}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${stage}" &&
        [[ "${stage}" == "${root}/locks/renewal."* && -d "${stage}" && -O "${stage}" &&
            -z "$(find "${stage}" ! -type f ! -type d -print -quit)" ]] || return 1
    if [[ "${DOCKER_RENEWAL_SWITCHED:-0}" == 1 ]]; then
        dockerDomainIsValid "${DOCKER_RENEWAL_DOMAIN}" || return 1
        target="${root}/secrets/renewal/${DOCKER_RENEWAL_DOMAIN}"
        dockerTrafficSafePath "${root}" "${target}" || return 1
        dockerRemoveManagedTree "${root}" "${target}" || return 1
        if [[ -d "${stage}/previous" ]]; then
            mv -- "${stage}/previous" "${target}" || return 1
        fi
        DOCKER_RENEWAL_SWITCHED=0
    fi
    dockerRemoveManagedTree "${root}" "${stage}" || return 1
    DOCKER_RENEWAL_STAGE=
    DOCKER_RENEWAL_DOMAIN=
}

dockerRenewalChange() {
    local action=$1 domain=$2 email=${3:-} provider=${4:-} credentials=${5:-}
    local root registry stage target existed=0 status=0 schema=1 remove=0
    root=$(dockerInstallRoot) || return 1
    registry="${root}/secrets/renewal"
    dockerTrafficSafePath "${root}" "${registry}" &&
        dockerRenewalRegistryValidate "${registry}" || return 1
    if [[ "${action}" == enable ]]; then
        dockerTrafficScheduleCheck &&
            dockerResolveOpsImage >/dev/null || return 1
        if [[ "${provider}" == standalone || "${provider}" == webroot ]]; then
            [[ -z "${credentials}" ]] || return 1
            if [[ "${provider}" == webroot ]]; then schema=3; else schema=2; fi
        else
            dockerRenewalCredentialsValidate "${credentials}" || return 1
        fi
        dockerTrafficSafePath "${root}" "${root}/secrets/tls/${domain}.crt" &&
            dockerTrafficSafePath "${root}" "${root}/secrets/tls/${domain}.key" &&
            [[ -f "${root}/secrets/tls/${domain}.crt" && -f "${root}/secrets/tls/${domain}.key" ]] || {
            dockerError '自动续期需要已存在的受管证书与 ACME 账户'
            return 1
        }
        dockerRenewalAccountCheck "${root}" "${domain}" "${provider}" || return 1
    fi
    stage=$(mktemp -d "${root}/locks/renewal.XXXXXX") || return 1
    DOCKER_RENEWAL_STAGE=${stage}
    DOCKER_RENEWAL_DOMAIN=${domain}
    target="${registry}/${domain}"
    mkdir -p -- "${registry}" || return 1
    chmod 0700 "${registry}" || return 1
    if [[ -e "${target}" ]]; then
        existed=1
        cp -a -- "${target}" "${stage}/previous" || return 1
    fi
    mkdir -- "${stage}/next" || return 1
    if [[ "${action}" == enable ]]; then
        if [[ "${provider}" != standalone && "${provider}" != webroot ]]; then
            cp -- "${credentials}" "${stage}/next/credentials.env" || status=1
        fi
        jq -n --arg domain "${domain}" --arg email "${email}" --arg provider "${provider}" --argjson schema "${schema}" '
          {schema_version:$schema,domain:$domain,email:$email,provider:$provider,enabled:true}
        ' >"${stage}/next/request.json" || status=1
    else
        if [[ "${existed}" == 0 ]]; then
            dockerRenewalInterrupted || return 1
            return 0
        fi
        if jq -e '.provider == "standalone" or .provider == "webroot"' "${target}/request.json" >/dev/null; then
            remove=1
        else
            cp -- "${target}/credentials.env" "${stage}/next/credentials.env" || status=1
            jq '.enabled = false' "${target}/request.json" >"${stage}/next/request.json" || status=1
        fi
    fi
    chmod 0700 "${stage}/next" &&
        { [[ "${remove}" == 1 ]] || chmod 0600 "${stage}/next/"*; } &&
        chown -R 0:0 "${stage}" && chown 0:0 "${registry}" || status=1
    if [[ "${status}" == 0 ]]; then
        DOCKER_RENEWAL_SWITCHED=1
        if [[ "${existed}" == 1 ]]; then dockerRemoveManagedTree "${root}" "${target}" || status=1; fi
        if [[ "${status}" == 0 && "${remove}" == 0 ]]; then mv -- "${stage}/next" "${target}" || status=1; fi
        dockerRenewalRegistryValidate "${registry}" || status=1
    fi
    if [[ "${status}" == 0 ]] && dockerRenewalScheduleInstall; then
        dockerRenewalScheduleCommit || return 1
        DOCKER_RENEWAL_SWITCHED=0
        dockerRenewalInterrupted
        return $?
    fi
    dockerRenewalScheduleInterrupted &&
        dockerRenewalInterrupted || dockerError "续期输入或调度恢复失败，请检查: ${stage}"
    return 1
}

dockerRenewalRun() {
    local root registry request domain email provider credentials image status=0 result
    root=$(dockerInstallRoot) || return 1
    registry="${root}/secrets/renewal"
    dockerTrafficSafePath "${root}" "${registry}" &&
        dockerRenewalRegistryValidate "${registry}" || return "${PADM_DOCKER_RC_STATE}"
    dockerRenewalEnabled "${registry}" || return 0
    image=$(dockerResolveOpsImage) || return "${PADM_DOCKER_RC_STATE}"
    while IFS= read -r request; do
        jq -e '.enabled == true' "${request}" >/dev/null || continue
        domain=$(jq -r '.domain' "${request}")
        email=$(jq -r '.email' "${request}")
        provider=$(jq -r '.provider' "${request}")
        credentials=
        [[ "${provider}" == standalone || "${provider}" == webroot ]] || credentials="${request%/*}/credentials.env"
        dockerRenewalAccountCheck "${root}" "${domain}" "${provider}" || {
            status=${PADM_DOCKER_RC_STATE}
            continue
        }
        if dockerAcmeApply renew "${domain}" "${email}" "${provider}" "${credentials}" "${image}"; then
            result=0
        else
            result=$?
        fi
        if [[ "${result}" != 0 && "${result}" != 2 ]]; then
            dockerError "自动续期失败: ${domain}；旧证书和账户已保留"
            status=${PADM_DOCKER_RC_STATE}
        fi
        # 恢复失败时保留当前事务，不启动下一域名覆盖恢复点。
        [[ "${DOCKER_TLS_SWITCHED:-0}" != 1 ]] || return "${PADM_DOCKER_RC_STATE}"
        [[ "${#DOCKER_ACME_STOPPED[@]}" == 0 && -z "${DOCKER_ACME_CONTAINER:-}" &&
            -z "${DOCKER_ACME_WEBROOT:-}" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerCleanupTlsCandidate || return "${PADM_DOCKER_RC_STATE}"
    done < <(find "${registry}" -mindepth 2 -maxdepth 2 -name request.json -print | LC_ALL=C sort)
    return "${status}"
}

dockerRenewalCommand() {
    local action=${1:-status} domain= email= provider= credentials= root registry request
    [[ "$#" -eq 0 ]] || shift
    case "${action}" in
    enable|disable)
        while [[ "$#" -gt 0 ]]; do
            if [[ "$1" == --standalone || "$1" == --webroot ]]; then
                [[ "${action}" == enable && -z "${provider}" ]] || return "${PADM_DOCKER_RC_USAGE}"
                provider=${1#--}
                shift
                continue
            fi
            [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --domain) domain=$2 ;;
            --email) [[ "${action}" == enable ]] || return "${PADM_DOCKER_RC_USAGE}"; email=$2 ;;
            --dns) [[ "${action}" == enable && -z "${provider}" && "$2" =~ ^dns_[a-z0-9_]+$ ]] || return "${PADM_DOCKER_RC_USAGE}"; provider=$2 ;;
            --credentials) [[ "${action}" == enable ]] || return "${PADM_DOCKER_RC_USAGE}"; credentials=$2 ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
            shift 2
        done
        dockerDomainIsValid "${domain}" || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${action}" == enable ]]; then
            dockerEmailIsValid "${email}" || return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${provider}" == standalone || "${provider}" == webroot ]]; then
                [[ -z "${credentials}" ]] || return "${PADM_DOCKER_RC_USAGE}"
            else
                [[ "${provider}" =~ ^dns_[a-z0-9_]+$ ]] || return "${PADM_DOCKER_RC_USAGE}"
                credentials=$(dockerResolveRegularFile "${credentials}") || return "${PADM_DOCKER_RC_USAGE}"
            fi
        fi
        ;;
    status|run) [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}" ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    registry="${root}/secrets/renewal"
    dockerTrafficSafePath "${root}" "${registry}" &&
        dockerRenewalRegistryValidate "${registry}" || return "${PADM_DOCKER_RC_STATE}"
    case "${action}" in
    run) dockerRenewalRun ;;
    enable|disable)
        dockerRenewalChange "${action}" "${domain}" "${email}" "${provider}" "${credentials}" ||
            return "${PADM_DOCKER_RC_STATE}"
        printf '自动续期 %s: %s\n' "${action}" "${domain}"
        ;;
    status)
        [[ -d "${registry}" ]] || { printf '自动续期未启用\n'; return 0; }
        while IFS= read -r request; do
            jq -r '"domain=\(.domain) enabled=\(.enabled) provider=\(.provider)"' "${request}" || return 1
        done < <(find "${registry}" -mindepth 2 -maxdepth 2 -name request.json -print | LC_ALL=C sort)
        ;;
    esac
}
