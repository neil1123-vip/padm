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
    local spec=$1 root=$2 recoveryMode=${4:-}
    [[ -z "${recoveryMode}" || "${recoveryMode}" == current ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    jq -e '.control.role == "main" and (has("control_sync") | not)' "${spec}" >/dev/null || {
        dockerError '邀请和撤销仅适用于已初始化的主控角色'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    dockerControlRecoveryCheck "${recoveryMode}" &&
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

dockerControlInviteInputCheck() {
    local input=$1 root=$2 resolved cursor metadata mode
    root=$(realpath -m -s -- "${root}") || return 1
    dockerPathIsSafeAbsolute "${input}" &&
        resolved=$(realpath -m -s -- "${input}") && [[ "${resolved}" == "${input}" ]] &&
        [[ "${input}" != "${root}" && "${input}" != "${root%/}/"* ]] &&
        dockerBusinessFileSafe "${input}" &&
        [[ "$(stat -c '%u:%s' "${input}")" == 0:* && "$(stat -c '%s' "${input}")" -le 1048576 ]] ||
        return 1
    mode=$(stat -c '%a' "${input}") || return 1
    (( (8#${mode} & ~8#600) == 0 )) || return 1
    cursor=$(dirname -- "${input}") || return 1
    while true; do
        [[ -d "${cursor}" && ! -L "${cursor}" ]] || return 1
        metadata=$(stat -c '%u:%a' "${cursor}") || return 1
        [[ "${metadata}" == 0:* ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 8#022) == 0 )) || return 1
        [[ "${cursor}" != / ]] || break
        cursor=$(dirname -- "${cursor}") || return 1
    done
}

dockerControlClientRuntimeCheck() {
    local invitation=$1 address peerAddress
    # 字段仅用于只读网络预检；完整邀请与重复 JSON 字段由客户端严格校验。
    address=$(jq -er '.listen.address' "${invitation}") &&
        peerAddress=$(jq -er '.peer_address' "${invitation}") &&
        dockerControlPrivateAddressIsValid "${address}" &&
        dockerControlPrivateAddressIsValid "${peerAddress}" &&
        [[ "${address}" != "${peerAddress}" ]] &&
        dockerCurrentOwnsHostIntegration wireguard &&
        DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T net-wireguard \
            /usr/local/bin/padm-entrypoint wireguard-health wg-padm >/dev/null 2>&1 &&
        dockerControlPeerCheck "${address}" || return "${PADM_DOCKER_RC_HOST}"
    DOCKER_COMPOSE_TIMEOUT=10 dockerComposeRun exec -T net-wireguard bash -euo pipefail -c '
ip -4 route get "$1" from "$2" | awk -v source="$2" '"'"'
    NR == 1 {
        for (i=1; i<=NF; i++) {
            if ($i == "dev") { count++; device=$(i+1) }
            if ($i == "from" || $i == "src") origin=$(i+1)
        }
    }
    END { if (count != 1 || device != "wg-padm" || origin != source) exit 1 }
'"'"'
' padm-control-route "${address}" "${peerAddress}" >/dev/null 2>&1 || {
        dockerError '到主控的指定源地址路由不属于 wg-padm，拒绝同步'
        return "${PADM_DOCKER_RC_HOST}"
    }
}

dockerControlSourceSnapshot() (
    local root spec service ids inspected image snapshots='[]' file hashes digest recoveryMode=
    root=$(dockerInstallRoot) || return 1
    spec="${root}/config/spec.json"
    if [[ "${completion:-}" == dockerFail2banStartManagedCommit &&
        "${mf_phase:-}" == witnessed && -n "${witnessOwner:-}" &&
        "${witnessOwner}" == "${mf_lockOwner:-}" &&
        "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null || true)" == "${witnessOwner}" ]]; then
        recoveryMode=current
    fi
    dockerControlRequireMain "${spec}" "${root}" '' "${recoveryMode}" &&
        dockerControlInviteRuntimeCheck "${spec}" &&
        cmp -s -- "${root}/compose.json" <(dockerGenerateCompose "${spec}" /dev/stdout "${root}") ||
        return 1
    for service in control net-wireguard; do
        ids=$(docker ps -aq --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
            --filter "label=com.docker.compose.service=${service}" \
            --filter label=com.docker.compose.oneoff=False) || return 1
        [[ "${ids}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
        inspected=$(docker container inspect "${ids}") &&
            image=$(jq -er --arg service "${service}" \
                '.images[if $service == "control" then "ops" else "net" end]' "${spec}") || return 1
        jq -e --arg root "${root}" --arg image "${image}" --arg service "${service}" \
            --slurpfile compose "${root}/compose.json" '
          length == 1 and (.[0] as $c | $compose[0].services[$service] as $s |
            ($c.Id | type == "string" and test("^[a-f0-9]{64}$")) and
            $c.State.Status == "running" and $c.State.Running == true and
            $c.State.Restarting == false and $c.State.Paused == false and $c.State.Dead == false and
            $c.State.Health.Status == "healthy" and
            ($c.State.StartedAt | type == "string" and
              test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,9})?Z$")) and
            ($c.RestartCount | type == "number" and floor == . and . >= 0) and
            $c.Config.Labels["com.docker.compose.project"] == "padm-docker" and
            $c.Config.Labels["com.docker.compose.project.working_dir"] == $root and
            $c.Config.Labels["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
            $c.Config.Labels["com.docker.compose.service"] == $service and
            $c.Config.Labels["com.docker.compose.oneoff"] == "False" and
            all($s.labels | to_entries[]; $c.Config.Labels[.key] == .value) and
            $c.Config.Image == $image and
            $c.Config.User == (if $service == "control" then "10001:10001" else "0:0" end) and
            $c.Config.Entrypoint == ["/usr/local/bin/padm-entrypoint"] and $c.Config.Cmd == $s.command and
            $c.Config.Healthcheck.Test == $s.healthcheck.test and
            $c.HostConfig.NetworkMode == "host" and $c.HostConfig.ReadonlyRootfs == true and
            $c.HostConfig.Privileged == false and $c.HostConfig.Init == true and
            ($c.HostConfig.CapAdd // [] | map(sub("^CAP_"; "")) | sort) == ($s.cap_add // [] | sort) and
            ($c.HostConfig.CapDrop | sort) == ["ALL"] and
            ($c.HostConfig.SecurityOpt | sort) == ($s.security_opt | sort) and
            $c.HostConfig.LogConfig.Type == $s.logging.driver and
            $c.HostConfig.LogConfig.Config == $s.logging.options and
            (($c.HostConfig.Tmpfs // {}) | keys | sort) ==
              ([$s.tmpfs[] | split(":")[0]] | sort) and
            all($c.Mounts[]; .Type == "bind") and
            ($c.Mounts | map({source:.Source,target:.Destination,read_only:(.RW | not)}) | sort_by(.target)) ==
              ($s.volumes | map({source:(.source | sub("^\\$\\{PADM_(DOCKER|NET)_ROOT\\}"; $root)),
                target,read_only}) | sort_by(.target)))
        ' <<<"${inspected}" >/dev/null || {
            dockerError "控制来源快照的 ${service} 容器状态或归属漂移"
            return 1
        }
        snapshots=$(jq -cn --argjson previous "${snapshots}" --argjson current "${inspected}" \
            '$previous + [$current[0] | {id:.Id,started_at:.State.StartedAt,restart_count:.RestartCount}]') ||
            return 1
    done
    hashes=
    for file in config/spec.json config/control/state.json compose.json deployment.json images.env \
        secrets/net/wireguard/wg-padm.conf data/net/wireguard/wireguard.state; do
        dockerTrafficSafePath "${root}" "${root}/${file}" &&
            [[ -f "${root}/${file}" && ! -L "${root}/${file}" ]] || return 1
        digest=$(sha256sum -- "${root}/${file}") || return 1
        hashes+="${digest}"$'\n'
    done
    jq -cn --argjson containers "${snapshots}" --arg hashes "${hashes}" \
        '{containers:$containers,hashes:$hashes}'
)

dockerControlSourceReceipt() (
    local file=$1 cursor=$2 nonce=$3 source=$4 target=$5 port=$6 since=$7 until=$8 metadata size offset
    set -o pipefail
    dockerTrafficSafePath "$(dockerInstallRoot)" "${file}" &&
        [[ -f "${file}" && ! -L "${file}" &&
            "$(stat -c '%a:%u:%g:%h' "${file}")" == "640:10001:10001:1" ]] || return 1
    metadata=$(stat -c '%d:%i:%s' "${file}") || return 1
    [[ "${metadata%:*}" == "${cursor%:*}" ]] || return 1
    size=${metadata##*:}
    offset=${cursor##*:}
    ((size >= offset && size - offset <= 65536)) || return 1
    # 只读本次偏移后的完整行；随机挑战关联不能由时间窗口或普通 401 代替。
    dd if="${file}" bs=1 skip="${offset}" count="$((size - offset))" status=none |
        jq -erRs --arg nonce "${nonce}" --arg source "${source}" --arg target "${target}" --arg port "${port}" \
            --arg since "${since}" --arg until "${until}" '
          def record:
            "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}Z control-source nonce=[a-f0-9]{64} status=401 source=[0-9.]+ target=[0-9.]+ port=[0-9]+$";
          if length == 0 or (endswith("\n") | not) then "pending"
          else [split("\n")[] | select(length > 0) |
            if test(record) then
              capture("^(?<time>[^ ]+) control-source nonce=(?<nonce>[a-f0-9]{64}) status=401 source=(?<source>[0-9.]+) target=(?<target>[0-9.]+) port=(?<port>[0-9]+)$")
            else error("invalid control source receipt") end] |
            map(select(.nonce == $nonce)) |
            if length == 0 then "pending"
            elif length == 1 and .[0].source == $source and .[0].target == $target and .[0].port == $port and
              .[0].time >= $since and .[0].time < $until
            then "verified" else error("invalid control source receipt") end
          end
        '
)

dockerControlSourceWitnessLocked() {
    local witnessOwner=${BASHPID:-$$}
    (
    local root spec challenge receipt temporary= registration= snapshot current nonce image expires cursor result started
    local registrationHash= since until directory mode completion=${1:-}
    [[ "$#" -le 1 ]] && { [[ -z "${completion}" ]] || declare -F "${completion}" >/dev/null; } ||
        return "${PADM_DOCKER_RC_USAGE}"
    [[ -n "${DOCKER_DEPLOYMENT_LOCK_DIR:-}" &&
        "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null || true)" == "${witnessOwner}" ]] ||
        return "${PADM_DOCKER_RC_LOCK}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    spec="${root}/config/spec.json"
    challenge="${root}/data/control-source/challenge.json"
    receipt="${root}/logs/control/source.receipt"
    dockerTrafficSafePath "${root}" "${challenge}" &&
        [[ -d "${root}/data/control-source" &&
            "$(stat -c '%a:%u:%g' "${root}/data/control-source")" == "750:0:10001" &&
            -z "$(find "${root}/data/control-source" -mindepth 1 -print -quit)" ]] || {
        dockerError '来源挑战需要新版受管空登记目录，旧登记未删除'
        return "${PADM_DOCKER_RC_STATE}"
    }
    for directory in "${root}" "${root}/config" "${root}/data" "${root}/logs" "${root}/logs/control"; do
        [[ -d "${directory}" && ! -L "${directory}" &&
            "$(stat -c '%u' "${directory}")" == 0 ]] || return "${PADM_DOCKER_RC_STATE}"
        (( (8#$(stat -c '%a' "${directory}") & 022) == 0 )) || return "${PADM_DOCKER_RC_STATE}"
    done
    directory=${root%/*}
    while [[ -n "${directory}" ]]; do
        [[ -d "${directory}" && ! -L "${directory}" &&
            "$(stat -c %u "${directory}")" == 0 ]] || return "${PADM_DOCKER_RC_STATE}"
        mode=$(stat -c %a "${directory}") || return "${PADM_DOCKER_RC_STATE}"
        (( (8#${mode} & 022) == 0 )) || (( (8#${mode} & 01000) != 0 )) ||
            return "${PADM_DOCKER_RC_STATE}"
        [[ "${directory}" != / ]] || break
        directory=${directory%/*}
        [[ -n "${directory}" ]] || directory=/
    done
    trap 'status=$?; if [[ -n "${registration}" ]]; then
        if [[ ! -e "${challenge}" && ! -L "${challenge}" ]]; then :
        elif [[ -f "${challenge}" && ! -L "${challenge}" &&
            "$(stat -c "%d:%i:%a:%u:%g:%h" "${challenge}")" == "${registration}" &&
            "$(sha256sum "${challenge}")" == "${registrationHash}" ]]; then
            rm -- "${challenge}" || status=15
        else dockerError "来源挑战登记已变化，保留文件"; status=15; fi
      fi
      [[ -z "${temporary}" ]] || dockerRemoveManagedTree "${root}" "${temporary}" || status=15
      exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    snapshot=$(dockerControlSourceSnapshot) || return "${PADM_DOCKER_RC_STATE}"
    image=$(dockerAccountImage ops) &&
        nonce=$(dockerSetupRandomHex "${image}" 32) &&
        [[ "${nonce}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    temporary=$(mktemp -d "${root}/.control-source.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${temporary}" || return "${PADM_DOCKER_RC_STATE}"
    expires=$(date +%s) && [[ "${expires}" =~ ^[0-9]{1,10}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    since=$(date -u -d "@${expires}" '+%Y-%m-%dT%H:%M:%S.000Z') || return "${PADM_DOCKER_RC_STATE}"
    expires=$((expires + 30))
    until=$(date -u -d "@${expires}" '+%Y-%m-%dT%H:%M:%S.000Z') || return "${PADM_DOCKER_RC_STATE}"
    (umask 027; jq --arg nonce "${nonce}" --argjson expires "${expires}" '
      {schema_version:1,nonce:$nonce,expires_at:$expires,
       expected_source:.control.peer.address,target:.control.listen.address,port:.control.listen.port}
    ' "${spec}" >"${temporary}/challenge.json") &&
        chmod 0640 "${temporary}/challenge.json" &&
        chown 0:10001 "${temporary}/challenge.json" &&
        registration=$(stat -c '%d:%i:%a:%u:%g:%h' "${temporary}/challenge.json") &&
        registrationHash=$(sha256sum "${temporary}/challenge.json") ||
        return "${PADM_DOCKER_RC_STATE}"
    registrationHash="${registrationHash%% *}  ${challenge}"
    [[ "$(stat -c %d "${temporary}")" == "$(stat -c %d "${root}/data/control-source")" &&
        ! -e "${challenge}" && ! -L "${challenge}" ]] &&
        mv -T -n -- "${temporary}/challenge.json" "${challenge}" &&
        [[ ! -e "${temporary}/challenge.json" ]] || return "${PADM_DOCKER_RC_STATE}"
    [[ "$(stat -c '%d:%i:%a:%u:%g:%h' "${challenge}")" == "${registration}" &&
        "$(sha256sum "${challenge}")" == "${registrationHash}" ]] || return "${PADM_DOCKER_RC_STATE}"
    [[ -f "${receipt}" && ! -L "${receipt}" &&
        "$(stat -c '%a:%u:%g:%h' "${receipt}")" == "640:10001:10001:1" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    cursor=$(stat -c '%d:%i:%s' "${receipt}") || return "${PADM_DOCKER_RC_STATE}"
    started=${SECONDS}
    printf 'source-challenge=%s\n' "$(jq -c '.' "${challenge}")" || return 1
    printf '请在受管 Peer 执行: padm-docker control source-probe --address %s --port %s --peer-address %s --nonce %s\n' \
        "$(jq -r .target "${challenge}")" "$(jq -r .port "${challenge}")" \
        "$(jq -r .expected_source "${challenge}")" "${nonce}" >&2
    while ((SECONDS - started < 30)); do
        [[ "$(stat -c '%d:%i:%a:%u:%g:%h' "${challenge}")" == "${registration}" &&
            "$(sha256sum "${challenge}")" == "${registrationHash}" &&
            "$(date +%s)" -lt "${expires}" ]] || return "${PADM_DOCKER_RC_STATE}"
        result=$(dockerControlSourceReceipt "${receipt}" "${cursor}" "${nonce}" \
            "$(jq -r .control.peer.address "${spec}")" "$(jq -r .control.listen.address "${spec}")" \
            "$(jq -r .control.listen.port "${spec}")" "${since}" "${until}") ||
            return "${PADM_DOCKER_RC_STATE}"
        if [[ "${result}" == verified ]]; then
            current=$(dockerControlSourceSnapshot) && [[ "${current}" == "${snapshot}" ]] &&
                ((SECONDS - started < 30)) && [[ "$(date +%s)" -lt "${expires}" &&
                    "$(stat -c '%d:%i:%a:%u:%g:%h' "${challenge}")" == "${registration}" &&
                    "$(sha256sum "${challenge}")" == "${registrationHash}" &&
                    "$(dockerControlSourceReceipt "${receipt}" "${cursor}" "${nonce}" \
                      "$(jq -r .control.peer.address "${spec}")" "$(jq -r .control.listen.address "${spec}")" \
                      "$(jq -r .control.listen.port "${spec}")" "${since}" "${until}")" == verified ]] ||
                return "${PADM_DOCKER_RC_STATE}"
            printf 'source-verified=%s\n' "$(jq -c '{source:.expected_source,target,port}' "${challenge}")" ||
                return 1
            [[ -z "${completion}" ]] || "${completion}" || return "${PADM_DOCKER_RC_STATE}"
            return 0
        fi
        sleep 1
    done
    dockerError '30 秒内未收到当前随机挑战的可信回执'
    return "${PADM_DOCKER_RC_HOST}"
    )
}

dockerControlSourceWitnessRecheck() {
    # 仅供同锁挑战完成回调使用；登记与快照不能跨事务缓存。
    [[ -n "${registration:-}" && -n "${snapshot:-}" && -n "${nonce:-}" &&
        "${completion:-}" == dockerFail2banStartManagedCommit ]] &&
        [[ "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null || true)" == "${witnessOwner}" &&
            "$(date +%s)" -lt "${expires}" ]] &&
        ((SECONDS - started < 30)) &&
        [[ "$(stat -c '%d:%i:%a:%u:%g:%h' "${challenge}")" == "${registration}" &&
            "$(sha256sum "${challenge}")" == "${registrationHash}" ]] &&
        current=$(dockerControlSourceSnapshot) && [[ "${current}" == "${snapshot}" ]] &&
        [[ "$(dockerControlSourceReceipt "${receipt}" "${cursor}" "${nonce}" \
          "$(jq -r .control.peer.address "${spec}")" "$(jq -r .control.listen.address "${spec}")" \
          "$(jq -r .control.listen.port "${spec}")" "${since}" "${until}")" == verified &&
            "$(date +%s)" -lt "${expires}" ]] && ((SECONDS - started < 30))
}

dockerControlSourceCheck() (
    local status
    [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    dockerControlSourceWitnessLocked
)

dockerControlSourceProbe() (
    local address= port= source= nonce= image root input=
    while [[ "$#" -gt 0 ]]; do
        [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
        case "$1" in
        --address) [[ -z "${address}" ]] || return 2; address=$2 ;;
        --port) [[ -z "${port}" ]] || return 2; port=$2 ;;
        --peer-address) [[ -z "${source}" ]] || return 2; source=$2 ;;
        --nonce) [[ -z "${nonce}" ]] || return 2; nonce=$2 ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
        shift 2
    done
    dockerControlPrivateAddressIsValid "${address}" &&
        dockerControlPrivateAddressIsValid "${source}" &&
        [[ "${address}" != "${source}" && "${port}" =~ ^[1-9][0-9]{3,4}$ &&
            "${nonce}" =~ ^[a-f0-9]{64}$ ]] && ((port >= 1024 && port <= 65535)) ||
        return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; if [[ -n "${input}" ]] && ! dockerRemoveManagedTree "${root}" "${input}"; then
        dockerError "控制来源探测临时目录清理失败"; status=15
      fi; dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    input=$(mktemp -d "${root}/.control-source-probe.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${input}" &&
        jq -n --arg address "${address}" --arg source "${source}" \
            '{listen:{address:$address},peer_address:$source}' >"${input}/connection.json" &&
        dockerControlClientRuntimeCheck "${input}/connection.json" || return "${PADM_DOCKER_RC_HOST}"
    image=$(dockerAccountImage ops) || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityProbeRun 10 --user 0:0 --network host --log-driver none \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --entrypoint python3 "${image}" -c '
import sys
sys.path.insert(0, "/opt/padm")
from control_client import source_probe
try:
    source_probe(sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4])
except Exception:
    sys.exit("控制来源探测失败")
' "${address}" "${port}" "${source}" "${nonce}" || return "${PADM_DOCKER_RC_HOST}"
)

dockerControlLogRotate() (
    local yes=0 answer root image snapshot current receiptIdentity receiptHash container= status=0 interrupted=0
    local inspected remaining cleanupWarned=0
    [[ "$#" == 0 || ( "$#" == 1 && "$1" == --yes ) ]] || return "${PADM_DOCKER_RC_USAGE}"
    [[ "$#" == 0 ]] || yes=1
    [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
        dockerError '轮转控制认证日志需要 --yes 确认'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${yes}" == 0 ]]; then
        dockerSetupRead answer '确认轮转满 10 MiB 的控制认证日志并只保留两份历史？[y/N]: ' n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/data/control-source" &&
        [[ -d "${root}/data/control-source" &&
            "$(stat -c '%a:%u:%g' "${root}/data/control-source")" == "750:0:10001" &&
            -z "$(find "${root}/data/control-source" -mindepth 1 -print -quit)" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; if [[ -n "${container}" ]]; then
        while ! docker rm "${container}" >/dev/null; do
            if remaining=$(docker ps --all --quiet --no-trunc --filter "id=${container}") &&
                [[ -z "${remaining}" ]]; then break; fi
            if [[ "${cleanupWarned}" == 0 ]]; then
                dockerError "等待日志轮转容器退出后再释放部署锁"
                cleanupWarned=1
            fi
            docker wait "${container}" >/dev/null || sleep 0.1
        done
      fi; dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    trap 'interrupted=130' INT
    trap 'interrupted=143' TERM
    [[ -z "$(find "${root}/data/control-source" -mindepth 1 -print -quit)" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    snapshot=$(dockerControlSourceSnapshot) || return "${PADM_DOCKER_RC_STATE}"
    receiptIdentity=$(stat -c '%d:%i:%a:%u:%g:%h' "${root}/logs/control/source.receipt") &&
        receiptHash=$(sha256sum "${root}/logs/control/source.receipt") &&
        image=$(dockerAccountImage ops) || return "${PADM_DOCKER_RC_STATE}"
    # 轮转不是探测：正常中断等待根端事务结束，不强杀仍在持锁的写入者。
    container=$(docker create --read-only --cap-drop ALL --cap-add CHOWN \
        --security-opt no-new-privileges --user 0:10001 --network none --log-driver none \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --mount "type=bind,src=${root}/logs/control,dst=/var/log/padm/control" \
        --mount "type=bind,src=${root}/config/control/state.json,dst=/etc/padm/control/state.json,readonly" \
        --entrypoint python3 "${image}" /opt/padm/control_api.py \
        --state /etc/padm/control/state.json --access-log /var/log/padm/control/auth.log \
        --access-lock /var/log/padm/control/auth.lock --rotate-access-log) &&
        [[ "${container}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
    docker start "${container}" >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    while :; do
        inspected=$(docker inspect --format '{{json .State}}' "${container}") ||
            return "${PADM_DOCKER_RC_STATE}"
        if jq -e '.Running == false and .Status == "exited"' <<<"${inspected}" >/dev/null; then
            status=$(jq -er '.ExitCode | select(type == "number" and floor == . and . >= 0)' <<<"${inspected}") ||
                return "${PADM_DOCKER_RC_STATE}"
            break
        fi
        jq -e '.Running == true and .Status == "running"' <<<"${inspected}" >/dev/null ||
            return "${PADM_DOCKER_RC_STATE}"
        docker wait "${container}" >/dev/null || true
    done
    [[ "${status}" == 0 ]] || return "${PADM_DOCKER_RC_STATE}"
    current=$(dockerControlSourceSnapshot) && [[ "${current}" == "${snapshot}" &&
        "$(stat -c '%d:%i:%a:%u:%g:%h' "${root}/logs/control/source.receipt")" == "${receiptIdentity}" &&
        "$(sha256sum "${root}/logs/control/source.receipt")" == "${receiptHash}" ]] ||
        return "${PADM_DOCKER_RC_STATE}"
    return "${interrupted}"
)

dockerControlClientBuildDraft() {
    local directory=$1 image
    shift
    image=$(dockerAccountImage ops) || return 1
    # token 只从私有只读快照读取，不进入参数、环境或 Docker 日志。
    dockerRealityProbeRun 30 --user 0:0 --network host --log-driver none \
        --tmpfs /tmp:rw,noexec,nosuid,nodev,size=8m \
        --label io.padm.mode=docker --label io.padm.project="${PADM_DOCKER_PROJECT}" \
        --mount "type=bind,src=${directory},dst=/input,readonly" \
        --entrypoint python3 "${image}" /opt/padm/control_client.py \
        --spec /input/spec.json --invite /input/invite.json "$@"
}

dockerControlClientApply() (
    local action=$1 invitation= yes=0 answer root spec draft= parent metadata mode status=0
    local -a listeners=()
    shift
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --invite)
            [[ -z "${invitation}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            invitation=$2; shift 2
            ;;
        --listener)
            [[ "${action}" == join && "$#" -ge 2 &&
                "$2" =~ ^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            listeners+=(--listener "$2"); shift 2
            ;;
        --yes)
            [[ "${action}" == join && "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            yes=1; shift
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ -n "${invitation}" && ( "${action}" == sync || "${#listeners[@]}" -gt 0 ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerControlInviteInputCheck "${invitation}" "${root}" || {
        dockerError '邀请须为受管目录外的 root 私有普通文件，祖先目录不得可写或含链接'
        return "${PADM_DOCKER_RC_STATE}"
    }
    if [[ "${action}" == join && "${yes}" != 1 ]]; then
        [[ -t 0 && -t 1 ]] || {
            dockerError '接入被控角色需要 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        dockerSetupRead answer '确认接入主控并同步到选定入口？[y/N]: ' n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
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
    dockerControlRecoveryCheck &&
        dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == join ]]; then
        if jq -e 'has("control") or has("control_sync")' "${spec}" >/dev/null; then
            dockerError '当前部署已有控制角色，拒绝重新接入'
            return "${PADM_DOCKER_RC_CONFLICT}"
        fi
    else
        jq -e '.control_sync.role == "controlled" and .control_sync.connection != null' \
            "${spec}" >/dev/null || {
            dockerError '当前被控角色缺少已接入的私网连接，拒绝外部同步'
            return "${PADM_DOCKER_RC_STATE}"
        }
    fi
    draft=$(mktemp -d "${root}/.control-client.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" &&
        dockerControlInviteInputCheck "${invitation}" "${root}" &&
        cp -- "${invitation}" "${draft}/invite.json" &&
        chmod 0600 "${draft}/invite.json" &&
        (umask 077; dockerConfigureSpecMigrate "${spec}" "${draft}/spec.json") ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerControlClientRuntimeCheck "${draft}/invite.json" || return $?
    (umask 077; dockerControlClientBuildDraft "${draft}" "${listeners[@]}" >"${draft}/next.json") &&
        dockerConfigureSpecValidate "${draft}/next.json" || {
        status=$?
        [[ "${status}" != 130 && "${status}" != 143 ]] || return "${status}"
        dockerError '私网认证或同步规划失败，保留当前角色、账号和配置'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    if jq -en --slurpfile current "${spec}" --slurpfile next "${draft}/next.json" \
        '$current == $next' >/dev/null; then
        printf '同步版本和内容未变，无需重新部署。\n'
        return 0
    fi
    DOCKER_CONTROL_SYNC_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json" || status=$?
    [[ "${status}" -ne 0 ]] || printf '被控角色和账号同步已提交。\n'
    return "${status}"
)

dockerControlJoin() { dockerControlClientApply join "$@"; }
dockerControlSync() { dockerControlClientApply sync "$@"; }

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
        listen: (.control_sync.connection.listen // null),
        peer_address: (.control_sync.connection.peer_address // null),
        revision: .control_sync.last_revision, healthy: null,
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
    join) dockerControlJoin "$@" ;;
    sync) dockerControlSync "$@" ;;
    source-check) dockerControlSourceCheck "$@" ;;
    source-probe) dockerControlSourceProbe "$@" ;;
    log-rotate) dockerControlLogRotate "$@" ;;
    *)
        dockerError '用法: control status [--json] | init --address <IPv4> --port <端口> --peer-address <IPv4> [--yes] | invite --output <绝对路径> [--expires-in <秒>] [--yes] | revoke [--yes] | join --invite <私有文件> --listener <入口 ID>... [--yes] | sync --invite <私有文件> | source-check | source-probe --address <IPv4> --port <端口> --peer-address <IPv4> --nonce <64 位 hex> | log-rotate [--yes]'
        return "${PADM_DOCKER_RC_USAGE}"
        ;;
    esac
}
