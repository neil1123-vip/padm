#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-state.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-state-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
mkdir -p "${root}/config" "${root}/backups" "${root}/.bundles" "${root}/secrets/net/wireguard"
chmod 0700 "${root}"

# 只读 API 投影与生产规划器共享校验，不以桩代替账号版本合同。
python3 - "${PROJECT_ROOT}" "${root}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
sys.path.insert(0, str(project / "docker/images/ops"))
import control_state as planner

def identity(n):
    return f"{n:08d}-1111-4111-8111-{n:012d}"

def account(n):
    return dict(id=identity(n), name=f"账号{n}", enabled=True, uuid=identity(n + 100),
                password=f"Password.-~@+=:{n:08d}", shadowsocks_password=None,
                listeners=["entry-reality"])

def save(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)

spec = {
    "schema_version": 3,
    "release": {"version": "3.1.8", "manifest_sha256": "1" * 64, "signature_identity": "fixture"},
    "core": {"type": "xray", "secondary_type": None, "protocols": [{
        "id": 1, "core": "xray", "server": "reality.example.com", "public_port": 443,
        "address_families": ["ipv4"], "listener_id": "entry-reality", "name": "main",
        "uuid": identity(9), "reality": {"server_name": "reality.example.com",
            "target_host": "reality.example.com", "target_port": 443,
            "private_key": "A" * 43, "public_key": "B" * 43, "short_id": "1234abcd"}
    }]},
    "tls": None, "subscription": {"enabled": False, "token": "control-state-token"},
    "images": {name: f"ghcr.io/example/padm-{name}:test@sha256:" + "1" * 64
               for name in ("xray", "sing-box", "nginx", "ops", "net")},
    "host_integrations": [dict(type="wireguard", profile="net-wireguard", firewall_rules=[],
        devices=["wg-padm"], schedules=[], settings=dict(config_file="wg-padm.conf", interface="wg-padm"))],
    "accounts": [account(3), account(4)],
    "control": dict(schema_version=1, role="main", node_id=identity(1),
        listen=dict(interface="wg-padm", address="10.77.0.1", port=18080),
        peer=dict(id=identity(2), address="10.77.0.2", enabled=True,
            expires_at=2000000000, token_sha256="a" * 64), revision=0, last_digest=None),
}
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
validator.validate(spec)
first = planner.build_plan(spec)
validator.validate(first["spec"])
assert first["state"]["revision"] == 0
assert all("listeners" not in a for a in first["state"]["accounts"])
assert spec["control"]["last_digest"] is None
empty = copy.deepcopy(spec)
empty["accounts"] = []
assert planner.build_plan(empty)["spec"]["control"]["last_digest"] is not None
reordered = copy.deepcopy(first["spec"])
reordered["accounts"].reverse()
assert planner.build_plan(reordered, first["spec"])["state"] == first["state"]
mapping = copy.deepcopy(first["spec"])
mapping["accounts"][0]["listeners"] = ["entry-other"]
assert planner.build_plan(mapping, first["spec"])["state"] == first["state"]
changed = copy.deepcopy(first["spec"])
changed["accounts"][0]["name"] = "新账号名"
next_plan = planner.build_plan(changed, first["spec"])
assert next_plan["state"]["revision"] == 1
assert planner.build_plan(first["spec"], next_plan["spec"])["state"]["revision"] == 2
assert planner.build_plan(first["spec"], first["spec"]) == first
authorization = copy.deepcopy(first["spec"])
authorization["control"]["peer"]["enabled"] = False
assert planner.build_plan(authorization, first["spec"])["state"]["revision"] == 0

def reject(value, previous=None):
    try:
        planner.build_plan(value, previous)
    except (ValueError, KeyError, TypeError):
        return
    raise AssertionError("主控规划器未拒绝损坏输入")

bad = copy.deepcopy(first["spec"])
bad["accounts"][0]["name"] = "摘要不符"
reject(first["spec"], bad)
reject(bad)
bad = copy.deepcopy(changed)
bad["control"]["revision"] = planner.MAX_REVISION
reject(bad, first["spec"])
bad = copy.deepcopy(first["spec"])
bad["control"]["node_id"] = identity(8)
reject(bad, first["spec"])
for mutation in (lambda s: s.update(control_sync={}),
                 lambda s: s.update(host_integrations=[]),
                 lambda s: s.update(schema_version=2)):
    bad = copy.deepcopy(spec)
    mutation(bad)
    assert not validator.is_valid(bad)
save(root / "initial.json", spec)
save(root / "changed.json", changed)
save(root / "published.json", first["spec"])
PY

# 核心、宿主和发布动作使用桩；生成、备份、安装、恢复和权限走生产路径。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerReleaseDeploymentLock() { :; }
dockerRequireInstalledBundle() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerConfigureReleaseValidate() { :; }
dockerRealityTargetsValidate() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${root}/initial.json"
}
dockerRealityProbeRun() {
    [[ "$1" == 30 ]] || return 1
    shift
    docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges "$@"
}
docker() {
    if [[ " $* " == *' /opt/padm/control_state.py '* ]]; then
        local previous= argument directory= check= old=
        local -a planFloors=()
        for argument in "$@"; do
            case "${previous}" in
            --mount) directory=${argument#type=bind,src=}; directory=${directory%,dst=/input,readonly} ;;
            --check-state) check=${argument#/input/} ;;
            --previous) old=${argument#/input/} ;;
            --plan-floor) planFloors+=("${argument#/input/}") ;;
            esac
            previous=${argument}
        done
        [[ -n "${directory}" && " $* " == *' --network none '* &&
            " $* " == *' --cap-drop ALL '* && " $* " == *' --user 0:0 '* ]]
        local -a args=(--spec "${directory}/spec.json")
        [[ -z "${check}" ]] || args+=(--check-state "${directory}/${check}")
        [[ -z "${old}" ]] || args+=(--previous "${directory}/${old}")
        for argument in "${planFloors[@]}"; do
            args+=(--plan-floor "${directory}/${argument}")
        done
        python3 "${PROJECT_ROOT}/docker/images/ops/control_state.py" "${args[@]}"
    fi
}
eval "$(declare -f dockerComposeRun | sed '1s/dockerComposeRun/dockerProductionComposeRun/')"
dockerComposeRun() {
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
    if [[ "${1:-}" == up && -f "${TEST_ROOT}/interrupt-up" ]]; then
        local signal
        signal=$(<"${TEST_ROOT}/interrupt-up")
        rm -- "${TEST_ROOT}/interrupt-up"
        kill -s "${signal}" "${BASHPID}"
    fi
    if [[ "${1:-}" == up && -f "${TEST_ROOT}/fail-up" ]]; then
        rm -- "${TEST_ROOT}/fail-up"
        return 1
    fi
}
apply() (
    trap dockerConfigurationInterrupted EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    dockerConfigureApply "$@"
)
printf '[Interface]\nPrivateKey = %s\nListenPort = 51820\n' "$(printf A%.0s {1..43})=" \
    >"${root}/secrets/net/wireguard/wg-padm.conf"
chmod 0600 "${root}/secrets/net/wireguard/wg-padm.conf"
dockerInstallBundle "${PROJECT_ROOT}" "$(printf a%.0s {1..40})"

if apply "${root}/initial.json"; then exit 1; fi
DOCKER_CONTROL_TRANSACTION=1 apply "${root}/initial.json"
spec="${root}/config/spec.json"
jq -e '.control.revision == 0 and .control.last_digest != null' "${spec}" >/dev/null
[[ "$(stat -c '%a:%u:%g' "${spec}")" == 600:0:0 ]]
[[ "$(stat -c '%a:%u:%g' "${root}/config/control/state.json")" == 640:0:10001 ]]
[[ "$(stat -c '%a:%u:%g' "${root}/config/control")" == 750:0:10001 ]]
jq -e '.services.control |
  .network_mode == "host" and .user == "10001:10001" and
  .cap_drop == ["ALL"] and (has("ports") | not) and
  .depends_on["net-wireguard"].condition == "service_healthy" and
  .volumes[0].target == "/etc/padm/control" and .volumes[0].read_only and
  .command == ["control","--state","/etc/padm/control/state.json"] and
  .healthcheck.test[-3:] == ["control-health","--state","/etc/padm/control/state.json"]' \
  "${root}/compose.json" >/dev/null
dockerControlStateCheck "${root}"
chmod 0666 "${spec}"
if dockerControlStateCheck "${root}"; then exit 1; fi
chmod 0600 "${spec}"
chmod 0770 "${root}/config"
if dockerControlStateCheck "${root}"; then exit 1; fi
chmod 0755 "${root}/config"
chmod 0770 "${root}"
if dockerControlStateCheck "${root}"; then exit 1; fi
chmod 0700 "${root}"
chmod 0770 "${root}/config/control"
if dockerControlStateCheck "${root}"; then exit 1; fi
chmod 0750 "${root}/config/control"
chmod 0660 "${root}/config/control/state.json"
if dockerControlStateCheck "${root}"; then exit 1; fi
backupsBefore=$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)
if dockerBackupConfiguration rollback; then exit 1; fi
[[ "$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)" == "${backupsBefore}" ]]
chmod 0640 "${root}/config/control/state.json"
mkdir -p "${TEST_ROOT}/empty/config/control"
jq 'del(.control)' "${spec}" >"${TEST_ROOT}/empty/config/spec.json"
dockerControlStateCheck "${TEST_ROOT}/empty"
touch "${TEST_ROOT}/empty/config/control/extra"
if dockerControlStateCheck "${TEST_ROOT}/empty"; then exit 1; fi
rm -- "${TEST_ROOT}/empty/config/control/extra"
ln -s "${root}/config/control/state.json" "${TEST_ROOT}/empty/config/control/state.json"
if dockerControlStateCheck "${TEST_ROOT}/empty"; then exit 1; fi
dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env"
jq '(.listeners[] | select(.listener_id == "host-control")).public_port = 19090' \
    "${root}/deployment.json" >"${root}/bad-deployment.json"
if dockerManagedSpecMatchesDeployment "${spec}" "${root}/bad-deployment.json" "${root}/images.env"; then exit 1; fi
jq '.control.peer.enabled = false' "${spec}" >"${root}/bad-role.json"
if dockerControlTransitionValidate "${root}/bad-role.json"; then exit 1; fi
jq '.core.protocols[0].public_port = .control.listen.port' "${spec}" >"${root}/collision.json"
if dockerConfigureSpecValidate "${root}/collision.json"; then exit 1; fi
mkdir -p "${TEST_ROOT}/old-bundle/docker/contracts"
jq 'del(.["x-padm-control-state"])' "$(dockerConfigureSchemaFile)" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/old-bundle/docker/contracts/features.json"
if dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${spec}"; then exit 1; fi
DOCKER_STAGED_BUNDLE_PATH="${TEST_ROOT}/old-bundle"
if dockerValidateUpdateCandidate "${root}"; then exit 1; fi
DOCKER_STAGED_BUNDLE_PATH=$(dockerCurrentBundlePath)

# 默认 umask 下创建更新候选仍须先收紧私有规格，再校验主控状态。
(
    umask 022
    PADM_DOCKER_MANIFEST_FILE="${TEST_ROOT}/update-manifest.json"
    jq --arg commit "$(printf b%.0s {1..40})" '
      {release: {version: .release.version, commit: $commit},
       images: (.images | with_entries(.value = {
         reference: .value, index_digest: (.value | split("@")[1])}))}
    ' "${spec}" >"${PADM_DOCKER_MANIFEST_FILE}"
    PADM_DOCKER_MANIFEST_SHA256=$(sha256sum "${PADM_DOCKER_MANIFEST_FILE}" | cut -d ' ' -f 1)
    PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=fixture
    dockerCreateUpdateCandidate
    [[ "$(stat -c '%a:%u:%g' "${DOCKER_CONFIG_CANDIDATE}/config/spec.json")" == 600:0:0 ]]
    dockerControlStateCheck "${DOCKER_CONFIG_CANDIDATE}"
    [[ "$(jq '.control.revision' "${DOCKER_CONFIG_CANDIDATE}/config/spec.json")" == 0 ]]
    dockerCleanupConfigurationCandidate
)

before=$(sha256sum "${spec}" "${root}/config/control/state.json")
upCount=$(wc -l <"${TEST_ROOT}/compose.log")
apply "${root}/changed.json" '' '' preview
[[ "$(sha256sum "${spec}" "${root}/config/control/state.json")" == "${before}" ]]
[[ "$(wc -l <"${TEST_ROOT}/compose.log")" == "${upCount}" ]]
apply "${root}/changed.json"
jq -e '.control.revision == 1 and .accounts[0].name == "新账号名"' "${spec}" >/dev/null
jq '.accounts[0].name = "部署失败账号"' "${spec}" >"${root}/failed.json"
chmod 0600 "${root}/failed.json"
touch "${TEST_ROOT}/fail-up"
if apply "${root}/failed.json"; then exit 1; fi
jq -e '.control.revision == 3 and .accounts[0].name == "新账号名"' "${spec}" >/dev/null
jq -e '.control.peer.enabled == false and .control.peer.expires_at == 1' "${spec}" >/dev/null
jq -e '.peer.enabled == false and .peer.expires_at == 1' "${root}/config/control/state.json" >/dev/null
for signal in INT TERM; do
    jq '.accounts[0].name = "信号失败账号"' "${spec}" >"${root}/failed.json"
    revision=$(jq '.control.revision' "${spec}")
    printf '%s\n' "${signal}" >"${TEST_ROOT}/interrupt-up"
    status=0
    apply "${root}/failed.json" || status=$?
    [[ "${signal}:${status}" == INT:130 || "${signal}:${status}" == TERM:143 ]]
    jq -e --argjson revision "$((revision + 2))" \
        '.control.revision == $revision and .accounts[0].name == "新账号名"' "${spec}" >/dev/null
done

# 部分安装缺失在线规格时，候选计划仍提供版本下限，备份不被改写。
dockerBackupConfiguration update
backup=${DOCKER_CONFIG_BACKUP}
backupDigest=$(sha256sum "${backup}/config/spec.json" "${backup}/config/control/state.json")
jq '.accounts[0].name = "安装中断账号"' "${spec}" >"${root}/partial.json"
chmod 0600 "${root}/partial.json"
revision=$(jq '.control.revision' "${spec}")
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${root}/partial.json" "${candidate}"
DOCKER_CONFIG_BACKUP=${backup}
DOCKER_CONFIG_SWITCHED=1
rm -- "${spec}"
dockerRestoreConfiguration
jq -e --argjson revision "$((revision + 2))" \
    '.control.revision == $revision and .accounts[0].name == "新账号名"' "${spec}" >/dev/null
[[ "$(sha256sum "${backup}/config/spec.json" "${backup}/config/control/state.json")" == "${backupDigest}" ]]
dockerCleanupConfigurationCandidate

# 禁用授权的规格复制失败后，重试仍以此前候选与恢复计划为版本下限。
dockerBackupConfiguration update
backup=${DOCKER_CONFIG_BACKUP}
revision=$(jq '.control.revision' "${spec}")
jq '.accounts[0].name = "恢复窗口账号"' "${spec}" >"${root}/window.json"
chmod 0600 "${root}/window.json"
dockerCreateConfigurationCandidate
candidate=${DOCKER_CONFIG_CANDIDATE}
dockerGenerateCandidate "${root}/window.json" "${candidate}"
DOCKER_CONFIG_BACKUP=${backup}
DOCKER_CONFIG_SWITCHED=1
cp() {
    if [[ "${1:-}" == -- &&
        "${2:-}" == "${DOCKER_CONTROL_RESTORE_PLAN:-}/config/spec.json" &&
        "${3:-}" == "${root}/config/spec.json" &&
        -f "${TEST_ROOT}/fail-restored-spec-copy" ]]; then
        return 1
    fi
    command cp "$@"
}
touch "${TEST_ROOT}/fail-restored-spec-copy"
if dockerRestoreConfiguration; then exit 1; fi
[[ ! -e "${spec}" && ! -e "${root}/config/control/state.json" ]]
[[ "$(jq '.spec.control.revision' "${candidate}/control-restore/control-plan.json")" == "$((revision + 2))" ]]
jq -e '.state.peer.enabled == false and .spec.control.peer.enabled == false' \
    "${candidate}/control-restore/control-plan.json" >/dev/null
dockerConfigurationInterrupted
[[ "${DOCKER_CONFIG_CANDIDATE}" == "${candidate}" &&
    "${DOCKER_CONFIG_SWITCHED}" == 1 &&
    -f "${candidate}/control-plan.json" &&
    -f "${candidate}/control-restore/control-plan.json" ]]
[[ "$(jq '.spec.control.revision' "${candidate}/control-restore/control-plan.json")" == "$((revision + 2))" ]]
backupsBefore=$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)
if dockerConfigureApply "${root}/window.json"; then exit 1; fi
if dockerCreateUpdateCandidate; then exit 1; fi
if dockerBackupConfiguration rollback; then exit 1; fi
[[ "${DOCKER_CONFIG_CANDIDATE}" == "${candidate}" &&
    "${DOCKER_CONFIG_SWITCHED}" == 1 && "${DOCKER_CONFIG_BACKUP}" == "${backup}" ]]
# 新进程清空事务变量仍须发现残留，不能发布较低版本或生成洗白备份。
(
    DOCKER_CONFIG_CANDIDATE=
    DOCKER_CONFIG_BACKUP=
    DOCKER_CONFIG_SWITCHED=0
    if dockerConfigureApply "${root}/window.json"; then exit 1; fi
    if dockerCreateUpdateCandidate; then exit 1; fi
    if dockerBackupConfiguration rollback; then exit 1; fi
    for action in up restart; do
        if dockerProductionComposeRun "${action}"; then exit 1; fi
    done
    for action in ps logs down; do
        dockerProductionComposeRun "${action}"
    done
    [[ -z "${DOCKER_CONFIG_CANDIDATE}" && -z "${DOCKER_CONFIG_BACKUP}" ]]
)
[[ ! -e "${spec}" &&
    "$(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d | sort)" == "${backupsBefore}" ]]
dockerControlRecoveryCheck current
rm -- "${TEST_ROOT}/fail-restored-spec-copy"
unset -f cp
dockerRestoreConfiguration
[[ "$(jq '.control.revision' "${spec}")" == "$((revision + 2))" ]]
dockerControlStateCheck "${root}"

# 同版本不同账号计划不能静默选取；损坏计划不改变在线规格。
cp -- "${candidate}/control-plan.json" "${candidate}/safe-plan.json"
python3 - "${PROJECT_ROOT}" "${candidate}/control-plan.json" "${spec}" <<'PY'
import json
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[1] + "/docker/images/ops")
import control_state as planner
path, current = map(Path, sys.argv[2:])
spec = json.loads(current.read_text())
spec["accounts"][0]["name"] = "同版本冲突账号"
spec["control"]["revision"] = 0
spec["control"]["last_digest"] = None
plan = planner.build_plan(spec)
plan["spec"]["control"]["revision"] = plan["state"]["revision"] = json.loads(current.read_text())["control"]["revision"]
path.write_text(json.dumps(plan))
path.chmod(0o600)
PY
before=$(sha256sum "${spec}")
DOCKER_CONFIG_SWITCHED=1
if dockerRestoreConfiguration; then exit 1; fi
[[ "$(sha256sum "${spec}")" == "${before}" ]]
cp -- "${candidate}/safe-plan.json" "${candidate}/control-plan.json"
DOCKER_CONFIG_SWITCHED=0
dockerCleanupConfigurationCandidate

dockerBackupConfiguration update
backup=${DOCKER_CONFIG_BACKUP}
backupDigest=$(sha256sum "${backup}/config/spec.json" "${backup}/config/control/state.json")
cp -- "${spec}" "${root}/safe-spec.json"
printf '{"broken":true}\n' >"${spec}"
DOCKER_CONFIG_BACKUP=${backup}
DOCKER_CONFIG_SWITCHED=1
if dockerRestoreConfiguration; then exit 1; fi
[[ "$(<"${spec}")" == '{"broken":true}' ]]
cp -- "${root}/safe-spec.json" "${spec}"
DOCKER_CONFIG_SWITCHED=0
dockerCleanupConfigurationCandidate
dockerControlStateCheck "${root}"
[[ "$(sha256sum "${backup}/config/spec.json" "${backup}/config/control/state.json")" == "${backupDigest}" ]]

# 显式恢复同内容不递增，回到旧账号内容按当前最大版本递增。
dockerBackupConfiguration update
backup=${DOCKER_CONFIG_BACKUP}
revision=$(jq '.control.revision' "${spec}")
DOCKER_CONFIG_BACKUP=${backup}
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration
[[ "$(jq '.control.revision' "${spec}")" == "${revision}" ]]
dockerCleanupConfigurationCandidate

# 即使旧备份授权仍启用，轮换或撤销后的回滚也不能复活它。
jq '.control.peer.enabled = true | .control.peer.expires_at = 2000000000' \
    "${spec}" >"${root}/reinvite.json"
chmod 0600 "${root}/reinvite.json"
DOCKER_CONTROL_TRANSACTION=1 apply "${root}/reinvite.json"
dockerBackupConfiguration update
rollbackBackup=${DOCKER_CONFIG_BACKUP}
jq -e '.control.peer.enabled == true' "${rollbackBackup}/config/spec.json" >/dev/null
jq '.accounts[0].name = "回滚前账号" | .control.peer.enabled = false |
    .control.peer.token_sha256 = ("b" * 64)' "${spec}" >"${root}/rollback-next.json"
chmod 0600 "${root}/rollback-next.json"
DOCKER_CONTROL_TRANSACTION=1 apply "${root}/rollback-next.json"
revision=$(jq '.control.revision' "${spec}")
dockerLatestUpdateBackup() { printf '%s\n' "${rollbackBackup}"; }
dockerRenewalRegistryValidate() { :; }
dockerRenewalEnabled() { return 1; }
cp() {
    # 模拟控制服务未成功停下；任何旧授权文件进入在线路径都会立即使断言失败。
    if [[ "${@: -1}" == "${root}/config/control" || "${@: -1}" == "${spec}" ]]; then
        [[ "${@: -2:1}" != "${rollbackBackup}/config/control" &&
            "${@: -2:1}" != "${rollbackBackup}/config/spec.json" ]] || return 1
    fi
    command cp "$@"
}
dockerRollbackCommand
unset -f cp
jq -e --argjson revision "$((revision + 1))" \
    '.control.revision == $revision and .accounts[0].name == "新账号名" and
     .control.peer.enabled == false and .control.peer.expires_at == 1' "${spec}" >/dev/null
jq -e '.peer.enabled == false and .peer.expires_at == 1' "${root}/config/control/state.json" >/dev/null
dockerControlStateCheck "${root}"
[[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.control-*' \) -print -quit)" ]]
# 悬空计划链接仍是恢复证据，不能在同进程失败清理时丢弃。
candidate="${root}/.candidate.dangling"
mkdir -p "${candidate}/control-restore"
DOCKER_CONFIG_CANDIDATE=${candidate}
DOCKER_CONFIG_SWITCHED=1
for plan in "${candidate}/control-plan.json" "${candidate}/control-restore/control-plan.json"; do
    ln -s "${candidate}/missing.json" "${plan}"
    if dockerCleanupConfigurationCandidate; then exit 1; fi
    [[ -L "${plan}" && "${DOCKER_CONFIG_CANDIDATE}" == "${candidate}" ]]
    rm -- "${plan}"
done
DOCKER_CONFIG_SWITCHED=0
dockerCleanupConfigurationCandidate
# 只剩恢复计划、更新候选及链接残留同样阻止新发布，正常清理后解除门禁。
residual="${root}/.update.residual"
mkdir -p "${residual}/control-restore"
printf '{}\n' >"${residual}/control-restore/control-plan.json"
if dockerControlRecoveryCheck; then exit 1; fi
dockerRemoveManagedTree "${root}" "${residual}"
ln -s "${TEST_ROOT}/empty" "${residual}"
if dockerControlRecoveryCheck; then exit 1; fi
rm -- "${residual}"
dockerControlRecoveryCheck
printf 'docker-control-state-regression-ok\n'
