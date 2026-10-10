#!/usr/bin/env bash

if [[ "${PADM_DOCKER_SUBSCRIPTIONS_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_SUBSCRIPTIONS_LOADED=1

dockerSubscriptionStateValidate() {
    jq -es '
      length == 1 and (.[0] |
      type == "object" and keys == ["groups","schema_version"] and .schema_version == 1 and
      (.groups | type == "array" and length <= 256 and
       ([.[].id] | length == (unique | length)) and
       ([.[].token] | length == (unique | length)) and
       all(.[]; type == "object" and
         (keys_unsorted | sort) ==
           ["account_ids","enabled","id","listener_ids","name","token"] and
         (.id | type == "string" and test("^share-[a-f0-9]{16}$")) and
         (.name | type == "string" and length >= 1 and length <= 64 and
           (explode | all(. >= 32 and . != 127))) and
         (.enabled | type == "boolean") and
         (.token | type == "string" and test("^[A-Za-z0-9_-]{16,128}$")) and
         (.account_ids | type == "array" and length >= 1 and unique == . and
          all(.[]; type == "string" and test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$"))) and
         (.listener_ids | type == "array" and length >= 1 and unique == . and
          all(.[]; type == "string" and test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$")))
       )))
    ' "$1" >/dev/null 2>&1
}

dockerSubscriptionReadState() {
    local root path
    root=$(dockerInstallRoot) || return 1
    path="${root}/config/share-groups.json"
    dockerTrafficSafePath "${root}" "${path}" || return 1
    if [[ ! -e "${path}" ]]; then
        printf '%s\n' '{"schema_version":1,"groups":[]}'
        return 0
    fi
    [[ -f "${path}" && -O "${path}" ]] &&
        dockerPrivateFileIsRestricted "${path}" &&
        dockerSubscriptionStateValidate "${path}" || return 1
    jq -c . "${path}"
}

dockerSubscriptionStatePath() {
    local root=$1 config path
    config="${root}/config"
    dockerManagedPathIsSafe "${root}" "${config}" || return 1
    if [[ -e "${config}" || -L "${config}" ]]; then
        [[ -d "${config}" && ! -L "${config}" ]] || return 1
    else
        mkdir -p -- "${config}" || return 1
    fi
    path="${root}/config/share-groups.json"
    dockerTrafficSafePath "${root}" "${path}" || return 1
    if [[ -e "${path}" || -L "${path}" ]]; then
        [[ -f "${path}" && ! -L "${path}" && -O "${path}" ]] || return 1
        dockerPrivateFileIsRestricted "${path}" || return 1
    else
        printf '%s\n' '{"schema_version":1,"groups":[]}' >"${path}" || return 1
        chmod 0600 "${path}" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] || chown 0:0 "${path}" || return 1
    fi
    dockerSubscriptionStateValidate "${path}" || {
        dockerError '分享组状态文件格式或权限不安全'
        return "${PADM_DOCKER_RC_STATE}"
    }
    printf '%s\n' "${path}"
}

dockerSubscriptionPrepareCandidate() {
    local specFile=$1 candidate=$2 source=${3:-} state group token
    if [[ -n "${source}" ]]; then
        dockerSubscriptionStateValidate "${source}" || return 1
        state=$(jq -c . "${source}") || return 1
    else
        state=$(dockerSubscriptionReadState) || return 1
    fi
    dockerSubscriptionStateWrite "${candidate}/config/share-groups.json" "${state}" || return 1
    # 账号停用或删除后撤销对应发布；组身份保留，重新启用时可重建内容。
    while IFS= read -r group; do
        jq -e --argjson group "${group}" '
          . as $spec |
          any(.core.protocols[]; .listener_id as $listener |
            ($group.listener_ids | index($listener)) != null and
            any($spec.accounts[]?;
              .enabled and (.id as $id | ($group.account_ids | index($id)) != null) and
              (.listeners | index($listener)) != null))
        ' "${specFile}" >/dev/null || continue
        token=$(jq -er '.token' <<<"${group}") || return 1
        [[ "${token}" != "$(jq -r '.subscription.token' "${specFile}")" ]] || {
            dockerError '分享 token 与主订阅冲突'
            return 1
        }
        dockerSubscriptionRender "${specFile}" "${group}" "${candidate}/data/subscription/${token}" || return 1
    done < <(jq -c '.groups[] | select(.enabled)' <<<"${state}")
}

dockerSubscriptionSpecFile() {
    local root
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" &&
            -O "${root}/config/spec.json" ]] || {
        dockerError 'Docker 服务尚未配置完整规格，请先完成首次配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerPrivateFileIsRestricted "${root}/config/spec.json" || {
        dockerError '完整规格权限不安全'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerConfigureSpecValidate "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    printf '%s\n' "${root}/config/spec.json"
}

dockerSubscriptionGroupIdIsValid() {
    [[ "$1" =~ ^share-[a-f0-9]{16}$ ]]
}

dockerSubscriptionTokenIsValid() {
    [[ "$1" =~ ^[A-Za-z0-9_-]{16,128}$ ]]
}

dockerSubscriptionNameIsValid() {
    jq -en --arg value "$1" '
      ($value | type == "string" and length >= 1 and length <= 64 and
        (explode | all(. >= 32 and . != 127)))
    ' >/dev/null 2>&1
}

dockerSubscriptionRandomHex() {
    local value
    if command -v openssl >/dev/null 2>&1; then
        value=$(openssl rand -hex 24 2>/dev/null || true)
    fi
    if [[ ! "${value}" =~ ^[a-f0-9]{48}$ ]]; then
        value=$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
    fi
    [[ "${value}" =~ ^[a-f0-9]{48}$ ]] || return 1
    printf '%s\n' "${value}"
}

dockerSubscriptionGroupId() {
    local value
    value=$(dockerSubscriptionRandomHex) || return 1
    printf 'share-%s\n' "${value:0:16}"
}

dockerSubscriptionCommaIds() {
    local raw=$1 kind=$2
    [[ -n "${raw}" && "${raw}" != *,,* && "${raw}" != ,* && "${raw}" != *, &&
        "${raw}" != *[[:space:]]* ]] || return 1
    case "${kind}" in
    accounts)
        jq -cn --arg raw "${raw}" '
          ($raw | split(",")) as $items |
          if ($items | length) >= 1 and ($items | unique | length) == ($items | length) and
             all($items[]; test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$"))
          then $items else error("invalid accounts") end
        ' ;;
    listeners)
        jq -cn --arg raw "${raw}" '
          ($raw | split(",")) as $items |
          if ($items | length) >= 1 and ($items | unique | length) == ($items | length) and
             all($items[]; test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$"))
          then $items else error("invalid listeners") end
        ' ;;
    *) return 1 ;;
    esac
}

dockerSubscriptionDefaultIds() {
    local specFile=$1 kind=$2
    case "${kind}" in
    accounts) jq -c '[.accounts[]? | select(.enabled) | .id]' "${specFile}" ;;
    listeners) jq -c '[.core.protocols[].listener_id] | unique' "${specFile}" ;;
    *) return 1 ;;
    esac
}

dockerSubscriptionIdsValidate() {
    local specFile=$1 kind=$2 ids=$3
    case "${kind}" in
    accounts)
        jq -e --argjson ids "${ids}" '
          . as $spec |
          all($ids[]; . as $id | $spec | any(($spec.accounts // [])[]; .id == $id))
        ' "${specFile}" >/dev/null 2>&1 ;;
    listeners)
        jq -e --argjson ids "${ids}" '
          . as $spec |
          all($ids[]; . as $id | $spec | any($spec.core.protocols[]; .listener_id == $id))
        ' "${specFile}" >/dev/null 2>&1 ;;
    *) return 1 ;;
    esac
}

dockerSubscriptionStateWrite() {
    local path=$1 json=$2 temp
    temp=$(mktemp "${path}.XXXXXX") || return 1
    chmod 0600 "${temp}" || { rm -f -- "${temp}"; return 1; }
    printf '%s\n' "${json}" >"${temp}" || { rm -f -- "${temp}"; return 1; }
    dockerSubscriptionStateValidate "${temp}" || { rm -f -- "${temp}"; return 1; }
    [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] || chown 0:0 "${temp}" || {
        rm -f -- "${temp}"
        return 1
    }
    mv -f -- "${temp}" "${path}" || { rm -f -- "${temp}"; return 1; }
}

dockerSubscriptionFindGroup() {
    local state=$1 groupId=$2
    dockerSubscriptionGroupIdIsValid "${groupId}" || return 1
    jq -e --arg id "${groupId}" '.groups[] | select(.id == $id)' "${state}" >/dev/null 2>&1
}

dockerSubscriptionRender() {
    local specFile=$1 groupJson=$2 target=$3 root tempSpec token status isStdout=0
    root=$(dockerInstallRoot) || return 1
    token=$(jq -er '.token' <<<"${groupJson}") || return 1
    dockerSubscriptionTokenIsValid "${token}" || return 1
    [[ "${target}" == /dev/stdout ]] && isStdout=1
    tempSpec=$(mktemp "${root}/.subscription.XXXXXX.json") || return 1
    chmod 0600 "${tempSpec}" || { rm -f -- "${tempSpec}"; return 1; }
    jq --argjson group "${groupJson}" '
      .subscription.enabled = true |
      .subscription.token = $group.token |
        .subscription.include_base = false |
      .core.protocols |= map(select(.listener_id as $id | ($group.listener_ids | index($id)) != null)) |
      if has("accounts") then
        .accounts |= map(select(.id as $id | ($group.account_ids | index($id)) != null))
      else . end
    ' "${specFile}" >"${tempSpec}" || {
        rm -f -- "${tempSpec}"
        return 1
    }
    jq -e '.core.protocols | length > 0' "${tempSpec}" >/dev/null || {
        rm -f -- "${tempSpec}"
        return 1
    }
    jq -e '
      [.core.protocols[] as $entry |
       (.accounts // [])[]? |
       select(.enabled == true and ((.listeners // []) | index($entry.listener_id) != null))
      ] | length > 0
    ' "${tempSpec}" >/dev/null || {
        dockerError '分享组没有匹配的启用账号和入口'
        rm -f -- "${tempSpec}"
        return 1
    }
    if ((isStdout == 0)); then
        mkdir -p -- "$(dirname -- "${target}")" || {
            rm -f -- "${tempSpec}"
            return 1
        }
    fi
    dockerGenerateSubscription "${tempSpec}" "${target}"
    status=$?
    rm -f -- "${tempSpec}" || [[ "${status}" -ne 0 ]] || status=1
    if ((isStdout)); then
        return "${status}"
    fi
    [[ "${status}" -eq 0 && -f "${target}" && ! -L "${target}" ]] || return 1
    chmod 0640 "${target}" || return 1
    [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == "1" ]] ||
        chown "0:${PADM_DOCKER_CONTAINER_GID:-10001}" "${target}" || return 1
}

dockerSubscriptionRenderGroup() {
    local specFile=$1 groupJson=$2 root token targetDir target tempTarget
    root=$(dockerInstallRoot) || return 1
    token=$(jq -er '.token' <<<"${groupJson}") || return 1
    dockerSubscriptionTokenIsValid "${token}" || return 1
    targetDir="${root}/data/subscription"
    dockerManagedPathIsSafe "${root}" "${targetDir}" || return 1
    if [[ -e "${targetDir}" || -L "${targetDir}" ]]; then
        [[ -d "${targetDir}" && ! -L "${targetDir}" ]] || return 1
    else
        mkdir -p -- "${targetDir}" || return 1
    fi
    tempTarget=$(mktemp "${targetDir}/.share.XXXXXX") || return 1
    chmod 0640 "${tempTarget}" || { rm -f -- "${tempTarget}"; return 1; }
    if ! dockerSubscriptionRender "${specFile}" "${groupJson}" "${tempTarget}"; then
        rm -f -- "${tempTarget}"
        return 1
    fi
    target="${targetDir}/${token}"
    dockerTrafficSafePath "${root}" "${target}" || {
        rm -f -- "${tempTarget}"
        return 1
    }
    [[ ! -e "${target}" && ! -L "${target}" ||
        ( -f "${target}" && ! -L "${target}" && -O "${target}" ) ]] || {
        rm -f -- "${tempTarget}"
        return 1
    }
    mv -f -- "${tempTarget}" "${target}" || {
        rm -f -- "${tempTarget}"
        return 1
    }
}

dockerSubscriptionTokenMoveAside() {
    local root=$1 token=$2 path backup
    dockerSubscriptionTokenIsValid "${token}" || return 1
    path="${root}/data/subscription/${token}"
    dockerTrafficSafePath "${root}" "${path}" || return 1
    [[ ! -L "${path}" ]] || return 1
    if [[ ! -e "${path}" ]]; then
        printf '\n'
        return 0
    fi
    [[ -f "${path}" && -O "${path}" ]] || return 1
    backup=$(mktemp "${root}/data/subscription/.rollback.XXXXXX") || return 1
    chmod 0600 "${backup}" || { rm -f -- "${backup}"; return 1; }
    mv -f -- "${path}" "${backup}" || { rm -f -- "${backup}"; return 1; }
    printf '%s\n' "${backup}"
}

dockerSubscriptionTokenRestore() {
    local root=$1 token=$2 backup=$3 path
    dockerSubscriptionTokenIsValid "${token}" || return 1
    path="${root}/data/subscription/${token}"
    dockerTrafficSafePath "${root}" "${path}" || return 1
    [[ -z "${backup}" || ( -f "${backup}" && ! -L "${backup}" ) ]] || return 1
    rm -f -- "${path}" || return 1
    [[ -z "${backup}" ]] || mv -f -- "${backup}" "${path}"
}

dockerSubscriptionTokenDiscardBackup() {
    [[ -z "${1:-}" ]] || rm -f -- "$1"
}

dockerSubscriptionRemoveToken() {
    local root=$1 token=$2 path
    dockerSubscriptionTokenIsValid "${token}" || return 1
    path="${root}/data/subscription/${token}"
    dockerManagedPathIsSafe "${root}" "${path}" || return 1
    [[ ! -e "${path}" || ( -f "${path}" && ! -L "${path}" && -O "${path}" ) ]] || return 1
    rm -f -- "${path}"
}

dockerSubscriptionGroupJson() {
    local state=$1 groupId=$2
    jq -ce --arg id "${groupId}" '.groups[] | select(.id == $id)' "${state}"
}

dockerSubscriptionContent() {
    local specFile=$1 state=$2 groupId=$3 group
    group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
    [[ "$(jq -r '.enabled' <<<"${group}")" == true ]] || {
        dockerError '分享组已停用'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerSubscriptionRender "${specFile}" "${group}" /dev/stdout
}

dockerSubscriptionLinks() {
    local specFile=$1 state=$2 groupId=$3 group domain
    group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
    [[ "$(jq -r '.enabled' <<<"${group}")" == true ]] || {
        dockerError '分享组已停用，未输出链接'
        return "${PADM_DOCKER_RC_STATE}"
    }
    jq -e '.subscription.enabled == true and .tls != null' "${specFile}" >/dev/null 2>&1 || {
        dockerError '当前部署没有启用受管 TLS 订阅，暂不能生成公网分享链接'
        return "${PADM_DOCKER_RC_STATE}"
    }
    domain=$(jq -er '.tls.domain' "${specFile}") || return "${PADM_DOCKER_RC_STATE}"
    printf 'https://%s/subscriptions/%s\n' "${domain}" "$(jq -er '.token' <<<"${group}")"
}

dockerSubscriptionList() {
    local state=$1 json=${2:-0}
    if ((json)); then
        jq -c '.groups | map(del(.token))' "${state}"
    else
        jq -r '.groups[]? |
          [.id, .name, (if .enabled then "enabled" else "disabled" end),
           (.account_ids | length | tostring), (.listener_ids | join(","))] | @tsv' "${state}"
    fi
}

dockerSubscriptionConfirm() {
    local action=$1 groupId=$2 confirmed=${3:-0} answer
    if [[ "${confirmed}" == 1 || "${DOCKER_SUBSCRIPTION_CONFIRM:-0}" == 1 ]]; then
        return 0
    fi
    [[ -t 0 && -t 1 ]] || {
        dockerError "${action} 需要 --yes 确认"
        return "${PADM_DOCKER_RC_USAGE}"
    }
    dockerSetupRead answer "${action} 分享组 ${groupId}？[y/N]: " n || return "${PADM_DOCKER_RC_USAGE}"
    case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
}

dockerSubscriptionCommand() {
    local action=${1:-} state='' specFile='' root='' groupId='' name='' \
        accountsRaw='' listenersRaw='' accounts='' listeners=''
    local enabled=1 json=0 yes=0 seenName=0 seenAccounts=0 seenListeners=0
    local group='' id='' token='' oldToken='' oldState='' nextState='' \
        groupJson='' tokenBackup='' newTokenBackup=''
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
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        dockerSubscriptionList "${state}" "${json}"
        ;;
    create)
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
            --name) [[ "${seenName}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; name=$2; seenName=1; shift 2 ;;
            --accounts) [[ "${seenAccounts}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; accountsRaw=$2; seenAccounts=1; shift 2 ;;
            --listeners) [[ "${seenListeners}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; listenersRaw=$2; seenListeners=1; shift 2 ;;
            --disabled) [[ "${enabled}" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"; enabled=0; shift ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        done
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        specFile=$(dockerSubscriptionSpecFile) || return $?
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        id=$(dockerSubscriptionGroupId) || return "${PADM_DOCKER_RC_STATE}"
        [[ -n "${name}" ]] || name="share-${id#share-}"
        dockerSubscriptionNameIsValid "${name}" || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${seenAccounts}" -eq 1 ]]; then accounts=$(dockerSubscriptionCommaIds "${accountsRaw}" accounts) || return "${PADM_DOCKER_RC_USAGE}"; else accounts=$(dockerSubscriptionDefaultIds "${specFile}" accounts) || return "${PADM_DOCKER_RC_STATE}"; fi
        if [[ "${seenListeners}" -eq 1 ]]; then listeners=$(dockerSubscriptionCommaIds "${listenersRaw}" listeners) || return "${PADM_DOCKER_RC_USAGE}"; else listeners=$(dockerSubscriptionDefaultIds "${specFile}" listeners) || return "${PADM_DOCKER_RC_STATE}"; fi
        jq -e 'length > 0' <<<"${accounts}" >/dev/null || { dockerError '没有可用账号'; return "${PADM_DOCKER_RC_STATE}"; }
        jq -e 'length > 0' <<<"${listeners}" >/dev/null || { dockerError '没有可用入口'; return "${PADM_DOCKER_RC_STATE}"; }
        dockerSubscriptionIdsValidate "${specFile}" accounts "${accounts}" || { dockerError '账号 ID 列表无效'; return "${PADM_DOCKER_RC_USAGE}"; }
        dockerSubscriptionIdsValidate "${specFile}" listeners "${listeners}" || { dockerError '入口 ID 列表无效'; return "${PADM_DOCKER_RC_USAGE}"; }
        token=$(dockerSubscriptionRandomHex) || return "${PADM_DOCKER_RC_STATE}"
        group=$(jq -cn --arg id "${id}" --arg name "${name}" --arg token "${token}" --argjson enabled "$([[ "${enabled}" -eq 1 ]] && printf true || printf false)" --argjson accounts "${accounts}" --argjson listeners "${listeners}" '{id:$id,name:$name,enabled:$enabled,token:$token,account_ids:$accounts,listener_ids:$listeners}') || return "${PADM_DOCKER_RC_STATE}"
         tokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${token}") || return "${PADM_DOCKER_RC_STATE}"
         if [[ "${enabled}" -ne 0 ]] &&
             ! dockerSubscriptionRenderGroup "${specFile}" "${group}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
        nextState=$(jq --argjson group "${group}" '.groups += [$group]' "${state}") || {
            dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
            return "${PADM_DOCKER_RC_STATE}"
        }
         if ! dockerSubscriptionStateWrite "${state}" "${nextState}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
         dockerSubscriptionTokenDiscardBackup "${tokenBackup}"
        printf '%s\n' "${id}"
        ;;
    edit)
        [[ "$#" -ge 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        groupId=$1; shift
        dockerSubscriptionGroupIdIsValid "${groupId}" || return "${PADM_DOCKER_RC_USAGE}"
        while [[ "$#" -gt 0 ]]; do
            case "$1" in
            --name) [[ "${seenName}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; name=$2; seenName=1; shift 2 ;;
            --accounts) [[ "${seenAccounts}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; accountsRaw=$2; seenAccounts=1; shift 2 ;;
            --listeners) [[ "${seenListeners}" -eq 0 && "$#" -ge 2 && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"; listenersRaw=$2; seenListeners=1; shift 2 ;;
            *) return "${PADM_DOCKER_RC_USAGE}" ;;
            esac
        done
        [[ "${seenName}" -eq 1 || "${seenAccounts}" -eq 1 || "${seenListeners}" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        specFile=$(dockerSubscriptionSpecFile) || return $?
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${seenName}" -eq 0 ]] || dockerSubscriptionNameIsValid "${name}" || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${seenAccounts}" -eq 0 ]] || accounts=$(dockerSubscriptionCommaIds "${accountsRaw}" accounts) || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${seenListeners}" -eq 0 ]] || listeners=$(dockerSubscriptionCommaIds "${listenersRaw}" listeners) || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${seenAccounts}" -eq 0 ]] || dockerSubscriptionIdsValidate "${specFile}" accounts "${accounts}" || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${seenListeners}" -eq 0 ]] || dockerSubscriptionIdsValidate "${specFile}" listeners "${listeners}" || return "${PADM_DOCKER_RC_USAGE}"
        group=$(jq --arg name "${name}" --argjson accounts "${accounts:-null}" --argjson listeners "${listeners:-null}" --argjson hasName "$([[ "${seenName}" -eq 1 ]] && printf true || printf false)" --argjson hasAccounts "$([[ "${seenAccounts}" -eq 1 ]] && printf true || printf false)" --argjson hasListeners "$([[ "${seenListeners}" -eq 1 ]] && printf true || printf false)" 'if $hasName then .name = $name else . end | if $hasAccounts then .account_ids = $accounts else . end | if $hasListeners then .listener_ids = $listeners else . end' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
        token=$(jq -er '.token' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
         tokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${token}") ||
             return "${PADM_DOCKER_RC_STATE}"
         if [[ "$(jq -r '.enabled' <<<"${group}")" == true ]] &&
             ! dockerSubscriptionRenderGroup "${specFile}" "${group}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
        nextState=$(jq --arg id "${groupId}" --argjson group "${group}" '(.groups[] | select(.id == $id)) = $group' "${state}") || {
            dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
            return "${PADM_DOCKER_RC_STATE}"
        }
         if ! dockerSubscriptionStateWrite "${state}" "${nextState}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
         dockerSubscriptionTokenDiscardBackup "${tokenBackup}"
        ;;
    enable|disable)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        groupId=$1
        dockerSubscriptionGroupIdIsValid "${groupId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        specFile=$(dockerSubscriptionSpecFile) || return $?
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
        enabled=$([[ "${action}" == enable ]] && printf 1 || printf 0)
        group=$(jq --argjson enabled "$([[ "${enabled}" -eq 1 ]] && printf true || printf false)" '.enabled = $enabled' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
         token=$(jq -er '.token' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
         tokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${token}") ||
             return "${PADM_DOCKER_RC_STATE}"
         if [[ "${enabled}" -eq 1 ]] &&
             ! dockerSubscriptionRenderGroup "${specFile}" "${group}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
         nextState=$(jq --arg id "${groupId}" --argjson group "${group}" '(.groups[] | select(.id == $id)) = $group' "${state}") || {
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         }
         if ! dockerSubscriptionStateWrite "${state}" "${nextState}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
             return "${PADM_DOCKER_RC_STATE}"
         fi
         dockerSubscriptionTokenDiscardBackup "${tokenBackup}"
        ;;
    delete)
        [[ "$#" -ge 1 && "$#" -le 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
        groupId=$1; [[ "${2:-}" == --yes ]] && yes=1
        dockerSubscriptionGroupIdIsValid "${groupId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerSubscriptionConfirm 删除 "${groupId}" "${yes}" || return $?
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
         oldState=$(<"${state}")
         token=$(jq -er '.token' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
         tokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${token}") ||
             return "${PADM_DOCKER_RC_STATE}"
        nextState=$(jq --arg id "${groupId}" 'del(.groups[] | select(.id == $id))' "${state}") || {
            dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
            return "${PADM_DOCKER_RC_STATE}"
        }
         if ! dockerSubscriptionStateWrite "${state}" "${nextState}"; then
             dockerSubscriptionTokenRestore "${root}" "${token}" "${tokenBackup}" || true
            dockerSubscriptionStateWrite "${state}" "${oldState}" || true
            return "${PADM_DOCKER_RC_STATE}"
        fi
         dockerSubscriptionTokenDiscardBackup "${tokenBackup}"
        ;;
    rotate)
        [[ "$#" -ge 1 && "$#" -le 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
        groupId=$1; [[ "${2:-}" == --yes ]] && yes=1
        dockerSubscriptionGroupIdIsValid "${groupId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerSubscriptionConfirm 轮换 "${groupId}" "${yes}" || return $?
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        specFile=$(dockerSubscriptionSpecFile) || return $?
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        group=$(dockerSubscriptionGroupJson "${state}" "${groupId}") || return "${PADM_DOCKER_RC_USAGE}"
         oldToken=$(jq -er '.token' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
        token=$(dockerSubscriptionRandomHex) || return "${PADM_DOCKER_RC_STATE}"
        group=$(jq --arg token "${token}" '.token = $token' <<<"${group}") || return "${PADM_DOCKER_RC_STATE}"
         oldState=$(<"${state}")
         tokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${oldToken}") ||
             return "${PADM_DOCKER_RC_STATE}"
         newTokenBackup=$(dockerSubscriptionTokenMoveAside "${root}" "${token}") ||
             { dockerSubscriptionTokenRestore "${root}" "${oldToken}" "${tokenBackup}" || true; return "${PADM_DOCKER_RC_STATE}"; }
        if [[ "$(jq -r '.enabled' <<<"${group}")" == true ]]; then
             if ! dockerSubscriptionRenderGroup "${specFile}" "${group}"; then
                 dockerSubscriptionTokenRestore "${root}" "${oldToken}" "${tokenBackup}" || true
                 dockerSubscriptionTokenRestore "${root}" "${token}" "${newTokenBackup}" || true
                 return "${PADM_DOCKER_RC_STATE}"
             fi
        fi
        nextState=$(jq --arg id "${groupId}" --argjson group "${group}" '(.groups[] | select(.id == $id)) = $group' "${state}") || {
            dockerSubscriptionTokenRestore "${root}" "${oldToken}" "${tokenBackup}" || true
            dockerSubscriptionTokenRestore "${root}" "${token}" "${newTokenBackup}" || true
            return "${PADM_DOCKER_RC_STATE}"
        }
        if ! dockerSubscriptionStateWrite "${state}" "${nextState}"; then
             dockerSubscriptionTokenRestore "${root}" "${oldToken}" "${tokenBackup}" || true
             dockerSubscriptionTokenRestore "${root}" "${token}" "${newTokenBackup}" || true
            return "${PADM_DOCKER_RC_STATE}"
        fi
         dockerSubscriptionTokenDiscardBackup "${tokenBackup}"
         dockerSubscriptionTokenDiscardBackup "${newTokenBackup}"
        ;;
    content|links)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        groupId=$1
        dockerSubscriptionGroupIdIsValid "${groupId}" || return "${PADM_DOCKER_RC_USAGE}"
        dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        specFile=$(dockerSubscriptionSpecFile) || return $?
        state=$(dockerSubscriptionStatePath "${root}") || return "${PADM_DOCKER_RC_STATE}"
        if [[ "${action}" == content ]]; then dockerSubscriptionContent "${specFile}" "${state}" "${groupId}"; else dockerSubscriptionLinks "${specFile}" "${state}" "${groupId}"; fi
        ;;
    revoke)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerSubscriptionCommand disable "$1"
        ;;
    *) return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
}
