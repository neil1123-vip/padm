#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-ssh-start.XXXXXX")
RUNNER_PID='' SENTINEL_PID=''
cleanup() {
    local status=$?
    if [[ -n "${RUNNER_PID}" ]]; then
        kill -TERM "${RUNNER_PID}" 2>/dev/null || true
        wait "${RUNNER_PID}" 2>/dev/null || true
    fi
    if [[ -n "${SENTINEL_PID}" ]]; then
        kill -TERM "${SENTINEL_PID}" 2>/dev/null || true
        wait "${SENTINEL_PID}" 2>/dev/null || true
    fi
    rm -rf -- "${TEST_ROOT}"
    return "${status}"
}
trap cleanup EXIT
fail() {
    [[ ! -f "${TEST_ROOT}/run.log" ]] || cat "${TEST_ROOT}/run.log" >&2
    printf 'docker-ssh-start-regression-fail: %s\n' "$*" >&2
    exit 1
}
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || fail 'requires root Linux'
for tool in sh python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done

mkdir -p "${TEST_ROOT}/bin" "${TEST_ROOT}/state"
chmod 0700 "${TEST_ROOT}/state"
sed '/^case "${1:-idle}" in/,$d' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" \
    >"${TEST_ROOT}/functions.sh"
cat >"${TEST_ROOT}/runner.sh" <<'SH'
#!/bin/sh
set -eu
. "$SSH_START_ROOT/functions.sh"
STATE_ROOT=$SSH_START_ROOT/state
fail2ban_ssh_scope
# 只替换配置、来源和内核边界，运行、监督、等待及 owner 清理由生产入口执行。
fail2ban_ssh_configuration_valid() { return 0; }
fail2ban_ssh_preflight() { return 0; }
fail2ban_resources() {
    case "$1" in
    guard)
        printf 'guard\n' >>"$SSH_START_ROOT/events"
        [ -f "$SSH_START_ROOT/guard-ready" ]
        ;;
    empty) [ ! -e "$SSH_START_ROOT/ban" ] ;;
    cleanup)
        printf 'cleanup %s\n' "$fb_token" >>"$SSH_START_ROOT/events"
        rm -f "$SSH_START_ROOT/ban"
        ;;
    *) return 99 ;;
    esac
}
fail2ban_run sshd-padm.service 198.51.100.10 22220
SH
cat >"${TEST_ROOT}/bin/fail2ban-client" <<'SH'
#!/bin/sh
case "$1" in
-t) exit 0 ;;
stop)
    printf 'client-stop\n' >>"$SSH_START_ROOT/events"
    [ -f "$SSH_START_ROOT/server.pid" ] || exit 1
    kill -TERM "$(cat "$SSH_START_ROOT/server.pid")"
    ;;
*) exit 99 ;;
esac
SH
cat >"${TEST_ROOT}/bin/fail2ban-server" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import signal
import time

root = Path(os.environ["SSH_START_ROOT"])
def stop(_signum, _frame):
    with (root / "events").open("a") as stream:
        stream.write("server-TERM\n")
    raise SystemExit(0)

signal.signal(signal.SIGTERM, stop)
(root / "server.pid").write_text(str(os.getpid()))
(root / "ban").write_text("owned-ban")
(root / "server.ready").touch()
while not (root / "server-release").exists():
    time.sleep(0.02)
with (root / "events").open("a") as stream:
    stream.write("server-natural\n")
PY
chmod 0755 "${TEST_ROOT}/bin/"*
export PATH="${TEST_ROOT}/bin:${PATH}" SSH_START_ROOT="${TEST_ROOT}"
export PADM_SSH_COLLECTOR_UNIT=sshd-padm.service PADM_SSH_COLLECTOR_TARGET=198.51.100.10 \
    PADM_SSH_COLLECTOR_PORT=22220

sleep 30 &
SENTINEL_PID=$!
for scenario in expired term natural; do
    rm -f -- "${TEST_ROOT}"/{server.pid,server.ready,server-release,ban}
    : >"${TEST_ROOT}/events"
    : >"${TEST_ROOT}/guard-ready"
    sh "${TEST_ROOT}/runner.sh" >"${TEST_ROOT}/run.log" 2>&1 &
    RUNNER_PID=$!
    python3 - "${TEST_ROOT}" "${RUNNER_PID}" <<'PY'
import json
from pathlib import Path
import sys
import time

root, parent = Path(sys.argv[1]), int(sys.argv[2])
for _ in range(100):
    if (root / "server.ready").exists():
        children = (Path(f"/proc/{parent}/task/{parent}/children")
                    .read_text().split())
        if len(children) == 2:
            server = (root / "server.pid").read_text()
            watcher = next(pid for pid in children if pid != server)
            try:
                if Path(f"/proc/{watcher}/task/{watcher}/children").read_text().split():
                    break
            except FileNotFoundError:
                pass
    time.sleep(0.02)
else:
    raise SystemExit("SSH server/guard watcher did not become ready")
identities = {}
pending = list(children)
while pending:
    pid = pending.pop()
    path = Path(f"/proc/{pid}")
    try:
        identities[pid] = path.joinpath("stat").read_text().split(") ", 1)[1].split()[19]
        pending.extend(path.joinpath(f"task/{pid}/children").read_text().split())
    except FileNotFoundError:
        pass
(root / "children.json").write_text(json.dumps(identities))
PY
    [[ -s "${TEST_ROOT}/state/fail2ban-ssh.state" && -s "${TEST_ROOT}/ban" ]] ||
        fail "${scenario}: 测试未建立 owner 与封禁"
    token=$(sed -n 's/^token=//p' "${TEST_ROOT}/state/fail2ban-ssh.state")
    case "${scenario}" in
    expired) rm -f -- "${TEST_ROOT}/guard-ready" ;;
    term) kill -TERM "${RUNNER_PID}" ;;
    natural) : >"${TEST_ROOT}/server-release" ;;
    esac
    # 限时只等待本次入口退出，失败后仍交给 cleanup 精确停止它。
    python3 - "${RUNNER_PID}" <<'PY'
from pathlib import Path
import sys
import time

path = Path(f"/proc/{sys.argv[1]}/stat")
for _ in range(200):
    try:
        if path.read_text().split(") ", 1)[1].split()[0] == "Z":
            break
    except FileNotFoundError:
        break
    time.sleep(0.02)
else:
    raise SystemExit("SSH entrypoint did not exit")
PY
    status=0
    wait "${RUNNER_PID}" || status=$?
    RUNNER_PID=
    [[ "${status}" == 0 ]] || fail "${scenario}: 正常清理返回 ${status}"
    [[ ! -e "${TEST_ROOT}/state/fail2ban-ssh.state" && ! -e "${TEST_ROOT}/ban" ]] ||
        fail "${scenario}: 退出后遗留 owner 或封禁"
    grep -qxF "cleanup ${token}" "${TEST_ROOT}/events" || fail "${scenario}: 未按当前 owner 清理"
    [[ "$(grep -c '^cleanup ' "${TEST_ROOT}/events")" == 1 ]] || fail "${scenario}: 重复执行清理"
    if [[ "${scenario}" == expired ]]; then
        grep -Fq 'SSH collector guard failed; stopping current jail' "${TEST_ROOT}/run.log" ||
            fail 'guard 失效未报告原因'
    fi
    if [[ "${scenario}" == natural ]]; then
        grep -qx server-natural "${TEST_ROOT}/events" || fail '自然退出场景未执行'
        ! grep -q '^client-stop$' "${TEST_ROOT}/events" || fail '自然退出后又停止了 server'
    else
        grep -qx server-TERM "${TEST_ROOT}/events" || fail "${scenario}: 未正常停止 server"
    fi
    python3 - "${TEST_ROOT}/children.json" <<'PY'
import json
from pathlib import Path
import sys

for pid, identity in json.loads(Path(sys.argv[1]).read_text()).items():
    try:
        current = Path(f"/proc/{pid}/stat").read_text().split(") ", 1)[1].split()[19]
    except FileNotFoundError:
        continue
    if current == identity:
        raise SystemExit(f"SSH child survived exit: {pid}")
PY
    kill -0 "${SENTINEL_PID}" || fail "${scenario}: 误停无关进程"
done
printf 'docker-ssh-start-regression-ok\n'
