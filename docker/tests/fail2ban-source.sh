#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-source.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-fail2ban-source-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

reject() {
    if "$@"; then
        printf 'docker-fail2ban-source-unexpected-success: %s\n' "$*" >&2
        exit 1
    fi
}

root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config/nginx" "${root}/logs/nginx" "${root}/data/static" \
    "${root}/secrets/tls" "${TEST_ROOT}/bundle"
printf 'local-test\n' >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
jq '
  .schema_version = 3 | .core.secondary_type = null | .subscription.enabled = false |
  .core.protocols[0] += {core:"xray",listener_id:"entry-source-ws"} |
  .core.protocols[0].websocket += {backend_port:31297,tls_port:8443}
' "${PROJECT_ROOT}/docker/configure-nginx.example.json" >"${root}/config/spec.json"
dockerConfigureSpecValidate "${root}/config/spec.json"
dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
dockerGenerateNginxConfig "${root}/config/spec.json" "${root}/config/nginx/default.conf"
jq -n --arg root "${root}" --slurpfile spec "${root}/config/spec.json" \
    --slurpfile compose "${root}/compose.json" '
  $compose[0].services.nginx as $service |
  [{Id:("a"*64),RestartCount:0,
    State:{Status:"running",Running:true,Restarting:false,Paused:false,Dead:false,
      StartedAt:"2026-10-10T01:00:00.000000000Z"},
    Config:{Image:$spec[0].images.nginx,Labels:($service.labels + {
      "com.docker.compose.project":"padm-docker",
      "com.docker.compose.project.working_dir":$root,
      "com.docker.compose.project.config_files":($root+"/compose.json"),
      "com.docker.compose.service":"nginx","com.docker.compose.oneoff":"False"}),
      Entrypoint:["/usr/sbin/nginx","-e","/dev/stderr"],
      Cmd:["-g","daemon off;"],User:"10001:10001"},
    HostConfig:{NetworkMode:"padm-docker",ReadonlyRootfs:true,Privileged:false,
      CapAdd:null,CapDrop:["ALL"],SecurityOpt:["no-new-privileges:true"],
      LogConfig:{Type:$service.logging.driver,Config:$service.logging.options},
      Tmpfs:{"/tmp":"rw,noexec,nosuid,nodev,size=32m"},
      PortBindings:{"8443/tcp":[{HostIp:"0.0.0.0",HostPort:"443"},
        {HostIp:"::",HostPort:"443"}]}},
    NetworkSettings:{Networks:{"padm-docker":{NetworkID:("b"*64),IPAddress:"172.30.0.2",
      Gateway:"172.30.0.1",GlobalIPv6Address:"",IPv6Gateway:""}}},
    Mounts:[$service.volumes[] | {Type:"bind",
      Source:(.source | sub("^\\$\\{PADM_DOCKER_ROOT\\}";$root)),
      Destination:.target,RW:(.read_only|not)}]}]
' >"${TEST_ROOT}/inspect.json"

MODE=ok
docker() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/commands.log"
    case "$1" in
    ps)
        [[ "${MODE}" != query-fail ]] || return 1
        printf '%s\n' aaaaaaaaaaaa
        [[ "${MODE}" != duplicate ]] || printf '%s\n' bbbbbbbbbbbb
        ;;
    container)
        jq "${INSPECT_FILTER:-.}" "${TEST_ROOT}/inspect.json"
        ;;
    network)
        jq -n --slurpfile compose "${root}/compose.json" --arg networkId "${NETWORK_ID:-b}" '
          $compose[0].networks.default as $network |
          [{Id:($networkId*64),Name:$network.name,Driver:"bridge",Labels:$network.labels,
            EnableIPv6:false}]
        '
        ;;
    *) return 99 ;;
    esac
}
ip() {
    printf '[{"addr_info":[{"family":"inet","local":"192.0.2.1"},{"family":"inet6","local":"2001:db8::1"}]}]\n'
}

snapshot=$(dockerFail2banSourceContainer entry-source-ws ipv4)
SOURCE_SNAPSHOT=${snapshot}
jq -e '.id == ("a"*64) and .public_port == 443 and .internal_port == 8443 and
  .restart_count == 0 and (.addresses | index("172.30.0.1") != null) and
  .networks == [{name:"padm-docker",id:("b"*64)}]' \
    <<<"${snapshot}" >/dev/null
changed=$(NETWORK_ID=c INSPECT_FILTER='.[0].NetworkSettings.Networks["padm-docker"].NetworkID = ("c"*64)' \
    dockerFail2banSourceContainer entry-source-ws ipv4)
[[ "${changed}" != "${snapshot}" ]]
jq -e '.networks == [{name:"padm-docker",id:("c"*64)}]' <<<"${changed}" >/dev/null
# 此处调用已导入的生产函数；后文仅为见证测试覆盖系统边界。
# shellcheck disable=SC2218
dockerFail2banSourceContainer entry-source-ws ipv6 >/dev/null
for filter in \
    '.[0].Config.Image = "foreign"' \
    '.[0].State.Running = false' \
    '.[0].State.Restarting = true' \
    '.[0].State.Paused = true' \
    '.[0].Config.Labels["com.docker.compose.project.working_dir"] = "/foreign"' \
    '.[0].Config.Cmd = ["foreign"]' \
    '.[0].HostConfig.Privileged = true' \
    '.[0].HostConfig.PortBindings["8443/tcp"][0].HostPort = "444"' \
    '.[0].Mounts[0].RW = true'; do
    INSPECT_FILTER="${filter}"
    reject dockerFail2banSourceContainer entry-source-ws ipv4 >/dev/null
done
unset INSPECT_FILTER
MODE=duplicate
reject dockerFail2banSourceContainer entry-source-ws ipv4 >/dev/null
MODE=query-fail
reject dockerFail2banSourceContainer entry-source-ws ipv4 >/dev/null
MODE=ok
reject dockerFail2banSourceContainer missing ipv4 >/dev/null
cp "${root}/config/nginx/default.conf" "${TEST_ROOT}/nginx.conf"
printf '\n# 漂移夹具\n' >>"${root}/config/nginx/default.conf"
reject dockerFail2banSourceContainer entry-source-ws ipv4 >/dev/null
cp "${TEST_ROOT}/nginx.conf" "${root}/config/nginx/default.conf"

# 仅替换系统边界；挑战、地址规范化和日志解析仍执行生产函数。
dockerFail2banSourceContainer() {
    local result=${SOURCE_SNAPSHOT}
    if [[ "${MODE}" == restart ]]; then
        if [[ -e "${TEST_ROOT}/restarted" ]]; then
            result=$(jq '.restart_count += 1' <<<"${result}")
        else
            touch "${TEST_ROOT}/restarted"
        fi
    elif [[ "${MODE}" == network-drift ]]; then
        if [[ -e "${TEST_ROOT}/network-drift" ]]; then
            result=$(jq '.networks[0].id = ("c"*64)' <<<"${result}")
        else
            touch "${TEST_ROOT}/network-drift"
        fi
    fi
    printf '%s\n' "${result}"
}
dockerSubscriptionRandomHex() { printf '%048d\n' 1; }
sleep() { SECONDS=$((SECONDS + 31)); }
docker() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/commands.log"
    [[ "$1" == logs ]] || return 99
    [[ "${MODE}" != logs-fail ]] || return 1
    local uri=/.well-known/padm-source/$(printf '%048d' 1)
    case "${MODE}" in
    historical) uri=/.well-known/padm-source/$(printf '%048d' 2) ;;
    malformed) printf 'padm-source invalid-json\n'; return ;;
    esac
    jq -cn --arg uri "${uri}" --arg mode "${MODE}" --arg address "${EXPECT_SOURCE}" '
      {source:$address,port:"8443",host:"proxy.example.com",method:"GET",uri:$uri} |
      if $mode == "wrong-port" then .port="8444"
      elif $mode == "wrong-source" then .source="198.51.100.8"
      elif $mode == "wrong-host" then .host="foreign.example.com"
      elif $mode == "wrong-method" then .method="POST" else . end |
      "padm-source " + tojson
    ' | jq -r .
}
MODE=ok EXPECT_SOURCE=198.51.100.7
dockerFail2banSourceWitness entry-source-ws "${EXPECT_SOURCE}" >"${TEST_ROOT}/result.log"
grep -q '^source-challenge=' "${TEST_ROOT}/result.log"
grep -q '^source-verified=' "${TEST_ROOT}/result.log"
for MODE in historical wrong-port wrong-source wrong-host wrong-method malformed logs-fail restart network-drift; do
    reject dockerFail2banSourceWitness entry-source-ws "${EXPECT_SOURCE}" >"${TEST_ROOT}/result.log"
    reject grep -q '^source-verified=' "${TEST_ROOT}/result.log"
done
MODE=ok
for invalid in localhost 0.0.0.0 127.0.0.1 224.0.0.1 :: ::1 ff02::1 \
    ::ffff:198.51.100.7 192.0.2.1 172.30.0.1 172.30.0.2; do
    reject dockerFail2banSourceWitness entry-source-ws "${invalid}" >"${TEST_ROOT}/result.log"
    reject grep -q '^source-verified=' "${TEST_ROOT}/result.log"
done
EXPECT_SOURCE=2001:db8:2::7
dockerFail2banSourceWitness entry-source-ws "${EXPECT_SOURCE}" >"${TEST_ROOT}/result.log"
grep -q '^source-verified=' "${TEST_ROOT}/result.log"
printf 'docker-fail2ban-source-contract-ok\n'
