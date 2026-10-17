#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-recovery-cli.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"

fail() { printf 'docker-backup-regression-fail: %s\n' "$*" >&2; exit 1; }
python3 -B "${PROJECT_ROOT}/docker/tests/recovery.py"
python3 -B "${PROJECT_ROOT}/docker/tests/acme_recovery.py"

# verify 必须绕开部署、Docker 和全局恢复；调用任何一项都让测试失败。
dockerHostPreflight() { fail 'verify 调用了 Docker 预检'; }
dockerInstallRoot() { fail 'verify 读取了部署状态'; }
dockerReleaseDeploymentLock() { fail 'verify 创建或释放了部署锁'; }
dockerAcmeChallengeRestore() { fail 'verify 触发了全局恢复'; }
dockerSetupCleanup() { fail 'verify 触发了全局清理'; }
python3 -B - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import importlib.util
import pathlib
import sys
spec = importlib.util.spec_from_file_location("recovery", pathlib.Path(sys.argv[1]) / "docker/lib/recovery.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
base = pathlib.Path(sys.argv[2])
root = base / "state"
root.mkdir(mode=0o750)
for name in module.REQUIRED:
    path = root / name
    path.parent.mkdir(mode=0o750, parents=True, exist_ok=True)
    path.write_bytes(b"{}\n")
    path.chmod(0o600)
module.export_archive(str(root), str(base / "private archive.tar"))
PY
dockerMain backup verify "${TEST_ROOT}/private archive.tar" >/dev/null ||
    fail '独立只读校验失败'
status=0
dockerMain backup verify "${TEST_ROOT}/missing.tar" >"${TEST_ROOT}/reject.log" 2>&1 || status=$?
[[ "${status}" -eq "${PADM_DOCKER_RC_STATE}" ]] || fail '归档拒绝退出码错误'
[[ ! -e "${TEST_ROOT}/state/locks" ]] || fail '只读校验创建了锁目录'

# export 只替换宿主门禁；实际归档、拒覆盖和锁释放仍经过生产命令。
dockerHostPreflight() { :; }
dockerInstallRoot() { printf '%s\n' "${TEST_ROOT}/state"; }
dockerLockInstalledDeployment() { printf 'lock\n' >>"${TEST_ROOT}/calls"; }
dockerReleaseDeploymentLock() { printf 'release\n' >>"${TEST_ROOT}/calls"; }
dockerAccountSpecFile() { printf '%s\n' "${TEST_ROOT}/state/config/spec.json"; }
dockerManagedSpecMatchesDeployment() { :; }
dockerMain backup export "${TEST_ROOT}/cli export.tar" >/dev/null || fail 'CLI 导出失败'
[[ "$(cat "${TEST_ROOT}/calls")" == $'lock\nrelease' ]] || fail '导出未正确释放锁'
status=0
dockerMain backup export "${TEST_ROOT}/cli export.tar" >/dev/null 2>&1 || status=$?
[[ "${status}" -eq "${PADM_DOCKER_RC_STATE}" ]] || fail '导出拒覆盖退出码错误'
[[ "$(tail -n 2 "${TEST_ROOT}/calls")" == $'lock\nrelease' ]] || fail '导出失败未释放锁'
dockerManagedSpecMatchesDeployment() { return 1; }
status=0
dockerMain backup export "${TEST_ROOT}/drift.tar" >/dev/null 2>&1 || status=$?
[[ "${status}" -eq "${PADM_DOCKER_RC_STATE}" && ! -e "${TEST_ROOT}/drift.tar" ]] ||
    fail '部署漂移仍允许导出'
[[ "$(tail -n 2 "${TEST_ROOT}/calls")" == $'lock\nrelease' ]] || fail '规格拒绝未释放锁'
printf 'docker-backup-regression-ok\n'
