#!/usr/bin/env bash
set -euo pipefail

# 复用可信资产、双核候选、恢复和 URI 基线，只替换宿主及容器边界。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
command -v openssl >/dev/null
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
ASSET_ARGS=(--manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" --control-bundle "${CONFIGURE_CONTROL}")
REGEN_SPEC="${TEST_ROOT}/reality-parameters.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --slurpfile ws "${TEST_ROOT}/v3.json" --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .subscription.enabled = true | .tls = $ws[0].tls |
  .core.protocols += [(.core.protocols[0] | .listener_id = "entry-vision-sing" |
    .core = "sing-box" | .name = "Reality-Vision-sing" | .public_port = 25446)] +
    [$ws[0].core.protocols[] | select(.id == 21)]
' "${REALITY_SPEC}" >"${REGEN_SPEC}"
chmod 0600 "${REGEN_SPEC}"
dockerConfigureSpecValidate "${REGEN_SPEC}" || fail 'Reality 参数管理双核发布夹具无效'
# 固定 RFC 7748 的另一私钥，由真实 OpenSSL 独立派生 fixture 公钥。
read -r REGEN_PRIVATE REGEN_PUBLIC < <(python3 -c '
import base64
import subprocess

key = bytes.fromhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
public = subprocess.run(["openssl","pkey","-inform","DER","-pubout","-outform","DER"],
    input=bytes.fromhex("302e020100300506032b656e04220420")+key,
    check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout
assert public[:12] == bytes.fromhex("302a300506032b656e032100") and len(public) == 44
print(*(base64.urlsafe_b64encode(value).decode().rstrip("=") for value in (key,public[12:])))
')
export FAKE_REGEN_PRIVATE="${REGEN_PRIVATE}" FAKE_REGEN_PUBLIC="${REGEN_PUBLIC}"
export FAKE_REGEN_SHORT=0123456789abcdef
export FAKE_REGEN_OLD_PRIVATE="${PRIVATE_KEY}" FAKE_REGEN_OLD_PUBLIC="${PUBLIC_KEY}"
export FAKE_REGEN_OLD_SHORT=6ba85179e30d4fc2
export FAKE_REGEN_XRAY_IMAGE FAKE_REGEN_OPS_IMAGE
FAKE_REGEN_XRAY_IMAGE=$(jq -r '.images.xray.reference' "${CONFIGURE_MANIFEST}")
FAKE_REGEN_OPS_IMAGE=$(jq -r '.images.ops.reference' "${CONFIGURE_MANIFEST}")
export FAKE_REGEN_REAL_JQ
FAKE_REGEN_REAL_JQ=$(command -v jq)
cp "${MOCK_BIN}/cosign" "${MOCK_BIN}/cosign-fixture"
cat >"${MOCK_BIN}/cosign" <<'EOF'
#!/usr/bin/env bash
printf 'verify-signature\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
[[ "${FAKE_REGEN_SIGN_FAIL:-0}" != 1 ]] || exit 1
exec "$(dirname -- "$0")/cosign-fixture" "$@"
EOF
cat >"${MOCK_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_REGEN_SECURITY_CHECK:-0}" == 1 ]]; then
    rawfile=0 rawfileName=
    for argument in "$@"; do
        [[ "${argument}" != *"${FAKE_REGEN_PRIVATE:?}"* &&
            "${argument}" != *"${FAKE_REGEN_OLD_PRIVATE:?}"* ]] || exit 1
        if [[ "${rawfile}" == 2 ]]; then
            # images.env 只含镜像引用；其它 rawfile 仍按秘密文件检查权限。
            if [[ "${rawfileName}" == imagesEnv ]]; then
                [[ "${argument}" == "${PADM_DOCKER_INSTALL_DIR:?}/images.env" ||
                    "${argument}" == "${PADM_DOCKER_INSTALL_DIR:?}/"*/images.env ]] || exit 1
            else
                [[ "$(stat -c '%a' "${argument}")" == 600 ]] || exit 1
                printf 'rawfile-private-0600\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
            fi
            rawfile=0
        elif [[ "${rawfile}" == 1 ]]; then rawfileName=${argument}; rawfile=2
        elif [[ "${argument}" == --rawfile ]]; then rawfile=1; fi
    done
fi
exec "${FAKE_REGEN_REAL_JQ:?}" "$@"
EOF
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${FAKE_PROTOCOL_EVENTS:?}"
case "${1:-}" in
info)
    case "${3:-}" in
    '{{.OSType}}') printf 'linux\n' ;;
    '{{.Architecture}}') printf '%s\n' "${FAKE_PROTOCOL_ARCH:?}" ;;
    '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
    esac ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps|pull) ;;
compose)
    [[ "${2:-}" != version ]] || { printf 'v2.29.1\n'; exit 0; }
    if [[ " $* " == *' sing-box version '* ]]; then
        printf 'sing-box version 1.14.0\nTags: with_v2ray_api\n'
    fi
    if [[ " $* " == *' up -d '* && "${FAKE_REGEN_HEALTH_FAIL:-0}" == 1 &&
        ! -e "${FAKE_REALITY_FAIL_MARKER:?}" ]]; then
        : >"${FAKE_REALITY_FAIL_MARKER}"
        exit 1
    fi ;;
run)
    if [[ " $* " == *' x25519 ' ]]; then
        [[ " $* " == *" ${FAKE_REGEN_XRAY_IMAGE:?} x25519 "* &&
            " $* " == *' --network none '* ]] || exit 1
        private=${FAKE_REGEN_PRIVATE:?} public=${FAKE_REGEN_PUBLIC:?}
        case "${FAKE_REGEN_MODE:-normal}" in
        generation-fail) exit 1 ;;
        wrong-public) public=${FAKE_REGEN_OLD_PUBLIC:?} ;;
        unchanged|old-private) private=${FAKE_REGEN_OLD_PRIVATE:?}; public=${FAKE_REGEN_OLD_PUBLIC:?} ;;
        malformed) private=invalid ;;
        esac
        printf 'PrivateKey: %s\nPassword (PublicKey): %s\n' "${private}" "${public}"
        exit 0
    fi
    if [[ " $* " == *' --entrypoint openssl '* && " $* " == *' rand -hex 8 '* ]]; then
        [[ " $* " == *" ${FAKE_REGEN_OPS_IMAGE:?} rand -hex 8 "* &&
            " $* " == *' --network none '* ]] || exit 1
        case "${FAKE_REGEN_MODE:-normal}" in
        short-fail) exit 1 ;;
        unchanged|old-short) printf '%s\n' "${FAKE_REGEN_OLD_SHORT:?}" ;;
        bad-short) printf '0123\n' ;;
        *) printf '%s\n' "${FAKE_REGEN_SHORT:?}" ;;
        esac
        exit 0
    fi
    previous=
    for argument in "$@"; do
        if [[ "${previous}" == -c && "${argument}" == *302e020100300506032b656e04220420* ]]; then
            exec python3 -c "${argument}"
        fi
        previous=${argument}
    done
    if [[ " $* " == *' tls ping '* ]]; then
        printf 'Pinging with SNI\n'
        if [[ " $* " == *' cloudflare.com:443 '* ]]; then
            printf 'Handshake failure: certificate does not match SNI\n'
        else printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'; fi
    else printf '192.0.2.1\tAS64500\tExampleNet\n'; fi ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/"{cosign,jq,docker}

parameterAssertCleanup() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Reality 管理遗留部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' \) -print -quit)" ]] || fail 'Reality 管理遗留秘密草稿'
    for private in "${PRIVATE_KEY}" "${REGEN_PRIVATE}"; do
        ! grep -Fq "${private}" "${EVENTS}" "${STDOUT}" "${STDERR}" || fail 'Reality 私钥泄漏到参数或预览'
    done
    for value in "${REGEN_PUBLIC}" "${FAKE_REGEN_SHORT}"; do
        ! grep -Fq "${value}" "${STDOUT}" "${STDERR}" || fail 'Reality 预览输出了新客户端参数'
    done
}

runParameterEdit() {
    local expected=$1 name=$2 unchanged=$3 actual=0 before
    shift 3
    before=$(snapshot)
    : >"${EVENTS}"
    FAKE_REGEN_SECURITY_CHECK=1 bash -u "${CLI}" edit "$@" "${ASSET_ARGS[@]}" \
        </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "${name}: 预期 ${expected}，实际 ${actual}"
    parameterAssertCleanup
    [[ "${unchanged}" != unchanged || "$(snapshot)" == "${before}" ]] || fail "${name}: 改变已安装部署"
}

runParameterPty() {
    local name=$1 answer=$2 before
    before=$(snapshot)
    : >"${EVENTS}"
    FAKE_REGEN_SECURITY_CHECK=1 python3 - "${STDOUT}" "${answer}" bash -u "${CLI}" edit \
        --regenerate-reality entry-grpc-sing "${ASSET_ARGS[@]}" <<'PY'
import errno
import os
import pathlib
import pty
import select
import signal
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[3:], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
os.close(slave)
output = bytearray()
sent = False
deadline = time.monotonic()+60
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.1)[0]:
            try:
                part = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not part:
                break
            output.extend(part)
            if not sent and b"[y/N]: " in output:
                if sys.argv[2] in ("int","term"):
                    os.kill(process.pid, signal.SIGINT if sys.argv[2] == "int" else signal.SIGTERM)
                else:
                    os.write(master, b"\x04" if sys.argv[2] == "eof" else (sys.argv[2]+"\n").encode())
                sent = True
        elif process.poll() is not None:
            break
    assert sent, "confirmation prompt was not reached"
    expected = {"int":130,"term":143}.get(sys.argv[2],0)
    assert process.wait(timeout=10) == expected, output.decode(errors="replace")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    pathlib.Path(sys.argv[1]).write_bytes(output)
PY
    : >"${STDERR}"
    if [[ "${answer}" != int && "${answer}" != term ]]; then
        grep -qF '已取消配置编辑' "${STDOUT}" || fail "${name}: 取消或 EOF 没有停止提交"
    fi
    parameterAssertCleanup
    [[ "$(snapshot)" == "${before}" ]] || fail "${name}: 取消或 EOF 改变部署"
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail "${name}: 取消时启动了候选"
}

newState reality-parameters "${REGEN_SPEC}"
dockerEnsureRuntimeDataPermissions
# 共享账号保持封禁状态，重生成只影响传输认证材料。
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 1' \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
printf '%s\n' "${quota}" | dockerTrafficWriteState
dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}"
for listener in vless-reality entry-vision-sing entry-xhttp entry-grpc-xray entry-grpc-sing; do
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/parameter-before.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" "${TEST_ROOT}/parameter-traffic.json"
    for core in xray sing-box; do
        cp "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" "${TEST_ROOT}/parameter-${core}.json"
    done
    dockerProtocolCommand links >"${TEST_ROOT}/parameter-links.txt"
    dockerProtocolCommand links "${listener}" >"${TEST_ROOT}/parameter-selected.uri"
    before=$(liveSnapshot)
    runParameterEdit 0 "${listener}-preview" unchanged --regenerate-reality "${listener}" --preview
    awk '/^verify-signature$/ {verified=1} /^run .* x25519$/ {if (!verified) exit 1; generated=1}
      END {if (!generated) exit 1}' "${EVENTS}" || fail '未在可信资产验签后生成密钥'
    grep -qF 'rawfile-private-0600' "${EVENTS}" || fail '重生成秘密未经过 0600 文件'
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail '预览提前启动候选'
    runParameterEdit 0 "${listener}-confirm" changed --regenerate-reality "${listener}" --confirm PADM-DOCKER-EDIT
    backup=$(sed -n 's/^Docker 配置已提交，回滚快照: //p' "${STDOUT}")
    [[ "${backup}" == "${PADM_DOCKER_INSTALL_DIR}/backups/configure."* ]] ||
        fail "${listener}: 未生成配置恢复快照"
    jq -en --arg listener "${listener}" --arg private "${REGEN_PRIVATE}" --arg public "${REGEN_PUBLIC}" \
        --arg short "${FAKE_REGEN_SHORT}" --slurpfile before "${TEST_ROOT}/parameter-before.json" \
        --slurpfile after "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      def stable: .core.protocols |= map(if .listener_id == $listener then
        del(.reality.private_key,.reality.public_key,.reality.short_id) else . end);
      ($before[0] | stable) == ($after[0] | stable) and
      any($after[0].core.protocols[]; .listener_id == $listener and
        .reality.private_key == $private and .reality.public_key == $public and .reality.short_id == $short)
    ' >/dev/null || fail "${listener}: 重生成改写其它规格字段"
    cmp -s "${TEST_ROOT}/parameter-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail "${listener}: 重生成改变 UUID 额度或累计流量"
    for core in xray sing-box; do
        jq -en --arg listener "${listener}" \
            --slurpfile before "${TEST_ROOT}/parameter-${core}.json" \
            --slurpfile after "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" '
          def stable: .inbounds |= map(if .tag == $listener then
            del(.streamSettings.realitySettings.privateKey,.streamSettings.realitySettings.shortIds,
              .tls.reality.private_key,.tls.reality.short_id) else . end);
          ($before[0] | stable) == ($after[0] | stable)
        ' >/dev/null || fail "${listener}: 重生成改写其它核心入口"
        jq -e --arg core "${core}" 'all(.inbounds[] | select(if $core == "xray"
          then .protocol == "vless" else .type == "vless" end);
            if $core == "xray" then .settings.clients == [] else .users == [] end)' \
            "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null ||
            fail "${listener}: 重生成解除共享账号额度"
    done
    selected=$(<"${TEST_ROOT}/parameter-selected.uri")
    expected=${selected//${PUBLIC_KEY}/${REGEN_PUBLIC}}
    expected=${expected//6ba85179e30d4fc2/${FAKE_REGEN_SHORT}}
    while IFS= read -r line; do
        [[ "${line}" != "${selected}" ]] || line=${expected}
        printf '%s\n' "${line}"
    done <"${TEST_ROOT}/parameter-links.txt" >"${TEST_ROOT}/parameter-expected-links.txt"
    dockerProtocolCommand links >"${STDOUT}"
    cmp -s "${STDOUT}" "${TEST_ROOT}/parameter-expected-links.txt" ||
        fail "${listener}: 分享 URI 未逐入口更新"
    cmp -s "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" "${TEST_ROOT}/parameter-expected-links.txt" ||
        fail "${listener}: HTTPS 发布内容未逐入口更新"
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        # edit 保存配置快照；公开 rollback 命令仅选择 update 快照。
        dockerAcquireDeploymentLock
        DOCKER_CONFIG_BACKUP=${backup} DOCKER_CONFIG_SWITCHED=1 dockerRestoreConfiguration
    ) >"${STDOUT}" 2>"${STDERR}" || fail "${listener}: 参数回滚失败"
    [[ "$(liveSnapshot)" == "${before}" ]] || fail "${listener}: 参数回滚改变旧核心、证书或流量"
done

for mutation in generation-fail malformed wrong-public short-fail bad-short unchanged old-private old-short; do
    FAKE_REGEN_MODE=${mutation} runParameterEdit 15 "${mutation}" unchanged \
        --regenerate-reality entry-grpc-sing --preview
done
FAKE_REGEN_SIGN_FAIL=1 runParameterEdit 16 signature-fail unchanged \
    --regenerate-reality entry-grpc-sing --preview
! grep -Eq '^run .* x25519$|^run .* rand -hex 8$' "${EVENTS}" ||
    fail '签名失败仍执行 Reality 凭据生成'
for listener in entry-missing vless-ws ../../draft; do
    runParameterEdit 15 "reject-${listener}" unchanged --regenerate-reality "${listener}" --preview
    ! grep -Eq '^run .* x25519$' "${EVENTS}" || fail '未知或非 Reality 入口仍生成凭据'
done
runParameterEdit 2 flag-with-spec unchanged --regenerate-reality vless-reality \
    --spec "${REGEN_SPEC}" --preview
runParameterEdit 2 duplicate-flag unchanged --regenerate-reality vless-reality \
    --regenerate-reality entry-xhttp --preview
runParameterEdit 2 noninteractive-no-mode unchanged --regenerate-reality vless-reality
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/parameter-managed.json"
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runParameterEdit 15 missing-managed-spec unchanged --regenerate-reality vless-reality --preview
cp "${TEST_ROOT}/parameter-managed.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq --arg private "${REGEN_PRIVATE}" --arg public "${REGEN_PUBLIC}" --arg short "${FAKE_REGEN_SHORT}" '
  (.core.protocols[] | select(.listener_id == "entry-xhttp") | .reality) |=
    (.private_key = $private | .public_key = $public | .short_id = $short)
' "${REGEN_SPEC}" >"${TEST_ROOT}/parameter-manual.json"
runParameterEdit 15 manual-key-rejected unchanged --spec "${TEST_ROOT}/parameter-manual.json" --preview
runParameterPty interactive-cancel n
runParameterPty interactive-eof eof
runParameterPty interactive-int int
runParameterPty interactive-term term
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
FAKE_REGEN_HEALTH_FAIL=1 runParameterEdit 14 health-fail-restored changed \
    --regenerate-reality entry-grpc-sing --confirm PADM-DOCKER-EDIT
[[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
    fail 'Reality 健康失败未恢复完整旧部署'
parameterAssertCleanup
printf 'docker-reality-parameters-regression-ok\n'
