#!/usr/bin/env bash

if [[ "${PADM_DOCKER_CONTROL_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_CONTROL_LOADED=1

dockerControlPrivateAddressIsValid() {
    jq -en --arg address "$1" '
      $address | (split(".") as $parts | ($parts | length) == 4 and
        all($parts[]; test("^(0|[1-9][0-9]{0,2})$") and tonumber <= 255)) and
        test("^(10\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.)")
    ' >/dev/null 2>&1
}

dockerControlPeerCheck() {
    # 归属健康已核对运行快照；这里只读比对配置和在线唯一 Peer 的 /32 地址。
    DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T net-wireguard bash -euo pipefail -c '
configured=$(wg-quick strip /etc/wireguard/wg-padm.conf | awk -v address="$1/32" '"'"'
    {
        line=$0; sub(/#.*/, "", line)
        gsub(/^[ \t]+|[ \t]+$/, "", line)
        if (line ~ /^\[/) {
            section=line
            if (section == "[Peer]") peers++
            next
        }
        if (section != "[Peer]") next
        if (line ~ /^PublicKey[ \t]*=/) {
            keys++; key=line; sub(/^[^=]*=[ \t]*/, "", key)
        }
        if (line ~ /^AllowedIPs[ \t]*=/) {
            ranges++; allowed=line; sub(/^[^=]*=[ \t]*/, "", allowed)
            gsub(/[ \t]/, "", allowed)
        }
    }
    END {
        if (peers != 1 || keys != 1 || ranges != 1 || allowed != address ||
            length(key) != 44 || key !~ /^[A-Za-z0-9+\/]+=$/) exit 1
        print key
    }
'"'"')
actual=$(wg show wg-padm allowed-ips)
[[ "$actual" == "$(printf "%s\t%s" "$configured" "$1/32")" ]]
' padm-control-peer "$1" >/dev/null 2>&1
}

dockerControlInit() (
    local address= port= peerAddress= yes=0 answer root spec draft= image nodeId peerId tokenHash metadata mode parent
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --address)
            [[ -z "${address}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            address=$2; shift 2
            ;;
        --port)
            [[ -z "${port}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            port=$2; shift 2
            ;;
        --peer-address)
            [[ -z "${peerAddress}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            peerAddress=$2; shift 2
            ;;
        --yes) [[ "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"; yes=1; shift ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerControlPrivateAddressIsValid "${address}" &&
        dockerControlPrivateAddressIsValid "${peerAddress}" &&
        [[ "${address}" != "${peerAddress}" && "${port}" =~ ^[1-9][0-9]{3,4}$ ]] &&
        ((port >= 1024 && port <= 65535)) || {
        dockerError '主控与 Peer 地址须为不同的 RFC1918 IPv4，端口须为 1024-65535'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
        dockerError '初始化主控需要 --yes 确认'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${yes}" != 1 ]]; then
        dockerSetupRead answer "确认初始化主控 ${address}:${port}，Peer ${peerAddress}？[y/N]: " n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    # 先检查原目录，不能让部署锁收紧 root 权限或候选副本掩盖不安全输入。
    for parent in "${root}" "${root}/config"; do
        dockerTrafficSafePath "${root}" "${parent}" && [[ -d "${parent}" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        metadata=$(stat -c '%u:%a' "${parent}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${metadata}" == 0:* ]] || return "${PADM_DOCKER_RC_STATE}"
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || return "${PADM_DOCKER_RC_STATE}"
    done
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'dockerConfigurationInterrupted; [[ -z "${draft}" ]] || dockerRemoveManagedTree "${root}" "${draft}" || true; dockerReleaseDeploymentLock' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    spec=$(dockerAccountSpecFile) || return $?
    jq -e 'has("control") or has("control_sync")' "${spec}" >/dev/null && {
        dockerError '当前部署已有主控或被控角色，拒绝重复初始化'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    dockerControlRecoveryCheck || return "${PADM_DOCKER_RC_STATE}"
    dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        dockerCurrentOwnsHostIntegration wireguard || {
        dockerError '主控初始化仅支持已有受管 WireGuard 的完整配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T net-wireguard \
        /usr/local/bin/padm-entrypoint wireguard-health wg-padm >/dev/null 2>&1 &&
        dockerControlPeerCheck "${peerAddress}" || {
        dockerError '受管 WireGuard 归属或唯一 Peer /32 地址核验失败'
        return "${PADM_DOCKER_RC_HOST}"
    }
    image=$(dockerAccountImage ops) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityProbeRun 10 --user 10001:10001 --network host \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint python3 "${image}" -c '
import sys
sys.path.insert(0, "/opt/padm")
from control_api import require_wireguard_address
require_wireguard_address({"listen": {"interface": "wg-padm", "address": sys.argv[1]}})
' "${address}" >/dev/null 2>&1 || {
        dockerError '主控监听地址不属于受管 wg-padm 接口'
        return "${PADM_DOCKER_RC_HOST}"
    }
    nodeId=$(dockerAccountRandomUuid "${spec}") &&
        peerId=$(dockerAccountRandomUuid "${spec}" "${nodeId}") || return "${PADM_DOCKER_RC_STATE}"
    # 占位授权禁用且过期；随机原文只经管道送入摘要，不写草稿或传入参数。
    tokenHash=$(set -o pipefail; dockerSetupRandomHex "${image}" 32 | tr -d '\r\n' | sha256sum) ||
        return "${PADM_DOCKER_RC_STATE}"
    tokenHash=${tokenHash%% *}
    [[ "${tokenHash}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    draft=$(mktemp -d "${root}/.control-init.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" &&
        (umask 077; dockerConfigureSpecMigrate "${spec}" "${draft}/spec.json") ||
        return "${PADM_DOCKER_RC_STATE}"
    (umask 077; jq --arg nodeId "${nodeId}" --arg peerId "${peerId}" --arg address "${address}" \
        --argjson port "${port}" --arg peerAddress "${peerAddress}" --arg tokenHash "${tokenHash}" '
      .control = {
        schema_version: 1, role: "main", node_id: $nodeId,
        listen: {interface: "wg-padm", address: $address, port: $port},
        peer: {id: $peerId, address: $peerAddress, enabled: false, expires_at: 1,
          token_sha256: $tokenHash},
        revision: 0, last_digest: null
      }
    ' "${draft}/spec.json" >"${draft}/next.json") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json" || return $?
    printf '主控已初始化，Peer 授权保持禁用。\n'
)

dockerControlStatus() (
    local json=${1:-0} spec root role healthy=null result
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap dockerReleaseDeploymentLock EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    spec=$(dockerAccountSpecFile) || return $?
    role=$(jq -r 'if has("control") then "main" elif has("control_sync") then "controlled"
        else "standalone" end' "${spec}") || return "${PADM_DOCKER_RC_STATE}"
    case "${role}" in
    main)
        dockerControlStateCheck "${root}" || return "${PADM_DOCKER_RC_STATE}"
        healthy=false
        if DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T control \
            /usr/local/bin/padm-entrypoint control-health --state /etc/padm/control/state.json \
            >/dev/null 2>&1; then healthy=true; fi
        ;;
    controlled) dockerControlSyncSpecValidate "${spec}" || return "${PADM_DOCKER_RC_STATE}" ;;
    esac
    result=$(jq -c --arg role "${role}" --argjson healthy "${healthy}" '
      if $role == "main" then {
        role: $role, node_id: .control.node_id, controller_id: null,
        listen: .control.listen, peer_address: .control.peer.address,
        revision: .control.revision, healthy: $healthy
      } elif $role == "controlled" then {
        role: $role, node_id: .control_sync.node_id, controller_id: .control_sync.controller_id,
        listen: null, peer_address: null, revision: .control_sync.last_revision, healthy: null
      } else {
        role: $role, node_id: null, controller_id: null, listen: null,
        peer_address: null, revision: null, healthy: null
      } end
    ' "${spec}") || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${json}" == 1 ]]; then
        printf '%s\n' "${result}"
    else
        jq -r 'to_entries[] | "\(.key)=\(.value | if type == "object" then tojson else tostring end)"' \
            <<<"${result}"
    fi
)

dockerControlCommand() {
    local action=${1:-} json=0
    shift || true
    case "${action}" in
    status)
        if [[ "$#" == 1 && "$1" == --json ]]; then json=1; shift; fi
        [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerControlStatus "${json}"
        ;;
    init) dockerControlInit "$@" ;;
    *)
        dockerError '用法: control status [--json] | control init --address <IPv4> --port <端口> --peer-address <IPv4> [--yes]'
        return "${PADM_DOCKER_RC_USAGE}"
        ;;
    esac
}
