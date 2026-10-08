#!/usr/bin/env bash

if [[ "${PADM_DOCKER_CONTROL_SYNC_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_CONTROL_SYNC_LOADED=1

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
