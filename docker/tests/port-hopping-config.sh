#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-port-hopping-config.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
trap 'printf "docker-port-hopping-config-fail: line %s, rc=%s\n" "${LINENO}" "$?" >&2' ERR
[[ "$(uname -s)" == Linux && "$(id -u)" == 0 ]] || exit 1
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state" PADM_DOCKER_SKIP_CHOWN=0
export PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_LOCK_TIMEOUT=1 PYTHONDONTWRITEBYTECODE=1
root=${PADM_DOCKER_INSTALL_DIR}
LOG=${TEST_ROOT}/command.log
MODE=ok
UUID=11111111-1111-4111-8111-111111111111
SAVED='{"listener_id":"entry-hy2","range_start":36000,"range_end":36002,"ipv4":"198.18.1.1","ipv6":"2001:db8:1::1"}'
fail() {
    [[ ! -f "${LOG}" ]] || sed 's/^/  /' "${LOG}" >&2
    printf 'docker-port-hopping-config-fail: %s\n' "$*" >&2
    exit 1
}
reject() { if "$@" >"${LOG}" 2>&1; then fail "应拒绝: $*"; fi; }

# 外部发布与启动使用桩，规格、编排、权限、锁、事务和恢复仍走生产实现。
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/install-docker.sh"
dockerHostPreflight() { :; }
dockerRequireInstalledBundle() { :; }
dockerConfigureReleasePrepare() { :; }
dockerConfigureReleaseValidate() { :; }
dockerTrafficRuntimeCheck() { :; }
dockerTrafficBeforeChange() { :; }
dockerTrafficScheduleInstall() { :; }
dockerRenewalScheduleInstall() { :; }
dockerGeoScheduleInstall() { :; }
dockerTlsValidateCandidate() { :; }
dockerIPv6NetworkManage() { :; }
dockerConfigurePortsAvailable() { :; }
dockerManifestImageReference() {
    jq -er --arg image "$1" '.images[$image]' "${TEST_ROOT}/base.json"
}
dockerCurrentBundlePath() { printf '%s\n' "${TEST_ROOT}/bundle"; }
dockerCandidateCompose() {
    [[ -d "$1" && -e "${root}/locks/deployment.lock" ]] || fail '候选未持有部署锁'
}
docker() { :; }
dockerComposeRun() {
    [[ -e "${root}/locks/deployment.lock" ]] || fail '事务未持有部署锁'
    if [[ "${1:-}" == up && "${MODE}" == health-fail && ! -e "${TEST_ROOT}/failed-once" ]]; then
        : >"${TEST_ROOT}/failed-once"
        return 1
    fi
}
dockerComposeExecute() {
    [[ "$*" == down ]] || fail "意外恢复启停参数: $*"
    dockerComposeRun "$@"
}
mkdir -p "${TEST_ROOT}/bundle/docker/contracts"
printf '%s\n' "$(printf 'a%.0s' {1..40})" >"${TEST_ROOT}/bundle/${PADM_DOCKER_BUNDLE_REF}"
cp -- "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${TEST_ROOT}/bundle/docker/contracts/"
dockerInitializeStateRoot
jq -n --arg uuid "${UUID}" '
  {schema_version:3,release:{version:"3.1.8",manifest_sha256:("a"*64),signature_identity:"fixture"},
   core:{type:"sing-box",secondary_type:null,protocols:[{
     id:3,core:"sing-box",listener_id:"entry-hy2",server:"proxy.example.com",public_port:35442,
     address_families:["ipv4","ipv6"],name:"hy2",uuid:$uuid,
     hy2:{domain:"tls.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:100,
       obfs:null,masquerade:""}}]},
   tls:{domain:"tls.example.com"},subscription:{enabled:false,token:"0123456789abcdef"},
   images:(["xray","sing-box","nginx","ops","net"] | map({key:.,value:
     ("ghcr.io/example/padm-"+.+":test@sha256:"+("a"*64))}) | from_entries),
   host_integrations:[]}
' >"${TEST_ROOT}/base.json"
jq --argjson saved "${SAVED}" '.port_hopping=$saved' \
    "${TEST_ROOT}/base.json" >"${TEST_ROOT}/saved.json"

# 类型边界同时查 Schema；跨字段和支持范围交给生产校验。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "base.json").read_text())
saved = json.loads((root / "saved.json").read_text())
validator = Draft202012Validator(
    json.loads((project / "docker/contracts/configure.schema.json").read_text()),
    format_checker=FormatChecker())
validator.validate(base)
validator.validate(saved)
cases = []

def case(name, value, schema_valid=None):
    if schema_valid is not None:
        assert validator.is_valid(value) == schema_valid, name
    (root / f"{name}.json").write_text(json.dumps(value))
    cases.append(name)

for key, value in (
        ("range_start", 0), ("range_end", 65536), ("range_start", True),
        ("range_end", "36002"), ("listener_id", "entry-missing"),
        ("ipv4", "127.0.0.1"), ("ipv6", "::1"), ("ipv6", "::ffff:198.18.1.1"),
        ("range_start", 36003), ("range_start", 35442)):
    invalid = copy.deepcopy(saved)
    invalid["port_hopping"][key] = value
    case(f"field-{len(cases)}", invalid,
         False if key in {"range_start", "range_end"} and
         (type(value) is not int or value in {0, 65536}) else None)
for key in ("extra", "missing"):
    invalid = copy.deepcopy(saved)
    if key == "extra":
        invalid["port_hopping"]["automatic"] = True
    else:
        del invalid["port_hopping"]["ipv6"]
    case(key, invalid, False)
for name, update in (
        ("single-family", lambda value: value["core"]["protocols"][0].update(address_families=["ipv4"])),
        ("multiple-listeners", lambda value: value["core"]["protocols"].append(
            dict(value["core"]["protocols"][0], listener_id="entry-second", public_port=35443))),
        ("subscription", lambda value: value["subscription"].update(enabled=True)),
        ("aliases", lambda value: value.update(
            port_aliases=[dict(listener_id="entry-hy2", public_port=37000)])),
        ("legacy", lambda value: value.update(schema_version=2))):
    invalid = copy.deepcopy(saved)
    update(invalid)
    case(name, invalid)
(root / "invalid-cases").write_text("\n".join(cases) + "\n")
PY
dockerConfigureSpecValidate "${TEST_ROOT}/base.json" >"${LOG}" 2>&1 || fail '基线规格无效'
dockerConfigureSpecValidate "${TEST_ROOT}/saved.json" >"${LOG}" 2>&1 || fail '保存规格无效'
while IFS= read -r name; do
    reject dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json"
done <"${TEST_ROOT}/invalid-cases"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/saved.json" || fail '当前 bundle 拒绝跳跃配置'
jq 'del(."x-padm-port-hopping-manual")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/saved.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" || fail '旧 bundle 拒绝普通规格'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"

snapshot() (
    cd "${root}"
    find config data secrets -type f -printf '%p %m %U %G %n\n' | LC_ALL=C sort
    find config data secrets -type f -print0 | sort -z | xargs -0 -r sha256sum
    for path in compose.json deployment.json deployment.previous.json images.env; do
        [[ ! -f "${path}" ]] || sha256sum "${path}"
    done
)
assertClean() {
    [[ ! -e "${root}/locks/deployment.lock" ]] || fail '事务遗留部署锁'
    [[ -z "$(find "${root}" -maxdepth 1 \( -name '.candidate.*' -o -name '.edit.*' \) -print -quit)" ]] ||
        fail '事务遗留候选'
}
runEdit() {
    local expected=$1 actual=0
    shift
    (dockerMain edit "$@") >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "edit $*: 预期 ${expected}，实际 ${actual}"
    assertClean
}
assertSaved() {
    jq -en --argjson saved "${SAVED}" --slurpfile spec "${root}/config/spec.json" \
        --slurpfile deployment "${root}/deployment.json" --slurpfile compose "${root}/compose.json" '
      $spec[0].port_hopping == $saved and $deployment[0].port_hopping == $saved and
      $compose[0]["x-padm-port-hopping"] == $saved and
      ($compose[0].services | keys) == ["acme","sing-box"]
    ' >/dev/null || fail '规格、部署与编排未同步或新增跳跃服务'
    dockerManagedSpecMatchesDeployment "${root}/config/spec.json" "${root}/deployment.json" \
        "${root}/images.env" || fail '受管部署与规格不匹配'
}
mkdir -p "${root}/secrets/tls"
printf '%s\n' fixture-certificate >"${root}/secrets/tls/tls.example.com.crt"
printf '%s\n' fixture-private-key >"${root}/secrets/tls/tls.example.com.key"
chmod 0640 "${root}/secrets/tls/"*
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化受管 Hy2 夹具失败'
assertClean
jq -cn --arg uuid "${UUID}" '{schema_version:1,accounts:{($uuid):{
  name:"business",upload:17,download:19,limit_bytes:0,baseline:{}}}}' | dockerTrafficWriteState
before=$(snapshot)
runEdit 0 --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 --preview
for arguments in \
    '--port-hopping entry-hy2 0 36002 198.18.1.1 2001:db8:1::1' \
    '--port-hopping entry-hy2 36003 36002 198.18.1.1 2001:db8:1::1' \
    '--port-hopping entry-hy2 36000 65536 198.18.1.1 2001:db8:1::1' \
    '--port-hopping-clear --socks5-off' \
    '--port-hopping-clear --port-hopping-clear'; do
    read -r -a words <<<"${arguments}"
    runEdit 2 "${words[@]}" --preview
done
runEdit 2 --port-hopping-clear --spec "${TEST_ROOT}/saved.json" --preview
runEdit 2 --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 --port-hopping-clear --preview
runEdit 15 --port-hopping entry-missing 36000 36002 198.18.1.1 2001:db8:1::1 --preview
runEdit 15 --port-hopping entry-hy2 35442 36002 198.18.1.1 2001:db8:1::1 --preview
runEdit 15 --spec "${TEST_ROOT}/saved.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '预览或拒绝编辑改变在线状态'
runEdit 0 --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
assertSaved
[[ ! -e "${root}/data/net/.hopping-supervisor" ]] || fail '保存配置自动启动监督'
before=$(snapshot)
(
    trap dockerReleaseDeploymentLock EXIT
    dockerAcquireDeploymentLock
    dockerPortHoppingTargetStartManaged() { fail '参数漂移仍启动核心或采集累计'; }
    dockerPortHoppingTargetFileSnapshot() { fail '参数漂移仍进入文件采集'; }
    reject dockerPortHoppingTargetPrepareActivation \
        entry-hy2 36000 36003 198.18.1.1 2001:db8:1::1
)
assertClean
[[ "$(snapshot)" == "${before}" ]] || fail '保存参数不匹配时改变在线状态'
python3 - "${PROJECT_ROOT}/docker/contracts/deployment.schema.json" "${root}/deployment.json" <<'PY'
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

schema, value = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
Draft202012Validator(schema, format_checker=FormatChecker()).validate(value)
PY
for change in '.port_hopping.range_end=65536' '.port_hopping.extra=true'; do
    jq "${change}" "${root}/deployment.json" >"${TEST_ROOT}/bad-deployment.json"
    reject dockerDeploymentFileValidate "${TEST_ROOT}/bad-deployment.json"
done
jq '.port_hopping.range_end=36003' "${root}/deployment.json" >"${TEST_ROOT}/bad-deployment.json"
reject dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
    "${TEST_ROOT}/bad-deployment.json" "${root}/images.env"
before=$(snapshot)
runEdit 0 --port-hopping-clear --preview
runEdit 15 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
jq '.port_hopping.range_end=36003' "${root}/config/spec.json" >"${TEST_ROOT}/import-change.json"
runEdit 15 --spec "${TEST_ROOT}/import-change.json" --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '清除预览或普通规格导入改变保存配置'
MODE=health-fail
runEdit 14 --port-hopping-clear --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail '启动失败未完整恢复旧跳跃配置'
assertSaved
MODE=ok
mkdir -m 0700 "${root}/data/net/.hopping-supervisor"
runEdit 12 --port-hopping-clear --confirm PADM-DOCKER-EDIT
runEdit 12 --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
rmdir "${root}/data/net/.hopping-supervisor"
[[ "$(snapshot)" == "${before}" ]] || fail '活动会话拒绝编辑时改变业务文件'
(dockerMain port-hopping status) >"${LOG}" 2>&1 || fail '保存未启用时状态查询失败'
jq -e --argjson saved "${SAVED}" '.=={state:"stopped",saved:$saved}' "${LOG}" >/dev/null ||
    fail '保存未启用时状态返回不正确'
(
    dockerPortHoppingSupervisorStart() { [[ "$#" == 0 ]] || fail '启动仍从 CLI 接收 tuple'; }
    dockerPortHoppingSupervisorStop() { [[ "$#" == 0 ]] || fail '停止接收额外参数'; }
    [[ "$(dockerMain port-hopping start)" == '端口跳跃已启用。' ]] || fail '启动缺少成功提示'
    [[ "$(dockerMain port-hopping stop)" == '端口跳跃已停止；保存配置保留。' ]] || fail '停止缺少成功提示'
    for action in status start stop; do
        actual=0
        dockerMain port-hopping "${action}" unexpected >"${LOG}" 2>&1 || actual=$?
        [[ "${actual}" == 2 ]] || fail "${action} 未拒绝额外参数"
    done
)
runEdit 0 --port-hopping-clear --confirm PADM-DOCKER-EDIT
for file in "${root}/config/spec.json" "${root}/deployment.json"; do
    jq -e 'has("port_hopping")|not' "${file}" >/dev/null || fail '清除后遗留保存配置'
done
jq -e 'has("x-padm-port-hopping")|not' "${root}/compose.json" >/dev/null ||
    fail '清除后编排遗留保存配置'
reject dockerMain port-hopping start
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload==17 and .accounts[$uuid].download==19' \
    "${root}/data/traffic/state.json" >/dev/null || fail '配置事务改写累计流量'

# 单个 PTY 会话验证真实菜单进程分发与编辑前台输入，不重复完整菜单矩阵。
command -v script >/dev/null || fail '菜单检查需要 util-linux script'
export PROJECT_ROOT TEST_ROOT
cat >"${TEST_ROOT}/menu-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_ROOT}/menu.calls"
if [[ "${1:-}" == edit ]]; then
    [[ -t 0 ]] || exit 19
    printf 'fixture-edit-confirm [y/N]: '
    IFS= read -r answer || exit 0
    [[ "${answer}" != y ]] || printf '%s\n' "$*" >>"${TEST_ROOT}/menu.writes"
fi
SH
cat >"${TEST_ROOT}/menu-driver.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
source "${PROJECT_ROOT}/docker/lib/setup.sh"
source "${PROJECT_ROOT}/docker/lib/menu.sh"
dockerMenuCli() { printf '%s\n' "${TEST_ROOT}/menu-cli.sh"; }
dockerMenuProtocols
SH
: >"${TEST_ROOT}/menu.calls"
: >"${TEST_ROOT}/menu.writes"
printf '%s\n' 11 1 2 entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 y \
    3 n 3 y 4 5 n 2 0 2 entry-hy2 0 0 0 |
    timeout 10 script -qefc "bash '${TEST_ROOT}/menu-driver.sh'" /dev/null >"${LOG}" 2>&1 ||
    fail '端口跳跃菜单 PTY 分发失败'
printf '%s\n' 'protocol list' 'port-hopping status' \
    'edit --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1' \
    'port-hopping start' 'port-hopping stop' 'edit --port-hopping-clear' \
    >"${TEST_ROOT}/menu.expected"
cmp -s "${TEST_ROOT}/menu.calls" "${TEST_ROOT}/menu.expected" || fail '菜单分发或取消行为错误'
[[ "$(cat "${TEST_ROOT}/menu.writes")" == \
    'edit --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1' ]] ||
    fail '取消清除仍写入保存配置'
for input in $'11\n' $'11\n2\n' $'11\n3\n' $'11\n2\nentry-hy2\n'; do
    : >"${TEST_ROOT}/menu.calls"
    printf '%s' "${input}" | timeout 5 bash "${TEST_ROOT}/menu-driver.sh" >"${LOG}" 2>&1 ||
        fail '菜单 EOF 未返回'
    [[ "$(cat "${TEST_ROOT}/menu.calls")" == 'protocol list' ]] || fail '菜单 EOF 触发动作'
done

printf 'docker-port-hopping-config-ok\n'
