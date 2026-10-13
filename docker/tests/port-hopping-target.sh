#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-port-hopping-target.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-port-hopping-target-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" DOCKER_HOST=unix:///var/run/docker.sock
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-port-hopping-target-fail: %s\n' "$*" >&2; exit 1; }
# 见证读取完整账号，但不能把密码传入外部程序的 argv。
jq() {
    local argument
    if [[ "${GUARD_SECRET_ARGV:-0}" == 1 ]]; then
        for argument in "$@"; do
            [[ "${argument}" != *Alice.SecretPass* && "${argument}" != *Alice.NewSecretPass* && "${argument}" != *"${SELF}"* &&
                "${argument}" != *"${ALICE}"* ]] || {
                printf '目标见证泄漏密码到外部参数\n' >&2
                return 99
            }
        done
    fi
    # 首次入口投影返回后完整切到单族，验证快照开始后的作用域复查。
    if [[ "${MODE:-ok}" == scope-race && ! -e "${TEST_ROOT}/scope-changed" &&
        "$*" == *'目标见证仅支持受管双族 Hy2 bridge 入口'* ]]; then
        command jq "$@" || return $?
        scopeRace
    else
        command jq "$@"
    fi
}

root=${PADM_DOCKER_INSTALL_DIR}
SELF=11111111-1111-4111-8111-111111111111
ALICE=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
ID=$(printf a%.0s {1..64})
NETWORK_ID=$(printf b%.0s {1..64})
IMAGE_ID=sha256:$(printf c%.0s {1..64})
IPV4=198.18.1.1
IPV6=2001:db8:1::1
mkdir -p "${root}/config/sing-box" "${root}/data/sing-box" "${root}/data/traffic" \
    "${root}/secrets/tls" "${TEST_ROOT}/bundle"
printf 'target-test\n' >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
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
printf '%s\n' '{"schema_version":1,"accounts":{}}' >"${root}/data/traffic/state.json"

generate() {
    dockerGenerateSingBoxConfig "${root}/config/spec.json" "${root}/config/sing-box/users.base"
    dockerTrafficRender sing-box "${root}/config/sing-box/users.base" "$(dockerTrafficReadState)" \
        >"${root}/config/sing-box/config.json"
    dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
    dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
    : >"${root}/images.env"
    dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
}
generate
cp -a -- "${root}" "${TEST_ROOT}/baseline"

# 发布夹具取自真实生成的 Compose；仅容器、镜像和主机地址属于系统边界。
jq -n --arg root "${root}" --arg id "${ID}" --arg network "${NETWORK_ID}" --arg image "${IMAGE_ID}" \
    --slurpfile spec "${root}/config/spec.json" --slurpfile compose "${root}/compose.json" '
  $compose[0].services["sing-box"] as $service |
  (reduce $service.ports[] as $port ({};
    ($port | capture("^(?<ip>0[.]0[.]0[.]0|\\[::\\]):(?<host>[0-9]+):(?<port>[0-9]+)/udp$")) as $binding |
    .[$binding.port + "/udp"] += [{HostIp:($binding.ip | gsub("\\[|\\]";"")),
      HostPort:$binding.host}])) as $bindings |
  [{Id:$id,Image:$image,RestartCount:0,
    State:{Status:"running",Running:true,Restarting:false,Paused:false,Dead:false,Pid:100,
      StartedAt:"2026-10-13T01:00:00.000000000Z",Health:{Status:"healthy"}},
    Config:{Image:$spec[0].images["sing-box"],Labels:($service.labels + {
      "com.docker.compose.project":"padm-docker",
      "com.docker.compose.project.working_dir":$root,
      "com.docker.compose.project.config_files":($root+"/compose.json"),
      "com.docker.compose.service":"sing-box","com.docker.compose.oneoff":"False"}),
      Entrypoint:["/usr/local/bin/sing-box"],
      Cmd:["run","-D","/var/lib/padm/sing-box","-c","/etc/padm/sing-box/config.json"],
      User:"10001:10001",Healthcheck:{Test:$service.healthcheck.test}},
    HostConfig:{NetworkMode:"padm-docker",ReadonlyRootfs:$service.read_only,Privileged:false,
      CapAdd:null,CapDrop:$service.cap_drop,SecurityOpt:$service.security_opt,
      LogConfig:{Type:$service.logging.driver,Config:$service.logging.options},
      Init:$service.init,PidsLimit:$service.pids_limit,PublishAllPorts:false,
      RestartPolicy:{Name:$service.restart,MaximumRetryCount:0},
      Tmpfs:{"/tmp":"rw,noexec,nosuid,nodev,size=16m"},PortBindings:$bindings,
      Devices:[],DeviceRequests:null,Binds:[$service.volumes[] |
        (.source | sub("^\\$\\{PADM_DOCKER_ROOT\\}";$root)) + ":" + .target +
          (if .read_only then ":ro" else ":rw" end)]},
    NetworkSettings:{Ports:$bindings,Networks:{"padm-docker":{
      NetworkID:$network,IPAddress:"172.30.0.2",Gateway:"172.30.0.1",
      GlobalIPv6Address:"",IPv6Gateway:""}}},
    Mounts:[$service.volumes[] | {Type:"bind",
      Source:(.source | sub("^\\$\\{PADM_DOCKER_ROOT\\}";$root)),
      Destination:.target,RW:(.read_only|not)}]}]
' >"${TEST_ROOT}/inspect.json"
jq -n --arg id "${IMAGE_ID}" --slurpfile spec "${root}/config/spec.json" '
  [{Id:$id,RepoDigests:[($spec[0].images["sing-box"] | sub(":[^/:]+@";"@"))],
    Config:{Entrypoint:["/usr/local/bin/sing-box"],
      Cmd:["run","-D","/var/lib/padm/sing-box","-c","/etc/padm/sing-box/config.json"],
      User:"10001:10001"}}]
' >"${TEST_ROOT}/image.json"
jq -n --arg id "${NETWORK_ID}" --slurpfile compose "${root}/compose.json" '
  [{Id:$id,Name:$compose[0].networks.default.name,Driver:"bridge",Scope:"local",
    Labels:$compose[0].networks.default.labels,EnableIPv6:false,Internal:false,
    Attachable:false,Ingress:false}]
' >"${TEST_ROOT}/network.json"
printf '[{"ifindex":1,"ifname":"eth0","addr_info":[{"family":"inet","local":"%s","prefixlen":24},{"family":"inet6","local":"%s","prefixlen":64}]}]\n' \
    "${IPV4}" "${IPV6}" >"${TEST_ROOT}/ip.json"

treeSnapshot() {
    python3 - "${root}" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import stat
import sys

root = Path(sys.argv[1])
rows = []
for path in [root, *sorted(root.rglob("*"))]:
    metadata = path.lstat()
    row = [str(path.relative_to(root)), metadata.st_dev, metadata.st_ino,
           metadata.st_mode, metadata.st_uid, metadata.st_gid, metadata.st_nlink,
           metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns]
    if stat.S_ISLNK(metadata.st_mode):
        row.append(os.readlink(path))
    elif stat.S_ISREG(metadata.st_mode):
        row.append(hashlib.sha256(path.read_bytes()).hexdigest())
    rows.append(row)
print(json.dumps(rows, separators=(",", ":")))
PY
}

MODE=ok
INSPECT_FILTER=.
IMAGE_FILTER=.
NETWORK_FILTER=.
IP_FILTER=.
snapshotRace() {
    [[ "${MODE}" == replace-live && ! -e "${TEST_ROOT}/replaced" ]] || return 0
    cp -a -- "${root}/config/sing-box/config.json" "${TEST_ROOT}/config.replacement"
    mv -f -- "${TEST_ROOT}/config.replacement" "${root}/config/sing-box/config.json"
    touch "${TEST_ROOT}/replaced"
    treeSnapshot >"${TEST_ROOT}/expected-after-race.json"
}
scopeRace() {
    local GUARD_SECRET_ARGV=0
    touch "${TEST_ROOT}/scope-changed"
    cp -a -- "${TEST_ROOT}/inspect.json" "${TEST_ROOT}/inspect.before-scope.json"
    change config/spec.json '.core.protocols[0].address_families = ["ipv4"]'
    generate
    command jq '
      .[0].HostConfig.PortBindings |= with_entries(.value |= map(select(.HostIp == "0.0.0.0"))) |
      .[0].NetworkSettings.Ports = .[0].HostConfig.PortBindings
    ' "${TEST_ROOT}/inspect.json" >"${TEST_ROOT}/inspect.scope.json"
    mv -- "${TEST_ROOT}/inspect.scope.json" "${TEST_ROOT}/inspect.json"
    treeSnapshot >"${TEST_ROOT}/expected-after-race.json"
}
docker() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/commands.log"
    case "$*" in
    info) return 0 ;;
    'info --format {{.OSType}}') printf 'linux\n' ;;
    'info --format {{.Architecture}}') uname -m ;;
    'info --format {{json .SecurityOptions}}') printf '[]\n' ;;
    'context inspect --format {{.Endpoints.docker.Host}}') printf 'unix:///var/run/docker.sock\n' ;;
    'compose version --short') printf '2.39.0\n' ;;
    'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=sing-box --filter label=com.docker.compose.oneoff=False')
        [[ "${MODE}" != query-fail ]] || return 1
        printf '%s\n' "${ID:0:12}"
        [[ "${MODE}" != duplicate ]] || printf '%s\n' "$(printf d%.0s {1..12})"
        ;;
    "container inspect ${ID:0:12}")
        snapshotRace
        if [[ "${MODE}" == restart-drift && $(grep -c '^container inspect ' "${TEST_ROOT}/commands.log") -gt 1 ]]; then
            jq '.[0].RestartCount += 1' "${TEST_ROOT}/inspect.json"
        elif [[ "${MODE}" == health-tick && $(grep -c '^container inspect ' "${TEST_ROOT}/commands.log") -gt 1 ]]; then
            jq '.[0].State.Health += {FailingStreak:1,Log:[{Start:"later",End:"later",ExitCode:0,Output:"tick"}]}' \
                "${TEST_ROOT}/inspect.json"
        else
            jq "${INSPECT_FILTER}" "${TEST_ROOT}/inspect.json"
        fi
        ;;
    "image inspect $(jq -r '.images["sing-box"]' "${root}/config/spec.json")")
        jq "${IMAGE_FILTER}" "${TEST_ROOT}/image.json"
        ;;
    "network inspect ${NETWORK_ID}") jq "${NETWORK_FILTER}" "${TEST_ROOT}/network.json" ;;
    *)
        printf '%s\n' "$*" >>"${TEST_ROOT}/unexpected.log"
        return 99
        ;;
    esac
}
ip() {
    printf 'ip %s\n' "$*" >>"${TEST_ROOT}/commands.log"
    [[ "$*" == '-j address show' ]] || {
        printf 'ip %s\n' "$*" >>"${TEST_ROOT}/unexpected.log"; return 99;
    }
    jq "${IP_FILTER}" "${TEST_ROOT}/ip.json"
}

cases=0
WITNESS_FUNCTION=dockerPortHoppingTargetWitness
runWitness() {
    local expected=$1 count=${2:-2} listener=${3:-entry-hy2} ipv4=${4:-${IPV4}} ipv6=${5:-${IPV6}}
    local before status=0 expectedStart
    before=$(treeSnapshot)
    expectedStart=$(jq -r '.[0].State.StartedAt' "${TEST_ROOT}/inspect.json")
    : >"${TEST_ROOT}/commands.log"
    rm -f -- "${TEST_ROOT}/replaced" "${TEST_ROOT}/scope-changed" "${TEST_ROOT}/expected-after-race.json"
    GUARD_SECRET_ARGV=1 "${WITNESS_FUNCTION}" "${listener}" "${ipv4}" "${ipv6}" \
        >"${TEST_ROOT}/result.json" 2>"${TEST_ROOT}/error.log" || status=$?
    [[ ! -e "${TEST_ROOT}/unexpected.log" ]] || fail "非只读或未知调用: $(cat "${TEST_ROOT}/unexpected.log")"
    if [[ "${MODE}" == replace-live || "${MODE}" == scope-race ]]; then
        before=$(<"${TEST_ROOT}/expected-after-race.json")
    fi
    [[ "$(treeSnapshot)" == "${before}" ]] || fail '见证改变了受管文件、元数据或目录'
    if [[ "${expected}" == ok ]]; then
        [[ "${status}" == 0 ]] || fail "正例被拒绝: $(cat "${TEST_ROOT}/error.log")"
        jq -e --arg listener "${listener}" --arg id "${ID}" --arg image "${IMAGE_ID}" \
            --arg ipv4 "${ipv4}" --arg ipv6 "${ipv6}" --arg started "${expectedStart}" --argjson count "${count}" '
          keys == (["schema_version","listener_id","protocol_id","core","container_id","image_id",
            "started_at","restart_count","target_port","ipv4","ipv6","enabled_accounts"] | sort) and
          .schema_version == 1 and .listener_id == $listener and .protocol_id == 3 and
          .core == "sing-box" and .container_id == $id and .image_id == $image and
          .started_at == $started and .restart_count == 0 and
          .target_port == 27443 and .ipv4 == $ipv4 and .ipv6 == $ipv6 and
          .enabled_accounts == $count
        ' "${TEST_ROOT}/result.json" >/dev/null || fail '目标 JSON 不符合固定合同'
        for kind in 'container inspect ' 'image inspect ' 'network inspect ' 'ip -j address show'; do
            [[ $(grep -c "^${kind}" "${TEST_ROOT}/commands.log") == 2 ]] || fail "${kind} 未执行两轮"
        done
    else
        [[ "${status}" != 0 && ! -s "${TEST_ROOT}/result.json" ]] || fail "非法见证成功: ${MODE}"
    fi
    cases=$((cases + 1))
}
change() {
    jq "$2" "${root}/$1" >"${TEST_ROOT}/changed.json"
    cp -- "${TEST_ROOT}/changed.json" "${root}/$1"
}
restore() { cp -a -- "${TEST_ROOT}/baseline/." "${root}/"; }

runWitness ok
MODE=health-tick
runWitness ok
MODE=scope-race
runWitness reject
MODE=ok
restore
cp -a -- "${TEST_ROOT}/inspect.before-scope.json" "${TEST_ROOT}/inspect.json"
change config/spec.json '.accounts[0].enabled = false'
generate
runWitness ok 1
restore
quota=$(jq -cn --arg self "${SELF}" '{schema_version:1,accounts:{
  ($self):{name:"self",upload:1,download:0,limit_bytes:1,baseline:{}}}}')
printf '%s\n' "${quota}" >"${root}/data/traffic/state.json"
dockerTrafficRender sing-box "${root}/config/sing-box/users.base" "${quota}" >"${root}/config/sing-box/config.json"
runWitness ok 1
quota=$(jq --arg alice "${ALICE}" '.accounts[$alice] = {name:"Alice",upload:1,download:0,
  limit_bytes:1,baseline:{}}' <<<"${quota}")
printf '%s\n' "${quota}" >"${root}/data/traffic/state.json"
dockerTrafficRender sing-box "${root}/config/sing-box/users.base" "${quota}" >"${root}/config/sing-box/config.json"
runWitness reject
restore
runWitness reject 0 missing
for tuple in '127.0.0.1 2001:db8:1::1' '198.18.1.2 2001:db8:1::1' \
    '198.18.1.1 2001:0db8:1::1' '198.18.1.1 ::ffff:198.18.1.1'; do
    read -r ipv4 ipv6 <<<"${tuple}"
    runWitness reject 0 entry-hy2 "${ipv4}" "${ipv6}"
done

for filter in \
    '.[0].State.Running = false' '.[0].State.Restarting = true' \
    '.[0].State.Health.Status = "unhealthy"' \
    '.[0].Config.Labels["com.docker.compose.project.working_dir"] = "/foreign"' \
    '.[0].Config.Image = "foreign@sha256:" + ("1"*64)' \
    '.[0].Image = "sha256:" + ("d"*64)' \
    '.[0].Config.Cmd = ["run","-c","/foreign"]' \
    '.[0].Mounts[0].Source = "/foreign"' '.[0].Mounts[0].RW = true' \
    '.[0].HostConfig.PortBindings["27443/udp"][0].HostPort = "27444"' \
    '.[0].HostConfig.PortBindings["27443/udp"] |= .[:1]' \
    '.[0].HostConfig.NetworkMode = "host"' \
    '.[0].HostConfig.CapAdd = ["NET_ADMIN"]' \
    '.[0].HostConfig.ReadonlyRootfs = false'; do
    INSPECT_FILTER=${filter}
    runWitness reject
done
INSPECT_FILTER=.
IMAGE_FILTER='.[0].Id = "sha256:" + ("d"*64)'
runWitness reject
IMAGE_FILTER=.
NETWORK_FILTER='.[0].Driver = "host"'
runWitness reject
NETWORK_FILTER=.
IP_FILTER='.[0].addr_info |= .[:1]'
runWitness reject
IP_FILTER=.
for MODE in duplicate query-fail restart-drift replace-live; do runWitness reject; done
MODE=ok
restore

for pair in \
    'config/spec.json|.schema_version = 2' \
    'config/spec.json|.core.protocols[0].address_families = ["ipv4"]' \
    'config/spec.json|.core.protocols[0].core = "xray"' \
    'deployment.json|.listeners[0].container_port = 27444' \
    'compose.json|.services["sing-box"].ports |= .[:1]' \
    'config/sing-box/users.base|.inbounds[0].users[0].password = "foreign"' \
    'config/sing-box/config.json|.inbounds[0].listen_port = 27444' \
    'config/sing-box/config.json|.inbounds[0].users[0].password = "foreign"'; do
    change "${pair%%|*}" "${pair#*|}"
    runWitness reject
    restore
done
printf 'foreign.env\n' >>"${root}/images.env"
runWitness reject
restore
printf '{}\n' >"${root}/config/sing-box/rogue.json"
runWitness reject
rm -- "${root}/config/sing-box/rogue.json"
for file in config/spec.json config/sing-box/config.json secrets/tls/proxy.example.com.crt; do
    mv -- "${root}/${file}" "${TEST_ROOT}/linked"
    ln -s -- "${TEST_ROOT}/linked" "${root}/${file}"
    runWitness reject
    rm -- "${root}/${file}"
    mv -- "${TEST_ROOT}/linked" "${root}/${file}"
done
runWitness ok

# 用文件实际纳秒时间构造启动夹具，避免等待整秒或依赖固定日期。
startupTime() {
    local started
    started=$(python3 - "${root}" "${1:-0}" <<'PY'
import datetime
from pathlib import Path
import sys

root = Path(sys.argv[1])
files = [root / "config/sing-box/config.json", *sorted((root / "secrets/tls").iterdir())]
cutoff = max(max(path.stat().st_mtime_ns, path.stat().st_ctime_ns) for path in files) + int(sys.argv[2])
seconds, nanos = divmod(cutoff, 1_000_000_000)
print(datetime.datetime.fromtimestamp(seconds, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S") +
      f".{nanos:09d}Z")
PY
    )
    jq --arg started "${started}" '.[0].State.StartedAt = $started' \
        "${TEST_ROOT}/inspect.json" >"${TEST_ROOT}/started.json"
    mv -- "${TEST_ROOT}/started.json" "${TEST_ROOT}/inspect.json"
}
WITNESS_FUNCTION=dockerPortHoppingTargetStartupWitness
startupTime
runWitness ok
startupTime -1
runWitness reject
startupTime 1
runWitness ok
INSPECT_FILTER='.[0].State.StartedAt = "2026-02-30T01:00:00.000000000Z"'
runWitness reject
INSPECT_FILTER=.
MODE=restart-drift
runWitness reject
MODE=replace-live
runWitness reject
MODE=ok
restore
startupTime
old_mtime=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' \
    "${root}/config/sing-box/config.json")
change config/spec.json '.accounts[0].password = "Alice.NewSecretPass"'
generate
python3 - "${root}/config/sing-box/config.json" "${old_mtime}" <<'PY'
import os
import sys

os.utime(sys.argv[1], ns=(int(sys.argv[2]), int(sys.argv[2])))
PY
WITNESS_FUNCTION=dockerPortHoppingTargetWitness
runWitness ok
WITNESS_FUNCTION=dockerPortHoppingTargetStartupWitness
runWitness reject
startupTime
runWitness ok
restore
for file in secrets/tls/proxy.example.com.crt secrets/tls/proxy.example.com.key; do
    startupTime
    cp -a -- "${root}/${file}" "${TEST_ROOT}/tls.replacement"
    mv -f -- "${TEST_ROOT}/tls.replacement" "${root}/${file}"
    WITNESS_FUNCTION=dockerPortHoppingTargetWitness
    runWitness ok
    WITNESS_FUNCTION=dockerPortHoppingTargetStartupWitness
    runWitness reject
    startupTime
    runWitness ok
done
startupTime
change data/traffic/state.json '.accounts["11111111-1111-4111-8111-111111111111"] = {
  name:"self",upload:1,download:0,limit_bytes:0,baseline:{}}'
chmod 0750 "${root}"
runWitness ok
printf 'docker-port-hopping-target-ok: %s read-only target cases\n' "${cases}"
