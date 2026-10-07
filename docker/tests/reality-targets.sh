#!/usr/bin/env bash
set -euo pipefail

# 复用双核部署、可信资产和事务夹具，不重复参数重生成全套场景。
# shellcheck source=/dev/null
source "$(dirname -- "${BASH_SOURCE[0]}")/reality.sh"
dockerConfigureTestFixture
ASSET_ARGS=(--manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" --control-bundle "${CONFIGURE_CONTROL}")
TARGET_SPEC="${TEST_ROOT}/reality-targets.json"
jq --arg manifest "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
    --slurpfile ws "${TEST_ROOT}/v3.json" --slurpfile release "${CONFIGURE_MANIFEST}" '
  .release = {version:"3.1.8",manifest_sha256:$manifest,signature_identity:$identity} |
  .images = ($release[0].images | with_entries(.value = .value.reference)) |
  .subscription.enabled = true | .tls = $ws[0].tls |
  .core.protocols += [(.core.protocols[0] | .listener_id = "entry-vision-sing" |
    .core = "sing-box" | .name = "Reality-Vision-sing" | .public_port = 25446)] +
    [$ws[0].core.protocols[] | select(.id == 21)] |
  .core.protocols |= map(if .id == 1 or .id == 2 or .id == 26 then
    .reality.target_host = (.listener_id + ".example.net") |
    .reality.server_name = .reality.target_host
  else . end)
' "${REALITY_SPEC}" >"${TARGET_SPEC}"
chmod 0600 "${TARGET_SPEC}"
dockerConfigureSpecValidate "${TARGET_SPEC}" || fail 'Reality 目标管理双核夹具无效'
export FAKE_TARGET_CID
FAKE_TARGET_CID=$(printf 'f%.0s' {1..64})
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
rm) [[ "$*" == "rm -f ${FAKE_TARGET_CID:?}" ]] || exit 1 ;;
compose)
    [[ "${2:-}" != version ]] || { printf 'v2.29.1\n'; exit 0; }
    if [[ " $* " == *' sing-box version '* ]]; then
        printf 'sing-box version 1.14.0\nTags: with_v2ray_api\n'
    fi
    if [[ " $* " == *' up -d '* && "${FAKE_TARGET_HEALTH_FAIL:-0}" == 1 &&
        ! -e "${FAKE_REALITY_FAIL_MARKER:?}" ]]; then
        : >"${FAKE_REALITY_FAIL_MARKER}"
        exit 1
    fi
    if [[ " $* " == *' up -d '* && "${FAKE_TARGET_SWITCH_SIGNAL:-0}" == 1 &&
        ! -e "${FAKE_TARGET_COMPOSE_STARTED:?}" ]]; then
        printf '%s\n' "${PPID}" >"${FAKE_TARGET_COMPOSE_STARTED}"
        exec sleep 60
    fi ;;
run)
    cidfile= candidate= previous=
    for argument in "$@"; do
        [[ "${previous}" != --cidfile ]] || cidfile=${argument}
        if [[ "${previous}" == --volume && "${argument}" == *:/candidate:ro ]]; then
            candidate=${argument%:/candidate:ro}
        fi
        if [[ "${previous}" == -c && "${argument}" == *302e020100300506032b656e04220420* ]]; then
            exec python3 -c "${argument}"
        fi
        if [[ "${previous}" == -c && "${argument}" == *'values["notBefore"]'* ]]; then
            [[ -n "${candidate}" ]] || exit 1
            certificate=${*: -1}
            exec python3 -c "${argument}" "${candidate}/${certificate#/candidate/}"
        fi
        previous=${argument}
    done
    if [[ " $* " == *' tls-check '* ]]; then
        files=("${@: -3}")
        cert="${candidate}/${files[0]#/candidate/}"
        key="${candidate}/${files[1]#/candidate/}"
        certPublic=$(openssl x509 -in "${cert}" -pubkey -noout) || exit 1
        keyPublic=$(openssl pkey -in "${key}" -pubout) || exit 1
        [[ "${certPublic}" == "${keyPublic}" ]] || exit 1
        exec openssl x509 -in "${cert}" -noout -checkhost "${files[2]}"
    fi
    [[ -n "${cidfile}" && ! -e "${cidfile}" && ! -L "${cidfile}" &&
        "$(stat -c '%a' "$(dirname -- "${cidfile}")")" == 700 &&
        " $* " == *' --read-only '* && " $* " == *' --cap-drop ALL '* &&
        " $* " == *' --security-opt no-new-privileges '* ]] || exit 1
    printf '%s\n' "${FAKE_TARGET_CID:?}" >"${cidfile}"
    if [[ "${FAKE_TARGET_MODE:-normal}" == probe-hang ]]; then
        printf '%s\n' "${cidfile}" >"${FAKE_TARGET_STARTED:?}"
        exec sleep 60
    fi
    if [[ " $* " == *'canonical name ='* || " $* " == *' -type=CNAME '* ||
        " $* " == *' --entrypoint nslookup '* ]]; then
        printf 'target-cname %s\n' "${*: -1}" >>"${FAKE_PROTOCOL_EVENTS}"
        case "${FAKE_TARGET_MODE:-normal}" in
        cname-fail) exit 1 ;;
        cname-risk) printf 'edge.fastly.net\n' ;;
        esac
    elif [[ " $* " == *'"s_client"'* ]]; then
        printf 'target-certificate %s\n' "${*: -3}" >>"${FAKE_PROTOCOL_EVENTS}"
        [[ "${FAKE_TARGET_MODE:-normal}" != chain-fail ]] || exit 1
        printf 'REALITY 证书链 #1\nsubject=CN=%s\nissuer=CN=fixture\n证书链数量: 1；叶子证书匹配 SNI=%s\n' \
            "${*: -1}" "${*: -1}"
    elif [[ " $* " == *' tls ping '* ]]; then
        printf 'target-tls %s\n' "${*: -3}" >>"${FAKE_PROTOCOL_EVENTS}"
        printf 'Pinging with SNI\n'
        if [[ "${*: -1}" == cloudflare.com:* ]]; then
            case "${FAKE_TARGET_MODE:-normal}" in
            cf-success) printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n' ;;
            cf-unknown) printf 'connection timed out\n' ;;
            *) printf 'Handshake failure: certificate does not match SNI\n' ;;
            esac
        else
            case "${FAKE_TARGET_MODE:-normal}" in
            tls12) printf 'Handshake succeeded\nTLS Version:\tTLS 1.2\n' ;;
            target-rejected) printf 'Handshake failure: certificate does not match SNI\n' ;;
            target-unknown) printf 'connection timed out\n' ;;
            *)
                printf 'Handshake succeeded\nTLS Version:\tTLS 1.3\n'
                grade=${FAKE_TARGET_GRADE:-C}
                if [[ "${FAKE_TARGET_MODE:-normal}" == worst-aaaa && "${*: -2:1}" == 2001:db8::1 ]]; then
                    grade=B
                fi
                [[ "${grade}" == C ]] || printf 'TLS Post-Quantum key exchange: X25519MLKEM768\n'
                if [[ "${grade}" == B ]]; then printf 'Certificate chain total length: 2048\n'
                else printf 'Certificate chain total length: 4096\n'; fi
                ;;
            esac
        fi
    else
        printf 'target-dns %s\n' "${*: -1}" >>"${FAKE_PROTOCOL_EVENTS}"
        case "${FAKE_TARGET_MODE:-normal}" in
        dns-fail) exit 1 ;;
        dns-empty) ;;
        unknown-asn) printf '192.0.2.1\tunknown\tExampleNet\n' ;;
        bad-asn) printf '192.0.2.1\tINVALID\tExampleNet\n' ;;
        risky-aaaa) printf '192.0.2.1\tAS64500\tExampleNet\n2001:db8::1\tAS13335\tCloudflare\n' ;;
        *) printf '192.0.2.1\t%s\t%s\n2001:db8::1\tAS64500\tExampleNet\n' \
            "${FAKE_TARGET_ASN:-AS64500}" "${FAKE_TARGET_ORG:-ExampleNet}" ;;
        esac
    fi ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/docker"
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'curl fixture\nFeatures: HTTP2\n'
    exit 0
fi
printf 'unexpected-download\n' >>"${FAKE_PROTOCOL_EVENTS:?}"
exit 1
EOF
chmod 0755 "${MOCK_BIN}/curl"
export TMPDIR="${TEST_ROOT}/probe-tmp"
mkdir -p "${TMPDIR}"

targetAssertCleanup() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail '目标管理遗留部署锁'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 1 \
        \( -name '.edit.*' -o -name '.candidate.*' -o -name '.protocol.*' \
        -o -name '.stage.*' -o -name '.manifest.*' \) -print -quit)" ]] ||
        fail '目标管理遗留私密工作目录'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}/.bundles" -maxdepth 1 -name '.stage.*' -print -quit)" ]] ||
        fail '目标管理遗留可信资产暂存目录'
    [[ -z "$(find "${TMPDIR}" -maxdepth 1 \
        \( -name 'padm-reality-probe.*' -o -name 'padm-docker-reality.*' \) -print -quit)" ]] ||
        fail 'Reality 探测遗留 cidfile 目录'
    ! grep -Fq "${PRIVATE_KEY}" "${EVENTS}" "${STDOUT}" "${STDERR}" ||
        fail '目标管理泄漏 Reality 私钥'
    created=$(grep -c '^run .* --cidfile ' "${EVENTS}" || true)
    removed=$(grep -c "^rm -f ${FAKE_TARGET_CID}$" "${EVENTS}" || true)
    [[ "${created}" == "${removed}" ]] || fail "探测容器未逐个清理: ${created}/${removed}"
}

targetDeploymentSnapshot() (
    cd "${PADM_DOCKER_INSTALL_DIR}"
    find . -path './.bundles' -prune -o -path './data/reality-targets' -prune -o \
        -mindepth 1 -printf '%P %y %m %u %g %l\n' | LC_ALL=C sort
    find . -path './.bundles' -prune -o -path './data/reality-targets' -prune -o \
        -type f -exec sha256sum {} + | LC_ALL=C sort
)

runTargetRead() {
    local expected=$1 name=$2 actual=0 before
    shift 2
    before=$(targetDeploymentSnapshot)
    : >"${EVENTS}"
    "$@" </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "${name}: 预期 ${expected}，实际 ${actual}"
    targetAssertCleanup
    [[ "$(targetDeploymentSnapshot)" == "${before}" ]] || fail "${name}: 检测改写已安装部署"
    ! grep -Eq '^compose .* (up|down|restart|stop|exec) |^pull ' "${EVENTS}" ||
        fail "${name}: 只读目标操作改变服务或采集流量"
}

runTargetEdit() {
    local expected=$1 name=$2 unchanged=$3 actual=0 before
    shift 3
    before=$(snapshot)
    : >"${EVENTS}"
    bash -u "${CLI}" edit "$@" "${ASSET_ARGS[@]}" \
        </dev/null >"${STDOUT}" 2>"${STDERR}" || actual=$?
    [[ "${actual}" == "${expected}" ]] || fail "${name}: 预期 ${expected}，实际 ${actual}"
    targetAssertCleanup
    [[ "${unchanged}" != unchanged || "$(snapshot)" == "${before}" ]] ||
        fail "${name}: 改变已安装部署"
}

newState reality-targets "${TARGET_SPEC}"
# 证书以容器当前时间签发；保留生产有效期、域名和公私钥匹配校验。
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 2 \
    -subj /CN=ws.example.com -addext subjectAltName=DNS:ws.example.com \
    -keyout "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.key" \
    -out "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.crt" \
    >"${STDOUT}" 2>"${STDERR}" || fail '真实短期 TLS 证书夹具生成失败'
dockerEnsureRuntimeDataPermissions
quota=$(jq --arg uuid "${UUID}" '.accounts[$uuid].limit_bytes = 1' \
    "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json")
printf '%s\n' "${quota}" | dockerTrafficWriteState
dockerTrafficPrepareCandidate "${PADM_DOCKER_INSTALL_DIR}"
runTargetRead 0 targets-all bash -u "${CLI}" protocol targets
jq -r '.core.protocols[] | select(.id == 1 or .id == 2 or .id == 26) |
  "\(.listener_id)  \(.core)  \(.reality.target_host):\(.reality.target_port)  SNI=\(.reality.server_name)"' \
    "${TARGET_SPEC}" >"${TEST_ROOT}/expected-targets.txt"
cmp -s "${STDOUT}" "${TEST_ROOT}/expected-targets.txt" || fail '目标列表混入非 Reality 入口或丢失入口'
! grep -q '^target-' "${EVENTS}" || fail '查看目标列表仍探测网络'
runTargetRead 0 targets-selected dockerProtocolCommand targets entry-grpc-sing
[[ "$(<"${STDOUT}")" == 'entry-grpc-sing  sing-box  entry-grpc-sing.example.net:443  SNI=entry-grpc-sing.example.net' ]] ||
    fail '目标列表没有按副核心入口筛选'
runTargetRead 0 check-selected bash -u "${CLI}" protocol check-target entry-grpc-sing
grep -qxF 'target-dns entry-grpc-sing.example.net' "${EVENTS}" ||
    fail '目标检测没有解析所选入口'
awk '$1 == "target-tls" && $4 != "entry-grpc-sing.example.net:443" && $4 != "cloudflare.com:443" {exit 1}' \
    "${EVENTS}" || fail '目标检测对其它入口发起 TLS 握手'
for address in 192.0.2.1 2001:db8::1; do
    grep -qxF "target-tls -ip ${address} entry-grpc-sing.example.net:443" "${EVENTS}" &&
        grep -qxF "target-tls -ip ${address} cloudflare.com:443" "${EVENTS}" ||
        fail '目标检测没有对全部 A/AAAA 执行目标及 Cloudflare SNI 探测'
done
for field in '评分: C' 'X25519MLKEM768: no' 'TLS1.3: yes' '证书链长度: 4096' \
    '全部 2 个地址按最差评分聚合' '证书链数量: 1'; do
    grep -qF "${field}" "${STDOUT}" || fail "共享原生检测缺少结果: ${field}"
done
library="${PADM_DOCKER_INSTALL_DIR}/data/reality-targets/results.tsv"
[[ -f "${library}" && ! -s "${library}" && "$(stat -c %a "${library}")" == 600 ]] ||
    fail 'C 级检测误保存为 A 级目标或目标库权限错误'
for action in targets check-target target-status; do
    for listener in entry-missing vless-ws 1 ../../draft; do
        runTargetRead 15 "${action}-${listener}" dockerProtocolCommand "${action}" "${listener}"
        ! grep -q '^target-' "${EVENTS}" || fail '未知或非 Reality 入口仍发起探测'
    done
    runTargetRead 2 "${action}-extra" dockerProtocolCommand "${action}" entry-grpc-sing extra
    runTargetRead 2 "${action}-option" dockerProtocolCommand "${action}" --spec
done
runTargetRead 0 selected-status dockerProtocolCommand target-status entry-grpc-sing
grep -qF 'entry-grpc-sing  target=entry-grpc-sing.example.net:443' "${STDOUT}" &&
    ! grep -qF 'entry-xhttp' "${STDOUT}" && ! grep -q '^target-' "${EVENTS}" ||
    fail '目标状态没有按入口筛选或错误发起在线检测'
runTargetRead 1 empty-library dockerProtocolCommand target-library
runTargetRead 2 invalid-library-filter dockerProtocolCommand target-library unsafe
runTargetRead 2 invalid-library-page dockerProtocolCommand target-library all 0

# 原生 A/B/C 评分与最差地址聚合影响目标库；检测不改变部署和账号。
for grade in B A; do
    FAKE_TARGET_GRADE=${grade} runTargetRead 0 "check-${grade}" dockerProtocolCommand check-target entry-grpc-sing
    grep -qF "评分: ${grade}" "${STDOUT}" && grep -qF 'X25519MLKEM768: yes' "${STDOUT}" ||
        fail "${grade}: 原生 PQC 评分没有传播到 Docker"
    if [[ "${grade}" == B ]]; then
        grep -qF '证书链长度: 2048' "${STDOUT}" "${STDERR}" && [[ ! -s "${library}" ]] ||
            fail '证书链不足的 B 级目标仍进入 A 级目标库'
    else
        awk -F'\t' '$1 == "entry-grpc-sing.example.net:443" && $5 == "no" && $10 == "A" &&
          $11 == "yes" && $12 == "4096" && $13 == "yes" {valid++}
          END {exit !(NR == 1 && valid == 1)}' "${library}" || fail '安全 A 级检测没有准确写入目标库'
    fi
done
FAKE_TARGET_GRADE=A FAKE_TARGET_MODE=worst-aaaa runTargetRead 0 worst-aaaa \
    dockerProtocolCommand check-target entry-grpc-sing
grep -qF '评分: B' "${STDOUT}" && grep -qF '目标地址: 2001:db8::1 AS64500 ExampleNet' "${STDOUT}" &&
    grep -qF '全部 2 个地址按最差评分聚合' "${STDOUT}" && [[ ! -s "${library}" ]] ||
    fail 'AAAA 较差评分没有覆盖 A 记录及剔除旧 A 级结果'
FAKE_TARGET_MODE=chain-fail runTargetRead 15 certificate-check-fail \
    dockerProtocolCommand check-target entry-grpc-sing

# 风险矩阵直接调用共享校验器，避免为同一拒绝重复准备完整候选。
jq '.core.protocols |= map(select(.listener_id == "entry-grpc-sing"))' \
    "${TARGET_SPEC}" >"${TEST_ROOT}/selected-target.json"
chmod 0600 "${TEST_ROOT}/selected-target.json"
for mode in dns-fail dns-empty cname-fail cname-risk tls12 target-rejected target-unknown \
    cf-success cf-unknown unknown-asn bad-asn risky-aaaa; do
    FAKE_TARGET_MODE=${mode} runTargetRead 1 "${mode}" dockerRealityTargetsValidate "${TEST_ROOT}/selected-target.json"
done
for asn in AS13335 AS16625 AS20940 AS54113 AS60068 AS12989 AS15133 AS22822; do
    FAKE_TARGET_ASN=${asn} runTargetRead 1 "${asn}" dockerRealityTargetsValidate "${TEST_ROOT}/selected-target.json"
done
for org in Akamai Fastly Bunny StackPath EdgeCast Limelight Imperva CDN77 GCore; do
    FAKE_TARGET_ORG=${org} runTargetRead 1 "${org}" dockerRealityTargetsValidate "${TEST_ROOT}/selected-target.json"
done
for host in java.com www.java.com nodejs.org www.nodejs.org riotcdn.net www.riotcdn.net; do
    jq --arg host "${host}" '.core.protocols[].reality.target_host = $host' \
        "${TEST_ROOT}/selected-target.json" >"${TEST_ROOT}/blacklisted-target.json"
    chmod 0600 "${TEST_ROOT}/blacklisted-target.json"
    runTargetRead 1 "${host}" dockerRealityTargetsValidate "${TEST_ROOT}/blacklisted-target.json"
    ! grep -q '^target-' "${EVENTS}" || fail '静态风险域名被拒后仍开始探测'
done

for listener in vless-reality entry-xhttp entry-grpc-sing; do
    cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/target-before.json"
    cp "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" "${TEST_ROOT}/target-traffic.json"
    dockerProtocolCommand links >"${TEST_ROOT}/target-links.txt"
    dockerProtocolCommand links "${listener}" >"${TEST_ROOT}/target-selected.uri"
    before=$(liveSnapshot)
    runTargetEdit 0 "${listener}-preview" unchanged --reality-target "${listener}" \
        new-target.example.net 8443 front.example.net --preview
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail '目标预览提前启动候选'
    runTargetEdit 0 "${listener}-confirm" changed --reality-target "${listener}" \
        new-target.example.net 8443 front.example.net --confirm PADM-DOCKER-EDIT
    backup=$(sed -n 's/^Docker 配置已提交，回滚快照: //p' "${STDOUT}")
    [[ "${backup}" == "${PADM_DOCKER_INSTALL_DIR}/backups/configure."* ]] ||
        fail "${listener}: 目标切换未生成配置恢复快照"
    jq -en --arg listener "${listener}" --slurpfile before "${TEST_ROOT}/target-before.json" \
        --slurpfile after "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
      def stable: .core.protocols |= map(if .listener_id == $listener then
        del(.reality.target_host,.reality.target_port,.reality.server_name) else . end);
      ($before[0] | stable) == ($after[0] | stable) and
      any($after[0].core.protocols[]; .listener_id == $listener and
        .reality.target_host == "new-target.example.net" and .reality.target_port == 8443 and
        .reality.server_name == "front.example.net")
    ' >/dev/null || fail "${listener}: 目标切换改变凭据或其它入口规格"
    cmp -s "${TEST_ROOT}/target-traffic.json" "${PADM_DOCKER_INSTALL_DIR}/data/traffic/state.json" ||
        fail "${listener}: 目标切换改变账号额度或累计流量"
    for core in xray sing-box; do
        jq -e --arg core "${core}" 'all(.inbounds[] | select(if $core == "xray"
          then .protocol == "vless" else .type == "vless" end);
          if $core == "xray" then .settings.clients == [] else .users == [] end)' \
            "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null ||
            fail "${listener}: 目标切换解除共享账号限额"
    done
    oldSni=$(jq -r --arg listener "${listener}" '.core.protocols[] |
      select(.listener_id == $listener) | .reality.server_name' "${TEST_ROOT}/target-before.json")
    selected=$(<"${TEST_ROOT}/target-selected.uri")
    expected=${selected//sni=${oldSni}/sni=front.example.net}
    while IFS= read -r line; do
        [[ "${line}" != "${selected}" ]] || line=${expected}
        printf '%s\n' "${line}"
    done <"${TEST_ROOT}/target-links.txt" >"${TEST_ROOT}/target-expected-links.txt"
    dockerProtocolCommand links >"${STDOUT}"
    cmp -s "${STDOUT}" "${TEST_ROOT}/target-expected-links.txt" &&
        cmp -s "${PADM_DOCKER_INSTALL_DIR}/data/subscription/${TOKEN}" "${TEST_ROOT}/target-expected-links.txt" ||
        fail "${listener}: 分享或启用的 HTTPS 发布未逐入口更新 SNI"
    (
        trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
        dockerAcquireDeploymentLock
        DOCKER_CONFIG_BACKUP=${backup} DOCKER_CONFIG_SWITCHED=1 dockerRestoreConfiguration
    ) >"${STDOUT}" 2>"${STDERR}" || fail "${listener}: 目标配置回滚失败"
    [[ "$(liveSnapshot)" == "${before}" ]] || fail "${listener}: 回滚没有恢复旧部署"
done
for listener in entry-missing vless-ws; do
    runTargetEdit 15 "edit-${listener}" unchanged --reality-target "${listener}" \
        new-target.example.net 8443 front.example.net --preview
    ! grep -q '^target-' "${EVENTS}" || fail '未知或非 Reality 入口仍进行候选探测'
done
for port in 0 65536 080 1e3 -1; do
    runTargetEdit 2 "invalid-port-${port}" unchanged --reality-target entry-grpc-sing \
        new-target.example.net "${port}" front.example.net --preview
done
runTargetEdit 2 invalid-host unchanged --reality-target entry-grpc-sing --host 443 front.example.net --preview
runTargetEdit 2 invalid-sni unchanged --reality-target entry-grpc-sing new-target.example.net 443 'a b' --preview
runTargetEdit 2 missing-arguments unchanged --reality-target entry-grpc-sing new-target.example.net
runTargetEdit 2 duplicate-target unchanged --reality-target entry-grpc-sing new-target.example.net 443 front.example.net \
    --reality-target entry-xhttp new-target.example.net 443 front.example.net --preview
runTargetEdit 2 with-regeneration unchanged --reality-target entry-grpc-sing new-target.example.net 443 front.example.net \
    --regenerate-reality entry-xhttp --preview
runTargetEdit 2 with-spec unchanged --reality-target entry-grpc-sing new-target.example.net 443 front.example.net \
    --spec "${TARGET_SPEC}" --preview
runTargetEdit 2 no-mode unchanged --reality-target entry-grpc-sing new-target.example.net 443 front.example.net
FAKE_TARGET_MODE=dns-fail runTargetEdit 15 rejected-target unchanged --reality-target entry-grpc-sing \
    new-target.example.net 443 front.example.net --confirm PADM-DOCKER-EDIT
! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail '风险检测失败仍启动候选'

for answer in n eof int term; do
    before=$(snapshot)
    : >"${EVENTS}"
    python3 - "${STDOUT}" "${answer}" bash -u "${CLI}" edit --reality-target entry-grpc-sing \
        new-target.example.net 8443 front.example.net "${ASSET_ARGS[@]}" <<'PY'
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
                if sys.argv[2] in ("int", "term"):
                    os.kill(process.pid, signal.SIGINT if sys.argv[2] == "int" else signal.SIGTERM)
                else:
                    os.write(master, b"\x04" if sys.argv[2] == "eof" else (sys.argv[2]+"\n").encode())
                sent = True
        elif process.poll() is not None:
            break
    assert sent, "confirmation prompt was not reached"
    assert process.wait(timeout=10) == {"int":130, "term":143}.get(sys.argv[2], 0), output.decode(errors="replace")
finally:
    if process.poll() is None:
        process.kill()
        process.wait()
    os.close(master)
    pathlib.Path(sys.argv[1]).write_bytes(output)
PY
    : >"${STDERR}"
    targetAssertCleanup
    [[ "$(snapshot)" == "${before}" ]] || fail "${answer}: 取消或中断改变部署"
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail "${answer}: 取消或中断仍启动候选"
done
before=$(liveSnapshot)
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
FAKE_TARGET_HEALTH_FAIL=1 runTargetEdit 14 health-restored changed --reality-target entry-grpc-sing \
    new-target.example.net 8443 front.example.net --confirm PADM-DOCKER-EDIT
[[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" ]] ||
    fail '目标切换健康失败未恢复旧配置'

# 缓存选择仍需重新验签与在线复测；只模拟三个可信下载资产，不放开公网请求。
export FAKE_TARGET_MANIFEST="${CONFIGURE_MANIFEST}" FAKE_TARGET_SIGNATURE="${CONFIGURE_BUNDLE}"
export FAKE_TARGET_CONTROL="${CONFIGURE_CONTROL}"
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
    printf 'curl fixture\nFeatures: HTTP2\n'
    exit 0
fi
output= previous=
for argument in "$@"; do
    [[ "${previous}" != -o ]] || output=${argument}
    previous=${argument}
done
[[ -n "${output}" ]] || exit 1
case "${*: -1}" in
https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.json)
    sourceFile=${FAKE_TARGET_MANIFEST:?} ;;
https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.sigstore.json)
    sourceFile=${FAKE_TARGET_SIGNATURE:?} ;;
https://example.invalid/control.tar.gz) sourceFile=${FAKE_TARGET_CONTROL:?} ;;
*) exit 1 ;;
esac
printf 'target-release-download %s\n' "${*: -1}" >>"${FAKE_PROTOCOL_EVENTS:?}"
cp -- "${sourceFile}" "${output}"
EOF
chmod 0755 "${MOCK_BIN}/curl"
FAKE_TARGET_GRADE=A runTargetRead 0 selection-seed dockerProtocolCommand check-target entry-xhttp
[[ "$(wc -l <"${library}")" == 1 ]] || fail '选择场景未创建唯一 A 级目标'

runTargetSelectionPty() {
    local answer=$1 expected=$2
    : >"${EVENTS}"
    python3 - "${STDOUT}" "${answer}" "${expected}" bash -u "${CLI}" protocol select-target entry-grpc-sing <<'PY'
import errno
import json
import os
import pathlib
import pty
import select
import signal
import subprocess
import sys
import time

master, slave = pty.openpty()
process = subprocess.Popen(sys.argv[4:], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
os.close(slave)
output = bytearray()
selected = False
confirmed = False
switched_signal = False
completed = False
deadline = time.monotonic()+90
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
            if not selected and "请选择本页编号切换".encode() in output:
                os.write(master, b"r\n" if sys.argv[2] == "return" else b"1\n")
                selected = True
            elif selected and not confirmed and b"[y/N]: " in output:
                if sys.argv[2] in ("int", "term"):
                    os.killpg(process.pid, signal.SIGINT if sys.argv[2] == "int" else signal.SIGTERM)
                else:
                    answer = "y" if sys.argv[2].startswith("switched-") else sys.argv[2]
                    os.write(master, (answer+"\n").encode())
                confirmed = True
        if confirmed and sys.argv[2].startswith("switched-") and not switched_signal:
            marker = pathlib.Path(os.environ["FAKE_TARGET_COMPOSE_STARTED"])
            if marker.exists():
                spec = json.loads(pathlib.Path(os.environ["PADM_DOCKER_INSTALL_DIR"], "config/spec.json").read_text())
                entry = next(value for value in spec["core"]["protocols"] if value["listener_id"] == "entry-grpc-sing")
                assert entry["reality"]["target_host"] == "entry-xhttp.example.net", "signal boundary precedes configuration switch"
                os.killpg(process.pid, signal.SIGINT if sys.argv[2] == "switched-int" else signal.SIGTERM)
                switched_signal = True
    assert selected, "target library prompt was not reached"
    if sys.argv[2] not in ("return", "dns-fail"):
        assert confirmed, "transaction confirmation prompt was not reached"
    if sys.argv[2].startswith("switched-"):
        assert switched_signal, "switched compose boundary was not reached"
    assert process.wait(timeout=10) == int(sys.argv[3]), output.decode(errors="replace")
    completed = True
except Exception as error:
    raise AssertionError(
        f"select-target answer={sys.argv[2]} selected={selected} confirmed={confirmed} "
        f"switched_signal={switched_signal}\n{output.decode(errors='replace')}"
    ) from error
finally:
    if not completed:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
    os.close(master)
    pathlib.Path(sys.argv[1]).write_bytes(output)
PY
    : >"${STDERR}"
    targetAssertCleanup
}

for answer in return n int term; do
    before=$(targetDeploymentSnapshot)
    expected=0
    [[ "${answer}" != int ]] || expected=130
    [[ "${answer}" != term ]] || expected=143
    runTargetSelectionPty "${answer}" "${expected}"
    [[ "$(targetDeploymentSnapshot)" == "${before}" ]] || fail "select-${answer}: 返回或取消改变部署"
    ! grep -Eq '^compose .* up -d ' "${EVENTS}" || fail "select-${answer}: 返回或取消启动候选"
    if [[ "${answer}" != return ]]; then
        grep -qxF 'target-dns entry-xhttp.example.net' "${EVENTS}" ||
            fail "select-${answer}: 缓存选择没有重新在线检测"
    fi
done
before=$(targetDeploymentSnapshot)
FAKE_TARGET_MODE=dns-fail runTargetSelectionPty dns-fail 15
[[ "$(targetDeploymentSnapshot)" == "${before}" ]] && ! grep -Eq '^compose .* up -d ' "${EVENTS}" ||
    fail '缓存 A 级复测失败仍改变或启动部署'
cp "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" "${TEST_ROOT}/selection-before.json"
before=$(liveSnapshot)
runTargetSelectionPty y 0
jq -en --slurpfile before "${TEST_ROOT}/selection-before.json" \
    --slurpfile after "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
  def stable: .core.protocols |= map(if .listener_id == "entry-grpc-sing" then
    del(.reality.target_host,.reality.target_port,.reality.server_name) else . end);
  ($before[0] | stable) == ($after[0] | stable) and
  any($after[0].core.protocols[]; .listener_id == "entry-grpc-sing" and
    .reality.target_host == "entry-xhttp.example.net" and .reality.target_port == 443 and
    .reality.server_name == "entry-xhttp.example.net")
' >/dev/null || fail '缓存选择没有提交到指定入口或改变其它字段'
grep -qxF 'target-dns entry-xhttp.example.net' "${EVENTS}" &&
    grep -q '^target-release-download ' "${EVENTS}" || fail '缓存选择没有复测或获取可信发布资产'
backup=$(sed -n 's/^Docker 配置已提交，回滚快照: //p' "${STDOUT}" | tr -d '\r')
(
    trap 'dockerCleanupConfigurationCandidate; dockerReleaseDeploymentLock' EXIT
    dockerAcquireDeploymentLock
    DOCKER_CONFIG_BACKUP=${backup} DOCKER_CONFIG_SWITCHED=1 dockerRestoreConfiguration
) >"${STDOUT}" 2>"${STDERR}" || fail '缓存选择配置回滚失败'
[[ "$(liveSnapshot)" == "${before}" ]] || fail '缓存选择回滚没有恢复旧部署'
export FAKE_TARGET_COMPOSE_STARTED="${TEST_ROOT}/select-compose-started"
for signalName in int term; do
    before=$(liveSnapshot)
    oldBundle=$(readlink "${PADM_DOCKER_INSTALL_DIR}/bundle")
    rm -f -- "${FAKE_TARGET_COMPOSE_STARTED}"
    expected=130
    [[ "${signalName}" != term ]] || expected=143
    FAKE_TARGET_SWITCH_SIGNAL=1 runTargetSelectionPty "switched-${signalName}" "${expected}"
    [[ -s "${FAKE_TARGET_COMPOSE_STARTED}" && "$(liveSnapshot)" == "${before}" &&
        "$(readlink "${PADM_DOCKER_INSTALL_DIR}/bundle")" == "${oldBundle}" ]] ||
        fail "select-${signalName}: 提交后中断没有恢复旧规格、账号、证书和发布"
    [[ "$(grep -c '^compose .* up -d ' "${EVENTS}")" -ge 2 ]] ||
        fail "select-${signalName}: 未触发候选启动后的旧服务恢复"
done
before=$(liveSnapshot)
oldBundle=$(readlink "${PADM_DOCKER_INSTALL_DIR}/bundle")
rm -f -- "${FAKE_REALITY_FAIL_MARKER}"
FAKE_TARGET_HEALTH_FAIL=1 runTargetSelectionPty y 14
[[ -e "${FAKE_REALITY_FAIL_MARKER}" && "$(liveSnapshot)" == "${before}" &&
    "$(readlink "${PADM_DOCKER_INSTALL_DIR}/bundle")" == "${oldBundle}" ]] ||
    fail '缓存选择健康失败没有恢复完整旧部署'

# 信号通过真实进程组送入探测，既检查返回码，也检查只清理本次 cid。
export FAKE_TARGET_STARTED="${TEST_ROOT}/probe-started" FAKE_TARGET_MODE=probe-hang
for signalName in timeout int term; do
    : >"${EVENTS}"
    rm -f -- "${FAKE_TARGET_STARTED}"
    python3 - "${signalName}" "${PROJECT_ROOT}/install-docker.sh" "${FAKE_TARGET_STARTED}" \
        "${STDOUT}" "${STDERR}" <<'PY'
import os
import pathlib
import signal
import subprocess
import sys
import time

seconds = "1" if sys.argv[1] == "timeout" else "30"
with open(sys.argv[4], "wb") as output, open(sys.argv[5], "wb") as errors:
    process = subprocess.Popen(
        ["bash", "-c", 'source "$1"; trap "exit 130" INT; trap "exit 143" TERM; '
         'dockerRealityProbeRun "$2" fixture probe-hang', "probe", sys.argv[2], seconds],
        stdout=output, stderr=errors, start_new_session=True,
    )
    try:
        deadline = time.monotonic()+10
        while not pathlib.Path(sys.argv[3]).exists() and time.monotonic() < deadline:
            assert process.poll() is None, "probe exited before cidfile was written"
            time.sleep(0.02)
        assert pathlib.Path(sys.argv[3]).exists(), "probe did not write cidfile"
        if sys.argv[1] != "timeout":
            os.killpg(process.pid, signal.SIGINT if sys.argv[1] == "int" else signal.SIGTERM)
        status = process.wait(timeout=10)
        assert status == {"timeout":124, "int":130, "term":143}[sys.argv[1]], status
    except Exception as error:
        transcript = pathlib.Path(sys.argv[4]).read_text(errors="replace")
        diagnostics = pathlib.Path(sys.argv[5]).read_text(errors="replace")
        raise AssertionError(
            f"probe signal={sys.argv[1]} pid={process.pid} status={process.poll()}\n"
            f"stdout:\n{transcript}\nstderr:\n{diagnostics}"
        ) from error
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
PY
    targetAssertCleanup
done
unset FAKE_TARGET_MODE
printf 'docker-reality-targets-regression-ok\n'
