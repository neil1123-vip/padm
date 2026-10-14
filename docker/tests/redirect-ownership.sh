#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-redirect-ownership.XXXXXX")
RUN_PID=
cleanup() {
    local status=$?
    if [[ -n "${RUN_PID}" ]]; then
        kill -TERM "${RUN_PID}" 2>/dev/null || true
        wait "${RUN_PID}" 2>/dev/null || true
    fi
    if [[ "${PADM_TEST_KEEP:-0}" == 1 ]]; then
        printf 'redirect-ownership-test-root: %s\n' "${TEST_ROOT}" >&2
    else rm -rf -- "${TEST_ROOT}"; fi
    return "${status}"
}
trap cleanup EXIT
trap 'printf "docker-redirect-ownership-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in python3 stat tar sha256sum; do command -v "${tool}" >/dev/null; done

fail() {
    [[ ! -f "${TEST_ROOT}/output.log" ]] || cat "${TEST_ROOT}/output.log" >&2
    printf 'docker-redirect-ownership-fail: %s\n' "$*" >&2
    exit 1
}
export FAKE_RD_ROOT="${TEST_ROOT}/kernel" FAKE_RD_STATE="${TEST_ROOT}/state"
export FAKE_RD_WRITES="${TEST_ROOT}/writes.log" FAKE_RD_MODE=ok FAKE_RD_SIGNAL=TERM
PORT=31298 OUTPUT_UID=65534
mkdir -p "${TEST_ROOT}/bin"

# 只替换系统命令，固定 state、归属解析和精确撤销执行生产实现。
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$1"
STATE_ROOT=$FAKE_RD_STATE
export FAKE_RD_SERVER_PID=$$
shift
case "$1" in
seed) shift; wait_forever() { kill -KILL "$$"; }; redirect_run "$@" ;;
run-once)
    shift
    health_args="$*"
    wait_forever() { redirect_health $health_args; }
    redirect_run "$@"
    ;;
run-wait) shift; redirect_run "$@" ;;
preflight) shift; redirect_preflight "$@" ;;
health) shift; redirect_health "$@" ;;
cleanup) redirect_cleanup "${2:-}" ;;
tproxy-preflight) shift; tproxy_preflight "$@" ;;
tproxy-cleanup) tproxy_cleanup ;;
*) exit 99 ;;
esac
SH
cat >"${TEST_ROOT}/bin/iptables" <<'PY'
#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shlex
import signal
import sys

root = Path(os.environ["FAKE_RD_ROOT"])
version = "6" if Path(sys.argv[0]).name == "ip6tables" else "4"
path = root / (version + ".json")
args = sys.argv[1:]
while args and args[0] in ("-w", "-t", "-n"):
    if args[0] == "-t":
        assert args[1] == "nat"
        args = args[2:]
    else:
        args = args[1:]
chains = json.loads(path.read_text())
action = args[0]
chain = args[1] if len(args) > 1 else ""
if action in ("-j", "-m"):
    assert args in (["-j", "REDIRECT", "-h"], ["-m", "owner", "-h"], ["-m", "conntrack", "-h"])
    raise SystemExit(0)
if action == "-L":
    raise SystemExit(0 if not chain or chain in chains else 1)
if action == "-S":
    for current, rules in chains.items():
        print(shlex.join(["-P", current, "ACCEPT"] if current in ("PREROUTING", "OUTPUT")
                         else ["-N", current]))
        for rule in rules:
            shown = rule[:]
            if "-p" in shown and shown[shown.index("-p") + 1] == "tcp":
                shown[2:2] = ["-m", "tcp"]
            print(shlex.join(["-A", current] + shown))
    raise SystemExit(0)
with open(os.environ["FAKE_RD_WRITES"], "a") as stream:
    stream.write(f"ipv{version} " + shlex.join(args) + "\n")
point = {
    "-N": "start-output-chain" if chain.endswith("-out") else "start-chain",
    "-X": "cleanup-delete-chain",
    "-D": "cleanup-output" if chain == "OUTPUT" or chain.endswith("-out") else "cleanup-chain",
}.get(action)
if action in ("-A", "-I"):
    if chain in ("PREROUTING", "OUTPUT"):
        point = "start-output-hook" if chain == "OUTPUT" else "start-hook"
    else:
        point = ("start-output-" if chain.endswith("-out") else "start-chain-") + str(len(chains[chain]) + 1)
point = ("ipv6-" if version == "6" else "") + point if point else ""
mode = os.environ["FAKE_RD_MODE"]
if mode == "fail-" + point and not (root / "failed-once").exists():
    (root / "failed-once").touch()
    raise SystemExit(1)
if action == "-N":
    assert chain not in chains and len(chain) <= 28
    chains[chain] = []
elif action in ("-A", "-I"):
    rule = args[2:]
    if action == "-I" and rule[0] == "1":
        rule = rule[1:]
    assert chain in chains
    if action == "-I":
        chains[chain].insert(0, rule)
    else:
        chains[chain].append(rule)
elif action == "-D":
    chains[chain].remove(args[2:])
elif action == "-X":
    assert chain in chains and not chains[chain]
    assert all(chain not in rule for rules in chains.values() for rule in rules)
    del chains[chain]
else:
    raise SystemExit(99)
path.write_text(json.dumps(chains))
if mode == "signal-" + point and not (root / "signaled-once").exists():
    (root / "signaled-once").touch()
    os.kill(int(os.environ["FAKE_RD_SERVER_PID"]), getattr(signal, "SIG" + os.environ["FAKE_RD_SIGNAL"]))
PY
ln -s iptables "${TEST_ROOT}/bin/ip6tables"
cat >"${TEST_ROOT}/bin/mv" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${!#}" == "${FAKE_RD_STATE}/redirect.state" ]]; then
    if [[ "${FAKE_RD_MODE}" == fail-state-write && ! -e "${FAKE_RD_ROOT}/failed-once" ]]; then
        touch "${FAKE_RD_ROOT}/failed-once"; exit 1
    fi
    command -p mv "$@"
    if [[ "${FAKE_RD_MODE}" == signal-state-write && ! -e "${FAKE_RD_ROOT}/signaled-once" ]]; then
        touch "${FAKE_RD_ROOT}/signaled-once"
        kill "-${FAKE_RD_SIGNAL}" "${FAKE_RD_SERVER_PID}"
    fi
else command -p mv "$@"; fi
SH
chmod 0755 "${TEST_ROOT}/bin/"* "${TEST_ROOT}/runner.sh"
export PATH="${TEST_ROOT}/bin:${PATH}"
call() { env --default-signal=INT --default-signal=TERM sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" "$@"; }
accept() { call "$@" >"${TEST_ROOT}/output.log" 2>&1 || fail "unexpected rejection: $*"; }
reject() { if call "$@" >"${TEST_ROOT}/output.log" 2>&1; then fail "unexpected acceptance: $*"; fi; }
reset() {
    rm -rf -- "${FAKE_RD_ROOT}" "${FAKE_RD_STATE}"
    mkdir -p "${FAKE_RD_ROOT}" "${FAKE_RD_STATE}"
    chmod 0700 "${FAKE_RD_STATE}"
    for version in 4 6; do printf '{"PREROUTING":[],"OUTPUT":[]}\n' >"${FAKE_RD_ROOT}/${version}.json"; done
    : >"${FAKE_RD_WRITES}"
    export FAKE_RD_MODE=ok
}
state_value() { sed -n "s/^$1=//p" "${FAKE_RD_STATE}/redirect.state"; }
seed_owned() {
    local status=0 family=${1:-dual} uid=${2-${OUTPUT_UID}} schema=1 args=("${PORT}" "${1:-dual}")
    if [[ "${uid}" == all ]]; then args+=(--output-all); schema=2
    elif [[ -n "${uid}" ]]; then args+=(--output-uid "${uid}"); fi
    call seed "${args[@]}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
    [[ "${status}" == 137 ]] || fail "seed did not reach active wait: ${status}"
    accept health "${args[@]}"
    CHAIN=$(state_value chain) TOKEN=$(state_value token)
    [[ "${CHAIN}" == "padm-redirect-${TOKEN:0:10}" &&
        "${TOKEN}" =~ ^[a-f0-9]{32}$ &&
        "$(state_value family)" == "${family}" &&
        "$(state_value schema_version)" == "${schema}" &&
        "$(state_value output_uid)" == "$([[ "${uid}" == all ]] || printf '%s' "${uid}")" &&
        "$(state_value output_all)" == "$([[ "${uid}" != all ]] || printf true)" &&
        "$(state_value phase)" == active &&
        "$(wc -l <"${FAKE_RD_STATE}/redirect.state")" == 7 &&
        "$(stat -c '%u:%a' "${FAKE_RD_STATE}/redirect.state")" == 0:600 ]] || fail 'wrong state identity'
    : >"${FAKE_RD_WRITES}"
}
snapshot() { tar --sort=name --numeric-owner -cf - -C "${TEST_ROOT}" kernel state | sha256sum; }
reject_unchanged() {
    local before
    before=$(snapshot)
    : >"${FAKE_RD_WRITES}"
    reject "$@"
    [[ ! -s "${FAKE_RD_WRITES}" && "$(snapshot)" == "${before}" ]] || fail "rejection modified resources: $*"
}
assert_empty() {
    [[ -z "$(find "${FAKE_RD_STATE}" -mindepth 1 -print -quit)" ]] || fail 'revoke retained state'
    python3 - "${FAKE_RD_ROOT}" <<'PY'
import json, sys
from pathlib import Path
for version in (4, 6):
    assert json.loads((Path(sys.argv[1]) / f"{version}.json").read_text()) == {"PREROUTING": [], "OUTPUT": []}
PY
    ! grep -Eq -- '(^| )-F( |$)' "${FAKE_RD_WRITES}" || fail 'cleanup used a broad flush'
}
mutate() {
    python3 - "${FAKE_RD_ROOT}/6.json" "${CHAIN}" "${TOKEN}" "$1" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
chain, token, kind = sys.argv[2:]
chains = json.loads(path.read_text())
out = chain + "-out"
if kind == "token":
    chains[chain][0][chains[chain][0].index(token if token in chains[chain][0] else "padm-redirect:" + token)] = "foreign"
elif kind == "uid":
    rule = chains[out][1]; rule[rule.index("--uid-owner") + 1] = "65533"
elif kind == "direction":
    rule = next(rule for rule in chains[out] if "--ctdir" in rule); rule[rule.index("--ctdir") + 1] = "REPLY"
elif kind == "group":
    rule = chains[out][1]; rule[rule.index("--gid-owner") + 1] = "10002"
elif kind == "local":
    rule = chains[out][0]; rule[rule.index("--dst-type") + 1] = "UNICAST"
elif kind == "missing-group":
    del chains[out][1]
elif kind == "missing-local":
    del chains[out][0]
elif kind == "port":
    rule = chains[chain][1]; rule[rule.index("--to-ports") + 1] = "1"
elif kind == "order":
    chains[out].reverse()
elif kind == "reference":
    chains["foreign"] = [["-g", out]]
elif kind == "duplicate":
    chains["OUTPUT"] += chains["OUTPUT"]
elif kind == "extra":
    chains[chain].append(["-j", "RETURN"])
elif kind == "empty":
    chains[out] = []
elif kind == "missing":
    chains[out].pop()
path.write_text(json.dumps(chains))
PY
}

# 三族和 UID 开关共用一组归属规则，UDP 不进入透明链。
for family in ipv4 ipv6 dual; do
    for uid in '' "${OUTPUT_UID}" all; do
        reset
        seed_owned "${family}" "${uid}"
        reject_unchanged cleanup 00000000000000000000000000000000
        reject_unchanged health "${PORT}" "${family}" --output-uid 65533
        accept cleanup "${TOKEN}"
        assert_empty
    done
done
for uid in 0 10001 065534 -1 2147483648 invalid all ''; do
    reset
    reject_unchanged preflight "${PORT}" dual --output-uid "${uid}" unowned
    reject_unchanged run-once "${PORT}" dual --output-uid "${uid}"
done
reset
accept run-once "${PORT}" --output-uid 2147483647
assert_empty
for args in '--output-all --output-uid 65534' '--output-all --output-all'; do
    reset
    read -r -a parameters <<<"${args}"
    reject_unchanged preflight "${PORT}" dual "${parameters[@]}" unowned
    reject_unchanged run-once "${PORT}" dual "${parameters[@]}"
done

# 不安全 state 拒绝读写；后族漂移必须保留前族与全部恢复证据。
for bad in duplicate phase family uid wide-state hardlink symlink nul; do
    reset
    seed_owned
    state="${FAKE_RD_STATE}/redirect.state"
    case "${bad}" in
    duplicate) printf 'port=%s\n' "${PORT}" >>"${state}" ;;
    phase) sed -i 's/^phase=.*/phase=foreign/' "${state}" ;;
    family) sed -i 's/^family=.*/family=foreign/' "${state}" ;;
    uid) sed -i 's/^output_uid=.*/output_uid=0/' "${state}" ;;
    wide-state) chmod 0644 "${state}" ;;
    hardlink) ln "${state}" "${TEST_ROOT}/linked-state" ;;
    symlink) cp -p "${state}" "${TEST_ROOT}/linked-state"; rm "${state}"; ln -s "${TEST_ROOT}/linked-state" "${state}" ;;
    nul) printf '\0' >>"${state}" ;;
    esac
    reject_unchanged cleanup
    reject_unchanged run-once "${PORT}" dual --output-uid "${OUTPUT_UID}"
    rm -f "${TEST_ROOT}/linked-state"
done
for drift in token uid direction port order reference duplicate extra empty; do
    reset
    seed_owned
    mutate "${drift}"
    reject_unchanged health "${PORT}" dual --output-uid "${OUTPUT_UID}"
    reject_unchanged cleanup
    reject_unchanged preflight "${PORT}" dual --output-uid "${OUTPUT_UID}" owned
done
reset
seed_owned
mutate missing
reject_unchanged health "${PORT}" dual --output-uid "${OUTPUT_UID}"
accept cleanup
assert_empty

# 不同透明运行态不能互相授权；孤链不因名称相似而被收回。
reset
printf 'foreign\n' >"${FAKE_RD_STATE}/tproxy.state"
chmod 0600 "${FAKE_RD_STATE}/tproxy.state"
reject_unchanged preflight "${PORT}" dual unowned
reject_unchanged run-once "${PORT}" dual
reset
seed_owned
reject_unchanged tproxy-preflight "${PORT}" 129 dual owned
reject_unchanged tproxy-cleanup
printf 'foreign\n' >"${FAKE_RD_STATE}/tproxy.state"
reject_unchanged cleanup
reset
printf '{"PREROUTING":[],"OUTPUT":[],"padm-redirect-ffffffff":[]}\n' >"${FAKE_RD_ROOT}/4.json"
reject_unchanged preflight "${PORT}" unowned
reset
printf '{"PREROUTING":[["-j","foreign"]],"OUTPUT":[],"foreign":[["-j","RETURN"]]}\n' >"${FAKE_RD_ROOT}/4.json"
accept run-once "${PORT}"
python3 - "${FAKE_RD_ROOT}/4.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1])) == {"PREROUTING": [["-j", "foreign"]],
                                      "OUTPUT": [], "foreign": [["-j", "RETURN"]]}
PY

# 候选只读取旧 owner，切换家族或 UID 后运行入口先收回旧 token。
reset
seed_owned ipv4 ''
OLD_TOKEN=${TOKEN} LIVE_STATE=${FAKE_RD_STATE} BEFORE=$(snapshot)
export FAKE_RD_STATE="${TEST_ROOT}/candidate"
mkdir -m 0700 "${FAKE_RD_STATE}"
accept preflight "$((PORT+1))" dual --output-uid "${OUTPUT_UID}" owned "${LIVE_STATE}"
[[ "$(snapshot)" == "${BEFORE}" && ! -s "${FAKE_RD_WRITES}" &&
    ! -e "${FAKE_RD_STATE}/redirect.state" ]] || fail 'candidate modified live owner'
export FAKE_RD_STATE=${LIVE_STATE}
seed_owned dual
[[ "${TOKEN}" != "${OLD_TOKEN}" ]] || fail 'migration reused owner'
accept run-once "${PORT}" dual
assert_empty

# 初始化每个命令失败和第二族 OUTPUT 失败均要精确恢复。
for point in start-chain start-chain-1 start-chain-2 start-hook state-write \
    ipv6-start-chain ipv6-start-output-chain ipv6-start-output-1 ipv6-start-output-2 ipv6-start-output-hook; do
    reset
    export FAKE_RD_MODE="fail-${point}"
    reject run-once "${PORT}" dual --output-uid "${OUTPUT_UID}"
    [[ -e "${FAKE_RD_ROOT}/failed-once" ]] || fail "failure fixture missed ${point}"
    assert_empty
done
for signal in TERM INT; do
    for point in state-write start-chain ipv6-start-output-chain ipv6-start-output-hook; do
        reset
        export FAKE_RD_MODE="signal-${point}" FAKE_RD_SIGNAL="${signal}"
        status=0
        call run-once "${PORT}" dual --output-uid "${OUTPUT_UID}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" &&
            -e "${FAKE_RD_ROOT}/signaled-once" ]] || fail "signal fixture missed ${point} ${signal}"
        assert_empty
    done
done

# 全局绕过和 ORIGINAL 捕获的顺序属于归属，缺少关键返回规则必须保留所有现场。
for bad in false duplicate mixed missing schema; do
    reset
    seed_owned dual all
    state="${FAKE_RD_STATE}/redirect.state"
    case "${bad}" in
    false) sed -i 's/^output_all=.*/output_all=false/' "${state}" ;;
    duplicate) printf 'output_all=true\n' >>"${state}" ;;
    mixed) printf 'output_uid=65534\n' >>"${state}" ;;
    missing) sed -i '/^output_all=/d' "${state}" ;;
    schema) sed -i 's/^schema_version=.*/schema_version=1/' "${state}" ;;
    esac
    reject_unchanged health "${PORT}" dual --output-all
    reject_unchanged cleanup
done
for drift in group local direction order reference missing-group missing-local; do
    reset
    seed_owned dual all
    mutate "${drift}"
    reject_unchanged health "${PORT}" dual --output-all
    reject_unchanged cleanup
    reject_unchanged preflight "${PORT}" dual --output-all owned
done
reset
seed_owned dual "${OUTPUT_UID}"
OLD_TOKEN=${TOKEN}
accept preflight "${PORT}" dual --output-all owned
[[ ! -s "${FAKE_RD_WRITES}" ]] || fail 'global candidate modified its old UID owner'
seed_owned dual all
[[ "${TOKEN}" != "${OLD_TOKEN}" ]] || fail 'global migration reused old token'
accept run-once "${PORT}" dual --output-uid "${OUTPUT_UID}"
assert_empty
for signal in TERM INT; do
    for point in start-output-2 start-output-3 start-output-hook; do
        reset
        export FAKE_RD_MODE="signal-ipv6-${point}" FAKE_RD_SIGNAL="${signal}"
        status=0
        call run-once "${PORT}" dual --output-all >"${TEST_ROOT}/output.log" 2>&1 || status=$?
        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" &&
            -e "${FAKE_RD_ROOT}/signaled-once" ]] || fail "global OUTPUT ${point}/${signal} missed startup signal"
        assert_empty
    done
done
reset
seed_owned dual all
export FAKE_RD_MODE=fail-ipv6-cleanup-output
reject cleanup
[[ -f "${FAKE_RD_STATE}/redirect.state" ]] || fail 'partial global revoke discarded state'
export FAKE_RD_MODE=ok
accept cleanup
assert_empty

# 部分撤销保留可重试 state；空链失去 token 时只能保留并人工核验。
reset
seed_owned
export FAKE_RD_MODE=fail-ipv6-cleanup-output
reject cleanup
[[ -f "${FAKE_RD_STATE}/redirect.state" ]] || fail 'partial revoke discarded state'
export FAKE_RD_MODE=ok
accept cleanup
assert_empty
reset
seed_owned
export FAKE_RD_MODE=fail-cleanup-delete-chain
reject cleanup
export FAKE_RD_MODE=ok
reject_unchanged cleanup
reset
export FAKE_RD_MODE=signal-start-chain FAKE_RD_SIGNAL=KILL
status=0
call run-once "${PORT}" >"${TEST_ROOT}/output.log" 2>&1 || status=$?
[[ "${status}" == 137 && "$(state_value phase)" == intent ]] || fail 'KILL did not preserve intent'
export FAKE_RD_MODE=ok
reject_unchanged cleanup
reject_unchanged run-once "${PORT}"

# 正常等待阶段收到信号也回收全部资源和等待子进程。
for output in uid all; do
output_args=(--output-uid "${OUTPUT_UID}")
[[ "${output}" != all ]] || output_args=(--output-all)
for signal in TERM INT; do
    reset
    env --default-signal=INT --default-signal=TERM sh "${TEST_ROOT}/runner.sh" \
        "${TEST_ROOT}/functions.sh" run-wait "${PORT}" dual "${output_args[@]}" >"${TEST_ROOT}/output.log" 2>&1 &
    RUN_PID=$!
    ready=false
    for ((attempt=0; attempt<200; attempt++)); do
        if [[ -f "${FAKE_RD_STATE}/redirect.state" ]] && grep -qx phase=active "${FAKE_RD_STATE}/redirect.state"; then
            ready=true; break
        fi
        kill -0 "${RUN_PID}" 2>/dev/null || break
        sleep 0.025
    done
    [[ "${ready}" == true ]] || fail 'runtime did not become active'
    kill "-${signal}" "${RUN_PID}"
    wait "${RUN_PID}" || true
    RUN_PID=
    assert_empty
done
done
printf 'docker-redirect-ownership-regression-ok\n'
