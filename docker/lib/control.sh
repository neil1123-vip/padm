#!/usr/bin/env bash

if [[ "${PADM_DOCKER_CONTROL_LOADED:-}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_CONTROL_LOADED=1
readonly PADM_DOCKER_CONTROL_LOG_SCHEDULE_SCHEMA=1
DOCKER_CONTROL_LOG_STAGE=
DOCKER_CONTROL_LOG_SWITCHED=0
DOCKER_CONTROL_LOG_HAD_DIRECTORY=0

dockerControlLogScheduleValidate() {
    local root=$1 directory="${1}/data/control-log" file="${1}/data/control-log/schedule.json" parent mode metadata
    dockerTrafficSafePath "${root}" "${file}" || return 1
    for parent in "${root}" "${root}/data"; do
        [[ -e "${parent}" ]] || continue
        [[ -d "${parent}" ]] || return 1
        metadata=$(stat -c '%u:%a' "${parent}") || return 1
        [[ "${metadata}" == 0:* ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 022) == 0 )) || return 1
    done
    [[ -e "${directory}" ]] || return 0
    [[ -d "${directory}" ]] || return 1
    metadata=$(stat -c '%u:%g:%a' "${directory}") || return 1
    [[ "${metadata}" == 0:0:700 &&
        -z "$(find "${directory}" -mindepth 1 -maxdepth 1 ! -path "${file}" -print -quit)" ]] || return 1
    [[ -e "${file}" ]] || return 0
    [[ -f "${file}" ]] || return 1
    metadata=$(stat -c '%u:%g:%a:%h:%s' "${file}") || return 1
    [[ "${metadata%:*}" == 0:0:600:1 && "${metadata##*:}" -le 4096 ]] || return 1
    jq -es 'length == 1 and (.[0] | type == "object" and
      keys == ["enabled","schema_version"] and .schema_version == 1 and
      (.enabled | type == "boolean"))' "${file}" >/dev/null 2>&1
}

dockerControlLogScheduleBundleCheck() {
    local bundle=$1 root file
    root=$(dockerInstallRoot) || return 1
    file="${root}/data/control-log/schedule.json"
    dockerControlLogScheduleValidate "${root}" || return 1
    [[ -f "${file}" ]] && jq -e '.enabled == true' "${file}" >/dev/null || return 0
    [[ -f "${bundle}/docker/lib/control.sh" && ! -L "${bundle}/docker/lib/control.sh" ]] &&
        grep -qxF 'readonly PADM_DOCKER_CONTROL_LOG_SCHEDULE_SCHEMA=1' "${bundle}/docker/lib/control.sh" || {
        dockerError '目标控制 bundle 不支持已启用的控制日志调度，请先停用调度或选择兼容版本'
        return 1
    }
}

dockerControlLogRole() {
    local root=$1 spec file haveInput=0 directory mode
    for file in config/spec.json deployment.json compose.json images.env; do
        dockerTrafficSafePath "${root}" "${root}/${file}" || return 1
        [[ ! -e "${root}/${file}" ]] || haveInput=1
    done
    if [[ "${haveInput}" == 0 ]]; then
        dockerTrafficSafePath "${root}" "${root}/config/control" || return 1
        for directory in "${root}/config" "${root}/config/control"; do
            [[ -e "${directory}" ]] || continue
            [[ -d "${directory}" && "$(stat -c %u "${directory}")" == 0 ]] || return 1
            mode=$(stat -c %a "${directory}") || return 1
            (( (8#${mode} & 022) == 0 )) || return 1
        done
        [[ ! -d "${root}/config/control" ||
            -z "$(find "${root}/config/control" -mindepth 1 -print -quit)" ]] || return 1
        printf 'unconfigured\n'
        return 0
    fi
    spec=$(dockerAccountSpecFile) &&
        dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        dockerControlStateCheck "${root}" || return 1
    jq -er 'if .control.role == "main" then "main"
      elif has("control_sync") then "controlled" else "standalone" end' "${spec}"
}

dockerControlLogScheduleRemove() {
    local unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system} content
    if [[ ! -e "${unitDir}/padm-docker-control-log.service" && ! -L "${unitDir}/padm-docker-control-log.service" &&
        ! -e "${unitDir}/padm-docker-control-log.timer" && ! -L "${unitDir}/padm-docker-control-log.timer" ]]; then
        command -v crontab >/dev/null 2>&1 || return 0
        content=$(dockerTrafficReadCrontab) || return 1
        [[ "${content}" == *'# padm-docker 控制认证日志自动轮转'* ]] || return 0
    fi
    dockerMaintenanceScheduleApply remove control-log
}

dockerControlLogScheduleInstall() {
    local root file role
    root=$(dockerInstallRoot) || return 1
    file="${root}/data/control-log/schedule.json"
    dockerControlLogScheduleValidate "${root}" || return 1
    if [[ ! -f "${file}" ]] || ! jq -e '.enabled == true' "${file}" >/dev/null; then
        dockerControlLogScheduleRemove
        return $?
    fi
    role=$(dockerControlLogRole "${root}") || return 1
    if [[ "${role}" == main ]]; then dockerMaintenanceScheduleApply install control-log;
    else dockerControlLogScheduleRemove; fi
}

dockerControlLogScheduleInterrupted() {
    local root stage=${DOCKER_CONTROL_LOG_STAGE:-} directory
    dockerMaintenanceScheduleInterrupted control-log || return 1
    [[ -n "${stage}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    directory="${root}/data/control-log"
    dockerTrafficSafePath "${root}" "${stage}" &&
        [[ "${stage}" == "${root}/locks/control-log-state."* && -d "${stage}" && -O "${stage}" &&
            -z "$(find "${stage}" ! -type f ! -type d -print -quit)" ]] || return 1
    if [[ "${DOCKER_CONTROL_LOG_SWITCHED:-0}" == 1 ]]; then
        dockerControlLogScheduleValidate "${root}" || return 1
        if [[ -f "${stage}/previous" ]]; then
            cp -p -- "${stage}/previous" "${stage}/restore" &&
                mv -f -- "${stage}/restore" "${directory}/schedule.json" || return 1
        else
            rm -f -- "${directory}/schedule.json" || return 1
        fi
        if [[ "${DOCKER_CONTROL_LOG_HAD_DIRECTORY:-0}" == 0 && -d "${directory}" ]]; then
            rmdir -- "${directory}" || return 1
        fi
        DOCKER_CONTROL_LOG_SWITCHED=0
    fi
    dockerRemoveManagedTree "${root}" "${stage}" || return 1
    DOCKER_CONTROL_LOG_STAGE= DOCKER_CONTROL_LOG_HAD_DIRECTORY=0
}

dockerControlLogInputsCheck() {
    local root=$1 file path metadata mode
    for file in auth.log auth.lock source.receipt; do
        [[ -f "${root}/logs/control/${file}" && ! -L "${root}/logs/control/${file}" ]] || return 1
    done
    [[ -d "${root}/data/control-source" && ! -L "${root}/data/control-source" ]] || return 1
    # Python 轮转 helper 会核对日志目录的全部祖先，启用前先拒绝 /tmp 等可写路径。
    path="${root}/logs/control"
    while :; do
        metadata=$(stat -c '%u:%a' "${path}") || return 1
        [[ "${metadata%%:*}" == 0 ]] || return 1
        mode=${metadata#*:}
        (( (8#${mode} & 022) == 0 )) || return 1
        [[ "${path}" == / ]] && break
        path=$(dirname -- "${path}")
    done
    [[ "$(stat -c '%u:%g:%a' "${root}/logs/control")" == 0:10001:750 ]] || return 1
    # 已有完整日志才允许校验，不能由首次创建空文件替代来源证据。
    dockerControlAccessLogEnsure "${root}" &&
        [[ -d "${root}/data/control-source" &&
            "$(stat -c '%a:%u:%g' "${root}/data/control-source")" == "750:0:10001" &&
            -z "$(find "${root}/data/control-source" -mindepth 1 -print -quit)" ]]
}

dockerControlLogScheduleCommand() (
    local action=${1:-} yes=0 answer root stage enabled=false current=false result status label
    shift || true
    case "${action}" in enable|disable|status) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    if [[ "$#" == 1 && "$1" == --yes && "${action}" != status ]]; then yes=1; shift; fi
    [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    if [[ "${action}" != status ]]; then
        [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
            dockerError '更改控制日志自动轮转需要 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        if [[ "${yes}" == 0 ]]; then
            if [[ "${action}" == enable ]]; then label=启用; else label=停用; fi
            dockerSetupRead answer "确认${label}控制日志每小时检查，满 10 MiB 轮转并保留两份历史？[y/N]: " n ||
                return "${PADM_DOCKER_RC_USAGE}"
            case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
        fi
    fi
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerControlLogScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; dockerControlLogScheduleInterrupted || status=15;
      dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    dockerControlLogScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ -f "${root}/data/control-log/schedule.json" ]]; then
        current=$(jq -r .enabled "${root}/data/control-log/schedule.json") || return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "${action}" == status ]]; then
        result=$(dockerMaintenanceScheduleApply check control-log) || return "${PADM_DOCKER_RC_STATE}"
        jq -c --argjson enabled "${current}" '. + {enabled:$enabled}' <<<"${result}"
        return $?
    fi
    if [[ "${action}" == enable ]]; then
        enabled=true
        dockerControlSourceSnapshot >/dev/null && dockerControlLogInputsCheck "${root}" ||
            return "${PADM_DOCKER_RC_STATE}"
    fi
    [[ -z "${DOCKER_CONTROL_LOG_STAGE:-}" ]] || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_LOG_STAGE=$(mktemp -d "${root}/locks/control-log-state.XXXXXX") ||
        return "${PADM_DOCKER_RC_STATE}"
    stage=${DOCKER_CONTROL_LOG_STAGE}
    chmod 0700 "${stage}" || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_LOG_HAD_DIRECTORY=0
    if [[ -d "${root}/data/control-log" ]]; then DOCKER_CONTROL_LOG_HAD_DIRECTORY=1; fi
    [[ ! -f "${root}/data/control-log/schedule.json" ]] ||
        cp -p -- "${root}/data/control-log/schedule.json" "${stage}/previous" ||
        return "${PADM_DOCKER_RC_STATE}"
    jq -n --argjson enabled "${enabled}" '{schema_version:1,enabled:$enabled}' >"${stage}/next" &&
        chmod 0600 "${stage}/next" && chown 0:0 "${stage}/next" || return "${PADM_DOCKER_RC_STATE}"
    # 登记和固定作业共用恢复窗口，任一步失败都回到原登记和原调度。
    DOCKER_CONTROL_LOG_SWITCHED=1
    if [[ "${action}" == enable ]]; then dockerMaintenanceScheduleApply install control-log;
    else dockerControlLogScheduleRemove; fi || return "${PADM_DOCKER_RC_STATE}"
    if [[ ! -d "${root}/data/control-log" ]]; then
        mkdir -m 0700 -- "${root}/data/control-log" &&
            chown 0:0 "${root}/data/control-log" || return "${PADM_DOCKER_RC_STATE}"
    fi
    mv -f -- "${stage}/next" "${root}/data/control-log/schedule.json" &&
        dockerMaintenanceScheduleCommit control-log &&
        dockerControlLogScheduleInterrupted || return "${PADM_DOCKER_RC_STATE}"
    printf '控制日志自动轮转 enabled=%s\n' "${enabled}"
)

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
        dockerError '邀请、撤销和监听修改仅适用于已初始化的主控角色'
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

dockerControlSetPort() (
    local port= yes=0 answer root spec draft= parent metadata mode
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --port)
            [[ -z "${port}" && "$#" -ge 2 && -n "$2" && "$2" != --* ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            port=$2; shift 2
            ;;
        --yes) [[ "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"; yes=1; shift ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ "${port}" =~ ^[1-9][0-9]{3,4}$ ]] && ((port >= 1024 && port <= 65535)) ||
        return "${PADM_DOCKER_RC_USAGE}"
    [[ "${yes}" == 1 || ( -t 0 && -t 1 ) ]] || {
        dockerError '修改主控 API 端口需要 --yes 确认'
        return "${PADM_DOCKER_RC_USAGE}"
    }
    if [[ "${yes}" != 1 ]]; then
        dockerSetupRead answer "确认将主控 API 端口修改为 ${port}，随后重新签发邀请并重连被控端？[y/N]: " n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
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
    dockerControlRequireMain "${spec}" "${root}" &&
        dockerControlInviteRuntimeCheck "${spec}" &&
        dockerControlLogScheduleValidate "${root}" || return $?
    if [[ "$(jq -r '.control.listen.port' "${spec}")" == "${port}" ]]; then
        printf '主控 API 端口未变，无需重新部署。\n'
        return 0
    fi
    if [[ -f "${root}/data/control-log/schedule.json" ]] &&
        jq -e '.enabled == true' "${root}/data/control-log/schedule.json" >/dev/null; then
        dockerError '修改端口前请先停用控制日志自动轮转，修改后重新 source-check 再启用'
        return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    jq -e 'all(.host_integrations[]; .type != "fail2ban-control")' "${spec}" >/dev/null || {
        dockerError '修改端口前请先停用控制面 Fail2ban，修改后重新 source-check 再启用'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    draft=$(mktemp -d "${root}/.control-port.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" &&
        (umask 077; jq --argjson port "${port}" '.control.listen.port = $port' "${spec}" >"${draft}/next.json") ||
        return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json" || return $?
    # 来源证明绑定旧端口和容器快照，不能随配置变更静默迁移。
    printf '主控 API 端口已更新；请重新签发邀请，在被控端执行 reconnect，并重新 source-check。\n'
)

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
    local yes=0 answer
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
    dockerControlLogRotateWorker manual
)

dockerControlAutoLogRotate() {
    [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerControlLogRotateWorker auto
}

dockerControlLogRotateWorker() (
    local mode=$1 root image snapshot current receiptIdentity receiptHash container= status=0 interrupted=0
    local inspected remaining cleanupWarned=0 role ids controlIds wireguardIds
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${mode}" == manual ]]; then
        dockerTrafficSafePath "${root}" "${root}/data/control-source" &&
            [[ -d "${root}/data/control-source" &&
                "$(stat -c '%a:%u:%g' "${root}/data/control-source")" == "750:0:10001" &&
                -z "$(find "${root}/data/control-source" -mindepth 1 -print -quit)" ]] ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    else
        # 自动任务不等待同锁，调度维护才能在持锁时安全停止尚未启动的服务。
        PADM_DOCKER_LOCK_TIMEOUT=0 dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    fi
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
    if [[ "${mode}" == auto ]]; then
        dockerControlLogScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
        [[ -f "${root}/data/control-log/schedule.json" ]] &&
            jq -e '.enabled == true' "${root}/data/control-log/schedule.json" >/dev/null || return 0
        role=$(dockerControlLogRole "${root}") || return "${PADM_DOCKER_RC_STATE}"
        [[ "${role}" == main ]] || return 0
        dockerControlRecoveryCheck current || return "${PADM_DOCKER_RC_STATE}"
        controlIds=$(docker ps --all --quiet --no-trunc \
            --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
            --filter label=com.docker.compose.service=control) &&
            wireguardIds=$(docker ps --all --quiet --no-trunc \
                --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
                --filter label=com.docker.compose.service=net-wireguard) || return "${PADM_DOCKER_RC_STATE}"
        # 正常 down 删除两组容器；残留、停止或半套容器须继续严格来源检查。
        [[ -n "${controlIds}" || -n "${wireguardIds}" ]] || return 0
        for ids in "${controlIds}" "${wireguardIds}"; do
            [[ "${ids}" =~ ^[a-f0-9]{64}$ ]] || return "${PADM_DOCKER_RC_STATE}"
        done
        dockerControlLogInputsCheck "${root}" || return "${PADM_DOCKER_RC_STATE}"
    fi
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
    local confirmation='确认接入主控并同步到选定入口？[y/N]: '
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
            [[ "${action}" != sync && "${action}" != reconnect && "${action}" != rebind && "$#" -ge 2 &&
                "$2" =~ ^(entry-[a-z0-9][a-z0-9-]{0,47}|vless-reality|vless-ws)$ ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            listeners+=(--listener "$2"); shift 2
            ;;
        --yes)
            [[ "${action}" != sync && "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            yes=1; shift
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ -n "${invitation}" && ( "${action}" == sync || "${action}" == reconnect ||
        "${action}" == rebind || "${#listeners[@]}" -gt 0 ) ]] ||
        return "${PADM_DOCKER_RC_USAGE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerControlInviteInputCheck "${invitation}" "${root}" || {
        dockerError '邀请须为受管目录外的 root 私有普通文件，祖先目录不得可写或含链接'
        return "${PADM_DOCKER_RC_STATE}"
    }
    if [[ "${action}" == remap ]]; then
        listeners=(--remap "${listeners[@]}")
        confirmation='确认在同一控制连接上替换受管账号的入口映射？[y/N]: '
    elif [[ "${action}" == reconnect ]]; then
        listeners=(--reconnect)
        confirmation='确认按新邀请重连同身份、同 WireGuard 地址的主控 API 端口？[y/N]: '
    elif [[ "${action}" == rebind ]]; then
        listeners=(--rebind)
        confirmation='确认在同一 WireGuard 隧道上更换主控身份并替换原受管账号？[y/N]: '
    fi
    if [[ "${action}" != sync && "${yes}" != 1 ]]; then
        [[ -t 0 && -t 1 ]] || {
            dockerError '接入、重映射、重连或重绑定被控角色需要 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        dockerSetupRead answer "${confirmation}" n ||
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
    if [[ "${action}" == remap || "${action}" == reconnect || "${action}" == rebind ]]; then
        dockerControlSyncScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
        [[ ! -d "${root}/secrets/control-sync" ]] || {
            dockerError '重映射、重连或重绑定前请先停用被控账号自动同步，提交后用新邀请重新启用'
            return "${PADM_DOCKER_RC_CONFLICT}"
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
    if [[ "${status}" -eq 0 ]]; then
        if [[ "${action}" == remap ]]; then
            printf '被控账号入口映射已提交，主控身份和连接保持不变。\n'
        elif [[ "${action}" == reconnect ]]; then
            printf '被控 API 连接已提交，控制身份、WireGuard 地址和入口映射保持不变。\n'
        elif [[ "${action}" == rebind ]]; then
            printf '主控重绑定和受管账号已提交，WireGuard 地址、入口映射及本机账号保持不变。\n'
        else
            printf '被控角色和账号同步已提交。\n'
        fi
    fi
    return "${status}"
)

dockerControlJoin() { dockerControlClientApply join "$@"; }
dockerControlSync() { dockerControlClientApply sync "$@"; }

dockerControlSyncScheduleCommand() (
    local action=${1:-} invitation= yes=0 answer root spec stage= draft= enabled=false result status label
    shift || true
    case "${action}" in enable|disable|status) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --invite)
            [[ "${action}" == enable && -z "${invitation}" && "$#" -ge 2 &&
                -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            invitation=$2; shift 2
            ;;
        --yes)
            [[ "${action}" != status && "${yes}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            yes=1; shift
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    [[ "${action}" != enable || -n "${invitation}" ]] || return "${PADM_DOCKER_RC_USAGE}"
    if [[ "${action}" != status && "${yes}" != 1 ]]; then
        [[ -t 0 && -t 1 ]] || {
            dockerError '更改被控自动同步需要 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        if [[ "${action}" == enable ]]; then label=启用; else label=停用; fi
        dockerSetupRead answer "确认${label}被控账号每 5 分钟自动同步？[y/N]: " n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; dockerControlSyncScheduleInterrupted || status=15;
      [[ -z "${draft}" ]] || dockerRemoveManagedTree "${root}" "${draft}" || status=15;
      dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    dockerControlSyncScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
    [[ ! -d "${root}/secrets/control-sync" ]] || enabled=true
    if [[ "${action}" == status ]]; then
        result=$(dockerMaintenanceScheduleApply check control-sync) || return "${PADM_DOCKER_RC_STATE}"
        jq -c --argjson enabled "${enabled}" '. + {enabled:$enabled}' <<<"${result}"
        return $?
    fi
    if [[ "${action}" == enable ]]; then
        spec=$(dockerAccountSpecFile) || return $?
        dockerControlRecoveryCheck &&
            dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
            dockerControlSyncScheduleSpecCheck "${spec}" || return "${PADM_DOCKER_RC_STATE}"
        jq -e '.control == null and .control_sync.role == "controlled" and
          .control_sync.connection != null and all(.host_integrations[];
            .type != "fail2ban" and .type != "fail2ban-control" and .type != "fail2ban-ssh")' \
            "${spec}" >/dev/null || {
            dockerError '自动同步仅支持已有私网连接的单 Peer 被控角色，拒绝 WS/SSH 防护来源组合'
            return "${PADM_DOCKER_RC_STATE}"
        }
        dockerControlInviteInputCheck "${invitation}" "${root}" || {
            dockerError '邀请须为受管目录外的 root 私有普通文件，祖先目录不得可写或含链接'
            return "${PADM_DOCKER_RC_STATE}"
        }
        draft=$(mktemp -d "${root}/.control-client.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
        chmod 0700 "${draft}" &&
            cp -- "${invitation}" "${draft}/invite.json" &&
            chmod 0600 "${draft}/invite.json" &&
            (umask 077; dockerConfigureSpecMigrate "${spec}" "${draft}/spec.json") ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerControlClientRuntimeCheck "${draft}/invite.json" || return $?
        (umask 077; dockerControlClientBuildDraft "${draft}" >"${draft}/next.json") &&
            dockerConfigureSpecValidate "${draft}/next.json" || {
            status=$?
            [[ "${status}" != 130 && "${status}" != 143 ]] || return "${status}"
            dockerError '私网认证或同步规划失败，保留原自动同步登记'
            return "${PADM_DOCKER_RC_CONFLICT}"
        }
    fi
    [[ -z "${DOCKER_CONTROL_SYNC_SCHEDULE_STAGE:-}" ]] || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_SYNC_SCHEDULE_STAGE=$(mktemp -d "${root}/locks/control-sync-state.XXXXXX") ||
        return "${PADM_DOCKER_RC_STATE}"
    stage=${DOCKER_CONTROL_SYNC_SCHEDULE_STAGE}
    chmod 0700 "${stage}" || return "${PADM_DOCKER_RC_STATE}"
    [[ ! -d "${root}/secrets/control-sync" ]] ||
        cp -a -- "${root}/secrets/control-sync" "${stage}/previous" || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONTROL_SYNC_SCHEDULE_SWITCHED=1
    if [[ "${action}" == enable ]]; then
        mkdir -m 0700 "${stage}/next" &&
            cp -- "${draft}/invite.json" "${stage}/next/invite.json" &&
            (umask 077; jq '.control_sync |
              {schema_version:1,enabled:true,node_id,controller_id,listener_ids,connection}' \
                "${draft}/spec.json" >"${stage}/next/request.json") &&
            chmod 0600 "${stage}/next/"*.json &&
            chown -R 0:0 "${stage}/next" || return "${PADM_DOCKER_RC_STATE}"
        dockerMaintenanceScheduleApply install control-sync || return "${PADM_DOCKER_RC_STATE}"
    else
        dockerControlSyncScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    fi
    # 私有登记与调度共享恢复窗口；TERM 或发布失败恢复原凭据和原作业。
    [[ ! -d "${root}/secrets/control-sync" ]] ||
        dockerRemoveManagedTree "${root}" "${root}/secrets/control-sync" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == enable ]]; then
        mv -T -- "${stage}/next" "${root}/secrets/control-sync" &&
            dockerControlSyncScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
        enabled=true
    else
        enabled=false
    fi
    dockerMaintenanceScheduleCommit control-sync &&
        dockerControlSyncScheduleInterrupted || return "${PADM_DOCKER_RC_STATE}"
    printf '被控账号自动同步 enabled=%s\n' "${enabled}"
)

dockerControlSyncScheduleRuntimeState() {
    local root=$1 ids inspected expected
    local -a containers=()
    ids=$(docker ps --all --quiet --no-trunc \
        --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}") || return 1
    if [[ -z "${ids}" ]]; then printf 'down\n'; return 0; fi
    mapfile -t containers <<<"${ids}"
    [[ "${#containers[@]}" -le 32 ]] || return 1
    for ids in "${containers[@]}"; do [[ "${ids}" =~ ^[a-f0-9]{64}$ ]] || return 1; done
    expected=$(jq -ce --slurpfile deployment "${root}/deployment.json" '
      [.services | to_entries[] |
        select((.value.profiles // [] | index("net-check")) == null) |
        select((.value.profiles // [] | length) == 0 or
          any(.value.profiles[]; . as $p | $deployment[0].compose.profiles | index($p))) |
        .key] | sort | select(length > 0 and index("net-wireguard") != null)
    ' "${root}/compose.json") &&
        inspected=$(docker container inspect "${containers[@]}") || return 1
    jq -e --arg root "${root}" --arg project "${PADM_DOCKER_PROJECT}" --argjson expected "${expected}" \
        --slurpfile compose "${root}/compose.json" '
      ([.[].Config.Labels["com.docker.compose.service"]] | sort) == $expected and
      all(.[]; . as $c | $compose[0].services[$c.Config.Labels["com.docker.compose.service"]] as $service |
        .State.Status == "running" and .State.Running == true and
        .State.Paused == false and .State.Restarting == false and .State.Dead == false and
        (if $service.healthcheck != null then .State.Health.Status == "healthy" else true end) and
        .Config.Labels["com.docker.compose.project"] == $project and
        .Config.Labels["com.docker.compose.project.working_dir"] == $root and
        .Config.Labels["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
        .Config.Labels["com.docker.compose.oneoff"] == "False" and
        .Config.Labels["io.padm.mode"] == "docker" and .Config.Labels["io.padm.project"] == $project)
    ' <<<"${inspected}" >/dev/null || return 1
    printf 'running\n'
}

dockerControlAutoSync() (
    local root spec draft= runtime status=0
    [[ "$#" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    PADM_DOCKER_LOCK_TIMEOUT=0 dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; dockerConfigurationInterrupted || status=15;
      [[ -z "${draft}" ]] || dockerRemoveManagedTree "${root}" "${draft}" || status=15;
      dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    dockerControlSyncScheduleValidate "${root}" || return "${PADM_DOCKER_RC_STATE}"
    [[ -d "${root}/secrets/control-sync" ]] || return 0
    spec=$(dockerAccountSpecFile) || return $?
    dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        dockerControlSyncScheduleSpecCheck "${spec}" &&
        dockerControlRecoveryCheck current || return "${PADM_DOCKER_RC_STATE}"
    runtime=$(dockerControlSyncScheduleRuntimeState "${root}") || {
        dockerError '被控自动同步发现容器状态、服务集合或归属漂移，保留当前配置'
        return "${PADM_DOCKER_RC_STATE}"
    }
    [[ "${runtime}" != down ]] || return 0
    draft=$(mktemp -d "${root}/.control-client.XXXXXX") || return "${PADM_DOCKER_RC_STATE}"
    chmod 0700 "${draft}" &&
        cp -- "${root}/secrets/control-sync/invite.json" "${draft}/invite.json" &&
        chmod 0600 "${draft}/invite.json" &&
        (umask 077; dockerConfigureSpecMigrate "${spec}" "${draft}/spec.json") ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerControlClientRuntimeCheck "${draft}/invite.json" || return $?
    (umask 077; dockerControlClientBuildDraft "${draft}" >"${draft}/next.json") &&
        dockerConfigureSpecValidate "${draft}/next.json" || {
        status=$?
        [[ "${status}" != 130 && "${status}" != 143 ]] || return "${status}"
        dockerError '被控自动同步认证或规划失败，本轮保留当前账号和配置'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    jq -en --slurpfile current "${spec}" --slurpfile next "${draft}/next.json" \
        '$current == $next' >/dev/null && return 0
    DOCKER_CONTROL_SYNC_TRANSACTION=1
    dockerAccountApplyDraft "${draft}/next.json"
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

dockerWireGuardCommand() (
    local action=${1:-status} yes=0 answer root spec directory draft= image status=0 key value public parent
    local -A options=()
    [[ "$#" == 0 ]] || shift
    case "${action}" in prepare|peer|status|start|stop) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == --yes ]]; then
            [[ "${yes}" == 0 && "${action}" != status ]] || return "${PADM_DOCKER_RC_USAGE}"
            yes=1; shift; continue
        fi
        case "${action}:$1" in
        prepare:--address|prepare:--listen-port|peer:--peer-address|peer:--peer-public-key|peer:--endpoint)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* && ! -v "options[$1]" ]] ||
                return "${PADM_DOCKER_RC_USAGE}"
            options[$1]=$2; shift 2 ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    if [[ "${action}" == prepare ]]; then
        dockerControlPrivateAddressIsValid "${options[--address]:-}" &&
            [[ "${options[--listen-port]:-}" =~ ^[1-9][0-9]{3,4}$ ]] &&
            (( ${options[--listen-port]} >= 1024 && ${options[--listen-port]} <= 65535 )) ||
            return "${PADM_DOCKER_RC_USAGE}"
    elif [[ "${action}" == peer ]]; then
        dockerControlPrivateAddressIsValid "${options[--peer-address]:-}" &&
            [[ "${options[--peer-public-key]:-}" =~ ^[A-Za-z0-9+/]{43}=$ ]] ||
            return "${PADM_DOCKER_RC_USAGE}"
    fi
    if [[ "${action}" != status && "${yes}" == 0 ]]; then
        [[ -t 0 && -t 1 ]] || {
            dockerError 'WireGuard 修改需要 --yes 确认'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        dockerSetupRead answer "确认 WireGuard ${action}？stop 为临时停止，up/restart 可重新启动。[y/N]: " n ||
            return "${PADM_DOCKER_RC_USAGE}"
        case "${answer}" in y|Y|yes|YES) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    # 在部署锁收紧目录权限前拒绝不安全的原路径。
    for parent in "${root}" "${root}/config" "${root}/secrets" "${root}/secrets/net"; do
        [[ "${parent}" != "${root}/secrets/net" || -e "${parent}" || -L "${parent}" ]] || continue
        dockerTrafficSafePath "${root}" "${parent}" && [[ -d "${parent}" ]] &&
            value=$(stat -c '%u:%a' "${parent}") &&
            [[ "${value%%:*}" == 0 ]] && (( (8#${value#*:} & 022) == 0 )) ||
            return "${PADM_DOCKER_RC_STATE}"
    done
    dockerLockInstalledDeployment || return "${PADM_DOCKER_RC_LOCK}"
    trap 'status=$?; dockerConfigurationInterrupted;
        if [[ -n "${draft}" ]]; then dockerRemoveManagedTree "${root}" "${draft}" || status=15; fi;
        dockerReleaseDeploymentLock || status=12; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    spec=$(dockerAccountSpecFile) || return $?
    dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        dockerControlRecoveryCheck current || return "${PADM_DOCKER_RC_STATE}"
    directory="${root}/secrets/net/wireguard"
    if [[ "${action}" == status ]]; then
        if [[ ! -d "${root}/secrets/net" ]]; then
            public='{"state":"absent","configured":false}'
        else
            public=$(python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" status --directory "${directory}") ||
                return "${PADM_DOCKER_RC_STATE}"
        fi
        jq --argjson enabled "$(jq 'any(.host_integrations[]; .type == "wireguard")' "${spec}")" \
            '. + {enabled:$enabled}' <<<"${public}"
        return $?
    fi
    if [[ "${action}" == start || "${action}" == stop ]]; then
        if dockerCurrentOwnsHostIntegration wireguard; then
            dockerWireGuardService "${action}"
            return $?
        fi
        [[ "${action}" == start ]] || return "${PADM_DOCKER_RC_STATE}"
        public=$(python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" status --directory "${directory}") &&
            jq -e '.configured == true' <<<"${public}" >/dev/null ||
            return "${PADM_DOCKER_RC_STATE}"
        draft=$(mktemp -d "${root}/.wireguard.XXXXXX") &&
            chmod 0700 "${draft}" || return "${PADM_DOCKER_RC_STATE}"
        (umask 077; jq '.host_integrations += [{
            type:"wireguard",profile:"net-wireguard",firewall_rules:[],
            devices:["wg-padm"],schedules:[],
            settings:{config_file:"wg-padm.conf",interface:"wg-padm"}
          }]' "${spec}" >"${draft}/spec.json") || return "${PADM_DOCKER_RC_STATE}"
        printf '首次启用 WireGuard 将通过现有配置事务更新并检查部署服务。\n'
        dockerAccountApplyDraft "${draft}/spec.json"
        return $?
    fi
    jq -e 'has("control") or has("control_sync") or any(.host_integrations[]; .type == "wireguard")' \
        "${spec}" >/dev/null && {
        dockerError '准备配置仅支持尚未启用 WireGuard、主控或被控角色的部署'
        return "${PADM_DOCKER_RC_CONFLICT}"
    }
    dockerTrafficSafePath "${root}" "${directory}" || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${action}" == peer ]]; then
        local -a peerArgs=(peer --directory "${directory}")
        for key in --peer-address --peer-public-key --endpoint; do
            [[ ! -v "options[${key}]" ]] || peerArgs+=("${key}" "${options[${key}]}")
        done
        python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" "${peerArgs[@]}" ||
            return "${PADM_DOCKER_RC_STATE}"
        return 0
    fi
    # 只移除安全的空骨架；已有密钥、配置或未知内容一律保留。
    if [[ -e "${directory}" ]]; then
        value=$(stat -c '%u:%a' "${directory}") || return "${PADM_DOCKER_RC_STATE}"
        [[ -d "${directory}" && "${value%%:*}" == 0 ]] &&
            (( (8#${value#*:} & 022) == 0 )) &&
            rmdir -- "${directory}" || return "${PADM_DOCKER_RC_CONFLICT}"
    fi
    dockerConfigureReleaseReuseInstalled &&
        dockerConfigureReleaseValidate "${spec}" || return "${PADM_DOCKER_RC_MANIFEST}"
    image=$(jq -er '.images.net' "${spec}") || return "${PADM_DOCKER_RC_STATE}"
    draft=$(mktemp -d "${root}/.wireguard.XXXXXX") &&
        chmod 0700 "${draft}" || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityProbeRun 10 --pull never --user 0:0 --network none --log-driver none \
        --mount "type=bind,src=${draft},dst=/input" --entrypoint sh "${image}" -ec \
        'umask 077; wg genkey > /input/private.key; wg pubkey < /input/private.key > /input/public.key' ||
        return "${PADM_DOCKER_RC_HOST}"
    [[ -d "${root}/secrets/net" ]] || mkdir -m 0700 -- "${root}/secrets/net" ||
        return "${PADM_DOCKER_RC_STATE}"
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare --directory "${directory}" \
        --address "${options[--address]}" --listen-port "${options[--listen-port]}" \
        --private-key "${draft}/private.key" --public-key "${draft}/public.key" ||
        return "${PADM_DOCKER_RC_STATE}"
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
    remap) dockerControlClientApply remap "$@" ;;
    set-port) dockerControlSetPort "$@" ;;
    reconnect) dockerControlClientApply reconnect "$@" ;;
    rebind) dockerControlClientApply rebind "$@" ;;
    source-check) dockerControlSourceCheck "$@" ;;
    source-probe) dockerControlSourceProbe "$@" ;;
    log-rotate) dockerControlLogRotate "$@" ;;
    log-schedule) dockerControlLogScheduleCommand "$@" ;;
    auto-log-rotate) dockerControlAutoLogRotate "$@" ;;
    sync-schedule) dockerControlSyncScheduleCommand "$@" ;;
    auto-sync) dockerControlAutoSync "$@" ;;
    *)
        dockerError '用法: control status [--json] | init --address <IPv4> --port <端口> --peer-address <IPv4> [--yes] | invite --output <绝对路径> [--expires-in <秒>] [--yes] | revoke [--yes] | join --invite <私有文件> --listener <入口 ID>... [--yes] | sync --invite <私有文件> | remap --invite <同连接私有文件> --listener <入口 ID>... [--yes] | set-port --port <端口> [--yes] | reconnect --invite <同身份新端口私有文件> [--yes] | rebind --invite <同隧道新主控私有文件> [--yes] | source-check | source-probe --address <IPv4> --port <端口> --peer-address <IPv4> --nonce <64 位 hex> | log-rotate [--yes] | log-schedule enable|disable [--yes] | log-schedule status | auto-log-rotate | sync-schedule enable --invite <私有文件> [--yes] | sync-schedule disable [--yes] | sync-schedule status | auto-sync'
        return "${PADM_DOCKER_RC_USAGE}"
        ;;
    esac
}
