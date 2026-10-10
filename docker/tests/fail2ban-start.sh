#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-start.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-fail2ban-start-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2; [[ ! -f "${TEST_ROOT}/output.log" ]] || cat "${TEST_ROOT}/output.log" >&2' ERR
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

reject() {
    if "$@"; then
        printf 'docker-fail2ban-start-unexpected-success: %s\n' "$*" >&2
        exit 1
    fi
}

root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config/nginx" "${root}/config/net/fail2ban" "${root}/logs/nginx" \
    "${root}/data/static" "${root}/secrets/tls" "${TEST_ROOT}/bundle"
printf 'local-test\n' >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
jq '
  .schema_version = 3 | .core.secondary_type = null | .subscription.enabled = false |
  .core.protocols[0] += {core:"xray",listener_id:"entry-source-ws",public_port:24444} |
  .core.protocols[0].address_families = ["ipv6","ipv4"] |
  .core.protocols[0].websocket += {backend_port:31297,tls_port:8443} |
  .core.protocols += [(.core.protocols[0] |
    .listener_id = "entry-source-ws2" | .public_port = 24445 | .name = "second-websocket" |
    .uuid = "33333333-3333-4333-8333-333333333333" |
    .websocket += {path:"second_random_path",backend_port:31298,tls_port:8444})] |
  .core.protocols |= reverse |
  .host_integrations = [{type:"fail2ban",profile:"net-fail2ban",
    firewall_rules:["DOCKER-USER"],devices:[],schedules:[],
    settings:{log_file:"access.log",ports:[24445,24444],max_retry:5,find_time:600,ban_time:3600}}]
' "${PROJECT_ROOT}/docker/configure-nginx.example.json" >"${root}/config/spec.json"
dockerConfigureSpecValidate "${root}/config/spec.json"
cp "${root}/config/spec.json" "${TEST_ROOT}/spec.json"
dockerGenerateCompose "${root}/config/spec.json" "${root}/compose.json" "${root}"
dockerGenerateDeployment "${root}/config/spec.json" "${root}/deployment.json"
dockerGenerateImagesEnv "${root}/config/spec.json" "${root}/images.env" "${root}"
dockerGenerateNginxConfig "${root}/config/spec.json" "${root}/config/nginx/default.conf"
dockerGenerateFail2banConfig "${root}/config/spec.json" "${root}"

plan=$(dockerFail2banSourcePlan "${root}/config/spec.json")
jq -e '. == ([{listener_id:"entry-source-ws",public_port:24444,internal_port:8443},
    {listener_id:"entry-source-ws2",public_port:24445,internal_port:8444}] |
  map(. as $entry | ["ipv4","ipv6"][] |
    $entry + {family:.,domain:"proxy.example.com"}))' <<<"${plan}" >/dev/null
jq '.host_integrations = []' "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/disabled.json"
[[ "$(dockerFail2banSourcePlan "${TEST_ROOT}/disabled.json")" == '[]' ]]
for filter in \
    '.host_integrations[0].settings.ports = [24446]' \
    '.core.protocols[1].public_port = 24445' \
    '.core.protocols[1].listener_id = "entry-source-ws2"' \
    '.port_aliases = [{listener_id:"entry-source-ws",public_port:24446}]' \
    '.reality_stream = {}'; do
    jq "${filter}" "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/invalid.json"
    reject dockerFail2banSourcePlan "${TEST_ROOT}/invalid.json" >/dev/null
done

# 两份恢复规格的地址族并集必须先收齐，不能继承上一事务的来源输入。
jq '.core.protocols[].address_families = ["ipv4"]' "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/ipv4.json"
jq '.core.protocols[].address_families = ["ipv6"]' "${TEST_ROOT}/spec.json" >"${TEST_ROOT}/ipv6.json"
export PADM_DOCKER_FAIL2BAN_SOURCE_IPV4=198.51.100.7
export PADM_DOCKER_FAIL2BAN_SOURCE_IPV6=2001:db8:2::7
dockerFail2banSourceInputsPrepare "${TEST_ROOT}/ipv4.json" "${TEST_ROOT}/ipv6.json"
[[ "${DOCKER_FAIL2BAN_SOURCE_IPV4}" == 198.51.100.7 &&
    "${DOCKER_FAIL2BAN_SOURCE_IPV6}" == 2001:0db8:0002:0000:0000:0000:0000:0007 ]]
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4=127.0.0.1
DOCKER_FAIL2BAN_SOURCE_IPV4=
reject dockerFail2banSourceInputsPrepare "${TEST_ROOT}/ipv4.json" >/dev/null
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4=198.51.100.7
DOCKER_FAIL2BAN_SOURCE_IPV4=198.51.100.7
PADM_DOCKER_FAIL2BAN_SOURCE_IPV6=198.51.100.7
DOCKER_FAIL2BAN_SOURCE_IPV6=
reject dockerFail2banSourceInputsPrepare "${TEST_ROOT}/ipv6.json" >/dev/null
PADM_DOCKER_FAIL2BAN_SOURCE_IPV6=2001:db8:2::7
DOCKER_FAIL2BAN_SOURCE_IPV6=2001:0db8:0002:0000:0000:0000:0000:0007

# 只替换现场边界，保留生产规格校验、计划和地址规范化。
MODE=ok
record() {
    local kind=$1
    shift
    jq -cn --arg kind "${kind}" --args '{kind:$kind,args:$ARGS.positional}' -- "$@" \
        >>"${TEST_ROOT}/events.jsonl"
}
dockerFail2banConfigurationCheck() {
    record config "$@"
    [[ "${MODE}" != config-fail ]]
}
dockerFail2banCleanCheck() {
    record clean "$@"
    [[ "${MODE}" != clean-drift || ! -e "${TEST_ROOT}/last-witness" ]]
}
dockerComposeExecute() {
    record compose "$@"
}
dockerFail2banSourceContainer() {
    local listener=$1 family=$2 publicPort=24444 internalPort=8443 restart=0
    record snapshot "$@"
    if [[ "${listener}" == entry-source-ws2 ]]; then
        publicPort=24445 internalPort=8444
    elif [[ "${MODE}" == snapshot-drift && -e "${TEST_ROOT}/last-witness" ]]; then
        restart=1
    fi
    jq -cn --argjson publicPort "${publicPort}" --argjson internalPort "${internalPort}" \
        --argjson restart "${restart}" '
      {id:("a"*64),started_at:"2026-10-10T01:00:00.000000000Z",restart_count:$restart,
       public_port:$publicPort,internal_port:$internalPort,domain:"proxy.example.com",
       addresses:["192.0.2.1"],networks:[{name:"padm-docker",id:("b"*64)}]}
    '
    [[ "${family}" == ipv4 || "${family}" == ipv6 ]]
}
dockerFail2banSourceWitness() {
    local listener=$1 address=$2
    record witness "$@"
    printf 'source-challenge={"listener_id":"%s","source":"%s"}\n' "${listener}" "${address}"
    if [[ "${listener}" == entry-source-ws2 && "${address}" == *:* ]]; then
        touch "${TEST_ROOT}/last-witness"
        [[ "${MODE}" != last-fail ]] || return 1
        if [[ "${MODE}" == spec-drift ]]; then
            jq '.host_integrations[0].settings.ban_time += 60' "${root}/config/spec.json" \
                >"${TEST_ROOT}/changed.json"
            mv -- "${TEST_ROOT}/changed.json" "${root}/config/spec.json"
        fi
    fi
    printf 'source-verified={"listener_id":"%s","source":"%s"}\n' "${listener}" "${address}"
}
dockerFail2banContainer() {
    record health "$@"
    [[ "${MODE}" != health-fail ]] || return 1
    printf '%s\n' aaaaaaaaaaaa
}

# net-check 是一次性评估 profile，不属于生成的运行期 profile。
jq '.services["net-tun-check"] = {profiles:["net-check"],command:["idle"]}' \
    "${root}/compose.json" >"${TEST_ROOT}/compose.json"
mv -- "${TEST_ROOT}/compose.json" "${root}/compose.json"
resetCase() {
    MODE=$1
    cp "${TEST_ROOT}/spec.json" "${root}/config/spec.json"
    : >"${TEST_ROOT}/events.jsonl"
    rm -f -- "${TEST_ROOT}/last-witness"
    DOCKER_FAIL2BAN_SOURCE_IPV4=198.51.100.7
    DOCKER_FAIL2BAN_SOURCE_IPV6=2001:0db8:0002:0000:0000:0000:0000:0007
}
assertNoJail() {
    jq -se 'all(.[] | select(.kind == "compose"); (.args | index("net-fail2ban")) == null)' \
        "${TEST_ROOT}/events.jsonl" >/dev/null
}

resetCase ok
DOCKER_FAIL2BAN_SOURCE_IPV6=
reject dockerFail2banStartVerified >"${TEST_ROOT}/output.log" 2>&1
jq -se 'all(.[]; .kind != "compose" and .kind != "witness")' \
    "${TEST_ROOT}/events.jsonl" >/dev/null
for MODE in config-fail last-fail snapshot-drift spec-drift clean-drift; do
    resetCase "${MODE}"
    reject dockerFail2banStartVerified >"${TEST_ROOT}/output.log" 2>&1
    assertNoJail
done

resetCase ok
dockerFail2banStartVerified >"${TEST_ROOT}/output.log" 2>&1
[[ "$(grep -c '^source-challenge=' "${TEST_ROOT}/output.log")" == 4 &&
    "$(grep -c '^source-verified=' "${TEST_ROOT}/output.log")" == 4 ]]
jq -se '
  [.[] | select(.kind == "witness") | .args] ==
    [["entry-source-ws","198.51.100.7"],
     ["entry-source-ws","2001:0db8:0002:0000:0000:0000:0000:0007"],
     ["entry-source-ws2","198.51.100.7"],
     ["entry-source-ws2","2001:0db8:0002:0000:0000:0000:0000:0007"]] and
  ([.[] | select(.kind == "compose") | .args] as $runs |
    ($runs | length) == 2 and $runs[0][0] == "up" and $runs[1][0] == "up" and
    ($runs[0] | index("xray")) != null and ($runs[0] | index("nginx")) != null and
    all(["net-fail2ban","acme","net-check","net-tun-check"][];
      . as $name | ($runs[0] | index($name)) == null) and
    ($runs[1] | index("--no-deps")) != null and
    ($runs[1] | index("net-fail2ban")) != null and
    all(["xray","nginx","acme","net-check","net-tun-check"][];
      . as $name | ($runs[1] | index($name)) == null) and
    all($runs[]; index("--wait") != null)) and
  ([to_entries[] | select(.value.kind == "compose") | .key] as $runs |
    [to_entries[] | select(.value.kind == "witness") | .key] as $witnesses |
    $runs[0] < $witnesses[0] and $witnesses[-1] < $runs[1]) and
  ([.[] | select(.kind == "clean")] | length) >= 2 and
  .[-1].kind == "health"
' "${TEST_ROOT}/events.jsonl" >/dev/null

resetCase health-fail
reject dockerFail2banStartVerified >"${TEST_ROOT}/output.log" 2>&1
jq -se 'any(.[]; .kind == "compose" and (.args | index("net-fail2ban")) != null) and
  .[-1].kind == "health"' "${TEST_ROOT}/events.jsonl" >/dev/null
printf 'docker-fail2ban-start-contract-ok\n'
