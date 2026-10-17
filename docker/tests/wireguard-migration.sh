#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d /root/padm-wireguard-migration.XXXXXX)
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "wireguard-migration-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]]
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PYTHONDONTWRITEBYTECODE=1
LOG=${TEST_ROOT}/output.log
CALLS=${TEST_ROOT}/calls.log
MODE=ok
checks=0
# 运行生产候选、备份、安装和恢复；仅替换无关业务验证与 Docker 边界。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
declare -A controlFunctions=()
for helper in dockerControlTransitionValidate dockerControlSyncTransitionValidate \
    dockerControlRestorePrepare dockerControlStateCheck; do
    controlFunctions[${helper}]=$(declare -f "${helper}")
done
for helper in dockerControlRecoveryCheck dockerConfigureSpecValidate dockerAcmeWebrootTransitionValidate \
    dockerControlSyncTransitionValidate dockerControlSyncScheduleSpecCheck dockerControlTransitionValidate \
    dockerRealityStreamDeploymentCheck dockerTrafficRuntimeCheck dockerTrafficBeforeChange \
    dockerConfigureReleaseValidate dockerRealityTargetsValidate dockerConfigurePortsAvailable \
    dockerValidateCandidate dockerFail2banSourceInputsPrepare dockerControlAccessLogEnsure \
    dockerEnsureRuntimeDataPermissions dockerTrafficScheduleInstall dockerRenewalScheduleInstall \
    dockerGeoScheduleInstall dockerControlLogScheduleInstall dockerControlSyncScheduleInstall \
    dockerValidateConfigurationBackup dockerSiteTreeValidate dockerControlStateCheck \
    dockerTProxyDisablePrepare dockerTunDisablePrepare dockerFail2banDisablePrepare \
    dockerControlFail2banDisablePrepare dockerSshFail2banDisablePrepare dockerTunTransitionPrepare \
    dockerRealityStreamTransitionPrepare dockerFail2banSourceInputsCheck dockerControlRestorePrepare \
    dockerTrafficPrepareCandidate; do
    eval "${helper}() { :; }"
done
dockerGenerateCandidate() {
    local source=$1 candidate=$2
    dockerControlPrepareCandidate "${source}" "${candidate}" "${root}/config/spec.json" || return 1
    printf '%s\n' '{}' >"${candidate}/compose.json"
    printf '%s\n' '{}' >"${candidate}/deployment.json"
    : >"${candidate}/images.runtime.env"
    dockerStageHostIntegrationFiles "${source}" "${candidate}"
}
dockerWireGuardContainer() {
    printf 'audit-%s\n' "$1" >>"${CALLS}"
    [[ "${MODE}" != owner-drift || "$1" != running ]] || return 1
    if [[ "${MODE}" == runtime-drift ]] &&
        cmp -s -- "${root}/secrets/net/wireguard/identity.json" "${input}/identity.json"; then
        return 1
    fi
    printf '%064d\n' 1
}
docker() {
    if [[ "$1" == ps ]]; then
        printf '%064d\n' 1
        return 0
    fi
    [[ "$1" != run ]] || return 0
    [[ "$1" == stop && "$2" == -t && "$3" == 30 && "$4" == "$(printf '%064d' 1)" ]] || return 1
    printf 'stop\n' >>"${CALLS}"
}
dockerComposeExecute() {
    [[ "$1" == down ]] || return 1
    printf 'down\n' >>"${CALLS}"
}
dockerComposeRun() {
    [[ "$1" == up ]] || return 1
    printf 'up\n' >>"${CALLS}"
    if cmp -s -- "${root}/secrets/net/wireguard/identity.json" "${input}/identity.json"; then
        case "${MODE}" in
        fail-up) return 1 ;;
        INT|TERM) kill -"${MODE}" "${BASHPID}"; return 1 ;;
        directory-drift)
            mv -- "${root}/secrets/net/wireguard" "${root}/foreign-original"
            mkdir -m 0700 -- "${root}/secrets/net/wireguard"
            cp -- "${input}/"* "${root}/secrets/net/wireguard/"
            return 1
            ;;
        runtime-drift) return 1 ;;
        esac
    fi
}
dockerWireGuardMigrate() (
    trap 'status=$?; trap - EXIT INT TERM; dockerConfigurationInterrupted; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerConfigureApply "${MIGRATION_SPEC:-${root}/config/spec.json}" '' '' configure '' '' '' '' '' "${input}"
)
fixture() {
    root=$(mktemp -d "${TEST_ROOT}/case.XXXXXX")
    export PADM_DOCKER_INSTALL_DIR=${root}
    mkdir -m 0700 -- "${root}/config" "${root}/secrets" "${root}/data" "${root}/backups"
    mkdir -m 0700 -- "${root}/secrets/net" "${root}/data/traffic"
    input=$(mktemp -d "${root}/.wireguard.XXXXXX")/wireguard
    printf '%s\n' '{"schema_version":3,"core":{"type":"xray","secondary_type":null,"protocols":[]},
        "tls":null,"images":{"net":"fixture"},"host_integrations":[{"type":"wireguard"}]}' >"${root}/config/spec.json"
    printf '%s\n' '{}' >"${root}/deployment.json"
    printf '%s\n' '{}' >"${root}/compose.json"
    : >"${root}/images.env"
    printf '%s\n' '{"schema_version":1,"accounts":{}}' >"${root}/data/traffic/state.json"
    chmod 0600 "${root}/config/spec.json" "${root}/data/traffic/state.json"
    printf '%032d' 1 | base64 >"${root}/old-private"
    printf '%032d' 2 | base64 >"${root}/old-public"
    printf '%032d' 3 | base64 >"${root}/new-private"
    printf '%032d' 4 | base64 >"${root}/new-public"
    local file
    for file in "${root}/"*private "${root}/"*public; do chmod 0600 "${file}"; done
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare \
        --directory "${root}/secrets/net/wireguard" --address 10.77.0.1 --listen-port 51820 \
        --private-key "${root}/old-private" --public-key "${root}/old-public" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" peer \
        --directory "${root}/secrets/net/wireguard" --peer-address 10.77.0.2 \
        --peer-public-key "$(cat "${root}/new-public")" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" prepare \
        --directory "${input}" --address 10.88.0.1 --listen-port 51821 \
        --private-key "${root}/new-private" --public-key "${root}/new-public" >/dev/null
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" peer \
        --directory "${input}" --peer-address 10.88.0.2 \
        --peer-public-key "$(cat "${root}/old-public")" --endpoint 192.0.2.1:51821 >/dev/null
    cp -a -- "${root}/secrets/net/wireguard" "${root}/expected"
    : >"${CALLS}"
    DOCKER_CONFIG_CANDIDATE=
    DOCKER_CONFIG_BACKUP=
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_WIREGUARD_MIGRATION=0
    DOCKER_CONFIG_WIREGUARD_SOURCE=
    MIGRATION_SPEC=
    MODE=ok
}
assertOld() {
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    [[ "$(stat -c '%u:%a' "${root}/secrets/net/wireguard")" == 0:700 ]]
    jq -e '.accounts == {}' "${root}/data/traffic/state.json" >/dev/null
    checks=$((checks + 1))
}
runMigration() {
    local expected=$1 status=0
    dockerWireGuardMigrate >"${LOG}" 2>&1 || status=$?
    [[ "${status}" == "${expected}" ]] || { cat "${LOG}" >&2; return 1; }
    checks=$((checks + 1))
}

fixture
runMigration 0
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
[[ "$(grep -c '^stop$' "${CALLS}")" == 1 ]]
checks=$((checks + 1))

for MODE_CASE in fail-up INT TERM; do
    fixture
    MODE=${MODE_CASE}
    expected=14
    [[ "${MODE}" != INT ]] || expected=130
    [[ "${MODE}" != TERM ]] || expected=143
    runMigration "${expected}"
    assertOld
    grep -qxF down "${CALLS}"
    grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
done

fixture
MODE=owner-drift
runMigration 14
assertOld
! grep -qxF stop "${CALLS}"
checks=$((checks + 1))

fixture
MODE=directory-drift
runMigration 14
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
! grep -qxF down "${CALLS}"
previous=$(find "${root}" -path '*/wireguard.previous/identity.json' -print)
[[ -n "${previous}" ]]
diff -qr -- "${root}/expected" "${previous%/identity.json}"
checks=$((checks + 1))

fixture
MODE=runtime-drift
runMigration 14
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
! grep -qxF down "${CALLS}"
previous=$(find "${root}" -path '*/wireguard.previous/identity.json' -print)
[[ -n "${previous}" ]]
diff -qr -- "${root}/expected" "${previous%/identity.json}"
checks=$((checks + 1))

fixture
status=0
dockerConfigureApply "${root}/config/spec.json" '' '' configure '' '' '' '' '' "${input}" \
    >"${LOG}" 2>&1 || status=$?
[[ "${status}" == 15 && ! -s "${CALLS}" ]]
checks=$((checks + 1))
DOCKER_WIREGUARD_INPUT=${input} dockerConfigureApply "${root}/config/spec.json" >"${LOG}" 2>&1
assertOld
! grep -qxF stop "${CALLS}"
! grep -qxF secrets/net/wireguard "${root}"/backups/configure.*/present
checks=$((checks + 1))

fixture
DOCKER_WIREGUARD_INPUT=${input} dockerBackupConfiguration
cp -- "${input}/"* "${root}/secrets/net/wireguard/"
DOCKER_CONFIG_SWITCHED=1
status=0
dockerRestoreConfiguration >"${LOG}" 2>&1 || status=$?
[[ "${status}" != 0 && ! -s "${CALLS}" ]]
diff -qr -- "${input}" "${root}/secrets/net/wireguard"
checks=$((checks + 1))

fixture
DOCKER_WIREGUARD_INPUT=${input} dockerBackupConfiguration
before=$(stat -c '%d:%i' "${root}/secrets/net/wireguard")
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration >"${LOG}" 2>&1
assertOld
[[ "$(stat -c '%d:%i' "${root}/secrets/net/wireguard")" == "${before}" ]]
checks=$((checks + 1))

[[ "${checks}" == 21 ]]
for helper in "${!controlFunctions[@]}"; do
    eval "${controlFunctions[${helper}]}"
done
dockerManagedSpecMatchesDeployment() { :; }
dockerGenerateCompatibleControlCompose() { cat -- "$2"; }
dockerControlPlan() {
    local directory=$1 argument
    local -a arguments=()
    shift 2
    for argument in "$@"; do
        arguments+=("${argument/#\/input\//${directory}/}")
    done
    python3 -B "${PROJECT_ROOT}/docker/images/ops/control_state.py" \
        --spec "${directory}/spec.json" "${arguments[@]}"
}
roleFixture() {
    local role=$1 plan directory
    fixture
    directory=$(mktemp -d "${root}/.wireguard.XXXXXX")
    input="${directory}/wireguard"
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" migrate \
        --directory "${root}/secrets/net/wireguard" --destination "${input}" \
        --listen-port 51821 --private-key "${root}/new-private" --public-key "${root}/new-public" \
        --peer-public-key "$(cat "${root}/old-public")" --endpoint 192.0.2.1:51821 >/dev/null
    jq --arg role "${role}" '
      def account($number):
        {id:("0000000" + $number + "-1111-4111-8111-00000000000" + $number),
         name:("账号" + $number),enabled:true,
         uuid:("0000010" + $number + "-1111-4111-8111-00000000010" + $number),
         password:("MigrationPassword.000" + $number),shadowsocks_password:null,
         listeners:["entry-main"]};
      .images.ops = "fixture" |
      .core.protocols = [{listener_id:"entry-main",id:1,uuid:"00000009-1111-4111-8111-000000000009"}] |
      .accounts = [account("3"),account("4")] |
      if $role == "main" then
        .control = {schema_version:1,role:"main",
          node_id:"00000001-1111-4111-8111-000000000001",
          listen:{interface:"wg-padm",address:"10.77.0.1",port:18080},
          peer:{id:"00000002-1111-4111-8111-000000000002",address:"10.77.0.2",
            enabled:true,expires_at:2000000000,token_sha256:("a"*64)},revision:0,last_digest:null}
      else
        .control_sync = {schema_version:1,role:"controlled",
          node_id:"00000002-1111-4111-8111-000000000002",
          controller_id:"00000001-1111-4111-8111-000000000001",
          listener_ids:["entry-main"],last_revision:7,last_digest:("d"*64),
          managed_accounts:[.accounts[1]],
          connection:{listen:{interface:"wg-padm",address:"10.77.0.2",port:18080},
            peer_address:"10.77.0.1"}}
      end' "${root}/config/spec.json" >"${root}/role.json"
    mv -- "${root}/role.json" "${root}/config/spec.json"
    chmod 0600 "${root}/config/spec.json"
    if [[ "${role}" == main ]]; then
        mkdir -m 0750 -- "${root}/config/control"
        plan="${root}/role-plan.json"
        (umask 077; dockerControlPlan "${root}/config" fixture >"${plan}")
        jq '.spec' "${plan}" >"${root}/config/spec.json"
        jq '.state' "${plan}" >"${root}/config/control/state.json"
        chmod 0600 "${root}/config/spec.json"
        chmod 0640 "${root}/config/control/state.json"
        mkdir -m 0700 -- "${root}/data/control-log"
        printf '%s\n' '{"schema_version":1,"enabled":false}' >"${root}/data/control-log/schedule.json"
        chmod 0600 "${root}/data/control-log/schedule.json"
        mkdir -m 0750 -- "${root}/data/control-source"
        chown "0:${PADM_DOCKER_CONTAINER_GID}" "${root}/data/control-source"
    fi
    jq -n '{schema_version:1,accounts:{
      "00000003-1111-4111-8111-000000000003":
        {name:"账号3",upload:123,download:456,limit_bytes:9000,baseline:{}},
      "00000004-1111-4111-8111-000000000004":
        {name:"账号4",upload:789,download:111,limit_bytes:8000,baseline:{}}}}' \
        >"${root}/data/traffic/state.json"
    cp -- "${root}/config/spec.json" "${root}/role-before.json"
    cp -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
}
assertRoleKept() {
    cmp -s -- "${root}/config/spec.json" "${root}/role-before.json"
    cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
    checks=$((checks + 1))
}

for role in main controlled; do
    roleFixture "${role}"
    runMigration 0
    diff -qr -- "${input}" "${root}/secrets/net/wireguard"
    assertRoleKept
    [[ "${role}" != main ]] || dockerControlStateCheck "${root}"

    for field in --address --peer-address; do
        roleFixture "${role}"
        directory=$(mktemp -d "${root}/.wireguard.XXXXXX")
        input="${directory}/wireguard"
        python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" migrate \
            --directory "${root}/secrets/net/wireguard" --destination "${input}" \
            "${field}" 10.77.0.9 >/dev/null
        runMigration "${PADM_DOCKER_RC_CONFLICT}"
        diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
        [[ ! -s "${CALLS}" ]]
        assertRoleKept
    done
done

roleFixture main
directory=$(mktemp -d "${root}/.wireguard.XXXXXX")
python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" migrate \
    --directory "${root}/secrets/net/wireguard" --destination "${directory}/wireguard" \
    --address 10.77.0.9 >/dev/null
cp -- "${directory}/wireguard/"* "${root}/secrets/net/wireguard/"
cp -a -- "${root}/secrets/net/wireguard" "${root}/drift-before"
runMigration "${PADM_DOCKER_RC_CONFLICT}"
diff -qr -- "${root}/drift-before" "${root}/secrets/net/wireguard"
[[ ! -s "${CALLS}" ]]
cmp -s -- "${root}/config/spec.json" "${root}/role-before.json"
cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"

for dependency in log-schedule fail2ban-control source-challenge control-sync; do
    role=main
    [[ "${dependency}" != control-sync ]] || role=controlled
    roleFixture "${role}"
    case "${dependency}" in
    log-schedule)
        printf '%s\n' '{"schema_version":1,"enabled":true}' >"${root}/data/control-log/schedule.json"
        chmod 0600 "${root}/data/control-log/schedule.json"
        ;;
    fail2ban-control)
        jq '.host_integrations += [{type:"fail2ban-control"}]' "${root}/config/spec.json" >"${root}/next.json"
        mv -- "${root}/next.json" "${root}/config/spec.json"
        chmod 0600 "${root}/config/spec.json"
        cp -- "${root}/config/spec.json" "${root}/role-before.json"
        ;;
    source-challenge)
        printf '%s\n' '{}' >"${root}/data/control-source/challenge.json"
        chmod 0600 "${root}/data/control-source/challenge.json"
        ;;
    control-sync)
        mkdir -m 0700 -- "${root}/secrets/control-sync"
        printf '%s\n' '{}' >"${root}/secrets/control-sync/request.json"
        chmod 0600 "${root}/secrets/control-sync/request.json"
        ;;
    esac
    runMigration "${PADM_DOCKER_RC_CONFLICT}"
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    [[ ! -s "${CALLS}" ]]
    assertRoleKept
done

for MODE_CASE in fail-up INT TERM; do
    roleFixture main
    MODE=${MODE_CASE}
    expected=14
    [[ "${MODE}" != INT ]] || expected=130
    [[ "${MODE}" != TERM ]] || expected=143
    runMigration "${expected}"
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
    jq -e '.control.peer.enabled == false and .control.peer.expires_at == 1' \
        "${root}/config/spec.json" >/dev/null
    jq -e '.peer.enabled == false and .peer.expires_at == 1' \
        "${root}/config/control/state.json" >/dev/null
    jq -e --slurpfile before "${root}/role-before.json" \
        'del(.control.peer.enabled,.control.peer.expires_at) ==
         ($before[0] | del(.control.peer.enabled,.control.peer.expires_at))' \
        "${root}/config/spec.json" >/dev/null
    dockerControlStateCheck "${root}"
    checks=$((checks + 1))
done

for role in main controlled; do
    roleFixture "${role}"
    if [[ "${role}" == main ]]; then
        jq '.control.listen.port += 1' "${root}/config/spec.json" >"${root}/next.json"
    else
        jq '.control_sync.last_revision += 1' "${root}/config/spec.json" >"${root}/next.json"
    fi
    chmod 0600 "${root}/next.json"
    status=0
    DOCKER_WIREGUARD_INPUT=${input} dockerConfigureApply "${root}/next.json" >"${LOG}" 2>&1 || status=$?
    [[ "${status}" == "${PADM_DOCKER_RC_CONFLICT}" && ! -s "${CALLS}" ]]
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    assertRoleKept
done

roleAddressFixture() {
    local role=$1 directory
    roleFixture "${role}"
    directory=$(mktemp -d "${root}/.wireguard.XXXXXX")
    input="${directory}/wireguard"
    python3 -B "${DOCKER_LIB_DIR}/wireguard-config.py" migrate \
        --directory "${root}/secrets/net/wireguard" --destination "${input}" \
        --address 10.88.0.1 --peer-address 10.88.0.2 --listen-port 51821 \
        --private-key "${root}/new-private" --public-key "${root}/new-public" \
        --peer-public-key "$(cat "${root}/old-public")" --endpoint 192.0.2.1:51821 >/dev/null
    MIGRATION_SPEC="${directory}/spec.json"
    jq --arg role "${role}" '
      if $role == "main" then
        .control.listen.address = "10.88.0.1" | .control.peer.address = "10.88.0.2" |
        .control.peer.enabled = false | .control.peer.expires_at = 1
      else
        .control_sync.connection.peer_address = "10.88.0.1" |
        .control_sync.connection.listen.address = "10.88.0.2"
      end' "${root}/config/spec.json" >"${MIGRATION_SPEC}"
    chmod 0600 "${MIGRATION_SPEC}"
}
assertRoleRestored() {
    local role=$1
    diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
    cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
    if [[ "${role}" == main ]]; then
        jq -e --slurpfile before "${root}/role-before.json" '
          .control.peer.enabled == false and .control.peer.expires_at == 1 and
          del(.control.peer.enabled,.control.peer.expires_at) ==
            ($before[0] | del(.control.peer.enabled,.control.peer.expires_at))
        ' "${root}/config/spec.json" >/dev/null
        dockerControlStateCheck "${root}"
    else
        cmp -s -- "${root}/config/spec.json" "${root}/role-before.json"
    fi
    checks=$((checks + 1))
}

for role in main controlled; do
    roleAddressFixture "${role}"
    runMigration 0
    diff -qr -- "${input}" "${root}/secrets/net/wireguard"
    jq -en --slurpfile expected "${MIGRATION_SPEC}" --slurpfile actual "${root}/config/spec.json" \
        '$actual == $expected' >/dev/null
    cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
    [[ "${role}" != main ]] || dockerControlStateCheck "${root}"
    [[ "${DOCKER_CONTROL_TRANSACTION:-0}" == 0 && "${DOCKER_CONTROL_SYNC_TRANSACTION:-0}" == 0 ]]
    checks=$((checks + 1))

    for MODE_CASE in fail-up INT TERM owner-drift; do
        roleAddressFixture "${role}"
        MODE=${MODE_CASE}
        expected=14
        [[ "${MODE}" != INT ]] || expected=130
        [[ "${MODE}" != TERM ]] || expected=143
        runMigration "${expected}"
        assertRoleRestored "${role}"
        if [[ "${MODE}" == owner-drift ]]; then
            ! grep -qxF stop "${CALLS}"
        else
            grep -qxF down "${CALLS}"
        fi
    done
    for MODE_CASE in directory-drift runtime-drift; do
        roleAddressFixture "${role}"
        MODE=${MODE_CASE}
        runMigration 14
        diff -qr -- "${input}" "${root}/secrets/net/wireguard"
        ! grep -qxF down "${CALLS}"
        previous=$(find "${root}" -path '*/wireguard.previous/identity.json' -print)
        [[ -n "${previous}" ]]
        diff -qr -- "${root}/expected" "${previous%/identity.json}"
        jq -en --slurpfile expected "${MIGRATION_SPEC}" --slurpfile actual "${root}/config/spec.json" \
            '$actual == $expected' >/dev/null
        cmp -s -- "${root}/data/traffic/state.json" "${root}/traffic-before.json"
        checks=$((checks + 1))
    done

    for mutation in identity revision accounts images port role unchanged-address wrong-address \
        public-spec linked-spec main-authorized; do
        [[ "${mutation}" != main-authorized || "${role}" == main ]] || continue
        roleAddressFixture "${role}"
        case "${mutation}" in
        identity)
            jq 'if has("control") then .control.node_id = "00000008-1111-4111-8111-000000000008"
              else .control_sync.controller_id = "00000008-1111-4111-8111-000000000008" end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        revision)
            jq 'if has("control") then .control.revision += 1 else .control_sync.last_revision += 1 end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        accounts)
            jq '.accounts[0].name = "越界修改"' "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        images)
            jq '.images.net = "different"' "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        port)
            jq 'if has("control") then .control.listen.port += 1
              else .control_sync.connection.listen.port += 1 end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        role)
            jq 'if has("control") then .control.role = "controlled" else .control_sync.role = "main" end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        unchanged-address)
            jq --slurpfile before "${root}/role-before.json" '
              if has("control") then
                .control.listen.address = $before[0].control.listen.address |
                .control.peer.address = $before[0].control.peer.address
              else .control_sync.connection = $before[0].control_sync.connection end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        wrong-address)
            jq 'if has("control") then .control.listen.address = "10.88.0.9"
              else .control_sync.connection.peer_address = "10.88.0.9" end' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        public-spec) chmod 0640 "${MIGRATION_SPEC}" ;;
        linked-spec)
            mv -- "${MIGRATION_SPEC}" "${root}/linked-spec.json"
            ln -s -- "${root}/linked-spec.json" "${MIGRATION_SPEC}" ;;
        main-authorized)
            jq '.control.peer.enabled = true | .control.peer.expires_at = 2000000000' \
                "${MIGRATION_SPEC}" >"${root}/mutation.json" ;;
        esac
        if [[ -f "${root}/mutation.json" ]]; then
            mv -- "${root}/mutation.json" "${MIGRATION_SPEC}"
            chmod 0600 "${MIGRATION_SPEC}"
        fi
        runMigration "${PADM_DOCKER_RC_CONFLICT}"
        [[ ! -s "${CALLS}" ]]
        diff -qr -- "${root}/expected" "${root}/secrets/net/wireguard"
        assertRoleKept
    done
done

printf 'docker-wireguard-migration-regression-ok: %s checks\n' "${checks}"
