#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-ownership.XXXXXX")
cleanup() {
    local status=$?
    if [[ "${PADM_TEST_KEEP:-0}" == 1 ]]; then
        printf 'fail2ban-ownership-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
    return "${status}"
}
trap cleanup EXIT
trap 'printf "docker-fail2ban-ownership-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
for tool in python3 stat sha256sum; do command -v "${tool}" >/dev/null; done
export FAKE_FB_ROOT="${TEST_ROOT}/kernel" FAKE_FB_STATE="${TEST_ROOT}/state"
export FAKE_FB_WRITES="${TEST_ROOT}/writes.log" FAKE_FB_READS="${TEST_ROOT}/reads.log"
export FAKE_FB_MODE=ok
TOKEN=0123456789abcdef0123456789abcdef
CHAIN=padm-f2b-0123456789ab
CONTROL_TOKEN=fedcba9876543210fedcba9876543210
CONTROL_CHAIN=padm-f2bc-fedcba987654
mkdir -p "${TEST_ROOT}/bin" "${FAKE_FB_ROOT}" "${FAKE_FB_STATE}"
chmod 0700 "${FAKE_FB_STATE}"

# 只替换系统命令，state 解析、资源审计及每个动作均执行生产函数。
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
    >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$1"
STATE_ROOT=$FAKE_FB_STATE
shift
case "$1" in control-*) fail2ban_control_scope ;; esac
case "$1" in
seed)
    fb_root=$STATE_ROOT fb_token=$2 fb_chain=padm-f2b-$(printf '%s' "$2" | cut -c1-12)
    fb_ports=${3:-24444,24445} fb_ipv6=${4:-yes}
    fail2ban_state_write
    ;;
control-seed)
    fb_root=$STATE_ROOT fb_token=$2 fb_chain=$fb_prefix$(printf '%s' "$2" | cut -c1-12)
    fb_target=${3:-10.77.0.1} fb_ports=${4:-39778} fb_ipv6=no
    fail2ban_state_write
    ;;
control-valid) fail2ban_control_parameters_valid "$2" "$3" ;;
control-precheck) fail2ban_control_precheck "$2" "$3" ;;
action|control-action) shift; fail2ban_action "$@" ;;
cleanup|control-cleanup) fail2ban_cleanup "${2:-}" ;;
audit|control-audit)
    fail2ban_state_read && fail2ban_resources "${2:-audit}" "${3:-}"
    ;;
control-empty)
    fb_root=$STATE_ROOT fb_token=00000000000000000000000000000000
    fb_chain=${fb_prefix}000000000000 fb_ports=39778 fb_ipv6=no fb_target=10.77.0.1
    fail2ban_resources empty
    ;;
empty)
    fb_root=$STATE_ROOT fb_token=00000000000000000000000000000000
    fb_chain=padm-f2b-000000000000 fb_ports=24444,24445 fb_ipv6=${2:-yes}
    fail2ban_resources empty
    ;;
*) exit 99 ;;
esac
SH
cat >"${TEST_ROOT}/bin/firewall" <<'PY'
#!/usr/bin/env python3
import json
import os
import shlex
import sys

table = os.path.basename(sys.argv[0])
args = sys.argv[1:]
if args[:1] != ["-w"]:
    raise SystemExit(99)
args = args[1:]
path = os.path.join(os.environ["FAKE_FB_ROOT"], table + ".json")
with open(path) as stream:
    chains = json.load(stream)
action = args[0]
if action == "-S":
    with open(os.environ["FAKE_FB_READS"], "a") as stream:
        stream.write(table + "\n")
    for chain, rules in chains.items():
        print("-N", chain)
        for rule in rules:
            print("-A", chain, shlex.join(rule))
    raise SystemExit(0)
with open(os.environ["FAKE_FB_WRITES"], "a") as stream:
    stream.write(table + " " + shlex.join(args) + "\n")
mode = os.environ["FAKE_FB_MODE"]
failure = os.path.join(os.environ["FAKE_FB_ROOT"], "failed")
if ((mode == "fail-hook" and action == "-I" and args[1] == "DOCKER-USER"
        and "24445" in args) or (mode == "fail-control-hook" and action == "-I" and args[1] == "INPUT")
        or (mode == "fail-delete" and action == "-X")) \
        and not os.path.exists(failure):
    open(failure, "w").close()
    raise SystemExit(1)
chain = args[1]
if action == "-N":
    if chain in chains:
        raise SystemExit(1)
    chains[chain] = []
elif action in ("-A", "-I", "-D"):
    rule = args[2:]
    if action == "-I" and rule[:1] == ["1"]:
        rule = rule[1:]
    if chain not in chains:
        raise SystemExit(1)
    if action == "-A":
        chains[chain].append(rule)
    elif action == "-I":
        chains[chain].insert(0, rule)
    elif rule in chains[chain]:
        chains[chain].remove(rule)
    else:
        raise SystemExit(1)
elif action == "-X":
    if chain not in chains or chains[chain]:
        raise SystemExit(1)
    if any(chain in rule for rules in chains.values() for rule in rules):
        raise SystemExit(1)
    del chains[chain]
else:
    raise SystemExit(99)
with open(path, "w") as stream:
    json.dump(chains, stream)
PY
chmod 0755 "${TEST_ROOT}/bin/firewall"
ln -s firewall "${TEST_ROOT}/bin/iptables"
ln -s firewall "${TEST_ROOT}/bin/ip6tables"
cat >"${TEST_ROOT}/bin/ip" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys
if sys.argv[1:] == ["-j", "-d", "link", "show", "dev", "wg-padm"]:
    print(json.dumps([{"ifname": "wg-padm", "linkinfo": {
        "info_kind": os.environ.get("FAKE_FB_INTERFACE_KIND", "dummy")}}]))
else:
    raise SystemExit(99)
PY
chmod 0755 "${TEST_ROOT}/bin/ip"
export PATH="${TEST_ROOT}/bin:${PATH}"
run() { sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" "$@"; }
reset() {
    rm -f -- "${FAKE_FB_STATE}/fail2ban.state" "${FAKE_FB_STATE}/fail2ban-control.state" "${FAKE_FB_ROOT}/failed"
    printf '{"DOCKER-USER": [], "INPUT": [], "FOREIGN": []}' >"${FAKE_FB_ROOT}/iptables.json"
    cp "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json"
    : >"${FAKE_FB_WRITES}"
    : >"${FAKE_FB_READS}"
    export FAKE_FB_MODE=ok
}
snapshot() {
    sha256sum "${FAKE_FB_ROOT}/"* "${FAKE_FB_STATE}/"* "${FAKE_FB_WRITES}" 2>/dev/null || true
}
reject_unchanged() {
    local before
    before=$(snapshot)
    if run "$@" >"${TEST_ROOT}/output.log" 2>&1; then
        printf 'unexpected accepted action: %s\n' "$*" >&2
        exit 1
    fi
    [[ "$(snapshot)" == "${before}" ]] || {
        cat "${TEST_ROOT}/output.log" >&2
        printf 'rejected action changed resources: %s\n' "$*" >&2
        exit 1
    }
}
alter() {
    python3 - "${FAKE_FB_ROOT}/iptables.json" "$1" "${CHAIN}" "${TOKEN}" <<'PY'
import json
import sys
path, mode, chain, token = sys.argv[1:]
with open(path) as stream:
    rules = json.load(stream)
comment = ["-m", "comment", "--comment", "padm-f2b:" + token]
if mode == "legacy":
    rules["padm-f2b"] = []
elif mode in {"jump", "goto"}:
    rules["FOREIGN"].append(["-j" if mode == "jump" else "-g", chain])
elif mode == "foreign-rule":
    rules[chain].insert(0, ["-s", "192.0.2.22", "-j", "DROP"])
elif mode == "wrong-token":
    rules[chain][-1] = ["-m", "comment", "--comment", "padm-f2b:" + "f" * 32, "-j", "RETURN"]
elif mode == "duplicate":
    rules["DOCKER-USER"].append(rules["DOCKER-USER"][0])
elif mode == "order":
    rules[chain].insert(0, rules[chain].pop())
elif mode == "hook-order":
    rules["DOCKER-USER"].insert(0, ["-j", "RETURN"])
elif mode == "empty-chain":
    rules[chain] = []
with open(path, "w") as stream:
    json.dump(rules, stream)
PY
}

reset
alter legacy
reject_unchanged empty
reset
printf 'ports=23444\n' >"${FAKE_FB_STATE}/fail2ban.state"
chmod 0600 "${FAKE_FB_STATE}/fail2ban.state"
reject_unchanged cleanup
reset
run seed "${TOKEN}"
chmod 0644 "${FAKE_FB_STATE}/fail2ban.state"
reject_unchanged action start "${TOKEN}" iptables -w
chmod 0600 "${FAKE_FB_STATE}/fail2ban.state"
ln "${FAKE_FB_STATE}/fail2ban.state" "${FAKE_FB_STATE}/linked"
reject_unchanged cleanup
rm "${FAKE_FB_STATE}/linked"
printf '\0' >>"${FAKE_FB_STATE}/fail2ban.state"
reject_unchanged cleanup

reset
run seed "${TOKEN}"
for table in iptables ip6tables; do
    run action start "${TOKEN}" "${table}" -w
    run action check "${TOKEN}" "${table}" -w
done
run action ban "${TOKEN}" iptables -w 192.0.2.7
run action ban "${TOKEN}" ip6tables -w 2001:db8::7
run action ban "${TOKEN}" ip6tables -w ::ffff:192.0.2.7
run action unban "${TOKEN}" ip6tables -w ::ffff:c000:207
run audit health
reject_unchanged action ban "${TOKEN}" iptables -w 2001:db8::7
reject_unchanged action ban "${TOKEN}" ip6tables -w 192.0.2.7
reject_unchanged action ban "${TOKEN}" ip6tables -w fe80::1%eth0
reject_unchanged action unban "${TOKEN}" iptables --wait 192.0.2.7
reject_unchanged action stop ffffffffffffffffffffffffffffffff iptables -w
run action unban "${TOKEN}" iptables -w 192.0.2.7
run action flush "${TOKEN}" ip6tables -w
run cleanup "${TOKEN}"
[[ ! -e "${FAKE_FB_STATE}/fail2ban.state" ]]
! grep -Eq '(^| )-F( |$)' "${FAKE_FB_WRITES}"

for drift in jump goto foreign-rule wrong-token duplicate order empty-chain hook-order; do
    reset
    run seed "${TOKEN}"
    run action start "${TOKEN}" iptables -w
    run action ban "${TOKEN}" iptables -w 192.0.2.7
    alter "${drift}"
    for operation in check stop flush start; do
        reject_unchanged action "${operation}" "${TOKEN}" iptables -w
    done
    reject_unchanged action ban "${TOKEN}" iptables -w 192.0.2.8
    reject_unchanged action unban "${TOKEN}" iptables -w 192.0.2.7
    reject_unchanged cleanup "${TOKEN}"
done

reset
run seed "${TOKEN}" 24444,24445 no
printf '{"DOCKER-USER": [], "padm-f2b": [["-s","2001:db8::9","-j","DROP"]]}' \
    >"${FAKE_FB_ROOT}/ip6tables.json"
ipv6_before=$(sha256sum "${FAKE_FB_ROOT}/ip6tables.json")
run action start "${TOKEN}" iptables -w
reject_unchanged audit audit yes
run cleanup "${TOKEN}"
[[ "$(sha256sum "${FAKE_FB_ROOT}/ip6tables.json")" == "${ipv6_before}" ]]

reset
run seed "${TOKEN}"
export FAKE_FB_MODE=fail-hook
if run action start "${TOKEN}" iptables -w >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
python3 - "${FAKE_FB_ROOT}/iptables.json" "${CHAIN}" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    rules = json.load(stream)
assert sys.argv[2] not in rules and not rules["DOCKER-USER"], rules
PY
[[ -f "${FAKE_FB_STATE}/fail2ban.state" ]]
export FAKE_FB_MODE=ok
run action start "${TOKEN}" iptables -w
export FAKE_FB_MODE=fail-delete
rm "${FAKE_FB_ROOT}/failed"
if run cleanup "${TOKEN}" >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ -f "${FAKE_FB_STATE}/fail2ban.state" ]]
run audit
export FAKE_FB_MODE=ok
run cleanup "${TOKEN}"
[[ ! -e "${FAKE_FB_STATE}/fail2ban.state" ]]

control_alter() {
    python3 - "${FAKE_FB_ROOT}/iptables.json" "$1" "${CONTROL_CHAIN}" "${CONTROL_TOKEN}" <<'PY'
import json
import sys
path, mode, chain, token = sys.argv[1:]
with open(path) as stream:
    rules = json.load(stream)
if mode == "foreign-chain":
    rules["padm-f2bc-ffffffffffff"] = []
elif mode == "goto":
    rules["FOREIGN"].append(["-g", chain])
elif mode == "duplicate":
    rules["INPUT"].append(rules["INPUT"][0])
elif mode in {"wide-target", "wrong-target", "wrong-port"}:
    rule = rules["INPUT"][0]
    key = "--dport" if mode == "wrong-port" else "-d"
    rule[rule.index(key) + 1] = {
        "wide-target":"10.77.0.0/24", "wrong-target":"10.77.0.3/32", "wrong-port":"39779"
    }[mode]
elif mode == "missing-new":
    rule = rules["INPUT"][0]
    index = rule.index("--ctstate")
    del rule[index:index + 2]
elif mode == "wrong-state":
    rule = rules["INPUT"][0]
    rule[rule.index("--ctstate") + 1] = "ESTABLISHED"
elif mode == "wrong-token":
    rules[chain][-1] = ["-m", "comment", "--comment", "padm-f2bc:" + "f" * 32, "-j", "RETURN"]
with open(path, "w") as stream:
    json.dump(rules, stream)
PY
}
ws_snapshot() {
    python3 - "${FAKE_FB_ROOT}/iptables.json" "${CHAIN}" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    rules = json.load(stream)
print(json.dumps({name:rules[name] for name in ("DOCKER-USER", sys.argv[2])}, sort_keys=True))
PY
    sha256sum "${FAKE_FB_STATE}/fail2ban.state" "${FAKE_FB_ROOT}/ip6tables.json"
}
control_snapshot() {
    python3 - "${FAKE_FB_ROOT}/iptables.json" "${CONTROL_CHAIN}" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    rules = json.load(stream)
print(json.dumps({name:rules[name] for name in ("INPUT", sys.argv[2])}, sort_keys=True))
PY
    sha256sum "${FAKE_FB_STATE}/fail2ban-control.state"
}
coexist() {
    reset
    run seed "${TOKEN}"
    run action start "${TOKEN}" iptables -w
    run action start "${TOKEN}" ip6tables -w
    run action ban "${TOKEN}" iptables -w 192.0.2.7
    run action ban "${TOKEN}" ip6tables -w 2001:db8::7
    run control-empty
    run control-seed "${CONTROL_TOKEN}"
    run control-action start "${CONTROL_TOKEN}" iptables -w
    run control-action ban "${CONTROL_TOKEN}" iptables -w 192.0.2.9
}

reset
run control-valid 10.77.0.1 39778
reject_unchanged control-precheck 10.77.0.1 39778
grep -qF 'requires an actual wg-padm WireGuard interface' "${TEST_ROOT}/output.log"
for target in 127.0.0.1 8.8.8.8 10.077.0.1 ::1; do
    reject_unchanged control-valid "${target}" 39778
done
for port in 1023 65536 039778 39778,39779; do
    reject_unchanged control-valid 10.77.0.1 "${port}"
done
# 外部环境不能把默认 WS 命令改为控制面范围。
fb_scope=control fb_state=fail2ban-control.state fb_prefix=padm-f2bc- run seed "${TOKEN}"
[[ -f "${FAKE_FB_STATE}/fail2ban.state" && ! -e "${FAKE_FB_STATE}/fail2ban-control.state" ]]

coexist
ws_before=$(ws_snapshot)
run audit health
run control-audit health
reject_unchanged control-action ban "${CONTROL_TOKEN}" ip6tables -w 2001:db8::9
reject_unchanged control-action ban "${TOKEN}" iptables -w 192.0.2.10
run control-action unban "${CONTROL_TOKEN}" iptables -w 192.0.2.9
run control-action ban "${CONTROL_TOKEN}" iptables -w 192.0.2.9
run control-action flush "${CONTROL_TOKEN}" iptables -w
run control-cleanup "${CONTROL_TOKEN}"
[[ ! -e "${FAKE_FB_STATE}/fail2ban-control.state" && "$(ws_snapshot)" == "${ws_before}" ]]
run audit health

for drift in wide-target wrong-target wrong-port missing-new wrong-state duplicate goto wrong-token foreign-chain; do
    coexist
    ws_before=$(ws_snapshot)
    control_alter "${drift}"
    reject_unchanged control-action check "${CONTROL_TOKEN}" iptables -w
    reject_unchanged control-cleanup "${CONTROL_TOKEN}"
    [[ "$(ws_snapshot)" == "${ws_before}" ]]
done
coexist
ws_before=$(ws_snapshot)
for mode in permissions extra nul; do
    cp -- "${FAKE_FB_STATE}/fail2ban-control.state" "${TEST_ROOT}/control-state.saved"
    case "${mode}" in
    permissions) chmod 0644 "${FAKE_FB_STATE}/fail2ban-control.state" ;;
    extra) printf 'target=10.77.0.3\n' >>"${FAKE_FB_STATE}/fail2ban-control.state" ;;
    nul) printf '\0' >>"${FAKE_FB_STATE}/fail2ban-control.state" ;;
    esac
    reject_unchanged control-cleanup "${CONTROL_TOKEN}"
    cp -- "${TEST_ROOT}/control-state.saved" "${FAKE_FB_STATE}/fail2ban-control.state"
    chmod 0600 "${FAKE_FB_STATE}/fail2ban-control.state"
    [[ "$(ws_snapshot)" == "${ws_before}" ]]
done
ln "${FAKE_FB_STATE}/fail2ban-control.state" "${FAKE_FB_STATE}/control-linked"
reject_unchanged control-cleanup "${CONTROL_TOKEN}"
rm -- "${FAKE_FB_STATE}/control-linked"
export FAKE_FB_MODE=fail-delete
if run control-cleanup "${CONTROL_TOKEN}" >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ -f "${FAKE_FB_STATE}/fail2ban-control.state" && "$(ws_snapshot)" == "${ws_before}" ]]
run control-audit
export FAKE_FB_MODE=ok
run control-cleanup "${CONTROL_TOKEN}"
[[ "$(ws_snapshot)" == "${ws_before}" ]]
run control-seed "${CONTROL_TOKEN}"
export FAKE_FB_MODE=fail-control-hook
rm -f -- "${FAKE_FB_ROOT}/failed"
if run control-action start "${CONTROL_TOKEN}" iptables -w >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ -f "${FAKE_FB_STATE}/fail2ban-control.state" && "$(ws_snapshot)" == "${ws_before}" ]]
python3 - "${FAKE_FB_ROOT}/iptables.json" "${CONTROL_CHAIN}" <<'PY'
import json
import sys
with open(sys.argv[1]) as stream:
    rules = json.load(stream)
assert sys.argv[2] not in rules and not rules["INPUT"], rules
PY
export FAKE_FB_MODE=ok
run control-cleanup "${CONTROL_TOKEN}"
run cleanup "${TOKEN}"
[[ ! -e "${FAKE_FB_STATE}/fail2ban.state" && ! -e "${FAKE_FB_STATE}/fail2ban-control.state" ]]
coexist
control_before=$(control_snapshot)
export FAKE_FB_MODE=fail-delete
if run cleanup "${TOKEN}" >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ -f "${FAKE_FB_STATE}/fail2ban.state" && "$(control_snapshot)" == "${control_before}" ]]
run audit
run control-audit health
export FAKE_FB_MODE=ok
run cleanup "${TOKEN}"
[[ ! -e "${FAKE_FB_STATE}/fail2ban.state" && "$(control_snapshot)" == "${control_before}" ]]
run control-audit health
run control-cleanup "${CONTROL_TOKEN}"
! grep -Eq '(^| )-F( |$)' "${FAKE_FB_WRITES}"
printf 'docker-fail2ban-ownership-ok\n'
