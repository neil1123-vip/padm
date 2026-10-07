#!/usr/bin/env bash

if [[ "${PADM_DOCKER_BUSINESS_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_BUSINESS_LOADED=1

dockerBusinessFileSafe() {
    local file=$1
    dockerPathIsSafeAbsolute "${file}" &&
        dockerTrafficSafePath "$(dirname -- "${file}")" "${file}" || return 1
    [[ -f "${file}" && ! -L "${file}" && -O "${file}" ]] &&
        dockerPrivateFileIsRestricted "${file}" &&
        [[ "$(stat -c '%s' "${file}")" -le 16777216 ]] || return 1
}

dockerBusinessValidate() {
    local file=$1 shares traffic
    jq -es '
      length == 1 and (.[0] |
        type == "object" and keys ==
          ["accounts","created_at","format","listeners","schema_version","shares","subscription","traffic"] and
        .format == "padm-docker-business" and .schema_version == 1 and
        (.created_at | type == "string" and
          test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
        (.accounts | type == "array" and length <= 256 and
          all(.[]; type == "object") and
          ([.[].id] | length == (unique | length))) and
        (.subscription | type == "object" and keys == ["enabled","token"] and
          (.enabled | type == "boolean") and
          (.token | type == "string" and test("^[A-Za-z0-9_-]{16,128}$"))) and
        (.listeners | type == "array" and length >= 1 and length <= 16 and
          ([.[].listener_id] | length == (unique | length)) and
          all(.[]; type == "object" and keys == ["core","id","listener_id"] and
            (.id | type == "number" and floor == .) and
            (.core == "xray" or .core == "sing-box") and
            (.listener_id | type == "string" and
              test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$")))))
    ' "${file}" >/dev/null 2>&1 || return 1
    shares=$(jq -c '.shares' "${file}") && traffic=$(jq -c '.traffic' "${file}") || return 1
    dockerSubscriptionStateValidate /dev/stdin <<<"${shares}" &&
        jq -e "${DOCKER_TRAFFIC_STATE_JQ}" <<<"${traffic}" >/dev/null || return 1
}

dockerBusinessExport() (
    local target=$1 spec=$2 root temp shares traffic
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${target}" &&
        dockerTrafficSafePath "$(dirname -- "${target}")" "${target}" &&
        [[ ! -e "${target}" && ! -L "${target}" ]] || {
        dockerError '备份目标必须是不存在的安全绝对路径'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerTrafficBeforeChange
    shares=$(dockerSubscriptionReadState) && traffic=$(dockerTrafficReadState) || return 1
    temp=$(mktemp "$(dirname -- "${target}")/.business.XXXXXX") || return 1
    trap 'rm -f -- "${temp}"' EXIT
    chmod 0600 "${temp}" || return 1
    jq --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson shares "${shares}" --argjson traffic "${traffic}" '
      . as $spec |
      {format:"padm-docker-business",schema_version:1,created_at:$created,
       listeners:[.core.protocols[] |
         {listener_id,id,core:(.core // $spec.core.type)}],
       accounts:(.accounts // []),subscription,shares:$shares,
       traffic:$traffic}
    ' "${spec}" >"${temp}" || return 1
    dockerBusinessValidate "${temp}" || return 1
    # 硬链接原子发布且拒绝覆盖，避免目标在检查后被其它进程抢占。
    ln -- "${temp}" "${target}" || return 1
    printf '业务备份已保存（含凭据，请妥善保管）: %s\n' "${target}"
)

dockerBusinessBuildDraft() {
    local source=$1 spec=$2 strategy=$3 draft=$4 currentShares
    currentShares=$(dockerSubscriptionReadState) || return 1
    jq -n --slurpfile backup "${source}" --slurpfile spec "${spec}" \
        --argjson currentShares "${currentShares}" --arg strategy "${strategy}" '
      def merge_ids($current; $saved):
        [$current[] | select(.id as $id | any($saved[]; .id == $id) | not)] + $saved;
      $backup[0] as $backup | $spec[0] as $spec |
      [$spec.core.protocols[] |
        {listener_id,id,core:(.core // $spec.core.type)}] as $listeners |
      if all($backup.listeners[]; . as $entry | any($listeners[]; . == $entry))
      then . else error("备份入口不存在或协议/核心已变化") end |
      (if $strategy == "merge"
       then merge_ids(($spec.accounts // []); $backup.accounts)
       else $backup.accounts end) as $accounts |
      (if $strategy == "merge"
       then merge_ids($currentShares.groups; $backup.shares.groups)
       else $backup.shares.groups end) as $groups |
      $spec | .subscription = $backup.subscription |
      if ($accounts | length) > 0 then .accounts = $accounts else del(.accounts) end |
      {spec:.,shares:{schema_version:1,groups:$groups},traffic:$backup.traffic,
       conflicts:{
         strategy:$strategy,
         accounts_overwrite:[$spec.accounts[]? | .id as $id |
           select(any($backup.accounts[]; .id == $id)) | .id],
         accounts_added:[$backup.accounts[] | .id as $id |
           select(any($spec.accounts[]?; .id == $id) | not) | .id],
         accounts_extra:[$spec.accounts[]? | .id as $id |
           select(any($backup.accounts[]; .id == $id) | not) | .id],
         shares_overwrite:[$currentShares.groups[] | .id as $id |
           select(any($backup.shares.groups[]; .id == $id)) | .id],
         shares_extra:[$currentShares.groups[] | .id as $id |
           select(any($backup.shares.groups[]; .id == $id) | not) | .id],
         publication_changed:($spec.subscription != $backup.subscription)}}
    ' >"${draft}/business.json" || return 1
    jq '.spec' "${draft}/business.json" >"${draft}/spec.json" &&
        jq '.shares' "${draft}/business.json" >"${draft}/shares.json" || return 1
    chmod 0600 "${draft}/"*.json || return 1
    dockerConfigureSpecValidate "${draft}/spec.json" &&
        dockerSubscriptionStateValidate "${draft}/shares.json" || return 1
    jq -e --slurpfile spec "${draft}/spec.json" '
      . as $state |
      all(.groups[]; . as $group |
        .token != $spec[0].subscription.token and
        all(.account_ids[]; . as $id | any($spec[0].accounts[]?; .id == $id)) and
        all(.listener_ids[]; . as $id | any($spec[0].core.protocols[]; .listener_id == $id)) and
        any($spec[0].accounts[]?; . as $account |
          ($group.account_ids | index($account.id)) != null and
          any($account.listeners[]; . as $id | ($group.listener_ids | index($id)) != null)))
    ' "${draft}/shares.json" >/dev/null || {
        dockerError '分享组引用缺失或 token 冲突，请先修正备份业务关系'
        return 1
    }
}

dockerBusinessMergeTraffic() {
    local saved=$1 current=$2
    jq -n --argjson saved "${saved}" --argjson current "${current}" '
      $current |
      reduce ($saved.accounts | to_entries[]) as $entry (.;
        (.accounts[$entry.key] // {upload:0,download:0,baseline:{}}) as $live |
        .accounts[$entry.key] = ($entry.value |
          .upload = ([.upload,$live.upload] | max) |
          .download = ([.download,$live.download] | max) |
          .limit_bytes = ([.limit_bytes,$live.limit_bytes] | max) |
          .baseline = $live.baseline))
    ' | jq -e "${DOCKER_TRAFFIC_STATE_JQ}"
}

dockerBusinessPrepareCandidate() {
    local source=$1 candidate=$2 saved current next
    saved=$(jq -c '.traffic' "${source}") &&
        current=$(dockerTrafficReadState) || return 1
    next=$(dockerBusinessMergeTraffic "${saved}" "${current}") || return 1
    printf '%s\n' "${next}" >"${candidate}/business-traffic.json" || return 1
    chmod 0600 "${candidate}/business-traffic.json" || return 1
    dockerTrafficPrepareCandidate "${candidate}" "${next}"
}

dockerBusinessCommand() (
    local action=${1:-} file strategy='' yes=0 spec root draft status=0
    [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
    file=$2
    shift 2
    case "${action}" in backup|preview|restore) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --strategy)
            [[ -z "${strategy}" && "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
            strategy=$2
            case "${strategy}" in merge|replace) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
            shift 2 ;;
        --yes)
            [[ "${yes}" -eq 0 && "${action}" == restore ]] || return "${PADM_DOCKER_RC_USAGE}"
            yes=1; shift ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    if [[ "${action}" == backup ]]; then
        [[ -z "${strategy}" && "${yes}" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    else
        [[ -n "${strategy}" ]] || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${action}" != restore || "${yes}" -eq 1 ]] || {
            dockerError '业务恢复需要先预览并使用 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        dockerBusinessFileSafe "${file}" || {
            dockerError '业务备份必须是本用户持有的私有普通文件（最大 16 MiB）'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    # 锁在本子进程取得，退出时必须在本进程释放。
    trap 'dockerConfigurationInterrupted; dockerReleaseDeploymentLock' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    spec=$(dockerSubscriptionSpecFile) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == backup ]]; then
        dockerBusinessExport "${file}" "${spec}"
        return $?
    fi
    root=$(dockerInstallRoot) || return 1
    draft=$(mktemp -d "${root}/.business.XXXXXX") || return 1
    chmod 0700 "${draft}" || return 1
    trap 'dockerConfigurationInterrupted; dockerRemoveManagedTree "${root}" "${draft}"; dockerReleaseDeploymentLock' EXIT
    cp -- "${file}" "${draft}/input.json" &&
        chmod 0600 "${draft}/input.json" &&
        dockerBusinessValidate "${draft}/input.json" &&
        dockerBusinessBuildDraft "${draft}/input.json" "${spec}" "${strategy}" "${draft}" || {
        dockerError '业务备份损坏、版本不支持或恢复对象冲突，未更改部署'
        return "${PADM_DOCKER_RC_STATE}"
    }
    printf '恢复冲突预览（同 ID 以备份为准；额外对象%s；累计流量不回退）:\n' \
        "$([[ "${strategy}" == merge ]] && printf 保留 || printf 删除)"
    jq '.conflicts' "${draft}/business.json"
    dockerConfigureReleaseReuseInstalled || return $?
    if [[ "${action}" == preview ]]; then
        dockerConfigureApply "${draft}/spec.json" '' '' preview "${draft}/business.json" || status=$?
    else
        dockerConfigureApply "${draft}/spec.json" '' '' configure "${draft}/business.json" || status=$?
        [[ "${status}" -ne 0 ]] || printf '业务恢复已完成。\n'
    fi
    return "${status}"
)
