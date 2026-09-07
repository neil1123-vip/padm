#!/usr/bin/env bash

# shellcheck source=/dev/null
source "${DOCKER_BUNDLE_SOURCE_ROOT}/shell/core/stats_grpc.sh"

DOCKER_TRAFFIC_USERS_JQ='
  def traffic_id:
    (.uuid // .id // .name // .email // "") |
    if type != "string" or (test("^[A-Za-z0-9_.@+-]{1,128}$") | not) then
      error("用户缺少有效的稳定统计标识")
    elif test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$") then ascii_downcase
    else . end;
  def traffic_users($core):
    if $core == "xray" then .inbounds[]?.settings.clients[]?
    else .inbounds[]?.users[]? end;
  def traffic_accounts($core):
    [traffic_users($core) | {account: traffic_id, name: (.name // .email // traffic_id)}] |
    unique_by(.account);
'

DOCKER_TRAFFIC_STATE_JQ='
  def count: type == "number" and . >= 0 and . <= 9007199254740991 and . == floor;
  def exact($expected): type == "object" and keys == ($expected | sort);
  def baseline:
    type == "object" and all(to_entries[];
      (.key == "xray" or .key == "sing-box") and
      (.value | type == "object" and all(to_entries[];
        (.key == "upload" or .key == "download") and
        (.value | exact(["generation", "value"]) and
          (.generation | type == "string" and length > 0) and (.value | count)))));
  if exact(["schema_version", "accounts"]) and .schema_version == 1 and
    (.accounts | type == "object" and all(to_entries[];
      (.key | test("^[A-Za-z0-9_.@+-]{1,128}$")) and
      (.value | exact(["name", "upload", "download", "limit_bytes", "baseline"]) and
        (.name | type == "string") and (.upload | count) and (.download | count) and
        ((.upload + .download) | count) and (.limit_bytes | count) and (.baseline | baseline))))
  then . else error("Docker 流量状态无效") end
'

dockerTrafficSafePath() {
    local root=$1 path=$2 cursor
    dockerPathIsSafeAbsolute "${root}" && dockerPathIsSafeAbsolute "${path}" || return 1
    [[ "${path}" == "${root}" ]] || dockerManagedPathIsSafe "${root}" "${path}" || return 1
    cursor=${path}
    while [[ -n "${cursor}" && "${cursor}" != / ]]; do
        [[ ! -L "${cursor}" ]] || { dockerError "流量路径不能含符号链接: ${cursor}"; return 1; }
        cursor=${cursor%/*}
    done
}

dockerTrafficReadState() {
    local root file
    root=$(dockerInstallRoot) || return 1
    file=${root}/data/traffic/state.json
    dockerTrafficSafePath "${root}" "${file}" || return 1
    if [[ ! -e "${file}" ]]; then
        printf '%s\n' '{"schema_version":1,"accounts":{}}'
        return 0
    fi
    [[ -f "${file}" && -O "${file}" ]] || return 1
    jq -ces 'if length == 1 then .[0] else error("流量状态必须是单个对象") end | '"${DOCKER_TRAFFIC_STATE_JQ}" "${file}"
}

dockerTrafficWriteState() (
    local root directory temporary
    root=$(dockerInstallRoot) || return 1
    directory=${root}/data/traffic
    dockerTrafficSafePath "${root}" "${directory}/state.json" || return 1
    [[ ! -e "${directory}/state.json" || ( -f "${directory}/state.json" && -O "${directory}/state.json" ) ]] || return 1
    mkdir -p -- "${directory}" || return 1
    [[ -d "${directory}" && -O "${directory}" ]] && chmod 0700 "${directory}" || return 1
    temporary=$(mktemp "${directory}/.state.XXXXXX") || return 1
    trap 'rm -f -- "${temporary}"' EXIT
    jq -es 'if length == 1 then .[0] else error("流量状态必须是单个对象") end | '"${DOCKER_TRAFFIC_STATE_JQ}" >"${temporary}" || return 1
    chmod 0600 "${temporary}" && mv -f -- "${temporary}" "${directory}/state.json"
)

dockerTrafficCore() {
    local root
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/deployment.json" || return 1
    jq -er '.core.type | select(. == "xray" or . == "sing-box")' "${root}/deployment.json"
}

dockerTrafficAccounts() {
    local core=$1 root base
    root=$(dockerInstallRoot) || return 1
    base=${root}/config/${core}/users.base
    dockerTrafficSafePath "${root}" "${base}" && [[ -f "${base}" ]] || {
        dockerError 'Docker 用户统计尚未初始化，请先更新或重新配置部署'
        return 1
    }
    jq -ce --arg core "${core}" "${DOCKER_TRAFFIC_USERS_JQ}"'traffic_accounts($core)' "${base}"
}

dockerTrafficRender() {
    local core=$1 source=$2 state=$3
    jq -e --arg core "${core}" --argjson state "${state}" "${DOCKER_TRAFFIC_USERS_JQ}"'
      def enabled:
        traffic_id as $id | ($state.accounts[$id] // {}) as $account |
        ($account.limit_bytes // 0) == 0 or
        (($account.upload // 0) + ($account.download // 0)) < $account.limit_bytes;
      if type != "object" or (.inbounds | type) != "array" then error("核心配置格式无效") else . end |
      traffic_accounts($core) as $accounts |
      if $core == "xray" then
        (.api.tag // "padm-traffic-api") as $api |
        [.inbounds[]?.settings.clients[]? | (.level // 0) | tostring] as $levels |
        .stats = (.stats // {}) |
        .api = ((.api // {}) + {tag:$api, services: (((.api.services // []) + ["StatsService"]) | unique)}) |
        reduce $levels[] as $level (.;
          .policy.levels[$level].statsUserUplink = true |
          .policy.levels[$level].statsUserDownlink = true) |
        .inbounds = ([.inbounds[] | select(.tag != $api) |
          if .settings.clients? != null then .settings.clients |= map(select(enabled) | .email = traffic_id) else . end] +
          [{tag:$api, listen:"127.0.0.1", port:10085, protocol:"dokodemo-door", settings:{address:"127.0.0.1"}}]) |
        .routing.rules = ([{type:"field", inboundTag:[$api], outboundTag:$api}] +
          [(.routing.rules // [])[] | select(((.inboundTag // []) | index($api)) == null)])
      else
        .inbounds |= map(if .users? != null then .users |= map(select(enabled) | .name = traffic_id) else . end) |
        .experimental.v2ray_api.listen = "127.0.0.1:10087" |
        .experimental.v2ray_api.stats.enabled = true |
        .experimental.v2ray_api.stats.users = [$accounts[].account]
      end
    ' "${source}"
}

dockerTrafficPrepareCandidate() (
    local candidate=$1 root stage state core directory source failed=false keep=false
    local -a prepared=() moved=()
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${candidate}" || return 1
    [[ -d "${candidate}" && -O "${candidate}" ]] || return 1
    state=$(dockerTrafficReadState) || return 1
    stage=$(mktemp -d "${candidate}/.traffic.XXXXXX") || return 1
    trap '[[ "${keep}" == true ]] || dockerRemoveManagedTree "${candidate}" "${stage}"' EXIT
    for core in xray sing-box; do
        directory=${candidate}/config/${core}
        dockerTrafficSafePath "${candidate}" "${directory}/config.json" || return 1
        [[ ! -e "${directory}/config.json" || -f "${directory}/config.json" ]] || return 1
        [[ -f "${directory}/config.json" ]] || continue
        [[ -z "$(find "${directory}" -type l -print -quit)" ]] || return 1
        cp -a -- "${directory}" "${stage}/${core}" || return 1
        source=${stage}/${core}/users.base
        if [[ ! -e "${source}" ]]; then
            cp -- "${directory}/config.json" "${source}" || return 1
        fi
        [[ -f "${source}" ]] || return 1
        jq -es 'length == 1 and (.[0] | type == "object")' "${source}" >/dev/null || return 1
        dockerTrafficRender "${core}" "${source}" "${state}" >"${stage}/${core}/config.json" || return 1
        chmod 0600 "${source}" && chmod 0640 "${stage}/${core}/config.json" || return 1
        prepared+=("${core}")
    done
    for core in "${prepared[@]}"; do
        mv -- "${candidate}/config/${core}" "${stage}/old-${core}" || { failed=true; break; }
        moved+=("${core}")
        mv -- "${stage}/${core}" "${candidate}/config/${core}" || { failed=true; break; }
    done
    if [[ "${failed}" == true ]]; then
        for core in "${moved[@]}"; do
            if [[ -e "${candidate}/config/${core}" ]]; then
                dockerRemoveManagedTree "${candidate}" "${candidate}/config/${core}" || { keep=true; continue; }
            fi
            mv -- "${stage}/old-${core}" "${candidate}/config/${core}" || keep=true
        done
        [[ "${keep}" == false ]] || dockerError "统计候选配置恢复失败，备份位于: ${stage}"
        return 1
    fi
)

dockerTrafficContainerState() {
    local core=$1 container metadata
    container=$(dockerComposeRun ps -q "${core}") || return 1
    [[ "${container}" =~ ^[a-f0-9]{12,64}$ ]] || { dockerError '无法确认运行中的核心容器'; return 1; }
    metadata=$(docker inspect --format '{{json .}}' "${container}") || return 1
    jq -ce --arg core "${core}" --arg project "${PADM_DOCKER_PROJECT}" '
      select(.State.Running == true and (.State.Pid | type == "number" and . > 1 and . == floor) and
        (.Id | test("^[a-f0-9]{64}$")) and (.State.StartedAt | type == "string" and length > 0) and
        .Config.Labels["com.docker.compose.project"] == $project and
        .Config.Labels["com.docker.compose.service"] == $core) |
      {id:.Id, started_at:.State.StartedAt, pid:.State.Pid}
    ' <<<"${metadata}"
}

dockerTrafficQuery() (
    set -o pipefail
    local core=$1 pid=$2 root temporary
    if [[ "${core}" == xray ]]; then
        dockerComposeRun exec -T xray /usr/local/bin/xray api statsquery --server=127.0.0.1:10085 -pattern user
        return $?
    fi
    dockerRequireCommand nsenter && dockerRequireCommand curl || return 1
    curl --version | grep -Eq '^Features:.*[[:space:]]HTTP2([[:space:]]|$)' || {
        dockerError 'sing-box 流量采集需要支持 HTTP2 的 curl'
        return 1
    }
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/data/traffic" || return 1
    mkdir -p -- "${root}/data/traffic" || return 1
    [[ -O "${root}/data/traffic" ]] && chmod 0700 "${root}/data/traffic" || return 1
    temporary=$(mktemp -d "${root}/data/traffic/.query.XXXXXX") || return 1
    trap 'dockerRemoveManagedTree "${root}" "${temporary}"' EXIT
    printf '\000\000\000\000\006\032\004user' >"${temporary}/request.bin" || return 1
    nsenter --target "${pid}" --net curl -fsS --http2-prior-knowledge --noproxy '*' --connect-timeout 2 --max-time 5 \
        -D "${temporary}/headers" -H 'Content-Type: application/grpc' -H 'TE: trailers' \
        --data-binary "@${temporary}/request.bin" --output "${temporary}/response.bin" \
        http://127.0.0.1:10087/v2ray.core.app.stats.command.StatsService/QueryStats || return 1
    awk '{sub(/\r$/, ""); if (tolower($0) == "grpc-status: 0") ok=1} END {exit !ok}' "${temporary}/headers" || return 1
    singBoxGrpcResponseToStatsJson "${temporary}/response.bin"
)

dockerTrafficSnapshot() {
    local core accounts before after stats state counters next generation
    core=$(dockerTrafficCore) || return 1
    accounts=$(dockerTrafficAccounts "${core}") || return 1
    state=$(dockerTrafficReadState) || return 1
    before=$(dockerTrafficContainerState "${core}") || return 1
    stats=$(dockerTrafficQuery "${core}" "$(jq -r '.pid' <<<"${before}")") || {
        dockerError '用户统计 API 采集失败，已保留累计流量'
        return 1
    }
    after=$(dockerTrafficContainerState "${core}") || return 1
    [[ "${before}" == "${after}" ]] || { dockerError '采样期间核心容器发生变化，已丢弃本次结果'; return 1; }
    generation=$(jq -r '.id + ":" + .started_at' <<<"${before}") || return 1
    counters=$(jq -ce --argjson accounts "${accounts}" '
      def count: type == "number" and . >= 0 and . <= 9007199254740991 and . == floor;
      if type != "object" then error("统计响应格式无效") else . end |
      (if has("stat") then .stat else [] end) |
      if type != "array" then error("统计响应格式无效") else . end |
      reduce .[] as $item ({};
        if ($item.name | type) != "string" then error("统计项名称无效") else . end |
        (($item.name | capture("^user>>>(?<account>[A-Za-z0-9_.@+-]{1,128})>>>traffic>>>(?<direction>uplink|downlink)$")?) // null) as $key |
        if $key == null or ([$accounts[].account] | index($key.account)) == null then .
        else ((if $item | has("value") then $item.value else 0 end) |
            if type == "string" and test("^[0-9]+$") then tonumber else . end) as $value |
          (if $key.direction == "uplink" then "upload" else "download" end) as $direction |
          if ($value | count | not) or .[$key.account][$direction] != null then error("统计计数无效或重复")
          else .[$key.account][$direction] = $value end
        end)
    ' <<<"${stats}") || return 1
    next=$(jq -c --arg core "${core}" --arg generation "${generation}" --argjson accounts "${accounts}" --argjson counters "${counters}" '
      reduce $accounts[] as $account (.;
        .accounts[$account.account] = ((.accounts[$account.account] //
          {upload:0, download:0, limit_bytes:0, baseline:{}}) + {name:$account.name}) |
        reduce ["upload", "download"][] as $direction (.;
          ($counters[$account.account][$direction] // null) as $value |
          if $value == null then . else
            (.accounts[$account.account].baseline[$core][$direction] // {}) as $previous |
            .accounts[$account.account][$direction] +=
              (if $previous.generation == $generation and $value >= ($previous.value // 0)
               then $value - ($previous.value // 0) else $value end) |
            .accounts[$account.account].baseline[$core][$direction] = {generation:$generation, value:$value}
          end))
    ' <<<"${state}") || return 1
    dockerTrafficWriteState <<<"${next}"
}

dockerTrafficRestartCore() {
    local core=$1
    dockerComposeRun restart --no-deps "${core}" &&
        dockerComposeRun up -d --no-deps --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" "${core}"
}

dockerTrafficApplyQuotas() (
    local core root directory base config state temporary backup='' keep=false
    core=$(dockerTrafficCore) || return 1
    root=$(dockerInstallRoot) || return 1
    directory=${root}/config/${core}
    base=${directory}/users.base
    config=${directory}/config.json
    dockerTrafficSafePath "${root}" "${base}" && dockerTrafficSafePath "${root}" "${config}" || return 1
    [[ -f "${base}" && -f "${config}" ]] || return 1
    state=$(dockerTrafficReadState) || return 1
    temporary=$(mktemp "${directory}/.traffic-candidate.XXXXXX") || return 1
    trap 'rm -f -- "${temporary}"; [[ "${keep}" == true || -z "${backup}" ]] || rm -f -- "${backup}"' EXIT
    dockerTrafficRender "${core}" "${base}" "${state}" >"${temporary}" || return 1
    cmp -s "${temporary}" "${config}" && return 0
    chmod 0640 "${temporary}" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
        chown "0:${PADM_DOCKER_CONTAINER_GID:-10001}" "${temporary}" || return 1
    fi
    if [[ "${core}" == xray ]]; then
        dockerComposeRun run --rm --no-deps xray -test -format json -config "/etc/padm/xray/${temporary##*/}" || return 1
    else
        dockerComposeRun run --rm --no-deps sing-box check -D /var/lib/padm/sing-box -c "/etc/padm/sing-box/${temporary##*/}" || return 1
    fi
    backup=$(mktemp "${directory}/.traffic-backup.XXXXXX") || return 1
    cp -p -- "${config}" "${backup}" && mv -f -- "${temporary}" "${config}" || return 1
    if ! dockerTrafficRestartCore "${core}"; then
        if ! mv -f -- "${backup}" "${config}"; then
            keep=true
            dockerError "额度配置恢复失败，累计流量已保留；备份: ${backup}"
            return 1
        fi
        dockerTrafficRestartCore "${core}" || dockerError '额度配置已恢复，但核心重启失败'
        dockerError '额度应用失败，已恢复旧配置并保留累计流量'
        return 1
    fi
)

dockerTrafficCollect() {
    dockerTrafficSnapshot && dockerTrafficApplyQuotas
}

dockerTrafficSetLimit() {
    local account=$1 bytes=$2 state
    [[ "${account}" =~ ^[A-Za-z0-9_.@+-]{1,128}$ && "${bytes}" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
    jq -en --arg value "${bytes}" '$value | tonumber | . <= 9007199254740991' >/dev/null || return 1
    dockerTrafficSnapshot || return 1
    state=$(dockerTrafficReadState) || return 1
    state=$(jq -ce --arg account "${account}" --argjson bytes "${bytes}" '
      if .accounts[$account] == null then error("未知流量账号") else .accounts[$account].limit_bytes = $bytes end
    ' <<<"${state}") || return 1
    dockerTrafficWriteState <<<"${state}" && dockerTrafficApplyQuotas
}

dockerTrafficReset() {
    local account=$1 state
    [[ "${account}" =~ ^[A-Za-z0-9_.@+-]{1,128}$ ]] || return 1
    dockerTrafficSnapshot || return 1
    state=$(dockerTrafficReadState) || return 1
    state=$(jq -ce --arg account "${account}" '
      if .accounts[$account] == null then error("未知流量账号") else
        .accounts[$account].upload = 0 | .accounts[$account].download = 0 end
    ' <<<"${state}") || return 1
    dockerTrafficWriteState <<<"${state}" && dockerTrafficApplyQuotas
}

dockerTrafficShow() {
    local state
    state=$(dockerTrafficReadState) || return 1
    printf '账号\t名称\t上传(bytes)\t下载(bytes)\t限额(bytes)\t状态\n'
    jq -r '.accounts | to_entries | sort_by(.key)[] |
      [.key, .value.name, .value.upload, .value.download, .value.limit_bytes,
       (if .value.limit_bytes > 0 and (.value.upload + .value.download) >= .value.limit_bytes
        then "超额" else "正常" end)] | @tsv' <<<"${state}"
}
