#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-cli.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-cli-fail: line %s, rc=%s, callers=%s\n" "${LINENO}" "$?" "${BASH_LINENO[*]}" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config" "${root}/backups"
chmod 0700 "${root}"

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
# 主入口由同阶段集成；单独运行此检查也使用同一生产 CLI。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/control.sh"

fail() { printf 'docker-control-cli-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    local status=0
    "$@" >"${TEST_ROOT}/rejected.log" 2>&1 || status=$?
    [[ "${status}" -ne 0 ]] || fail "应拒绝: $*"
}

spec="${root}/config/spec.json"
jq -n '{
  schema_version: 3,
  release: {version:"3.1.8", manifest_sha256:("1"*64), signature_identity:"fixture"},
  core: {type:"xray", secondary_type:null, protocols:[{
    id:1, core:"xray", server:"reality.example.com", public_port:443,
    address_families:["ipv4"], listener_id:"entry-reality", name:"main",
    uuid:"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    reality:{server_name:"reality.example.com", target_host:"reality.example.com",
      target_port:443, private_key:("A"*43), public_key:("B"*43), short_id:"1234abcd"}
  }]},
  tls:null, subscription:{enabled:false, token:"cli-subscription-secret"},
  images: (["xray","sing-box","nginx","ops","net"] |
    map({key:., value:("ghcr.io/example/padm-" + . + ":test@sha256:" + ("1"*64))}) |
    from_entries),
  host_integrations:[{type:"wireguard", profile:"net-wireguard", firewall_rules:[],
    devices:["wg-padm"], schedules:[],
    settings:{config_file:"wg-padm.conf", interface:"wg-padm"}}],
  accounts:[{id:"11111111-1111-4111-8111-111111111111", name:"CLI账号", enabled:true,
    uuid:"22222222-2222-4222-8222-222222222222", password:"CLI.-~@+=:Secret",
    shadowsocks_password:null, listeners:["entry-reality"]}]
}' >"${spec}"
chmod 0600 "${spec}"
dockerConfigureSpecValidate "${spec}"
cp -- "${spec}" "${TEST_ROOT}/standalone.json"
jq -r '.images | to_entries[] |
  "PADM_" + (if .key == "sing-box" then "SINGBOX" else (.key | ascii_upcase) end) +
  "_IMAGE=" + .value' "${spec}" >"${root}/images.env"

# 宿主探针使用桩；参数、Peer 核验脚本、规划器和角色校验均走生产实现。
dockerHostPreflight() { printf 'host\n' >>"${TEST_ROOT}/host.log"; }
dockerLockInstalledDeployment() { printf 'lock\n' >>"${TEST_ROOT}/host.log"; }
dockerReleaseDeploymentLock() { printf 'unlock\n' >>"${TEST_ROOT}/host.log"; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerManagedSpecMatchesDeployment() { [[ ! -f "${TEST_ROOT}/bad-deployment" ]]; }
dockerCurrentOwnsHostIntegration() { [[ "$1" == wireguard && ! -f "${TEST_ROOT}/unowned" ]]; }
export CONTROL_WG_CONFIG="${TEST_ROOT}/wg.conf"
export CONTROL_WG_ACTUAL="${TEST_ROOT}/wg.actual"
peerKey="$(printf B%.0s {1..43})="
printf '[Interface]\nPrivateKey = %s\n[Peer]\nPublicKey = %s\nAllowedIPs = 10.77.0.2/32\n' \
    "$(printf A%.0s {1..43})=" "${peerKey}" >"${CONTROL_WG_CONFIG}"
printf '%s\t10.77.0.2/32\n' "${peerKey}" >"${CONTROL_WG_ACTUAL}"
cp -- "${CONTROL_WG_CONFIG}" "${TEST_ROOT}/safe-wg.conf"
cp -- "${CONTROL_WG_ACTUAL}" "${TEST_ROOT}/safe-wg.actual"
wg-quick() { [[ "$1" == strip ]] && cat -- "${CONTROL_WG_CONFIG}"; }
wg() { [[ "$*" == 'show wg-padm allowed-ips' ]] && cat -- "${CONTROL_WG_ACTUAL}"; }
export -f wg wg-quick
dockerComposeRun() {
    [[ "${DOCKER_COMPOSE_TIMEOUT:-}" == 10 && "$1" == exec && "$2" == -T ]] || return 1
    case "$3" in
    net-wireguard)
        if [[ "$4" == /usr/local/bin/padm-entrypoint ]]; then
            [[ "$*" == 'exec -T net-wireguard /usr/local/bin/padm-entrypoint wireguard-health wg-padm' &&
                ! -f "${TEST_ROOT}/bad-health" ]]
        else
            shift 3
            "$@"
        fi
        ;;
    control)
        [[ "$*" == 'exec -T control /usr/local/bin/padm-entrypoint control-health --state /etc/padm/control/state.json' &&
            ! -f "${TEST_ROOT}/control-down" ]]
        ;;
    *) return 1 ;;
    esac
}
dockerRealityProbeRun() {
    [[ "$1" == 10 && " $* " == *' --network host '* &&
        " $* " == *' --user 10001:10001 '* &&
        " $* " == *'from control_api import require_wireguard_address'* &&
        "${!#}" == 10.77.0.1 && ! -f "${TEST_ROOT}/bad-address" ]]
}
dockerSetupTool() {
    [[ "$2" == uuid ]] || return 1
    local counter=0
    [[ ! -f "${TEST_ROOT}/uuid-counter" ]] || counter=$(<"${TEST_ROOT}/uuid-counter")
    counter=$((counter + 1))
    printf '%s\n' "${counter}" >"${TEST_ROOT}/uuid-counter"
    printf '00000000-0000-4000-8000-%012d\n' "${counter}"
}
dockerSetupRandomHex() {
    [[ "$2" == 32 ]] || return 1
    printf c%.0s {1..64}
    printf '\n'
}
dockerConfigureApply() {
    [[ "${DOCKER_CONTROL_TRANSACTION:-0}" == 1 &&
        "$(stat -c '%a:%u' "$(dirname -- "$1")")" == 700:0 &&
        "$(stat -c '%a:%u' "$1")" == 600:0 ]] || return 1
    if [[ -f "${TEST_ROOT}/retain-recovery" ]]; then
        DOCKER_CONFIG_CANDIDATE="${root}/.candidate.failed"
        mkdir -- "${DOCKER_CONFIG_CANDIDATE}"
        printf '{}\n' >"${DOCKER_CONFIG_CANDIDATE}/control-plan.json"
        DOCKER_CONFIG_SWITCHED=1
        DOCKER_CONFIG_BACKUP=
        return 17
    fi
    if [[ -f "${TEST_ROOT}/signal" ]]; then
        kill -s "$(<"${TEST_ROOT}/signal")" "${BASHPID}"
    fi
    [[ ! -f "${TEST_ROOT}/fail-apply" ]] || return 17
    python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" --spec "$1" >"${TEST_ROOT}/plan.json" ||
        return 1
    jq '.spec' "${TEST_ROOT}/plan.json" >"${spec}" &&
        mkdir -p "${root}/config/control" &&
        jq '.state' "${TEST_ROOT}/plan.json" >"${root}/config/control/state.json" &&
        chmod 0600 "${spec}" && chmod 0750 "${root}/config/control" &&
        chmod 0640 "${root}/config/control/state.json"
}
# 健康状态本阶段只验证有界的现有容器探针，不复用新容器替代在线状态。
dockerControlStateCheck() { [[ "$1" == "${root}" && ! -f "${TEST_ROOT}/bad-state" ]]; }
args=(--address 10.77.0.1 --port 18080 --peer-address 10.77.0.2 --yes)
original=$(sha256sum "${spec}")
dockerControlPrivateAddressIsValid 10.77.0.1 || fail '有效主控地址未通过参数校验'
dockerControlPrivateAddressIsValid 10.77.0.2 || fail '有效 Peer 地址未通过参数校验'

reject dockerControlCommand
reject dockerControlCommand status --json --json
reject dockerControlCommand init
reject dockerControlCommand init --address 8.8.8.8 --port 18080 --peer-address 10.77.0.2 --yes
reject dockerControlCommand init --address 10.77.0.01 --port 18080 --peer-address 10.77.0.2 --yes
reject dockerControlCommand init --address 10.77.0.1 --port 1023 --peer-address 10.77.0.2 --yes
reject dockerControlCommand init --address 10.77.0.1 --port 65536 --peer-address 10.77.0.2 --yes
reject dockerControlCommand init --address 10.77.0.1 --port 018080 --peer-address 10.77.0.2 --yes
reject dockerControlCommand init --address 10.77.0.1 --port 18080 --peer-address 10.77.0.1 --yes
reject dockerControlCommand init "${args[@]}" --yes
reject dockerControlCommand init "${args[@]}" --address 10.77.0.3
reject dockerControlCommand init "${args[@]}" --unknown
reject dockerControlCommand init --address 10.77.0.1 --port 18080 --peer-address
reject dockerControlCommand init --address 10.77.0.1 --port 18080 --peer-address 10.77.0.2
[[ ! -f "${TEST_ROOT}/host.log" ]] || fail '参数错误触及宿主'

json=$(dockerControlCommand status --json)
jq -e '.role == "standalone" and .node_id == null and .healthy == null' <<<"${json}" >/dev/null
for directory in "${root}" "${root}/config"; do
    originalMode=$(stat -c '%a' "${directory}")
    chmod 0770 "${directory}"
    reject dockerControlCommand init "${args[@]}"
    [[ "$(sha256sum "${spec}")" == "${original}" &&
        -z "$(find "${root}" -maxdepth 1 -name '.control-init.*' -print -quit)" ]]
    chmod "${originalMode}" "${directory}"
done
for marker in bad-deployment unowned bad-health bad-address fail-apply; do
    touch "${TEST_ROOT}/${marker}"
    reject dockerControlCommand init "${args[@]}"
    rm -- "${TEST_ROOT}/${marker}"
    [[ "$(sha256sum "${spec}")" == "${original}" &&
        -z "$(find "${root}" -maxdepth 1 -name '.control-init.*' -print -quit)" ]]
    [[ "$(tail -n 1 "${TEST_ROOT}/host.log")" == unlock ]]
done
printf '[Peer]\nPublicKey = %s\nAllowedIPs = 10.77.0.3/32\n' "${peerKey}" >>"${CONTROL_WG_CONFIG}"
reject dockerControlCommand init "${args[@]}"
cp -- "${TEST_ROOT}/safe-wg.conf" "${CONTROL_WG_CONFIG}"
sed 's@10.77.0.2/32@10.77.0.2/32, 10.77.0.3/32@' "${TEST_ROOT}/safe-wg.conf" >"${CONTROL_WG_CONFIG}"
reject dockerControlCommand init "${args[@]}"
cp -- "${TEST_ROOT}/safe-wg.conf" "${CONTROL_WG_CONFIG}"
printf '%s\t10.77.0.3/32\n' "${peerKey}" >"${CONTROL_WG_ACTUAL}"
reject dockerControlCommand init "${args[@]}"
printf '%s\t10.77.0.2/32\n' "$(printf D%.0s {1..43})=" >"${CONTROL_WG_ACTUAL}"
reject dockerControlCommand init "${args[@]}"
cp -- "${TEST_ROOT}/safe-wg.actual" "${CONTROL_WG_ACTUAL}"
[[ "$(sha256sum "${spec}")" == "${original}" ]]
for signal in INT TERM; do
    printf '%s\n' "${signal}" >"${TEST_ROOT}/signal"
    status=0
    dockerControlCommand init "${args[@]}" >"${TEST_ROOT}/signal.log" 2>&1 || status=$?
    if [[ "${signal}:${status}" != INT:130 && "${signal}:${status}" != TERM:143 ]]; then
        cat -- "${TEST_ROOT}/signal.log" >&2
        fail "信号退出码错误: ${signal}:${status}"
    fi
    [[ "$(sha256sum "${spec}")" == "${original}" &&
        -z "$(find "${root}" -maxdepth 1 -name '.control-init.*' -print -quit)" ]]
    [[ "$(tail -n 1 "${TEST_ROOT}/host.log")" == unlock ]]
done
rm -- "${TEST_ROOT}/signal"
touch "${TEST_ROOT}/retain-recovery"
reject dockerControlCommand init "${args[@]}"
[[ -f "${root}/.candidate.failed/control-plan.json" &&
    -z "$(find "${root}" -maxdepth 1 -name '.control-init.*' -print -quit)" ]]
rm -- "${TEST_ROOT}/retain-recovery"
dockerRemoveManagedTree "${root}" "${root}/.candidate.failed"

dockerControlCommand init "${args[@]}" >"${TEST_ROOT}/init.log"
jq -e '.control | .role == "main" and .node_id != .peer.id and
  .listen == {interface:"wg-padm",address:"10.77.0.1",port:18080} and
  .peer.address == "10.77.0.2" and .peer.enabled == false and .peer.expires_at == 1 and
  (.peer.token_sha256 | test("^[a-f0-9]{64}$")) and
  .revision == 0 and (.last_digest | test("^[a-f0-9]{64}$"))' "${spec}" >/dev/null
reject dockerControlCommand init "${args[@]}"
json=$(dockerControlCommand status --json)
text=$(dockerControlCommand status)
jq -e 'keys == ["authorization","controller_id","healthy","listen","node_id","peer_address","revision","role"] and
  .role == "main" and .healthy == true and .revision == 0 and
  .authorization == {enabled:false, expires_at:1}' <<<"${json}" >/dev/null
cp -- "${spec}" "${TEST_ROOT}/main.json"
rm -- "${spec}"
reject dockerControlCommand status --json
cp -- "${TEST_ROOT}/main.json" "${spec}"
chmod 0600 "${spec}"
for secret in 'CLI.-~@+=:Secret' cli-subscription-secret "$(printf c%.0s {1..64})" \
    "$(jq -r '.control.peer.token_sha256' "${spec}")" "$(jq -r '.control.last_digest' "${spec}")"; do
    [[ "${json}" != *"${secret}"* ]]
    [[ "${text}" != *"${secret}"* ]]
    if grep -Fq -- "${secret}" "${TEST_ROOT}/init.log"; then fail '初始化泄露敏感值'; fi
done
touch "${TEST_ROOT}/control-down"
json=$(dockerControlCommand status --json)
jq -e '.healthy == false' <<<"${json}" >/dev/null
rm -- "${TEST_ROOT}/control-down"
touch "${TEST_ROOT}/bad-state"
reject dockerControlCommand status --json
rm -- "${TEST_ROOT}/bad-state"
mkdir -- "${root}/.candidate.residual"
printf '{}\n' >"${root}/.candidate.residual/control-plan.json"
dockerControlCommand status --json >/dev/null
dockerRemoveManagedTree "${root}" "${root}/.candidate.residual"

jq '.control_sync = {
  schema_version:1, role:"controlled", node_id:"33333333-3333-4333-8333-333333333333",
  controller_id:"44444444-4444-4444-8444-444444444444", listener_ids:["entry-reality"],
  last_revision:null, last_digest:null, managed_accounts:[]
}' "${TEST_ROOT}/standalone.json" >"${spec}"
chmod 0600 "${spec}"
json=$(dockerControlCommand status --json)
jq -e '.role == "controlled" and .controller_id != null and .healthy == null and .revision == null and
  .authorization == null' \
    <<<"${json}" >/dev/null
reject dockerControlCommand init "${args[@]}"
[[ -z "$(find "${root}" -maxdepth 1 -name '.control-init.*' -print -quit)" ]]
# 旧版协议凭据经标准迁移后初始化；账号数组从 schema 3 才开始支持。
jq '.schema_version = 2 | del(.accounts, .core.secondary_type) |
  .core.protocols |= map(del(.core))' \
    "${TEST_ROOT}/standalone.json" >"${spec}"
chmod 0600 "${spec}"
dockerControlCommand init "${args[@]}" >/dev/null
jq -e '.schema_version == 3 and .core.secondary_type == null and
  .core.protocols[0].core == "xray" and .control.role == "main" and
  .core.protocols[0].uuid == "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"' "${spec}" >/dev/null

(
    # 从实际 Compose 构造 inspect 夹具，独立目录不改变后续命令的在线文件。
    snapshotRoot="${TEST_ROOT}/source-snapshot"
    mkdir -p "${snapshotRoot}/config/control" "${snapshotRoot}/secrets/net/wireguard" \
        "${snapshotRoot}/data/net/wireguard"
    cp -- "${spec}" "${snapshotRoot}/config/spec.json"
    cp -- "${root}/config/control/state.json" "${snapshotRoot}/config/control/state.json"
    cp -- "${root}/images.env" "${snapshotRoot}/images.env"
    cp -- "${CONTROL_WG_CONFIG}" "${snapshotRoot}/secrets/net/wireguard/wg-padm.conf"
    printf '{}\n' >"${snapshotRoot}/deployment.json"
    printf '{}\n' >"${snapshotRoot}/data/net/wireguard/wireguard.state"
    root=${snapshotRoot}
    spec="${root}/config/spec.json"
    export PADM_DOCKER_INSTALL_DIR="${root}"
    dockerGenerateCompose "${spec}" "${root}/compose.json" "${root}"
    dockerControlRequireMain() { [[ "$1" == "${spec}" && "$2" == "${root}" ]]; }
    dockerControlInviteRuntimeCheck() { [[ "$1" == "${spec}" ]]; }
    controlId="$(printf 1%.0s {1..64})"
    netId="$(printf 2%.0s {1..64})"
    for service in control net-wireguard; do
        jq --arg root "${root}" --arg service "${service}" --arg controlId "${controlId}" \
            --arg netId "${netId}" --slurpfile spec "${spec}" '
          .services[$service] as $s |
          [{
            Id: (if $service == "control" then $controlId else $netId end),
            State: {Status:"running", Running:true, Restarting:false, Paused:false, Dead:false,
              Health:{Status:"healthy"}, StartedAt:"2026-10-10T00:00:00.000Z"},
            RestartCount:0,
            Config: {
              Labels: ($s.labels + {
                "com.docker.compose.project":"padm-docker",
                "com.docker.compose.project.working_dir":$root,
                "com.docker.compose.project.config_files":($root + "/compose.json"),
                "com.docker.compose.service":$service, "com.docker.compose.oneoff":"False"
              }),
              Image:$spec[0].images[if $service == "control" then "ops" else "net" end],
              User:($s.user // "0:0"), Entrypoint:["/usr/local/bin/padm-entrypoint"],
              Cmd:$s.command, Healthcheck:{Test:$s.healthcheck.test}
            },
            HostConfig: {
              NetworkMode:$s.network_mode, ReadonlyRootfs:$s.read_only, Privileged:false, Init:$s.init,
              CapAdd:($s.cap_add // [] | map("CAP_" + .)), CapDrop:$s.cap_drop,
              SecurityOpt:$s.security_opt, LogConfig:{Type:$s.logging.driver, Config:$s.logging.options},
              Tmpfs:($s.tmpfs | map(split(":") | {key:.[0], value:.[1]}) | from_entries)
            },
            Mounts:($s.volumes | map({
              Type:"bind", Source:(.source | sub("^\\$\\{PADM_(DOCKER|NET)_ROOT\\}"; $root)),
              Destination:.target, RW:(.read_only | not)
            }))
          }]
        ' "${root}/compose.json" >"${TEST_ROOT}/snapshot-${service}.json"
    done
    docker() {
        if [[ "$1" == ps ]]; then
            case "$*" in
            *label=com.docker.compose.service=control*) printf '%s\n' "${controlId}" ;;
            *label=com.docker.compose.service=net-wireguard*) printf '%s\n' "${netId}" ;;
            *) return 1 ;;
            esac
        elif [[ "$*" == "container inspect ${controlId}" ]]; then
            cat -- "${TEST_ROOT}/snapshot-control.json"
        elif [[ "$*" == "container inspect ${netId}" ]]; then
            jq --arg fault "${SNAPSHOT_FAULT:-}" '
              if $fault == "extra-cap" then .[0].HostConfig.CapAdd += ["CAP_NET_RAW"]
              elif $fault == "wrong-mount" then .[0].Mounts[0].Source += ".wrong"
              else . end
            ' "${TEST_ROOT}/snapshot-net-wireguard.json"
        else
            return 1
        fi
    }
    dockerControlSourceSnapshot >"${TEST_ROOT}/snapshot.json"
    jq -e '(.containers | length == 2) and
      (.hashes | split("\n") | map(select(length > 0)) | length == 7)' \
        "${TEST_ROOT}/snapshot.json" >/dev/null
    (
        sha256sum() { return 1; }
        reject dockerControlSourceSnapshot
    )
    for SNAPSHOT_FAULT in extra-cap wrong-mount; do
        reject dockerControlSourceSnapshot
    done
)

(
    # 仅在线代次检查使用桩，登记、偏移解析及信号清理走生产命令。
    dockerControlAccessLogEnsure "${root}"
    sourceDirectory="${root}/data/control-source"
    receipt="${root}/logs/control/source.receipt"
    nonce="$(printf c%.0s {1..64})"
    dockerControlSourceSnapshot() {
        if [[ -f "${TEST_ROOT}/source-drift" ]]; then printf 'changed\n'; else printf 'stable\n'; fi
    }
    mv() {
        command mv "$@" || return $?
        if [[ "${SOURCE_CASE:-}" == publish-signal && "$*" == *'.control-source.'* ]]; then
            kill -TERM "${BASHPID}"
        fi
    }
    sleep() {
        local challenge="${sourceDirectory}/challenge.json" event
        [[ "$1" == 1 && -f "${challenge}" ]] || return 1
        case "${SOURCE_CASE:-valid}" in
        signal) kill -TERM "${BASHPID}"; return ;;
        changed-registration)
            jq '.target = "10.77.0.3"' "${challenge}" >"${TEST_ROOT}/changed-source.json"
            cat -- "${TEST_ROOT}/changed-source.json" >"${challenge}"
            return
            ;;
        drift) touch "${TEST_ROOT}/source-drift" ;;
        esac
        event="$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ') control-source nonce=${nonce} status=401 source=10.77.0.2 target=10.77.0.1 port=18080"
        printf '%s\n' "${event}" >>"${receipt}"
    }
    reject dockerControlCommand source-check --extra
    reject dockerControlCommand source-probe --address 8.8.8.8 --port 18080 --peer-address 10.77.0.2 --nonce "${nonce}"
    reject dockerControlCommand source-probe --address 10.77.0.1 --port 18080 --peer-address 10.77.0.2 --nonce short
    # 偏移以前的同 nonce 行不得自证；部分行、截断、替换和错来源有独立失败价值。
    event="2026-10-10T00:00:01.000Z control-source nonce=${nonce} status=401 source=10.77.0.2 target=10.77.0.1 port=18080"
    printf '%s\n' "${event}" >"${receipt}"
    cursor=$(stat -c '%d:%i:%s' "${receipt}")
    receiptArgs=("${receipt}" "${cursor}" "${nonce}" 10.77.0.2 10.77.0.1 18080 \
        2026-10-10T00:00:00.000Z 2026-10-10T00:00:30.000Z)
    [[ "$(dockerControlSourceReceipt "${receiptArgs[@]}")" == pending ]]
    printf '%s' "${event}" >>"${receipt}"
    [[ "$(dockerControlSourceReceipt "${receiptArgs[@]}")" == pending ]]
    printf '\n' >>"${receipt}"
    [[ "$(dockerControlSourceReceipt "${receiptArgs[@]}")" == verified ]]
    (
        dd() { command dd "$@"; return 1; }
        reject dockerControlSourceReceipt "${receiptArgs[@]}"
    )
    printf '%s\n' "${event}" >>"${receipt}"
    reject dockerControlSourceReceipt "${receiptArgs[@]}"
    : >"${receipt}"
    reject dockerControlSourceReceipt "${receiptArgs[@]}"
    cursor=$(stat -c '%d:%i:%s' "${receipt}")
    receiptArgs[1]=${cursor}
    printf '%s\n' "${event/10.77.0.2/10.77.0.3}" >>"${receipt}"
    reject dockerControlSourceReceipt "${receiptArgs[@]}"
    : >"${receipt}"
    printf 'untrusted receipt\n' >>"${receipt}"
    reject dockerControlSourceReceipt "${receiptArgs[@]}"
    : >"${receipt}"
    beforeReceipt=$(stat -c '%s' "${receipt}")
    dockerControlCommand source-check >"${TEST_ROOT}/source-check.log" 2>"${TEST_ROOT}/source-check.err"
    grep -Fq 'source-verified=' "${TEST_ROOT}/source-check.log"
    [[ ! -e "${sourceDirectory}/challenge.json" && "$(stat -c '%s' "${receipt}")" -gt "${beforeReceipt}" ]]
    for SOURCE_CASE in signal publish-signal drift changed-registration; do
        status=0
        dockerControlCommand source-check >"${TEST_ROOT}/source-check.log" 2>&1 || status=$?
        if [[ "${SOURCE_CASE}" == signal || "${SOURCE_CASE}" == publish-signal ]]; then
            [[ "${status}" == 143 && ! -e "${sourceDirectory}/challenge.json" ]]
        elif [[ "${SOURCE_CASE}" == changed-registration ]]; then
            [[ "${status}" == 15 && -f "${sourceDirectory}/challenge.json" ]]
            reject dockerControlCommand source-check
            rm -- "${sourceDirectory}/challenge.json"
        else
            [[ "${status}" == 15 && ! -e "${sourceDirectory}/challenge.json" ]]
            rm -- "${TEST_ROOT}/source-drift"
        fi
    done
    [[ -z "$(find "${root}" -maxdepth 1 -name '.control-source.*' -print -quit)" ]]
    [[ "$(grep -c '^lock$' "${TEST_ROOT}/host.log")" == "$(grep -c '^unlock$' "${TEST_ROOT}/host.log")" ]]
    (
        dockerControlClientRuntimeCheck() { [[ "$1" == "${root}/.control-source-probe."*/connection.json ]]; }
        dockerRealityProbeRun() {
            [[ "$1" == 10 && " $* " == *' --log-driver none '* &&
                " $* " == *'from control_client import source_probe'* ]]
        }
        probeArgs=(--address 10.77.0.1 --port 18080 --peer-address 10.77.0.2 --nonce "${nonce}")
        dockerControlCommand source-probe "${probeArgs[@]}"
        [[ -z "$(find "${root}" -maxdepth 1 -name '.control-source-probe.*' -print -quit)" ]]
        dockerRemoveManagedTree() { return 1; }
        status=0
        dockerControlCommand source-probe "${probeArgs[@]}" >"${TEST_ROOT}/probe-cleanup.log" 2>&1 || status=$?
        [[ "${status}" == 15 ]]
        grep -Fq '控制来源探测临时目录清理失败' "${TEST_ROOT}/probe-cleanup.log"
        for directory in "${root}"/.control-source-probe.*; do
            [[ -d "${directory}" ]] && rm -rf -- "${directory}"
        done
    )
)
printf 'docker-control-cli-regression-ok\n'
