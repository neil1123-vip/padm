#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-tproxy-ownership.XXXXXX")
RUN_PID=
cleanup() {
    local status=$?
    if [[ -n "${RUN_PID}" ]]; then
        kill -TERM "${RUN_PID}" 2>/dev/null || true
        wait "${RUN_PID}" 2>/dev/null || true
    fi
    if [[ -f "${TEST_ROOT}/sleep.pids" ]]; then
        while IFS= read -r pid; do kill -TERM "${pid}" 2>/dev/null || true; done <"${TEST_ROOT}/sleep.pids"
    fi
    if [[ "${PADM_TEST_KEEP:-0}" == 1 ]]; then
        printf 'tproxy-ownership-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
    return "${status}"
}
trap cleanup EXIT
trap 'printf "docker-tproxy-ownership-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in jq python3 stat tar sha256sum; do command -v "${tool}" >/dev/null; done

fail() {
    [[ ! -f "${TEST_ROOT}/output.log" ]] || cat "${TEST_ROOT}/output.log" >&2
    printf 'docker-tproxy-ownership-fail: %s\n' "$*" >&2
    exit 1
}
export FAKE_TP_ROOT="${TEST_ROOT}/kernel" FAKE_TP_STATE="${TEST_ROOT}/state"
export FAKE_TP_LOG="${TEST_ROOT}/commands.log" FAKE_TP_WRITES="${TEST_ROOT}/writes.log"
export FAKE_TP_MODE=ok FAKE_TP_SIGNAL=TERM
PORT=31298
MARK=129
mkdir -p "${TEST_ROOT}/bin"

# 只替换系统命令，归属解析与清理仍执行生产函数。
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
    >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$1"
STATE_ROOT=$FAKE_TP_STATE
export FAKE_TP_SERVER_PID=$$
shift
case "$1" in
seed)
    shift
    wait_forever() { kill -KILL "$$"; }
    tproxy_run "$@"
    ;;
run-once)
    test_port=$2 test_mark=$3 test_family=ipv4 test_uid=
    case "${4:-}" in
    ipv4|ipv6|dual) test_family=$4; test_uid=${6:-} ;;
    --output-uid) test_uid=${5:-} ;;
    esac
    shift
    wait_forever() {
        if [ -n "$test_uid" ]; then
            tproxy_health "$test_port" "$test_mark" "$test_family" --output-uid "$test_uid"
        else tproxy_health "$test_port" "$test_mark" "$test_family"; fi
    }
    tproxy_run "$@"
    ;;
run-wait) shift; tproxy_run "$@" ;;
preflight) shift; tproxy_preflight "$@" ;;
health) shift; tproxy_health "$@" ;;
cleanup) tproxy_cleanup "${2:-}" ;;
*) exit 99 ;;
esac
SH
cat >"${TEST_ROOT}/bin/common" <<'SH'
record_write() {
    printf '%s %s\n' "${0##*/}" "$*" >>"${FAKE_TP_WRITES}"
}
inject_failure() {
    local point=$1
    if [[ "${FAKE_TP_MODE}" == "fail-${point_prefix:-}${point}" &&
        ! -e "${FAKE_TP_ROOT}/failed-once" ]]; then
        : >"${FAKE_TP_ROOT}/failed-once"
        exit 1
    fi
}
inject_signal() {
    local point=$1
    if [[ "${FAKE_TP_MODE}" == "signal-${point_prefix:-}${point}" &&
        ! -e "${FAKE_TP_ROOT}/signaled-once" ]]; then
        : >"${FAKE_TP_ROOT}/signaled-once"
        kill "-${FAKE_TP_SIGNAL}" "${FAKE_TP_SERVER_PID:-${PPID}}"
    fi
}
field() {
    local wanted=$1 index
    for ((index=0; index<${#args[@]}-1; index++)); do
        if [[ "${args[index]}" == "${wanted}" ]]; then
            printf '%s\n' "${args[index+1]}"
            return 0
        fi
    done
    return 1
}
remove_line() {
    local file=$1 value=$2
    grep -qxF -- "${value}" "${file}" || return 1
    awk -v value="${value}" '$0 != value' "${file}" >"${file}.new"
    command -p mv -- "${file}.new" "${file}"
}
SH
cat >"${TEST_ROOT}/bin/iptables" <<'SH'
#!/usr/bin/env bash
set -eu
source "${0%/*}/common"
printf '%s %s\n' "${0##*/}" "$*" >>"${FAKE_TP_LOG}"
kernel_root=${FAKE_TP_ROOT} point_prefix= on_ip=0.0.0.0
if [[ "${0##*/}" == ip6tables ]]; then
    kernel_root=${FAKE_TP_ROOT}/ipv6 point_prefix=ipv6- on_ip=::
fi
args=("$@")
while [[ "${1:-}" == -w || "${1:-}" == -t || "${1:-}" == -n ]]; do
    if [[ "$1" == -t ]]; then [[ "$2" == mangle ]]; shift 2; else shift; fi
done
action=${1:-}
chain=${2:-}
case "${action}" in
-j) [[ "$*" == '-j TPROXY -h' || "$*" == '-j MARK -h' ]] ;;
-m) [[ "$*" == '-m owner -h' || "$*" == '-m conntrack -h' ]] ;;
-L)
    [[ -z "${chain}" ]] || grep -qxF -- "${chain}" "${kernel_root}/chains"
    ;;
-S)
    if [[ -n "${chain}" ]]; then
        grep -qxF -- "${chain}" "${kernel_root}/chains" || exit 1
    fi
    while IFS= read -r current; do
        [[ -z "${chain}" || "${chain}" == "${current}" ]] || continue
        if [[ "${current}" == PREROUTING || "${current}" == OUTPUT ]]; then printf -- '-P %s ACCEPT\n' "${current}"
        else printf -- '-N %s\n' "${current}"; fi
        while IFS= read -r rule; do
            [[ -n "${rule}" ]] || continue
            shown=${rule}
            if [[ "${shown}" == *' -j TPROXY '* ]]; then
                [[ "${shown}" == *' --on-ip '* ]] ||
                    shown=${shown/' --on-port '/" --on-ip ${on_ip} --on-port "}
                if [[ "${shown}" =~ --tproxy-mark[[:space:]]+([^[:space:]]+) ]]; then
                    original_mark=${BASH_REMATCH[1]}
                    canonical_mark=$(printf '0x%x/0xffffffff' "$(( ${original_mark%/*} ))")
                    shown=${shown/"${original_mark}"/"${canonical_mark}"}
                fi
            fi
            if [[ "${shown}" =~ --set-xmark[[:space:]]+([^[:space:]]+) ]]; then
                original_mark=${BASH_REMATCH[1]}
                canonical_mark=$(printf '0x%x/0xffffffff' "$(( ${original_mark%/*} ))")
                shown=${shown/"${original_mark}"/"${canonical_mark}"}
            fi
            printf -- '-A %s %s\n' "${current}" "${shown}"
        done <"${kernel_root}/${current}.rules"
    done <"${kernel_root}/chains"
    ;;
-C)
    shift 2
    [[ -f "${kernel_root}/${chain}.rules" ]] &&
        grep -qxF -- "$*" "${kernel_root}/${chain}.rules"
    ;;
-N)
    record_write "$@"
    point=start-chain
    [[ "${chain}" != *-out ]] || point=start-output-chain
    inject_failure "${point}"
    ! grep -qxF -- "${chain}" "${kernel_root}/chains" || exit 1
    printf '%s\n' "${chain}" >>"${kernel_root}/chains"
    : >"${kernel_root}/${chain}.rules"
    inject_signal "${point}"
    ;;
-A|-I)
    record_write "$@"
    shift 2
    [[ "${action}" != -I || "${1:-}" != 1 ]] || shift
    point=start-hook
    if [[ "${chain}" == OUTPUT ]]; then
        point=start-output-hook
    elif [[ "${chain}" != PREROUTING ]]; then
        count=$(wc -l <"${kernel_root}/${chain}.rules")
        point="start-chain-$((count+1))"
        [[ "${chain}" != *-out ]] || point="start-output-$((count+1))"
    fi
    inject_failure "${point}"
    printf '%s\n' "$*" >>"${kernel_root}/${chain}.rules"
    inject_signal "${point}"
    ;;
-D)
    record_write "$@"
    point=cleanup-chain
    [[ "${chain}" != *-out && "${chain}" != OUTPUT ]] || point=cleanup-output
    inject_failure "${point}"
    shift 2
    remove_line "${kernel_root}/${chain}.rules" "$*"
    ;;
-X)
    record_write "$@"
    inject_failure cleanup-delete-chain
    [[ ! -s "${kernel_root}/${chain}.rules" ]] || exit 1
    ! grep -Eq -- "(^| )-j ${chain}( |$)" "${kernel_root}/"*.rules || exit 1
    remove_line "${kernel_root}/chains" "${chain}"
    rm -f -- "${kernel_root}/${chain}.rules"
    ;;
-F) record_write "$@"; exit 99 ;;
*) exit 98 ;;
esac
SH
ln -s iptables "${TEST_ROOT}/bin/ip6tables"
cat >"${TEST_ROOT}/bin/ip" <<'SH'
#!/usr/bin/env bash
set -eu
source "${0%/*}/common"
printf 'ip %s\n' "$*" >>"${FAKE_TP_LOG}"
version=4
while [[ "${1:-}" == -j || "${1:-}" == -N || "${1:-}" == -4 || "${1:-}" == -6 || "${1:-}" == -o ]]; do
    [[ "$1" != -6 ]] || version=6
    shift
done
kernel_root=${FAKE_TP_ROOT} point_prefix=
if [[ "${version}" == 6 ]]; then
    kernel_root=${FAKE_TP_ROOT}/ipv6 point_prefix=ipv6-
fi
kind=${1:-} action=${2:-}
shift 2
args=("$@")
case "${kind}:${action}" in
rule:show) cat "${kernel_root}/rules.json" ;;
route:show)
    table=$(field table)
    if [[ -f "${kernel_root}/routes.${table}.json" ]]; then
        cat "${kernel_root}/routes.${table}.json"
    else printf '[]\n'; fi
    ;;
rule:add|rule:del)
    pref=$(field pref || field priority)
    mark=$(field fwmark)
    table=$(field lookup || field table)
    protocol=$(field protocol || field proto)
    [[ "${mark#*/}" == 0xffffffff ]] || exit 2
    value=$(jq -nc --argjson priority "${pref}" --arg fwmark "$(printf '0x%x' "$(( ${mark%/*} ))")" \
        --arg table "${table}" --arg protocol "${protocol}" \
        '{priority:$priority,src:"all",fwmark:$fwmark,table:$table,protocol:$protocol}')
    file="${kernel_root}/rules.json"
    point=start-rule
    [[ "${action}" != del ]] || point=cleanup-rule
    record_write "${kind}" "${action}" "$@"
    inject_failure "${point}"
    if [[ "${action}" == add ]]; then
        jq -e --argjson value "${value}" 'all(.[]; .priority != $value.priority)' "${file}" >/dev/null
        jq --argjson value "${value}" '. + [$value]' "${file}" >"${file}.new"
    else
        jq -e --argjson value "${value}" 'index($value) != null' "${file}" >/dev/null
        jq --argjson value "${value}" 'map(select(. != $value))' "${file}" >"${file}.new"
    fi
    command -p mv -- "${file}.new" "${file}"
    inject_signal "${point}"
    ;;
route:add|route:del)
    [[ "${1:-}" == local ]] || exit 2
    table=$(field table)
    protocol=$(field proto || field protocol)
    if [[ "${version}" == 4 ]]; then
        [[ "${2:-}" == 0.0.0.0/0 ]] || exit 2
        realm=$(field realm || field realms)
        value=$(jq -nc --arg protocol "${protocol}" --arg realm "${realm}" \
            '{type:"2",dst:"default",dev:"lo",protocol:$protocol,scope:"254",flow:{to:$realm},flags:[]}')
    else
        [[ "${2:-}" == ::/0 ]] || exit 2
        metric=$(field metric)
        value=$(jq -nc --arg protocol "${protocol}" --argjson metric "${metric}" \
            '{type:"2",dst:"default",dev:"lo",protocol:$protocol,metric:$metric,flags:[],pref:"medium"}')
    fi
    file="${kernel_root}/routes.${table}.json"
    [[ -f "${file}" ]] || printf '[]\n' >"${file}"
    point=start-route
    [[ "${action}" != del ]] || point=cleanup-route
    record_write "${kind}" "${action}" "$@"
    inject_failure "${point}"
    if [[ "${action}" == add ]]; then
        jq -e --argjson value "${value}" 'index($value) == null' "${file}" >/dev/null
        jq --argjson value "${value}" '. + [$value]' "${file}" >"${file}.new"
    else
        jq -e --argjson value "${value}" 'index($value) != null' "${file}" >/dev/null
        jq --argjson value "${value}" 'map(select(. != $value))' "${file}" >"${file}.new"
    fi
    command -p mv -- "${file}.new" "${file}"
    inject_signal "${point}"
    ;;
route:flush|rule:flush) record_write "${kind}" "${action}" "$@"; exit 99 ;;
*) exit 98 ;;
esac
SH
cat >"${TEST_ROOT}/bin/mv" <<'SH'
#!/usr/bin/env bash
set -eu
source "${0%/*}/common"
target=${!#}
if [[ "${target}" == "${FAKE_TP_STATE}/tproxy.state" ]]; then
    inject_failure state-write
    command -p mv "$@"
    inject_signal state-write
else command -p mv "$@"; fi
SH
cat >"${TEST_ROOT}/bin/cat" <<'SH'
#!/usr/bin/env bash
set -eu
case "$*" in
/proc/sys/net/ipv4/ip_forward) printf '%s\n' "${FAKE_TP_FORWARD:-1}" ;;
/proc/sys/net/ipv6/conf/all/forwarding) printf '%s\n' "${FAKE_TP_FORWARD6:-1}" ;;
*) command -p cat "$@" ;;
esac
SH
cat >"${TEST_ROOT}/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == 86400 ]]; then printf '%s\n' "$$" >>"${FAKE_TP_SLEEP_PIDS}"; fi
exec "$(command -p -v sleep)" "$@"
SH
chmod 0755 "${TEST_ROOT}/bin/"* "${TEST_ROOT}/runner.sh"
export PATH="${TEST_ROOT}/bin:${PATH}" FAKE_TP_SLEEP_PIDS="${TEST_ROOT}/sleep.pids"

call() { env --default-signal=INT --default-signal=TERM sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" "$@"; }
accept() {
    call "$@" >"${TEST_ROOT}/output.log" 2>&1 || fail "unexpected rejection: $*"
}
reject() {
    if call "$@" >"${TEST_ROOT}/output.log" 2>&1; then fail "unexpected acceptance: $*"; fi
}
reset() {
    rm -rf -- "${FAKE_TP_ROOT}" "${FAKE_TP_STATE}"
    mkdir -p "${FAKE_TP_ROOT}/ipv6" "${FAKE_TP_STATE}"
    chmod 0700 "${FAKE_TP_STATE}"
    local kernel_root
    for kernel_root in "${FAKE_TP_ROOT}" "${FAKE_TP_ROOT}/ipv6"; do
        printf 'PREROUTING\nOUTPUT\n' >"${kernel_root}/chains"
        : >"${kernel_root}/PREROUTING.rules"
        : >"${kernel_root}/OUTPUT.rules"
        printf '[]\n' >"${kernel_root}/rules.json"
    done
    : >"${FAKE_TP_LOG}"
    : >"${FAKE_TP_WRITES}"
    : >"${FAKE_TP_SLEEP_PIDS}"
    export FAKE_TP_MODE=ok FAKE_TP_FORWARD=1 FAKE_TP_FORWARD6=1
}
state_value() { sed -n "s/^$1=//p" "${FAKE_TP_STATE}/tproxy.state"; }
seed_owned() {
    local status=0 family=${1:-ipv4} output_uid=${2:-} schema=2 lines=11
    local parameters=("${PORT}" "${MARK}" "${family}")
    [[ -z "${output_uid}" ]] || parameters+=(--output-uid "${output_uid}")
    call seed "${parameters[@]}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
    [[ "${status}" == 137 ]] || fail "seed did not reach active wait: ${status}"
    accept health "${parameters[@]}"
    CHAIN=$(state_value chain)
    TOKEN=$(state_value token)
    PREF=$(state_value pref)
    TABLE=$(state_value table)
    REALM=$(state_value realm)
    [[ "$(stat -c '%u:%a' "${FAKE_TP_STATE}/tproxy.state")" == 0:600 ]] ||
        fail 'state is not root-private'
    if [[ "${family}" != ipv4 ]]; then
        schema=3 lines=12
        [[ "$(state_value family)" == "${family}" ]] || fail 'wrong state family'
    fi
    if [[ -n "${output_uid}" ]]; then
        schema=4 lines=13
        [[ "$(state_value output_uid)" == "${output_uid}" &&
            "$(state_value family)" == "${family}" ]] || fail 'wrong OUTPUT state identity'
    fi
    grep -qx "schema_version=${schema}" "${FAKE_TP_STATE}/tproxy.state" || fail 'wrong state schema'
    [[ "${TOKEN}" =~ ^[a-f0-9]{32}$ && "${CHAIN}" =~ ^padm-tproxy-[a-f0-9]{12}$ ]] ||
        fail 'missing random ownership identity'
    [[ "$(wc -l <"${FAKE_TP_STATE}/tproxy.state")" == "${lines}" &&
        "$(state_value phase)" == active ]] || fail 'state is not canonical active state'
    grep -qx 'route_proto=186' "${FAKE_TP_STATE}/tproxy.state" &&
        grep -qx 'rule_proto=186' "${FAKE_TP_STATE}/tproxy.state" ||
        fail 'route and rule lack an explicit ownership protocol'
    : >"${FAKE_TP_WRITES}"
}
snapshot() {
    tar --sort=name --numeric-owner -cf - -C "${TEST_ROOT}" kernel state | sha256sum
}
reject_unchanged() {
    local before
    before=$(snapshot)
    : >"${FAKE_TP_WRITES}"
    reject "$@"
    [[ ! -s "${FAKE_TP_WRITES}" && "$(snapshot)" == "${before}" ]] ||
        fail "rejected ownership changed kernel objects or state: $*"
}
assert_empty() {
    [[ ! -e "${FAKE_TP_STATE}/tproxy.state" ]] || fail 'successful revoke kept state'
    [[ -z "$(find "${FAKE_TP_STATE}" -mindepth 1 -print -quit)" ]] ||
        fail 'successful revoke leaked a private state candidate'
    local file kernel_root
    for kernel_root in "${FAKE_TP_ROOT}" "${FAKE_TP_ROOT}/ipv6"; do
        [[ "$(<"${kernel_root}/chains")" == $'PREROUTING\nOUTPUT' &&
            ! -s "${kernel_root}/PREROUTING.rules" &&
            ! -s "${kernel_root}/OUTPUT.rules" ]] || fail 'owned firewall resources survived revoke'
        jq -e 'length == 0' "${kernel_root}/rules.json" >/dev/null ||
            fail 'owned policy rule survived revoke'
        for file in "${kernel_root}/routes."*.json; do
            [[ ! -f "${file}" ]] || jq -e 'length == 0' "${file}" >/dev/null ||
                fail 'owned route survived revoke'
        done
    done
    ! grep -Eq '^ip(6)?tables .* -F( |$)|^ip .* (rule|route) flush( |$)' "${FAKE_TP_LOG}" ||
        fail 'cleanup used a broad flush'
}

reset
seed_owned
reject_unchanged cleanup 00000000000000000000000000000000
accept preflight "${PORT}" "${MARK}" owned
accept cleanup
assert_empty

# 畸形或不私有的标记不能冒充归属，更不能被当作 shell 执行。
for bad in schema token chain port mark table pref route-proto rule-proto realm phase \
    duplicate unknown shell wide-state state-symlink state-hardlink wrong-owner wide-root root-symlink; do
    reset
    seed_owned
    state="${FAKE_TP_STATE}/tproxy.state"
    case "${bad}" in
    schema) sed -i 's/^schema_version=.*/schema_version=1/' "${state}" ;;
    token) sed -i 's/^token=.*/token=not-a-token/' "${state}" ;;
    chain) sed -i 's/^chain=.*/chain=padm-tproxy/' "${state}" ;;
    port) sed -i 's/^port=.*/port=0/' "${state}" ;;
    mark) sed -i 's/^mark=.*/mark=-1/' "${state}" ;;
    table) sed -i 's/^table=.*/table=999/' "${state}" ;;
    pref) sed -i 's/^pref=.*/pref=0/' "${state}" ;;
    route-proto) sed -i 's/^route_proto=.*/route_proto=3/' "${state}" ;;
    rule-proto) sed -i 's/^rule_proto=.*/rule_proto=3/' "${state}" ;;
    realm) sed -i 's/^realm=.*/realm=0/' "${state}" ;;
    phase) sed -i 's/^phase=.*/phase=unknown/' "${state}" ;;
    duplicate) printf 'mark=%s\n' "${MARK}" >>"${state}" ;;
    unknown) printf 'foreign=value\n' >>"${state}" ;;
    shell) printf 'touch "%s"\n' "${TEST_ROOT}/executed-marker" >>"${state}" ;;
    wide-state) chmod 0644 "${state}" ;;
    state-symlink)
        cp -p -- "${state}" "${TEST_ROOT}/outside-state"
        rm -f -- "${state}"
        ln -s "${TEST_ROOT}/outside-state" "${state}"
        ;;
    state-hardlink) ln -- "${state}" "${TEST_ROOT}/hardlinked-state" ;;
    wrong-owner) chown 65534 "${state}" ;;
    wide-root) chmod 0777 "${FAKE_TP_STATE}" ;;
    root-symlink)
        mv -- "${FAKE_TP_STATE}" "${TEST_ROOT}/outside-root"
        ln -s "${TEST_ROOT}/outside-root" "${FAKE_TP_STATE}"
        ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}"
    reject_unchanged cleanup
    reject_unchanged run-once "${PORT}" "${MARK}"
    [[ ! -e "${TEST_ROOT}/executed-marker" ]] || fail 'state was executed as shell code'
    [[ "${bad}" != root-symlink ]] || rm -rf -- "${TEST_ROOT}/outside-root"
    [[ "${bad}" != state-hardlink ]] || rm -f -- "${TEST_ROOT}/hardlinked-state"
done

# 同名对象、额外引用和任一运行态字段漂移都不能被宽泛删除。
for drift in chain-token chain-order chain-extra chain-reference chain-goto hook-token hook-duplicate \
    rule-mark rule-mask rule-table rule-pref rule-proto route-proto route-realm route-dev route-type route-extra; do
    reset
    seed_owned
    case "${drift}" in
    chain-token) sed -i "s/${TOKEN}/00000000000000000000000000000000/g" "${FAKE_TP_ROOT}/${CHAIN}.rules" ;;
    chain-order)
        awk 'NR==1 {first=$0; next} NR==2 {print; print first; next} {print}' \
            "${FAKE_TP_ROOT}/${CHAIN}.rules" >"${TEST_ROOT}/changed-rules"
        mv -- "${TEST_ROOT}/changed-rules" "${FAKE_TP_ROOT}/${CHAIN}.rules"
        ;;
    chain-extra) printf '%s\n' '-m comment --comment outside-owner -j RETURN' >>"${FAKE_TP_ROOT}/${CHAIN}.rules" ;;
    chain-reference|chain-goto)
        printf 'outside-chain\n' >>"${FAKE_TP_ROOT}/chains"
        option=-j
        [[ "${drift}" != chain-goto ]] || option=-g
        printf -- '%s %s\n' "${option}" "${CHAIN}" >"${FAKE_TP_ROOT}/outside-chain.rules"
        ;;
    hook-token) sed -i "s/${TOKEN}/00000000000000000000000000000000/g" "${FAKE_TP_ROOT}/PREROUTING.rules" ;;
    hook-duplicate)
        cp -- "${FAKE_TP_ROOT}/PREROUTING.rules" "${TEST_ROOT}/duplicate-hook"
        cat "${TEST_ROOT}/duplicate-hook" >>"${FAKE_TP_ROOT}/PREROUTING.rules"
        rm -f "${TEST_ROOT}/duplicate-hook"
        ;;
    rule-mark) jq '.[0].fwmark = "0x82"' "${FAKE_TP_ROOT}/rules.json" >"${TEST_ROOT}/changed.json" ;;
    rule-mask) jq '.[0].fwmask = "0xff"' "${FAKE_TP_ROOT}/rules.json" >"${TEST_ROOT}/changed.json" ;;
    rule-table) jq '.[0].table = "999"' "${FAKE_TP_ROOT}/rules.json" >"${TEST_ROOT}/changed.json" ;;
    rule-pref) jq '.[0].priority += 1' "${FAKE_TP_ROOT}/rules.json" >"${TEST_ROOT}/changed.json" ;;
    rule-proto) jq '.[0].protocol = "3"' "${FAKE_TP_ROOT}/rules.json" >"${TEST_ROOT}/changed.json" ;;
    route-proto) jq '.[0].protocol = "3"' "${FAKE_TP_ROOT}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json" ;;
    route-realm) jq '.[0].flow.to = "0"' "${FAKE_TP_ROOT}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json" ;;
    route-dev) jq '.[0].dev = "eth0"' "${FAKE_TP_ROOT}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json" ;;
    route-type) jq '.[0].type = "1"' "${FAKE_TP_ROOT}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json" ;;
    route-extra) jq '. + [{dst:"203.0.113.0/24",dev:"eth0",protocol:"3",scope:"0",flags:[]}]' \
        "${FAKE_TP_ROOT}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json" ;;
    esac
    case "${drift}" in
    rule-*) mv -- "${TEST_ROOT}/changed.json" "${FAKE_TP_ROOT}/rules.json" ;;
    route-*) mv -- "${TEST_ROOT}/changed.json" "${FAKE_TP_ROOT}/routes.${TABLE}.json" ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}"
    reject_unchanged cleanup
    reject_unchanged run-once "${PORT}" "${MARK}"
done

for conflict in orphan-chain legacy-chain legacy-state external-rule masked-rule not-rule external-route; do
    reset
    case "${conflict}" in
    orphan-chain)
        printf 'padm-tproxy-ffffffffffff\n' >>"${FAKE_TP_ROOT}/chains"
        : >"${FAKE_TP_ROOT}/padm-tproxy-ffffffffffff.rules"
        ;;
    legacy-chain|legacy-state)
        printf 'padm-tproxy\n' >>"${FAKE_TP_ROOT}/chains"
        printf '%s\n' '-j RETURN' >"${FAKE_TP_ROOT}/padm-tproxy.rules"
        printf '%s\n' '-j padm-tproxy' >"${FAKE_TP_ROOT}/PREROUTING.rules"
        if [[ "${conflict}" == legacy-state ]]; then
            printf 'port=%s\nmark=%s\n' "${PORT}" "${MARK}" >"${FAKE_TP_STATE}/tproxy.state"
            chmod 0600 "${FAKE_TP_STATE}/tproxy.state"
        fi
        ;;
    external-rule)
        printf '[{"priority":1234,"src":"all","fwmark":"0x81","table":"999","protocol":"3"}]\n' \
            >"${FAKE_TP_ROOT}/rules.json"
        ;;
    masked-rule)
        printf '[{"priority":1234,"src":"all","fwmark":"0x181","fwmask":"0xff","table":"999","protocol":"3"}]\n' \
            >"${FAKE_TP_ROOT}/rules.json"
        ;;
    not-rule)
        printf '[{"priority":1234,"src":"all","not":null,"fwmark":"0x2","fwmask":"0xff","table":"999","protocol":"3"}]\n' \
            >"${FAKE_TP_ROOT}/rules.json"
        ;;
    external-route)
        printf '[{"dst":"203.0.113.0/24","dev":"eth0","protocol":"3","scope":"0","flags":[]}]\n' \
            >"${FAKE_TP_ROOT}/routes.${MARK}.json"
        ;;
    esac
    reject_unchanged preflight "${PORT}" "${MARK}" unowned
    reject_unchanged run-once "${PORT}" "${MARK}"
done
reset
printf 'port=%s\nmark=%s\n' "${PORT}" "${MARK}" >"${FAKE_TP_STATE}/tproxy.state"
chmod 0600 "${FAKE_TP_STATE}/tproxy.state"
reject_unchanged cleanup

# 无关链、策略规则与其它表的路由从启动到撤销都保持不变。
reset
printf 'outside-chain\n' >>"${FAKE_TP_ROOT}/chains"
printf '%s\n' '-m comment --comment outside-owner -j RETURN' >"${FAKE_TP_ROOT}/outside-chain.rules"
printf '%s\n' '-m comment --comment outside-owner -j outside-chain' >"${FAKE_TP_ROOT}/PREROUTING.rules"
printf '[{"priority":1234,"src":"all","fwmark":"0x3e7","table":"999","protocol":"3"}]\n' \
    >"${FAKE_TP_ROOT}/rules.json"
printf '[{"dst":"203.0.113.0/24","dev":"eth0","protocol":"3","scope":"0","flags":[]}]\n' \
    >"${FAKE_TP_ROOT}/routes.999.json"
FOREIGN_RULES=$(<"${FAKE_TP_ROOT}/rules.json")
FOREIGN_ROUTES=$(<"${FAKE_TP_ROOT}/routes.999.json")
accept run-once "${PORT}" "${MARK}"
[[ "$(<"${FAKE_TP_ROOT}/chains")" == $'PREROUTING\nOUTPUT\noutside-chain' &&
    "$(<"${FAKE_TP_ROOT}/outside-chain.rules")" == '-m comment --comment outside-owner -j RETURN' &&
    "$(<"${FAKE_TP_ROOT}/PREROUTING.rules")" == '-m comment --comment outside-owner -j outside-chain' ]] ||
    fail 'successful revoke modified external firewall objects'
jq -en --argjson expected "${FOREIGN_RULES}" --slurpfile actual "${FAKE_TP_ROOT}/rules.json" \
    '$actual[0] == $expected' >/dev/null || fail 'successful revoke removed an external policy rule'
jq -en --argjson expected "${FOREIGN_ROUTES}" --slurpfile actual "${FAKE_TP_ROOT}/routes.999.json" \
    '$actual[0] == $expected' >/dev/null || fail 'successful revoke removed an external route'
[[ ! -e "${FAKE_TP_STATE}/tproxy.state" ]] || fail 'successful revoke retained state'

for point in start-route start-rule start-chain start-chain-1 start-chain-2 start-chain-3 start-hook state-write; do
    reset
    export FAKE_TP_MODE="fail-${point}"
    reject run-once "${PORT}" "${MARK}"
    [[ -e "${FAKE_TP_ROOT}/failed-once" ]] || fail "failure fixture did not reach ${point}"
    assert_empty
done

# 删除中途失败留证据；空链已失去 token，跨进程重试不能猜测归属。
for point in cleanup-chain cleanup-delete-chain cleanup-rule cleanup-route; do
    reset
    seed_owned
    export FAKE_TP_MODE="fail-${point}"
    reject cleanup
    [[ -e "${FAKE_TP_ROOT}/failed-once" && -f "${FAKE_TP_STATE}/tproxy.state" ]] ||
        fail "${point} discarded recovery state"
    export FAKE_TP_MODE=ok
    if [[ "${point}" == cleanup-delete-chain ]]; then
        [[ ! -s "${FAKE_TP_ROOT}/${CHAIN}.rules" ]] || fail 'delete-chain failure did not leave an empty chain'
        reject_unchanged cleanup
    else
        accept cleanup
        assert_empty
    fi
done
for missing in chain-rule hook rule route; do
    reset
    seed_owned
    case "${missing}" in
    chain-rule) sed -i '1d' "${FAKE_TP_ROOT}/${CHAIN}.rules" ;;
    hook) : >"${FAKE_TP_ROOT}/PREROUTING.rules" ;;
    rule) printf '[]\n' >"${FAKE_TP_ROOT}/rules.json" ;;
    route) printf '[]\n' >"${FAKE_TP_ROOT}/routes.${TABLE}.json" ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}"
    accept cleanup
    assert_empty
done

# 启动窗口被强杀后留下的空链没有跨进程归属证明。
reset
export FAKE_TP_MODE=signal-start-chain FAKE_TP_SIGNAL=KILL
status=0
call run-once "${PORT}" "${MARK}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
[[ "${status}" == 137 && -e "${FAKE_TP_ROOT}/signaled-once" ]] ||
    fail 'start-chain KILL did not interrupt runtime'
CHAIN=$(state_value chain)
[[ "$(state_value phase)" == intent &&
    -f "${FAKE_TP_ROOT}/${CHAIN}.rules" && ! -s "${FAKE_TP_ROOT}/${CHAIN}.rules" ]] ||
    fail 'start-chain KILL did not preserve empty-chain intent'
export FAKE_TP_MODE=ok
reject_unchanged cleanup
reject_unchanged run-once "${PORT}" "${MARK}"

# active 标记也不能证明一个已失去 token 的空链仍属本进程。
reset
seed_owned
: >"${FAKE_TP_ROOT}/${CHAIN}.rules"
reject_unchanged health "${PORT}" "${MARK}"
reject_unchanged cleanup
reject_unchanged run-once "${PORT}" "${MARK}"

# 候选只读取旧运行态归属，不把 marker 复制进自己的 state 目录。
reset
seed_owned
LIVE_STATE=${FAKE_TP_STATE}
LIVE_HASH=$(snapshot)
export FAKE_TP_STATE="${TEST_ROOT}/candidate-state"
mkdir -m 0700 "${FAKE_TP_STATE}"
reject preflight "${PORT}" "${MARK}" owned
accept preflight "$((PORT+1))" "${MARK}" owned "${LIVE_STATE}"
[[ ! -e "${FAKE_TP_STATE}/tproxy.state" && "$(snapshot)" == "${LIVE_HASH}" ]] ||
    fail 'candidate preflight modified or copied live ownership'
export FAKE_TP_STATE=${LIVE_STATE}
accept cleanup
assert_empty

for signal in TERM INT; do
    for point in start-route start-rule start-chain start-chain-1 start-chain-2 start-chain-3 start-hook state-write; do
        reset
        export FAKE_TP_MODE="signal-${point}" FAKE_TP_SIGNAL="${signal}"
        status=0
        call run-once "${PORT}" "${MARK}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" &&
            -e "${FAKE_TP_ROOT}/signaled-once" ]] || fail "${point} ${signal} did not propagate its signal"
        assert_empty
    done
    reset
    export FAKE_TP_SIGNAL="${signal}"
    env --default-signal=INT --default-signal=TERM sh "${TEST_ROOT}/runner.sh" \
        "${TEST_ROOT}/functions.sh" run-wait "${PORT}" "${MARK}" >"${TEST_ROOT}/output.log" 2>&1 &
    RUN_PID=$!
    ready=false
    for ((attempt=0; attempt<200; attempt++)); do
        if [[ -f "${FAKE_TP_STATE}/tproxy.state" ]] &&
            grep -qx 'phase=active' "${FAKE_TP_STATE}/tproxy.state"; then
            ready=true
            break
        fi
        kill -0 "${RUN_PID}" 2>/dev/null || break
        sleep 0.025
    done
    [[ "${ready}" == true ]] || fail "runtime did not become active before ${signal}"
    accept health "${PORT}" "${MARK}"
    kill "-${signal}" "${RUN_PID}"
    status=0
    wait "${RUN_PID}" || status=$?
    RUN_PID=
    [[ "${status}" == 0 || "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]] ||
        fail "runtime ${signal} returned ${status}"
    while IFS= read -r pid; do
        ! kill -0 "${pid}" 2>/dev/null || fail "wait child ${pid} survived ${signal}"
    done <"${FAKE_TP_SLEEP_PIDS}"
    assert_empty
done

# IPv6 与双栈均使用同一 owner，schema 2 的 IPv4 格式仍由旧用例约束。
for family in ipv6 dual; do
    reset
    seed_owned "${family}"
    [[ -s "${FAKE_TP_ROOT}/ipv6/${CHAIN}.rules" &&
        -s "${FAKE_TP_ROOT}/ipv6/PREROUTING.rules" ]] || fail 'IPv6 firewall resources were not created'
    jq -e --argjson metric "${REALM}" \
        'length == 1 and .[0] == {type:"2",dst:"default",dev:"lo",protocol:"186",metric:$metric,flags:[],pref:"medium"}' \
        "${FAKE_TP_ROOT}/ipv6/routes.${MARK}.json" >/dev/null || fail 'IPv6 route lacks its exact metric'
    reject_unchanged health "${PORT}" "${MARK}" ipv4
    if [[ "${family}" == ipv6 ]]; then
        [[ "$(<"${FAKE_TP_ROOT}/chains")" == $'PREROUTING\nOUTPUT' &&
            ! -s "${FAKE_TP_ROOT}/PREROUTING.rules" ]] || fail 'IPv6-only startup touched IPv4 firewall resources'
        jq -e 'length == 0' "${FAKE_TP_ROOT}/rules.json" >/dev/null ||
            fail 'IPv6-only startup touched IPv4 policy rules'
    else
        [[ -s "${FAKE_TP_ROOT}/${CHAIN}.rules" ]] || fail 'dual startup omitted IPv4 firewall resources'
    fi
    accept cleanup "${TOKEN}"
    assert_empty
done

# 第二族任一步骤失败或收到信号，第一族已创建的对象也必须精确撤销。
for point in start-route start-chain start-hook; do
    reset
    export FAKE_TP_MODE="fail-ipv6-${point}"
    reject run-once "${PORT}" "${MARK}" dual
    [[ -e "${FAKE_TP_ROOT}/failed-once" ]] || fail "IPv6 failure fixture did not reach ${point}"
    assert_empty
done
for signal in TERM INT; do
    for point in start-route start-chain start-hook; do
        reset
        export FAKE_TP_MODE="signal-ipv6-${point}" FAKE_TP_SIGNAL="${signal}"
        status=0
        call run-once "${PORT}" "${MARK}" dual >"${TEST_ROOT}/output.log" 2>&1 || status=$?
        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" &&
            -e "${FAKE_TP_ROOT}/signaled-once" ]] || fail "IPv6 ${point} ${signal} did not propagate its signal"
        assert_empty
    done
done

# 先整体审计两族；后一族漂移也不能留下前一族已经被清理的半成品。
for family in ipv4 ipv6; do
    for drift in chain-token route-identity; do
        reset
        seed_owned dual
        kernel_root=${FAKE_TP_ROOT}
        [[ "${family}" != ipv6 ]] || kernel_root=${FAKE_TP_ROOT}/ipv6
        if [[ "${drift}" == chain-token ]]; then
            sed -i "s/${TOKEN}/00000000000000000000000000000000/g" "${kernel_root}/${CHAIN}.rules"
        else
            field=flow.to
            [[ "${family}" != ipv6 ]] || field=metric
            jq ".[] |= (.${field} = 0)" "${kernel_root}/routes.${TABLE}.json" >"${TEST_ROOT}/changed.json"
            mv -- "${TEST_ROOT}/changed.json" "${kernel_root}/routes.${TABLE}.json"
        fi
        reject_unchanged health "${PORT}" "${MARK}" dual
        reject_unchanged cleanup
        reject_unchanged run-once "${PORT}" "${MARK}" dual
    done
done
reset
seed_owned dual
printf '[]\n' >"${FAKE_TP_ROOT}/ipv6/rules.json"
reject_unchanged health "${PORT}" "${MARK}" dual
accept cleanup
assert_empty

# schema 2 旧 owner 升双栈：候选只读两族，运行入口先撤销再生成新 owner。
reset
seed_owned
OLD_TOKEN=${TOKEN} OLD_CHAIN=${CHAIN}
LIVE_STATE=${FAKE_TP_STATE}
LIVE_HASH=$(snapshot)
export FAKE_TP_STATE="${TEST_ROOT}/candidate-dual"
mkdir -m 0700 "${FAKE_TP_STATE}"
accept preflight "$((PORT+1))" "${MARK}" dual owned "${LIVE_STATE}"
[[ ! -e "${FAKE_TP_STATE}/tproxy.state" && ! -s "${FAKE_TP_WRITES}" &&
    "$(snapshot)" == "${LIVE_HASH}" ]] || fail 'dual candidate preflight modified or copied its IPv4 owner'
export FAKE_TP_STATE=${LIVE_STATE}
seed_owned dual
[[ "${TOKEN}" != "${OLD_TOKEN}" && "${CHAIN}" != "${OLD_CHAIN}" &&
    ! -e "${FAKE_TP_ROOT}/${OLD_CHAIN}.rules" ]] || fail 'dual migration reused or retained its old owner'
accept cleanup
assert_empty

# 新增族的候选 mark 已被外部使用时，旧 IPv4 owner 也不能先撤销。
reset
seed_owned
NEXT_MARK=$((MARK+1))
printf '[{"priority":1234,"src":"all","fwmark":"0x%x","table":"999","protocol":"3"}]\n' \
    "${NEXT_MARK}" >"${FAKE_TP_ROOT}/ipv6/rules.json"
reject_unchanged preflight "${PORT}" "${NEXT_MARK}" dual owned
reject_unchanged run-once "${PORT}" "${NEXT_MARK}" dual

reset
export FAKE_TP_FORWARD6=0
reject_unchanged preflight "${PORT}" "${MARK}" ipv6 unowned
reject_unchanged preflight "${PORT}" "${MARK}" dual unowned
reject_unchanged run-once "${PORT}" "${MARK}" dual
for family in invalid IPv6 all; do
    reset
    reject_unchanged preflight "${PORT}" "${MARK}" "${family}" unowned
    reject_unchanged run-once "${PORT}" "${MARK}" "${family}"
done

# family 与 schema 必须共同匹配固定字节格式，未知或缺失字段不能授权清理。
for bad in unknown duplicate missing schema ipv4; do
    reset
    seed_owned dual
    state="${FAKE_TP_STATE}/tproxy.state"
    case "${bad}" in
    unknown) sed -i 's/^family=.*/family=unknown/' "${state}" ;;
    duplicate) printf 'family=dual\n' >>"${state}" ;;
    missing) sed -i '/^family=/d' "${state}" ;;
    schema) sed -i 's/^schema_version=.*/schema_version=2/' "${state}" ;;
    ipv4) sed -i 's/^family=.*/family=ipv4/' "${state}" ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}" dual
    reject_unchanged cleanup
    reject_unchanged run-once "${PORT}" "${MARK}" dual
done

# OUTPUT 单 UID 与旧 PREROUTING 共存；旧 schema 不添加新字段。
OUTPUT_UID=65534
for family in ipv4 ipv6 dual; do
    reset
    seed_owned "${family}" "${OUTPUT_UID}"
    versions='4 6'
    [[ "${family}" != ipv4 ]] || versions=4
    [[ "${family}" != ipv6 ]] || versions=6
    for version in ${versions}; do
        kernel_root=${FAKE_TP_ROOT}
        [[ "${version}" != 6 ]] || kernel_root=${FAKE_TP_ROOT}/ipv6
        [[ -s "${kernel_root}/${CHAIN}-out.rules" &&
            -s "${kernel_root}/OUTPUT.rules" &&
            "$(wc -l <"${kernel_root}/${CHAIN}-out.rules")" == 3 ]] ||
            fail 'OUTPUT firewall resources were not created'
        grep -q -- "--uid-owner ${OUTPUT_UID} -m conntrack --ctdir ORIGINAL .* -j MARK" \
            "${kernel_root}/${CHAIN}-out.rules" || fail 'OUTPUT capture lacks UID or ORIGINAL direction'
    done
    reject_unchanged health "${PORT}" "${MARK}" "${family}"
    reject_unchanged health "${PORT}" "${MARK}" "${family}" --output-uid 65533
    accept cleanup
    assert_empty
done

for uid in 0 10001 065534 -1 2147483648 invalid ''; do
    reset
    reject_unchanged preflight "${PORT}" "${MARK}" dual --output-uid "${uid}" unowned
    reject_unchanged run-once "${PORT}" "${MARK}" dual --output-uid "${uid}"
done
reset
accept run-once "${PORT}" "${MARK}" --output-uid 2147483647
assert_empty

# 新 state 的 UID、family、schema 必须共同匹配；候选只读旧 owner。
for bad in uid reserved duplicate missing family schema; do
    reset
    seed_owned dual "${OUTPUT_UID}"
    state="${FAKE_TP_STATE}/tproxy.state"
    case "${bad}" in
    uid) sed -i 's/^output_uid=.*/output_uid=0/' "${state}" ;;
    reserved) sed -i 's/^output_uid=.*/output_uid=10001/' "${state}" ;;
    duplicate) printf 'output_uid=65534\n' >>"${state}" ;;
    missing) sed -i '/^output_uid=/d' "${state}" ;;
    family) sed -i '/^family=/d' "${state}" ;;
    schema) sed -i 's/^schema_version=.*/schema_version=3/' "${state}" ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}"
    reject_unchanged cleanup
done
reset
seed_owned
OLD_TOKEN=${TOKEN} OLD_CHAIN=${CHAIN}
accept preflight "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}" owned
[[ ! -s "${FAKE_TP_WRITES}" ]] || fail 'OUTPUT candidate modified its old PREROUTING owner'
seed_owned dual "${OUTPUT_UID}"
[[ "${TOKEN}" != "${OLD_TOKEN}" && ! -e "${FAKE_TP_ROOT}/${OLD_CHAIN}.rules" ]] ||
    fail 'OUTPUT migration retained the old PREROUTING chain'
accept preflight "${PORT}" "${MARK}" dual owned
[[ ! -s "${FAKE_TP_WRITES}" ]] || fail 'OUTPUT-off candidate modified its old owner'
accept run-once "${PORT}" "${MARK}" dual
assert_empty

# 后一族 OUTPUT 漂移也不能先撤销前一族或 PREROUTING。
for drift in uid direction mark local order reference hook empty; do
    reset
    seed_owned dual "${OUTPUT_UID}"
    output_rules="${FAKE_TP_ROOT}/ipv6/${CHAIN}-out.rules"
    case "${drift}" in
    uid) sed -i "s/--uid-owner ${OUTPUT_UID}/--uid-owner 65533/g" "${output_rules}" ;;
    direction) sed -i 's/--ctdir ORIGINAL/--ctdir REPLY/g' "${output_rules}" ;;
    mark) sed -i "s/${MARK}\\/0xffffffff/130\\/0xffffffff/g" "${output_rules}" ;;
    local) sed -i 's/--dst-type LOCAL/--dst-type UNICAST/' "${output_rules}" ;;
    order)
        awk 'NR==1 {first=$0; next} NR==2 {print; print first; next} {print}' \
            "${output_rules}" >"${TEST_ROOT}/changed-rules"
        mv -- "${TEST_ROOT}/changed-rules" "${output_rules}"
        ;;
    reference)
        printf 'outside-chain\n' >>"${FAKE_TP_ROOT}/ipv6/chains"
        printf -- '-g %s-out\n' "${CHAIN}" >"${FAKE_TP_ROOT}/ipv6/outside-chain.rules"
        ;;
    hook) sed -i "s/${TOKEN}/00000000000000000000000000000000/g" "${FAKE_TP_ROOT}/ipv6/OUTPUT.rules" ;;
    empty) : >"${output_rules}" ;;
    esac
    reject_unchanged health "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}"
    reject_unchanged cleanup
    reject_unchanged run-once "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}"
done

for point in start-output-chain start-output-1 start-output-2 start-output-3 start-output-hook; do
    reset
    export FAKE_TP_MODE="fail-ipv6-${point}"
    reject run-once "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}"
    [[ -e "${FAKE_TP_ROOT}/failed-once" ]] || fail "OUTPUT failure fixture did not reach ${point}"
    assert_empty
done
for signal in TERM INT; do
    reset
    export FAKE_TP_MODE=signal-ipv6-start-output-chain FAKE_TP_SIGNAL="${signal}"
    status=0
    call run-once "${PORT}" "${MARK}" dual --output-uid "${OUTPUT_UID}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
    [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" &&
        -e "${FAKE_TP_ROOT}/signaled-once" ]] || fail "OUTPUT ${signal} did not interrupt startup"
    assert_empty
done
reset
seed_owned dual "${OUTPUT_UID}"
export FAKE_TP_MODE=fail-ipv6-cleanup-output
reject cleanup
[[ -e "${FAKE_TP_ROOT}/failed-once" && -f "${FAKE_TP_STATE}/tproxy.state" ]] ||
    fail 'partial OUTPUT revoke discarded recovery state'
export FAKE_TP_MODE=ok
accept cleanup
assert_empty
printf 'docker-tproxy-ownership-regression-ok\n'
