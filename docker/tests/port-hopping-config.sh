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
tuic_base = copy.deepcopy(base)
entry = tuic_base["core"]["protocols"][0]
del entry["hy2"]
entry.update(id=31, listener_id="entry-tuic", name="tuic",
             tuic=dict(domain="tls.example.com", congestion_control="cubic",
                       auth_timeout="3s", heartbeat="10s", zero_rtt_handshake=False))
tuic_saved = copy.deepcopy(tuic_base)
tuic_saved["port_hopping"] = dict(saved["port_hopping"], listener_id="entry-tuic")
for name, value in (("tuic-base", tuic_base), ("tuic-saved", tuic_saved)):
    validator.validate(value)
    (root / f"{name}.json").write_text(json.dumps(value))
# TUIC 只补协议支持边界，通用字段类型和数值矩阵复用上面的 Hy2 案例。
for name, update in (
        ("single-family", lambda value: value["core"]["protocols"][0].update(address_families=["ipv4"])),
        ("multiple-listeners", lambda value: value["core"]["protocols"].append(
            dict(value["core"]["protocols"][0], listener_id="entry-second", public_port=35443))),
        ("subscription", lambda value: value["subscription"].update(enabled=True)),
        ("aliases", lambda value: value.update(
            port_aliases=[dict(listener_id="entry-tuic", public_port=37000)])),
        ("legacy", lambda value: value.update(schema_version=2))):
    invalid = copy.deepcopy(tuic_saved)
    update(invalid)
    case(f"tuic-{name}", invalid)
(root / "invalid-cases").write_text("\n".join(cases) + "\n")
PY
dockerConfigureSpecValidate "${TEST_ROOT}/base.json" >"${LOG}" 2>&1 || fail '基线规格无效'
dockerConfigureSpecValidate "${TEST_ROOT}/saved.json" >"${LOG}" 2>&1 || fail '保存规格无效'
dockerConfigureSpecValidate "${TEST_ROOT}/tuic-saved.json" >"${LOG}" 2>&1 || fail 'TUIC 保存规格无效'
while IFS= read -r name; do
    reject dockerConfigureSpecValidate "${TEST_ROOT}/${name}.json"
done <"${TEST_ROOT}/invalid-cases"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/saved.json" || fail '当前 bundle 拒绝跳跃配置'
jq 'del(."x-padm-port-hopping-manual")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/saved.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/base.json" || fail '旧 bundle 拒绝普通规格'
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${TEST_ROOT}/bundle/docker/contracts/"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/tuic-saved.json" ||
    fail '当前 bundle 拒绝 TUIC 跳跃配置'
jq 'del(."x-padm-port-hopping-tuic")' "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    >"${TEST_ROOT}/bundle/docker/contracts/configure.schema.json"
reject dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/tuic-saved.json"
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/saved.json" ||
    fail '缺少 TUIC 跳跃能力仍应兼容已有 Hy2 跳跃配置'
dockerBundleSupportsSpec "${TEST_ROOT}/bundle" "${TEST_ROOT}/tuic-base.json" ||
    fail '缺少 TUIC 跳跃能力错误拒绝普通 TUIC 规格'
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
# 原根路径保留编排挂载，完整备份在子进程退出时恢复，不干扰后续已有规格案例。
(
    cp -a -- "${root}" "${TEST_ROOT}/legacy-backup"
    trap 'rm -rf -- "${root}"; mv -- "${TEST_ROOT}/legacy-backup" "${root}"' EXIT
    rm -- "${root}/config/spec.json"
    before=$(snapshot)
    runEdit 15 --confirm PADM-DOCKER-EDIT
    jq '.core.protocols[0].uuid="22222222-2222-4222-8222-222222222222"' \
        "${TEST_ROOT}/base.json" >"${TEST_ROOT}/legacy-wrong.json"
    runEdit 15 --spec "${TEST_ROOT}/legacy-wrong.json" --confirm PADM-DOCKER-EDIT
    [[ "$(snapshot)" == "${before}" ]] || fail '缺少或错误原始规格接入改变在线状态'
    runEdit 0 --spec "${TEST_ROOT}/base.json" --confirm PADM-DOCKER-EDIT
    [[ -f "${root}/config/spec.json" ]] || fail '完整原始规格接入未保存受管规格'
    runEdit 0 --port-hopping entry-hy2 36000 36002 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
    assertSaved
    [[ ! -e "${root}/data/net/.hopping-supervisor" ]] || fail '旧部署接入保存时自动启动监督'
    for path in config/sing-box/config.json config/sing-box/users.base data/traffic/state.json; do
        cmp -s -- "${root}/${path}" "${TEST_ROOT}/legacy-backup/${path}" ||
            fail "旧部署接入或跳跃保存改写账号或累计: ${path}"
    done
    dockerPortHoppingSupervisorStart() {
        [[ "$#" == 0 ]] || fail '旧部署接入后启动仍从 CLI 接收 tuple'
        [[ "$(dockerPortHoppingSavedArguments)" == \
            '["entry-hy2","36000","36002","198.18.1.1","2001:db8:1::1"]' ]] ||
            fail '旧部署接入后启动未使用已保存参数'
    }
    dockerMain port-hopping start >"${LOG}" 2>&1 || fail '旧部署接入后无法启动已保存跳跃配置'
)
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
# 原投影摘要未核验前，不得用现场镜像启动带 NET_ADMIN 的预检。
(
    stage=$(mktemp -d "${root}/.hopping-guarded.XXXXXX")
    trap 'rm -rf -- "${stage}"' EXIT
    target=$(jq -cn --argjson saved "${SAVED}" \
        '$saved + {target_port:35442,startup_binding:{lock:{}}}')
    printf '%s\n' "${target}" >"${stage}/prepared.json"
    jq -cn --argjson target "${target}" '{target:$target}' >"${stage}/supervised.json"
    child=$(jq -cn '{Id:("b"*64),Image:("sha256:"+("c"*64)),
      State:{Status:"exited",Running:false,ExitCode:0},
      Config:{Labels:{"io.padm.hopping-supervised":("d"*64)},Hostname:"fixture"}}')
    cid=$(jq -r '.Id' <<<"${child}")
    printf '%s\n' "${cid}" >"${stage}/cid"
    owner=$(jq -cn --arg root "${root}" --arg stage "${stage}" '{root:$root,
      state:"active",stage:$stage,bash:{pid:99999},stage_sha256:("0"*64)}')
    dockerPortHoppingTargetBindingCheck() { :; }
    dockerPortHoppingGuardedContainer() { printf '%s\n' "${child}"; }
    timeout() {
        [[ "$1 $2 $3" == '-k 2 5' ]] || fail '恢复使用意外检查时限'
        shift 3
        "$@"
    }
    docker() {
        case "$*" in
        "container inspect ${cid}") printf '[%s]\n' "${child}" ;;
        run\ *) : >"${TEST_ROOT}/recovery-untrusted-run" ;;
        *) fail "恢复调用意外 Docker 命令: $*" ;;
        esac
    }
    reject dockerPortHoppingRecoveryInspect "${owner}"
    grep -Fq '恢复投影与原监督摘要不一致' "${LOG}" || fail '恢复未抵达原投影摘要核验'
    [[ ! -e "${TEST_ROOT}/recovery-untrusted-run" ]] || fail '错误原投影仍启动 NET_ADMIN 预检'
)
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
    dockerPortHoppingSupervisorStatus() {
        jq -n --argjson saved "${SAVED}" --argjson end "${STATUS_END:-36002}" \
            '{payload:{target:($saved + {range_end:$end,target_port:35442,protocol_id:3})}}'
    }
    recoverPreview=$(jq -cn --argjson saved "${SAVED}" '{state:"recoverable",saved:$saved,
      owner_sha256:("a"*64),child_id:("b"*64),stage:"/fixture-stage"}')
    recoverConfirmed=$(jq -c '.state="stopped"' <<<"${recoverPreview}")
    : >"${TEST_ROOT}/recover.calls"
    dockerPortHoppingSupervisorRecover() {
        if [[ "$#" == 0 ]]; then
            printf 'preview\n' >>"${TEST_ROOT}/recover.calls"
            printf '%s\n' "${recoverPreview}"
        else
            [[ "$#" == 1 && "$1" == --confirm ]] || fail '恢复收到未授权参数'
            printf '%s\n' "$1" >>"${TEST_ROOT}/recover.calls"
            printf '%s\n' "${recoverConfirmed}"
        fi
    }
    [[ "$(dockerMain port-hopping recover --preview)" == "${recoverPreview}" ]] ||
        fail '恢复预览未透传五键 JSON'
    [[ "$(dockerMain port-hopping recover --confirm PADM-DOCKER-HOPPING-RECOVER)" == "${recoverConfirmed}" ]] ||
        fail '恢复确认未透传五键 JSON'
    for arguments in '' '--preview unexpected' '--confirm' '--confirm invalid' \
        '--confirm PADM-DOCKER-HOPPING-RECOVER unexpected'; do
        read -r -a words <<<"${arguments}"
        actual=0
        dockerMain port-hopping recover "${words[@]}" >"${LOG}" 2>&1 || actual=$?
        [[ "${actual}" == 2 ]] || fail "recover 未拒绝非法参数: ${arguments}"
    done
    [[ "$(cat "${TEST_ROOT}/recover.calls")" == $'preview\n--confirm' ]] ||
        fail '恢复参数分发错误或非法调用进入监督'
    [[ "$(dockerMain port-hopping start)" == '端口跳跃已启用。' ]] || fail '启动缺少成功提示'
    [[ "$(dockerMain port-hopping stop)" == '端口跳跃已停止；保存配置保留。' ]] || fail '停止缺少成功提示'
    [[ "$(dockerMain port-hopping share)" == \
        "hysteria2://${UUID}@proxy.example.com:36000-36002?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3#hy2" ]] ||
        fail '活动范围分享链接不正确'
    jq '.core.protocols[0].hy2 |= (.bandwidth_mode="brutal" | .up_mbps=120 |
      .down_mbps=60 | .obfs={type:"salamander",password:"hy2-obfs-private_1234"})' \
        "${root}/config/spec.json" >"${TEST_ROOT}/brutal-share.json"
    runEdit 0 --spec "${TEST_ROOT}/brutal-share.json" --confirm PADM-DOCKER-EDIT
    before=$(snapshot)
    [[ "$(dockerMain port-hopping share)" == \
        "hysteria2://${UUID}@proxy.example.com:36000-36002?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3&upmbps=60&downmbps=120&up=60&down=120&obfs=salamander&obfs-password=hy2-obfs-private_1234#hy2" ]] ||
        fail '活动范围分享未保留带宽方向或混淆参数'
    [[ "$(dockerMain port-hopping share 36001)" == \
        "hysteria2://${UUID}@proxy.example.com:36001?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3&upmbps=60&downmbps=120&up=60&down=120&obfs=salamander&obfs-password=hy2-obfs-private_1234#hy2" ]] ||
        fail 'Hy2 指定活动端口分享未保留认证、带宽或混淆参数'
    [[ "$(snapshot)" == "${before}" ]] || fail '活动范围分享改变受管文件'
    STATUS_END=36003
    if dockerMain port-hopping share >"${LOG}" 2>&1; then fail '活动范围漂移仍生成分享链接'; fi
    unset STATUS_END
    for action in status start stop share; do
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

# TUIC 完整编辑事务复用同一夹具和恢复断言，不复制通用的非法数值矩阵。
SAVED=$(jq -cn --argjson saved "${SAVED}" '$saved | .listener_id="entry-tuic"')
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    dockerConfigureApply "${TEST_ROOT}/tuic-base.json" '' '' configure
) >"${LOG}" 2>&1 || fail '初始化受管 TUIC 夹具失败'
assertClean
before=$(snapshot)
runEdit 0 --port-hopping entry-tuic 36000 36002 198.18.1.1 2001:db8:1::1 --preview
[[ "$(snapshot)" == "${before}" ]] || fail 'TUIC 跳跃预览改变在线状态'
runEdit 0 --port-hopping entry-tuic 36000 36002 198.18.1.1 2001:db8:1::1 --confirm PADM-DOCKER-EDIT
assertSaved
python3 - "${PROJECT_ROOT}/docker/contracts/deployment.schema.json" "${root}/deployment.json" <<'PY'
import json
import sys
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

schema, value = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
Draft202012Validator(schema, format_checker=FormatChecker()).validate(value)
assert value["core"]["protocol_ids"] == [31]
PY
before=$(snapshot)
MODE=health-fail
rm -f -- "${TEST_ROOT}/failed-once"
runEdit 14 --port-hopping-clear --confirm PADM-DOCKER-EDIT
[[ "$(snapshot)" == "${before}" ]] || fail 'TUIC 清除启动失败未恢复全部受管文件'
assertSaved
MODE=ok
(
    dockerPortHoppingSupervisorStart() { [[ "$#" == 0 ]] || fail 'TUIC 启动接收额外 tuple'; }
    dockerPortHoppingSupervisorStop() { [[ "$#" == 0 ]] || fail 'TUIC 停止接收额外参数'; }
    dockerPortHoppingSupervisorStatus() {
        [[ "${STATUS_STOPPED:-0}" == 0 ]] || return 1
        jq -n --argjson saved "${SAVED}" --argjson end "${STATUS_END:-36002}" \
            --argjson protocol "${STATUS_PROTOCOL:-31}" \
            '{payload:{target:($saved + {range_end:$end,target_port:35442,protocol_id:$protocol})}}'
    }
    [[ "$(dockerMain port-hopping start)" == '端口跳跃已启用。' ]] || fail 'TUIC 启动缺少成功提示'
    [[ "$(dockerMain port-hopping stop)" == '端口跳跃已停止；保存配置保留。' ]] || fail 'TUIC 停止缺少成功提示'
    uri="tuic://${UUID}:${UUID}@proxy.example.com:36000?congestion_control=cubic&alpn=h3&sni=tls.example.com&udp_relay_mode=native&allow_insecure=0#tuic"
    [[ "$(dockerMain port-hopping share)" == "${uri}" ]] || fail 'TUIC 默认分享没有使用普通首端口 URI'
    [[ "$(dockerMain port-hopping share 36001)" == "${uri/:36000?/:36001?}" ]] ||
        fail 'TUIC 指定活动端口分享丢失参数或输出范围 URI'
    [[ "$(snapshot)" == "${before}" ]] || fail 'TUIC 分享改变受管文件'
    for port in 0 01 65536 abc -1; do
        actual=0
        dockerMain port-hopping share "${port}" >"${LOG}" 2>&1 || actual=$?
        [[ "${actual}" == 2 ]] || fail "分享接受非法端口: ${port}"
    done
    actual=0
    dockerMain port-hopping share 36003 >"${LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 15 ]] || fail '分享接受范围外端口'
    STATUS_END=36003
    reject dockerMain port-hopping share
    reject dockerMain port-hopping share 36001
    unset STATUS_END
    STATUS_PROTOCOL=3
    reject dockerMain port-hopping share
    reject dockerMain port-hopping share 36001
    unset STATUS_PROTOCOL
    STATUS_STOPPED=1
    reject dockerMain port-hopping share
    reject dockerMain port-hopping share 36001
)
runEdit 0 --port-hopping-clear --confirm PADM-DOCKER-EDIT
for file in "${root}/config/spec.json" "${root}/deployment.json"; do
    jq -e 'has("port_hopping")|not' "${file}" >/dev/null || fail 'TUIC 清除后遗留保存配置'
done
jq -e --arg uuid "${UUID}" '.accounts[$uuid].upload==17 and .accounts[$uuid].download==19' \
    "${root}/data/traffic/state.json" >/dev/null || fail 'TUIC 跳跃事务改写累计流量'

# 单个 PTY 会话验证真实菜单进程分发与编辑前台输入，不重复完整菜单矩阵。
command -v script >/dev/null || fail '菜单检查需要 util-linux script'
export PROJECT_ROOT TEST_ROOT
cat >"${TEST_ROOT}/menu-cli.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${TEST_ROOT}/menu.calls"
if [[ "$*" == 'port-hopping recover --preview' && "${MENU_RECOVER_PREVIEW_FAIL:-0}" == 1 ]]; then
    exit 15
fi
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
trap 'dockerMenuInterrupted 130; printf "fixture-int-ready\n"' INT
dockerMenuProtocols
SH
: >"${TEST_ROOT}/menu.calls"
: >"${TEST_ROOT}/menu.writes"
printf '%s\n' 11 1 6 7 0 7 36001 2 entry-tuic 36000 36002 198.18.1.1 2001:db8:1::1 y \
    3 n 3 y 4 5 n 8 n 8 y 2 0 2 entry-hy2 0 0 0 |
    timeout 10 script -qefc "bash '${TEST_ROOT}/menu-driver.sh'" /dev/null >"${LOG}" 2>&1 ||
    fail '端口跳跃菜单 PTY 分发失败'
printf '%s\n' 'protocol list' 'port-hopping status' 'port-hopping share' \
    'port-hopping share 36001' \
    'edit --port-hopping entry-tuic 36000 36002 198.18.1.1 2001:db8:1::1' \
    'port-hopping start' 'port-hopping stop' 'edit --port-hopping-clear' \
    'port-hopping recover --preview' 'port-hopping recover --preview' \
    'port-hopping recover --confirm PADM-DOCKER-HOPPING-RECOVER' \
    >"${TEST_ROOT}/menu.expected"
cmp -s "${TEST_ROOT}/menu.calls" "${TEST_ROOT}/menu.expected" || fail '菜单分发或取消行为错误'
[[ "$(cat "${TEST_ROOT}/menu.writes")" == \
    'edit --port-hopping entry-tuic 36000 36002 198.18.1.1 2001:db8:1::1' ]] ||
    fail '取消清除仍写入保存配置'

# 复用已有 PTY 驱动方式，真实 SIGINT 后必须仍在子菜单并能继续查看状态。
: >"${TEST_ROOT}/menu.calls"
python3 - "${TEST_ROOT}/menu-driver.sh" "${LOG}" <<'PY'
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import termios
import time

def terminal_session():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    signal.signal(signal.SIGINT, signal.SIG_DFL)

master, slave = pty.openpty()
process = subprocess.Popen(["bash", sys.argv[1]], stdin=slave, stdout=slave,
                           stderr=slave, preexec_fn=terminal_session)
os.close(slave)
output = bytearray()

def expect(text, count=1):
    deadline = time.monotonic() + 3
    while output.count(text.encode()) < count:
        assert process.poll() is None and time.monotonic() < deadline, output.decode()
        if select.select([master], [], [], 0.05)[0]:
            output.extend(os.read(master, 65536))

try:
    expect("请选择: ")
    os.write(master, b"11\n")
    expect("请选择: ", 2)
    os.killpg(os.getpgid(process.pid), signal.SIGINT)
    expect("fixture-int-ready")
    os.write(master, b"1\n")
    expect("Docker 端口跳跃（单个双族 Hy2/TUIC）", 2)
    expect("请选择: ", 3)
    os.write(master, b"0\n0\n")
    assert process.wait(timeout=3) == 0, output.decode()
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    Path(sys.argv[2]).write_bytes(output)
PY
[[ "$(cat "${TEST_ROOT}/menu.calls")" == $'protocol list\nport-hopping status' ]] ||
    fail '菜单中断后未在当前子菜单继续操作'
for input in $'11\n' $'11\n2\n' $'11\n3\n' $'11\n2\nentry-hy2\n' $'11\n7\n'; do
    : >"${TEST_ROOT}/menu.calls"
    printf '%s' "${input}" | timeout 5 bash "${TEST_ROOT}/menu-driver.sh" >"${LOG}" 2>&1 ||
        fail '菜单 EOF 未返回'
    [[ "$(cat "${TEST_ROOT}/menu.calls")" == 'protocol list' ]] || fail '菜单 EOF 触发动作'
done
: >"${TEST_ROOT}/menu.calls"
printf '11\n8\n' | timeout 5 bash "${TEST_ROOT}/menu-driver.sh" >"${LOG}" 2>&1 ||
    fail '恢复确认 EOF 未返回'
[[ "$(cat "${TEST_ROOT}/menu.calls")" == $'protocol list\nport-hopping recover --preview' ]] ||
    fail '恢复确认 EOF 仍提交清理'
: >"${TEST_ROOT}/menu.calls"
printf '11\n8\n1\n0\n0\n' | MENU_RECOVER_PREVIEW_FAIL=1 \
    timeout 5 bash "${TEST_ROOT}/menu-driver.sh" >"${LOG}" 2>&1 ||
    fail '恢复预览失败后菜单未返回'
[[ "$(cat "${TEST_ROOT}/menu.calls")" == \
    $'protocol list\nport-hopping recover --preview\nport-hopping status' ]] ||
    fail '恢复预览失败后仍读取确认或提交清理'
if grep -Fq '确认清理已核验的退出会话并保留保存配置？' "${LOG}"; then
    fail '恢复预览失败仍提示确认'
fi

printf 'docker-port-hopping-config-ok\n'
