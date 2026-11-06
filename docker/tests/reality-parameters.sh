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
read -r REGEN_PRIVATE REGEN_PUBLIC REGEN_MLDSA_SEED REGEN_MLDSA_VERIFY < <(python3 -c '
import base64
import subprocess

key = bytes.fromhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
public = subprocess.run(["openssl","pkey","-inform","DER","-pubout","-outform","DER"],
    input=bytes.fromhex("302e020100300506032b656e04220420")+key,
    check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout
assert public[:12] == bytes.fromhex("302a300506032b656e032100") and len(public) == 44
seed = bytes(range(32))
mldsa = subprocess.run(["openssl","pkey","-inform","DER","-pubout","-outform","DER"],
    input=bytes.fromhex("3034020100300b060960864801650304031204228020")+seed,
    check=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL).stdout
prefix = bytes.fromhex("308207b2300b0609608648016503040312038207a100")
assert mldsa.startswith(prefix) and len(mldsa) == len(prefix)+1952
print(*(base64.urlsafe_b64encode(value).decode().rstrip("=")
        for value in (key,public[12:],seed,mldsa[len(prefix):])))
')
export FAKE_REGEN_PRIVATE="${REGEN_PRIVATE}" FAKE_REGEN_PUBLIC="${REGEN_PUBLIC}"
export FAKE_REGEN_MLDSA_SEED="${REGEN_MLDSA_SEED}" FAKE_REGEN_MLDSA_VERIFY="${REGEN_MLDSA_VERIFY}"
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
            "${argument}" != *"${FAKE_REGEN_OLD_PRIVATE:?}"* &&
            "${argument}" != *"${FAKE_REGEN_MLDSA_SEED:?}"* ]] || exit 1
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
    if [[ " $* " == *' mldsa65 '* ]]; then
        [[ " $* " == *" ${FAKE_REGEN_XRAY_IMAGE:?} mldsa65 "* &&
            " $* " == *' --network none '* && " $* " != *' -i '* ]] || exit 1
        seed=${FAKE_REGEN_MLDSA_SEED:?} verify=${FAKE_REGEN_MLDSA_VERIFY:?}
        case "${FAKE_REGEN_MLDSA_MODE:-supported}" in
        generation-fail|reuse) exit 1 ;;
        bad-seed) seed=invalid ;;
        bad-verify) verify=invalid ;;
        short-verify) verify=${verify:1} ;;
        long-verify) verify="${verify}A" ;;
        bad-verify-character) verify="!${verify:1}" ;;
        noncanonical-verify) verify="${verify:0:2602}B" ;;
        mismatch) verify="B${verify:1}" ;;
        esac
        printf 'Seed: %s\nVerify: %s\n' "${seed}" "${verify}"
        exit 0
    fi
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
        if [[ "${previous}" == -c && "${argument}" == *'socket.getaddrinfo(sys.argv[1], None'* ]]; then
            [[ "${FAKE_REGEN_RESOLVE_FAIL:-0}" != 1 ]] || exit 1
            printf '192.0.2.1\n'
            exit 0
        fi
        if [[ "${previous}" == -c && ( "${argument}" == *302e020100300506032b656e04220420* ||
            "${argument}" == *3034020100300b060960864801650304031204228020* ) ]]; then
            exec python3 -c "${argument}"
        fi
        previous=${argument}
    done
    if [[ " $* " == *' tls ping '* ]]; then
        case "${FAKE_REGEN_MLDSA_MODE:-supported}" in
        probe-fail) exit 1 ;;
        timeout) exit 124 ;;
        malformed-ping) printf 'invalid TLS output\n'; exit 0 ;;
        no-sni-pqc)
            printf 'Pinging without SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nCertificate chain total length: 4096\n' ;;
        esac
        printf 'Pinging with SNI\n'
        if [[ " $* " == *' cloudflare.com:'* ]]; then
            printf 'Handshake failure: certificate does not match SNI\n'
        else
            printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'
            case "${FAKE_REGEN_MLDSA_MODE:-supported}" in
            no-pqc|no-sni-pqc) ;;
            *) printf 'TLS Post-Quantum key exchange: X25519MLKEM768\n' ;;
            esac
            if [[ "${FAKE_REGEN_MLDSA_MODE:-supported}" == short-chain ]]; then
                printf 'Certificate chain total length: 3500\n'
            else printf "Certificate chain's total length:\t4096 (certs count: 3)\n"; fi
        fi
    else printf '192.0.2.1\tAS64500\tExampleNet\n'; fi ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/"{cosign,jq,docker}

parameterAssertCleanup() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Reality 管理遗留部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' \) -print -quit)" ]] || fail 'Reality 管理遗留秘密草稿'
    for private in "${PRIVATE_KEY}" "${REGEN_PRIVATE}" "${REGEN_MLDSA_SEED}"; do
        ! grep -Fq "${private}" "${EVENTS}" "${STDOUT}" "${STDERR}" || fail 'Reality 私钥泄漏到参数或预览'
    done
    for value in "${REGEN_PUBLIC}" "${FAKE_REGEN_SHORT}" "${REGEN_MLDSA_VERIFY}"; do
        ! grep -Fq "${value}" "${STDOUT}" "${STDERR}" || fail 'Reality 预览输出了新客户端参数'
    done
}

runParameterEdit() {
    local expected=$1 name=$2 unchanged=$3 actual=0 before
    shift 3
    if [[ "${unchanged}" == unchanged ]]; then before=$(snapshot); fi
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
        del(.reality.private_key,.reality.public_key,.reality.short_id,
          .reality.mldsa65_seed,.reality.mldsa65_verify) else . end);
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
              .streamSettings.realitySettings.mldsa65Seed,.streamSettings.realitySettings.mldsa65Verify,
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
    if [[ "${listener}" != entry-vision-sing && "${listener}" != entry-grpc-sing ]]; then
        expected=${expected/"&type="/"&pqv=${REGEN_MLDSA_VERIFY}&type="}
        jq -e --arg listener "${listener}" --rawfile seed <(printf '%s' "${REGEN_MLDSA_SEED}") \
            --rawfile verify <(printf '%s' "${REGEN_MLDSA_VERIFY}") '
          any(.inbounds[]; .tag == $listener and
            .streamSettings.realitySettings.mldsa65Seed == $seed and
            .streamSettings.realitySettings.mldsa65Verify == $verify)
        ' "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" >/dev/null ||
            fail "${listener}: 核心未启用完整 ML-DSA 参数"
    fi
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

# 连接目标域名解析出的地址，并验证配置的独立 SNI。
jq '
  (.core.protocols[] | select(.listener_id == "entry-grpc-xray") | .reality) |=
    (.target_host = "target.example.net" | .target_port = 8443 | .server_name = "sni.example.net")
' "${REGEN_SPEC}" >"${TEST_ROOT}/independent-sni.json"
chmod 0600 "${TEST_ROOT}/independent-sni.json"
newState independent-sni "${TEST_ROOT}/independent-sni.json"
runParameterEdit 0 independent-sni unchanged --regenerate-reality entry-grpc-xray --preview
grep -qF ' target.example.net' "${EVENTS}" &&
    grep -qF ' tls ping -ip 192.0.2.1 sni.example.net:8443' "${EVENTS}" ||
    fail 'Reality 重生成未分开使用实际目标地址与配置 SNI'
FAKE_REGEN_RESOLVE_FAIL=1 runParameterEdit 15 resolve-fail unchanged \
    --regenerate-reality entry-grpc-xray --preview
! grep -qF ' tls ping ' "${EVENTS}" || fail 'Reality 目标解析失败仍发起 TLS 探测'

# 已有材料仍须配对校验；复用和降级只影响选中入口。
MLDSA_SPEC="${TEST_ROOT}/mldsa-valid.json"
jq --rawfile seed <(printf '%s' "${REGEN_MLDSA_SEED}") \
    --rawfile verify <(printf '%s' "${REGEN_MLDSA_VERIFY}") '
  .core.protocols |= map(if .reality != null and .core == "xray" then
    .reality += {mldsa65_seed:$seed,mldsa65_verify:$verify} else . end)
' "${REGEN_SPEC}" >"${MLDSA_SPEC}"
chmod 0600 "${MLDSA_SPEC}"
dockerConfigureSpecValidate "${MLDSA_SPEC}" || fail 'ML-DSA 成对规格被拒绝'
dockerRealityMldsa65Validate "${MLDSA_SPEC}" "${OPS_IMAGE}" || fail 'ML-DSA 派生校验拒绝有效材料'
newState mldsa-reuse "${MLDSA_SPEC}"
FAKE_REGEN_MLDSA_MODE=reuse runParameterEdit 0 mldsa-reuse changed \
    --regenerate-reality entry-xhttp --confirm PADM-DOCKER-EDIT
! grep -Eq '^run .* mldsa65$' "${EVENTS}" || fail '已有 ML-DSA 参数仍被重新生成'
jq -e --slurpfile before "${MLDSA_SPEC}" '
  [.core.protocols[].reality | {mldsa65_seed,mldsa65_verify}] ==
    [$before[0].core.protocols[].reality | {mldsa65_seed,mldsa65_verify}]
' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail '复用改变已有 ML-DSA 材料'
for mode in no-pqc short-chain no-sni-pqc; do
    newState "mldsa-${mode}" "${MLDSA_SPEC}"
    FAKE_REGEN_MLDSA_MODE=${mode} runParameterEdit 0 "mldsa-${mode}" changed \
        --regenerate-reality entry-xhttp --confirm PADM-DOCKER-EDIT
    jq -e --slurpfile before "${MLDSA_SPEC}" '
      def stable: .core.protocols |= map(if .listener_id == "entry-xhttp" then
        del(.reality.private_key,.reality.public_key,.reality.short_id,
          .reality.mldsa65_seed,.reality.mldsa65_verify) else . end);
      (. | stable) == ($before[0] | stable) and
      all(.core.protocols[] | select(.listener_id == "entry-xhttp");
        (.reality | has("mldsa65_seed") or has("mldsa65_verify") | not))
    ' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail "${mode}: 降级误改未选入口"
    ! grep -Eq '^run .* mldsa65$' "${EVENTS}" || fail "${mode}: 不适合目标仍生成 ML-DSA"
done
newState mldsa-failures "${REGEN_SPEC}"
for mode in probe-fail timeout malformed-ping generation-fail bad-seed bad-verify \
    short-verify long-verify bad-verify-character noncanonical-verify mismatch; do
    FAKE_REGEN_MLDSA_MODE=${mode} runParameterEdit 15 "mldsa-${mode}" unchanged \
        --regenerate-reality entry-xhttp --preview
done
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
FAKE_REGEN_HEALTH_FAIL=1 runParameterEdit 14 mldsa-health-fail-restored changed \
    --regenerate-reality entry-xhttp --confirm PADM-DOCKER-EDIT
[[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
    fail 'ML-DSA 健康失败未恢复完整旧部署'

# 同身份 XHTTP 下行随主链接传播 pqv，客户端的独立下行身份不借用本入口材料。
jq '(.core.protocols[] | select(.id == 2) | .xhttp.download_port) = 35444 |
  .port_aliases = [{listener_id:"entry-xhttp",public_port:35444}]
' "${MLDSA_SPEC}" >"${TEST_ROOT}/mldsa-download.json"
dockerGenerateSubscription "${TEST_ROOT}/mldsa-download.json" "${TEST_ROOT}/mldsa-links.txt" local
python3 - "${TEST_ROOT}/mldsa-links.txt" <<'PY'
import json
import os
import pathlib
import sys
import urllib.parse

links = [urllib.parse.urlsplit(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
query = urllib.parse.parse_qs(next(link for link in links if link.port == 25443).query)
verify = os.environ["FAKE_REGEN_MLDSA_VERIFY"]
assert query["pqv"] == [verify]
download = json.loads(query["extra"][0])["downloadSettings"]
assert download["realitySettings"]["mldsa65Verify"] == verify
PY

python3 - "${PROJECT_ROOT}" "${MLDSA_SPEC}" "${TEST_ROOT}" <<'PY'
import copy
import json
from pathlib import Path
import sys
from jsonschema import Draft202012Validator, FormatChecker

project, source, root = map(Path, sys.argv[1:])
base = json.loads(source.read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
validator = Draft202012Validator(schema, format_checker=FormatChecker())
cases = [("valid", base, True)]
for name, target, field, value in [
    ("missing-seed", 0, "mldsa65_seed", None),
    ("missing-verify", 0, "mldsa65_verify", None),
    ("bad-seed", 0, "mldsa65_seed", "invalid"),
    ("bad-verify", 0, "mldsa65_verify", "invalid"),
    ("null-verify", 0, "mldsa65_verify", False),
    ("noncanonical-seed", 0, "mldsa65_seed", "A"*42+"B"),
    ("noncanonical-verify", 0, "mldsa65_verify", "A"*2602+"B"),
    ("unknown-field", 0, "extra", True),
]:
    item = copy.deepcopy(base)
    reality = item["core"]["protocols"][target]["reality"]
    if value is None:
        del reality[field]
    else:
        reality[field] = None if value is False else value
    cases.append((name, item, False))
item = copy.deepcopy(base)
item["core"]["protocols"][3]["reality"].update(
    {key: value for key, value in base["core"]["protocols"][0]["reality"].items()
     if key.startswith("mldsa65_")})
cases.append(("sing-box", item, False))
item = copy.deepcopy(base)
item["core"]["protocols"][0]["reality"]["mldsa65_verify"] = (
    "B" + item["core"]["protocols"][0]["reality"]["mldsa65_verify"][1:])
cases.append(("mismatch", item, True))
with (root / "mldsa-schema-cases").open("w") as ledger:
    for name, item, valid in cases:
        assert validator.is_valid(item) == valid, name
        target = root / f"mldsa-schema-{name}.json"
        target.write_text(json.dumps(item))
        target.chmod(0o600)
        ledger.write(f"{name}\t{int(valid)}\n")
PY
while IFS=$'\t' read -r name valid; do
    if dockerConfigureSpecValidate "${TEST_ROOT}/mldsa-schema-${name}.json" 2>/dev/null; then
        [[ "${valid}" == 1 ]] || fail "生产校验接受非法 ML-DSA: ${name}"
    else [[ "${valid}" == 0 ]] || fail "生产校验拒绝有效 ML-DSA: ${name}"; fi
done <"${TEST_ROOT}/mldsa-schema-cases"
if dockerRealityMldsa65Validate "${TEST_ROOT}/mldsa-schema-mismatch.json" "${OPS_IMAGE}"; then
    fail 'ML-DSA 派生校验接受格式合法的错配公钥'
fi
newState mldsa-mismatch "${TEST_ROOT}/mldsa-schema-mismatch.json"
runParameterEdit 15 mldsa-reuse-mismatch unchanged --regenerate-reality vless-reality --preview
cp "${PROJECT_ROOT}/docker/contracts/"{configure.schema.json,features.json} \
    "${COMPAT_BUNDLE}/docker/contracts/"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${MLDSA_SPEC}" || fail '当前 bundle 拒绝 ML-DSA'
jq 'del(.["x-padm-reality-mldsa65"])' \
    "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json" >"${TEST_ROOT}/old-mldsa-schema.json"
cp "${TEST_ROOT}/old-mldsa-schema.json" "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${MLDSA_SPEC}" 2>/dev/null; then
    fail '旧 bundle 接受 ML-DSA 字段'
fi
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${REGEN_SPEC}" || fail 'ML-DSA marker 误拒旧规格'
printf 'docker-reality-parameters-regression-ok\n'
