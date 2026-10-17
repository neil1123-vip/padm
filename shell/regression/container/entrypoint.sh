#!/usr/bin/env bash
set -euo pipefail

mkdir -p /work "${HOME}" "${TMPDIR}"
tar -xf /snapshot.tar -C /work
# 只规范容器内 UTF-8 文本的 CRLF，保留二进制，不改工作区。
python3 - <<'PY'
from pathlib import Path

for path in Path("/work").rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    data = path.read_bytes()
    if b"\0" in data or b"\r\n" not in data:
        continue
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        continue
    path.write_bytes(data.replace(b"\r\n", b"\n"))
PY
cd /work
if [[ "${1:-fast}" == docker-contracts || "${1:-fast}" == docker-contracts-full ||
    "${1:-fast}" == docker-port-hopping-preflight ]]; then
    # 完整合同及独立跳跃 CI 分片复用解释器启动，生产仍使用原入口。
    # shellcheck source=/dev/null
    source shell/regression/container/snapshot-fork-runtime.sh
    if ! padmSnapshotForkStart; then
        printf 'snapshot fork adapter 启动失败，使用原 Python 入口\n' >&2
        unset PADM_SNAPSHOT_FORK_CLIENT PADM_SNAPSHOT_FORK_SOCKET PADM_SNAPSHOT_FORK_PID
    fi
fi
exec bash shell/subscription_groups_regression.sh "${1:-fast}"
