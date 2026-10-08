#!/usr/bin/env bash

if [[ "${PADM_DOCKER_ACCOUNTS_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_ACCOUNTS_LOADED=1
dockerAccountSpecFile() {
    local root
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return 1
    [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" &&
        -O "${root}/config/spec.json" ]] || {
        dockerError 'Docker 服务尚未配置账号规格，请先完成 configure'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerPrivateFileIsRestricted "${root}/config/spec.json" || {
        dockerError '账号规格权限不安全'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureSpecValidate "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    printf '%s\n' "${root}/config/spec.json"
}

dockerAccountIdIsValid() {
    [[ "$1" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]]
}

dockerAccountNameIsValid() {
    jq -en --arg value "$1" '
      ($value | type == "string" and length >= 1 and length <= 64 and
        (explode | all(. >= 32 and . != 127)))
    ' >/dev/null 2>&1
}

dockerAccountImage() {
    local name=$1 root value count key
    root=$(dockerInstallRoot) || return 1
    case "${name}" in
    xray) key=XRAY ;;
    ops) key=OPS ;;
    sing-box) key=SINGBOX ;;
    *) return 1 ;;
    esac
    if [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]]; then
        count=$(grep -c "^PADM_${key}_IMAGE=" "${root}/images.env" 2>/dev/null || true)
        [[ "${count}" == 1 ]] || return 1
        value=$(sed -n "s/^PADM_${key}_IMAGE=//p" "${root}/images.env") || return 1
        dockerImageReferenceIsValid "${value}" || return 1
        printf '%s\n' "${value}"
        return 0
    fi
    # 测试桩可提供镜像占位符；正式调用在复用已安装发布后一定走 images.env。
    declare -F dockerManifestImageReference >/dev/null 2>&1 &&
        value=$(dockerManifestImageReference "${name}" 2>/dev/null) &&
        [[ -n "${value}" ]] && printf '%s\n' "${value}"
}

dockerAccountRandomUuid() {
    local specFile=$1 excluded=${2:-} image value attempt
    image=$(dockerAccountImage xray) || return 1
    for attempt in {1..32}; do
        value=$(dockerSetupTool "${image}" uuid 2>/dev/null) || continue
        dockerAccountIdIsValid "${value}" || continue
        [[ -z "${excluded}" || "${value}" != "${excluded}" ]] || continue
        jq -e --arg value "${value}" '
          (any(.core.protocols[]; .uuid == $value) | not) and
          (any((.accounts // [])[]; .id == $value or .uuid == $value) | not)
        ' "${specFile}" >/dev/null 2>&1 || continue
        printf '%s\n' "${value}"
        return 0
    done
    dockerError '无法生成不冲突的账号 UUID'
    return 1
}

dockerAccountRandomPassword() {
    local specFile=$1 image value attempt
    image=$(dockerAccountImage ops) || return 1
    for attempt in {1..32}; do
        value=$(dockerSetupRandomHex "${image}" 24 2>/dev/null) || continue
        [[ "${value}" =~ ^[A-Fa-f0-9]{16,128}$ ]] || continue
        jq -e --arg value "${value}" '
          (any(.core.protocols[]; .uuid == $value) | not) and
          (any((.accounts // [])[]; .password == $value) | not)
        ' "${specFile}" >/dev/null 2>&1 || continue
        printf '%s\n' "${value}"
        return 0
    done
    dockerError '无法生成不冲突的账号密码'
    return 1
}

dockerAccountRandomSsPassword() {
    local image=$1 value
    image=${image:-$(dockerAccountImage ops)} || return 1
    value=$(docker run --rm --read-only --network none --cap-drop ALL \
        --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint openssl "${image}" rand -base64 16 2>/dev/null | tr -d '\r\n') || value=
    if [[ ! "${value}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ ]] && command -v openssl >/dev/null 2>&1; then
        value=$(openssl rand -base64 16 2>/dev/null | tr -d '\r\n') || value=
    fi
    [[ "${value}" =~ ^[A-Za-z0-9+/]{21}[AQgw]==$ ]] || return 1
    printf '%s\n' "${value}"
}

dockerAccountListenersJson() {
    local specFile=$1 raw=${2-} listeners
    if [[ -z "${raw}" ]]; then
        jq -c '[.core.protocols[].listener_id]' "${specFile}"
        return
    fi
    [[ "${raw}" != *,,* && "${raw}" != ,* && "${raw}" != *, &&
        "${raw}" != *[[:space:]]* ]] || return 1
    listeners=$(jq -cn --arg raw "${raw}" '
      ($raw | split(",")) as $items |
      if ($items | length) >= 1 and
         ($items | unique | length) == ($items | length) and
         all($items[]; test("^entry-[a-z0-9][a-z0-9-]{0,47}$"))
      then $items else error("invalid listeners") end
    ') || return 1
    jq -e --argjson listeners "${listeners}" '
      . as $spec |
      all($listeners[]; . as $id | any($spec.core.protocols[]; .listener_id == $id))
    ' "${specFile}" >/dev/null 2>&1 || return 1
    printf '%s\n' "${listeners}"
}

dockerAccountListenersNeedSs() {
    local specFile=$1 listeners=$2
    jq -e --argjson listeners "${listeners}" '
      any(.core.protocols[];
        .id == 30 and (.listener_id as $id | (($listeners | index($id)) != null)))
    ' "${specFile}" >/dev/null 2>&1
}

dockerAccountFind() {
    local specFile=$1 accountId=$2
    dockerAccountIdIsValid "${accountId}" || return 1
    jq -e --arg id "${accountId}" 'any((.accounts // [])[]; .id == $id)' \
        "${specFile}" >/dev/null 2>&1
}

dockerAccountRequireLocal() {
    jq -e --arg id "$2" '
      any(.control_sync.managed_accounts[]?; .id == $id) | not
    ' "$1" >/dev/null 2>&1 || {
        dockerError '该账号归主控管理，请在主控修改后同步'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
}

dockerAccountConfirm() {
    local action=$1 accountId=$2 confirmed=${3:-0} answer
    if [[ "${confirmed}" == 1 || "${DOCKER_ACCOUNT_CONFIRM:-0}" == 1 ]]; then
        return 0
    fi
    [[ -t 0 && -t 1 ]] || {
        dockerError "${action} 需要 --yes 确认"
        return "${PADM_DOCKER_RC_USAGE}"
    }
    dockerSetupRead answer "${action} 账号 ${accountId}？[y/N]: " n || return "${PADM_DOCKER_RC_USAGE}"
    case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
}

dockerAccountApplyDraft() {
    local sourceSpec=$1
    dockerConfigureReleaseReuseInstalled || return $?
    dockerConfigureSpecValidate "${sourceSpec}" || return "${PADM_DOCKER_RC_STATE}"
    dockerConfigureApply "${sourceSpec}"
}

dockerAccountMutate() {
    local transform=$1 specFile draft root status=0
    shift
    specFile=$(dockerAccountSpecFile) || return $?
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    draft=$(mktemp "${root}/.account.XXXXXX.json") || {
        dockerError '无法创建账号变更草稿'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerManagedPathIsSafe "${root}" "${draft}" || {
        rm -f -- "${draft}"
        return "${PADM_DOCKER_RC_STATE}"
    }
    chmod 0600 "${draft}" || {
        rm -f -- "${draft}"
        return "${PADM_DOCKER_RC_STATE}"
    }
    if ! jq "$@" "$transform" "${specFile}" >"${draft}"; then
        dockerError '账号变更参数无效'
        status=${PADM_DOCKER_RC_USAGE}
    else
        dockerAccountApplyDraft "${draft}" || status=$?
    fi
    rm -f -- "${draft}" || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    DOCKER_STAGED_BUNDLE_PATH=
    DOCKER_CONFIG_RELEASE_INPUTS=
    return "${status}"
}

dockerAccountList() {
    local json=${1:-0} specFile
    specFile=$(dockerAccountSpecFile) || return $?
    if ((json)); then
        jq -c '[.accounts[]? | del(.uuid, .password, .shadowsocks_password)]' "${specFile}"
    else
        jq -r '(.accounts // [])[] |
          [ .id, .name, (if .enabled then "enabled" else "disabled" end), (.listeners | join(",")) ] |
          @tsv' "${specFile}"
    fi
}

dockerAccountPrintCredentials() {
    local action=$1 id=$2 uuid=$3 password=$4 ss=${5:-null}
    printf '账号%s成功\nid=%s\nuuid=%s\npassword=%s\n' "${action}" "${id}" "${uuid}" "${password}"
    [[ "${ss}" == null ]] || printf 'shadowsocks_password=%s\n' "${ss}"
}

dockerAccountCommand() {
    local action=${1:-} specFile accountId name listenersRaw listeners enabled=1 json=0
    local sourceId id uuid password ssPassword yes=0 arg seenName=0 seenListeners=0 status
    shift || true
    case "${action}" in
    list)
        while [[ "$#" -gt 0 ]]; do
            [[ "$1" == --json && "${json}" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            json=1
            shift
        done
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        dockerAccountList "${json}"
        ;;
    create)
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
            --name)
                [[ "${seenName}" -eq 0 && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                name=$2; seenName=1; shift 2 ;;
            --listeners)
                [[ "${seenListeners}" -eq 0 && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                listenersRaw=$2; seenListeners=1; shift 2 ;;
            --disabled)
                [[ "${enabled}" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
                enabled=0; shift ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        done
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        specFile=$(dockerAccountSpecFile) || return $?
        listeners=$(dockerAccountListenersJson "${specFile}" "${listenersRaw-}") || {
            dockerError '入口 ID 列表无效'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        uuid=$(dockerAccountRandomUuid "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
        sourceId=$(dockerAccountRandomUuid "${specFile}" "${uuid}") || return "${PADM_DOCKER_RC_STATE}"
        password=$(dockerAccountRandomPassword "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
        if dockerAccountListenersNeedSs "${specFile}" "${listeners}"; then
            ssPassword=$(dockerAccountRandomSsPassword) || return "${PADM_DOCKER_RC_STATE}"
        else
            ssPassword=null
        fi
        dockerAccountNameIsValid "${name:-account-${sourceId:0:8}}" || return "${PADM_DOCKER_RC_USAGE}"
        [[ -n "${name}" ]] || name="account-${sourceId:0:8}"
        dockerAccountMutate \
            '.accounts += [{id:$id,name:$name,enabled:$enabled,uuid:$uuid,password:$password,
              shadowsocks_password:(if $ss == "null" then null else $ss end),listeners:$listeners}]' \
            --arg id "${sourceId}" --arg name "${name}" --argjson enabled "$([[ "${enabled}" -eq 1 ]] && printf true || printf false)" \
            --arg uuid "${uuid}" --arg password "${password}" --arg ss "${ssPassword}" --argjson listeners "${listeners}" ||
            return $?
        dockerAccountPrintCredentials 创建 "${sourceId}" "${uuid}" "${password}" "${ssPassword}"
        ;;
    edit|copy)
        [[ "$#" -ge 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        sourceId=$1
        dockerAccountIdIsValid "${sourceId}" || return "${PADM_DOCKER_RC_USAGE}"
        shift
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
            --name)
                [[ "${seenName}" -eq 0 && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                name=$2; seenName=1; shift 2 ;;
            --listeners)
                [[ "${seenListeners}" -eq 0 && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                    return "${PADM_DOCKER_RC_USAGE}"
                listenersRaw=$2; seenListeners=1; shift 2 ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        done
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        specFile=$(dockerAccountSpecFile) || return $?
        dockerAccountFind "${specFile}" "${sourceId}" || {
            dockerError "账号不存在: ${sourceId}"
            return "${PADM_DOCKER_RC_USAGE}"
        }
        if [[ "${action}" == edit ]]; then
            dockerAccountRequireLocal "${specFile}" "${sourceId}" || return $?
            [[ "${seenName}" -eq 1 || "${seenListeners}" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
            [[ "${seenName}" -eq 0 ]] || dockerAccountNameIsValid "${name}" ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${seenListeners}" -eq 1 ]]; then
                listeners=$(dockerAccountListenersJson "${specFile}" "${listenersRaw}") || return "${PADM_DOCKER_RC_USAGE}"
            fi
            ssPassword=
            if [[ "${seenListeners}" -eq 1 ]]; then
                if dockerAccountListenersNeedSs "${specFile}" "${listeners}"; then
                    ssPassword=$(jq -r --arg id "${sourceId}" \
                        '.accounts[] | select(.id == $id) | .shadowsocks_password // empty' "${specFile}") ||
                        return "${PADM_DOCKER_RC_STATE}"
                    [[ -n "${ssPassword}" ]] ||
                        ssPassword=$(dockerAccountRandomSsPassword) ||
                        return "${PADM_DOCKER_RC_STATE}"
                else
                    ssPassword=null
                fi
            fi
            dockerAccountMutate \
                '(.accounts[] | select(.id == $id)) |=
                  (if $nameSet then .name = $name else . end |
                   if $listenersSet then
                     .listeners = $listeners |
                     .shadowsocks_password = (if $ss == "null" then null else $ss end)
                   else . end)' \
                --arg id "${sourceId}" --arg name "${name}" --argjson nameSet "$([[ "${seenName}" -eq 1 ]] && printf true || printf false)" \
                --argjson listenersSet "$([[ "${seenListeners}" -eq 1 ]] && printf true || printf false)" \
                --argjson listeners "${listeners:-[]}" --arg ss "${ssPassword}"
        else
            [[ "${seenName}" -eq 0 ]] || dockerAccountNameIsValid "${name}" ||
                return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${seenListeners}" -eq 1 ]]; then
                listeners=$(dockerAccountListenersJson "${specFile}" "${listenersRaw}") || return "${PADM_DOCKER_RC_USAGE}"
            else
                listeners=$(jq -c --arg id "${sourceId}" \
                    '.accounts[] | select(.id == $id) | .listeners' "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
            fi
            uuid=$(dockerAccountRandomUuid "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
            password=$(dockerAccountRandomPassword "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
            ssPassword=null
            if dockerAccountListenersNeedSs "${specFile}" "${listeners}"; then
                ssPassword=$(dockerAccountRandomSsPassword) || return "${PADM_DOCKER_RC_STATE}"
            fi
            [[ -n "${name}" ]] || name=$(jq -er --arg id "${sourceId}" \
                '.accounts[] | select(.id == $id) | ((.name + "-copy")[:64])' "${specFile}") ||
                return "${PADM_DOCKER_RC_STATE}"
            dockerAccountNameIsValid "${name}" || return "${PADM_DOCKER_RC_USAGE}"
            id=$(dockerAccountRandomUuid "${specFile}" "${uuid}") || return "${PADM_DOCKER_RC_STATE}"
            dockerAccountMutate \
                '(.accounts[] | select(.id == $sourceId)) as $source |
                 .accounts += [{id:$id,name:$name,enabled:$source.enabled,uuid:$uuid,password:$password,
                   shadowsocks_password:(if $ss == "null" then null else $ss end),listeners:$listeners}]' \
                --arg sourceId "${sourceId}" --arg id "${id}" \
                --arg name "${name}" --argjson listeners "${listeners}" --arg uuid "${uuid}" \
                --arg password "${password}" --arg ss "${ssPassword}" ||
                return $?
            dockerAccountPrintCredentials 复制 "${id}" "${uuid}" "${password}" "${ssPassword}"
        fi
        ;;
    enable|disable)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        accountId=$1
        dockerAccountIdIsValid "${accountId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        specFile=$(dockerAccountSpecFile) || return $?
        dockerAccountFind "${specFile}" "${accountId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerAccountRequireLocal "${specFile}" "${accountId}" || return $?
        enabled=true
        [[ "${action}" == enable ]] || enabled=false
        dockerAccountMutate \
            '(.accounts[] | select(.id == $id)).enabled = $enabled' \
            --arg id "${accountId}" --argjson enabled "${enabled}"
        ;;
    delete|rotate)
        [[ "$#" -ge 1 && "$#" -le 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
        accountId=$1
        dockerAccountIdIsValid "${accountId}" || return "${PADM_DOCKER_RC_USAGE}"
        [[ "$#" -eq 1 || "$2" == --yes ]] || return "${PADM_DOCKER_RC_USAGE}"
        [[ "$#" -eq 2 ]] && yes=1
        dockerAccountConfirm "${action}" "${accountId}" "${yes}" || return $?
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        specFile=$(dockerAccountSpecFile) || return $?
        dockerAccountFind "${specFile}" "${accountId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerAccountRequireLocal "${specFile}" "${accountId}" || return $?
        if [[ "${action}" == delete ]]; then
            dockerAccountMutate \
                'if (.accounts | length) == 1 then del(.accounts) else .accounts |= map(select(.id != $id)) end' \
                --arg id "${accountId}"
        else
            uuid=$(dockerAccountRandomUuid "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
            password=$(dockerAccountRandomPassword "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
            ssPassword=null
            listeners=$(jq -c --arg id "${accountId}" \
                '.accounts[] | select(.id == $id) | .listeners' "${specFile}") ||
                return "${PADM_DOCKER_RC_STATE}"
            if dockerAccountListenersNeedSs "${specFile}" "${listeners}"; then
                ssPassword=$(dockerAccountRandomSsPassword) || return "${PADM_DOCKER_RC_STATE}"
            fi
            dockerAccountMutate \
                '(.accounts[] | select(.id == $id)) |=
                  (.uuid = $uuid | .password = $password |
                   .shadowsocks_password = (if $ss == "null" then null else $ss end))' \
                --arg id "${accountId}" --arg uuid "${uuid}" --arg password "${password}" --arg ss "${ssPassword}" ||
                return $?
            dockerAccountPrintCredentials 轮换 "${accountId}" "${uuid}" "${password}" "${ssPassword}"
        fi
        ;;
    *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
}
