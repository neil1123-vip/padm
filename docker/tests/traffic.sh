#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-traffic.XXXXXX")
trap '[[ "${PADM_TEST_KEEP:-0}" == 1 ]] || rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=1
export MSYS=winsymlinks:sys
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/traffic.sh"

ACCOUNT=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
CONTAINER_ID=$(printf 'a%.0s' {1..64})
GENERATION=1
MODE=ok
HTTP2=1
QUERY_MODE=ok
COMPOSE_LOG=${TEST_ROOT}/compose.log

fail() { printf 'docker-traffic-regression-fail: %s\n' "$*" >&2; exit 1; }
reject() {
    if "$@" >"${TEST_ROOT}/rejected.log" 2>&1; then fail "应拒绝: $*"; fi
}

dockerComposeRun() {
    printf '%s\n' "$*" >>"${COMPOSE_LOG}"
    case "$1" in
    ps) printf '%s\n' "${CONTAINER_ID}" ;;
    exec) [[ "${QUERY_MODE}" != api-fail ]] && printf '%s\n' "${STATS}" ;;
    run) [[ "${MODE}" != check-fail ]] ;;
    restart)
        if [[ "${MODE}" == restart-fail && ! -e "${TEST_ROOT}/restart-failed" ]]; then
            : >"${TEST_ROOT}/restart-failed"
            return 1
        fi
        ;;
    up) ;;
    *) fail "意外的 Compose 命令: $*" ;;
    esac
}

docker() {
    [[ "$1" == inspect ]] || return 1
    local count started pid=1234
    count=$(<"${TEST_ROOT}/inspect-count")
    printf '%s\n' "$((count + 1))" >"${TEST_ROOT}/inspect-count"
    started=${GENERATION}
    if [[ "${QUERY_MODE}" == changed && "$((count % 2))" == 1 ]]; then started=changed; fi
    if [[ "${QUERY_MODE}" == changed-pid && "$((count % 2))" == 1 ]]; then pid=5678; fi
    jq -cn --arg id "${CONTAINER_ID}" --arg start "${started}" --arg core "${CORE}" --argjson pid "${pid}" '
      {Id:$id, State:{Running:true, Pid:$pid, StartedAt:$start},
       Config:{Labels:{"com.docker.compose.project":"padm-docker", "com.docker.compose.service":$core}}}'
}

varint() {
    local value=$1 byte
    while ((value >= 128)); do
        byte=$(((value & 127) | 128))
        printf -v byte '%03o' "${byte}"
        printf '%b' "\\${byte}"
        value=$((value >> 7))
    done
    printf -v byte '%03o' "${value}"
    printf '%b' "\\${byte}"
}

grpcResponse() {
    local payload=${TEST_ROOT}/payload.bin entry=${TEST_ROOT}/entry.bin name value length byte
    : >"${payload}"
    while IFS=$'\t' read -r name value; do
        printf '\012' >"${entry}"
        varint "${#name}" >>"${entry}"
        printf '%s\020' "${name}" >>"${entry}"
        varint "${value}" >>"${entry}"
        printf '\012' >>"${payload}"
        varint "$(wc -c <"${entry}")" >>"${payload}"
        cat "${entry}" >>"${payload}"
    done < <(jq -r '.stat[]? | [.name, (.value // 0)] | @tsv' <<<"${STATS}")
    length=$(wc -c <"${payload}")
    printf '\000'
    for shift in 24 16 8 0; do
        printf -v byte '%03o' "$(((length >> shift) & 255))"
        printf '%b' "\\${byte}"
    done
    cat "${payload}"
}

curl() {
    [[ "$1" == --version ]] || return 1
    if [[ "${HTTP2}" == 1 ]]; then printf 'Features: SSL HTTP2\n'; else printf 'Features: SSL\n'; fi
}

nsenter() {
    local headers='' output='' request='' status=0
    [[ "${QUERY_MODE}" != api-fail ]] || return 1
    [[ "$1 $2 $3 $4 $5" == '--target 1234 --net curl -fsS' ]] || fail 'nsenter 参数错误'
    shift 4
    while (($#)); do
        case "$1" in
        -D) headers=$2; shift ;;
        --output) output=$2; shift ;;
        --data-binary) request=${2#@}; shift ;;
        esac
        shift
    done
    [[ "$(od -An -v -tu1 "${request}" | xargs)" == '0 0 0 0 6 26 4 117 115 101 114' ]] || fail 'gRPC patterns 请求错误'
    [[ "${QUERY_MODE}" != grpc-fail ]] || status=13
    printf 'HTTP/2 200\r\ngrpc-status: %s\r\n\r\n' "${status}" >"${headers}"
    if [[ "${QUERY_MODE}" == malformed ]]; then printf '\000\000\000\000\001' >"${output}";
    else grpcResponse >"${output}"; fi
}

counters() {
    STATS=$(jq -cn --arg account "${ACCOUNT}" --argjson up "$1" --argjson down "$2" '
      {stat:([{name:("user>>>"+$account+">>>traffic>>>uplink"),value:$up},
              {name:("user>>>"+$account+">>>traffic>>>downlink"),value:$down}] | map(select(.value != null)))}')
}

assertCounts() {
    jq -e --arg account "${ACCOUNT}" --argjson up "$1" --argjson down "$2" '
      .accounts[$account] | .upload == $up and .download == $down' "${STATE}" >/dev/null || fail "${CORE}: 累计应为 $1/$2"
}

assertEnabled() {
    local count
    if [[ "${CORE}" == xray ]]; then count=$(jq '[.inbounds[].settings.clients[]?] | length' "${CONFIG}");
    else count=$(jq '[.inbounds[].users[]?] | length' "${CONFIG}"); fi
    [[ "${count}" == "$1" ]] || fail "${CORE}: 用户数量应为 $1，实际 ${count}"
}

assertSnapshotRejected() {
    cp "${STATE}" "${TEST_ROOT}/before-state"
    printf '0\n' >"${TEST_ROOT}/inspect-count"
    reject dockerTrafficSnapshot
    cmp -s "${STATE}" "${TEST_ROOT}/before-state" || fail '失败采样修改了累计状态'
}

for CORE in xray sing-box; do
    PADM_DOCKER_INSTALL_DIR=${TEST_ROOT}/${CORE}
    CONFIG=${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/config.json
    BASE=${PADM_DOCKER_INSTALL_DIR}/config/${CORE}/users.base
    STATE=${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json
    mkdir -p "${CONFIG%/*}"
    jq -n --arg core "${CORE}" '{core:{type:$core}}' >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
    if [[ "${CORE}" == xray ]]; then
        jq -n --arg id "${ACCOUNT^^}" '{inbounds:[
          {tag:"first",protocol:"vless",settings:{clients:[{id:$id,email:"Alice",flow:"xtls-rprx-vision"}]}},
          {tag:"second",protocol:"vless",settings:{clients:[{id:$id,email:"Alice"}]}}]}' >"${CONFIG}"
    else
        jq -n --arg id "${ACCOUNT^^}" '{inbounds:[
          {type:"hysteria2",tag:"hy2",users:[{name:$id,password:"hy2-secret"}]},
          {type:"tuic",tag:"tuic",users:[{name:"Alice",uuid:$id,password:"tuic-secret"}]}]}' >"${CONFIG}"
    fi
    cp "${CONFIG}" "${TEST_ROOT}/original-${CORE}.json"
    dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}" || fail '根目录恢复路径被拒绝'
    cmp -s "${BASE}" "${TEST_ROOT}/original-${CORE}.json" || fail '完整配置保存发生变化'
    [[ "$(dockerTrafficAccounts "${CORE}" | jq length)" == 1 ]] || fail '同账号跨协议未合并'
    if [[ "${CORE}" == xray ]]; then
        jq -e '.api.services | index("StatsService") != null' "${CONFIG}" >/dev/null
        jq -e '.policy.levels["0"].statsUserUplink and .policy.levels["0"].statsUserDownlink' "${CONFIG}" >/dev/null
    else
        jq -e --arg account "${ACCOUNT}" '.experimental.v2ray_api.listen == "127.0.0.1:10087" and
          .experimental.v2ray_api.stats.enabled and .experimental.v2ray_api.stats.users == [$account]' "${CONFIG}" >/dev/null
    fi
    cp "${CONFIG}" "${TEST_ROOT}/enabled-${CORE}.json"
    GENERATION=1
    printf '0\n' >"${TEST_ROOT}/inspect-count"
    counters 100 200
    dockerTrafficCollect
    assertCounts 100 200
    dockerTrafficCollect
    assertCounts 100 200
    counters 130 null
    dockerTrafficCollect
    assertCounts 130 200
    GENERATION=2
    counters 7 null
    dockerTrafficCollect
    assertCounts 137 200
    counters 9 11
    dockerTrafficCollect
    assertCounts 139 211
    counters 3 2
    dockerTrafficCollect
    assertCounts 142 213
    for QUERY_MODE in api-fail changed changed-pid; do assertSnapshotRejected; done
    QUERY_MODE=ok
    if [[ "${CORE}" == xray ]]; then
        for STATS in '{"stat":false}' '{"stat":[{"name":null}]}' \
            "{\"stat\":[{\"name\":\"user>>>${ACCOUNT}>>>traffic>>>uplink\",\"value\":false}]}" \
            "{\"stat\":[{\"name\":\"user>>>${ACCOUNT}>>>traffic>>>uplink\",\"value\":-1}]}"; do
            assertSnapshotRejected
        done
        counters 3 2
        STATS=$(jq '.stat += [.stat[0]]' <<<"${STATS}")
        assertSnapshotRejected
    else
        for QUERY_MODE in grpc-fail malformed; do assertSnapshotRejected; done
        QUERY_MODE=ok
        HTTP2=0
        assertSnapshotRejected
        HTTP2=1
    fi
    counters 3 2
    : >"${COMPOSE_LOG}"
    dockerTrafficCollect
    if grep -q '^restart ' "${COMPOSE_LOG}"; then fail '无配置变化触发了重启'; fi
    dockerTrafficSetLimit "${ACCOUNT}" 355
    assertEnabled 0
    dockerTrafficReset "${ACCOUNT}"
    assertCounts 0 0
    assertEnabled 2
    cmp -s "${CONFIG}" "${TEST_ROOT}/enabled-${CORE}.json" || fail '归零未恢复原凭据'
    counters 403 2
    dockerTrafficCollect
    assertCounts 400 0
    assertEnabled 0
    dockerTrafficSetLimit "${ACCOUNT}" 500
    assertEnabled 2
    cmp -s "${CONFIG}" "${TEST_ROOT}/enabled-${CORE}.json" || fail '上调限额未恢复原凭据'
    dockerTrafficSetLimit "${ACCOUNT}" 1
    assertEnabled 0
    dockerTrafficSetLimit "${ACCOUNT}" 0
    assertEnabled 2
    MODE=check-fail
    reject dockerTrafficSetLimit "${ACCOUNT}" 1
    assertCounts 400 0
    assertEnabled 2
    MODE=restart-fail
    rm -f -- "${TEST_ROOT}/restart-failed"
    reject dockerTrafficApplyQuotas
    assertCounts 400 0
    cmp -s "${CONFIG}" "${TEST_ROOT}/enabled-${CORE}.json" || fail '重启失败未恢复旧配置'
    MODE=ok
    dockerTrafficApplyQuotas
    assertEnabled 0
    cmp -s "${BASE}" "${TEST_ROOT}/original-${CORE}.json" || fail '额度流程修改了原始凭据'
done

# 大计数必须逐字保留，不能采用 awk 默认的六位有效数字。
counters 123456789 9007199254740000
grpcResponse >"${TEST_ROOT}/large.bin"
singBoxGrpcResponseToStatsJson "${TEST_ROOT}/large.bin" | jq -e '
  .stat[0].value == 123456789 and .stat[1].value == 9007199254740000' >/dev/null || fail 'gRPC 大计数丢失精度'

cp "${STATE}" "${TEST_ROOT}/before-state"
cp "${CONFIG}" "${TEST_ROOT}/before-config"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/candidate/config/sing-box"
printf '{}\n' >"${PADM_DOCKER_INSTALL_DIR}/candidate/config/sing-box/config.json"
reject dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}/candidate"
cmp -s "${STATE}" "${TEST_ROOT}/before-state" || fail '无效候选修改累计状态'
cmp -s "${CONFIG}" "${TEST_ROOT}/before-config" || fail '无效候选修改运行配置'

# 实际符号链接依赖宿主能力；MSYS2 的 sys 链接可保留与 Linux 相同的检查语义。
mv "${STATE}" "${STATE}.real"
ln -s "${STATE}.real" "${STATE}"
[[ -L "${STATE}" ]] || fail '测试环境未创建符号链接'
reject dockerTrafficReadState
reject dockerTrafficWriteState <"${STATE}.real"
rm -- "${STATE}"
mv "${STATE}.real" "${STATE}"
mv "${BASE}" "${BASE}.real"
ln -s "${BASE}.real" "${BASE}"
reject dockerTrafficAccounts sing-box
reject dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}"
rm -- "${BASE}"
mv "${BASE}.real" "${BASE}"
mv "${PADM_DOCKER_INSTALL_DIR}/data" "${PADM_DOCKER_INSTALL_DIR}/data.real"
ln -s "${PADM_DOCKER_INSTALL_DIR}/data.real" "${PADM_DOCKER_INSTALL_DIR}/data"
reject dockerTrafficReadState
reject dockerTrafficWriteState <"${STATE}"
cmp -s "${STATE}" "${TEST_ROOT}/before-state" || fail '符号链接检查修改了状态'
printf 'docker-traffic-regression: ok\n'
