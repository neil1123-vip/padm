#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
# guard 只读属性用真实挂载证明；私有命名空间不修改其它回归的 /run。
if [[ "${PADM_TEST_FB_PRIVATE_MOUNT:-0}" != 1 ]]; then
    exec unshare --mount --propagation private -- \
        env PADM_TEST_FB_PRIVATE_MOUNT=1 bash "${BASH_SOURCE[0]}"
fi
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-fail2ban-ownership.XXXXXX")
cleanup() {
    local status=$?
    if [[ "${GUARD_MOUNTED:-0}" == 1 ]]; then
        umount -- /run/padm/ssh-collector || status=1
    fi
    if [[ "${RUN_MOUNTED:-0}" == 1 ]]; then
        umount -- /run || status=1
    fi
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
for tool in python3 stat sha256sum mount umount; do command -v "${tool}" >/dev/null; done
export FAKE_FB_ROOT="${TEST_ROOT}/kernel" FAKE_FB_STATE="${TEST_ROOT}/state"
export FAKE_FB_WRITES="${TEST_ROOT}/writes.log" FAKE_FB_READS="${TEST_ROOT}/reads.log"
export FAKE_FB_MODE=ok
TOKEN=0123456789abcdef0123456789abcdef
CHAIN=padm-f2b-0123456789ab
CONTROL_TOKEN=fedcba9876543210fedcba9876543210
CONTROL_CHAIN=padm-f2bc-fedcba987654
SSH_TOKEN=abcdefabcdefabcdefabcdefabcdefab
SSH_CHAIN=padm-f2bs-abcdefabcdef
mkdir -p "${TEST_ROOT}/bin" "${FAKE_FB_ROOT}" "${FAKE_FB_STATE}"
chmod 0700 "${FAKE_FB_STATE}"
GUARD_ROOT="${TEST_ROOT}/collector"
mkdir -p "${GUARD_ROOT}"
chmod 0700 "${GUARD_ROOT}"
mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run
RUN_MOUNTED=1
mkdir -p /run/padm/ssh-collector
mount --bind "${GUARD_ROOT}" /run/padm/ssh-collector
GUARD_MOUNTED=1
mount -o remount,bind,ro /run/padm/ssh-collector

# 只替换系统命令，state 解析、资源审计及每个动作均执行生产函数。
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
    >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$1"
STATE_ROOT=$FAKE_FB_STATE
shift
case "$1" in control-*) fail2ban_control_scope ;; ssh-*) fail2ban_ssh_scope ;; esac
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
ssh-seed)
    fb_root=$STATE_ROOT fb_token=$2 fb_chain=$fb_prefix$(printf '%s' "$2" | cut -c1-12)
    fb_target=$3 fb_ports=$4 fb_ipv6=no
    case "$fb_target" in *:*) fb_ipv6=yes ;; esac
    fail2ban_state_write
    ;;
ssh-valid) fail2ban_ssh_parameters_valid "$2" "$3" ;;
ssh-preflight) shift; fail2ban_ssh_preflight "$@" ;;
ssh-clean) shift; fail2ban_ssh_clean "$@" ;;
ssh-run) shift; fail2ban_run "$@" ;;
control-valid) fail2ban_control_parameters_valid "$2" "$3" ;;
control-precheck) fail2ban_control_precheck "$2" "$3" ;;
control-clean) shift; fail2ban_control_clean "$@" ;;
action|control-action|ssh-action) shift; fail2ban_action "$@" ;;
cleanup|control-cleanup|ssh-cleanup) fail2ban_cleanup "${2:-}" ;;
audit|control-audit|ssh-audit)
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
    if os.environ["FAKE_FB_MODE"] == "replace-ssh-state":
        state = os.path.join(os.environ["FAKE_FB_STATE"], "fail2ban-ssh.state")
        with open(state) as stream:
            value = stream.read()
        with open(state, "w") as stream:
            stream.write(value.replace("token=" + "abcdef" * 5 + "ab", "token=" + "f" * 32))
    if os.environ["FAKE_FB_MODE"] == "create-ssh-state":
        state = os.path.join(os.environ["FAKE_FB_STATE"], "fail2ban-ssh.state")
        with open(state, "w") as stream:
            stream.write("created-during-read-only-audit\n")
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
cat >"${TEST_ROOT}/adapter.py" <<'PY'
import contextlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback


def install():
    original_run = subprocess.run
    binaries = Path(os.environ["FAKE_FB_ROOT"]).parent / "bin"
    firewall = binaries / "firewall"
    tool_source = compile(firewall.read_text(), str(firewall), "exec")

    def run(args, *positional, **keywords):
        if (not isinstance(args, (list, tuple)) or not args
                or args[0] not in {"iptables", "ip6tables"} or positional
                or keywords != {"text": True, "capture_output": True}
                or shutil.which(args[0]) != str(binaries / args[0])):
            return original_run(args, *positional, **keywords)
        output, error = io.StringIO(), io.StringIO()
        saved, status = sys.argv, 0
        try:
            sys.argv = [str(binaries / args[0]), *args[1:]]
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(error):
                try:
                    exec(tool_source, {"__name__": "__main__"})
                except SystemExit as stopped:
                    status = stopped.code or 0
                except Exception:
                    traceback.print_exc()
                    status = 1
        finally:
            sys.argv = saved
        return subprocess.CompletedProcess(args, status, output.getvalue(), error.getvalue())

    subprocess.run = run
    return original_run


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if (len(arguments) < 9 or arguments[0] != "-"
            or arguments[1] != os.environ.get("FAKE_FB_STATE")):
        os.execv("/usr/bin/python3", ["python3", *arguments])
    body = sys.stdin.read()
    # 仅本夹具的资源审计内联 mock；每次工具调用仍读取当前内核 JSON。
    if "root, token, chain, ports, ipv6, scope, target, operation = sys.argv[1:9]" in body:
        install()
    sys.argv = arguments
    exec(compile(body, "<fail2ban-resources-fixture>", "exec"), {"__name__": "__main__"})
PY
printf '#!/bin/sh\nexec /usr/bin/python3 "%s/adapter.py" "$@"\n' "${TEST_ROOT}" \
    >"${TEST_ROOT}/bin/python3"
chmod 0755 "${TEST_ROOT}/bin/python3"
export PATH="${TEST_ROOT}/bin:${PATH}"
# 与原工具子进程逐次比较标准流、失败码、读取记录和实际 JSON 写入。
/usr/bin/python3 - "${TEST_ROOT}" <<'PY'
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys

root = Path(sys.argv[1])
original = runpy.run_path(str(root / "adapter.py"))["install"]()
files = [root / "kernel/iptables.json", Path(os.environ["FAKE_FB_READS"]),
         Path(os.environ["FAKE_FB_WRITES"])]
try:
    for args, inventory in (
        (["iptables", "-w", "-S"], {"INPUT": []}),
        (["iptables", "-w", "-S"], {"INPUT": [["-j", "ACCEPT"]]}),
        (["iptables", "-w", "-N", "new"], {"INPUT": []}),
        (["iptables", "-w", "-X", "missing"], {"INPUT": []}),
        (["iptables", "", "quoted ' value", "line\nbreak"], {"INPUT": []}),
    ):
        contents = [json.dumps(inventory).encode(), b"", b""]
        for path, value in zip(files, contents):
            path.write_bytes(value)
        expected = original(args, text=True, capture_output=True)
        expected_files = [path.read_bytes() for path in files]
        for path, value in zip(files, contents):
            path.write_bytes(value)
        actual = subprocess.run(args, text=True, capture_output=True)
        assert (actual.returncode, actual.stdout, actual.stderr) == (
            expected.returncode, expected.stdout, expected.stderr), args
        assert [path.read_bytes() for path in files] == expected_files, args
finally:
    subprocess.run = original
    for path in files:
        path.unlink()
PY
ssh_guard_refresh() {
    python3 - "${GUARD_ROOT}/guard.json" "${PADM_SSH_COLLECTOR_TOKEN}" \
        "${PADM_SSH_COLLECTOR_UNIT}" "${PADM_SSH_COLLECTOR_TARGET}" "${PADM_SSH_COLLECTOR_PORT}" <<'PY'
import json
import os
import sys
import time

path, token, unit, target, port = sys.argv[1:]
with open("/proc/sys/kernel/random/boot_id", encoding="ascii") as handle:
    boot = handle.read().strip().replace("-", "")
guard = dict(schema=1, token=token, unit=unit, target=target, port=int(port),
             boot=boot, invocation="a" * 32, monotonic_ns=time.monotonic_ns())
with open(path, "w", encoding="ascii") as handle:
    json.dump(guard, handle)
os.chmod(path, 0o600)
PY
}
run() {
    if [[ "$1" == ssh-seed ]]; then
        export PADM_SSH_COLLECTOR_TOKEN=13571357135713571357135713571357
        export PADM_SSH_COLLECTOR_UNIT=ssh.service PADM_SSH_COLLECTOR_TARGET=$3 PADM_SSH_COLLECTOR_PORT=$4
    fi
    if [[ "$1" == ssh-seed || ( "$1" == ssh-action &&
        ( "$2" == start || "$2" == ban || "$2" == check ) ) ]]; then
        ssh_guard_refresh
    fi
    sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" "$@"
}
reset() {
    rm -f -- "${FAKE_FB_STATE}/fail2ban.state" "${FAKE_FB_STATE}/fail2ban-control.state" \
        "${FAKE_FB_STATE}/fail2ban-ssh.state" "${FAKE_FB_ROOT}/failed"
    printf '{"DOCKER-USER": [], "INPUT": [], "FOREIGN": []}' >"${FAKE_FB_ROOT}/iptables.json"
    cp "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json"
    : >"${FAKE_FB_WRITES}"
    : >"${FAKE_FB_READS}"
    export FAKE_FB_MODE=ok
    unset PADM_SSH_COLLECTOR_TOKEN PADM_SSH_COLLECTOR_UNIT \
        PADM_SSH_COLLECTOR_TARGET PADM_SSH_COLLECTOR_PORT
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
clean_before=$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json")
run control-clean 10.77.0.1 39778
[[ "$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json")" == "${clean_before}" ]]
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
reject_unchanged control-clean 10.77.0.1 39778
run audit health
run control-audit health
reject_unchanged control-action ban "${CONTROL_TOKEN}" ip6tables -w 2001:db8::9
reject_unchanged control-action ban "${TOKEN}" iptables -w 192.0.2.10
run control-action unban "${CONTROL_TOKEN}" iptables -w 192.0.2.9
run control-action ban "${CONTROL_TOKEN}" iptables -w 192.0.2.9
run control-action flush "${CONTROL_TOKEN}" iptables -w
run control-cleanup "${CONTROL_TOKEN}"
run control-clean 10.77.0.1 39778
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

# SSH 只新增单端点 owner 后端；WS 共存不改其 state、双族 hook 或 ban。
ws_scope_snapshot() {
    python3 - "${FAKE_FB_ROOT}" "${CHAIN}" <<'PY'
import json
from pathlib import Path
import sys
root, chain = Path(sys.argv[1]), sys.argv[2]
for table in ("iptables", "ip6tables"):
    rules = json.loads((root / (table + ".json")).read_text())
    print(json.dumps({name: rules[name] for name in ("DOCKER-USER", chain)}, sort_keys=True))
PY
    sha256sum "${FAKE_FB_STATE}/fail2ban.state"
}
ssh_ws_coexist() {
    reset
    run seed "${TOKEN}"
    run action start "${TOKEN}" iptables -w
    run action start "${TOKEN}" ip6tables -w
    run action ban "${TOKEN}" iptables -w 192.0.2.7
    run action ban "${TOKEN}" ip6tables -w 2001:db8::7
}
ssh_alter() {
    python3 - "${FAKE_FB_ROOT}/$1.json" "$2" "${SSH_CHAIN}" <<'PY'
import json
import sys
path, mode, chain = sys.argv[1:]
with open(path) as stream:
    rules = json.load(stream)
rule = rules["INPUT"][0]
if mode in ("target", "wide-target", "port", "state"):
    key = {"target":"-d", "wide-target":"-d", "port":"--dport", "state":"--ctstate"}[mode]
    rule[rule.index(key) + 1] = {
        "target":"198.51.100.11/32", "wide-target":"198.51.100.0/24",
        "port":"22221", "state":"ESTABLISHED",
    }[mode]
elif mode == "head":
    rules["INPUT"].insert(0, ["-j", "ACCEPT"])
elif mode == "foreign":
    rules["FOREIGN"].append(["-g", chain])
elif mode == "token":
    rules[chain][-1][3] = "padm-f2bs:" + "f" * 32
with open(path, "w") as stream:
    json.dump(rules, stream)
PY
}
for target in 198.51.100.10 2001:db8::10; do
    run ssh-valid "${target}" 22220
done
for target in 127.0.0.1 0.0.0.0 0.1.2.3 240.1.2.3 ::1 :: \
    fe80::1 ff02::1 ::ffff:192.0.2.1 2001:0DB8::10 198.51.100.10/32; do
    reject_unchanged ssh-valid "${target}" 22220
done
for port in 0 65536 022220 22,23 '22;id'; do
    reject_unchanged ssh-valid 198.51.100.10 "${port}"
done
reset
reject_unchanged ssh-run ssh.service 198.51.100.10 22220
before=$(snapshot)
if sh "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" fail2ban-ssh ssh.service 198.51.100.10 22220 \
    >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ "$(snapshot)" == "${before}" ]]

# guard 失效时没有任何防火墙写入，正确夹具仍须经过生产门禁。
reset
run ssh-seed "${SSH_TOKEN}" 198.51.100.10 22220
# 在真实只读挂载上确定性替换 guard，覆盖读取前后两个轮换窗口。
/usr/bin/python3 - "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" "${GUARD_ROOT}" <<'PY'
import json
import os
from pathlib import Path
import re
import stat
import sys
import time
from unittest.mock import patch

source = Path(sys.argv[1]).read_text()
namespace = dict(os=os, re=re, stat=stat, json=json, time=time,
                 target=os.environ["PADM_SSH_COLLECTOR_TARGET"],
                 ports=[os.environ["PADM_SSH_COLLECTOR_PORT"]])
body = source[source.index("\ndef collector_guard():") + 1:source.index("\ndef hook(port):")]
exec(compile(body, "<production-collector-guard>", "exec"), namespace)
check = namespace["collector_guard"]
guard = Path(sys.argv[2]) / "guard.json"
valid = guard.read_bytes()
original_open, original_fstat = os.open, os.fstat

def exercise(window, replacements, accepted):
    guard.write_bytes(valid)
    guard.chmod(0o600)
    pending, reads = replacements, {}
    def rotate():
        nonlocal pending
        temporary = guard.with_name(".guard-race")
        temporary.write_bytes(valid)
        temporary.chmod(0o600)
        os.replace(temporary, guard)
        pending -= 1
    def opened(path, *args, **kwargs):
        descriptor = original_open(path, *args, **kwargs)
        if path == "/run/padm/ssh-collector/guard.json":
            reads[descriptor] = 0
            if window == "open" and pending:
                rotate()
        return descriptor
    def metadata(descriptor):
        result = original_fstat(descriptor)
        if descriptor in reads:
            reads[descriptor] += 1
            if reads[descriptor] == 1:
                if window == "read" and pending:
                    rotate()
                elif window == "same-inode":
                    os.utime(guard, ns=(result.st_atime_ns, result.st_mtime_ns + 1_000_000))
        return result
    if window == "permissions":
        guard.chmod(0o644)
    elif window == "hardlink":
        os.link(guard, guard.with_name("linked"))
    try:
        with patch.object(os, "open", side_effect=opened), \
                patch.object(os, "fstat", side_effect=metadata):
            try:
                check()
            except ValueError:
                assert not accepted, (window, replacements)
            else:
                assert accepted, (window, replacements)
        assert pending == 0, (window, replacements, pending)
    finally:
        if window == "hardlink":
            guard.with_name("linked").unlink()
        guard.chmod(0o600)

for window in ("open", "read"):
    exercise(window, 1, True)
    exercise(window, 2, False)
for window in ("same-inode", "permissions", "hardlink"):
    exercise(window, 0, False)
print("ssh-guard-atomic-replacement-ok")
PY
for mutation in token unit target port boot invocation expired; do
    ssh_guard_refresh
    python3 - "${GUARD_ROOT}/guard.json" "${mutation}" <<'PY'
import json
import sys

path, mutation = sys.argv[1:]
with open(path, encoding="ascii") as handle:
    guard = json.load(handle)
changes = dict(token="f" * 32, unit="other.service", target="198.51.100.11",
               port=22221, boot="f" * 32, invocation="0" * 32,
               expired=guard["monotonic_ns"] - 11_000_000_000)
guard["monotonic_ns" if mutation == "expired" else mutation] = changes[mutation]
with open(path, "w", encoding="ascii") as handle:
    json.dump(guard, handle)
PY
    before=$(snapshot)
    if sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" \
        ssh-action start "${SSH_TOKEN}" iptables -w >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
    grep -qF 'SSH collector guard expired or changed' "${TEST_ROOT}/output.log"
    [[ "$(snapshot)" == "${before}" ]]
done
ssh_guard_refresh
mount -o remount,bind,rw /run/padm/ssh-collector
before=$(snapshot)
if sh "${TEST_ROOT}/runner.sh" "${TEST_ROOT}/functions.sh" \
    ssh-action start "${SSH_TOKEN}" iptables -w >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
grep -qF 'SSH collector guard mount is writable' "${TEST_ROOT}/output.log"
[[ "$(snapshot)" == "${before}" ]]
mount -o remount,bind,ro /run/padm/ssh-collector

for target in 198.51.100.10 2001:db8::10; do
    table=iptables peer=192.0.2.20 other=ip6tables
    [[ "${target}" != *:* ]] || { table=ip6tables peer=2001:db8::20 other=iptables; }
    ssh_ws_coexist
    ws_before=$(ws_scope_snapshot)
    run ssh-preflight "${target}" 22220
    run ssh-clean "${target}" 22220
    reject_unchanged ssh-preflight "${target}" 22220 anything
    run ssh-seed "${SSH_TOKEN}" "${target}" 22220
    reject_unchanged ssh-audit health
    reject_unchanged ssh-clean "${target}" 22220
    run ssh-action start "${SSH_TOKEN}" "${table}" -w
    run ssh-action check "${SSH_TOKEN}" "${table}" -w
    run ssh-audit health
    run ssh-preflight "${target}" 22220 owned
    reject_unchanged ssh-preflight "${target}" 22221 owned
    for bad_field in family target; do
        cp -- "${FAKE_FB_STATE}/fail2ban-ssh.state" "${TEST_ROOT}/ssh-state.saved"
        if [[ "${bad_field}" == family ]]; then
            bad_family=yes
            [[ "${target}" != *:* ]] || bad_family=no
            sed "s/^ipv6=.*/ipv6=${bad_family}/" "${TEST_ROOT}/ssh-state.saved" \
                >"${FAKE_FB_STATE}/fail2ban-ssh.state"
        else
            bad_target=198.051.100.10
            [[ "${target}" != *:* ]] || bad_target=2001:DB8::10
            sed "s/^target=.*/target=${bad_target}/" "${TEST_ROOT}/ssh-state.saved" \
                >"${FAKE_FB_STATE}/fail2ban-ssh.state"
        fi
        reject_unchanged ssh-action check "${SSH_TOKEN}" "${table}" -w
        reject_unchanged ssh-cleanup "${SSH_TOKEN}"
        cp -- "${TEST_ROOT}/ssh-state.saved" "${FAKE_FB_STATE}/fail2ban-ssh.state"
        chmod 0600 "${FAKE_FB_STATE}/fail2ban-ssh.state"
    done
    python3 - "${FAKE_FB_ROOT}/${other}.json" add <<'PY'
import json
import sys
path = sys.argv[1]
with open(path) as stream:
    rules = json.load(stream)
rules["padm-f2bs-ffffffffffff"] = []
with open(path, "w") as stream:
    json.dump(rules, stream)
PY
    reject_unchanged ssh-preflight "${target}" 22220 owned
    reject_unchanged ssh-action check "${SSH_TOKEN}" "${table}" -w
    reject_unchanged ssh-cleanup "${SSH_TOKEN}"
    python3 - "${FAKE_FB_ROOT}/${other}.json" <<'PY'
import json
import sys
path = sys.argv[1]
with open(path) as stream:
    rules = json.load(stream)
del rules["padm-f2bs-ffffffffffff"]
with open(path, "w") as stream:
    json.dump(rules, stream)
PY
    reject_unchanged ssh-action start "${SSH_TOKEN}" "${other}" -w
    reject_unchanged ssh-action ban "${CONTROL_TOKEN}" "${table}" -w "${peer}"
    run ssh-action ban "${SSH_TOKEN}" "${table}" -w "${peer}"
    run ssh-action unban "${SSH_TOKEN}" "${table}" -w "${peer}"
    run ssh-action ban "${SSH_TOKEN}" "${table}" -w "${peer}"
    run ssh-action flush "${SSH_TOKEN}" "${table}" -w
    [[ "$(ws_scope_snapshot)" == "${ws_before}" ]]
    export FAKE_FB_MODE=fail-delete
    if run ssh-cleanup "${SSH_TOKEN}" >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
    [[ -f "${FAKE_FB_STATE}/fail2ban-ssh.state" && "$(ws_scope_snapshot)" == "${ws_before}" ]]
    run ssh-audit
    export FAKE_FB_MODE=ok
    run ssh-cleanup "${SSH_TOKEN}"
    run ssh-clean "${target}" 22220
    [[ ! -e "${FAKE_FB_STATE}/fail2ban-ssh.state" && "$(ws_scope_snapshot)" == "${ws_before}" ]]
done
for drift in target wide-target port state head foreign token; do
    reset
    run ssh-seed "${SSH_TOKEN}" 198.51.100.10 22220
    run ssh-action start "${SSH_TOKEN}" iptables -w
    ssh_alter iptables "${drift}"
    for operation in start check stop flush; do
        reject_unchanged ssh-action "${operation}" "${SSH_TOKEN}" iptables -w
    done
    reject_unchanged ssh-action ban "${SSH_TOKEN}" iptables -w 192.0.2.20
    reject_unchanged ssh-cleanup "${SSH_TOKEN}"
done
# 控制面规则在 IPv4 时，IPv6 SSH 动作也须在任何写入之前拒绝。
for target in 198.51.100.10 2001:db8::10; do
    coexist
    table=iptables
    [[ "${target}" != *:* ]] || table=ip6tables
    reject_unchanged ssh-preflight "${target}" 22220
    reject_unchanged ssh-clean "${target}" 22220
    run ssh-seed "${SSH_TOKEN}" "${target}" 22220
    for operation in start stop check flush; do
        reject_unchanged ssh-action "${operation}" "${SSH_TOKEN}" "${table}" -w
    done
    reject_unchanged ssh-audit health
    reject_unchanged ssh-cleanup "${SSH_TOKEN}"
    run control-audit health
    run audit health
done
for operation in ssh-preflight ssh-clean; do
    reset
    kernel_before=$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json" "${FAKE_FB_WRITES}")
    export FAKE_FB_MODE=create-ssh-state
    if run "${operation}" 198.51.100.10 22220 >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
    grep -qF 'unexpected ownership state' "${TEST_ROOT}/output.log"
    [[ "$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json" "${FAKE_FB_WRITES}")" == "${kernel_before}" ]]
    grep -qxF 'created-during-read-only-audit' "${FAKE_FB_STATE}/fail2ban-ssh.state"
done
reset
run ssh-seed "${SSH_TOKEN}" 198.51.100.10 22220
run ssh-action start "${SSH_TOKEN}" iptables -w
kernel_before=$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json" "${FAKE_FB_WRITES}")
export FAKE_FB_MODE=replace-ssh-state
if run ssh-action ban "${SSH_TOKEN}" iptables -w 192.0.2.20 >"${TEST_ROOT}/output.log" 2>&1; then exit 1; fi
[[ "$(sha256sum "${FAKE_FB_ROOT}/iptables.json" "${FAKE_FB_ROOT}/ip6tables.json" "${FAKE_FB_WRITES}")" == "${kernel_before}" &&
    -f "${FAKE_FB_STATE}/fail2ban-ssh.state" ]]
! grep -Eq '(^| )-F( |$)' "${FAKE_FB_WRITES}"
printf 'docker-fail2ban-ownership-ok\n'
