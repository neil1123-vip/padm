#!/usr/bin/env bash

if [[ "${PADM_DOCKER_CONTROL_SYNC_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_CONTROL_SYNC_LOADED=1
readonly PADM_DOCKER_CONTROL_SYNC_SCHEDULE_SCHEMA=1
DOCKER_CONTROL_SYNC_SCHEDULE_STAGE=
DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED=0

dockerControlSyncScheduleJsonCheck() {
    # 值路径与结束时的容器路径均须唯一，正常数组按数字路径区分。
    jq --stream -es '
      [.[] | if length == 2 then .[0] else .[0][:-1] end | select(length > 0)] |
      length == (unique | length)
    ' "$1" >/dev/null 2>&1
}

dockerControlSyncScheduleValidate() {
    local root=$1 directory="${1}/secrets/control-sync" file parent mode
    dockerTrafficSafePath "${root}" "${directory}" || return 1
    [[ -e "${directory}" ]] || return 0
    [[ -d "${directory}" && "$(stat -c '%u:%g:%a' "${directory}")" == 0:0:700 &&
        -z "$(find "${directory}" -mindepth 1 -maxdepth 1 \
            ! -path "${directory}/request.json" ! -path "${directory}/invite.json" -print -quit)" ]] || return 1
    parent=${directory}
    while :; do
        [[ -d "${parent}" && ! -L "${parent}" && "$(stat -c %u "${parent}")" == 0 ]] || return 1
        mode=$(stat -c %a "${parent}") || return 1
        (( (8#${mode} & 022) == 0 )) || return 1
        [[ "${parent}" != / ]] || break
        parent=$(dirname -- "${parent}")
    done
    for file in request.json invite.json; do
        [[ -f "${directory}/${file}" && ! -L "${directory}/${file}" &&
            "$(stat -c '%u:%g:%a:%h' "${directory}/${file}")" == 0:0:600:1 &&
            "$(stat -c %s "${directory}/${file}")" -le 1048576 ]] || return 1
    done
    jq -es '
      def uuid: type == "string" and
        test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$");
      def private_address: type == "string" and
        (split(".") as $parts | ($parts | length) == 4 and
          all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255)) and
        test("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)");
      length == 1 and (.[0] | type == "object" and
      keys == ["connection","controller_id","enabled","listener_ids","node_id","schema_version"] and
      .schema_version == 1 and .enabled == true and
      (.node_id | uuid) and (.controller_id | uuid) and .node_id != .controller_id and
      (.listener_ids | type == "array" and length > 0 and length <= 16 and
        length == (unique | length) and all(.[]; type == "string" and
          test("^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$"))) and
      (.connection | type == "object" and keys == ["listen","peer_address"] and
        (.peer_address | private_address) and
        (.listen | type == "object" and keys == ["address","interface","port"] and
          .interface == "wg-padm" and (.address | private_address) and
          (.port | type == "number" and floor == . and . >= 1024 and . <= 65535)) and
        .listen.address != .peer_address))' \
        "${directory}/request.json" >/dev/null 2>&1 &&
        jq -es 'length == 1 and (.[0] | type == "object" and
          keys == ["controller_id","expires_at","format","listen","node_id","peer_address","schema_version","token"] and
          .schema_version == 1 and .format == "padm-docker-control-invite" and
          (.token | type == "string" and test("^[a-f0-9]{48}$")) and
          (.expires_at | type == "number" and floor == . and . > 0 and . <= 9007199254740991))' \
            "${directory}/invite.json" >/dev/null 2>&1 &&
        jq -en --slurpfile request "${directory}/request.json" --slurpfile invite "${directory}/invite.json" '
          $request[0] as $r | $invite[0] as $i |
          $r.node_id == $i.node_id and $r.controller_id == $i.controller_id and
          $r.connection == {listen:$i.listen,peer_address:$i.peer_address}
        ' >/dev/null 2>&1 &&
        dockerControlSyncScheduleJsonCheck "${directory}/request.json" &&
        dockerControlSyncScheduleJsonCheck "${directory}/invite.json"
}

dockerControlSyncScheduleSpecCheck() {
    local spec=$1 root directory
    root=$(dockerInstallRoot) || return 1
    directory="${root}/secrets/control-sync"
    dockerControlSyncScheduleValidate "${root}" || return 1
    [[ -d "${directory}" ]] || return 0
    jq -en --slurpfile request "${directory}/request.json" --slurpfile spec "${spec}" '
      ($spec | length) == 1 and ($spec[0].control_sync as $s | $request[0] as $r |
        $spec[0].control == null and $s.role == "controlled" and
        $s.node_id == $r.node_id and $s.controller_id == $r.controller_id and
        $s.connection == $r.connection and $s.listener_ids == $r.listener_ids and
        all($spec[0].host_integrations[]; .type != "fail2ban" and
          .type != "fail2ban-control" and .type != "fail2ban-ssh"))
    ' >/dev/null 2>&1 || {
        dockerError '自动同步登记身份、连接、入口或防护组合不支持，请先停用自动同步'
        return 1
    }
}

dockerControlSyncScheduleBundleCheck() {
    local bundle=$1 root
    root=$(dockerInstallRoot) || return 1
    dockerControlSyncScheduleValidate "${root}" || return 1
    [[ -d "${root}/secrets/control-sync" ]] || return 0
    [[ -f "${bundle}/docker/lib/control-sync.sh" && ! -L "${bundle}/docker/lib/control-sync.sh" ]] &&
        grep -qxF 'readonly PADM_DOCKER_CONTROL_SYNC_SCHEDULE_SCHEMA=1' \
            "${bundle}/docker/lib/control-sync.sh" || {
        dockerError '目标控制 bundle 不支持已启用的被控自动同步，请先停用自动同步或选择兼容版本'
        return 1
    }
}

dockerControlSyncScheduleRemove() {
    local unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system} content
    if [[ ! -e "${unitDir}/padm-docker-control-sync.service" && ! -L "${unitDir}/padm-docker-control-sync.service" &&
        ! -e "${unitDir}/padm-docker-control-sync.timer" && ! -L "${unitDir}/padm-docker-control-sync.timer" ]]; then
        command -v crontab >/dev/null 2>&1 || return 0
        content=$(dockerTrafficReadCrontab) || return 1
        [[ "${content}" == *'# padm-docker 被控账号自动同步'* ]] || return 0
    fi
    dockerMaintenanceScheduleApply remove control-sync
}

dockerControlSyncScheduleInstall() {
    local root role
    root=$(dockerInstallRoot) || return 1
    dockerControlSyncScheduleValidate "${root}" || return 1
    if [[ ! -d "${root}/secrets/control-sync" ]]; then
        dockerControlSyncScheduleRemove
        return $?
    fi
    role=$(dockerControlLogRole "${root}") || return 1
    if [[ "${role}" == unconfigured ]]; then
        dockerControlSyncScheduleRemove
        return $?
    fi
    dockerControlSyncScheduleSpecCheck "${root}/config/spec.json" &&
        dockerMaintenanceScheduleApply install control-sync
}

dockerControlSyncScheduleInterrupted() {
    local root directory stage=${DOCKER_CONTROL_SYNC_SCHEDULE_STAGE:-}
    dockerMaintenanceScheduleInterrupted control-sync || return 1
    [[ -n "${stage}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    directory="${root}/secrets/control-sync"
    dockerTrafficSafePath "${root}" "${stage}" &&
        [[ "${stage}" == "${root}/locks/control-sync-state."* && -d "${stage}" && -O "${stage}" &&
            -z "$(find "${stage}" ! -type f ! -type d -print -quit)" ]] || return 1
    if [[ "${DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED:-0}" == 1 ]]; then
        dockerTrafficSafePath "${root}" "${directory}" || return 1
        [[ ! -e "${directory}" ]] || dockerControlSyncScheduleValidate "${root}" || return 1
        [[ ! -d "${directory}" ]] || dockerRemoveManagedTree "${root}" "${directory}" || return 1
        [[ ! -d "${stage}/previous" ]] || cp -a -- "${stage}/previous" "${directory}" || return 1
        DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED=0
    fi
    dockerRemoveManagedTree "${root}" "${stage}" || return 1
    DOCKER_CONTROL_SYNC_SCHEDULE_STAGE=
}

dockerControlSyncSpecValidate() {
    jq -e '
      def exact($keys): type == "object" and ((keys_unsorted | sort) == ($keys | sort));
      def uuid: type == "string" and
        test("^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$");
      def private_address: type == "string" and
        (split(".") as $parts | ($parts | length) == 4 and
         all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255)) and
        test("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)");
      . as $spec |
      if has("control_sync") then
        .schema_version == 3 and
        (.control_sync |
          exact(["schema_version","role","node_id","controller_id","listener_ids",
            "last_revision","last_digest","managed_accounts"] +
            (if has("connection") then ["connection"] else [] end)) and
          .schema_version == 1 and .role == "controlled" and
          (.node_id | uuid) and (.controller_id | uuid) and .node_id != .controller_id and
          (if has("connection") then
            any($spec.host_integrations[]; .type == "wireguard") and
            (.connection |
              exact(["listen","peer_address"]) and (.peer_address | private_address) and
              (.listen | exact(["interface","address","port"]) and .interface == "wg-padm" and
                (.address | private_address) and
                (.port | type == "number" and floor == . and . >= 1024 and . <= 65535)) and
              .listen.address != .peer_address)
           else true end) and
          (.listener_ids | type == "array" and length >= 1 and length <= 16 and
            length == (unique | length) and all(.[]; . as $id |
              any($spec.core.protocols[]; .listener_id == $id))) and
          (.managed_accounts | type == "array" and length <= 256 and
            ([.[].id] | length == (unique | length))) and
          (if .last_revision == null then
            .last_digest == null and .managed_accounts == []
           else
            (.last_revision | type == "number" and floor == . and . >= 0 and . <= 9007199254740991) and
            (.last_digest | type == "string" and test("^[a-f0-9]{64}$"))
           end) and
          (.listener_ids as $listeners |
            all(.managed_accounts[]; . as $account |
              .listeners == $listeners and any($spec.accounts[]?; . == $account))))
      else true end
    ' "$1" >/dev/null 2>&1
}

dockerControlSyncTransitionValidate() {
    local source=$1 root
    [[ "${DOCKER_CONTROL_SYNC_TRANSACTION:-0}" != 1 ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerTrafficSafePath "${root}" "${root}/config/spec.json" || return 1
    [[ -f "${root}/config/spec.json" ]] || return 0
    jq -en --slurpfile current "${root}/config/spec.json" --slurpfile next "${source}" '
      $current[0].control_sync == $next[0].control_sync
    ' >/dev/null 2>&1 || {
        dockerError '角色、同步归属和入口映射只能通过控制事务修改'
        return 1
    }
}

dockerControlSyncRollbackCheck() {
    local backup=$1 root source current=false previous=false role
    root=$(dockerInstallRoot) || return 1
    for source in "${root}/config/spec.json" "${backup}/config/spec.json"; do
        [[ -e "${source}" || -L "${source}" ]] || continue
        dockerTrafficSafePath "${root}" "${source}" &&
            [[ -f "${source}" && ! -L "${source}" && -O "${source}" ]] &&
            dockerPrivateFileIsRestricted "${source}" &&
            role=$(jq -er 'has("control_sync") | tostring' "${source}") || return 1
        if [[ "${source}" == "${root}/config/spec.json" ]]; then
            current=${role}
        else
            previous=${role}
        fi
    done
    [[ "${current}:${previous}" != false:false ]] || return 0
    [[ "${current}:${previous}" == true:true ]] || {
        dockerError '回滚不能新增、删除或重绑定被控角色'
        return 1
    }
    dockerConfigureSpecValidate "${backup}/config/spec.json" &&
        dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
            "${root}/deployment.json" "${root}/images.env" || return 1
    # 只约束显式回滚；未提交同步失败仍恢复事务前备份，不伪造上游版本。
    jq -en --slurpfile current "${root}/config/spec.json" --slurpfile previous "${backup}/config/spec.json" '
      $current[0].control_sync as $current |
      $previous[0].control_sync as $previous |
      ($current | del(.last_revision, .last_digest, .managed_accounts)) ==
        ($previous | del(.last_revision, .last_digest, .managed_accounts)) and
      (if $current.last_revision == null then true
       elif $previous.last_revision == null then false
       elif $previous.last_revision > $current.last_revision then true
       else $previous.last_revision == $current.last_revision and
         $previous.last_digest == $current.last_digest and
         $previous.managed_accounts == $current.managed_accounts
       end)
    ' >/dev/null 2>&1 || {
        dockerError '回滚快照的被控身份、连接或同步版本/内容冲突，保留当前部署'
        return 1
    }
}

dockerControlSyncBuildDraft() {
    local directory=$1 image
    image=$(dockerAccountImage ops) || return 1
    # 私有输入只读挂载；无网络、无能力，不传账号凭据到参数。
    dockerRealityProbeRun 30 --user 0:0 --network none \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --mount "type=bind,src=${directory},dst=/input,readonly" \
        --entrypoint python3 "${image}" /opt/padm/control_sync.py \
        --spec /input/spec.json --desired /input/desired.json
}

# 仅供后续私网认证客户端调用；本阶段不开放文件导入 CLI 或菜单。
dockerControlSyncApply() (
    local desired=$1 root spec draft status=0
    root=$(dockerInstallRoot) || return 1
    dockerManagedPathIsSafe "${root}" "${desired}" &&
        dockerBusinessFileSafe "${desired}" &&
        [[ "$(stat -c '%s' "${desired}")" -le 1048576 ]] || {
        dockerError '同步响应必须是 root 私有普通文件，最大 1 MiB'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'dockerConfigurationInterrupted; dockerReleaseDeploymentLock' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    spec=$(dockerAccountSpecFile) || return $?
    jq -e '.control_sync.role == "controlled"' "${spec}" >/dev/null || {
        dockerError '当前部署尚未初始化被控同步角色'
        return "${PADM_DOCKER_RC_STATE}"
    }
    draft=$(mktemp -d "${root}/.control-sync.XXXXXX") || return 1
    trap 'dockerConfigurationInterrupted; dockerRemoveManagedTree "${root}" "${draft}"; dockerReleaseDeploymentLock' EXIT
    chmod 0700 "${draft}" || return 1
    cp -- "${spec}" "${draft}/spec.json" &&
        cp -- "${desired}" "${draft}/desired.json" &&
        chmod 0600 "${draft}/spec.json" "${draft}/desired.json" &&
        (umask 077; dockerControlSyncBuildDraft "${draft}" >"${draft}/next.json") &&
        dockerConfigureSpecValidate "${draft}/next.json" || {
        dockerError '同步规划失败，保留当前账号和配置'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    if jq -en --slurpfile current "${spec}" --slurpfile next "${draft}/next.json" \
        '$current == $next' >/dev/null; then
        printf '同步版本和内容未变，无需重新部署。\n'
        return 0
    fi
    DOCKER_CONTROL_SYNC_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json" || status=$?
    [[ "${status}" -ne 0 ]] || printf '被控账号同步已提交。\n'
    return "${status}"
)
