#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-port-hopping-start.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-port-hopping-start-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" DOCKER_HOST=unix:///var/run/docker.sock
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

for function in dockerGenerateSingBoxConfig dockerTrafficRender dockerTrafficReadState \
    dockerTrafficWriteState dockerTrafficSnapshot dockerPortHoppingTargetProjectCheck \
    dockerPortHoppingTargetStartManaged dockerPortHoppingTargetBindingCheck dockerRemoveManagedTree; do
    eval "$(declare -f "${function}" | sed "1s/${function}/${function}Original/")"
done
fail() { printf 'docker-port-hopping-start-fail: %s\n' "$*" >&2; exit 1; }
root=${PADM_DOCKER_INSTALL_DIR}
SELF=11111111-1111-4111-8111-111111111111
ALICE=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
ID=$(printf a%.0s {1..64})
NEXT_ID=$(printf d%.0s {1..64})
IMAGE_ID=sha256:$(printf c%.0s {1..64})
IPV4=198.18.1.1
IPV6=2001:db8:1::1
STARTED=2026-10-13T01:00:00.000000000Z
mkdir -p "${root}/config/sing-box" "${root}/data/sing-box" \
    "${root}/data/traffic" "${root}/secrets/tls" "${TEST_ROOT}/bundle"
printf 'start-test\n' >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
record() { printf '%s\n' "$*" >>"${TEST_ROOT}/events"; }
eventCount() { grep -c "^$1\\($\\| \\)" "${TEST_ROOT}/events" || true; }
jq() {
    local argument
    if [[ -n "${SCENARIO:-}" ]]; then
        for argument in "$@"; do
            [[ "${argument}" != *Alice.SecretPass* && "${argument}" != *Alice.NewSecretPass* ]] ||
                { record secret-argv; return 99; }
        done
    fi
    command jq "$@"
}
jq --arg alice "${ALICE}" '
  .schema_version = 3 | .core = {type:"sing-box",secondary_type:null,protocols:[
    (.core.protocols[0] | del(.reality) | .id = 3 | .core = "sing-box" |
      .listener_id = "entry-hy2" | .public_port = 27443 | .name = "Hysteria2" |
      .hy2 = {domain:"proxy.example.com",bandwidth_mode:"bbr",up_mbps:100,
        down_mbps:50,obfs:null,masquerade:""})]} |
  .tls = {domain:"proxy.example.com"} | .subscription.enabled = false |
  .accounts = [{id:$alice,name:"Alice",enabled:true,
    uuid:"44444444-4444-4444-8444-444444444444",password:"Alice.SecretPass",
    shadowsocks_password:null,listeners:["entry-hy2"]}]
' "${PROJECT_ROOT}/docker/configure.example.json" >"${root}/config/spec.json"
dockerConfigureSpecValidate "${root}/config/spec.json"
printf 'fixture certificate\n' >"${root}/secrets/tls/proxy.example.com.crt"
printf 'fixture private key\n' >"${root}/secrets/tls/proxy.example.com.key"
jq -n --arg self "${SELF}" --arg alice "${ALICE}" --arg generation "${ID}:${STARTED}" '
  {schema_version:1,accounts:{
    ($self):{name:"self",upload:0,download:0,limit_bytes:0,baseline:{
      "sing-box":{upload:{generation:$generation,value:0}}}},
    ($alice):{name:"Alice",upload:4,download:0,limit_bytes:5,baseline:{
      "sing-box":{upload:{generation:$generation,value:0}}}}}}
' >"${root}/data/traffic/state.json"
dockerGenerateSingBoxConfigOriginal "${root}/config/spec.json" "${root}/config/sing-box/users.base"
dockerTrafficRenderOriginal sing-box "${root}/config/sing-box/users.base" "$(dockerTrafficReadStateOriginal)" \
    >"${root}/config/sing-box/config.json"
dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
: >"${root}/images.env"
dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"

# 保留真实累计和渲染，故障只注入采集、发布与文件切换边界。
dockerGenerateSingBoxConfig() {
    record generate "$@"
    dockerGenerateSingBoxConfigOriginal "$@"
}
dockerTrafficRender() {
    record render "$1" "$2"
    [[ "${SCENARIO:-}" != render-fail || "$(eventCount render)" -lt 2 ]] || return 1
    dockerTrafficRenderOriginal "$@"
}
dockerTrafficReadState() {
    record read-state
    [[ "${SCENARIO:-}" != read-fail || "$(eventCount read-state)" -lt 3 ]] || return 1
    dockerTrafficReadStateOriginal "$@"
}
dockerTrafficWriteState() {
    record write-state
    dockerTrafficWriteStateOriginal "$@" || return $?
    record state-committed
    inject state-committed
}
dockerTrafficSnapshot() {
    dockerTrafficSnapshotOriginal "$@" || return $?
    [[ "${SCENARIO}" != snapshot-return-fail ]] || return 1
}
dockerPortHoppingTargetProjectCheck() {
    dockerPortHoppingTargetProjectCheckOriginal "$@" || return $?
    record project-checked
    [[ "${ph_verified:-false}" != true ]] || inject project-checked
}
dockerPortHoppingTargetStartManaged() {
    local status=0
    record start-managed
    dockerPortHoppingTargetStartManagedOriginal "$@" || status=$?
    [[ "${status}" != 0 ]] || inject prepared-started
    return "${status}"
}
dockerPortHoppingTargetBindingCheck() {
    record binding-check
    inject binding-check
    dockerPortHoppingTargetBindingCheckOriginal "$@"
}
dockerRemoveManagedTree() {
    if [[ "$2" == "${root}"/.hopping-start.* ]]; then
        record startup-cleanup
        inject startup-cleanup
        [[ "${ph_signal:-0}" == 0 ]] || return 1
    fi
    dockerRemoveManagedTreeOriginal "$@" || return $?
    if [[ "$2" == "${root}"/.hopping-start.* ]]; then inject startup-cleaned; fi
    if [[ "$2" == "${root}"/.hopping-prepare.* ]]; then inject prepare-cleaned; fi
}
dockerTrafficContainerState() {
    record container-state "$@"
    local started=${STARTED}
    if [[ "${SCENARIO}" == container-drift && "$(eventCount container-state)" -gt 1 ]]; then
        started=2026-10-13T01:00:01.000000000Z
    fi
    jq -cn --arg id "${ID}" --arg started "${started}" \
        '{id:$id,started_at:$started,pid:100}'
}
dockerTrafficQuery() {
    record query "$@"
    [[ "${SCENARIO}" != query-fail ]] || return 1
    jq -cn --arg self "${SELF}" --arg alice "${ALICE}" \
        --argjson self_value "${SELF_VALUE:-0}" --argjson alice_value "${ALICE_VALUE:-0}" '
      {stat:[
        {name:("user>>>"+$self+">>>traffic>>>uplink"),value:$self_value},
        {name:("user>>>"+$alice+">>>traffic>>>uplink"),value:$alice_value}]}
    '
}

inject() {
    local point=$1
    [[ ! -e "${TEST_ROOT}/injected" ]] || return 0
    [[ "${SCENARIO}:${point}" != bound-middle-*:binding-inspected ||
        "$(eventCount binding-check)" -gt 0 ]] || return 0
    case "${SCENARIO}:${point}" in
    lock-race:state-committed)
        cp -a -- "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" "${TEST_ROOT}/pid.replacement"
        mv -f -- "${TEST_ROOT}/pid.replacement" "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid"
        ;;
    spec-race:state-committed)
        printf '\n ' >>"${root}/config/spec.json"
        cp -a -- "${root}/config/spec.json" "${TEST_ROOT}/foreign-input"
        ;;
    tls-race:state-committed)
        printf 'foreign certificate\n' >"${root}/secrets/tls/proxy.example.com.crt"
        cp -a -- "${root}/secrets/tls/proxy.example.com.crt" "${TEST_ROOT}/foreign-input"
        ;;
    live-race:state-committed)
        printf '{}\n' >"${root}/config/sing-box/config.json"
        cp -a -- "${root}/config/sing-box/config.json" "${TEST_ROOT}/foreign-input"
        ;;
    state-race:validation)
        jq --arg alice "${ALICE}" '.accounts[$alice].upload += 1' \
            "${root}/data/traffic/state.json" >"${TEST_ROOT}/state.foreign"
        cp -- "${TEST_ROOT}/state.foreign" "${root}/data/traffic/state.json"
        ;;
    candidate-race:validation)
        printf '{}\n' >"${stage}/config.safe.expected"
        cp -a -- "${stage}/config.safe.expected" "${TEST_ROOT}/foreign-input"
        ;;
    live-post-install:renamed)
        printf '{}\n' >"${root}/config/sing-box/config.json"
        cp -a -- "${root}/config/sing-box/config.json" "${TEST_ROOT}/foreign-input"
        ;;
    prepare-*-race:prepared-started)
        case "${SCENARIO}" in
        prepare-lock-race)
            cp -a -- "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" "${TEST_ROOT}/pid.replacement"
            mv -f -- "${TEST_ROOT}/pid.replacement" "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid"
            ;;
        prepare-live-race) printf '{}\n' >"${root}/config/sing-box/config.json" ;;
        prepare-spec-race) printf '\n ' >>"${root}/config/spec.json" ;;
        prepare-baseline-race) printf '\n ' >>"${root}/config/sing-box/users.base" ;;
        prepare-compose-race) printf '\n ' >>"${root}/compose.json" ;;
        prepare-deployment-race) printf '\n ' >>"${root}/deployment.json" ;;
        prepare-images-race) printf '\n ' >>"${root}/images.env" ;;
        prepare-tls-race) printf 'foreign certificate\n' >"${root}/secrets/tls/proxy.example.com.crt" ;;
        prepare-permissions-race) chmod 0777 "${root}/data/traffic" ;;
        esac
        ;;
    prepare-state-update:prepared-started)
        jq --arg alice "${ALICE}" '.accounts[$alice].upload += 1' \
            "${root}/data/traffic/state.json" >"${TEST_ROOT}/state.foreign"
        cp -- "${TEST_ROOT}/state.foreign" "${root}/data/traffic/state.json"
        ;;
    bound-before-*:binding-check|bound-middle-*:binding-inspected|\
    bound-after-*:startup-cleaned|bound-prepare-*:prepare-cleaned)
        case "${SCENARIO}" in
        *-state)
            # 同字节替换也不能被后置快照接受为实际启动采用的 state。
            cp -a -- "${root}/data/traffic/state.json" "${TEST_ROOT}/state.replacement"
            mv -f -- "${TEST_ROOT}/state.replacement" "${root}/data/traffic/state.json"
            ;;
        *-lock)
            cp -a -- "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" "${TEST_ROOT}/pid.replacement"
            mv -f -- "${TEST_ROOT}/pid.replacement" "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid"
            ;;
        *-live)
            cp -a -- "${root}/config/sing-box/config.json" "${TEST_ROOT}/live.replacement"
            mv -f -- "${TEST_ROOT}/live.replacement" "${root}/config/sing-box/config.json"
            ;;
        *-spec) printf '\n ' >>"${root}/config/spec.json" ;;
        *-permissions) chmod 0750 "${root}/data/traffic" ;;
        *-INT) kill -INT "${TX_OWNER}" ;;
        *-TERM) kill -TERM "${TX_OWNER}" ;;
        esac
        ;;
    prepare-signal-INT:prepared-started) kill -INT "${TX_OWNER}" ;;
    prepare-signal-TERM:prepared-started) kill -TERM "${TX_OWNER}" ;;
    signal-INT-${point}:${point}) kill -INT "${TX_OWNER}" ;;
    signal-TERM-${point}:${point}) kill -TERM "${TX_OWNER}" ;;
    *) return 0 ;;
    esac
    touch "${TEST_ROOT}/injected"
}

proof() {
    local identity=${1:-${ID}} started=${STARTED}
    [[ ! -s "${TEST_ROOT}/started" ]] || started=$(<"${TEST_ROOT}/started")
    jq -cn --arg id "${identity}" --arg image "${IMAGE_ID}" --arg started "${started}" \
        --arg ipv4 "${IPV4}" --arg ipv6 "${IPV6}" \
        --slurpfile live "${root}/config/sing-box/config.json" '
      ($live | if length == 1 then .[0] else error("live 配置必须是单个对象") end) as $live |
      {schema_version:1,listener_id:"entry-hy2",protocol_id:3,core:"sing-box",
       container_id:$id,image_id:$image,started_at:$started,restart_count:0,
       target_port:27443,ipv4:$ipv4,ipv6:$ipv6,
       enabled_accounts:([$live.inbounds[].users[]?] | length)}
    '
}

# 只读发布边界已有专用合同，此处用相同材料验证事务没有重算或回退旧账号。
dockerPortHoppingTargetInspect() {
    local mode=$1 stage=$5 state
    record inspect "${mode}"
    [[ "$#" == 5 && "$2" == entry-hy2 && "$3" == "${IPV4}" && "$4" == "${IPV6}" ]] ||
        return 1
    case "${mode}" in
    start-before)
        dockerGenerateSingBoxConfig "${root}/config/spec.json" "${stage}/users.base.expected" ||
            return 1
        cmp -s -- "${stage}/users.base.expected" "${root}/config/sing-box/users.base" || return 1
        state=$(dockerTrafficReadState) || return 1
        printf '%s\n' "${state}" >"${stage}/state.initial.json"
        dockerTrafficRender sing-box "${stage}/users.base.expected" "${state}" \
            >"${stage}/config.initial.expected" || return 1
        cmp -s -- "${stage}/config.initial.expected" "${root}/config/sing-box/config.json" ||
            return 1
        proof
        ;;
    start-after)
        [[ "${SCENARIO}" != after-fail && "${SCENARIO}" != recovery-fail ]] || return 1
        cmp -s -- "${stage}/config.safe.expected" "${root}/config/sing-box/config.json" ||
            return 1
        [[ -s "${TEST_ROOT}/active" ]] || return 1
        inject commit
        proof "$(<"${TEST_ROOT}/active")"
        ;;
    *) record unexpected-inspect "$@"; return 99 ;;
    esac
}

dockerComposeExecute() {
    local stage argument candidate= up_count
    record compose "$@"
    case "${1:-}" in
    run)
        for argument in "$@"; do
            [[ "${argument}" != *:/etc/padm/sing-box/config.json:ro ]] ||
                candidate=${argument%:/etc/padm/sing-box/config.json:ro}
        done
        [[ -f "${candidate}" ]] || { record unexpected-compose "$@"; return 99; }
        stage=${candidate%/*}
        jq -e '.inbounds[0].type == "hysteria2"' "${candidate}" >/dev/null || return 99
        cmp -s -- "${stage}/users.base.expected" "${root}/config/sing-box/users.base" ||
            return 99
        record validate
        inject validation
        [[ "${SCENARIO}" != validate-fail && "${SCENARIO}" != stop-health-tick ]] || return 1
        printf 'validation-noise\n'
        ;;
    up|restart)
        if [[ "$1" == restart ]]; then
            [[ "$#" == 1 ]] || { record unexpected-compose "$@"; return 99; }
        else
            [[ "$*" == "up -d --force-recreate --no-deps --wait --wait-timeout 60 sing-box" ]] ||
                { record unexpected-compose "$@"; return 99; }
        fi
        record "$1"
        up_count=$(eventCount up)
        jq -c '[.inbounds[].users[]?.name]' "${root}/config/sing-box/config.json" \
            >>"${TEST_ROOT}/started-users"
        if [[ "$1" == restart ]]; then
            [[ "${SCENARIO}" != restart-fail ]] || return 1
            printf '%s\n' "${ID}" >"${TEST_ROOT}/active"
        else
            # 真实 Compose 可能已删旧容器再失败，恢复不得只对旧 CID restart。
            rm -f -- "${TEST_ROOT}/active"
            rm -f -- "${TEST_ROOT}/stopped"
            if [[ "${SCENARIO}" == recovery-fail && "${up_count}" -gt 1 ]]; then
                printf '%s\n' "${NEXT_ID}" >"${TEST_ROOT}/active"
            fi
            inject compose
            [[ "${SCENARIO}" != compose-fail && "${SCENARIO}" != recovery-fail ||
                "${up_count}" -gt 1 ]] || return 1
            [[ "${SCENARIO}" != recovery-fail ]] || return 1
            if [[ "${SCENARIO}" == up-no-recreate && "${up_count}" == 1 ]]; then
                printf '%s\n' "${ID}" >"${TEST_ROOT}/active"
            else printf '%s\n' "${NEXT_ID}" >"${TEST_ROOT}/active"; fi
        fi
        python3 - "${root}" >"${TEST_ROOT}/started" <<'PY'
import datetime
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = [root / "config/sing-box/config.json", *sorted((root / "secrets/tls").iterdir())]
cutoff = max(max(path.stat().st_mtime_ns, path.stat().st_ctime_ns) for path in files) + 1
seconds, nanos = divmod(cutoff, 1_000_000_000)
print(datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S") +
      f".{nanos:09d}Z")
PY
        if [[ "${SCENARIO}" == restart-no-change ||
            ( "${SCENARIO}" == up-no-recreate && "${up_count}" == 1 ) ]]; then
            printf '%s\n' "${STARTED}" >"${TEST_ROOT}/started"
        fi
        printf 'compose-noise\n'
        ;;
    *) record unexpected-compose "$@"; return 99 ;;
    esac
}

# 仅替换调度动作；安全渲染、累计与启动后绑定继续走真实事务。
dockerLifecycleRestart() { dockerComposeExecute restart; }

timeout() {
    if [[ "${1:-}" == -k && "${2:-}" == 2 && "${3:-}" == 5 && "${4:-}" == docker ]]; then
        shift 4
        docker "$@"
    else
        command timeout "$@"
    fi
}

mv() {
    local last=${!#}
    command mv "$@" || return $?
    if [[ "${last}" == "${root}/config/sing-box/config.json" ]]; then
        record live-renamed
        inject renamed
    fi
}

cp() {
    local last=${!#}
    command cp "$@" || return $?
    if [[ "${last}" == "${root}"/.hopping-start.*/config.next ]]; then
        record candidate-copied
        inject copied
    fi
}

docker() {
    local identity requested running=true service=sing-box rows='[]' started=${STARTED}
    record docker "$@"
    case "${1:-}" in
    ps)
        [[ "$*" == *label=com.docker.compose.project=padm-docker* ]] ||
            { record unexpected-docker "$@"; return 99; }
        [[ ! -s "${TEST_ROOT}/active" ]] || cat -- "${TEST_ROOT}/active"
        [[ "${SCENARIO}" != orphan ]] || printf '%s\n' "${NEXT_ID}"
        ;;
    container|inspect)
        if [[ "${1}" == container ]]; then
            [[ "${2:-}" == inspect ]] || { record unexpected-docker "$@"; return 99; }
            shift 2
        else shift; fi
        if [[ -s "${TEST_ROOT}/active" ]]; then identity=$(<"${TEST_ROOT}/active")
        elif [[ -s "${TEST_ROOT}/stopped" ]]; then
            identity=$(<"${TEST_ROOT}/stopped")
            running=false
        else return 1; fi
        [[ ! -s "${TEST_ROOT}/started" ]] || started=$(<"${TEST_ROOT}/started")
        for requested in "$@"; do
            [[ "${requested}" =~ ^[a-f0-9]{12,64}$ ]] ||
                { record unexpected-docker inspect "${requested}"; return 99; }
            service=sing-box
            if [[ "${SCENARIO}" == orphan && "${NEXT_ID}" == "${requested}"* ]]; then
                service=rogue
            else [[ "${identity}" == "${requested}"* ]] || return 1; fi
            rows=$(jq -cn --arg id "${requested}" --arg root "${root}" --arg image "${IMAGE_ID}" \
                --arg service "${service}" --arg started "${started}" --argjson running "${running}" \
                --argjson rows "${rows}" \
                --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
          $rows + [{Id:$id,Image:$image,RestartCount:0,
            State:{Running:$running,Status:(if $running then "running" else "exited" end),
              Restarting:false,Paused:false,Dead:false,Pid:(if $running then 100 else 0 end),
              StartedAt:$started,Health:{Status:"healthy"}},
            Config:{Image:$spec[0].images["sing-box"],
              Labels:($compose[0].services["sing-box"].labels + {
                "com.docker.compose.project":"padm-docker",
                "com.docker.compose.project.working_dir":$root,
                "com.docker.compose.project.config_files":($root+"/compose.json"),
                "com.docker.compose.service":$service,"com.docker.compose.oneoff":"False"})}}]
        ') || return 1
        done
        if [[ "${SCENARIO}" == stop-health-tick ]]; then
            rows=$(jq -c --argjson tick "$(eventCount docker)" '
              .[].State.Health += {Log:[{tick:$tick}]}
            ' <<<"${rows}") || return 1
        fi
        if [[ -e "${TEST_ROOT}/injected" ]]; then
            case "${SCENARIO}" in
            prepare-cid-race|bound-*-cid) rows=$(jq --arg id "${ID}" '.[0].Id = $id' <<<"${rows}") ;;
            prepare-started-race) rows=$(jq --arg started "${STARTED}" '.[0].State.StartedAt = $started' <<<"${rows}") ;;
            prepare-image-race) rows=$(jq '.[0].Image = ("sha256:" + ("e" * 64))' <<<"${rows}") ;;
            prepare-health-race|bound-*-health) rows=$(jq '.[0].State.Health.Status = "unhealthy"' <<<"${rows}") ;;
            esac
        fi
        printf '%s\n' "${rows}"
        inject binding-inspected
        ;;
    stop)
        [[ "$*" == "stop -t 10 ${ID}" || "$*" == "stop -t 10 ${NEXT_ID}" ]] || return 99
        record stop "${@: -1}"
        [[ -s "${TEST_ROOT}/active" ]] || return 1
        cp -- "${TEST_ROOT}/active" "${TEST_ROOT}/stopped"
        rm -f -- "${TEST_ROOT}/active"
        ;;
    *) record unexpected-docker "$@"; return 99 ;;
    esac
}

runCase() {
    local scenario=$1 expected=$2 up_count=$3 stop_count=$4 alice_value=${5:-1} status=0
    local operation=${6:-start} range_start=${7:-30000} range_end=${8:-30001}
    local isPrepare=false isBound=false ph_restart=false expected_id=${NEXT_ID}
    local -a extra=()
    case "${operation}" in
    prepare) isPrepare=true ;;
    bound-start) isBound=true; extra=(bound) ;;
    bound-restart) isBound=true; ph_restart=true; expected_id=${ID}; extra=(bound) ;;
    bound-prepare) isPrepare=true; isBound=true; extra=(bound) ;;
    invalid-start) extra=(invalid) ;;
    invalid-prepare) isPrepare=true; extra=(bound extra) ;;
    esac
    (
        SCENARIO=${scenario}
        ALICE_VALUE=${alice_value}
        SELF_VALUE=0
        TX_OWNER=${BASHPID}
        rm -rf -- "${root}"
        cp -a -- "${TEST_ROOT}/baseline" "${root}"
        : >"${TEST_ROOT}/events"
        : >"${TEST_ROOT}/started-users"
        rm -f -- "${TEST_ROOT}/injected" "${TEST_ROOT}/foreign-input" "${TEST_ROOT}/stopped" \
            "${TEST_ROOT}/started"
        printf '%s\n' "${ID}" >"${TEST_ROOT}/active"
        if [[ "${SCENARIO}" == all-quota ]]; then
            jq --arg self "${SELF}" '.accounts[$self].limit_bytes = 1' \
                "${root}/data/traffic/state.json" >"${TEST_ROOT}/all-quota.json"
            cp -- "${TEST_ROOT}/all-quota.json" "${root}/data/traffic/state.json"
            SELF_VALUE=1
        fi
        dockerAcquireDeploymentLock || fail "${SCENARIO}: 未取得夹具部署锁"
        listener=entry-hy2
        ipv4=${IPV4}
        ipv6=${IPV6}
        case "${SCENARIO}" in
        prepare-invalid-listener) listener=foreign-hy2 ;;
        prepare-invalid-ipv4) ipv4=198.018.1.1 ;;
        prepare-invalid-ipv6) ipv6= ;;
        prepare-invalid-family)
            jq '.core.protocols[0].address_families = ["ipv4"]' "${root}/config/spec.json" \
                >"${TEST_ROOT}/single-family.json"
            cp -- "${TEST_ROOT}/single-family.json" "${root}/config/spec.json"
            ;;
        esac
        trap 'record original-INT' INT
        trap 'record original-TERM' TERM
        traps_before=$(trap -p INT TERM)
        status=0
        if [[ "${isPrepare}" == true ]]; then
            dockerPortHoppingTargetPrepareActivation "${listener}" "${range_start}" "${range_end}" \
                "${ipv4}" "${ipv6}" "${extra[@]}" >"${TEST_ROOT}/result.json" \
                2>"${TEST_ROOT}/error.log" || status=$?
        else
            dockerPortHoppingTargetStartManaged entry-hy2 "${IPV4}" "${IPV6}" "${extra[@]}" \
                >"${TEST_ROOT}/result.json" 2>"${TEST_ROOT}/error.log" || status=$?
        fi
        [[ "${status}" == "${expected}" || ( "${expected}" == reject && "${status}" != 0 ) ]] ||
            fail "${SCENARIO}: 状态 ${status}，预期 ${expected}: $(cat "${TEST_ROOT}/error.log")"
        [[ "$(eventCount up)" == "${up_count}" ]] ||
            fail "${SCENARIO}: 重建次数 $(eventCount up)，预期 ${up_count}"
        [[ "$(eventCount stop)" == "${stop_count}" ]] ||
            fail "${SCENARIO}: 停止次数 $(eventCount stop)，预期 ${stop_count}"
        [[ "${ph_restart}" != true || "$(eventCount restart)" == 1 ]] ||
            fail "${SCENARIO}: 重启没有恰好执行一次"
        [[ "$(eventCount unexpected-inspect)" == 0 && "$(eventCount unexpected-compose)" == 0 &&
            "$(eventCount unexpected-docker)" == 0 && "$(eventCount secret-argv)" == 0 ]] ||
            fail "${SCENARIO}: 存在未知系统动作或认证 argv 泄漏"
        [[ "$(trap -p INT TERM)" == "${traps_before}" ]] ||
            fail "${SCENARIO}: 启动事务没有恢复调用方 INT/TERM trap"
        if [[ "${expected}" == 0 ]]; then
            jq -e --arg id "${expected_id}" --argjson prepare "${isPrepare}" --argjson bound "${isBound}" \
                --argjson count "$((2 - alice_value))" \
                --argjson start "${range_start}" --argjson end "${range_end}" '
              keys == (["schema_version","listener_id","protocol_id","core","container_id","image_id",
                "started_at","restart_count","target_port","ipv4","ipv6","enabled_accounts"] +
                (if $prepare then ["range_start","range_end"] else [] end) +
                (if $bound then ["startup_binding"] else [] end) | sort) and
              .container_id == $id and .enabled_accounts == $count and
              (if $prepare then .range_start == $start and .range_end == $end else true end)
            ' "${TEST_ROOT}/result.json" >/dev/null || fail "${SCENARIO}: 成功未返回唯一见证"
            if [[ "${ph_restart}" == true ]]; then
                jq -e --arg started "${STARTED}" '.started_at != $started' \
                    "${TEST_ROOT}/result.json" >/dev/null ||
                    fail "${SCENARIO}: 重启后启动代次没有更新"
            fi
            if [[ "${isBound}" == true ]]; then
                binding=$(jq -ec '.startup_binding' "${TEST_ROOT}/result.json")
                jq -e 'keys == ["files","live","lock","state"] and
                  (.state | length == 1 and .[0][0] == "data/traffic/state.json") and
                  (.live | length > 0 and all(.[]; .[0] == "config/sing-box/config.json"))' \
                    <<<"${binding}" >/dev/null || fail "${SCENARIO}: 启动绑定结构不完整"
                dockerPortHoppingTargetBindingCheck "$(<"${TEST_ROOT}/result.json")" \
                    "${binding}" proxy.example.com ||
                    fail "${SCENARIO}: 返回绑定与本轮真实文件或锁身份不符"
                [[ "$(<"${TEST_ROOT}/result.json")" != *SecretPass* &&
                    "$(<"${TEST_ROOT}/result.json")" != *"${ALICE}"* ]] ||
                    fail "${SCENARIO}: 版本诊断暴露账号或密码"
            fi
            [[ "$(eventCount generate)" == 1 && "$(eventCount render)" == 2 &&
                "$(eventCount read-state)" == 3 &&
                "$(eventCount query)" == 1 && "$(eventCount write-state)" == 1 &&
                "$(eventCount validate)" == 1 ]] || fail "${SCENARIO}: 事务重复生成、采集或渲染"
            [[ -z "$(find "${root}" -maxdepth 1 \( -name '.hopping-start.*' -o -name '.hopping-prepare.*' \) -print)" ]] ||
                fail "${SCENARIO}: 成功后仍保留临时 stage"
        else
            [[ ! -s "${TEST_ROOT}/result.json" ]] || fail "${SCENARIO}: 失败输出了见证或命令噪声"
            if [[ "${ph_restart}" == true ]]; then
                [[ -s "${TEST_ROOT}/stopped" && "$(<"${TEST_ROOT}/stopped")" == "${ID}" &&
                    ! -e "${TEST_ROOT}/active" &&
                    -n "$(find "${root}" -maxdepth 1 -name '.hopping-start.*' -type d -print)" ]] ||
                    fail "${SCENARIO}: 重启失败未停止原受管核心或保留证据"
            fi
        fi
        if [[ "${SCENARIO}" == query-fail || "${SCENARIO}" == container-drift ||
            "${SCENARIO}" == orphan || "${SCENARIO}" == prepare-invalid-* ||
            "${SCENARIO}" == start-invalid-mode ]]; then
            cmp -s -- "${root}/data/traffic/state.json" "${TEST_ROOT}/baseline/data/traffic/state.json" &&
                cmp -s -- "${root}/config/sing-box/config.json" \
                    "${TEST_ROOT}/baseline/config/sing-box/config.json" ||
                fail "${SCENARIO}: 未采集成功却改动累计或 live"
            [[ "$(eventCount state-committed)" == 0 ]] || fail "${SCENARIO}: 错误提交采集"
            if [[ "${SCENARIO}" == prepare-invalid-* || "${SCENARIO}" == start-invalid-mode ]]; then
                [[ ( "${isPrepare}" != true || "$(eventCount start-managed)" == 0 ) &&
                    "$(eventCount query)" == 0 &&
                    "$(eventCount write-state)" == 0 && "$(eventCount compose)" == 0 &&
                    -z "$(find "${root}" -maxdepth 1 -name '.hopping-*' -print)" ]] ||
                    fail "${SCENARIO}: 非法输入仍调用启动、采集或创建 stage"
            fi
        elif [[ "${SCENARIO}" == state-race ]]; then
            cmp -s -- "${TEST_ROOT}/state.foreign" "${root}/data/traffic/state.json" ||
                fail '失败覆盖了外来累计'
        else
            extra=0
            [[ "${SCENARIO}" != prepare-state-update ]] || extra=1
            jq -e --arg alice "${ALICE}" --argjson value "$((4 + alice_value + extra))" \
                '.accounts[$alice].upload == $value' "${root}/data/traffic/state.json" >/dev/null ||
                fail "${SCENARIO}: 已提交累计被回退或遗失"
        fi
        if [[ "${isPrepare}" == true && "${SCENARIO}" != prepare-invalid-* ]]; then
            [[ "$(eventCount start-managed)" == 1 ]] || fail "${SCENARIO}: 准备没有恰好调用一次启动"
        fi
        if [[ -s "${TEST_ROOT}/started-users" && "${ALICE_VALUE}" == 1 ]]; then
            jq -es --arg alice "${ALICE}" 'all(.[]; index($alice) == null)' \
                "${TEST_ROOT}/started-users" >/dev/null || fail "${SCENARIO}: 重建恢复重新启用了超额账号"
        fi
        if [[ "${SCENARIO}" == signal-*-copied ]]; then
            [[ "$(eventCount candidate-copied)" == 2 && "$(eventCount live-renamed)" == 1 ]] ||
                fail "${SCENARIO}: 收到复制节点信号后仍继续原流程 rename"
        fi
        [[ "${SCENARIO}" == prepare-baseline-race ]] || cmp -s -- "${root}/config/sing-box/users.base" \
            "${TEST_ROOT}/baseline/config/sing-box/users.base" ||
            fail "${SCENARIO}: 启动事务改变了账号基线"
        for file in deployment.json compose.json images.env secrets/tls/proxy.example.com.key; do
            [[ "${SCENARIO}:${file}" != prepare-deployment-race:deployment.json &&
                "${SCENARIO}:${file}" != prepare-compose-race:compose.json &&
                "${SCENARIO}:${file}" != prepare-images-race:images.env ]] || continue
            cmp -s -- "${root}/${file}" "${TEST_ROOT}/baseline/${file}" ||
                fail "${SCENARIO}: 启动事务改变了 ${file}"
        done
        case "${SCENARIO}" in
        lock-race|prepare-lock-race|bound-*-lock)
            [[ -z "${DOCKER_DEPLOYMENT_LOCK_DIR}" ]] || fail '锁变化后未阻止通用 Release'
            dockerReleaseDeploymentLock
            [[ -f "${root}/locks/deployment.lock/pid" ]] || fail '外来锁被 Release 删除'
            ;;
        spec-race)
            cmp -s -- "${TEST_ROOT}/foreign-input" "${root}/config/spec.json" ||
                fail '失败覆盖了外来 spec'
            ;;
        tls-race)
            cmp -s -- "${TEST_ROOT}/foreign-input" "${root}/secrets/tls/proxy.example.com.crt" ||
                fail '失败覆盖了外来 TLS'
            ;;
        live-race|live-post-install)
            cmp -s -- "${TEST_ROOT}/foreign-input" "${root}/config/sing-box/config.json" ||
                fail '失败覆盖了外来 live'
            ;;
        candidate-race)
            stage=$(find "${root}" -maxdepth 1 -name '.hopping-start.*' -type d -print)
            cmp -s -- "${TEST_ROOT}/foreign-input" "${stage}/config.safe.expected" ||
                fail '失败覆盖或清理了漂移候选'
            ;;
        recovery-fail)
            [[ -n "$(find "${root}" -maxdepth 1 -name '.hopping-start.*' -type d -print)" ]] ||
                fail '恢复失败清理了 stage 证据'
            ;;
        esac
        if [[ "${SCENARIO}" == stop-health-tick ]]; then
            [[ -s "${TEST_ROOT}/stopped" ]] || fail '健康日志 tick 阻止安全停止'
        fi
        if [[ "${SCENARIO}" == bound-before-* ]]; then
            [[ -n "$(find "${root}" -maxdepth 1 -name '.hopping-start.*' -type d -print)" ]] ||
                fail "${SCENARIO}: 绑定失败清理了尚存的启动证据"
        fi
        if [[ "${isPrepare}" == true && "${expected}" != 0 && "${SCENARIO}" != prepare-invalid-* &&
            "${SCENARIO}" != bound-prepare-* ]]; then
            [[ -n "$(find "${root}" -maxdepth 1 -name '.hopping-prepare.*' -type d -print)" ]] ||
                fail "${SCENARIO}: 失败没有保留准备证据"
        fi
        [[ "${SCENARIO}" == lock-race || "${SCENARIO}" == prepare-lock-race ||
            "${SCENARIO}" == bound-*-lock ]] || dockerReleaseDeploymentLock
    ) || status=$?
    [[ "${status}" == 0 ]] || fail "场景失败: ${scenario}"
    cases=$((cases + 1))
}

cp -a -- "${root}" "${TEST_ROOT}/baseline"

# 同进程核验须区分锁漂移与文件失败，不能让子进程吞掉父 Bash 的清锁动作。
for failure in missing-tls replaced-lock invalid-lock; do
    (
        SCENARIO="snapshot-${failure}"
        rm -rf -- "${root}"
        cp -a -- "${TEST_ROOT}/baseline" "${root}"
        : >"${TEST_ROOT}/events"
        dockerAcquireDeploymentLock || fail "${failure}: 未取得夹具锁"
        ph_owner=${BASHPID}
        ph_root=${root}
        ph_domain=proxy.example.com
        ph_stage="${root}/snapshot-evidence"
        ph_verified=false
        ph_installed=false
        ph_stateFile=
        ph_lock=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") ||
            fail "${failure}: 单独锁快照失败"
        files=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "") ||
            fail "${failure}: 单独文件快照失败"
        output=$(dockerPortHoppingTargetSnapshot start "${ph_owner}" "${ph_domain}" "" "${ph_lock}") ||
            fail "${failure}: 合并快照失败"
        [[ "${output}" == "${ph_lock}"$'\n'"${files}" ]] ||
            fail "${failure}: 合并快照改变原输出"
        case "${failure}" in
        missing-tls) rm -- "${root}/secrets/tls/proxy.example.com.crt" ;;
        replaced-lock)
            cp -a -- "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" "${TEST_ROOT}/snapshot-pid"
            mv -f -- "${TEST_ROOT}/snapshot-pid" "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid"
            ;;
        invalid-lock) chmod 0600 "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" ;;
        esac
        status=0
        output=$(dockerPortHoppingTargetSnapshot start "${ph_owner}" "${ph_domain}" "" "${ph_lock}" \
            2>"${TEST_ROOT}/snapshot-error") || status=$?
        [[ "${status}" != 0 ]] || fail "${failure}: 合并快照接受失败边界"
        case "${failure}" in
        missing-tls)
            [[ "${output}" == "${ph_lock}" ]] || fail '文件失败没有保留唯一锁行'
            ;;
        replaced-lock)
            [[ -n "${output}" && "${output}" != *$'\n'* && "${output}" != "${ph_lock}" ]] ||
                fail '锁替换未在读取文件前拒绝'
            ;;
        invalid-lock) [[ -z "${output}" ]] || fail '无效锁仍输出快照' ;;
        esac
        if dockerPortHoppingTargetStartFilesCheck >"${TEST_ROOT}/snapshot-check" \
            2>"${TEST_ROOT}/snapshot-error"; then
            fail "${failure}: StartFilesCheck 接受失败边界"
        fi
        if [[ "${failure}" == missing-tls ]]; then
            [[ "${DOCKER_DEPLOYMENT_LOCK_DIR}" == "${root}/locks/deployment.lock" ]] ||
                fail '文件失败错误清除了锁标记'
            dockerReleaseDeploymentLock
        else
            [[ -z "${DOCKER_DEPLOYMENT_LOCK_DIR}" ]] || fail '锁失败没有清除父 Bash 锁标记'
            dockerReleaseDeploymentLock
            [[ -f "${root}/locks/deployment.lock/pid" ]] || fail '锁失败误删了现场'
        fi
    )
done
printf 'docker-port-hopping-snapshot-ok: 3 failure boundaries\n'
cases=0
runCase normal 0 1 0 0
runCase quota 0 1 0
runCase query-fail reject 0 0
runCase container-drift reject 0 0
runCase snapshot-return-fail reject 0 1
runCase orphan reject 0 0
runCase read-fail reject 0 1
runCase render-fail reject 0 1
runCase validate-fail reject 0 1
runCase stop-health-tick reject 0 1
runCase all-quota reject 0 1
runCase lock-race reject 0 0
runCase spec-race reject 0 1
runCase tls-race reject 0 1
runCase live-race reject 0 1
runCase state-race reject 0 1
runCase candidate-race reject 0 1
runCase live-post-install reject 0 1
runCase compose-fail reject 2 0
runCase up-no-recreate reject 2 0
runCase recovery-fail reject 2 1
runCase after-fail reject 2 1
for signal in INT TERM; do
    expected=130
    [[ "${signal}" != TERM ]] || expected=143
    runCase "signal-${signal}-state-committed" "${expected}" 0 1
    runCase "signal-${signal}-validation" "${expected}" 1 0
    runCase "signal-${signal}-copied" "${expected}" 1 0
    runCase "signal-${signal}-project-checked" "${expected}" 1 0
    runCase "signal-${signal}-renamed" "${expected}" 1 0
    runCase "signal-${signal}-compose" "${expected}" 2 0
    runCase "signal-${signal}-commit" "${expected}" 2 0
    runCase "signal-${signal}-startup-cleanup" "${expected}" 1 0
done
printf 'docker-port-hopping-start-ok: %s transaction cases\n' "${cases}"

# 准备层复用启动事务；非法输入必须在采集前拒绝，后验不重算材料。
cases=0
runCase prepare-normal 0 1 0 0 prepare
runCase prepare-quota 0 1 0 1 prepare
runCase prepare-state-update 0 1 0 1 prepare
runCase prepare-single-port 0 1 0 0 prepare 65535 65535
for range in '0 30001' '030000 30001' '30000 +30001' '30001 30000' \
    '30000 65536' '1 27443' '27443 30000' '27443 27443' '1 65535'; do
    read -r start end <<<"${range}"
    runCase prepare-invalid-range reject 0 0 1 prepare "${start}" "${end}"
done
for kind in listener ipv4 ipv6 family; do
    runCase "prepare-invalid-${kind}" reject 0 0 1 prepare
done
for kind in lock spec baseline compose deployment images tls live cid started image health permissions; do
    runCase "prepare-${kind}-race" reject 1 0 1 prepare
done
runCase prepare-signal-INT 130 1 0 1 prepare
runCase prepare-signal-TERM 143 1 0 1 prepare
runCase query-fail reject 0 0 1 prepare
runCase compose-fail reject 2 0 1 prepare
runCase signal-INT-validation 130 1 0 1 prepare
runCase signal-TERM-commit 143 2 0 1 prepare
runCase signal-INT-startup-cleanup 130 1 0 1 prepare
runCase signal-TERM-startup-cleanup 143 1 0 1 prepare
printf 'docker-port-hopping-prepare-ok: %s preparation cases\n' "${cases}"

# 绑定必须对应实际启动版本；成功清理之后的漂移只拒绝诊断，不再次重建。
cases=0
runCase bound-normal 0 1 0 0 bound-start
runCase bound-quota 0 1 0 1 bound-start
runCase bound-normal 0 1 0 0 bound-prepare
runCase bound-quota 0 1 0 1 bound-prepare
runCase start-invalid-mode reject 0 0 1 invalid-start
runCase prepare-invalid-mode reject 0 0 1 invalid-prepare
runCase prepare-state-update reject 1 0 1 bound-prepare
for phase in before middle after prepare; do
    operation=bound-start
    [[ "${phase}" != prepare ]] || operation=bound-prepare
    case "${phase}" in
    before) kinds=(state live lock cid health) ;;
    middle) kinds=(state lock) ;;
    after) kinds=(state spec permissions lock) ;;
    prepare) kinds=(state live lock) ;;
    esac
    for kind in "${kinds[@]}"; do
        runCase "bound-${phase}-${kind}" reject 1 0 1 "${operation}"
    done
    [[ "${phase}" != middle ]] || continue
    runCase "bound-${phase}-INT" 130 1 0 1 "${operation}"
    runCase "bound-${phase}-TERM" 143 1 0 1 "${operation}"
done
printf 'docker-port-hopping-bound-ok: %s startup binding cases\n' "${cases}"

# 重启只执行一次；失败保留累计和证据，不能借恢复再次启动核心。
cases=0
runCase restart-quota 0 0 0 1 bound-restart
runCase restart-fail reject 0 1 1 bound-restart
runCase restart-no-change reject 0 1 1 bound-restart
printf 'docker-port-hopping-restart-ok: %s restart transaction cases\n' "${cases}"
