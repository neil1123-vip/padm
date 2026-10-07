#!/usr/bin/env bash
set -euo pipefail

# 目标算法复用原生代码，夹具仅替换网络与扫描边界。
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-target-library.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export TMPDIR="${TEST_ROOT}/tmp"
mkdir "${TMPDIR}"
chmod 700 "${TEST_ROOT}" "${TMPDIR}"
export PADM_DOCKER_INSTALL_ROOT="${TEST_ROOT}/docker"
export PADM_DOCKER_ROOT="${PADM_DOCKER_INSTALL_ROOT}"
export PADM_REALITY_SECONDARY_JOBS=2 PADM_SUPPRESS_PROGRESS=1

# shellcheck source=/dev/null
source "${ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${ROOT}/docker/lib/reality-targets.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
dockerPrivateFileIsRestricted() { [[ "$(stat -c %a "$1")" == 600 ]]; }
dockerInstallRoot() { printf '%s\n' "${PADM_DOCKER_INSTALL_ROOT}"; }
SPEC="${TEST_ROOT}/spec.json"
jq -n '{images:{xray:"fixture-xray",ops:"fixture-ops"},core:{protocols:[
    {id:1,listener_id:"vision",core:"xray",reality:{
        target_host:"www.postgresql.org",target_port:443,server_name:"www.postgresql.org"}},
    {id:2,listener_id:"grpc",core:"sing-box",reality:{
        target_host:"www.pgadmin.org",target_port:443,server_name:"www.pgadmin.org"}}
]}}' >"${SPEC}"
chmod 600 "${SPEC}"
STATE="$(dockerInstallRoot)/data/reality-targets"
EVENTS="${TEST_ROOT}/network-events"
: >"${EVENTS}"
export EVENTS FAKE_TARGET_FAIL='' FAKE_TARGET_CNAME_FAIL='' FAKE_TARGET_CNAME_EDGE='' FAKE_TARGET_RISK='' FAKE_TARGET_IP_BAD='' FAKE_TARGET_DNS_BAD=''
export FAKE_TARGET_GRADE=A FAKE_SCANNER_MODE='' FAKE_SCANNER_COUNTER="${TEST_ROOT}/scanner-count"
export FAKE_SCANNER_STARTED="${TEST_ROOT}/scanner-started" FAKE_SCANNER_CLEANED="${TEST_ROOT}/scanner-cleaned"
dockerRealityTargetCnameRecords() {
    printf 'CNAME %s\n' "$2" >>"${EVENTS}"
    [[ "$2" != "${FAKE_TARGET_CNAME_FAIL}" ]] || return 1
    [[ "$2" != "${FAKE_TARGET_CNAME_EDGE}" ]] || printf 'edge.fastly.net\n'
    return 0
}
dockerRealityTargetNetworkRecords() {
    local host=$2 address
    printf 'DNS %s\n' "${host}" >>"${EVENTS}"
    [[ "${host}" != "${FAKE_TARGET_FAIL}" ]] || return 1
    address=192.0.2.1
    case "${host}" in
    *.library.test) address=192.0.2.2 ;;
    *) ;;
    esac
    printf '%s\tAS64500\tFixture Network\n2001:db8::1\tAS64500\tFixture Network\n' "${address}"
    [[ "${FAKE_TARGET_DNS_BAD}" != 1 ]] || printf 'not-an-IP\tAS64500\tFixture Network\n'
    return 0
}
dockerRealityTargetTlsPing() {
    printf 'TLS %s %s\n' "$2" "$3" >>"${EVENTS}"
    printf 'Pinging with SNI\n'
    if [[ "$3" == cloudflare.com ]]; then
        if [[ "${FAKE_TARGET_RISK}" == 1 ]]; then printf 'Handshake succeeded\n'; else printf 'Handshake failure\n'; fi
        return 0
    fi
    if [[ "$2" == "${FAKE_TARGET_IP_BAD}" ]]; then
        printf 'Handshake failure\n'
    else
        printf 'Handshake succeeded\nTLS Version: TLS 1.3\n'
        [[ "${FAKE_TARGET_GRADE}" == C ]] || printf 'TLS Post-Quantum key exchange: X25519MLKEM768\n'
        if [[ "${FAKE_TARGET_GRADE}" == B ]]; then
            printf 'Certificate chain has length: 3000\n'
        else
            printf 'Certificate chain has length: 4400\n'
        fi
    fi
}
dockerRealityTargetCertificateChain() { printf 'REALITY 证书链 #1\nSubject: %s\n' "$2"; }
dockerRealityProbeRun() {
    local seconds=$1 scanner=false mount source
    shift
    [[ "${seconds}" == 3600 ]] || fail '扫描器未使用独立时限'
    while (($#)); do
        case "$1" in
        --mount)
            shift
            mount=$1
            case "${mount}" in
            *dst=/work)
                source=${mount#type=bind,src=}
                source=${source%,dst=/work}
                [[ "${source}" == */scanner-run.* ]] || fail '扫描器挂载了非独立结果目录'
                ;;
            *dst=/scanner,readonly) ;;
            *) fail '扫描器挂载了额外路径' ;;
            esac
            ;;
        --entrypoint) shift; [[ "$1" != /scanner ]] || scanner=true ;;
        *docker.sock*) fail '扫描器获得了 Docker socket' ;;
        esac
        shift
    done
    [[ "${scanner}" == true && -n "${source:-}" ]] || fail '未执行可信扫描器'
    local count=0
    [[ ! -f "${FAKE_SCANNER_COUNTER}" ]] || count=$(<"${FAKE_SCANNER_COUNTER}")
    printf '%s\n' "$((count + 1))" >"${FAKE_SCANNER_COUNTER}"
    if [[ "${FAKE_SCANNER_MODE}" == hang ]]; then
        local scannerSelf=${BASHPID}
        trap '[[ -d "${source}" ]] && printf "cleaned\n" >"${FAKE_SCANNER_CLEANED}"; exit 143' INT TERM
        printf '%s %s\n' "${scannerSelf}" "$(ps -o ppid= -p "${scannerSelf}" | tr -d ' ')" >"${FAKE_SCANNER_STARTED}"
        while :; do command sleep 0.1; done
    fi
    [[ "${FAKE_SCANNER_MODE}" != first-fails || "${count}" != 0 ]] || return 7
    [[ "${FAKE_SCANNER_MODE}" != no-result ]] || return 7
    cat >"${source}/output.csv" <<'EOF'
IP,ORIGIN,CERT_DOMAIN,CERT_ISSUER,GEO_CODE
192.0.2.2,192.0.2.0/24,scan.library.test,Fixture CA,ZZ
192.0.2.3,192.0.2.0/24,www.cloudflare.com,Fixture CA,ZZ
EOF
    [[ "${FAKE_SCANNER_MODE}" != partial ]] || return 7
    return 0
}

# 保留可信原生算法，下载函数只给出不会执行的扫描器占位文件。
FIXTURE="${TEST_ROOT}/source"
mkdir -p "${FIXTURE}/shell/core"
cp "${ROOT}/shell/core/runtime.sh" "${ROOT}/shell/core/reality_targets.sh" "${FIXTURE}/shell/core/"
cat >>"${FIXTURE}/shell/core/reality_targets.sh" <<'EOF'
lookupRealityTargetLocation() { printf 'Fixture Location\n'; }
currentRealityNetworkProfile() { printf '192.0.2.10\tAS64500\tFixture Network\n'; }
fetchRealityAsnPrefixes() { printf '192.0.2.0/28\n198.51.100.0/28\n'; }
ensureRealityScannerBinary() {
    mkdir -p "$1"
    printf '#!/bin/sh\nexit 99\n' >"$2"
    chmod 755 "$2"
}
EOF
export DOCKER_BUNDLE_SOURCE_ROOT="${FIXTURE}"
SOURCE_CHECK=$(sha256sum "${SPEC}")
TRAPS_CHECK=$(trap -p EXIT INT TERM)
(
    # shellcheck source=/dev/null
    source "${ROOT}/shell/core/runtime.sh"
    # shellcheck source=/dev/null
    source "${ROOT}/shell/core/reality_targets.sh"
    [[ "$(realityTargetCandidatePool | wc -l)" == 25 ]] || fail '没有复用原生 25 个推荐候选'
    realityTargetCandidateBlocked foo.nodejs.org cloudflare_relay || fail '原生风险子域名未阻止'
    [[ "$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nHandshake succeeded\nTLS Version: TLS 1.3\nTLS Post-Quantum key exchange: X25519MLKEM768\nCertificate chain has length: 3500')" == B$'\t'* ]] ||
        fail 'PQC A 门槛未复用'
)
dockerRealityTargetAction "${SPEC}" status >"${TEST_ROOT}/status"
dockerRealityTargetAction "${SPEC}" blocked >"${TEST_ROOT}/blocked"
[[ ! -e "${STATE}" ]] || fail '只读状态创建了持久库'
grep -q vision "${TEST_ROOT}/status" && grep -q grpc "${TEST_ROOT}/status" || fail '入口状态遗漏'
grep -q nodejs.org "${TEST_ROOT}/blocked" || fail '黑名单不含原生风险候选'
dockerRealityTargetAction "${SPEC}" validate
[[ ! -e "${STATE}" ]] || fail 'validate 写入库'
for grade in B C; do
    FAKE_TARGET_GRADE=${grade} dockerRealityTargetAction "${SPEC}" validate \
        >"${TEST_ROOT}/validate-grade" 2>&1
    grep -q "但质量为 ${grade} 级" "${TEST_ROOT}/validate-grade" || fail '手动低评级缺少告警'
    [[ ! -e "${STATE}" ]] || fail 'validate 告警写入目标库'
done
grep -q 'TLS 2001:db8::1 www.postgresql.org' "${EVENTS}" || fail 'validate 未覆盖全部 AAAA'
LEGACY_SPEC="${TEST_ROOT}/legacy-spec.json"
jq '.core.protocols |= map(del(.listener_id, .core))' "${SPEC}" >"${LEGACY_SPEC}"
chmod 600 "${LEGACY_SPEC}"
dockerRealityTargetAction "${LEGACY_SPEC}" validate || fail '旧规格缺少入口 ID 时字段错位'
export FAKE_TARGET_IP_BAD=2001:db8::1
if dockerRealityTargetAction "${SPEC}" validate; then fail '最差地址 FAIL 未拒绝'; fi
if dockerRealityTargetAction "${LEGACY_SPEC}" validate; then fail '旧规格缺少入口 ID 时绕过地址安全门'; fi
export FAKE_TARGET_IP_BAD=
export FAKE_TARGET_DNS_BAD=1
if dockerRealityTargetAction "${SPEC}" validate; then fail '部分有效 DNS 地址掩盖后续非法记录'; fi
export FAKE_TARGET_DNS_BAD=
export FAKE_TARGET_CNAME_FAIL=www.postgresql.org
if dockerRealityTargetAction "${SPEC}" validate; then fail 'CNAME 探测失败被当作安全'; fi
export FAKE_TARGET_CNAME_FAIL='' FAKE_TARGET_CNAME_EDGE=www.postgresql.org
if dockerRealityTargetAction "${SPEC}" validate; then fail 'CNAME CDN 风险未拒绝'; fi
export FAKE_TARGET_CNAME_EDGE='' FAKE_TARGET_RISK=1
if dockerRealityTargetAction "${SPEC}" validate; then fail '异 SNI 成功未拒绝'; fi
export FAKE_TARGET_RISK=
dockerRealityTargetAction "${SPEC}" refresh recommended_only >"${TEST_ROOT}/refresh"
[[ "$(wc -l <"${STATE}/results.tsv")" == 25 ]] || fail '刷新推荐未检测原生 25 候选'
[[ "$(stat -c %a "${STATE}")" == 700 && "$(stat -c %a "${STATE}/results.tsv")" == 600 ]] || fail '目标库权限不私密'
printf '%s\n' $'old.library.test:443\told.library.test\tOld\tscanner\tno\t192.0.2.2\tAS64500\tFixture Network\tsame_asn\tA\tyes\t4500\tyes\t1\tfixture\tLocation' >>"${STATE}/results.tsv"
: >"${EVENTS}"
dockerRealityTargetAction "${SPEC}" refresh recommended_only >"${TEST_ROOT}/refresh"
if grep -q 'DNS old.library.test' "${EVENTS}"; then fail 'recommended_only 复测了旧库'; fi
dockerRealityTargetAction "${SPEC}" refresh recommended >"${TEST_ROOT}/refresh"
grep -q 'DNS old.library.test' "${EVENTS}" || fail 'recommended 没复测旧库'
dockerRealityTargetAction "${SPEC}" refresh all >"${TEST_ROOT}/refresh-all"
grep -q '全部候选清单' "${TEST_ROOT}/refresh-all" || fail 'all 刷新没有复用原生范围'
export FAKE_TARGET_FAIL=old.library.test
dockerRealityTargetAction "${SPEC}" refresh recommended >"${TEST_ROOT}/refresh"
if grep -q '^old.library.test:' "${STATE}/results.tsv"; then fail '失败目标没有移出 A 库'; fi
export FAKE_TARGET_FAIL=
dockerRealityTargetAction "${SPEC}" library same_asn 2 >"${TEST_ROOT}/library"
grep -q '第 2/' "${TEST_ROOT}/library" || fail '目标库分页未复用'
dockerRealityTargetAction "${SPEC}" library scanner 1 >"${TEST_ROOT}/filter"
grep -q '当前筛选没有 A 级目标' "${TEST_ROOT}/filter" || fail '扫描筛选包含非扫描来源'
mkdir "${TEST_ROOT}/selection"
chmod 700 "${TEST_ROOT}/selection"
selectedStatus=0
dockerRealityTargetAction "${SPEC}" candidates "${TEST_ROOT}/selection/candidate.json" \
    <<<'1' >"${TEST_ROOT}/candidates" || selectedStatus=$?
[[ "${selectedStatus}" == 2 ]] || fail '首配候选未返回选中值'
jq -e '.host != "" and .port == 443 and .sni != ""' \
    "${TEST_ROOT}/selection/candidate.json" >/dev/null || fail '首配候选输出无效'
beforeLibrary=$(sha256sum "${STATE}/results.tsv")
FAKE_TARGET_GRADE=C dockerRealityTargetAction "${SPEC}" candidates "${TEST_ROOT}/selection/no-a.json" \
    <<<'r' >"${TEST_ROOT}/candidates-no-a"
grep -q '总数：0' "${TEST_ROOT}/candidates-no-a" || fail '首配候选展示非 A 级'
[[ ! -e "${TEST_ROOT}/selection/no-a.json" &&
    "${beforeLibrary}" == "$(sha256sum "${STATE}/results.tsv")" ]] || fail '首配取消改变持久目标库'
dockerRealityTargetAction "${SPEC}" select "${TEST_ROOT}/selection/selected.json" <<<'r' >"${TEST_ROOT}/select"
[[ ! -f "${TEST_ROOT}/selection/selected.json" ]] || fail '取消选择仍写选中值'
selectedStatus=0
dockerRealityTargetAction "${SPEC}" select "${TEST_ROOT}/selection/selected.json" <<<'1' >"${TEST_ROOT}/select" || selectedStatus=$?
[[ "${selectedStatus}" == 2 ]] || fail '选择成功没有返回 2'
jq -e '.host != "" and .port == 443 and .sni != ""' "${TEST_ROOT}/selection/selected.json" >/dev/null || fail '选择结果无效'
dockerRealityTargetAction "${SPEC}" block www.postgresql.org >"${TEST_ROOT}/block"
dockerRealityTargetAction "${SPEC}" library all 1 >"${TEST_ROOT}/library"
if grep -q '  [0-9]. www.postgresql.org:443' "${TEST_ROOT}/library"; then fail '手动黑名单未从展示过滤'; fi
beforeLibrary=$(sha256sum "${STATE}/results.tsv")
dockerRealityTargetAction "${SPEC}" scan-range 192.0.2.0/28 <<<'n' >"${TEST_ROOT}/scan"
[[ "${beforeLibrary}" == "$(sha256sum "${STATE}/results.tsv")" ]] || fail '取消扫描改了 A 库'
dockerRealityTargetAction "${SPEC}" scan-range 192.0.2.0/28 <<<'y' >"${TEST_ROOT}/scan"
grep -q '^scan.library.test:443' "${STATE}/results.tsv" || fail '扫描 CSV 没有二检导入'
grep -q 'TLS 192.0.2.2 scan.library.test' "${EVENTS}" || fail '扫描结果没有 TLS 二检'
if grep -q '^www.cloudflare.com:' "${STATE}/results.tsv"; then fail '扫描导入绕过黑名单'; fi
export FAKE_TARGET_CNAME_FAIL=scan.library.test
dockerRealityTargetAction "${SPEC}" scan-range 192.0.2.0/28 <<<'y' >"${TEST_ROOT}/scan"
if grep -q '^scan.library.test:443' "${STATE}/results.tsv"; then fail '扫描 CNAME 失败仍保留了旧 A'; fi
export FAKE_TARGET_CNAME_FAIL=
FAKE_SCANNER_MODE=partial dockerRealityTargetAction "${SPEC}" scan-range 192.0.2.0/28 \
    <<<'y' >"${TEST_ROOT}/scan-partial"
grep -q '^scan.library.test:443' "${STATE}/results.tsv" &&
    grep -q '继续导入结果' "${TEST_ROOT}/scan-partial" || fail '非零扫描丢弃有效部分结果'
beforeLibrary=$(sha256sum "${STATE}/results.tsv")
if FAKE_SCANNER_MODE=no-result dockerRealityTargetAction "${SPEC}" scan-range 192.0.2.0/28 \
    <<<'y' >"${TEST_ROOT}/scan-empty"; then fail '无结果扫描错误返回成功'; fi
[[ "${beforeLibrary}" == "$(sha256sum "${STATE}/results.tsv")" ]] || fail '无结果失败改变持久库'
dockerRealityTargetAction "${SPEC}" scan-asn 4 <<<$'y\ny' >"${TEST_ROOT}/asn"
grep -q '本次将扫描 IP: 4' "${TEST_ROOT}/asn" || fail '同 ASN 样本规模错误'
dockerRealityTargetAction "${SPEC}" scan-asn all <<<$'y\ny' >"${TEST_ROOT}/asn-all"
grep -q '本次将扫描 IP: 28' "${TEST_ROOT}/asn-all" || fail '同 ASN 全量公告地址规模错误'
rm -f -- "${FAKE_SCANNER_COUNTER}"
FAKE_SCANNER_MODE=first-fails dockerRealityTargetAction "${SPEC}" scan-asn all \
    <<<$'y\ny' >"${TEST_ROOT}/asn-continue"
[[ "$(<"${FAKE_SCANNER_COUNTER}")" == 2 ]] &&
    grep -q '继续扫描剩余 prefix' "${TEST_ROOT}/asn-continue" || fail '失败 prefix 阻断后续扫描'
if dockerRealityTargetAction "${SPEC}" scan-asn 100001; then fail '同 ASN 超大样本未拒绝'; fi
export FAKE_TARGET_FAIL=www.pgadmin.org
if dockerRealityTargetAction "${SPEC}" check >"${TEST_ROOT}/check"; then fail '当前目标解析失败误报通过'; fi
if grep -q '^www.pgadmin.org:443' "${STATE}/results.tsv"; then fail '检测失败目标仍留在 A 库'; fi
export FAKE_TARGET_FAIL=
# 仅终止 action 父进程，不向整棵树广播，验证后台容器清理先于工作目录清理。
declare -f dockerRealityProbeRun dockerInstallRoot dockerPrivateFileIsRestricted >"${TEST_ROOT}/scanner-probe.sh"
for signalName in INT TERM; do
    rm -f -- "${FAKE_SCANNER_STARTED}" "${FAKE_SCANNER_CLEANED}"
    python3 - "${signalName}" "${ROOT}" "${SPEC}" "${TEST_ROOT}/scanner-probe.sh" \
        "${TEST_ROOT}/scanner-signal.log" <<'PY'
import os
import pathlib
import signal
import subprocess
import sys
import time

environment = dict(os.environ, FAKE_SCANNER_MODE="hang")
command = ['bash', '-c',
    'targetSource=$DOCKER_BUNDLE_SOURCE_ROOT; source "$1/docker/lib/bootstrap.sh"; '
    'DOCKER_BUNDLE_SOURCE_ROOT=$targetSource; source "$1/docker/lib/reality-targets.sh"; '
    'source "$3"; dockerRealityTargetAction "$2" scan-range 192.0.2.0/28',
    'scanner', *sys.argv[2:5]]
with open(sys.argv[5], "wb") as output:
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=output, stderr=output,
        env=environment, start_new_session=True)
    scanner_pid = None
    try:
        process.stdin.write(b"y\n")
        process.stdin.flush()
        marker = pathlib.Path(environment["FAKE_SCANNER_STARTED"])
        deadline = time.monotonic() + 10
        while not marker.exists() and time.monotonic() < deadline:
            assert process.poll() is None, pathlib.Path(sys.argv[5]).read_text(errors="replace")
            time.sleep(0.01)
        scanner_pid, action_pid = map(int, marker.read_text().split())
        os.kill(action_pid, getattr(signal, "SIG" + sys.argv[1]))
        assert process.wait(timeout=10) == {"INT": 130, "TERM": 143}[sys.argv[1]]
        assert pathlib.Path(environment["FAKE_SCANNER_CLEANED"]).read_text() == "cleaned\n"
        assert not pathlib.Path("/proc", str(scanner_pid)).exists(), "scanner remained alive"
    except Exception as error:
        raise AssertionError(pathlib.Path(sys.argv[5]).read_text(errors="replace")) from error
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        if scanner_pid is not None:
            try:
                os.killpg(scanner_pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
PY
done
savedSource="${DOCKER_BUNDLE_SOURCE_ROOT}"
DOCKER_BUNDLE_SOURCE_ROOT="${TEST_ROOT}/missing"
if dockerRealityTargetAction "${SPEC}" status >"${TEST_ROOT}/missing-source" 2>&1; then fail '来源缺失未拒绝'; fi
DOCKER_BUNDLE_SOURCE_ROOT="${savedSource}"
mkdir "${TEST_ROOT}/unsafe"
chmod 777 "${TEST_ROOT}/unsafe"
if dockerRealityTargetPathIsSafe "${TEST_ROOT}/unsafe/file"; then fail '可写祖先目录未拒绝'; fi
ln -s "${TEST_ROOT}/selection" "${TEST_ROOT}/linked"
if dockerRealityTargetPathIsSafe "${TEST_ROOT}/linked/file"; then fail '符号链接祖先未拒绝'; fi
[[ "${TRAPS_CHECK}" == "$(trap -p EXIT INT TERM)" ]] || fail 'adapter 覆盖了父 trap'
[[ "${SOURCE_CHECK}" == "$(sha256sum "${SPEC}")" ]] || fail '目标操作修改了部署规格'
[[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]] || fail 'adapter 留下临时目录'
printf 'docker Reality 目标库与原生算法对齐回归通过\n'
