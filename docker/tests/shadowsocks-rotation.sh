#!/usr/bin/env bash
set -euo pipefail

# 只加载可信资产与真实部署夹具，不串跑其它协议的完整基线。
# shellcheck source=/dev/null
PADM_DOCKER_TEST_FIXTURE_ONLY=1 source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
export OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
dockerConfigureTestFixture
ASSET_ARGS=(--manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" --control-bundle "${CONFIGURE_CONTROL}")
SS_ROTATION_SPEC="${TEST_ROOT}/ss-rotation.json"
SS_ACCOUNT=22222222-2222-4222-8222-222222222222
SS_GROUP=share-1111111111111111
SS_GROUP_TOKEN=ss-rotation-share-token-0123456789
export FAKE_SS_SERVER_PASSWORD=AAECAwQFBgcICQoLDA0ODw==
export FAKE_SS_USER_PASSWORD=+/v7+/v7+/v7+/v7+/v7+w==
export FAKE_SS_ACCOUNT_PASSWORD=AQEBAQEBAQEBAQEBAQEBAQ==
export FAKE_SS_OTHER_SERVER=BQUFBQUFBQUFBQUFBQUFBQ==
export FAKE_SS_OTHER_USER=BgYGBgYGBgYGBgYGBgYGBg==
export FAKE_SS_ROTATION_PASSWORD=AwMDAwMDAwMDAwMDAwMDAw==
export FAKE_SS_ROTATION_SECOND=BAQEBAQEBAQEBAQEBAQEBA==
export FAKE_SS_ROTATION_FAILURE=BwcHBwcHBwcHBwcHBwcHBw==
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --arg account "${SS_ACCOUNT}" --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .core.secondary_type = "sing-box" |
  .core.protocols += [
    {id:30,listener_id:"entry-ss",core:"sing-box",server:"ss.example.com",public_port:30443,
      address_families:["ipv4","ipv6"],name:"Self-SS",uuid:.core.protocols[0].uuid,
      shadowsocks:{method:"2022-blake3-aes-128-gcm",
        server_password:env.FAKE_SS_SERVER_PASSWORD,user_password:env.FAKE_SS_USER_PASSWORD}},
    {id:30,listener_id:"entry-ss-copy",core:"sing-box",server:"copy.example.com",public_port:30444,
      address_families:["ipv4","ipv6"],name:"Copy-SS",uuid:.core.protocols[0].uuid,
      shadowsocks:{method:"2022-blake3-aes-128-gcm",
        server_password:env.FAKE_SS_SERVER_PASSWORD,user_password:env.FAKE_SS_USER_PASSWORD}},
    {id:30,listener_id:"entry-ss-other",core:"sing-box",server:"other.example.com",public_port:30445,
      address_families:["ipv4"],name:"Other-SS",uuid:"55555555-5555-4555-8555-555555555555",
      shadowsocks:{method:"2022-blake3-aes-128-gcm",
        server_password:env.FAKE_SS_OTHER_SERVER,user_password:env.FAKE_SS_OTHER_USER}}] |
  .accounts = [{id:$account,name:"Alice",enabled:true,
    uuid:"44444444-4444-4444-8444-444444444444",password:"Alice.-~@+=:Secret",
    shadowsocks_password:env.FAKE_SS_ACCOUNT_PASSWORD,listeners:["entry-ss","entry-ss-copy"]}]
' "${TEST_ROOT}/v3.json" >"${SS_ROTATION_SPEC}"
chmod 0600 "${SS_ROTATION_SPEC}"
dockerConfigureSpecValidate "${SS_ROTATION_SPEC}" || fail 'SS 轮换双核心发布夹具无效'
export FAKE_SS_REAL_JQ FAKE_SS_REAL_OPENSSL FAKE_SS_ROTATION_OPS_IMAGE
FAKE_SS_REAL_JQ=$(command -v jq)
FAKE_SS_REAL_OPENSSL=$(command -v openssl)
FAKE_SS_ROTATION_OPS_IMAGE=$(jq -r '.images.ops.reference' "${CONFIGURE_MANIFEST}")
export FAKE_SS_ROTATION_COUNTER="${TEST_ROOT}/ss-random-count"
cp "${MOCK_BIN}/cosign" "${MOCK_BIN}/cosign-fixture"
cat >"${MOCK_BIN}/cosign" <<'SH'
#!/usr/bin/env bash
printf 'verify-signature\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
[[ "${FAKE_SS_ROTATION_MODE:-normal}" != signature-fail ]] || exit 1
exec "$(dirname -- "$0")/cosign-fixture" "$@"
SH
cat >"${MOCK_BIN}/jq" <<'SH'
#!/usr/bin/env bash
if [[ "${FAKE_SS_ROTATION_SECURITY_CHECK:-0}" == 1 ]]; then
    for argument in "$@"; do
        for secret in "${FAKE_SS_SERVER_PASSWORD:?}" "${FAKE_SS_USER_PASSWORD:?}" \
            "${FAKE_SS_ACCOUNT_PASSWORD:?}" "${FAKE_SS_OTHER_SERVER:?}" "${FAKE_SS_OTHER_USER:?}" \
            "${FAKE_SS_ROTATION_PASSWORD:?}" "${FAKE_SS_ROTATION_SECOND:?}" \
            "${FAKE_SS_ROTATION_FAILURE:?}"; do
            [[ "${argument}" != *"${secret}"* ]] || {
                printf 'SS 密钥进入 jq 参数\n' >&2
                exit 99
            }
        done
        if [[ -f "${argument}" ]]; then
            case "${argument##*/}" in
            spec.json|request.json|original.json|normalized.json|draft.json|*.next|*.credentials)
                [[ "$(stat -c '%a' "${argument}")" == 600 ]] || {
                    printf 'SS 私密文件权限错误: %s\n' "${argument##*/}" >&2
                    exit 99
                }
                printf 'ss-private-0600\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
                ;;
            esac
        fi
    done
fi
exec "${FAKE_SS_REAL_JQ:?}" "$@"
SH
cat >"${MOCK_BIN}/openssl" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == rand && "${2:-}" == -base64 && "${3:-}" == 16 ]]; then
    printf 'host-ss-random\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
    case "${FAKE_SS_ROTATION_MODE:-normal}" in
    generation-fail) exit 1 ;;
    malformed) printf 'invalid-key\n'; exit 0 ;;
    *) printf 'unexpected SS random fallback\n' >&2; exit 99 ;;
    esac
fi
exec "${FAKE_SS_REAL_OPENSSL:?}" "$@"
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
        case "${FAKE_SS_ROTATION_MODE:-normal}" in
        health-fail) : >"${FAKE_REALITY_FAIL_MARKER}"; exit 1 ;;
        commit-int|commit-term)
            : >"${FAKE_REALITY_FAIL_MARKER}"
            signal=INT
            [[ "${FAKE_SS_ROTATION_MODE}" != commit-term ]] || signal=TERM
            kill -s "${signal}" "${PPID}"
            ;;
        esac
    fi ;;
run)
    if [[ " $* " == *' rand -base64 16 '* ]]; then
        [[ " $* " == *" ${FAKE_SS_ROTATION_OPS_IMAGE:?} rand -base64 16 "* &&
            " $* " == *' --entrypoint openssl '* &&
            " $* " == *' --network none '* && " $* " == *' --log-driver none '* ]] || exit 99
        count=0
        [[ ! -f "${FAKE_SS_ROTATION_COUNTER:?}" ]] || read -r count <"${FAKE_SS_ROTATION_COUNTER}"
        count=$((count + 1))
        printf '%s\n' "${count}" >"${FAKE_SS_ROTATION_COUNTER}"
        case "${FAKE_SS_ROTATION_MODE:-normal}" in
        generation-fail) exit 1 ;;
        malformed) printf 'invalid-key\n' ;;
        collision) printf '%s\n' "${FAKE_SS_USER_PASSWORD:?}" ;;
        retry)
            case "${count}" in
            1) printf '%s\n' "${FAKE_SS_SERVER_PASSWORD:?}" ;;
            2) printf '%s\n' "${FAKE_SS_USER_PASSWORD:?}" ;;
            3) printf '%s\n' "${FAKE_SS_ACCOUNT_PASSWORD:?}" ;;
            4) printf '%s\n' "${FAKE_SS_OTHER_SERVER:?}" ;;
            5) printf '%s\n' "${FAKE_SS_OTHER_USER:?}" ;;
            *) printf '%s\n' "${FAKE_SS_ROTATION_PASSWORD:?}" ;;
            esac ;;
        second) printf '%s\n' "${FAKE_SS_ROTATION_SECOND:?}" ;;
        health-fail|commit-int|commit-term) printf '%s\n' "${FAKE_SS_ROTATION_FAILURE:?}" ;;
        *) printf '%s\n' "${FAKE_SS_ROTATION_PASSWORD:?}" ;;
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
        else
            printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'
        fi
    else
        printf '192.0.2.1\tAS64500\tExampleNet\n'
    fi ;;
*) exit 1 ;;
esac
SH
chmod 0755 "${MOCK_BIN}/"{cosign,jq,openssl,docker}

ssRotationAssertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'SS 轮换遗留部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' -o -name '.protocol.*' -o -name '.subscription.*' \) \
        -print -quit)" ]] || fail 'SS 轮换遗留秘密草稿'
    for secret in "${PRIVATE_KEY}" "${FAKE_SS_SERVER_PASSWORD}" "${FAKE_SS_USER_PASSWORD}" \
        "${FAKE_SS_ACCOUNT_PASSWORD}" "${FAKE_SS_OTHER_SERVER}" "${FAKE_SS_OTHER_USER}" \
        "${FAKE_SS_ROTATION_PASSWORD}" "${FAKE_SS_ROTATION_SECOND}" "${FAKE_SS_ROTATION_FAILURE}"; do
        ! grep -Fq "${secret}" "${EVENTS}" "${STDOUT}" "${STDERR}" ||
            fail 'SS 密钥泄漏到参数、状态或预览'
    done
}

runSsRotationEdit() {
    local expected=$1 name=$2 change=$3 actual=0 before
    shift 3
    if [[ "${change}" == unchanged ]]; then before=$(snapshot); fi
    : >"${EVENTS}"
    rm -f -- "${FAKE_SS_ROTATION_COUNTER}"
    FAKE_SS_ROTATION_SECURITY_CHECK=1 bash -u "${CLI}" edit "$@" "${ASSET_ARGS[@]}" \
        </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    ssRotationAssertClean
    if [[ "${actual}" != "${expected}" ]]; then
        cat "${STDOUT}" "${STDERR}" >&2
        fail "${name}: 预期 ${expected}，实际 ${actual}"
    fi
    [[ "${change}" != unchanged || "$(snapshot)" == "${before}" ]] ||
        fail "${name}: 改变已安装部署"
}

runSsRotationPty() {
    local answer=$1 before
    before=$(snapshot)
    : >"${EVENTS}"
    rm -f -- "${FAKE_SS_ROTATION_COUNTER}"
    FAKE_SS_ROTATION_SECURITY_CHECK=1 python3 - "${STDOUT}" "${answer}" \
        bash -u "${CLI}" edit --rotate-ss-user entry-ss-copy "${ASSET_ARGS[@]}" <<'PY'
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
                answer = {"eof": b"\x04", "confirm": b"y\n"}.get(sys.argv[2], b"n\n")
                os.write(master, answer)
                sent = True
        elif process.poll() is not None:
            break
    assert sent, ("SS 轮换未显示一次提交确认，退出码 " + str(process.poll()) +
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
    ssRotationAssertClean
    if [[ "${answer}" != confirm ]]; then
        [[ "$(snapshot)" == "${before}" ]] || fail "${answer}: SS 取消改变部署"
        ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'SS 取消时启动候选'
    else
        grep -Fq 'Docker 配置已提交' "${STDOUT}" || fail 'SS 一次确认没有提交'
    fi
}

ssRotationAssertResult() {
    local listener=$1 password=$2
    jq -en --arg listener "${listener}" --arg password "${password}" \
        --slurpfile old "${TEST_ROOT}/ss-before-spec.json" \
        --slurpfile new "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      $new[0] == ($old[0] | .core.protocols |= map(if .listener_id == $listener
        then .shadowsocks.user_password = $password else . end))
    ' >/dev/null || fail 'SS 轮换改写服务器密钥、其它入口或独立账号'
    cmp -s "${TEST_ROOT}/ss-before-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail 'SS 轮换改变累计或额度'
    cmp -s "${TEST_ROOT}/ss-before-groups.json" "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" ||
        fail 'SS 轮换改变分享组授权或 token'
    cmp -s "${TEST_ROOT}/ss-before-share.txt" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${SS_GROUP_TOKEN}" ||
        fail 'SS 自用轮换改变独立账号分享内容'
    cmp -s "${TEST_ROOT}/ss-before-xray.json" "${PADM_DOCKER_INSTALL_DIR}/config/xray/users.base" ||
        fail 'SS 轮换改变 Xray 底稿'
    jq -en --arg listener "${listener}" --arg uuid "${UUID}" --arg password "${password}" \
        --slurpfile old "${TEST_ROOT}/ss-before-sing-box.json" \
        --slurpfile new "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/users.base" '
      def stable: .inbounds |= map(if .tag == $listener then
        .users |= map(if .name == $uuid then del(.password) else . end) else . end);
      ($old[0] | stable) == ($new[0] | stable) and
      any($new[0].inbounds[]; .tag == $listener and
        any(.users[]; .name == $uuid and .password == $password))
    ' >/dev/null || fail 'SS 轮换未仅更新选中自用认证'
    for core in xray sing-box; do
        [[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base")" == 600 ]] ||
            fail 'SS 完整账号底稿权限不是 0600'
        [[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json")" == 640 ]] ||
            fail 'SS 核心运行配置权限不是 0640'
    done
    [[ "$(stat -c '%a' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json")" == 600 ]] ||
        fail 'SS 规格权限不是 0600'
    dockerProtocolCommand links >"${TEST_ROOT}/ss-after-links.txt"
    python3 - "${TEST_ROOT}/ss-before-links.txt" "${TEST_ROOT}/ss-after-links.txt" \
        "${listener}" "${password}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" <<'PY'
import json
from pathlib import Path
import sys
from urllib.parse import quote, unquote, urlsplit

before, after = (Path(path).read_text().splitlines() for path in sys.argv[1:3])
listener, password = sys.argv[3:5]
spec = json.loads(Path(sys.argv[5]).read_text())
entry = next(item for item in spec["core"]["protocols"] if item["listener_id"] == listener)
assert len(before) == len(after)
changed = []
for index, (old, new) in enumerate(zip(before, after)):
    if old == new:
        continue
    old_uri, new_uri = urlsplit(old), urlsplit(new)
    assert old_uri.scheme == new_uri.scheme == "ss"
    assert old_uri.port == new_uri.port == entry["public_port"]
    assert unquote(old_uri.fragment) == unquote(new_uri.fragment) == entry["name"]
    old_keys = unquote(old_uri.password).split(":")
    new_keys = unquote(new_uri.password).split(":")
    assert old_keys[0] == new_keys[0] == entry["shadowsocks"]["server_password"]
    assert old_keys[1] != new_keys[1] == password
    assert new == old.replace(quote(":".join(old_keys), safe=""),
                              quote(":".join(new_keys), safe=""))
    changed.append(index)
assert len(changed) == 1, changed
PY
    cmp -s "${TEST_ROOT}/ss-after-links.txt" "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" ||
        fail 'SS 主订阅与实际分享链接不同步'
}

ssRotationSaveBefore() {
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/ss-before-spec.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" "${TEST_ROOT}/ss-before-traffic.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/config/share-groups.json" "${TEST_ROOT}/ss-before-groups.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${SS_GROUP_TOKEN}" "${TEST_ROOT}/ss-before-share.txt"
    for core in xray sing-box; do
        cp "${PADM_DOCKER_INSTALL_DIR}/config/${core}/users.base" "${TEST_ROOT}/ss-before-${core}.json"
    done
    dockerProtocolCommand links >"${TEST_ROOT}/ss-before-links.txt"
}

newState ss-rotation "${SS_ROTATION_SPEC}"
dockerEnsureRuntimeDataPermissions
jq -n --arg account "${SS_ACCOUNT}" --arg group "${SS_GROUP}" --arg token "${SS_GROUP_TOKEN}" '
  {schema_version:1,groups:[{id:$group,name:"Alice-SS",enabled:true,token:$token,
    account_ids:[$account],listener_ids:["entry-ss","entry-ss-copy"]}]}
' >"${TEST_ROOT}/ss-groups.json"
chmod 0600 "${TEST_ROOT}/ss-groups.json"
dockerSubscriptionPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}" "${TEST_ROOT}/ss-groups.json"
dockerEnsureRuntimeDataPermissions

for listener in entry-missing vless-reality vless-ws ../../draft; do
    runSsRotationEdit 15 "reject-${listener}" unchanged --rotate-ss-user "${listener}" --preview
    ! grep -Eq '^run .* rand -base64 16( |$)' "${EVENTS}" || fail '非 SS 入口仍生成密钥'
done
runSsRotationEdit 2 missing-listener unchanged --rotate-ss-user
runSsRotationEdit 2 noninteractive unchanged --rotate-ss-user entry-ss
runSsRotationEdit 2 duplicate unchanged --rotate-ss-user entry-ss --rotate-ss-user entry-ss-copy --preview
runSsRotationEdit 2 with-spec unchanged --rotate-ss-user entry-ss --spec "${SS_ROTATION_SPEC}" --preview
runSsRotationEdit 2 with-reality unchanged --rotate-ss-user entry-ss --regenerate-reality vless-reality --preview
runSsRotationEdit 2 with-routing unchanged --rotate-ss-user entry-ss --dns-off --preview
runSsRotationEdit 2 with-encryption unchanged --rotate-ss-user entry-ss \
    --vless-encryption vless-reality enable --preview
FAKE_SS_ROTATION_MODE=signature-fail runSsRotationEdit 16 signature-fail unchanged \
    --rotate-ss-user entry-ss --preview
[[ ! -e "${FAKE_SS_ROTATION_COUNTER}" ]] || fail '验签失败仍生成 SS 密钥'
for mode in generation-fail malformed collision; do
    FAKE_SS_ROTATION_MODE=${mode} runSsRotationEdit 15 "${mode}" unchanged \
        --rotate-ss-user entry-ss --preview
done
[[ "$(<"${FAKE_SS_ROTATION_COUNTER}")" == 32 ]] || fail 'SS 碰撞未在 32 次后拒绝'
FAKE_SS_ROTATION_MODE=retry runSsRotationEdit 0 collision-retry unchanged \
    --rotate-ss-user entry-ss --preview
[[ "$(<"${FAKE_SS_ROTATION_COUNTER}")" == 6 ]] ||
    fail 'SS 未拒绝旧自用、其它入口或独立账号的密钥碰撞'
awk '/^verify-signature$/ {verified=1} /^run .* rand -base64 16( |$)/ {
  if (!verified) exit 1; generated=1} END {if (!generated) exit 1}' "${EVENTS}" ||
    fail 'SS 在可信资产验签前生成密钥'
grep -Fq ss-private-0600 "${EVENTS}" || fail 'SS 私密草稿未保持 0600'
! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail 'SS 预览启动了候选'
runSsRotationPty cancel
runSsRotationPty eof

for field in user_password server_password; do
    jq --arg field "${field}" --arg password "${FAKE_SS_ROTATION_PASSWORD}" '
      (.core.protocols[] | select(.listener_id == "entry-ss") | .shadowsocks[$field]) = $password
    ' "${SS_ROTATION_SPEC}" >"${TEST_ROOT}/ss-manual.json"
    chmod 0600 "${TEST_ROOT}/ss-manual.json"
    runSsRotationEdit 15 "manual-${field}" unchanged --spec "${TEST_ROOT}/ss-manual.json" --preview
done
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/ss-managed.json"
rm -f -- "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
runSsRotationEdit 15 missing-managed unchanged --rotate-ss-user entry-ss --preview
cp "${TEST_ROOT}/ss-managed.json" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"

ssRotationSaveBefore
runSsRotationEdit 0 rotate-selected changed --rotate-ss-user entry-ss --confirm PADM-DOCKER-EDIT
ssRotationAssertResult entry-ss "${FAKE_SS_ROTATION_PASSWORD}"
ssRotationSaveBefore
FAKE_SS_ROTATION_MODE=second runSsRotationPty confirm
ssRotationAssertResult entry-ss-copy "${FAKE_SS_ROTATION_SECOND}"

for mode in health-fail commit-int commit-term; do
    before=$(liveSnapshot)
    rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
    expected=14
    [[ "${mode}" != commit-int ]] || expected=130
    [[ "${mode}" != commit-term ]] || expected=143
    FAKE_SS_ROTATION_MODE=${mode} runSsRotationEdit "${expected}" "${mode}" changed \
        --rotate-ss-user entry-ss-other --confirm PADM-DOCKER-EDIT
    [[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
        fail "${mode}: SS 轮换没有恢复完整旧部署"
done
(
    : >"${TEST_ROOT}/ss-menu-events"
    dockerMenuRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/ss-menu-events"; }
    dockerMenuProtocols >"${STDOUT}" <<'INPUT'
19
entry-ss
19
0
0
INPUT
    expectedMenu=$'protocol list\nprotocol list\nedit --rotate-ss-user entry-ss\nprotocol list'
    [[ "$(<"${TEST_ROOT}/ss-menu-events")" == "${expectedMenu}" ]] ||
        fail 'SS 轮换菜单派发或取消错误'
    ! grep -Fq '[y/N]' "${STDOUT}" || fail 'SS 轮换菜单重复提交确认'
)
ssRotationAssertClean
printf 'docker-shadowsocks-rotation-regression-ok\n'
