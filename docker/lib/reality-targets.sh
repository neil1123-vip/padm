#!/usr/bin/env bash
# 原生回调通过动态 source 使用这些函数及状态变量。
# shellcheck disable=SC2034,SC2317

dockerRealityTargetPathIsSafe() {
    local path=$1 component current='' owner mode
    local -a components=()
    dockerPathIsSafeAbsolute "${path}" || return 1
    IFS=/ read -r -a components <<<"${path}"
    for component in "${components[@]}"; do
        [[ -n "${component}" ]] || continue
        current="${current}/${component}"
        [[ ! -L "${current}" ]] || return 1
        [[ -e "${current}" ]] || continue
        owner=$(stat -c %u -- "${current}") || return 1
        [[ "${owner}" == "$(id -u)" || "${owner}" == 0 ]] || return 1
        mode=$(stat -c %a -- "${current}") || return 1
        if (( (8#${mode} & 0022) != 0 )); then
            [[ -d "${current}" ]] && (( (8#${mode} & 01000) != 0 )) || return 1
        fi
    done
}

dockerRealityTargetCnameRecords() {
    local opsImage=$1 host=$2
    dockerRealityProbeRun 30 --entrypoint python3 "${opsImage}" -c '
import ipaddress
import re
import shutil
import subprocess
import sys

host = sys.argv[1]
try:
    ipaddress.ip_address(host)
    raise SystemExit(0)
except ValueError:
    pass
if not shutil.which("nslookup"):
    raise SystemExit("DNS CNAME probe requires nslookup")
seen = {host.lower()}
for _ in range(16):
    result = subprocess.run(["nslookup", "-type=CNAME", host], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8)
    if result.returncode:
        sys.stderr.write(result.stdout)
        raise SystemExit(result.returncode)
    aliases = re.findall(r"canonical name =\s*(\S+)", result.stdout, re.I)
    aliases = [value.rstrip(".").lower() for value in aliases]
    if not aliases:
        break
    for alias in aliases:
        if alias in seen:
            raise SystemExit("DNS alias loop")
        seen.add(alias)
        print(alias)
    host = aliases[-1]
else:
    raise SystemExit("DNS alias chain too long")
' "${host}"
}

dockerRealityTargetCertificateChain() {
    local opsImage=$1 host=$2 port=$3 sni=$4
    dockerRealityProbeRun 25 --tmpfs /tmp:rw,nosuid,nodev,size=16m --entrypoint python3 "${opsImage}" -c '
import re
import subprocess
import sys
import tempfile

host, port, sni = sys.argv[1:]
target = ("[" + host + "]" if ":" in host else host) + ":" + port
result = subprocess.run(["openssl", "s_client", "-connect", target, "-servername", sni,
    "-verify_hostname", sni, "-verify_return_error", "-showcerts"], input=b"",
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=18)
if result.returncode:
    sys.stderr.buffer.write(result.stderr)
    raise SystemExit(result.returncode)
certificates = re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
    result.stdout, re.DOTALL)
if not certificates:
    raise SystemExit("Certificate chain unavailable")
with tempfile.TemporaryDirectory() as directory:
    for index, certificate in enumerate(certificates, 1):
        path = directory + "/cert.pem"
        with open(path, "wb") as output:
            output.write(certificate)
        print("REALITY 证书链 #" + str(index), flush=True)
        subprocess.run(["openssl", "x509", "-in", path, "-noout", "-subject",
            "-issuer", "-dates", "-fingerprint", "-sha256", "-ext", "subjectAltName"],
            check=True, timeout=5)
print("证书链数量: " + str(len(certificates)) + "；叶子证书匹配 SNI=" + sni)
' "${host}" "${port}" "${sni}"
}

# 原生目标算法只在隔离子 shell 中载入，不能覆盖部署事务的 trap 或写原生配置。
dockerRealityTargetAction() (
    local specFile=$1 action=$2 root state work records row id host port sni target result
    local status=0 selectedFile='' mutation=0 libraryLock='' commitFile=''
    shift 2
    if ! dockerRealityTargetPathIsSafe "${specFile}" ||
        [[ ! -f "${specFile}" || -L "${specFile}" ]] ||
        ! dockerPrivateFileIsRestricted "${specFile}"; then
        dockerError 'REALITY 规格快照路径或权限不安全'
        return 1
    fi
    root=$(dockerInstallRoot) || return 1
    command -v timeout >/dev/null 2>&1 || { dockerError '缺少 timeout，无法限制 REALITY 探测时长'; return 1; }
    state="${root}/data/reality-targets"
    dockerRealityTargetPathIsSafe "${state}" || {
        dockerError 'REALITY 目标库路径、所有权或链接不安全'
        return 1
    }
    for commitFile in results.tsv blocked.tsv; do
        dockerRealityTargetPathIsSafe "${state}/${commitFile}" &&
            [[ ! -e "${state}/${commitFile}" || -f "${state}/${commitFile}" ]] || return 1
    done
    case "${action}" in
    status | blocked | library | select | validate) ;;
    check | refresh | block | scan-range | scan-asn) mutation=1 ;;
    *) dockerError "未知 REALITY 目标库动作: ${action}"; return 2 ;;
    esac
    if (( mutation )); then
        mkdir -p -- "${state}" || return 1
        chmod 700 -- "${state}" || return 1
        libraryLock="${state}/.lock"
        dockerRealityTargetPathIsSafe "${libraryLock}" || return 1
        exec 8>>"${libraryLock}" || return 1
        chmod 600 -- "${libraryLock}" || return 1
        command -v flock >/dev/null 2>&1 || { dockerError '缺少 flock，无法保护 REALITY 目标库'; return 1; }
        flock -w 30 8 || { dockerError 'REALITY 目标库正在被其它操作使用'; return 1; }
    fi
    umask 077
    work=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-reality.XXXXXX") || return 1
    dockerRealityTargetPathIsSafe "${work}" || { rmdir -- "${work}"; return 1; }
    trap 'status=$?; rm -rf -- "${work}"; exit "${status}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # shellcheck source=/dev/null
    source "${DOCKER_BUNDLE_SOURCE_ROOT}/shell/core/runtime.sh" || return 1
    # shellcheck source=/dev/null
    source "${DOCKER_BUNDLE_SOURCE_ROOT}/shell/core/reality_targets.sh" || return 1
    export TMPDIR="${work}"
    PADM_CLEANUP_PATHS=("${work}")
    PADM_CLEANUP_TRAP_INSTALLED=1
    trap 'padmCleanupTempPaths' EXIT
    trap 'padmCleanupTempPaths INT' INT
    trap 'padmCleanupTempPaths TERM' TERM
    unset PADM_REALITY_TARGET_CANDIDATES_FILE PADM_REALITY_TARGET_SELECTION_SCAN PADM_REALITY_TARGET_SELECTION_REQUIRE_SCAN
    unset AUTO_REALITY_SERVER_NAME AUTO_REALITY_TARGET_SELECT
    PADM_REALITY_TARGET_RESULTS_FILE="${state}/results.tsv"
    PADM_REALITY_TARGET_BLOCKED_FILE="${state}/blocked.tsv"
    if (( mutation )); then
        mkdir "${work}/library" || return 1
        for commitFile in results.tsv blocked.tsv; do
            [[ ! -f "${state}/${commitFile}" ]] || cp -p -- "${state}/${commitFile}" "${work}/library/${commitFile}" || return 1
        done
        PADM_REALITY_TARGET_RESULTS_FILE="${work}/library/results.tsv"
        PADM_REALITY_TARGET_BLOCKED_FILE="${work}/library/blocked.tsv"
    fi
    # 原生函数内部可暂用 644，发布目标库时统一恢复 Docker 私密模式。
    local targetXrayImage targetOpsImage
    targetXrayImage=$(jq -er '.images.xray' "${specFile}") || return 1
    targetOpsImage=$(jq -er '.images.ops' "${specFile}") || return 1

    dockerTargetPrintSafe() { printf '%s\n' "$*" | LC_ALL=C tr -d '\000-\010\013-\037\177'; }
    echoContent() { shift; dockerTargetPrintSafe "${*//$'\033'/}"; }
    menuLine() { dockerTargetPrintSafe "  $*"; }
    menuItem() { dockerTargetPrintSafe "  $1. $2${3:+  $3}"; }
    menuRecommendedItem() { menuItem "$@"; }
    menuReturnItem() { menuItem "$@"; }
    menuClose() { printf '\n'; }
    errorCard() { dockerError "$*"; }
    uiStyle() { printf '%s' "$2"; }
    menuReadChoice() { IFS= read -r -p "$2" "$3"; }
    autoRead() { IFS= read -r -p "$2" "$3"; }
    autoConfirm() {
        local prompt=$2 default=$3 variable=$4 answer
        IFS= read -r -p "${prompt} [y/n]: " answer || return 1
        answer=${answer:-${default}}
        printf -v "${variable}" '%s' "${answer,,}"
    }
    parseHostPort() {
        local input=$1 defaultPort=${2:-443} parsedHost=${1%:*} parsedPort=${1##*:}
        [[ "${parsedHost}" != "${input}" && -n "${parsedPort}" ]] || parsedPort=${defaultPort}
        printf '%s:%s\n' "${parsedHost}" "${parsedPort}"
    }
    validateRealityTarget() {
        padmIsValidHostName "$1" && [[ "$2" =~ ^[0-9]{1,5}$ ]] && (( 10#$2 > 0 && 10#$2 <= 65535 ))
    }
    checkLogBackupCreate() {
        local variable=$1 backup path index=0
        shift
        padmCreateTempPath backup -d || return 1
        local -a pairs=()
        for path in "$@"; do
            [[ -n "${path}" ]] || continue
            pairs+=("${index}" "${path}")
            index=$((index + 1))
        done
        padmWriteManagedFileBackupManifest "${backup}" "${pairs[@]}" || return 1
        printf -v "${variable}" '%s' "${backup}"
    }
    checkLogBackupRestore() { padmRestoreManagedFileBackupManifest "$1"; }
    realityTargetDetector() { printf '%s\n' "${targetXrayImage}"; }
    probeRealityTargetTls() { dockerRealityTargetTlsPing "$1" "$2" "$3" "$4"; }
    fetchPublicIP() { fetchUrlToStdout https://api.ipify.org 1 5; }
    dockerTargetNetworkFile() {
        local queriedHost=$1 cache recordsFile
        cache=$(printf '%s' "${queriedHost}" | sha256sum) || return 1
        recordsFile="${work}/network-${cache%% *}"
        if [[ ! -f "${recordsFile}" ]]; then
            dockerRealityTargetNetworkRecords "${targetOpsImage}" "${queriedHost}" >"${recordsFile}.stage" || return 1
            [[ -s "${recordsFile}.stage" ]] || return 1
            mv -- "${recordsFile}.stage" "${recordsFile}" || return 1
        fi
        printf '%s\n' "${recordsFile}"
    }
    dockerTargetCnameFile() {
        local queriedHost=$1 cache cnameFile
        cache=$(printf '%s' "${queriedHost}" | sha256sum) || return 1
        cnameFile="${work}/cname-${cache%% *}"
        if [[ ! -f "${cnameFile}" ]]; then
            dockerRealityTargetCnameRecords "${targetOpsImage}" "${queriedHost}" >"${cnameFile}.stage" || return 1
            mv -- "${cnameFile}.stage" "${cnameFile}" || return 1
        fi
        printf '%s\n' "${cnameFile}"
    }
    resolveRealityTargetAddresses() {
        local queriedHost=$1 recordsFile address _asn _org
        local -a addresses=()
        dockerTargetCnameFile "${queriedHost}" >/dev/null || return 1
        recordsFile=$(dockerTargetNetworkFile "${queriedHost}") || return 1
        while IFS=$'\t' read -r address _asn _org; do
            if [[ "${address}" == *:* ]]; then
                padmIsValidIPv6Address "${address}" || return 1
            else
                [[ "${address}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] &&
                    padmIsValidHostName "${address}" || return 1
            fi
            addresses+=("${address}")
        done <"${recordsFile}"
        (( ${#addresses[@]} > 0 )) || return 1
        printf '%s\n' "${addresses[@]}"
    }
    realityTargetDnsCdnProvider() {
        local queriedHost=$1 cnameFile cname provider
        cnameFile=$(dockerTargetCnameFile "${queriedHost}") || {
            # 原生扫描二检会吞 DNS 非零；明确非空风险标记才能阻止未知结果入库。
            printf 'dns_probe_unknown\n'
            return 0
        }
        while IFS= read -r cname; do
            provider=$(realityTargetCdnProviderFromCname "${cname}") || continue
            printf '%s\n' "${provider}"
            return 0
        done <"${cnameFile}"
        return 1
    }
    lookupRealityTargetAsn() {
        local address=$1 recordsFile candidateIp candidateAsn candidateOrg
        for recordsFile in "${work}"/network-*; do
            [[ -f "${recordsFile}" && "${recordsFile}" != *.stage ]] || continue
            while IFS=$'\t' read -r candidateIp candidateAsn candidateOrg; do
                [[ "${candidateIp}" == "${address}" ]] || continue
                [[ "${candidateAsn}" =~ ^AS[0-9]+$ ]] || return 1
                printf '%s\t%s\n' "${candidateAsn}" "${candidateOrg}"
                return 0
            done <"${recordsFile}"
        done
        recordsFile=$(dockerTargetNetworkFile "${address}") || return 1
        IFS=$'\t' read -r candidateIp candidateAsn candidateOrg <"${recordsFile}"
        [[ "${candidateAsn}" =~ ^AS[0-9]+$ ]] || return 1
        printf '%s\t%s\n' "${candidateAsn}" "${candidateOrg}"
    }
    # 原生安全判定保持不变，仅把 Docker 平台无法完成的 CNAME 探测映为 unknown。
    eval "$(declare -f realityTargetAddressCdnRisk |
        sed '1s/realityTargetAddressCdnRisk/dockerTargetNativeAddressCdnRisk/')"
    realityTargetAddressCdnRisk() {
        if [[ "${7:-}" == dns_probe_unknown ]]; then
            printf 'unknown\n'
            return 0
        fi
        dockerTargetNativeAddressCdnRisk "$@"
    }
    showRealityTargetCertificateChain() {
        local parsedTarget
        parsedTarget=$(parseHostPort "$1" 443) || return 1
        dockerRealityTargetCertificateChain "${targetOpsImage}" "${parsedTarget%:*}" "${parsedTarget##*:}" "${realitySNI}" |
            LC_ALL=C tr -d '\000-\010\013-\037\177'
        return "${PIPESTATUS[0]}"
    }
    runRealityScannerQuietly() {
        local outputFile=$1 scannerBin=$2 mode=$3 input=$4
        shift 4
        local scannerTimeout=${PADM_DOCKER_REALITY_SCANNER_TIMEOUT:-3600} entry scanWork status=0
        [[ "${scannerTimeout}" =~ ^[1-9][0-9]{0,5}$ ]] || scannerTimeout=3600
        [[ "${outputFile}" == "${work}/"* && "${scannerBin}" == "${work}/"* ]] || return 1
        padmCreateTempPath scanWork -d "${work}/scanner-run.XXXXXX" || return 1
        local -a arguments=()
        while (($#)); do
            entry=$1
            shift
            [[ "${entry}" != "${outputFile}" ]] || entry=/work/output.csv
            arguments+=("${entry}")
        done
        if [[ "${mode}" == -in ]]; then
            [[ "${input}" == "${work}/"* ]] || return 1
            cp -- "${input}" "${scanWork}/input" || return 1
            input=/work/input
        fi
        dockerRealityProbeRun "${scannerTimeout}" --user 0:0 --tmpfs /tmp:rw,nosuid,nodev,size=64m \
            --mount "type=bind,src=${scanWork},dst=/work" \
            --mount "type=bind,src=${scannerBin},dst=/scanner,readonly" \
            --entrypoint /scanner "${targetOpsImage}" "${mode}" "${input}" "${arguments[@]}" >"${outputFile}.log" 2>&1 || status=$?
        if [[ -f "${scanWork}/output.csv" && ! -L "${scanWork}/output.csv" ]]; then
            cp -- "${scanWork}/output.csv" "${outputFile}" || status=1
        fi
        padmRemoveCleanupPath "${scanWork}"
        return "${status}"
    }
    dockerTargetScanImport() {
        local mode=$1 input=$2 currentAsn=${3:-} currentOrg=${4:-} seenDomainsFile=${5:-}
        local scannerDir scannerBin outputFile scannerStatus=0 networkMode=lookup
        scannerDir="${work}/RealiTLScanner"
        scannerBin="${scannerDir}/RealiTLScanner"
        ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
        padmCreateTempPath outputFile "${work}/scanner-result.XXXXXX" || return 1
        runRealityScannerQuietly "${outputFile}" "${scannerBin}" "${mode}" "${input}" -thread 20 -timeout 3 -out "${outputFile}" || scannerStatus=$?
        if (( scannerStatus != 0 )); then
            dockerError "RealiTLScanner 执行失败: ${scannerStatus}"
            [[ ! -f "${outputFile}.log" ]] || cat -- "${outputFile}.log" >&2
            return "${scannerStatus}"
        fi
        [[ -s "${outputFile}" ]] || { dockerError 'RealiTLScanner 未生成有效 CSV'; return 1; }
        [[ -z "${currentAsn}" || -z "${currentOrg}" ]] || networkMode=same_asn
        importRealityScannerResults "${outputFile}" "${currentAsn}" "${currentOrg}" "" "${networkMode}" "${seenDomainsFile}"
    }
    runRealityScannerRange() { dockerTargetScanImport -addr "$1"; }
    runRealityScannerTargetFile() {
        local targetFile=$1 currentAsn=${2:-} currentOrg=${3:-}
        local seenDomainsFile batchFile total batchSize processed=0 batchCount
        padmCreateTempPath seenDomainsFile || return 1
        total=$(wc -l <"${targetFile}") || return 1
        batchSize=${total}
        (( total < 1000 )) || batchSize=1000
        (( total < 5000 )) || batchSize=2000
        while (( processed < total )); do
            padmCreateTempPath batchFile || return 1
            sed -n "$((processed + 1)),$((processed + batchSize))p" "${targetFile}" >"${batchFile}" || return 1
            batchCount=$(wc -l <"${batchFile}") || return 1
            (( batchCount > 0 )) || break
            dockerTargetScanImport -in "${batchFile}" "${currentAsn}" "${currentOrg}" "${seenDomainsFile}" || return 1
            processed=$((processed + batchCount))
            realityTargetProgressLine "RealiTLScanner 抽样扫描进度: ${processed}/${total}"
            padmRemoveCleanupPath "${batchFile}"
        done
    }
    runRealityScannerPrefixFile() {
        local prefixFile=$1 currentAsn=${2:-} currentOrg=${3:-} prefix seenDomainsFile
        padmCreateTempPath seenDomainsFile || return 1
        while IFS= read -r prefix; do
            [[ -n "${prefix}" ]] || continue
            dockerTargetScanImport -addr "${prefix}" "${currentAsn}" "${currentOrg}" "${seenDomainsFile}" || return 1
        done <"${prefixFile}"
    }
    # 扫描参数作为单独 argv 传递；保留扫描器支持的域名、IP、CIDR 和地址范围。
    dockerTargetRangeIsValid() {
        local range=$1
        [[ -n "${range}" && ${#range} -le 1024 && "${range}" != -* &&
            "${range}" != *[[:cntrl:]]* && "${range}" != *[[:space:]]* ]]
    }
    dockerTargetStatus() {
        local cached pqc mldsa core
        while IFS=$'\t' read -r id host port sni; do
            target=$(formatRealityTarget "${host}" "${port}")
            cached=$(realityTargetResultLine "${target}" 2>/dev/null || true)
            pqc=未检测
            [[ -z "${cached}" ]] || pqc="rank=$(realityTargetResultField "${cached}" 10) X25519MLKEM768=$(realityTargetResultField "${cached}" 11) TLS1.3=$(realityTargetResultField "${cached}" 13)"
            dockerTargetPrintSafe "${id}  target=${target}  SNI=${sni}"
            core=$(jq -r --arg id "${id}" '.core.protocols[] | select(.listener_id == $id) | .core' "${specFile}") || return 1
            mldsa=未配置
            if [[ "${core}" == xray && -f "${root}/config/xray/config.json" && ! -L "${root}/config/xray/config.json" ]]; then
                dockerRealityTargetPathIsSafe "${root}/config/xray/config.json" || return 1
                mldsa=$(jq -er --arg id "${id}" '[.inbounds[]? | select(.tag == $id) |
                    .streamSettings.realitySettings.mldsa65Verify // empty] |
                    if length > 0 then .[0] else "未配置" end' "${root}/config/xray/config.json") || return 1
            fi
            dockerTargetPrintSafe "  ASN: $(realityTargetCachedAsnSummary "${target}")  网络: $(realityTargetCachedNetworkSummary "${target}")  PQC: ${pqc}  ML-DSA-65: ${mldsa}"
        done <<<"${records}"
    }
    records=$(jq -er '[.core.protocols[] | select(.id == 1 or .id == 2 or .id == 26) |
        [(.listener_id // (.id | tostring)), .reality.target_host, (.reality.target_port | tostring), .reality.server_name]] |
        if length == 0 then "" else .[] | @tsv end' "${specFile}") || return 1
    case "${action}" in
    status) [[ -z "${records}" ]] || dockerTargetStatus; return 0 ;;
    blocked) showRealityTargetBlockedCandidates; return 0 ;;
    library) showRealityTargetScanResults "${1:-all}" once "${2:-1}"; return $? ;;
    select)
        selectedFile=${1:-}
        dockerRealityTargetPathIsSafe "${selectedFile}" &&
            [[ -d "$(dirname -- "${selectedFile}")" &&
                "$(stat -c %a -- "$(dirname -- "${selectedFile}")")" == 700 &&
                ! -e "${selectedFile}" && ! -L "${selectedFile}" ]] || return 1
        showRealityTargetScanResults all interactive || status=$?
        [[ "${status}" == 2 ]] || return "${status}"
        jq -n --arg host "${realityTargetHost}" --argjson port "${realityTargetPort}" --arg sni "${realitySNI}" \
            '{host:$host,port:$port,sni:$sni}' >"${selectedFile}" || return 1
        chmod 600 -- "${selectedFile}" || return 1
        return 2
        ;;
    validate | check)
        [[ -n "${records}" ]] || return 0
        local -A visited=()
        while IFS=$'\t' read -r id host port sni; do
            validateRealityTarget "${host}" "${port}" && padmIsValidHostName "${sni}" || return 1
            target=$(formatRealityTarget "${host}" "${port}")
            [[ ! -v "visited[${target}|${sni}]" ]] || continue
            visited["${target}|${sni}"]=1
            if [[ "${action}" == validate ]]; then
                if realityTargetCandidateBlocked "${host}" cdn || realityTargetCandidateBlocked "${host}" cdn_edge ||
                    realityTargetCandidateBlocked "${host}" cloudflare_relay ||
                    realityTargetCandidateBlocked "${sni}" cdn || realityTargetCandidateBlocked "${sni}" cdn_edge ||
                    realityTargetCandidateBlocked "${sni}" cloudflare_relay; then
                    dockerError "REALITY 目标命中已知 CDN 风险名单: ${host} SNI=${sni}"
                    return 1
                fi
                result=$(probeRealityTargetEndpoint "${targetXrayImage}" "${target}" "${sni}") || {
                    dockerError "REALITY 目标地址解析失败: ${target}"
                    return 1
                }
                IFS=$'\t' read -r row _ip _asn _org _score _pqc _cert _tls _note <<<"${result}"
                [[ "${row}" == no && "${_tls}" == yes && "${_score}" != FAIL ]] || {
                    dockerError "REALITY 目标风险检测不完整或不安全，已拒绝部署: ${target} (${row})"
                    return 1
                }
            else
                realityTargetHost=${host}
                realityTargetPort=${port}
                realitySNI=${sni}
                if ! showRealityTargetQuality "${target}"; then
                    local failedTarget
                    status=1
                    padmCreateTempPath failedTarget || return 1
                    printf '%s\n' "${target}" >"${failedTarget}" || return 1
                    removeRealityTargetsFromUnifiedLibrary "${failedTarget}" || return 1
                fi
                showRealityTargetCertificateChain "${target}" || status=1
            fi
        done <<<"${records}"
        [[ "${action}" != validate ]] || return 0
        commitFile=results.tsv
        ;;
    refresh)
        case "${1:-recommended}" in recommended | recommended_only | all) ;; *) return 2 ;; esac
        scanLocalAsnRealityTargets "${1:-recommended}" || return 1
        commitFile=results.tsv
        ;;
    block)
        host=${1:-}
        padmIsValidHostName "${host}" || { dockerError '黑名单目标必须为合法域名或 IPv4 地址'; return 2; }
        addRealityTargetBlockedCandidate "${host,,}" || return 1
        commitFile=blocked.tsv
        ;;
    scan-range)
        local scanRange=${1:-} confirm currentIp
        if [[ -z "${scanRange}" ]]; then
            currentIp=$(realityTargetPublicIPv4 2>/dev/null || true)
            selectRealityScannerRange "${currentIp}" || return 0
            scanRange=${selectedRealityScannerRange}
        fi
        dockerTargetRangeIsValid "${scanRange}" || { dockerError '扫描范围不能为空、包含控制符或以选项字符开头'; return 2; }
        realityTargetStatusBlock yellow 'RealiTLScanner 风险提示' "将扫描 ${scanRange}；云端扫描可能导致 VPS 被标记"
        autoConfirm reality_scanner_confirm '确认开始扫描？' n confirm || return 0
        [[ "${confirm}" == y ]] || return 0
        runRealityScannerRange "${scanRange}" || return 1
        commitFile=results.tsv
        ;;
    scan-asn)
        local requestedSize=${1:-}
        if [[ -n "${requestedSize}" ]]; then
            [[ "${requestedSize}" == all || ("${requestedSize}" =~ ^[1-9][0-9]{0,5}$ && "${requestedSize}" -le 100000) ]] || return 2
            selectRealityAsnSampleSize() {
                selectedRealityAsnFullScan=false
                [[ "${requestedSize}" != all ]] || selectedRealityAsnFullScan=true
                selectedRealityAsnSampleSize=${requestedSize}
                [[ "${requestedSize}" == all ]] || (( requestedSize <= $1 )) || selectedRealityAsnSampleSize=$1
            }
        fi
        local profile currentIp currentAsn currentOrg rest prefixFile confirm
        local selectedRealityScannerPrefixFile selectedRealityScannerRange
        local selectedRealityAsnPrefixTotal selectedRealityAsnAddressTotal selectedRealityAsnSampleSize selectedRealityAsnFullScan
        profile=$(currentRealityNetworkProfile) || { dockerError '无法识别本机公网 ASN'; return 1; }
        currentIp=${profile%%$'\t'*}
        rest=${profile#*$'\t'}
        currentAsn=${rest%%$'\t'*}
        currentOrg=${rest#*$'\t'}
        realityTargetStatusBlock yellow '同 ASN 前缀扫描' "本机公网网络: ${currentIp} ${currentAsn} ${currentOrg}"
        padmCreateTempPath prefixFile || return 1
        if ! fetchRealityAsnPrefixes "${currentAsn}" >"${prefixFile}" || [[ ! -s "${prefixFile}" ]]; then
            dockerError "未获取到 ${currentAsn} 的 IPv4 公告前缀"
            return 1
        fi
        selectRealityAsnScanPlan "${currentAsn}" "${prefixFile}" || return 0
        realityTargetStatusBlock yellow 'RealiTLScanner 风险提示' "扫描计划: ${selectedRealityScannerRange}" \
            "公告 prefix 数: ${selectedRealityAsnPrefixTotal}" "本次将扫描 IP: ${selectedRealityAsnAddressTotal}" \
            '会扫描目标网段 TLS 证书；云端扫描可能导致 VPS 被标记'
        autoConfirm reality_asn_scanner_confirm '确认开始扫描？' n confirm || return 0
        [[ "${confirm}" == y ]] || return 0
        if [[ "${selectedRealityAsnFullScan}" == true ]]; then
            runRealityScannerPrefixFile "${selectedRealityScannerPrefixFile}" "${currentAsn}" "${currentOrg}" || return 1
        else
            runRealityScannerTargetFile "${selectedRealityScannerPrefixFile}" "${currentAsn}" "${currentOrg}" || return 1
        fi
        commitFile=results.tsv
        ;;
    esac
    if [[ -n "${commitFile}" && -f "${work}/library/${commitFile}" ]]; then
        local stage
        dockerRealityTargetPathIsSafe "${state}/${commitFile}" || return 1
        stage=$(mktemp "${state}/.${commitFile}.XXXXXX") || return 1
        PADM_CLEANUP_PATHS+=("${stage}")
        cp -- "${work}/library/${commitFile}" "${stage}" && chmod 600 -- "${stage}" &&
            mv -f -- "${stage}" "${state}/${commitFile}" || return 1
    fi
    return "${status}"
)
