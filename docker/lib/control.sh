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

dockerControlRequireMain() {
    local spec=$1 root=$2
    jq -e '.control.role == "main" and (has("control_sync") | not)' "${spec}" >/dev/null || {
        dockerError '邀请和撤销仅适用于已初始化的主控角色'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    dockerControlRecoveryCheck &&
        dockerControlStateCheck "${root}" "${3:-}" &&
        dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" ||
        return "${PADM_DOCKER_RC_STATE}"
}

dockerControlInviteRuntimeCheck() {
    local spec=$1 image address peerAddress
    address=$(jq -er '.control.listen.address' "${spec}") &&
        peerAddress=$(jq -er '.control.peer.address' "${spec}") &&
        dockerControlPrivateAddressIsValid "${address}" &&
        dockerControlPrivateAddressIsValid "${peerAddress}" &&
        dockerCurrentOwnsHostIntegration wireguard &&
        DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T net-wireguard \
            /usr/local/bin/padm-entrypoint wireguard-health wg-padm >/dev/null 2>&1 &&
        dockerControlPeerCheck "${peerAddress}" || return "${PADM_DOCKER_RC_HOST}"
    image=$(dockerAccountImage ops) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityProbeRun 10 --user 10001:10001 --network host \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint python3 "${image}" -c '
import sys
sys.path.insert(0, "/opt/padm")
from control_api import require_wireguard_address
require_wireguard_address({"listen": {"interface": "wg-padm", "address": sys.argv[1]}})
' "${address}" >/dev/null 2>&1 || return "${PADM_DOCKER_RC_HOST}"
}

dockerControlRandomToken() {
    local image=$1
    dockerRealityProbeRun 10 --log-driver none --network none \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint openssl "${image}" rand -hex 24 2>/dev/null
}

dockerControlInviteOutputCheck() {
    local output=$1 root=$2 parent cursor metadata mode resolved
    root=$(realpath -m -s -- "${root}") || return "${PADM_DOCKER_RC_USAGE}"
    dockerPathIsSafeAbsolute "${output}" &&
        resolved=$(realpath -m -s -- "${output}") && [[ "${resolved}" == "${output}" ]] &&
        [[ "${output}" != "${root}" && "${output}" != "${root%/}/"* &&
            ! -e "${output}" && ! -L "${output}" ]] || {
        dockerError '邀请输出须为受管目录之外且尚不存在的绝对路径'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    parent=$(dirname -- "${output}") || return "${PADM_DOCKER_RC_USAGE}"
    cursor=${parent}
    while true; do
        [[ -d "${cursor}" && ! -L "${cursor}" ]] || return "${PADM_DOCKER_RC_USAGE}"
        metadata=$(stat -c '%u:%a' "${cursor}") || return "${PADM_DOCKER_RC_USAGE}"
        [[ "${metadata}" == 0:* ]] || return "${PADM_DOCKER_RC_USAGE}"
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || {
            dockerError '邀请输出的父目录须由 root 所有，且禁止组或其他用户写入'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        [[ "${cursor}" != / ]] || break
        cursor=$(dirname -- "${cursor}") || return "${PADM_DOCKER_RC_USAGE}"
    done
}

dockerControlInvite() (
    local output= expiresIn=86400 seenExpires=0 yes=0 answer root spec draft= temporary= published=0
    local image tokenHash expiresAt metadata mode parent
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --output)
            [[ -z "${output}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            output=$2; shift 2
            ;;
        --expires-in)
            [[ "${seenExpires}" == 0 && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            expiresIn=$2; seenExpires=1; shift 2
            ;;
        --yes) [[ "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"; yes=1; shift ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ -n "${output}" && "${expiresIn}" =~ ^[1-9][0-9]{1,5}$ ]] &&
        ((expiresIn >= 60 && expiresIn <= 604800)) || return "${PADM_DOCKER_RC_USAGE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerControlInviteOutputCheck "${output}" "${root}" || return $?
    [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
        dockerError '生成或轮换邀请需要 --yes 确认'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${yes}" != 1 ]]; then
        dockerSetupRead answer "确认生成或轮换邀请至 ${output}，有效 ${expiresIn} 秒？[y/N]: " n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    # 原目录权限先于锁的 chmod；邀请草稿不能洗白不安全的在线状态。
    for parent in "${root}" "${root}/config"; do
        dockerTrafficSafePath "${root}" "${parent}" && [[ -d "${parent}" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        metadata=$(stat -c '%u:%a' "${parent}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${metadata}" == 0:* ]] || return "${PADM_DOCKER_RC_STATE}"
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || return "${PADM_DOCKER_RC_STATE}"
    done
    trap 'status=$?; dockerConfigurationInterrupted; [[ -z "${temporary}" ]] || rm -f -- "${temporary}"; [[ -z "${draft}" ]] || dockerRemoveManagedTree "${root}" "${draft}" || true; dockerReleaseDeploymentLock; if [[ "${status}" != 0 && "${published}" == 1 ]]; then dockerError "邀请文件已保留，授权状态未确认，请查看 control status: ${output}"; fi; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    spec=$(dockerAccountSpecFile) || return $?
    dockerControlRequireMain "${spec}" "${root}" &&
        dockerControlInviteRuntimeCheck "${spec}" || return $?
    draft=$(mktemp -d "${root}/.control-invite.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" && cp -- "${spec}" "${draft}/spec.json" &&
        chmod 0600 "${draft}/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    image=$(dockerAccountImage ops) || return "${PADM_DOCKER_RC_STATE}"
    dockerReleaseDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerControlInviteOutputCheck "${output}" "${root}" || return $?
    parent=$(dirname -- "${output}") || return "${PADM_DOCKER_RC_USAGE}"
    temporary=$(mktemp "${parent}/.padm-control-invite.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0600 "${temporary}" && chown 0:0 "${temporary}" || return "${PADM_DOCKER_RC_STATE}"
    expiresAt=$(date +%s) || return "${PADM_DOCKER_RC_STATE}"
    [[ "${expiresAt}" =~ ^[0-9]{1,10}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    expiresAt=$((expiresAt + expiresIn))
    # 原文只经标准输入写入私有邀请，不展开到 jq 参数、环境或在线规格。
    (set -o pipefail; dockerControlRandomToken "${image}" | jq -Rs --slurpfile spec "${draft}/spec.json" \
        --argjson expiresAt "${expiresAt}" '
      rtrimstr("\n") |
      if length == 48 and test("^[a-f0-9]{48}$") then {
        format: "padm-docker-control-invite", schema_version: 1,
        controller_id: $spec[0].control.node_id, node_id: $spec[0].control.peer.id,
        listen: $spec[0].control.listen,
        peer_address: $spec[0].control.peer.address, token: ., expires_at: $expiresAt
      } else error("invalid invitation token") end
    ' >"${temporary}") || return "${PADM_DOCKER_RC_STATE}"
    tokenHash=$(set -o pipefail; jq -ejr '.token' "${temporary}" | sha256sum) ||
        return "${PADM_DOCKER_RC_STATE}"
    tokenHash=${tokenHash%% *}
    [[ "${tokenHash}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    # -T 防止竞争者把输出换成目录；硬链接原子交付且绝不覆盖已有文件。
    ln -T -- "${temporary}" "${output}" || return "${PADM_DOCKER_RC_STATE}"
    published=1
    rm -f -- "${temporary}" && temporary= || return "${PADM_DOCKER_RC_STATE}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    spec=$(dockerAccountSpecFile) || return $?
    dockerControlRequireMain "${spec}" "${root}" &&
        jq -en --slurpfile current "${spec}" --slurpfile saved "${draft}/spec.json" \
            '$current[0].control == $saved[0].control' >/dev/null &&
        dockerControlInviteRuntimeCheck "${spec}" || {
        dockerError '邀请交付后主控身份、授权或网络状态已改变，拒绝启用'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    (umask 077; jq --arg tokenHash "${tokenHash}" --argjson expiresAt "${expiresAt}" '
      .control.peer |= . + {token_sha256: $tokenHash, enabled: true, expires_at: $expiresAt}
    ' "${spec}" >"${draft}/next.json") || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json" || return $?
    printf '主控邀请已启用，私有文件: %s\n' "${output}"
)

dockerControlRevoke() (
    local yes=0 answer root spec draft=
    if [[ "$#" == 1 && "$1" == --yes ]]; then yes=1; shift; fi
    [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
        dockerError '撤销主控授权需要 --yes 确认'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${yes}" != 1 ]]; then
        dockerSetupRead answer '确认撤销当前 Peer 授权？[y/N]: ' n || return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    # 撤销仅依赖已验证状态；WireGuard 故障不能阻止禁用授权。
    dockerControlStateCheck "${root}" revoke || return "${PADM_DOCKER_RC_STATE}"
    trap '[[ -z "${draft}" ]] || dockerRemoveManagedTree "${root}" "${draft}" || true; dockerReleaseDeploymentLock' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    spec=$(dockerAccountSpecFile) || return $?
    dockerControlRequireMain "${spec}" "${root}" revoke || return $?
    if jq -e '.control.peer.enabled == false and .control.peer.expires_at == 1' "${spec}" >/dev/null; then
        printf 'Peer 授权已撤销，无需重复部署。\n'
        return 0
    fi
    draft=$(mktemp -d "${root}/.control-revoke.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" &&
        (umask 077; jq '.control.peer |= . + {enabled: false, expires_at: 1}' \
            "${spec}" >"${draft}/spec.json" &&
            jq '.peer |= . + {enabled: false, expires_at: 1}' \
                "${root}/config/control/state.json" >"${draft}/state.json") &&
        chmod 0600 "${draft}/spec.json" &&
        chmod 0640 "${draft}/state.json" &&
        chown 0:0 "${draft}/spec.json" &&
        chown "0:${PADM_DOCKER_CONTAINER_GID}" "${draft}/state.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    [[ "$(stat -c '%d' "${draft}")" == "$(stat -c '%d' "${root}/config/control")" &&
        "$(stat -c '%d' "${draft}")" == "$(stat -c '%d' "${root}/config")" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    # 先禁用 API；规格写入中断时不恢复授权，重复撤销只补齐同一份禁用状态。
    mv -T -- "${draft}/state.json" "${root}/config/control/state.json" &&
        mv -T -- "${draft}/spec.json" "${spec}" || {
        dockerError '撤销写入未完成，请重复执行 revoke；已禁用的授权不会恢复'
        return "${PADM_DOCKER_RC_STATE}"
    }
    printf 'Peer 授权已撤销。\n'
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
        revision: .control.revision, healthy: $healthy,
        authorization: {enabled: .control.peer.enabled, expires_at: .control.peer.expires_at}
      } elif $role == "controlled" then {
        role: $role, node_id: .control_sync.node_id, controller_id: .control_sync.controller_id,
        listen: null, peer_address: null, revision: .control_sync.last_revision, healthy: null,
        authorization: null
      } else {
        role: $role, node_id: null, controller_id: null, listen: null,
        peer_address: null, revision: null, healthy: null, authorization: null
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
    invite) dockerControlInvite "$@" ;;
    revoke) dockerControlRevoke "$@" ;;
    *)
        dockerError '用法: control status [--json] | init --address <IPv4> --port <端口> --peer-address <IPv4> [--yes] | invite --output <绝对路径> [--expires-in <秒>] [--yes] | revoke [--yes]'
        return "${PADM_DOCKER_RC_USAGE}"
        ;;
    esac
}
