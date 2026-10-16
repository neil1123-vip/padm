#!/usr/bin/env bash
set -euo pipefail

# 只复用可信资产与部署夹具，不执行 Reality 的其它专项场景。
# shellcheck source=/dev/null
PADM_DOCKER_TEST_FIXTURE_ONLY=1 source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
ASSET_ARGS=(--manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" --control-bundle "${CONFIGURE_CONTROL}")
ENCRYPTION_SPEC="${TEST_ROOT}/encryption-base.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --slurpfile ws "${TEST_ROOT}/v3.json" --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .subscription.enabled = true | .tls = $ws[0].tls |
  .core.protocols += [$ws[0].core.protocols[] | select(.id == 21)]
' "${REALITY_SPEC}" >"${ENCRYPTION_SPEC}"
chmod 0600 "${ENCRYPTION_SPEC}"
dockerConfigureSpecValidate "${ENCRYPTION_SPEC}" || fail 'Encryption 双核发布夹具无效'
command -v openssl >/dev/null
# 固定零 seed 不是秘密；由真实 OpenSSL 派生配对，避免把形状合法误当作密钥匹配。
read -r FAKE_ENCRYPTION_PRIVATE FAKE_ENCRYPTION_PUBLIC < <(python3 -c '
import base64
import subprocess

seed = bytes(64)
result = subprocess.run(
    ["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
    input=bytes.fromhex("3054020100300b060960864801650304040204428040") + seed,
    capture_output=True, check=True,
).stdout
prefix = bytes.fromhex("308204b2300b0609608648016503040402038204a100")
assert result.startswith(prefix) and len(result) == len(prefix) + 1184
encode = lambda value: base64.urlsafe_b64encode(value).decode().rstrip("=")
print("mlkem768x25519plus.native.600s." + encode(seed),
      "mlkem768x25519plus.native.0rtt." + encode(result[len(prefix):]))
')
export FAKE_ENCRYPTION_PRIVATE FAKE_ENCRYPTION_PUBLIC
export FAKE_ENCRYPTION_XRAY_IMAGE FAKE_ENCRYPTION_REAL_JQ
FAKE_ENCRYPTION_XRAY_IMAGE=$(jq -r '.images.xray.reference' "${CONFIGURE_MANIFEST}")
FAKE_ENCRYPTION_REAL_JQ=$(command -v jq)
cp "${MOCK_BIN}/cosign" "${MOCK_BIN}/cosign-fixture"
cat >"${MOCK_BIN}/cosign" <<'SH'
#!/usr/bin/env bash
printf 'verify-signature\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
exec "$(dirname -- "$0")/cosign-fixture" "$@"
SH
cat >"${MOCK_BIN}/jq" <<'SH'
#!/usr/bin/env bash
if [[ "${FAKE_ENCRYPTION_SECURITY_CHECK:-0}" == 1 ]]; then
    for argument in "$@"; do
        [[ "${argument}" != *"${FAKE_ENCRYPTION_PRIVATE:?}"* &&
            "${argument}" != *"${FAKE_ENCRYPTION_PUBLIC:?}"* ]] || {
            printf 'Encryption 材料进入 jq 参数\n' >&2
            exit 99
        }
        if [[ -f "${argument}" ]]; then
            content=$(<"${argument}")
            if [[ "${content}" == *"${FAKE_ENCRYPTION_PRIVATE}"* ]]; then
                # 核心运行配置须由容器组读取；这里只检查私密输入和编辑材料。
                case "${argument##*/}" in
                spec.json|request.json|*.vlessenc|*.encryption.json|*.next)
                    [[ "$(stat -c '%a' "${argument}")" == 600 ]] || {
                        printf 'Encryption 私密文件权限错误: %s\n' "${argument##*/}" >&2
                        exit 99
                    }
                    printf 'encryption-private-0600\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
                    ;;
                esac
            fi
        fi
    done
fi
exec "${FAKE_ENCRYPTION_REAL_JQ:?}" "$@"
SH
cat >"${MOCK_BIN}/docker" <<'SH'
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
    if [[ " $* " == *' up -d '* && ! -e "${FAKE_REALITY_FAIL_MARKER:?}" ]]; then
        case "${FAKE_ENCRYPTION_MODE:-normal}" in
        health-fail) : >"${FAKE_REALITY_FAIL_MARKER}"; exit 1 ;;
        commit-int|commit-term)
            : >"${FAKE_REALITY_FAIL_MARKER}"
            signal=INT
            [[ "${FAKE_ENCRYPTION_MODE}" != commit-term ]] || signal=TERM
            kill -s "${signal}" "${PPID}"
            ;;
        esac
    fi ;;
run)
    if [[ " $* " == *' vlessenc '* ]]; then
        [[ " $* " == *" ${FAKE_ENCRYPTION_XRAY_IMAGE:?} vlessenc "* &&
            " $* " == *' --network none '* &&
            " $* " == *' --log-driver none '* ]] || exit 99
        case "${FAKE_ENCRYPTION_MODE:-normal}" in
        generation-fail) exit 1 ;;
        malformed)
            printf 'Authentication: ML-KEM-768, Post-Quantum\n"decryption": "invalid"\n"encryption": "invalid"\n'
            exit 0
            ;;
        missing-heading) ;;
        duplicate-heading)
            printf 'Authentication: ML-KEM-768, Post-Quantum\nAuthentication: ML-KEM-768, Post-Quantum\n'
            ;;
        duplicate-key)
            printf 'Authentication: ML-KEM-768, Post-Quantum\n"decryption": "%s"\n' \
                "${FAKE_ENCRYPTION_PRIVATE:?}"
            ;;
        *)
            printf 'fixture vlessenc\n\nAuthentication: X25519, not Post-Quantum\n'
            printf '"decryption": "%s"\n"encryption": "%s"\n\n' \
                "${FAKE_ENCRYPTION_PRIVATE:0:74}" "${FAKE_ENCRYPTION_PUBLIC:0:74}"
            printf 'Authentication: ML-KEM-768, Post-Quantum\n'
            ;;
        esac
        printf '"decryption": "%s"\n"encryption": "%s"\n' \
            "${FAKE_ENCRYPTION_PRIVATE:?}" "${FAKE_ENCRYPTION_PUBLIC:?}"
        exit 0
    fi
    previous=
    for argument in "$@"; do
        if [[ "${previous}" == -c && ( "${argument}" == *302e020100300506032b656e04220420* ||
            "${argument}" == *3054020100300b060960864801650304040204428040* ) ]]; then
            exec python3 -c "${argument}"
        fi
        previous=${argument}
    done
    if [[ " $* " == *' tls ping '* ]]; then
        printf 'Pinging with SNI\n'
        if [[ " $* " == *' cloudflare.com:443 '* ]]; then
            printf 'Handshake failure: certificate does not match SNI\n'
        else
            printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'
        fi
    else
        printf '192.0.2.1\tAS64500\tExampleNet\n'
    fi ;;
*) exit 1 ;;
esac
SH
chmod 0755 "${MOCK_BIN}/"{cosign,jq,docker}

encryptionAssertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'Encryption 遗留部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' -o -name '.protocol.*' \) -print -quit)" ]] ||
        fail 'Encryption 遗留秘密草稿'
    for secret in "${PRIVATE_KEY}" "${FAKE_ENCRYPTION_PRIVATE}" "${FAKE_ENCRYPTION_PUBLIC}"; do
        ! grep -Fq "${secret}" "${EVENTS}" "${STDOUT}" "${STDERR}" ||
            fail 'Encryption 材料泄漏到参数、状态或预览'
    done
}

runEncryptionEdit() {
    local expected=$1 name=$2 change=$3 actual=0 before
    shift 3
    if [[ "${change}" == unchanged ]]; then before=$(snapshot); fi
    : >"${EVENTS}"
    FAKE_ENCRYPTION_SECURITY_CHECK=1 bash -u "${CLI}" edit "$@" "${ASSET_ARGS[@]}" \
        </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    encryptionAssertClean
    if [[ "${actual}" != "${expected}" ]]; then
        cat "${STDOUT}" "${STDERR}" >&2
        fail "${name}: 预期 ${expected}，实际 ${actual}"
    fi
    [[ "${change}" != unchanged || "$(snapshot)" == "${before}" ]] ||
        fail "${name}: 改变已安装部署"
}

runEncryptionPty() {
    local answer=$1 before
    before=$(snapshot)
    : >"${EVENTS}"
    FAKE_ENCRYPTION_SECURITY_CHECK=1 python3 - "${STDOUT}" "${answer}" \
        bash -u "${CLI}" edit --vless-encryption vless-reality enable "${ASSET_ARGS[@]}" <<'PY'
import errno
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[3:], stdin=slave, stdout=slave, stderr=slave,
                           start_new_session=True)
os.close(slave)
output = bytearray()
sent = False
deadline = time.monotonic() + 30
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], .1)[0]:
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not data:
                break
            output.extend(data)
            if not sent and b"[y/N]: " in output:
                os.write(master, b"\x04" if sys.argv[2] == "eof" else b"n\n")
                sent = True
        elif process.poll() is not None:
            break
    assert sent, ("Encryption 未显示一次提交确认，退出码 " + str(process.poll()) +
                  ": " + output.decode(errors="replace"))
    assert process.wait(timeout=5) == 0, output.decode(errors="replace")
    assert output.count(b"[y/N]: ") == 1
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    Path(sys.argv[1]).write_bytes(output)
PY
    : >"${STDERR}"
    encryptionAssertClean
    [[ "$(snapshot)" == "${before}" ]] || fail "${answer}: Encryption 取消改变部署"
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'Encryption 取消时启动候选'
}

newState vless-encryption "${ENCRYPTION_SPEC}"
dockerEnsureRuntimeDataPermissions
before=$(snapshot)
dockerProtocolCommand encryption-status >"${STDOUT}" 2>"${STDERR}"
jq -e '.experimental == true and
  (.entries | map({listener_id,protocol,enabled}) | sort_by(.listener_id)) ==
  ([{listener_id:"vless-reality",protocol:1,enabled:false},
    {listener_id:"entry-xhttp",protocol:2,enabled:false}] | sort_by(.listener_id))' \
    "${STDOUT}" >/dev/null || fail 'Encryption 状态未限定支持入口或默认 none'
[[ "$(snapshot)" == "${before}" ]] || fail 'Encryption 状态改变部署'
encryptionAssertClean

for listener in entry-missing entry-grpc-xray entry-grpc-sing vless-ws ../../draft; do
    runEncryptionEdit 15 "reject-${listener}" unchanged \
        --vless-encryption "${listener}" enable --preview
    ! grep -Eq '^run .* vlessenc' "${EVENTS}" || fail '不支持入口仍生成 Encryption 材料'
done
for args in 'entry-xhttp invalid' 'entry-xhttp' ''; do
    read -r -a arguments <<<"${args}"
    runEncryptionEdit 2 invalid-arguments unchanged --vless-encryption "${arguments[@]}" --preview
done
runEncryptionEdit 2 noninteractive unchanged --vless-encryption vless-reality enable
runEncryptionEdit 2 with-spec unchanged --vless-encryption vless-reality enable \
    --spec "${ENCRYPTION_SPEC}" --preview
runEncryptionEdit 2 duplicate unchanged --vless-encryption vless-reality enable \
    --vless-encryption entry-xhttp disable --preview
for mode in generation-fail malformed missing-heading duplicate-heading duplicate-key; do
    FAKE_ENCRYPTION_MODE=${mode} runEncryptionEdit 15 "${mode}" unchanged \
        --vless-encryption vless-reality enable --preview
done
runEncryptionPty cancel
runEncryptionPty eof

for listener in vless-reality entry-xhttp; do
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/before-spec.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" "${TEST_ROOT}/before-traffic.json"
    for core in xray sing-box; do
        cp "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" "${TEST_ROOT}/before-${core}.json"
    done
    runEncryptionEdit 0 "${listener}-preview" unchanged \
        --vless-encryption "${listener}" enable --preview
    awk '/^verify-signature$/ {verified=1} /^run .* vlessenc/ {
      if (!verified) exit 1; generated=1} END {if (!generated) exit 1}' "${EVENTS}" ||
        fail 'Encryption 在可信资产验签前生成材料'
    grep -Fq encryption-private-0600 "${EVENTS}" || fail 'Encryption 未经过 0600 私密文件'
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'Encryption 预览启动了候选'
    runEncryptionEdit 0 "${listener}-enable" changed \
        --vless-encryption "${listener}" enable --confirm PADM-DOCKER-EDIT
    jq -en --arg listener "${listener}" --arg private "${FAKE_ENCRYPTION_PRIVATE}" \
        --arg public "${FAKE_ENCRYPTION_PUBLIC}" --slurpfile old "${TEST_ROOT}/before-spec.json" \
        --slurpfile new "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      $new[0] == ($old[0] | .core.protocols |= map(if .listener_id == $listener then
        .vless_encryption = {decryption:$private,encryption:$public} else . end))
    ' >/dev/null || fail "${listener}: Encryption 改写非目标规格"
    cmp -s "${TEST_ROOT}/before-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail 'Encryption 改变账号累计或额度'
    [[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")" == 600 ]] ||
        fail 'Encryption 规格权限不是 0600'
    for core in xray sing-box; do
        [[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base")" == 600 ]] ||
            fail 'Encryption 完整账号底稿权限不是 0600'
    done
    jq -e --arg listener "${listener}" --arg private "${FAKE_ENCRYPTION_PRIVATE}" '
      any(.inbounds[]; .tag == $listener and .settings.decryption == $private)
    ' "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" >/dev/null ||
        fail 'Encryption 未进入选中 Xray 入口'
    jq -en --arg listener "${listener}" --slurpfile old "${TEST_ROOT}/before-xray.json" \
        --slurpfile new "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" '
      def stable: .inbounds |= map(if .tag == $listener then del(.settings.decryption) else . end);
      ($old[0] | stable) == ($new[0] | stable)
    ' >/dev/null || fail 'Encryption 改变其它 Xray 入口'
    cmp -s "${TEST_ROOT}/before-sing-box.json" "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" ||
        fail 'Encryption 改变 sing-box 入口'
    dockerProtocolCommand links >"${TEST_ROOT}/encrypted.uri"
    python3 - "${TEST_ROOT}/encrypted.uri" "${listener}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" <<'PY'
import json
import os
from pathlib import Path
import sys
from urllib.parse import parse_qs, urlsplit

spec = json.loads(Path(sys.argv[3]).read_text())
port = next(entry["public_port"] for entry in spec["core"]["protocols"]
            if entry["listener_id"] == sys.argv[2])
for uri in Path(sys.argv[1]).read_text().splitlines():
    node = urlsplit(uri)
    expected = os.environ["FAKE_ENCRYPTION_PUBLIC"] if node.port == port else "none"
    assert parse_qs(node.query)["encryption"] == [expected]
PY
    cmp -s "${TEST_ROOT}/encrypted.uri" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" ||
        fail 'Encryption 分享 URI 与 HTTPS 发布内容不同步'
    runEncryptionEdit 15 already-enabled unchanged \
        --vless-encryption "${listener}" enable --preview
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/enabled-spec.json"
    dockerProtocolCommand encryption-status "${listener}" >"${STDOUT}" 2>"${STDERR}"
    jq -e '.experimental == true and (.entries | length) == 1 and .entries[0].enabled == true' \
        "${STDOUT}" >/dev/null || fail 'Encryption 启用后状态错误'
    encryptionAssertClean
    runEncryptionEdit 0 "${listener}-disable" changed \
        --vless-encryption "${listener}" disable --confirm PADM-DOCKER-EDIT
    jq -en --slurpfile old "${TEST_ROOT}/before-spec.json" \
        --slurpfile new "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '$old[0] == $new[0]' >/dev/null ||
        fail '关闭 Encryption 未精确恢复 none 规格'
    dockerProtocolCommand links "${listener}" >"${STDOUT}" 2>"${STDERR}"
    grep -Fq 'encryption=none&' "${STDOUT}" || fail '关闭 Encryption 未恢复 none URI'
    runEncryptionEdit 15 already-disabled unchanged \
        --vless-encryption "${listener}" disable --preview
done

for mode in health-fail commit-int commit-term; do
    before=$(liveSnapshot)
    rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
    expected=14
    [[ "${mode}" != commit-int ]] || expected=130
    [[ "${mode}" != commit-term ]] || expected=143
    FAKE_ENCRYPTION_MODE=${mode} runEncryptionEdit "${expected}" "${mode}" changed \
        --vless-encryption entry-xhttp enable --confirm PADM-DOCKER-EDIT
    [[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
        fail "${mode}: Encryption 未恢复完整旧部署"
done

# 同时验证 JSON Schema 和生产校验，旧 bundle 必须在使用新字段前拒绝。
python3 - "${PROJECT_ROOT}" "${TEST_ROOT}" <<'PY'
import copy
import json
import os
from pathlib import Path
import sys
from jsonschema import Draft202012Validator, FormatChecker

project, root = map(Path, sys.argv[1:])
base = json.loads((root / "encryption-base.json").read_text())
schema = json.loads((project / "docker/contracts/configure.schema.json").read_text())
validator = Draft202012Validator(schema, format_checker=FormatChecker())
pair = {"decryption": os.environ["FAKE_ENCRYPTION_PRIVATE"],
        "encryption": os.environ["FAKE_ENCRYPTION_PUBLIC"]}
valid = copy.deepcopy(base)
valid["core"]["protocols"][0]["vless_encryption"] = pair
cases = [("valid", valid, True)]
item = copy.deepcopy(valid)
prefix, key = pair["encryption"].rsplit(".", 1)
item["core"]["protocols"][0]["vless_encryption"]["encryption"] = (
    prefix + "." + ("B" if key[0] != "B" else "C") + key[1:])
cases.append(("mismatched-public", item, True))
for name, target, value in [
    ("sing-box", 3, pair), ("grpc", 2, pair), ("empty", 0, {}),
    ("missing-public", 0, {"decryption": pair["decryption"]}),
    ("extra", 0, dict(pair, extra=True)), ("none", 0, dict(pair, encryption="none")),
    ("wrong-private", 0, dict(pair, decryption="invalid")),
    ("wrong-public", 0, dict(pair, encryption="invalid")),
]:
    item = copy.deepcopy(base)
    item["core"]["protocols"][target]["vless_encryption"] = value
    cases.append((name, item, False))
item = copy.deepcopy(valid)
item["schema_version"] = 2
cases.append(("old-schema", item, False))
with (root / "encryption-schema-cases").open("w") as ledger:
    for name, item, expected in cases:
        assert validator.is_valid(item) == expected, name
        path = root / f"encryption-{name}.json"
        path.write_text(json.dumps(item))
        path.chmod(0o600)
        ledger.write(f"{name}\t{int(expected)}\n")
PY
while IFS=$'\t' read -r name valid; do
    if dockerConfigureSpecValidate "${TEST_ROOT}/encryption-${name}.json" 2>/dev/null; then
        [[ "${valid}" == 1 ]] || fail "生产校验接受非法 Encryption: ${name}"
    else
        [[ "${valid}" == 0 ]] || fail "生产校验拒绝有效 Encryption: ${name}"
    fi
done <"${TEST_ROOT}/encryption-schema-cases"
# 错配公钥仍满足完整形状合同，但必须由生产配对校验拒绝。
dockerVlessEncryptionValidate "${TEST_ROOT}/encryption-valid.json" "${OPS_IMAGE}" ||
    fail 'Encryption 配对校验拒绝真实派生夹具'
if dockerVlessEncryptionValidate "${TEST_ROOT}/encryption-mismatched-public.json" "${OPS_IMAGE}"; then
    fail 'Encryption 配对校验接受形状合法的错配公钥'
fi
cp "${PROJECT_ROOT}/docker/contracts/configure.schema.json" "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
cp "${PROJECT_ROOT}/docker/contracts/features.json" "${COMPAT_BUNDLE}/docker/contracts/features.json"
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/encryption-valid.json" ||
    fail '当前 bundle 拒绝 Encryption'
jq 'del(.["x-padm-vless-encryption"])' \
    "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json" >"${TEST_ROOT}/old-encryption-schema.json"
cp "${TEST_ROOT}/old-encryption-schema.json" "${COMPAT_BUNDLE}/docker/contracts/configure.schema.json"
if dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${TEST_ROOT}/encryption-valid.json" 2>/dev/null; then
    fail '缺少 marker 的旧 bundle 接受 Encryption'
fi
dockerBundleSupportsSpec "${COMPAT_BUNDLE}" "${ENCRYPTION_SPEC}" ||
    fail 'Encryption marker 误拒旧 none 规格'
runEncryptionEdit 15 import-frozen unchanged --spec "${TEST_ROOT}/encryption-valid.json" --preview

(
    dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/menu-events"; }
    : >"${TEST_ROOT}/menu-events"
    dockerMenuProtocols >"${STDOUT}" <<'INPUT'
18
1
2
vless-reality
3
entry-xhttp
0
0
INPUT
    expected=$'protocol list\nprotocol encryption-status\nprotocol encryption-status\nedit --vless-encryption vless-reality enable\nprotocol encryption-status\nedit --vless-encryption entry-xhttp disable'
    [[ "$(<"${TEST_ROOT}/menu-events")" == "${expected}" ]] || fail 'Encryption 菜单派发错误'
    grep -Fq '重新导入分享 URI' "${STDOUT}" || fail 'Encryption 菜单缺少客户端重导提示'
    grep -Fq '固定 Xray/Mihomo' "${STDOUT}" || fail 'Encryption 菜单缺少实验支持范围'
    ! grep -Fq '[y/N]' "${STDOUT}" || fail 'Encryption 菜单重复提交确认'
)
(
    : >"${TEST_ROOT}/menu-events"
    dockerMenuRun() {
        printf '%s\n' "$*" >>"${TEST_ROOT}/menu-events"
        [[ "$*" != 'protocol encryption-status' ]]
    }
    dockerMenuVlessEncryption >"${STDOUT}" <<'INPUT'
2
0
INPUT
    [[ "$(<"${TEST_ROOT}/menu-events")" == 'protocol encryption-status' ]] ||
        fail 'Encryption 状态失败后仍进入编辑'
)
(
    : >"${TEST_ROOT}/menu-events"
    dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/menu-events"; }
    dockerMenuVlessEncryption >"${STDOUT}" <<'INPUT'
2
0
3

0
INPUT
    [[ "$(<"${TEST_ROOT}/menu-events")" == $'protocol encryption-status\nprotocol encryption-status' ]] ||
        fail 'Encryption 入口取消仍提交编辑'
)
encryptionAssertClean
printf 'docker-vless-encryption-regression-ok\n'
