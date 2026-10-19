#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    printf 'docker-permissions-regression-skip: Linux root is required\n'
    exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'docker-permissions-regression-fail: run as root\n' >&2; exit 1; }
for tool in jq python3 setpriv stat chown chmod; do
    command -v "${tool}" >/dev/null || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "/root/padm-docker-permissions.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bundle.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/manifest.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

fail() { printf 'docker-permissions-regression-fail: %s\n' "$*" >&2; exit 1; }
assertMetadata() {
    [[ "$(stat -c '%a %u %g' "$1")" == "$2" ]] || fail "unexpected permissions/owner: $1"
}
# 只隔离服务启停和只读归属查询，文件复制、属主和权限检查均使用实际共享函数。
dockerComposeExecute() {
    [[ "$*" == down ||
        "$*" == "up -d --force-recreate --wait --wait-timeout ${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ]] ||
        fail "unexpected restore service operation: $*"
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
}
dockerComposeRun() { dockerComposeExecute "$@"; }
dockerTrafficScheduleRemove() { printf 'removed\n' >>"${TEST_ROOT}/schedule.log"; }
docker() {
    [[ "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban-control --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban-ssh --filter label=com.docker.compose.oneoff=False' ||
        "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-transparent --filter label=com.docker.compose.oneoff=False' ]] ||
        fail "unexpected ownership query: $*"
    printf '%s\n' "$*" >>"${TEST_ROOT}/ownership.log"
    [[ "${OWNERSHIP_QUERY_FAIL:-0}" != 1 ]]
}

seedRuntimeSecrets() {
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0700 "${PADM_DOCKER_INSTALL_DIR}/secrets"
    printf 'certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.crt"
    printf 'private-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
    printf 'acme-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
    dockerTlsRuntimePermissions "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
}
assertRuntimeSecrets() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    assertMetadata "${root}/secrets" '700 0 0'
    assertMetadata "${root}/secrets/tls/example.com.key" '600 10001 10001'
    assertMetadata "${root}/secrets/tls/example.com.crt" '640 0 10001'
    assertMetadata "${root}/data/acme/account.conf" '600 10001 10001'
    # 进入实际 bind 子目录视图后降权，不让宿主私密父目录影响容器读取结论。
    (
        cd "${root}/secrets/tls"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r example.com.key && test -r example.com.crt && test "$(cat example.com.key)" = private-key'
    ) || fail 'container UID could not read the restored TLS key and certificate'
    (
        cd "${root}/data/acme"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r account.conf && test -w account.conf && test -w .'
    ) || fail 'container UID could not use the restored ACME account'
}

# 合并遍历仍须按原谓词处理特殊文件与 .key 目录，并传播批量工具错误。
(
    tls="${TEST_ROOT}/tls-batch"
    mkdir -p "${tls}/directory.key"
    printf 'certificate\n' >"${tls}/example.crt"
    printf 'private-key\n' >"${tls}/example.key"
    mkfifo "${tls}/special" "${tls}/special.key"
    chmod 0777 "${tls}"
    chmod 2777 "${tls}/directory.key"
    chmod 4777 "${tls}/example.crt" "${tls}/example.key"
    chmod 0611 "${tls}/special" "${tls}/special.key"
    chown -R 12345:12345 "${tls}"
    dockerTlsRuntimePermissions "${tls}" || fail 'TLS 批处理失败'
    assertMetadata "${tls}" '750 0 10001'
    assertMetadata "${tls}/example.crt" '640 0 10001'
    assertMetadata "${tls}/example.key" '600 10001 10001'
    assertMetadata "${tls}/directory.key" '2750 12345 12345'
    assertMetadata "${tls}/special" '611 0 10001'
    assertMetadata "${tls}/special.key" '611 12345 12345'
    ln -s example.crt "${tls}/unsafe"
    chmod 0600 "${tls}/example.crt"
    ! dockerTlsRuntimePermissions "${tls}" || fail 'TLS 批处理接受符号链接'
    assertMetadata "${tls}/example.crt" '600 0 10001'
    rm -- "${tls}/unsafe"
    for failedTool in chmod chown; do
        mockBin="${TEST_ROOT}/tls-${failedTool}"
        mkdir -- "${mockBin}"
        printf '#!/bin/sh\nexit 17\n' >"${mockBin}/${failedTool}"
        chmod 0755 "${mockBin}/${failedTool}"
        ! PATH="${mockBin}:${PATH}" dockerTlsRuntimePermissions "${tls}" ||
            fail "TLS 批处理吞掉 ${failedTool} 错误"
    done
) || fail 'TLS 批处理边界检查失败'

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/configured"
dockerInitializeStateRoot
dockerInstallBundle "${PROJECT_ROOT}" "$(printf 'a%.0s' {1..40})"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/xray" "${PADM_DOCKER_INSTALL_DIR}/data/subscription"
seedRuntimeSecrets
jq -n '
    def ref($name): "ghcr.io/example/padm-" + $name + ":3.2.0@sha256:" + ("2" * 64);
    {schema_version:1, release:{version:"3.2.0",manifest_sha256:("a"*64),signature_identity:"test"},
     core:{type:"xray",protocols:[{id:21,server:"proxy.example.com",public_port:24443,
       address_families:["ipv4"],name:"main",uuid:"11111111-1111-4111-8111-111111111111",
       websocket:{domain:"example.com",path:"abcdefgh"}}]},
     tls:{domain:"example.com"},subscription:{enabled:false,token:("a"*32)},
     images:{xray:ref("xray"),"sing-box":ref("sing-box"),nginx:ref("nginx"),ops:ref("ops"),net:ref("net")},
     host_integrations:[]}
' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq -n --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
    $spec[0] as $s |
    {schema_version:1,mode:"docker",padm_version:$s.release.version,bundle_version:"fixture",
     manifest:{sha256:$s.release.manifest_sha256,signature_identity:$s.release.signature_identity},
     compose:{project:"padm-docker",profiles:["core-xray","nginx"]},
     core:{type:"xray",protocol_ids:[21]},
     listeners:[{service:"nginx",public_port:24443,container_port:8443,transport:"tcp",address_families:["ipv4"]}],
     images:($s.images|with_entries(.value={index_digest:(.value|split("@")|last)})),
     formats:{compose:1,config:1,data:1},previous_manifest_sha256:null,host_integrations:[]}
' >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
printf '{"name":"padm-docker","services":{}}\n' >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
jq -r '.images | "PADM_XRAY_IMAGE=" + .xray, "PADM_SINGBOX_IMAGE=" + ."sing-box",
    "PADM_NGINX_IMAGE=" + .nginx, "PADM_OPS_IMAGE=" + .ops, "PADM_NET_IMAGE=" + .net' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerEnsureRuntimeDataPermissions
# 旧候选曾将全部 ACME 材料放宽为组可读；运行时准备须修复且不改内容。
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc"
printf 'domain-private-key\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc/example.com.key"
chmod 0640 "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" \
    "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc/example.com.key"
chmod 2750 "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc"
acmeDigest=$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" \
    "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc/example.com.key")
dockerEnsureRuntimeDataPermissions || fail '旧 ACME 权限修复失败'
assertRuntimeSecrets
assertMetadata "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc" '750 10001 10001'
assertMetadata "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc/example.com.key" '600 10001 10001'
[[ "$(sha256sum "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" \
    "${PADM_DOCKER_INSTALL_DIR}/data/acme/example.com_ecc/example.com.key")" == "${acmeDigest}" ]] ||
    fail 'ACME 权限修复改动账户或私钥内容'
# 配置切换、升级和首配共用候选权限入口，ACME 树不能重新变成 0640。
(
    candidate="${TEST_ROOT}/acme-candidate"
    mkdir -p "${candidate}/config" "${candidate}/data/"{static,subscription,xray,sing-box} \
        "${candidate}/logs/nginx"
    cp -a -- "${PADM_DOCKER_INSTALL_DIR}/data/acme" "${candidate}/data/"
    cp -a -- "${PADM_DOCKER_INSTALL_DIR}/secrets" "${candidate}/"
    cp -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${candidate}/config/"
    for file in mode deployment.json compose.json images.env; do
        cp -- "${PADM_DOCKER_INSTALL_DIR}/${file}" "${candidate}/"
    done
    cp -- "${candidate}/images.env" "${candidate}/images.runtime.env"
    chmod 0640 "${candidate}/data/acme/account.conf" \
        "${candidate}/data/acme/example.com_ecc/example.com.key"
    dockerPrepareCandidatePermissions "${candidate}" || fail 'ACME 候选权限准备失败'
    assertMetadata "${candidate}/data/acme/account.conf" '600 10001 10001'
    assertMetadata "${candidate}/data/acme/example.com_ecc/example.com.key" '600 10001 10001'
    # 直接使用归档库存检查，防止权限修复与备份安全边界再次漂移。
    python3 -B - "${PROJECT_ROOT}" "${candidate}" <<'PY' || exit 1
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("recovery", sys.argv[1] + "/docker/lib/recovery.py")
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
fd = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY)
try:
    assert "data/acme/account.conf" in recovery.inventory(fd)
finally:
    os.close(fd)
PY
    printf 'outside-secret\n' >"${TEST_ROOT}/acme-outside"
    chmod 0600 "${TEST_ROOT}/acme-outside"
    chown 12345:12345 "${TEST_ROOT}/acme-outside"
    for entryType in symlink hardlink fifo; do
        case "${entryType}" in
        symlink) ln -s "${TEST_ROOT}/acme-outside" "${candidate}/data/acme/unsafe" ;;
        hardlink) ln "${TEST_ROOT}/acme-outside" "${candidate}/data/acme/unsafe" ;;
        fifo) mkfifo "${candidate}/data/acme/unsafe" ;;
        esac
        ! dockerPrepareCandidatePermissions "${candidate}" || fail "ACME 候选接受 ${entryType}"
        assertMetadata "${TEST_ROOT}/acme-outside" '600 12345 12345'
        rm -- "${candidate}/data/acme/unsafe"
    done
    for failedTool in chmod chown find; do
        mockBin="${TEST_ROOT}/acme-${failedTool}"
        mkdir -- "${mockBin}"
        printf '#!/bin/sh\nexit 17\n' >"${mockBin}/${failedTool}"
        chmod 0755 "${mockBin}/${failedTool}"
        ! PATH="${mockBin}:${PATH}" dockerAcmeRuntimePermissions "${candidate}/data/acme" ||
            fail "ACME 权限准备吞掉 ${failedTool} 错误"
    done
) || fail 'ACME 私密权限合同失败'
# 透明核心按真实编排保留 DAC_OVERRIDE，不能靠放宽文件或只改 check 用户绕过。
(
    transparent="${TEST_ROOT}/transparent-permissions"
    cp -a -- "${TEST_ROOT}/acme-candidate" "${transparent}"
    for core in xray sing-box; do
        for kind in tun tproxy redirect; do
            [[ "${kind}:${core}" != tun:xray ]] || continue
            jq --arg core "${core}" --arg kind "${kind}" '
              .schema_version = 3 | .core.type = $core | .core.secondary_type = null |
              .core.protocols |= map(.core = $core | .listener_id = "entry-main" |
                .address_families = ["ipv4"]) |
              .host_integrations = [{type:$kind,profile:"net-transparent",schedules:[],
                firewall_rules:[if $kind == "tun" then "sing-box-auto-redirect" else "padm-" + $kind end],
                devices:(if $kind == "tun" then ["/dev/net/tun"] else [] end),
                settings:(if $kind == "tun" then {interface:"padm-tun",address:"198.18.0.1/30"}
                  elif $kind == "tproxy" then {port:31298,mark:1} else {port:31298} end)}]
            ' "${PROJECT_ROOT}/docker/configure.example.json" >"${transparent}/config/spec.json"
            dockerGenerateCompose "${transparent}/config/spec.json" "${transparent}/compose.json" "${transparent}"
            dockerPrepareCandidatePermissions "${transparent}" || fail '透明核心候选权限准备失败'
            jq -e --arg core "${core}" '
              .services[$core].user == "0:0" and
              .services[$core].cap_drop == ["ALL"] and
              .services[$core].cap_add == ["NET_ADMIN","DAC_OVERRIDE"] and
              .services[$core].read_only == true and
              all(.services | to_entries[] | select(.key != $core);
                ((.value.cap_add // []) | index("DAC_OVERRIDE")) == null)
            ' "${transparent}/compose.json" >/dev/null || fail '透明核心能力范围错误'
            assertMetadata "${transparent}/data/${core}" '750 10001 10001'
            assertMetadata "${transparent}/secrets/tls/example.com.key" '600 10001 10001'
            (
                cd "${transparent}/data/${core}" || exit 1
                ! setpriv --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- \
                    sh -c 'cd . && printf blocked >permission-check' >/dev/null 2>&1 ||
                    fail '无 DAC 能力的 root 意外取得私密数据写权限'
                # NET_ADMIN 与文件访问无关，子进程只保留生成编排所需的 DAC 位。
                setpriv --bounding-set=-all,+dac_override --inh-caps=-all --ambient-caps=-all -- \
                    sh -c 'cd . && printf writable >permission-check && test "$(cat permission-check)" = writable' || exit 1
                rm -- permission-check
            ) || fail "透明核心 ${core}/${kind} 无法访问数据目录"
            (
                cd "${transparent}/secrets/tls" || exit 1
                ! setpriv --bounding-set=-all --inh-caps=-all --ambient-caps=-all -- \
                    cat example.com.key >/dev/null 2>&1 ||
                    fail '无 DAC 能力的 root 意外读取私钥'
                setpriv --bounding-set=-all,+dac_override --inh-caps=-all --ambient-caps=-all -- \
                    sh -c 'test "$(cat example.com.key)" = private-key && test -r example.com.crt'
            ) || fail "透明核心 ${core}/${kind} 无法读取私密 TLS"
            jq '.host_integrations = []' "${transparent}/config/spec.json" >"${transparent}/regular.json"
            mv -- "${transparent}/regular.json" "${transparent}/config/spec.json"
            dockerGenerateCompose "${transparent}/config/spec.json" "${transparent}/compose.json" "${transparent}"
            PADM_DOCKER_INSTALL_DIR=${transparent} dockerEnsureRuntimeDataPermissions ||
                fail '关闭透明模式后运行权限准备失败'
            jq -e --arg core "${core}" '
              .services[$core].user == null and (.services[$core].cap_add // []) == []
            ' "${transparent}/compose.json" >/dev/null || fail '普通核心保留透明能力'
            (
                cd "${transparent}/data/${core}" || exit 1
                setpriv --reuid 10001 --regid 10001 --clear-groups --bounding-set=-all \
                    --inh-caps=-all --ambient-caps=-all -- sh -c 'printf regular >permission-check' || exit 1
                rm -- permission-check
                cd "${transparent}/secrets/tls" || exit 1
                setpriv --reuid 10001 --regid 10001 --clear-groups --bounding-set=-all \
                    --inh-caps=-all --ambient-caps=-all -- sh -c 'test "$(cat example.com.key)" = private-key'
            ) || fail '普通核心或 ops 用户无法访问原私密材料'
        done
    done
) || fail '透明核心实际文件权限合同失败'
# 首次预检创建的锁须经过二次权限准备；坏证据必须保留，由真实归属校验拒绝。
(
    candidate="${TEST_ROOT}/tun-ownership-permissions"
    cp -a -- "${TEST_ROOT}/acme-candidate" "${candidate}" || exit 1
    ownership="${candidate}/data/net/transparent"
    mkdir -p -- "${ownership}" || exit 1
    tunOwnershipValidate() {
        python3 -B - "${PROJECT_ROOT}/docker/images/net/tun-resources.py" "${ownership}" <<'PY'
import importlib.util
import os
import sys

spec = importlib.util.spec_from_file_location("tun_resources", sys.argv[1])
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
runtime.ROOT = sys.argv[2]
runtime.STATE_PATH = os.path.join(runtime.ROOT, "tun.state")
for _ in range(2):
    runtime.lock()
    runtime.state_metadata()
    os.close(runtime.LOCK)
    runtime.LOCK = None
PY
    }
    tunOwnershipValidate || fail '首次 TUN 锁创建失败'
    printf 'kept-ownership-state\n' >"${ownership}/tun.state"
    chmod 0600 "${ownership}/tun.state" || exit 1
    lockIdentity=$(stat -c '%d:%i:%a:%u:%g:%h' -- "${ownership}/.tun.lock")
    stateDigest=$(sha256sum "${ownership}/tun.state")
    for preparation in candidate runtime; do
        case "${preparation}" in
        candidate) dockerPrepareCandidatePermissions "${candidate}" || exit 1 ;;
        runtime) PADM_DOCKER_INSTALL_DIR=${candidate} dockerEnsureRuntimeDataPermissions || exit 1 ;;
        esac
        tunOwnershipValidate || fail "${preparation} 权限准备破坏 TUN 锁或归属登记"
        [[ "$(stat -c '%d:%i:%a:%u:%g:%h' -- "${ownership}/.tun.lock")" == "${lockIdentity}" &&
            "$(sha256sum "${ownership}/tun.state")" == "${stateDigest}" ]] ||
            fail '权限准备替换或改写 TUN 归属证据'
    done
    for entry in "${ownership}/.tun.lock" "${ownership}/tun.state" "${ownership}"; do
        safeMode=0600
        [[ "${entry}" != "${ownership}" ]] || safeMode=0750
        for corruption in mode owner; do
            case "${corruption}" in
            mode) chmod 0770 "${entry}" || exit 1 ;;
            owner) chown 12345:12345 "${entry}" || exit 1 ;;
            esac
            unsafeIdentity=$(stat -c '%d:%i:%a:%u:%g:%h' -- "${entry}")
            dockerPrepareCandidatePermissions "${candidate}" || exit 1
            PADM_DOCKER_INSTALL_DIR=${candidate} dockerEnsureRuntimeDataPermissions || exit 1
            [[ "$(stat -c '%d:%i:%a:%u:%g:%h' -- "${entry}")" == "${unsafeIdentity}" ]] ||
                fail '通用权限准备掩盖被篡改的 TUN 归属证据'
            ! tunOwnershipValidate >"${TEST_ROOT}/tun-ownership-invalid.log" 2>&1 ||
                fail '真实 TUN validator 接受被篡改的归属证据'
            chmod "${safeMode}" "${entry}" && chown 0:0 "${entry}" || exit 1
        done
    done
    mv -- "${ownership}/tun.state" "${candidate}/saved-tun.state" || exit 1
    for linkType in symlink hardlink; do
        case "${linkType}" in
        symlink)
            ln -s "${candidate}/saved-tun.state" "${ownership}/tun.state" || exit 1
            ! dockerPrepareCandidatePermissions "${candidate}" || fail 'TUN 候选接受符号链接'
            ;;
        hardlink)
            ln "${candidate}/saved-tun.state" "${ownership}/tun.state" || exit 1
            dockerPrepareCandidatePermissions "${candidate}" || exit 1
            ;;
        esac
        PADM_DOCKER_INSTALL_DIR=${candidate} dockerEnsureRuntimeDataPermissions || exit 1
        ! tunOwnershipValidate >"${TEST_ROOT}/tun-ownership-invalid.log" 2>&1 ||
            fail "真实 TUN validator 接受 ${linkType}"
        assertMetadata "${candidate}/saved-tun.state" '600 0 0'
        rm -- "${ownership}/tun.state" || exit 1
    done
    printf 'outside-owner\n' >"${TEST_ROOT}/tun-owner-outside"
    chmod 0600 "${TEST_ROOT}/tun-owner-outside" &&
        chown 12345:12345 "${TEST_ROOT}/tun-owner-outside" || exit 1
    ln -s "${TEST_ROOT}/tun-owner-outside" "${candidate}/data/net/outside-link" || exit 1
    PADM_DOCKER_INSTALL_DIR=${candidate} dockerEnsureRuntimeDataPermissions || exit 1
    assertMetadata "${TEST_ROOT}/tun-owner-outside" '600 12345 12345'
) || fail 'TUN 归属证据权限合同失败'
# 复现实机留下的空 collector 目录，SSH 状态不能影响普通部署的恢复。
(
    sshRoot="${TEST_ROOT}/ssh-collector-runtime"
    cp -a -- "${PADM_DOCKER_INSTALL_DIR}" "${sshRoot}"
    export PADM_DOCKER_INSTALL_DIR="${sshRoot}"
    jq '.host_integrations = [{type:"fail2ban-ssh"}]' "${sshRoot}/config/spec.json" \
        >"${TEST_ROOT}/ssh-spec.json"
    mv -- "${TEST_ROOT}/ssh-spec.json" "${sshRoot}/config/spec.json"
    mkdir -p "${sshRoot}/data/net/ssh-collector"
    chmod 0755 "${sshRoot}/data/net/ssh-collector"
    dockerEnsureRuntimeDataPermissions || fail 'SSH collector 运行权限准备失败'
    python3 -B - "${PROJECT_ROOT}" "${sshRoot}/data/net/ssh-collector" <<'PY' || exit 1
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("runtime", sys.argv[1] + "/docker/lib/ssh-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
directory = runtime.Directory(sys.argv[2])
directory.close()
PY
    assertMetadata "${sshRoot}/data/net/ssh-collector" '700 0 0'
    dockerEnsureRuntimeDataPermissions || fail '重复准备 SSH collector 运行权限失败'
    assertMetadata "${sshRoot}/data/net/ssh-collector" '700 0 0'
) || fail 'SSH collector 运行权限准备失败'
# 后段路径和批量工具失败均须拒绝，私密文件不得因此放宽权限。
for permissionFailure in late-link mkdir chmod find; do
    (
        runtimeRoot=${PADM_DOCKER_INSTALL_DIR}
        case "${permissionFailure}" in
        late-link)
            mv -- "${runtimeRoot}/logs/acme" "${runtimeRoot}/logs/acme.saved"
            ln -s acme.saved "${runtimeRoot}/logs/acme"
            trap 'rm -- "${runtimeRoot}/logs/acme"; mv -- "${runtimeRoot}/logs/acme.saved" "${runtimeRoot}/logs/acme"' EXIT
            ;;
        mkdir)
            rmdir -- "${runtimeRoot}/logs/acme"
            trap '[[ -d "${runtimeRoot}/logs/acme" ]] || command mkdir -- "${runtimeRoot}/logs/acme"; command chmod 0750 "${runtimeRoot}/logs/acme"' EXIT
            mkdir() { command mkdir "$@" || return $?; return 17; }
            ;;
        chmod)
            chmod() {
                command chmod "$@" || return $?
                [[ "$*" != *"${runtimeRoot}/logs/acme"* ]] || return 17
            }
            ;;
        find)
            find() {
                command find "$@" || return $?
                [[ "$*" != *"${runtimeRoot}/config ${runtimeRoot}/data/subscription"* ]] || return 17
            }
            ;;
        esac
        if dockerEnsureRuntimeDataPermissions >"${TEST_ROOT}/permissions-failure.log" 2>&1; then
            fail "权限批处理故障未拒绝: ${permissionFailure}"
        fi
        assertMetadata "${runtimeRoot}/config/spec.json" '600 0 0'
    ) || fail "权限批处理合同失败: ${permissionFailure}"
done
dockerEnsureRuntimeDataPermissions
# 两个范围的运行数据库不属于配置恢复点，恢复须保留各自最新内容。
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/data/net/"{fail2ban,control-fail2ban}
wsDatabase="${PADM_DOCKER_INSTALL_DIR}/data/net/fail2ban/fail2ban.sqlite3"
controlDatabase="${PADM_DOCKER_INSTALL_DIR}/data/net/control-fail2ban/control-fail2ban.sqlite3"
printf 'ws-database-before-backup\n' >"${wsDatabase}"
printf 'control-database-before-backup\n' >"${controlDatabase}"
dockerBackupConfiguration configure
backup=${DOCKER_CONFIG_BACKUP}
[[ -z "$(find "${backup}" ! -uid 0 -o ! -gid 0)" ]] || fail 'backup retained runtime file owners'
[[ ! -e "${backup}/data/net" ]] || fail 'configuration backup copied runtime Fail2ban databases'
dockerValidateConfigurationBackup "${backup}" || fail 'root-owned runtime backup did not validate'
printf 'ws-database-after-backup\n' >>"${wsDatabase}"
printf 'control-database-after-backup\n' >>"${controlDatabase}"
databaseDigest=$(sha256sum "${wsDatabase}" "${controlDatabase}")
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
jq 'del(.host_integrations)' "${backup}/deployment.json" \
    >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
DOCKER_CONFIG_SWITCHED=1
! dockerRestoreConfiguration >"${TEST_ROOT}/restore-corrupt.log" 2>&1 ||
    fail 'runtime restore overwrote a corrupt current spec with unknown integration metadata'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ||
    fail 'corrupt-spec refusal changed the current spec'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key" ||
    fail 'corrupt-spec refusal changed the current TLS key'
cp -p -- "${backup}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
OWNERSHIP_QUERY_FAIL=1
! dockerRestoreConfiguration >"${TEST_ROOT}/restore-query-fail.log" 2>&1 ||
    fail 'runtime restore ignored an ownership query failure'
[[ "${DOCKER_CONFIG_SWITCHED}" == 1 ]] || fail 'ownership query refusal discarded the restore transaction'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key" ||
    fail 'ownership query refusal changed the current TLS key'
[[ ! -e "${TEST_ROOT}/compose.log" ]] || fail 'refused restore stopped or started services'
OWNERSHIP_QUERY_FAIL=0
dockerRestoreConfiguration || fail 'runtime backup restore failed'
[[ "$(sha256sum "${wsDatabase}" "${controlDatabase}")" == "${databaseDigest}" ]] ||
    fail 'configuration restore overwrote or crossed Fail2ban database scopes'
assertMetadata "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '600 0 0'
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" || fail 'restored spec was inconsistent'
(
    cd "${PADM_DOCKER_INSTALL_DIR}/config"
    ! setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c 'cat spec.json' >/dev/null 2>&1
) || fail 'container UID could read the root-only spec'
assertRuntimeSecrets

# 主控来源日志只允许 root 管理目录、运行 UID 追加普通单链接文件。
controlRoot="${TEST_ROOT}/control-log-runtime"
mkdir -p -- "${controlRoot}/config"
chmod 0750 "${controlRoot}" "${controlRoot}/config"
printf '{"control":{"role":"main"}}\n' >"${controlRoot}/config/spec.json"
dockerControlAccessLogEnsure "${controlRoot}"
controlLog="${controlRoot}/logs/control/auth.log"
controlLock="${controlRoot}/logs/control/auth.lock"
sourceReceipt="${controlRoot}/logs/control/source.receipt"
sourceChallenge="${controlRoot}/data/control-source/challenge.json"
assertMetadata "${controlRoot}/logs/control" '750 0 10001'
assertMetadata "${controlLog}" '640 10001 10001'
assertMetadata "${controlLock}" '640 0 10001'
assertMetadata "${sourceReceipt}" '640 10001 10001'
assertMetadata "${controlRoot}/data/control-source" '750 0 10001'
[[ ! -e "${sourceChallenge}" ]] || fail 'runtime permissions created a challenge'
[[ ! -e "${controlLog}.1" && ! -e "${controlLog}.2" ]] || fail 'runtime permissions created archives'
(
    cd "${controlRoot}/logs/control"
    setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
        'test -w auth.log && test -r auth.lock && test ! -w auth.lock && test ! -w . &&
         printf "kept-control-evidence\n" >>auth.log'
) || fail 'control UID could not append to the protected log'
controlDigest=$(sha256sum "${controlLog}")
printf 'kept-source-receipt\n' >"${sourceReceipt}"
receiptDigest=$(sha256sum "${sourceReceipt}")
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLog}")" == "${controlDigest}" ]] || fail 'existing control log was truncated'
[[ "$(sha256sum "${sourceReceipt}")" == "${receiptDigest}" ]] || fail 'existing source receipt was truncated'
# 锁 inode 与历史归档必须保留；坏条目不能借权限准备得到修复或补建日志。
printf 'kept-lock-content\n' >"${controlLock}"
lockIdentity=$(stat -c '%d:%i' -- "${controlLock}")
for archive in "${controlLog}.1" "${controlLog}.2"; do
    printf 'kept-control-archive\n' >"${archive}"
    chmod 0640 "${archive}"
    chown 10001:10001 "${archive}"
done
rotationDigest=$(sha256sum "${controlLock}" "${controlLog}.1" "${controlLog}.2")
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLock}" "${controlLog}.1" "${controlLog}.2")" == "${rotationDigest}" &&
    "$(stat -c '%d:%i' -- "${controlLock}")" == "${lockIdentity}" ]] ||
    fail 'existing control lock or archives were replaced'
for entry in "${controlLock}" "${controlLog}.1" "${controlLog}.2"; do
    safeOwner=10001
    unsafeOwner=0
    if [[ "${entry}" == "${controlLock}" ]]; then
        safeOwner=0
        unsafeOwner=10001
    fi
    chmod 0660 "${entry}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe rotation entry mode was repaired'
    assertMetadata "${entry}" "660 ${safeOwner} 10001"
    chmod 0640 "${entry}"
    chown "${unsafeOwner}:10001" "${entry}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe rotation entry owner was repaired'
    assertMetadata "${entry}" "640 ${unsafeOwner} 10001"
    chown "${safeOwner}:10001" "${entry}"
    mv -- "${entry}" "${controlRoot}/saved-rotation-entry"
    ln -s "${controlRoot}/saved-rotation-entry" "${entry}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'rotation entry symlink was accepted'
    rm -- "${entry}"
    ln "${controlRoot}/saved-rotation-entry" "${entry}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'rotation entry hardlink was accepted'
    rm -- "${entry}"
    mv -- "${controlRoot}/saved-rotation-entry" "${entry}"
done
mv -- "${controlLog}" "${controlRoot}/saved-auth.log"
chmod 0660 "${controlLog}.2"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe archive was accepted with a missing active log'
[[ ! -e "${controlLog}" ]] || fail 'unsafe archive refusal created the missing active log'
chmod 0640 "${controlLog}.2"
mv -- "${controlRoot}/saved-auth.log" "${controlLog}"
printf 'unknown-archive\n' >"${controlLog}.3"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unknown control archive name was accepted'
grep -qxF unknown-archive "${controlLog}.3" || fail 'unknown control archive was changed'
rm -- "${controlLog}.3"
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLock}" "${controlLog}.1" "${controlLog}.2")" == "${rotationDigest}" &&
    "$(stat -c '%d:%i' -- "${controlLock}")" == "${lockIdentity}" ]] ||
    fail 'control lock or archives changed after rejected inputs'
mv -- "${controlLog}" "${controlRoot}/saved-auth.log"
printf 'untouched\n' >"${controlRoot}/outside-log"
chmod 0600 "${controlRoot}/outside-log"
chown 12345:12345 "${controlRoot}/outside-log"
ln -s "${controlRoot}/outside-log" "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log symlink was accepted'
rm -- "${controlLog}"
ln "${controlRoot}/outside-log" "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log hardlink was accepted'
assertMetadata "${controlRoot}/outside-log" '600 12345 12345'
grep -qxF untouched "${controlRoot}/outside-log" || fail 'unsafe control log changed its external target'
rm -- "${controlLog}"
mv -- "${controlRoot}/saved-auth.log" "${controlLog}"
chmod 0660 "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log permissions were repaired'
assertMetadata "${controlLog}" '660 10001 10001'
chmod 0640 "${controlLog}"
chown 0:10001 "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log owner was repaired'
assertMetadata "${controlLog}" '640 0 10001'
chown 10001:10001 "${controlLog}"
for unsafeParent in "${controlRoot}" "${controlRoot}/logs" "${controlRoot}/logs/control"; do
    safeMode=$(stat -c %a -- "${unsafeParent}")
    chmod 0770 "${unsafeParent}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log parent was accepted'
    [[ "$(stat -c %a -- "${unsafeParent}")" == 770 ]] || fail 'unsafe log parent was silently repaired'
    chmod "${safeMode}" "${unsafeParent}"
done
mv -- "${controlRoot}/logs/control" "${controlRoot}/saved-control"
ln -s "${controlRoot}/saved-control" "${controlRoot}/logs/control"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log directory symlink was accepted'
rm -- "${controlRoot}/logs/control"
mv -- "${controlRoot}/saved-control" "${controlRoot}/logs/control"
mkdir -- "${controlRoot}/logs/control/unexpected"
chmod 0777 "${controlRoot}/logs/control/unexpected"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unexpected control log tree was accepted'
[[ "$(stat -c %a -- "${controlRoot}/logs/control/unexpected")" == 777 ]] ||
    fail 'unexpected control log tree was recursively repaired'
rmdir -- "${controlRoot}/logs/control/unexpected"
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLog}")" == "${controlDigest}" ]] || fail 'control log changed after rejected unsafe inputs'
mv -- "${sourceReceipt}" "${controlRoot}/saved-source.receipt"
ln -s "${controlRoot}/outside-log" "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source receipt symlink was accepted'
rm -- "${sourceReceipt}"
ln "${controlRoot}/saved-source.receipt" "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source receipt hardlink was accepted'
rm -- "${sourceReceipt}"
mv -- "${controlRoot}/saved-source.receipt" "${sourceReceipt}"
chmod 0660 "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source receipt permissions were repaired'
assertMetadata "${sourceReceipt}" '660 10001 10001'
chmod 0640 "${sourceReceipt}"
printf '{"fixture":"registered-source"}\n' >"${sourceChallenge}"
chmod 0640 "${sourceChallenge}"
chown 0:10001 "${sourceChallenge}"
challengeDigest=$(sha256sum "${sourceChallenge}")
dockerControlAccessLogEnsure "${controlRoot}"
(
    cd "${controlRoot}/data/control-source"
    setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
        'test -r challenge.json && test ! -w challenge.json && test ! -w .'
) || fail 'control UID could modify the root-owned challenge registration'
ln "${sourceChallenge}" "${controlRoot}/challenge-link"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source challenge hardlink was accepted'
rm -- "${controlRoot}/challenge-link"
chmod 0660 "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source challenge permissions were repaired'
assertMetadata "${sourceChallenge}" '660 0 10001'
chmod 0640 "${sourceChallenge}"
chown 10001:10001 "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'API-owned source challenge was accepted'
assertMetadata "${sourceChallenge}" '640 10001 10001'
chown 0:10001 "${sourceChallenge}"
[[ "$(sha256sum "${sourceChallenge}")" == "${challengeDigest}" ]] || fail 'challenge content was replaced'
mv -- "${sourceChallenge}" "${controlRoot}/saved-challenge.json"
ln -s "${controlRoot}/saved-challenge.json" "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source challenge symlink was accepted'
rm -- "${sourceChallenge}"
mv -- "${controlRoot}/saved-challenge.json" "${sourceChallenge}"
printf '%4097s' '' >"${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'oversize source challenge was accepted'
[[ "$(stat -c %s -- "${sourceChallenge}")" == 4097 ]] || fail 'oversize source challenge was truncated'
rm -- "${sourceChallenge}"
chmod 0770 "${controlRoot}/data"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source directory parent was accepted'
chmod 0750 "${controlRoot}/data"
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${sourceReceipt}")" == "${receiptDigest}" ]] || fail 'source receipt changed after rejected unsafe inputs'
printf '{"control_sync":{}}\n' >"${controlRoot}/config/spec.json"
rm -- "${controlLog}" "${sourceReceipt}" "${controlLock}" "${controlLog}.1" "${controlLog}.2"
rmdir -- "${controlRoot}/logs/control"
rmdir -- "${controlRoot}/data/control-source"
dockerControlAccessLogEnsure "${controlRoot}"
[[ ! -e "${controlRoot}/logs/control" && ! -e "${controlRoot}/data/control-source" ]] ||
    fail 'controlled node created unused source paths'

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/unconfigured"
dockerInitializeStateRoot
seedRuntimeSecrets
dockerBackupConfiguration configure
backup=${DOCKER_CONFIG_BACKUP}
[[ -z "$(find "${backup}" ! -uid 0 -o ! -gid 0)" ]] || fail 'unconfigured backup retained runtime owners'
! dockerValidateConfigurationBackup "${backup}" || fail 'unconfigured snapshot was accepted as a deployment backup'
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration || fail 'unconfigured backup restore failed'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'unconfigured restore created a deployment'
assertRuntimeSecrets
grep -qxF removed "${TEST_ROOT}/schedule.log" || fail 'unconfigured restore did not remove the runtime scheduler'
# 权限准备必须在 chmod/chown 前拒绝指向候选之外的链接。
unsafeCandidate="${TEST_ROOT}/unsafe-candidate"
mkdir -p "${unsafeCandidate}/config/xray"
printf 'external\n' >"${TEST_ROOT}/external"
chmod 0600 "${TEST_ROOT}/external"
chown 12345:12345 "${TEST_ROOT}/external"
ln -s "${TEST_ROOT}/external" "${unsafeCandidate}/config/xray/unsafe"
! dockerPrepareCandidatePermissions "${unsafeCandidate}" || fail 'candidate symlink was accepted'
assertMetadata "${TEST_ROOT}/external" '600 12345 12345'
unsafeLogCandidate="${TEST_ROOT}/unsafe-log-candidate"
mkdir -p "${unsafeLogCandidate}/logs/control"
printf 'not-candidate-evidence\n' >"${unsafeLogCandidate}/logs/control/auth.log"
chmod 0600 "${unsafeLogCandidate}/logs/control/auth.log"
chown 12345:12345 "${unsafeLogCandidate}/logs/control/auth.log"
! dockerPrepareCandidatePermissions "${unsafeLogCandidate}" || fail 'candidate carried runtime control evidence'
assertMetadata "${unsafeLogCandidate}/logs/control/auth.log" '600 12345 12345'
unsafeSourceCandidate="${TEST_ROOT}/unsafe-source-candidate"
mkdir -p "${unsafeSourceCandidate}/data/control-source"
printf 'not-candidate-registration\n' >"${unsafeSourceCandidate}/data/control-source/challenge.json"
chmod 0600 "${unsafeSourceCandidate}/data/control-source/challenge.json"
chown 12345:12345 "${unsafeSourceCandidate}/data/control-source/challenge.json"
! dockerPrepareCandidatePermissions "${unsafeSourceCandidate}" || fail 'candidate carried a runtime challenge'
assertMetadata "${unsafeSourceCandidate}/data/control-source/challenge.json" '600 12345 12345'
printf 'docker-permissions-regression-ok\n'
