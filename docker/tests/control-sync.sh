#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-control-sync.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-control-sync-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/backups" \
    "${PADM_DOCKER_INSTALL_DIR}/.bundles"
chmod 0700 "${PADM_DOCKER_INSTALL_DIR}"

# 规划器使用生产实现与 JSON Schema；夹具不启动 WireGuard，不冒充双节点验收。
python3 - "${PROJECT_ROOT}" "${PADM_DOCKER_INSTALL_DIR}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

root, state = map(Path, sys.argv[1:])
sys.path.insert(0, str(root / "docker/images/ops"))
import control_sync as sync
import control_api as api

def identity(n):
    return f"{n:08d}-1111-4111-8111-{n:012d}"

def account(n):
    return dict(id=identity(n), name=f"账号{n}", enabled=True, uuid=identity(n + 100),
                password=f"Password.-~@+=:{n:08d}", shadowsocks_password=None)

def save(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)

controller, node = identity(1), identity(2)
local = account(3)
local["listeners"] = ["entry-reality"]
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
    "tls": None, "subscription": {"enabled": False, "token": "control-sync-token"},
    "images": {name: f"ghcr.io/example/padm-{name}:test@sha256:" + "1" * 64
               for name in ("xray", "sing-box", "nginx", "ops", "net")},
    "host_integrations": [], "accounts": [local],
    "control_sync": {"schema_version": 1, "role": "controlled", "node_id": node,
        "controller_id": controller, "listener_ids": ["entry-reality"],
        "last_revision": None, "last_digest": None, "managed_accounts": []},
}
desired = dict(ok=True, api_version=1, controller_id=controller, node_id=node,
               revision=7, accounts=[account(4), account(5)])
schema = json.loads((root / "docker/contracts/configure.schema.json").read_text())
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
validator.validate(spec)
draft = sync.build_draft(spec, desired)
validator.validate(draft)
assert draft["accounts"][0] == local and spec["control_sync"]["last_revision"] is None
assert sync.build_draft(draft, desired) == draft
reordered = copy.deepcopy(desired)
reordered["accounts"].reverse()
assert sync.build_draft(draft, reordered) == draft
with_extra = copy.deepcopy(draft)
extra = account(6)
extra["listeners"] = ["entry-reality"]
with_extra["accounts"].append(extra)
assert sync.build_draft(with_extra, desired) == with_extra

def reject(base, request):
    try:
        sync.build_draft(base, request)
    except (ValueError, KeyError, TypeError):
        return
    raise AssertionError("同步规划器未拒绝冲突")

for field, value in (("controller_id", identity(6)), ("node_id", identity(6)),
                     ("api_version", 2), ("api_version", True), ("revision", True),
                     ("revision", 6), ("revision", 9007199254740992)):
    request = copy.deepcopy(desired)
    request[field] = value
    reject(draft, request)
request = copy.deepcopy(desired)
request["accounts"][0]["name"] = "同版本冲突"
reject(draft, request)
request["revision"] = 8
updated = sync.build_draft(draft, request)
assert updated["control_sync"]["last_revision"] == 8
for field in ("id", "uuid", "password"):
    collision = copy.deepcopy(request)
    collision["accounts"][0][field] = local[field]
    reject(draft, collision)
collision = copy.deepcopy(request)
collision["accounts"][0]["uuid"] = local["id"]
reject(draft, collision)
collision = copy.deepcopy(request)
collision["accounts"][0]["id"] = spec["core"]["protocols"][0]["uuid"]
reject(draft, collision)
collision = copy.deepcopy(request)
collision["accounts"][0]["uuid"] = collision["accounts"][1]["id"]
reject(draft, collision)
drift = copy.deepcopy(draft)
drift["accounts"][1]["password"] += "changed"
reject(drift, request)
drift = copy.deepcopy(draft)
drift["control_sync"]["listener_ids"] = ["entry-missing"]
reject(drift, request)
request = copy.deepcopy(desired)
request.update(revision=8, accounts=[])
removed = sync.build_draft(draft, request)
assert removed["accounts"] == [local] and removed["control_sync"]["managed_accounts"] == []
ss_spec = copy.deepcopy(spec)
ss_spec["core"]["protocols"][0]["id"] = 30
reject(ss_spec, desired)
ss_request = copy.deepcopy(desired)
ss_request["accounts"][0]["shadowsocks_password"] = "AQEBAQEBAQEBAQEBAQEBAQ=="
ss_request["accounts"][1]["shadowsocks_password"] = "AgICAgICAgICAgICAgICAg=="
assert all(a["shadowsocks_password"] for a in sync.build_draft(ss_spec, ss_request)["accounts"][1:])
assert all(a["shadowsocks_password"] is None for a in sync.build_draft(spec, ss_request)["accounts"][1:])
save(state / "config/spec.json", spec)
save(state / "desired.json", desired)
save(state / "next-desired.json", dict(desired, revision=8, accounts=[account(5)]))
save(state / "expected.json", draft)
save(state / "extra-account.json", extra)
bad = state / "duplicate.json"
bad.write_text('{"ok":true,"ok":true}')
bad.chmod(0o600)
try:
    sync.read_input(bad, api.MAX_STATE_BYTES)
    raise AssertionError("重复字段未拒绝")
except ValueError:
    pass
bad.write_text("[" * 1100 + "0" + "]" * 1100)
try:
    sync.read_input(bad, api.MAX_STATE_BYTES)
    raise AssertionError("深层损坏 JSON 未拒绝")
except (ValueError, RecursionError):
    pass
PY

# 外部发布、核心与宿主动作使用桩；候选生成、备份、安装、恢复及权限均走生产路径。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerLockInstalledDeployment() { :; }
dockerReleaseDeploymentLock() { :; }
dockerRequireInstalledBundle() { :; }
dockerConfigureReleaseReuseInstalled() { :; }
dockerConfigureReleaseValidate() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
}
dockerRealityTargetsValidate() { :; }
dockerConfigurePortsAvailable() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
# 工具容器执行层使用桩；超时和 cidfile 清理复用已验收的探针 helper。
dockerRealityProbeRun() {
    [[ "$1" == 30 ]] || return 1
    shift
    docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges "$@"
}
docker() {
    if [[ " $* " == *' /opt/padm/control_sync.py '* ]]; then
        local previous= argument directory=
        for argument in "$@"; do
            if [[ "${previous}" == --mount ]]; then
                directory=${argument#type=bind,src=}
                directory=${directory%,dst=/input,readonly}
            fi
            previous=${argument}
        done
        [[ -n "${directory}" && " $* " == *' --network none '* &&
            " $* " == *' --cap-drop ALL '* && " $* " == *' --user 0:0 '* ]]
        python3 "${PROJECT_ROOT}/docker/images/ops/control_sync.py" \
            --spec "${directory}/spec.json" --desired "${directory}/desired.json"
    fi
}
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
root=${PADM_DOCKER_INSTALL_DIR}
spec="${root}/config/spec.json"
mkdir -p "${root}/data/traffic"
jq -n '{schema_version:1,accounts:{
  "00000004-1111-4111-8111-000000000004":{
    name:"账号4",upload:12,download:34,limit_bytes:100,baseline:{}}}}' >"${root}/data/traffic/state.json"
chmod 0600 "${root}/data/traffic/state.json"
traffic=$(sha256sum "${root}/data/traffic/state.json")
dockerInstallBundle "${PROJECT_ROOT}" "$(printf a%.0s {1..40})"
dockerControlSyncApply "${root}/desired.json"
jq -en --slurpfile got "${spec}" --slurpfile expected "${root}/expected.json" \
    '$got == $expected' >/dev/null
[[ "$(stat -c '%a:%u:%g' "${spec}")" == 600:0:0 ]]
[[ "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
before=$(sha256sum "${spec}")
upCount=$(wc -l <"${TEST_ROOT}/compose.log")
dockerControlSyncApply "${root}/desired.json"
[[ "$(wc -l <"${TEST_ROOT}/compose.log")" == "${upCount}" ]]
[[ "$(sha256sum "${spec}")" == "${before}" ]]
for action in enable disable; do
    if dockerAccountCommand "${action}" 00000004-1111-4111-8111-000000000004; then exit 1; fi
done
for action in delete rotate; do
    if dockerAccountCommand "${action}" 00000004-1111-4111-8111-000000000004 --yes; then exit 1; fi
done
if dockerAccountCommand edit 00000004-1111-4111-8111-000000000004 --name changed; then exit 1; fi
jq 'del(.control_sync)' "${spec}" >"${root}/without-sync.json"
if dockerControlSyncTransitionValidate "${root}/without-sync.json"; then exit 1; fi
mkdir -p "${TEST_ROOT}/old-bundle/docker/contracts"
jq 'del(.["x-padm-control-sync"])' "$(dockerConfigureSchemaFile)" \
    >"${TEST_ROOT}/old-bundle/docker/contracts/configure.schema.json"
cp -- "$(dockerFeatureMatrixFile)" "${TEST_ROOT}/old-bundle/docker/contracts/features.json"
if dockerBundleSupportsSpec "${TEST_ROOT}/old-bundle" "${spec}"; then exit 1; fi

# 本机追加账号后数组顺序变了，同版本重试仍不能触发重建。
dockerAccountMutate '.accounts += $extra' --slurpfile extra "${root}/extra-account.json"
before=$(sha256sum "${spec}")
upCount=$(wc -l <"${TEST_ROOT}/compose.log")
dockerControlSyncApply "${root}/desired.json"
[[ "$(wc -l <"${TEST_ROOT}/compose.log")" == "${upCount}" ]]
[[ "$(sha256sum "${spec}")" == "${before}" ]]
touch "${TEST_ROOT}/fail-up"
if dockerControlSyncApply "${root}/next-desired.json"; then exit 1; fi
[[ "$(sha256sum "${spec}")" == "${before}" ]]
[[ "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
for signal in INT TERM; do
    printf '%s\n' "${signal}" >"${TEST_ROOT}/interrupt-up"
    status=0
    dockerControlSyncApply "${root}/next-desired.json" || status=$?
    [[ "${signal}:${status}" == INT:130 || "${signal}:${status}" == TERM:143 ]]
    [[ "$(sha256sum "${spec}")" == "${before}" ]]
    [[ "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
done
dockerControlSyncApply "${root}/next-desired.json"
jq -e '.control_sync.last_revision == 8 and (.accounts | length) == 3 and
    any(.accounts[]; .id == "00000006-1111-4111-8111-000000000006")' "${spec}" >/dev/null
[[ "$(sha256sum "${root}/data/traffic/state.json")" == "${traffic}" ]]
[[ -z "$(find "${root}" -maxdepth 1 \( -name '.control-sync.*' -o -name '.candidate.*' \) -print -quit)" ]]
printf 'docker-control-sync-regression-ok\n'
