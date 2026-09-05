#!/usr/bin/env bash

realityTargetProgressLine() {
    local message=$1
    if [[ "${PADM_SUPPRESS_PROGRESS:-}" == "1" ]]; then
        return 0
    fi
    if declare -F printInstallProgressLine >/dev/null 2>&1; then
        printInstallProgressLine "${message}"
    else
        printf '\r\033[K%s\n' "${message}"
    fi
}

realityTargetStatusBlock() {
    local color=$1
    local title=$2
    shift 2
    echoContent "${color}" "\n┌─ ${title} ─────────────────────────────────────────"
    local line
    for line in "$@"; do
        if declare -F menuLine >/dev/null 2>&1; then
            menuLine "${line}"
        else
            echoContent "${color}" "│ ${line}"
        fi
    done
    if declare -F menuClose >/dev/null 2>&1; then
        menuClose
    else
        echoContent "${color}" "└──────────────────────────────────────────────────"
    fi
}

realityTargetTmpPath() {
    local template=$1
    padmTmpFilePath "${template}"
}

realityScannerOutputPath() {
    local stamp=$1
    local suffix=${2:-}
    if [[ -n "${suffix}" ]]; then
        realityTargetTmpPath "padm-realitlscanner-${stamp}-${suffix}.csv"
    else
        realityTargetTmpPath "padm-realitlscanner-${stamp}.csv"
    fi
}

realityTargetScoreStyle() {
    case $1 in
    A) uiStyle ok A ;;
    B) uiStyle title B ;;
    C) uiStyle warn C ;;
    FAIL) uiStyle danger FAIL ;;
    *) uiStyle muted "$1" ;;
    esac
}

realityTargetCandidatePool() {
    local candidatesFile
    candidatesFile=$(realityTargetManagedCandidatesFile 2>/dev/null || true)
    if [[ -n "${candidatesFile}" && -f "${candidatesFile}" ]]; then
        cat "${candidatesFile}"
        return 0
    fi
    cat <<'EOF'
www.gnu.org|www.gnu.org|GNU|global|developer|unknown|52|yes|远端复测确认直连，作为普通 Reality 默认候选
www.debian.org|www.debian.org|Debian|global|developer|unknown|51|yes|远端复测确认直连，作为普通 Reality 默认候选
www.ubuntu.com|www.ubuntu.com|Ubuntu|global|developer|unknown|50|yes|远端复测确认直连，作为普通 Reality 默认候选
www.dropbox.com|www.dropbox.com|Dropbox|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.slack.com|www.slack.com|Slack|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
grafana.com|grafana.com|Grafana|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
elastic.co|elastic.co|Elastic|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.postgresql.org|www.postgresql.org|PostgreSQL|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
mariadb.org|mariadb.org|MariaDB|global|developer|unknown|39|yes|远端复测确认直连，作为普通 Reality 默认候选
www.nginx.com|www.nginx.com|NGINX|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
nginx.org|nginx.org|NGINX Open Source|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
httpd.apache.org|httpd.apache.org|Apache HTTP Server|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.apache.org|www.apache.org|Apache|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
maven.apache.org|maven.apache.org|Apache Maven|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
cmake.org|cmake.org|CMake|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
llvm.org|llvm.org|LLVM|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
clang.llvm.org|clang.llvm.org|Clang|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
gcc.gnu.org|gcc.gnu.org|GCC|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.eclipse.org|www.eclipse.org|Eclipse|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
developer.android.com|developer.android.com|Android Developers|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
android.com|android.com|Android|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.chromium.org|www.chromium.org|Chromium|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.openjdk.org|www.openjdk.org|OpenJDK|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
docs.rs|docs.rs|Docs.rs|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
pypi.org|pypi.org|PyPI|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
deno.com|deno.com|Deno|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
angular.dev|angular.dev|Angular|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
fly.io|fly.io|Fly.io|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.ovhcloud.com|www.ovhcloud.com|OVHcloud|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.hetzner.com|www.hetzner.com|Hetzner|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
cloud.google.com|cloud.google.com|Google Cloud|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.alibabacloud.com|www.alibabacloud.com|Alibaba Cloud|asia|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cloudflarestatus.com|www.cloudflarestatus.com|Cloudflare Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
status.cloud.google.com|status.cloud.google.com|Google Cloud Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
azure.status.microsoft|azure.status.microsoft|Azure Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.stripe.com|www.stripe.com|Stripe|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.netflix.com|www.netflix.com|Netflix|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
EOF
}

realityTargetManagedBlockedCandidatesFile() {
    padmResolveManagedAbsolutePath "${PADM_REALITY_TARGET_BLOCKED_FILE:-/etc/padm/reality_target_blocked.tsv}"
}

realityTargetManagedResultsFile() {
    padmResolveManagedAbsolutePath "${PADM_REALITY_TARGET_RESULTS_FILE:-/etc/padm/reality_targets_results.tsv}"
}

realityTargetManagedCandidatesFile() {
    local candidatesFile=${PADM_REALITY_TARGET_CANDIDATES_FILE:-}
    [[ -n "${candidatesFile}" ]] || return 1
    padmResolveManagedAbsolutePath "${candidatesFile}"
}

realityTargetBuiltInCdnBlockedCandidates() {
    # Full built-in candidate audit: DNS CNAME/ASN and HTTPS edge evidence.
    cat <<'EOF'
www.ibm.com
www.microsoft.com
www.reuters.com
www.qualcomm.com
www.vmware.com
www.atlassian.com
www.jetbrains.com
www.mongodb.com
www.asus.com
www.bbc.com
www.nationalgeographic.com
tensorflow.org
www.oracle.com
go.dev
www.samsung.com
www.nvidia.com
www.amd.com
www.python.org
react.dev
vuejs.org
www.cisco.com
www.mozilla.org
developer.mozilla.org
www.kernel.org
git-scm.com
www.vultr.com
www.linode.com
www.spotify.com
www.twitch.tv
www.wikipedia.org
www.wikimedia.org
addons.mozilla.org
dl.google.com
rust-lang.org
www.ruby-lang.org
www.perl.org
www.springer.com
www.nytimes.com
www.theguardian.com
www.sony.com
www.hp.com
www.redhat.com
www.dell.com
www.intel.com
www.lenovo.com
www.amazon.com
m.media-amazon.com
www.swift.com
www.sap.com
www.salesforce.com
www.adobe.com
www.autodesk.com
www.servicenow.com
www.workday.com
www.box.com
www.okta.com
www.zoom.com
www.docusign.com
www.paypal.com
www.visa.com
www.mastercard.com
www.americanexpress.com
www.hsbc.com
www.citi.com
www.jpmorgan.com
www.goldmansachs.com
www.nasdaq.com
www.londonstockexchange.com
www.bloomberg.com
www.ft.com
www.wsj.com
www.economist.com
www.apnews.com
www.npr.org
www.pbs.org
www.cnn.com
www.cnbc.com
www.forbes.com
www.wired.com
www.theverge.com
www.engadget.com
www.arstechnica.com
www.stackoverflow.com
stackexchange.com
superuser.com
serverfault.com
github.com
docs.github.com
about.gitlab.com
bitbucket.org
code.visualstudio.com
marketplace.visualstudio.com
www.docker.com
hub.docker.com
kubernetes.io
helm.sh
prometheus.io
www.mysql.com
redis.io
gradle.org
www.qt.io
www.djangoproject.com
flask.palletsprojects.com
fastapi.tiangolo.com
laravel.com
symfony.com
rubyonrails.org
dotnet.microsoft.com
learn.microsoft.com
jdk.java.net
crates.io
npmjs.com
yarnpkg.com
pnpm.io
bun.sh
typescriptlang.org
webpack.js.org
vitejs.dev
svelte.dev
nuxt.com
nextjs.org
vercel.com
netlify.com
www.heroku.com
render.com
railway.app
www.digitalocean.com
www.scaleway.com
www.oraclecloud.com
aws.amazon.com
azure.microsoft.com
www.tencentcloud.com
www.uptime.com
www.pingdom.com
www.cloudflareblog.com
www.shopify.com
squareup.com
www.ebay.com
www.etsy.com
www.airbnb.com
www.booking.com
www.expedia.com
www.tripadvisor.com
www.uber.com
www.lyft.com
soundcloud.com
vimeo.com
www.hulu.com
www.disneyplus.com
www.imdb.com
www.rottentomatoes.com
www.metmuseum.org
www.britannica.com
www.coursera.org
EOF
}

realityTargetRestoreManagedBackup() {
    local backupDir=$1
    if ! checkLogBackupRestore "${backupDir}"; then
        padmForgetCleanupPath "${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
}

realityTargetBlockedCandidates() {
    cat <<'EOF'
www.apple.com|Apple|xray_warn|Xray 会提示 Apple/iCloud 类目标可能带来封锁风险
www.google-analytics.com|Google Analytics|policy_variance|部分地区可达性和策略差异较大
www.cloudflare.com|Cloudflare|cdn|CDN 目标可能带来转发滥用风险
www.fastly.com|Fastly|cdn|CDN 目标可能带来转发滥用风险
www.akamai.com|Akamai|cdn|CDN 目标可能带来转发滥用风险
cloudflare.com|Cloudflare Root|cdn|CDN 目标可能带来转发滥用风险
java.com|Java|cloudflare_relay|已知 Cloudflare 回源中继风险，禁止作为 Reality 目标
nodejs.org|Node.js|cloudflare_relay|已确认由 Cloudflare CDN 承载，禁止作为 Reality 目标
riotcdn.net|Riot CDN|cloudflare_relay|已知 CDN 回源中继风险，禁止作为 Reality 目标
EOF
    while IFS= read -r blocked; do
        [[ -n "${blocked}" ]] || continue
        printf '%s|内置 CDN/边缘代理|cdn_edge|全量候选复测确认存在 CDN 或边缘平台代理证据\n' "${blocked}"
    done < <(realityTargetBuiltInCdnBlockedCandidates)
    local customBlockedFile
    customBlockedFile=$(realityTargetManagedBlockedCandidatesFile 2>/dev/null || true)
    [[ -f "${customBlockedFile}" ]] && cat "${customBlockedFile}"
    return 0
}

addRealityTargetBlockedCandidate() {
    local target=$1
    local reason=${2:-manual}
    local parsed host blockedFile stagedFile
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    [[ -n "${host}" ]] || return 1
    blockedFile=$(realityTargetManagedBlockedCandidatesFile) || return 1
    if realityTargetCandidateBlocked "${host}"; then
        realityTargetStatusBlock yellow "REALITY 目标站黑名单" "已在黑名单中: ${host}"
        return 0
    fi
    padmEnsureSafeDirectory "$(dirname -- "${blockedFile}")" || return 1
    padmCreateTempFileForTarget stagedFile "${blockedFile}" reality || return 1
    if [[ -f "${blockedFile}" ]]; then
        cp -p "${blockedFile}" "${stagedFile}" || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
    fi
    printf '%s|%s|%s|%s\n' "${host}" "手动加入" "${reason}" "用户手动加入；后续不参与目标库刷新和扫描导入" >>"${stagedFile}" || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
    commitGeneratedFile "${stagedFile}" "${blockedFile}" 644 || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
    realityTargetStatusBlock green "REALITY 目标站黑名单" "已加入: ${host}" "后续不参与目标库刷新和 RealiTLScanner 导入" "当前已安装目标不会自动切换"
}

realityTargetBlockedHostMatches() {
    local host=${1,,}
    local blocked=${2,,}
    local normalizedBlocked=${blocked#www.}
    [[ -n "${blocked}" && ("${host}" == "${blocked}" || "${host}" == "${normalizedBlocked}" || "${host}" == *."${normalizedBlocked}" || "${host}" == *."${blocked}") ]]
}

realityTargetCandidateBlocked() {
    local host=$1 requiredType=${2:-}
    local blocked _name blockType _description
    requiredType=${requiredType,,}
    while IFS='|' read -r blocked _name blockType _description; do
        blockType=${blockType,,}
        [[ -z "${requiredType}" || "${blockType}" == "${requiredType}" ]] || continue
        realityTargetBlockedHostMatches "${host}" "${blocked}" && return 0
    done < <(realityTargetBlockedCandidates)
    return 1
}

realityTargetCandidates() {
    local line host _sni _name _region _category cdn _rest blocked skip
    local blockedHosts=()
    while IFS='|' read -r blocked _rest; do
        blockedHosts+=("${blocked}")
    done < <(realityTargetBlockedCandidates)
    while IFS= read -r line; do
        IFS='|' read -r host _sni _name _region _category cdn _rest <<<"${line}"
        [[ "${cdn,,}" == "yes" ]] && continue
        skip=false
        for blocked in "${blockedHosts[@]}"; do
            if realityTargetBlockedHostMatches "${host}" "${blocked}"; then
                skip=true
                break
            fi
        done
        [[ "${skip}" == "true" ]] && continue
        printf '%s\n' "${line}"
    done < <(realityTargetCandidatePool)
}

realityTargetScannerRecordAllowed() {
    local domain=$1
    local lowerDomain
    [[ -n "${domain}" ]] || return 1
    [[ "${domain}" == "CERT_DOMAIN" ]] && return 1
    [[ "${domain}" == *"/"* ]] && return 1
    [[ "${domain}" == \** ]] && return 1
    lowerDomain=$(printf '%s' "${domain}" | tr '[:upper:]' '[:lower:]')
    [[ "${lowerDomain}" == "localhost" ]] && return 1
    [[ "${lowerDomain}" == "invalid.invalid" ]] && return 1
    [[ "${lowerDomain}" == "common name" ]] && return 1
    [[ "${lowerDomain}" == "cloudflare" ]] && return 1
    [[ "${lowerDomain}" == "cloudflare origin certificate" ]] && return 1
    [[ "${lowerDomain}" == "lucky" ]] && return 1
    [[ "${lowerDomain}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && return 1
    [[ "${lowerDomain}" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]] || return 1
    realityTargetCandidateBlocked "${domain}" && return 1
    return 0
}

showRealityTargetBlockedCandidates() {
    local line index=1 host name reason note
    echoContent title "\n┌─ REALITY 目标站黑名单 ─────────────────────────────"
    while IFS= read -r line; do
        host=$(printf '%s\n' "${line}" | awk -F'|' '{print $1}')
        name=$(printf '%s\n' "${line}" | awk -F'|' '{print $2}')
        reason=$(printf '%s\n' "${line}" | awk -F'|' '{print $3}')
        note=$(printf '%s\n' "${line}" | awk -F'|' '{print $4}')
        menuItem "${index}" "${host}" "${name} reason=${reason}"
        menuLine "    ${note}"
        index=$((index + 1))
    done < <(realityTargetBlockedCandidates)
    menuClose
}

realityTargetResultCount() {
    local line count=0
    while IFS= read -r line; do
        count=$((count + 1))
    done < <(sortedRealityTargetResults A)
    printf '%s\n' "${count}"
}

realityTargetResultField() {
    local line=$1
    local field=$2
    local value
    IFS=$'\t' read -r _f1 _f2 _f3 _f4 _f5 _f6 _f7 _f8 _f9 _f10 _f11 _f12 _f13 _f14 _f15 <<<"${line}"
    case "${field}" in
    1) value=${_f1} ;;
    2) value=${_f2} ;;
    3) value=${_f3} ;;
    4) value=${_f4} ;;
    5) value=${_f5} ;;
    6) value=${_f6} ;;
    7) value=${_f7} ;;
    8) value=${_f8} ;;
    9) value=${_f9} ;;
    10) value=${_f10} ;;
    11) value=${_f11} ;;
    12) value=${_f12} ;;
    13) value=${_f13} ;;
    14) value=${_f14} ;;
    15) value=${_f15} ;;
    *) value= ;;
    esac
    printf '%s\n' "${value}"
}

realityTargetResultLine() {
    local target=$1
    local resultsFile
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    [[ -n "${target}" && -f "${resultsFile}" ]] || return 1
    awk -F'\t' -v target="${target}" '$1 == target {line = $0; keep = ($5 == "no" && $10 == "A")} END {if (keep) print line; else exit 1}' "${resultsFile}"
}

realityTargetCachedAsnSummary() {
    local target=$1
    local line ip asn asOrg summary=
    line=$(realityTargetResultLine "${target}" 2>/dev/null || true)
    [[ -n "${line}" ]] || { printf '暂无缓存\n'; return 0; }
    ip=$(realityTargetResultField "${line}" 6)
    asn=$(realityTargetResultField "${line}" 7)
    asOrg=$(realityTargetResultField "${line}" 8)
    [[ -z "${ip}" || "${ip}" == "unknown" ]] || summary=${ip}
    [[ -z "${asn}" || "${asn}" == "unknown" ]] || summary="${summary:+${summary} }${asn}"
    [[ -z "${asOrg}" || "${asOrg}" == "unknown" ]] || summary="${summary:+${summary} }${asOrg}"
    printf '%s\n' "${summary:-暂无缓存}"
}

realityTargetCachedNetworkSummary() {
    local target=$1
    local line networkMatch
    line=$(realityTargetResultLine "${target}" 2>/dev/null || true)
    [[ -n "${line}" ]] || { printf '暂无缓存\n'; return 0; }
    networkMatch=$(realityTargetResultField "${line}" 9)
    case "${networkMatch}" in
    same_asn) printf '同 ASN\n' ;;
    same_provider) printf '同提供商\n' ;;
    different_network) printf '不同网络\n' ;;
    *) printf '暂无缓存\n' ;;
    esac
}

removeRealityTargetFromUnifiedLibrary() {
    local target=$1
    local targetsFile
    padmCreateTempPath targetsFile "$(realityTargetTmpPath 'padm-reality-target-remove.XXXXXX')" || return 1
    printf '%s\n' "${target}" >"${targetsFile}" || { padmRemoveCleanupPath "${targetsFile}"; return 1; }
    removeRealityTargetsFromUnifiedLibrary "${targetsFile}"
    local status=$?
    padmRemoveCleanupPath "${targetsFile}"
    return "${status}"
}

formatRealityTargetResultLine() {
    local target=$1
    local sni=$2
    local name=$3
    local category=$4
    local cdnRisk=$5
    local ip=$6
    local asn=$7
    local asOrg=$8
    local networkMatch=$9
    local score=${10}
    local pqc=${11}
    local certLength=${12}
    local tls13=${13}
    local checkedAt=${14}
    local note=${15}
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}"
}

writeRealityTargetResultLine() {
    local linesFile status
    padmCreateTempPath linesFile "$(realityTargetTmpPath 'padm-reality-target-result.XXXXXX')" || return 1
    formatRealityTargetResultLine "$@" >"${linesFile}" || { padmRemoveCleanupPath "${linesFile}"; return 1; }
    writeRealityTargetResultLines "${linesFile}"
    status=$?
    padmRemoveCleanupPath "${linesFile}"
    return "${status}"
}

writeRealityTargetResultLines() {
    local linesFile=$1
    local resultsFile mergedFile stagedFile line target parsed host
    local -a sourceFiles=()
    [[ -f "${linesFile}" ]] || return 0
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    [[ -f "${resultsFile}" ]] && sourceFiles+=("${resultsFile}")
    [[ -s "${linesFile}" ]] && sourceFiles+=("${linesFile}")
    ((${#sourceFiles[@]} > 0)) || return 0
    padmEnsureSafeDirectory "$(dirname -- "${resultsFile}")" || return 1
    padmCreateTempFileForTarget mergedFile "${resultsFile}" reality-merge || return 1
    padmCreateTempFileForTarget stagedFile "${resultsFile}" reality || { padmRemoveCleanupPath "${mergedFile}"; return 1; }
    awk -F'\t' '
      {
        if (!($1 in seen)) order[++count] = $1
        seen[$1] = 1
        line[$1] = $0
        keep[$1] = ($5 == "no" && $10 == "A")
      }
      END {
        for (i = 1; i <= count; i++) {
          target = order[i]
          if (keep[target]) print line[target]
        }
      }
    ' "${sourceFiles[@]}" >"${mergedFile}" || { padmRemoveCleanupPath "${mergedFile}"; padmRemoveCleanupPath "${stagedFile}"; return 1; }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        target=${line%%$'\t'*}
        parsed=$(parseHostPort "${target}" 443)
        host=${parsed%:*}
        realityTargetCandidateBlocked "${host}" && continue
        printf '%s\n' "${line}" >>"${stagedFile}" || { padmRemoveCleanupPath "${mergedFile}"; padmRemoveCleanupPath "${stagedFile}"; return 1; }
    done <"${mergedFile}"
    padmRemoveCleanupPath "${mergedFile}"
    commitGeneratedFile "${stagedFile}" "${resultsFile}" 644 || { padmRemoveCleanupPath "${stagedFile}"; return 1; }
}

realityTargetRefreshRecords() {
    local scope=${1:-recommended}
    local resultsFile line target parsed host port candidateKey sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note
    local -A seenTargets=()
    case "${scope}" in
    recommended | all) ;;
    *) return 1 ;;
    esac
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    if [[ "${scope}" != "all" && -s "${resultsFile}" ]]; then
        while IFS= read -r line; do
            IFS=$'\t' read -r target sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note <<<"${line}"
            [[ -n "${target}" ]] || continue
            parsed=$(parseHostPort "${target}" 443)
            host=${parsed%:*}
            host=${host,,}
            port=${parsed##*:}
            seenTargets["$(formatRealityTarget "${host}" "${port}")"]=1
            [[ "${cdnRisk}" == "no" && "${score}" == "A" ]] || continue
            realityTargetCandidateBlocked "${host}" && continue
            printf '%s\n' "${line}"
        done <"${resultsFile}"
    fi
    while IFS='|' read -r candidateHost sni name _region category cdnRisk _rank _recommended note; do
        [[ "${scope}" == "all" || "${_recommended}" == "yes" ]] || continue
        target=$(formatRealityTarget "${candidateHost}" 443)
        candidateKey=$(formatRealityTarget "${candidateHost,,}" 443)
        [[ -v "seenTargets[${candidateKey}]" ]] && continue
        formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "unknown" "unknown" "unknown" "unknown" "unknown" "unknown" "unknown" "unknown" "0" "内置候选首次检测: ${note}"
    done < <(realityTargetCandidates)
}

removeRealityTargetsFromUnifiedLibrary() {
    local targetsFile=$1
    local resultsFile candidatesFile resultsStageFile candidatesStageFile hostsFile normalizationFile target parsed host libraryBackupDir=
    [[ -s "${targetsFile}" ]] || return 0
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    candidatesFile=$(realityTargetManagedCandidatesFile 2>/dev/null || true)
    checkLogBackupCreate libraryBackupDir "${resultsFile}" "${candidatesFile}" || return 1
    if [[ -f "${resultsFile}" ]]; then
        if ! padmCreateTempPath normalizationFile; then
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || true
            return 1
        fi
        if ! writeRealityTargetResultLines "${normalizationFile}"; then
            padmRemoveCleanupPath "${normalizationFile}"
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
            return 1
        fi
        padmRemoveCleanupPath "${normalizationFile}"
    fi
    if [[ -f "${resultsFile}" ]]; then
        padmCreateTempFileForTarget resultsStageFile "${resultsFile}" reality || {
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || true
            return 1
        }
        awk -F'\t' 'NR == FNR {targets[$1] = 1; next} !($1 in targets)' "${targetsFile}" "${resultsFile}" >"${resultsStageFile}" || {
            padmRemoveCleanupPath "${resultsStageFile}"
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || true
            return 1
        }
        commitGeneratedFile "${resultsStageFile}" "${resultsFile}" 644 || {
            padmRemoveCleanupPath "${resultsStageFile}"
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || true
            return 1
        }
    fi
    [[ -n "${candidatesFile}" && -f "${candidatesFile}" ]] || { padmRemoveCleanupPath "${libraryBackupDir}"; return 0; }
    padmCreateTempPath hostsFile "$(realityTargetTmpPath 'padm-reality-target-hosts.XXXXXX')" || {
        realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
        return 1
    }
    : >"${hostsFile}" || {
        padmRemoveCleanupPath "${hostsFile}"
        realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
        return 1
    }
    while IFS= read -r target; do
        [[ -n "${target}" ]] || continue
        parsed=$(parseHostPort "${target}" 443)
        host=${parsed%:*}
        printf '%s\n' "${host}" >>"${hostsFile}" || {
            padmRemoveCleanupPath "${hostsFile}"
            realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
            return 1
        }
    done <"${targetsFile}"
    padmCreateTempFileForTarget candidatesStageFile "${candidatesFile}" reality || {
        padmRemoveCleanupPath "${hostsFile}"
        realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
        return 1
    }
    awk -F'|' 'NR == FNR {hosts[$1] = 1; next} !($1 in hosts)' "${hostsFile}" "${candidatesFile}" >"${candidatesStageFile}" || {
        padmRemoveCleanupPath "${candidatesStageFile}"
        padmRemoveCleanupPath "${hostsFile}"
        realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
        return 1
    }
    if ! commitGeneratedFile "${candidatesStageFile}" "${candidatesFile}" 644; then
        padmRemoveCleanupPath "${candidatesStageFile}"
        padmRemoveCleanupPath "${hostsFile}"
        realityTargetRestoreManagedBackup "${libraryBackupDir}" || return 1
        return 1
    fi
    padmRemoveCleanupPath "${hostsFile}"
    padmRemoveCleanupPath "${libraryBackupDir}"
}

sortedRealityTargetResults() {
    local score=${1:-A}
    local resultsFile
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    [[ -f "${resultsFile}" ]] || return 1
    awk -F'\t' -v score="${score}" '
      function blockedHost(host, i, blocked, normalized, suffix) {
        host = tolower(host)
        for (i = 1; i <= blockedCount; i++) {
          blocked = blockedHosts[i]
          normalized = blocked
          sub(/^www\./, "", normalized)
          if (host == blocked || host == normalized) return 1
          suffix = "." normalized
          if (length(host) > length(suffix) && substr(host, length(host) - length(suffix) + 1) == suffix) return 1
          suffix = "." blocked
          if (length(host) > length(suffix) && substr(host, length(host) - length(suffix) + 1) == suffix) return 1
        }
        return 0
      }
      FILENAME == ARGV[1] {
        split($0, parts, "[|]")
        if (parts[1] != "") blockedHosts[++blockedCount] = tolower(parts[1])
        next
      }
      {
        target = $1
        sub(/:[^:]*$/, "", target)
        if ($5 == "no" && $10 == score && !blockedHost(target)) {
          networkRank = ($9 == "same_asn" ? 4 : ($9 == "same_provider" ? 3 : ($9 == "different_network" ? 2 : 1)))
          certRank = ($12 ~ /^[0-9]+$/ ? $12 : 0)
          checked = ($14 ~ /^[0-9]+$/ ? $14 : 0)
          printf "%d\t%d\t%d\t%s\n", networkRank, certRank, checked, $0
        }
      }
    ' <(realityTargetBlockedCandidates) "${resultsFile}" | sort -t $'\t' -k1,1nr -k2,2nr -k3,3nr | cut -f4-
}

bestScannedRealityTargetLine() {
    local score=${1:-A}
    sortedRealityTargetResults "${score}" | awk 'NR == 1 {line = $0} END {if (line != "") print line; else exit 1}'
}

selectScannedRealityTarget() {
    local score=${1:-A}
    local line target sni parsed
    line=$(bestScannedRealityTargetLine "${score}") || return 1
    target=$(realityTargetResultField "${line}" 1)
    sni=$(realityTargetResultField "${line}" 2)
    parsed=$(parseHostPort "${target}" 443)
    realityTargetHost=${parsed%:*}
    realityTargetPort=${parsed##*:}
    realitySNI=${AUTO_REALITY_SERVER_NAME:-${sni:-${realityTargetHost}}}
}

resolveRealityTargetAddresses() {
    local host=$1
    local resolved='' aResponse='' aaaaResponse='' resolverOutput=''
    if [[ "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || ( "${host}" == *:* && "${host}" =~ ^[0-9A-Fa-f:]+$ ) ]]; then
        printf '%s\n' "${host}"
        return 0
    fi
    if command -v dig >/dev/null 2>&1; then
        aResponse=$(dig +time=3 +tries=1 +noall +comments +answer A "${host}" 2>/dev/null) || return 1
        aaaaResponse=$(dig +time=3 +tries=1 +noall +comments +answer AAAA "${host}" 2>/dev/null) || return 1
        resolverOutput="${aResponse}"$'\n'"${aaaaResponse}"
        [[ "$(printf '%s\n' "${resolverOutput}" | grep -c 'status: NOERROR')" == "2" ]] || return 1
        resolved=$(printf '%s\n' "${resolverOutput}" |
            awk '$4 == "A" || $4 == "AAAA" {if (!seen[$5]++) print $5}')
    fi
    if [[ -z "${resolved}" ]] && command -v getent >/dev/null 2>&1; then
        resolverOutput=$(getent ahosts "${host}" 2>/dev/null || true)
        resolved=$(printf '%s\n' "${resolverOutput}" |
            awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || $1 ~ /^[0-9A-Fa-f:]+$/ {if (!seen[$1]++) print $1}')
    fi
    if [[ -z "${resolved}" ]] && command -v host >/dev/null 2>&1; then
        resolved=$(host "${host}" | awk '/has address/ || /has IPv6 address/ {if (!seen[$NF]++) print $NF}')
    fi
    [[ -n "${resolved}" ]] || return 1
    printf '%s\n' "${resolved}"
}

resolveRealityTargetIPv4() {
    resolveRealityTargetAddresses "$1" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print; exit}'
}

normalizeAsnOrg() {
    local value=$1
    printf '%s\n' "${value}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g'
}

lookupRealityTargetAsn() {
    local ip=$1
    local response asn org
    response=$(fetchUrlToStdout "https://api.bgpview.io/ip/${ip}" 1 5 2>/dev/null || true)
    if [[ -n "${response}" ]] && command -v jq >/dev/null 2>&1; then
        asn=$(printf '%s\n' "${response}" | jq -r '.data.prefixes[0].asn.asn // empty' 2>/dev/null)
        org=$(printf '%s\n' "${response}" | jq -r '.data.prefixes[0].asn.name // empty' 2>/dev/null)
        if [[ -n "${asn}" ]]; then
            printf '%s\t%s\n' "AS${asn}" "$(normalizeAsnOrg "${org}")"
            return 0
        fi
    fi
    response=$(fetchUrlToStdout "https://ipinfo.io/${ip}/org" 1 5 2>/dev/null || true)
    if [[ "${response}" =~ ^AS[0-9]+ ]]; then
        asn=$(printf '%s\n' "${response}" | awk '{print $1}')
        org=$(printf '%s\n' "${response}" | cut -d' ' -f2-)
        printf '%s\t%s\n' "${asn}" "$(normalizeAsnOrg "${org}")"
        return 0
    fi
    response=$(fetchUrlToStdout "https://stat.ripe.net/data/prefix-overview/data.json?resource=${ip}" 1 5 2>/dev/null || true)
    if [[ -n "${response}" ]] && command -v jq >/dev/null 2>&1; then
        asn=$(printf '%s\n' "${response}" | jq -r '.data.asns[0].asn // empty' 2>/dev/null)
        org=$(printf '%s\n' "${response}" | jq -r '.data.asns[0].holder // empty' 2>/dev/null)
        if [[ "${asn}" =~ ^[0-9]+$ ]]; then
            printf 'AS%s\t%s\n' "${asn}" "$(normalizeAsnOrg "${org}")"
            return 0
        fi
    fi
    return 1
}

realityTargetAsnCacheLookup() {
    local ip=$1
    local cacheFile=$2
    local origin=${3:-}
    local cacheKey cacheAsn cacheOrg cachedOrigin='' cachedIpUnknown=false
    [[ -f "${cacheFile}" ]] || return 1
    while IFS=$'\t' read -r cacheKey cacheAsn cacheOrg; do
        if [[ "${cacheKey}" == "ip:${ip}" ]]; then
            if [[ "${cacheAsn}" == "unknown" ]]; then
                cachedIpUnknown=true
                continue
            fi
            [[ "${cacheAsn}" =~ ^AS[0-9]+$ ]] || continue
            printf '%s\t%s\n' "${cacheAsn}" "${cacheOrg}"
            return 0
        fi
        if [[ -n "${origin}" && "${cacheKey}" == "origin:${origin}" ]]; then
            if [[ "${cacheAsn}" == "unknown" || "${cacheAsn}" =~ ^AS[0-9]+$ ]]; then
                cachedOrigin="${cacheAsn}"$'\t'"${cacheOrg}"
            fi
        fi
    done <"${cacheFile}"
    if [[ -n "${cachedOrigin}" && "${cachedOrigin}" != unknown$'\t'* ]]; then
        printf '%s\n' "${cachedOrigin}"
        return 0
    fi
    [[ "${cachedIpUnknown}" == "true" || -n "${cachedOrigin}" ]] && return 2
    return 1
}

lookupRealityTargetAsnAndCache() {
    local ip=$1
    local cacheFile=${2:-}
    local origin=${3:-}
    local profile asn org
    if ! profile=$(lookupRealityTargetAsn "${ip}"); then
        if [[ -n "${cacheFile}" ]]; then
            if [[ "${origin}" == */* ]]; then
                printf 'ip:%s\tunknown\tunknown\norigin:%s\tunknown\tunknown\n' "${ip}" "${origin}" >>"${cacheFile}" 2>/dev/null || true
            else
                printf 'ip:%s\tunknown\tunknown\n' "${ip}" >>"${cacheFile}" 2>/dev/null || true
            fi
        fi
        return 1
    fi
    if [[ -n "${cacheFile}" ]]; then
        asn=${profile%%$'\t'*}
        org=${profile#*$'\t'}
        if [[ "${asn}" =~ ^AS[0-9]+$ ]]; then
            if [[ "${origin}" == */* ]]; then
                printf 'ip:%s\t%s\t%s\norigin:%s\t%s\t%s\n' \
                    "${ip}" "${asn}" "${org}" "${origin}" "${asn}" "${org}" >>"${cacheFile}" 2>/dev/null || true
            else
                printf 'ip:%s\t%s\t%s\n' "${ip}" "${asn}" "${org}" >>"${cacheFile}" 2>/dev/null || true
            fi
        fi
    fi
    printf '%s\n' "${profile}"
}

lookupRealityTargetAsnCached() {
    local ip=$1
    local cacheFile=${2:-}
    local origin=${3:-}
    local profile cacheStatus lockToken lockFile status
    if profile=$(realityTargetAsnCacheLookup "${ip}" "${cacheFile}" "${origin}"); then
        printf '%s\n' "${profile}"
        return 0
    else
        cacheStatus=$?
        [[ "${cacheStatus}" == "2" ]] && return 1
    fi
    if [[ -n "${cacheFile}" ]] && command -v flock >/dev/null 2>&1; then
        lockToken=${origin:-ip:${ip}}
        lockToken=${lockToken//[^[:alnum:]._-]/_}
        lockFile="${cacheFile}.${lockToken}.lock"
        if (
            if ! { exec 9>>"${lockFile}"; } 2>/dev/null; then
                exit 74
            fi
            flock -w 15 9 || exit 75
            if profile=$(realityTargetAsnCacheLookup "${ip}" "${cacheFile}" "${origin}"); then
                printf '%s\n' "${profile}"
                exit 0
            else
                cacheStatus=$?
                case "${cacheStatus}" in
                2) exit 1 ;;
                esac
            fi
            lookupRealityTargetAsnAndCache "${ip}" "${cacheFile}" "${origin}"
        ); then
            return 0
        else
            status=$?
            case "${status}" in
            74 | 75) ;;
            *) return "${status}" ;;
            esac
        fi
    fi
    lookupRealityTargetAsnAndCache "${ip}" "${cacheFile}" "${origin}"
}

realityTargetPublicIPv4() {
    local currentIp endpoint
    currentIp=$(fetchPublicIP 4 2>/dev/null || true)
    if [[ "${currentIp}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && padmIsValidHostName "${currentIp}"; then
        printf '%s\n' "${currentIp}"
        return 0
    fi
    for endpoint in https://api.ipify.org https://ipinfo.io/ip; do
        currentIp=$(fetchUrlToStdout "${endpoint}" 1 5 2>/dev/null || true)
        if [[ "${currentIp}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && padmIsValidHostName "${currentIp}"; then
            printf '%s\n' "${currentIp}"
            return 0
        fi
    done
    return 1
}

currentRealityNetworkProfile() {
    local currentIp profile
    currentIp=$(realityTargetPublicIPv4) || return 1
    profile=$(lookupRealityTargetAsn "${currentIp}") || return 1
    printf '%s\t%s\n' "${currentIp}" "${profile}"
}

normalizeRealityAsn() {
    local asn=$1
    asn=${asn#AS}
    asn=${asn#as}
    [[ "${asn}" =~ ^[0-9]+$ ]] || return 1
    printf 'AS%s\n' "${asn}"
}

fetchRealityAsnPrefixes() {
    local asn=$1
    local response
    asn=$(normalizeRealityAsn "${asn}") || return 1
    command -v jq >/dev/null 2>&1 || return 1
    response=$(fetchUrlToStdout "https://stat.ripe.net/data/announced-prefixes/data.json?resource=${asn}" 3 2>/dev/null) || return 1
    printf '%s\n' "${response}" | jq -r '.data.prefixes[]?.prefix | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/[0-9]+$"))' 2>/dev/null
}

realityIpv4ToInt() {
    local ip=$1
    local a b c d
    [[ "${ip}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    a=${BASH_REMATCH[1]}
    b=${BASH_REMATCH[2]}
    c=${BASH_REMATCH[3]}
    d=${BASH_REMATCH[4]}
    [[ "${a}" -le 255 && "${b}" -le 255 && "${c}" -le 255 && "${d}" -le 255 ]] || return 1
    printf '%s\n' "$(((a << 24) + (b << 16) + (c << 8) + d))"
}

realityIntToIpv4() {
    local value=$1
    printf '%s.%s.%s.%s\n' "$(((value >> 24) & 255))" "$(((value >> 16) & 255))" "$(((value >> 8) & 255))" "$((value & 255))"
}

realityAsnPrefixUsableRange() {
    local prefix=$1
    local ip mask start size first last
    [[ "${prefix}" =~ ^([^/]+)/([0-9]+)$ ]] || return 1
    ip=${BASH_REMATCH[1]}
    mask=${BASH_REMATCH[2]}
    [[ "${mask}" =~ ^[0-9]+$ && "${mask}" -le 32 ]] || return 1
    start=$(realityIpv4ToInt "${ip}") || return 1
    size=$((1 << (32 - mask)))
    first=${start}
    last=$((start + size - 1))
    if (( mask <= 30 && size > 2 )); then
        first=$((first + 1))
        last=$((last - 1))
    fi
    (( last >= first )) || return 1
    printf '%s\t%s\t%s\n' "${first}" "${last}" "$((last - first + 1))"
}

realityAsnPrefixTotalUsableAddressCount() {
    local prefix range first last count total=0
    while IFS= read -r prefix; do
        range=$(realityAsnPrefixUsableRange "${prefix}" || true)
        [[ -n "${range}" ]] || continue
        IFS=$'\t' read -r first last count <<<"${range}"
        total=$((total + count))
    done
    printf '%s\n' "${total}"
}

selectRealityAsnSampleSize() {
    local selected manualSize totalUsable=$1
    selectedRealityAsnSampleSize=0
    selectedRealityAsnFullScan=false
    echoContent title "\n┌─ 同 ASN 随机抽样 ─────────────────────────────────"
    menuLine "用途：从本机 ASN 的公告前缀里抽样寻找可用 REALITY 目标站"
    menuLine "说明：普通档位按 prefix 均衡覆盖；不会全量扫描 ASN"
    menuItem 1 "快速 300 个 IP" "先探路，风险低"
    menuRecommendedItem 2 "推荐 1000 个 IP" "默认推荐"
    menuItem 3 "深入 3000 个 IP" "提高命中率"
    menuItem 4 "大规模 10000 个 IP" "耗时更长，谨慎使用"
    menuItem 5 "手动输入数量" "自定义本次抽样 IP 数"
    menuItem 6 "全量扫描 高风险" "扫描全部公告前缀，可能数量很大"
    menuReturnItem 7 "返回" "回到 REALITY 目标站管理"
    menuClose
    autoRead reality_asn_sample_size "请选择抽样规模[默认2]:" selected
    case "${selected:-2}" in
    1) selectedRealityAsnSampleSize=300 ;;
    2) selectedRealityAsnSampleSize=1000 ;;
    3) selectedRealityAsnSampleSize=3000 ;;
    4) selectedRealityAsnSampleSize=10000 ;;
    5)
        autoRead reality_asn_sample_size_manual "请输入要随机抽样的 IP 数[1~100000，默认1000]:" manualSize
        manualSize=${manualSize:-1000}
        [[ "${manualSize}" =~ ^[0-9]+$ && "${manualSize}" -ge 1 && "${manualSize}" -le 100000 ]] || return 1
        selectedRealityAsnSampleSize=${manualSize}
        ;;
    6)
        selectedRealityAsnFullScan=true
        selectedRealityAsnSampleSize=${totalUsable}
        ;;
    7|r|R) return 1 ;;
    *) return 1 ;;
    esac
    if [[ "${selectedRealityAsnFullScan}" != "true" && "${selectedRealityAsnSampleSize}" -gt "${totalUsable}" ]]; then
        selectedRealityAsnSampleSize=${totalUsable}
    fi
}

generateRealityAsnSampleIps() {
    local prefixFile=$1
    local targetCount=$2
    local outputFile=$3
    local rangesFile prefix range first _ count generated=0 prefixIndex remaining randomIndex lastIndex
    local pickKey lastKey ipOffset lastOffset randomValue ip
    declare -a rangeFirsts=()
    declare -a rangeRemaining=()
    declare -A rangeShuffle=()
    padmCreateTempPath rangesFile || return 1
    while IFS= read -r prefix; do
        range=$(realityAsnPrefixUsableRange "${prefix}" || true)
        [[ -n "${range}" ]] && printf '%s\n' "${range}" >>"${rangesFile}"
    done <"${prefixFile}"
    while IFS=$'\t' read -r first _ count; do
        rangeFirsts+=("${first}")
        rangeRemaining+=("${count}")
    done <"${rangesFile}"
    padmRemoveCleanupPath "${rangesFile}"
    : >"${outputFile}"
    [[ "${#rangeFirsts[@]}" -gt 0 && "${targetCount}" -gt 0 ]] || return 1
    while (( generated < targetCount )); do
        for prefixIndex in "${!rangeFirsts[@]}"; do
            (( generated >= targetCount )) && break
            first=${rangeFirsts[${prefixIndex}]}
            remaining=${rangeRemaining[${prefixIndex}]}
            if (( remaining <= 0 )); then
                continue
            fi
            # Sparse Fisher-Yates: sample a unique offset without walking a huge prefix.
            randomValue=$(( (RANDOM << 30) ^ (RANDOM << 15) ^ RANDOM ))
            randomIndex=$((randomValue % remaining))
            lastIndex=$((remaining - 1))
            pickKey="${prefixIndex}:${randomIndex}"
            lastKey="${prefixIndex}:${lastIndex}"
            if [[ -v "rangeShuffle[${pickKey}]" ]]; then
                ipOffset=${rangeShuffle[${pickKey}]}
            else
                ipOffset=${randomIndex}
            fi
            if [[ -v "rangeShuffle[${lastKey}]" ]]; then
                lastOffset=${rangeShuffle[${lastKey}]}
            else
                lastOffset=${lastIndex}
            fi
            if (( randomIndex == lastIndex )); then
                unset "rangeShuffle[${lastKey}]"
            else
                rangeShuffle[${pickKey}]=${lastOffset}
                unset "rangeShuffle[${lastKey}]"
            fi
            rangeRemaining[prefixIndex]=${lastIndex}
            ip=$((first + ipOffset))
            printf '%d.%d.%d.%d\n' "$(( (ip >> 24) & 255 ))" "$(( (ip >> 16) & 255 ))" "$(( (ip >> 8) & 255 ))" "$(( ip & 255 ))" >>"${outputFile}"
            generated=$((generated + 1))
        done
        if (( generated < targetCount )); then
            local hasRemaining=false
            for prefixIndex in "${!rangeFirsts[@]}"; do
                if (( rangeRemaining[prefixIndex] > 0 )); then
                    hasRemaining=true
                    break
                fi
            done
            [[ "${hasRemaining}" == "true" ]] || break
        fi
    done
    [[ -s "${outputFile}" ]]
}

showRealityAsnSampleSummary() {
    local targetFile=$1
    local asn=$2
    local totalPrefixes=$3
    local totalUsable=$4
    local sampleSize=$5
    local strategy=$6
    local sampleTargets= target ratioBasis ratioPercent ratioFraction
    while IFS= read -r target; do
        if [[ -z "${sampleTargets}" ]]; then
            sampleTargets=${target}
        else
            sampleTargets+=",${target}"
        fi
        [[ "${#sampleTargets}" -ge 140 ]] && break
    done <"${targetFile}"
    sampleTargets=${sampleTargets:0:140}
    if [[ "${totalUsable}" -gt 0 ]]; then
        ratioBasis=$((sampleSize * 10000 / totalUsable))
        ratioPercent=$((ratioBasis / 100))
        ratioFraction=$((ratioBasis % 100))
        ratio=$(printf '%s.%02d%%' "${ratioPercent}" "${ratioFraction}")
    else
        ratio="0.00%"
    fi
    echoContent title "\n┌─ 同 ASN 抽样确认：${asn} ───────────────────────────"
    menuLine "ASN 公告 prefix 数：${totalPrefixes}"
    menuLine "ASN 可用 IP 总数：${totalUsable}"
    menuLine "本次将扫描 IP：${sampleSize}"
    menuLine "本次覆盖比例：${ratio}"
    menuLine "抽样策略：${strategy}"
    [[ -n "${sampleTargets}" ]] && menuLine "示例 IP：${sampleTargets}"
    menuLine "确认后只扫描本次抽样出的 IP 列表，不扫描整个 ASN"
    menuClose
}

showRealityAsnPrefixSetSummary() {
    local prefixFile=$1
    local asn=$2
    local title=$3
    local samplePrefixes= prefix count=0
    while IFS= read -r prefix; do
        count=$((count + 1))
        if (( count <= 5 )); then
            if [[ -z "${samplePrefixes}" ]]; then
                samplePrefixes=${prefix}
            else
                samplePrefixes+=",${prefix}"
            fi
        fi
    done <"${prefixFile}"
    echoContent title "\n┌─ 同 ASN ${title}确认：${asn} ───────────────────────"
    menuLine "公告 prefix 数：${count}"
    [[ -n "${samplePrefixes}" ]] && menuLine "示例 prefix：${samplePrefixes}"
    menuLine "该操作会扫描所选范围内 IP；如数量过大，请返回选择更小规模"
    menuClose
}

selectRealityAsnScanPlan() {
    local asn=$1
    local allPrefixFile=$2
    local totalPrefixes totalUsable sampleFile confirm strategy
    selectedRealityScannerPrefixFile=
    selectedRealityScannerRange=
    selectedRealityAsnPrefixTotal=0
    selectedRealityAsnAddressTotal=0
    selectedRealityAsnSampleSize=0
    selectedRealityAsnFullScan=false
    asn=$(normalizeRealityAsn "${asn}") || return 1
    totalPrefixes=$(wc -l <"${allPrefixFile}" | tr -d ' ')
    totalUsable=$(realityAsnPrefixTotalUsableAddressCount <"${allPrefixFile}")
    [[ "${totalUsable}" -gt 0 ]] || return 1
    while true; do
        selectRealityAsnSampleSize "${totalUsable}" || return 1
        if [[ "${selectedRealityAsnFullScan}" == "true" ]]; then
            showRealityAsnPrefixSetSummary "${allPrefixFile}" "${asn}" "全量公告前缀"
            selectedRealityAsnPrefixTotal=${totalPrefixes}
            selectedRealityAsnAddressTotal=${totalUsable}
            autoConfirm reality_asn_prefix_confirm "确认全量扫描 ${selectedRealityAsnPrefixTotal} 个 prefix、约 ${selectedRealityAsnAddressTotal} 个可用 IP？" n confirm
            if [[ "${confirm}" == "y" ]]; then
                padmCreateTempPath selectedRealityScannerPrefixFile || return 1
                cp "${allPrefixFile}" "${selectedRealityScannerPrefixFile}"
                selectedRealityScannerRange="全量公告前缀 ${selectedRealityAsnPrefixTotal} prefixes"
                return 0
            fi
            continue
        fi
        padmCreateTempPath sampleFile || return 1
        generateRealityAsnSampleIps "${allPrefixFile}" "${selectedRealityAsnSampleSize}" "${sampleFile}" || {
            padmRemoveCleanupPath "${sampleFile}"
            errorCard "随机抽样失败，请返回或重试"
            continue
        }
        selectedRealityAsnSampleSize=$(wc -l <"${sampleFile}" | tr -d ' ')
        selectedRealityAsnPrefixTotal=${totalPrefixes}
        selectedRealityAsnAddressTotal=${selectedRealityAsnSampleSize}
        strategy="均衡覆盖 prefix"
        showRealityAsnSampleSummary "${sampleFile}" "${asn}" "${totalPrefixes}" "${totalUsable}" "${selectedRealityAsnSampleSize}" "${strategy}"
        autoConfirm reality_asn_prefix_confirm "确认扫描本次抽样出的 ${selectedRealityAsnSampleSize} 个 IP？" n confirm
        if [[ "${confirm}" == "y" ]]; then
            selectedRealityScannerPrefixFile=${sampleFile}
            selectedRealityScannerRange="本次抽样 ${selectedRealityAsnSampleSize} IP（ASN 总可用 ${totalUsable}）"
            return 0
        fi
        padmRemoveCleanupPath "${sampleFile}"
    done
}

realityTargetProviderMatches() {
    local currentOrg=$1
    local candidateOrg=$2
    local currentNorm candidateNorm
    currentNorm=$(printf '%s\n' "${currentOrg}" | tr '[:upper:]' '[:lower:]')
    candidateNorm=$(printf '%s\n' "${candidateOrg}" | tr '[:upper:]' '[:lower:]')
    [[ -n "${currentNorm}" && -n "${candidateNorm}" ]] || return 1
    [[ "${candidateNorm}" == *"${currentNorm}"* || "${currentNorm}" == *"${candidateNorm}"* ]]
}

realityTargetCdnProviderFromCname() {
    local cname=${1,,}
    cname=${cname%.}
    case "${cname}" in
    cloudfront.net | *.cloudfront.net | *.cloudfront.com) printf 'cloudfront\n' ;;
    fastly.net | *.fastly.net | *.fastlylb.net) printf 'fastly\n' ;;
    akamai.net | *.akamai.net | *.akamaiedge.net | *.akamaihd.net | *.akamaized.net | *.edgesuite.net | *.edgekey.net | *.akamaistream.net) printf 'akamai\n' ;;
    azureedge.net | *.azureedge.net | *.trafficmanager.net | *.azurefd.net) printf 'azure\n' ;;
    cdn.cloudflare.net | *.cdn.cloudflare.net | *.cloudflare.net) printf 'cloudflare\n' ;;
    bunnycdn.com | *.bunnycdn.com | *.b-cdn.net) printf 'bunny\n' ;;
    cdn77.org | *.cdn77.org | *.cdn77.net | *.stackpathcdn.com | *.stackpathdns.com) printf 'edge\n' ;;
    *.incapdns.net | *.impervadns.net | *.sucuri.net | *.edgecastcdn.net | *.llnwd.net | *.limelight.com) printf 'edge\n' ;;
    *.cachefly.net | *.keycdn.com | *.kxcdn.com | *.gcorelabs.net | *.gcore.com) printf 'edge\n' ;;
    *) return 1 ;;
    esac
}

realityTargetCdnProviderFromAsn() {
    local asn=${1:-}
    local asOrg=${2:-}
    local normalizedAsn normalizedOrg
    normalizedAsn=$(normalizeRealityAsn "${asn}" 2>/dev/null || true)
    case "${normalizedAsn}" in
    AS13335) printf 'cloudflare\n'; return 0 ;;
    AS16625 | AS20940) printf 'akamai\n'; return 0 ;;
    AS54113) printf 'fastly\n'; return 0 ;;
    AS60068) printf 'bunny\n'; return 0 ;;
    AS12989 | AS15133 | AS22822) printf 'edge\n'; return 0 ;;
    esac
    normalizedOrg=$(printf '%s' "${asOrg}" | tr '[:upper:]' '[:lower:]')
    case "${normalizedOrg}" in
    *akamai* | *fastly* | *bunny* | *stackpath* | *edgecast* | *limelight* | *imperva* | *cdn77* | *gcore*)
        printf 'edge\n'
        return 0
        ;;
    *) return 1 ;;
    esac
}

realityTargetDnsCdnProvider() {
    local host=$1
    local cname provider
    [[ -n "${host}" && "${host}" != *:* && ! "${host}" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    if command -v dig >/dev/null 2>&1; then
        while IFS= read -r cname; do
            [[ -n "${cname}" ]] || continue
            provider=$(realityTargetCdnProviderFromCname "${cname}" 2>/dev/null || true)
            [[ -n "${provider}" ]] && { printf '%s\n' "${provider}"; return 0; }
        done < <(dig +time=2 +tries=1 +short CNAME "${host}" 2>/dev/null || true)
    elif command -v host >/dev/null 2>&1; then
        while IFS= read -r cname; do
            [[ -n "${cname}" ]] || continue
            provider=$(realityTargetCdnProviderFromCname "${cname}" 2>/dev/null || true)
            [[ -n "${provider}" ]] && { printf '%s\n' "${provider}"; return 0; }
        done < <(host -t CNAME "${host}" 2>/dev/null | awk '/alias for/ {print $NF}')
    fi
    return 1
}

realityTargetDetector() {
    if [[ -x "/etc/padm/xray/xray" ]]; then
        printf '%s\n' "/etc/padm/xray/xray"
    elif command -v xray >/dev/null 2>&1; then
        command -v xray
    else
        return 1
    fi
}

realityTargetOpenSslAutoFallbackAllowed() {
    local detector=${1:-}
    [[ -z "${detector}" ]] || return 1
    [[ "${coreInstallType:-}" == "2" || "${selectCoreType:-}" == "2" ]] || return 1
    command -v openssl >/dev/null 2>&1
}

realityTargetTlsPingState() {
    local output=$1
    printf '%s\n' "${output}" | awk '
      /Pinging with SNI/ {inSni = 1; next}
      inSni && /Handshake succeeded/ {success = 1}
      inSni && /Handshake failure/ {rejected = 1}
      END {
        if (success) print "success"
        else if (rejected) print "rejected"
        else print "unknown"
      }
    '
}

probeRealityTargetTls() {
    local detector=$1
    local ip=$2
    local sni=$3
    local port=$4
    local timeoutSeconds=${PADM_REALITY_TLS_TIMEOUT:-15}
    local target connect raw
    [[ "${timeoutSeconds}" =~ ^[0-9]+$ && "${timeoutSeconds}" -gt 0 ]] || timeoutSeconds=15
    target=$(formatRealityTarget "${sni}" "${port}")
    if ! command -v timeout >/dev/null 2>&1; then
        printf 'Pinging with SNI\nProbe unavailable: timeout command is missing\n'
        return 0
    fi
    if [[ -n "${detector}" ]]; then
        if declare -F "${detector}" >/dev/null 2>&1 && ! declare -F timeout >/dev/null 2>&1; then
            raw=$("${detector}" tls ping -ip "${ip}" "${target}" 2>&1 || true)
        else
            raw=$(timeout -k 2 "${timeoutSeconds}" "${detector}" tls ping -ip "${ip}" "${target}" 2>&1 || true)
        fi
        printf '%s\n' "${raw}"
        return 0
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        printf 'Pinging with SNI\nProbe unavailable: neither xray nor openssl is installed\n'
        return 0
    fi
    if [[ "${ip}" == *:* ]]; then
        connect="[${ip}]:${port}"
    else
        connect="${ip}:${port}"
    fi
    if raw=$(timeout -k 2 "${timeoutSeconds}" openssl s_client -connect "${connect}" -servername "${sni}" \
        -verify_hostname "${sni}" -verify_return_error -tls1_3 -brief </dev/null 2>&1); then
        printf 'Pinging with SNI\nHandshake succeeded\nTLS version: TLSv1.3\n%s\n' "${raw}"
    elif printf '%s\n' "${raw}" | grep -Eqi 'hostname mismatch|certificate verify failed|verify error:num=62'; then
        printf 'Pinging with SNI\nHandshake failure: certificate does not match SNI\n%s\n' "${raw}"
    else
        printf 'Pinging with SNI\nProbe unavailable: TLS connection failed\n%s\n' "${raw}"
    fi
}

realityTargetAddressCdnRisk() {
    local detector=$1
    local ip=$2
    local port=$3
    local asn=$4
    local targetState=$5
    local asOrg=${6:-}
    local dnsProvider=${7:-}
    local normalizedAsn provider cfResult cfState
    if [[ "${dnsProvider}" == "cloudflare" ]]; then
        printf 'cloudflare_relay\n'
        return 0
    elif [[ -n "${dnsProvider}" ]]; then
        printf 'cdn_edge\n'
        return 0
    fi
    provider=$(realityTargetCdnProviderFromAsn "${asn}" "${asOrg}" 2>/dev/null || true)
    if [[ "${provider}" == "cloudflare" ]]; then
        printf 'cloudflare_relay\n'
        return 0
    elif [[ -n "${provider}" ]]; then
        printf 'cdn_edge\n'
        return 0
    fi
    normalizedAsn=$(normalizeRealityAsn "${asn}" 2>/dev/null || true)
    if [[ "${normalizedAsn}" == "AS13335" ]]; then
        printf 'cloudflare_relay\n'
        return 0
    fi
    if [[ "${targetState}" != "success" ]]; then
        printf 'unknown\n'
        return 0
    fi
    cfResult=$(probeRealityTargetTls "${detector}" "${ip}" cloudflare.com "${port}")
    cfState=$(realityTargetTlsPingState "${cfResult}")
    case "${cfState}" in
    success) printf 'cloudflare_relay\n' ;;
    rejected)
        if [[ -n "${normalizedAsn}" ]]; then
            printf 'no\n'
        else
            printf 'unknown\n'
        fi
        ;;
    *) printf 'unknown\n' ;;
    esac
}

probeRealityTargetEndpoint() {
    local detector=$1
    local target=$2
    local sni=$3
    local preferredIp=${4:-}
    local addressScope=${5:-all}
    local asnCacheFile=${6:-}
    local parsed host port resolved='' addresses ip profile asn asOrg targetResult targetState addressRisk hostCdnProvider
    local primaryIp=unknown primaryAsn=unknown primaryOrg=unknown scoreResult='' risk=no
    local addressScore addressPqc addressCertLength addressTls13 addressNote addressRank certRank
    local score=FAIL pqc=no certLength=unknown tls13=unknown note="未完成 TLS 质量检测"
    local worstRank=99 worstCertRank=0 scoredAddresses=0
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    hostCdnProvider=$(realityTargetDnsCdnProvider "${host}" 2>/dev/null || true)
    if [[ "${addressScope}" == "preferred_only" ]]; then
        addresses=${preferredIp}
    else
        resolved=$(resolveRealityTargetAddresses "${host}" 2>/dev/null || true)
        addresses=$(printf '%s\n%s\n' "${preferredIp}" "${resolved}" | awk 'NF && !seen[$0]++')
        [[ -n "${resolved}" ]] || risk=unknown
    fi
    [[ -n "${addresses}" ]] || return 1

    while IFS= read -r ip; do
        [[ -n "${ip}" ]] || continue
        targetResult=$(probeRealityTargetTls "${detector}" "${ip}" "${sni}" "${port}")
        targetState=$(realityTargetTlsPingState "${targetResult}")
        scoreResult=$(scoreRealityTargetFromTlsPing "${targetResult}")
        IFS=$'\t' read -r addressScore addressPqc addressCertLength addressTls13 addressNote <<<"${scoreResult}"
        profile=
        if [[ "${addressScore}" != "FAIL" ]]; then
            profile=$(lookupRealityTargetAsnCached "${ip}" "${asnCacheFile}" 2>/dev/null || true)
        fi
        if [[ -n "${profile}" ]]; then
            asn=${profile%%$'\t'*}
            asOrg=${profile#*$'\t'}
        else
            asn=unknown
            asOrg=unknown
        fi
        case "${addressScore}" in
        A) addressRank=4 ;;
        B) addressRank=3 ;;
        C) addressRank=2 ;;
        FAIL) addressRank=1 ;;
        *) addressRank=0 ;;
        esac
        certRank=0
        [[ "${addressCertLength}" =~ ^[0-9]+$ ]] && certRank=${addressCertLength}
        scoredAddresses=$((scoredAddresses + 1))
        if (( addressRank < worstRank || (addressRank == worstRank && certRank < worstCertRank) )); then
            primaryIp=${ip}
            primaryAsn=${asn}
            primaryOrg=${asOrg}
            score=${addressScore}
            pqc=${addressPqc}
            certLength=${addressCertLength}
            tls13=${addressTls13}
            note=${addressNote}
            worstRank=${addressRank}
            worstCertRank=${certRank}
        fi
        addressRisk=$(realityTargetAddressCdnRisk "${detector}" "${ip}" "${port}" "${asn}" "${targetState}" "${asOrg}" "${hostCdnProvider}")
        case "${addressRisk}" in
        cloudflare_relay) risk=cloudflare_relay ;;
        cdn_edge) [[ "${risk}" == "cloudflare_relay" ]] || risk=cdn_edge ;;
        no) ;;
        *) [[ "${risk}" == "cloudflare_relay" ]] || risk=unknown ;;
        esac
    done <<<"${addresses}"

    if (( scoredAddresses > 1 )); then
        note="${note}; 全部 ${scoredAddresses} 个地址按最差评分聚合"
    fi
    case "${risk}" in
    cloudflare_relay) note="${note}; 检测到 Cloudflare 中继风险" ;;
    cdn_edge) note="${note}; 检测到 CDN/边缘代理风险" ;;
    unknown) note="${note}; DNS/ASN/TLS 风险探测不完整" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${risk}" "${primaryIp}" "${primaryAsn}" "${primaryOrg}" \
        "${score}" "${pqc}" "${certLength}" "${tls13}" "${note}"
}

validateRealityTargetSelection() {
    local policy=$1
    local target=$2
    local sni=$3
    local parsed host port detector='' probeResult cdnRisk ip asn asOrg score pqc certLength tls13 note
    local networkProfile rest currentAsn='' currentOrg='' networkMatch=unknown checkedAt cachedLine='' name category
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    target=$(formatRealityTarget "${host}" "${port}")
    if ! validateRealityTarget "${host}" "${port}" || ! padmIsValidHostName "${sni}"; then
        realityTargetStatusBlock red "REALITY 目标站" "目标或 SNI 不合法: ${target} / ${sni}"
        return 1
    fi
    if realityTargetCandidateBlocked "${host}" cdn_edge ||
        realityTargetCandidateBlocked "${host}" cloudflare_relay ||
        realityTargetCandidateBlocked "${host}" cdn; then
        realityTargetStatusBlock red "REALITY 目标站" "命中已知 CDN/边缘代理风险域名: ${target}" "静态黑名单已拒绝写入配置"
        return 1
    fi
    detector=$(realityTargetDetector 2>/dev/null || true)
    if [[ -z "${detector}" ]] && ! command -v openssl >/dev/null 2>&1; then
        realityTargetStatusBlock red "REALITY 目标站" "缺少 Xray/OpenSSL，无法完成安全检测" "已拒绝写入配置"
        return 1
    fi
    realityTargetStatusBlock yellow "REALITY 目标站校验" "正在检测全部 A/AAAA: ${target}" "SNI: ${sni}"
    probeResult=$(probeRealityTargetEndpoint "${detector}" "${target}" "${sni}") || {
        realityTargetStatusBlock red "REALITY 目标站" "目标地址解析失败: ${target}" "已拒绝写入配置"
        return 1
    }
    IFS=$'\t' read -r cdnRisk ip asn asOrg score pqc certLength tls13 note <<<"${probeResult}"
    if networkProfile=$(currentRealityNetworkProfile 2>/dev/null); then
        rest=${networkProfile#*$'\t'}
        currentAsn=${rest%%$'\t'*}
        currentOrg=${rest#*$'\t'}
        if [[ "${asn}" == "${currentAsn}" ]]; then
            networkMatch=same_asn
        elif [[ "${asn}" != "unknown" ]] && realityTargetProviderMatches "${currentOrg}" "${asOrg}"; then
            networkMatch=same_provider
        elif [[ "${asn}" != "unknown" ]]; then
            networkMatch=different_network
        fi
    fi
    cachedLine=$(realityTargetResultLine "${target}" 2>/dev/null || true)
    name=${host}
    category=manual
    if [[ -n "${cachedLine}" ]]; then
        name=$(realityTargetResultField "${cachedLine}" 3)
        category=$(realityTargetResultField "${cachedLine}" 4)
    fi
    checkedAt=$(date +%s)
    writeRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" \
        "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" \
        "${certLength}" "${tls13}" "${checkedAt}" "最终校验: ${note}" || return 1

    case "${cdnRisk}" in
    cloudflare_relay)
        realityTargetStatusBlock red "REALITY 目标站" "检测到 Cloudflare 中继风险: ${target}" "ASN=${asn}，已拒绝写入配置"
        return 1
        ;;
    cdn_edge | yes)
        realityTargetStatusBlock red "REALITY 目标站" "检测到 CDN/边缘代理风险: ${target}" "ASN=${asn} ${asOrg}，已拒绝写入配置"
        return 1
        ;;
    no) ;;
    *)
        realityTargetStatusBlock red "REALITY 目标站" "风险检测结果为 unknown: ${target}" "DNS、ASN 或 TLS 探测不完整，已拒绝写入配置"
        return 1
        ;;
    esac
    case "${score}" in
    A | B | C) ;;
    FAIL)
        realityTargetStatusBlock red "REALITY 目标站" "TLS 质量检测失败: ${target}" "${note}"
        return 1
        ;;
    *)
        realityTargetStatusBlock red "REALITY 目标站" "TLS 质量检测返回无效评分: ${score:-empty}" "已拒绝写入配置"
        return 1
        ;;
    esac
    if [[ "${policy}" == "auto" && "${score}" != "A" ]]; then
        if [[ "${score}" != "C" ]] || ! realityTargetOpenSslAutoFallbackAllowed "${detector}"; then
            realityTargetStatusBlock red "REALITY 自动推荐" "自动模式不接受当前目标: ${target}" "本次评分: ${score}"
            return 1
        fi
    fi
    if [[ "${policy}" == "auto" && "${score}" == "C" ]]; then
        realityTargetStatusBlock yellow "REALITY 自动推荐" "sing-box 无 Xray，已使用 OpenSSL 验证的 C 级 TLS 1.3 目标" "${note}"
    elif [[ "${score}" == "B" || "${score}" == "C" ]]; then
        realityTargetStatusBlock yellow "REALITY 目标站" "手工目标已通过 CDN 风险校验，但质量为 ${score} 级" "${note}"
    else
        realityTargetStatusBlock green "REALITY 目标站" "已通过安全校验: ${target}" "cdn_risk=no，评分=${score}"
    fi
}

formatRealityTarget() {
    local host=$1
    local port=${2:-443}
    printf '%s:%s\n' "${host}" "${port}"
}

realityTargetCandidateLineByIndex() {
    local wanted=$1
    local line index=1
    while IFS= read -r line; do
        if [[ "${index}" == "${wanted}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
        index=$((index + 1))
    done < <(realityTargetCandidates)
    return 1
}

realityTargetCandidateCount() {
    local line count=0
    while IFS= read -r line; do
        count=$((count + 1))
    done < <(realityTargetCandidates)
    printf '%s\n' "${count}"
}

realityTargetCandidateField() {
    local line=$1
    local field=$2
    local value
    IFS='|' read -r _f1 _f2 _f3 _f4 _f5 _f6 _f7 _f8 _f9 <<<"${line}"
    case "${field}" in
    1) value=${_f1} ;;
    2) value=${_f2} ;;
    3) value=${_f3} ;;
    4) value=${_f4} ;;
    5) value=${_f5} ;;
    6) value=${_f6} ;;
    7) value=${_f7} ;;
    8) value=${_f8} ;;
    9) value=${_f9} ;;
    *) value= ;;
    esac
    printf '%s\n' "${value}"
}

realityTargetCandidateMatchesFilter() {
    local line=$1
    local filter=${2:-recommended}
    local host sni name region category cdn rank recommended note haystack
    filter=${filter,,}
    IFS='|' read -r host sni name region category cdn rank recommended note <<<"${line}"

    case "${filter}" in
    dev | 开发者) filter=developer ;;
    媒体) filter=media ;;
    亚洲) filter=asia ;;
    esac
    case "${filter}" in
    "" | all | 全部)
        return 0
        ;;
    recommended | 推荐)
        [[ "${recommended}" == "yes" ]]
        return
        ;;
    manual | 手动备选)
        [[ "${recommended}" != "yes" ]]
        return
        ;;
    esac

    haystack="${host} ${sni} ${name} ${region} ${category} ${note}"
    haystack=${haystack,,}
    [[ "${haystack}" == *"${filter}"* ]]
}

realityTargetFilteredCandidates() {
    local filter=${1:-recommended}
    local line
    while IFS= read -r line; do
        realityTargetCandidateMatchesFilter "${line}" "${filter}" && printf '%s\n' "${line}"
    done < <(realityTargetCandidates)
}

realityTargetFilteredCandidateCount() {
    local line count=0
    while IFS= read -r line; do
        count=$((count + 1))
    done < <(realityTargetFilteredCandidates "${1:-recommended}")
    printf '%s\n' "${count}"
}

realityTargetFilteredCandidateLineByIndex() {
    local filter=$1
    local wanted=$2
    local line index=1
    while IFS= read -r line; do
        if [[ "${index}" == "${wanted}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
        index=$((index + 1))
    done < <(realityTargetFilteredCandidates "${filter}")
    return 1
}

showRealityTargetCandidatePage() {
    local filter=${1:-all}
    local page=${2:-1}
    local pageSize=${3:-12}
    local total start end line index=1 host sni name region category _cdn rank recommended note
    total=$(realityTargetFilteredCandidateCount "${filter}")
    start=$(( (page - 1) * pageSize + 1 ))
    end=$(( page * pageSize ))

    echoContent title "\n┌─ REALITY 目标站候选 ───────────────────────────────"
    menuLine "筛选：${filter}；第 ${page} 页；总数：${total}"
    menuLine "输入编号选择；n 下一页；p 上一页；f 筛选；a 全部；m 手动输入；r 返回"
    if [[ "${total}" == "0" ]]; then
        menuLine "没有匹配候选，请更换筛选条件或手动输入"
        menuClose
        return 0
    fi
    while IFS= read -r line; do
        if (( index >= start && index <= end )); then
            IFS='|' read -r host sni name region category _cdn rank recommended note <<<"${line}"
            menuItem "${index}" "${host}:443" "${name} ${region}/${category} SNI=${sni}"
            [[ -n "${note}" ]] && menuLine "    ${note}"
        fi
        index=$((index + 1))
    done < <(realityTargetFilteredCandidates "${filter}")
    menuClose
}

selectRealityTargetCandidateInteractive() {
    local filter=${1:-all}
    local page=1
    local pageSize=${REALITY_TARGET_PAGE_SIZE:-12}
    local total maxPage choice selectedLine targetInput

    while true; do
        total=$(realityTargetFilteredCandidateCount "${filter}")
        maxPage=$(( (total + pageSize - 1) / pageSize ))
        (( maxPage < 1 )) && maxPage=1
        (( page > maxPage )) && page=${maxPage}
        (( page < 1 )) && page=1
        showRealityTargetCandidatePage "${filter}" "${page}" "${pageSize}"
        autoRead reality_target_candidate "请选择候选编号或操作:" choice
        case "${choice}" in
        n | N)
            (( page < maxPage )) && page=$((page + 1))
            ;;
        p | P)
            (( page > 1 )) && page=$((page - 1))
            ;;
        a | A)
            filter=all
            page=1
            ;;
        f | F)
            echoContent title "\n┌─ REALITY 候选筛选 ─────────────────────────────────"
            menuLine "可输入：recommended/manual/all，或域名、名称、区域、分类关键词"
            menuClose
            autoRead reality_target_filter "请输入筛选条件[回车全部]：" filter
            filter=${filter:-all}
            page=1
            ;;
        m | M)
            autoRead reality_target "请输入REALITY伪装目标 host[:port]:" targetInput
            [[ -n "${targetInput}" ]] || continue
            parseRealityTargetInput "${targetInput}" || continue
            statusCard "已选择 REALITY 目标站" "目标: ${realityTargetHost}:${realityTargetPort}" "SNI: ${realitySNI}"
            return 0
            ;;
        r | R)
            return 1
            ;;
        '' )
            ;;
        *)
            if [[ "${choice}" =~ ^[0-9]+$ ]]; then
                selectedLine=$(realityTargetFilteredCandidateLineByIndex "${filter}" "${choice}") || {
                    errorCard "候选编号无效，请重新选择"
                    continue
                }
                realityTargetHost=$(realityTargetCandidateField "${selectedLine}" 1)
                realityTargetPort=443
                realitySNI=${AUTO_REALITY_SERVER_NAME:-$(realityTargetCandidateField "${selectedLine}" 2)}
                return 0
            fi
            errorCard "输入无效，请输入编号或 n/p/f/a/m/r"
            ;;
        esac
    done
}

selectAutoRecommendedRealityTarget() {
    local detector='' line host sni name category target record probeRecord probeStatus probePayload
    local currentProfile rest currentAsn='' currentOrg='' probeLimit probed=0 selectedLine selectedTarget selectedScore fallbackLine='' parsed
    local resultTarget resultSni resultName resultCategory cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note

    detector=$(realityTargetDetector 2>/dev/null || true)
    if [[ -z "${detector}" ]] && ! command -v openssl >/dev/null 2>&1; then
        realityTargetStatusBlock red "REALITY 自动推荐" "缺少 Xray/OpenSSL，无法实测目标质量"
        return 1
    fi
    if currentProfile=$(currentRealityNetworkProfile 2>/dev/null); then
        rest=${currentProfile#*$'\t'}
        currentAsn=${rest%%$'\t'*}
        currentOrg=${rest#*$'\t'}
    fi

    probeLimit=${PADM_REALITY_AUTO_PROBE_LIMIT:-10}
    [[ "${probeLimit}" =~ ^[0-9]+$ && "${probeLimit}" -gt 0 ]] || probeLimit=10

    while IFS= read -r line; do
        IFS='|' read -r host sni name _region category _cdn _rank _recommended _note <<<"${line}"
        target=$(formatRealityTarget "${host}" 443)
        probed=$((probed + 1))
        realityTargetStatusBlock yellow "REALITY 自动推荐" "正在检测全部 A/AAAA: ${target}" "SNI: ${sni}" "进度: ${probed}/${probeLimit}"
        record=$(formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" unknown unknown unknown unknown unknown unknown unknown unknown unknown 0 "自动推荐")
        probeRecord=$(probeRealityTargetRecord "${detector}" "${record}" "${currentAsn}" "${currentOrg}")
        IFS=$'\t' read -r probeStatus probePayload <<<"${probeRecord}"
        if [[ "${probeStatus}" == "OK" && -n "${probePayload}" ]]; then
            IFS=$'\t' read -r resultTarget resultSni resultName resultCategory cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note <<<"${probePayload}"
            if [[ -z "${fallbackLine}" && "${cdnRisk}" == "no" && "${score}" == "C" ]]; then
                fallbackLine=${probePayload}
            fi
            writeRealityTargetResultLine "${resultTarget}" "${resultSni}" "${resultName}" "${resultCategory}" "${cdnRisk}" \
                "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}" || return 1
        fi
        (( probed >= probeLimit )) && break
    done < <(realityTargetFilteredCandidates recommended)

    if selectScannedRealityTarget; then
        selectedTarget=$(formatRealityTarget "${realityTargetHost}" "${realityTargetPort}")
        selectedLine=$(realityTargetResultLine "${selectedTarget}") || return 1
    elif realityTargetOpenSslAutoFallbackAllowed "${detector}" && [[ -n "${fallbackLine}" ]]; then
        selectedLine=${fallbackLine}
        selectedTarget=$(realityTargetResultField "${selectedLine}" 1)
        resultSni=$(realityTargetResultField "${selectedLine}" 2)
        parsed=$(parseHostPort "${selectedTarget}" 443)
        realityTargetHost=${parsed%:*}
        realityTargetPort=${parsed##*:}
        realitySNI=${AUTO_REALITY_SERVER_NAME:-${resultSni:-${realityTargetHost}}}
    else
        realityTargetStatusBlock red "REALITY 自动推荐" "推荐候选未得到可接受的 cdn_risk=no 结果" "未写入未经检测的兜底目标"
        return 1
    fi
    selectedScore=$(realityTargetResultField "${selectedLine}" 10)
    if [[ "${selectedScore}" == "C" ]]; then
        realityTargetStatusBlock yellow "REALITY 自动推荐" "已选择 OpenSSL 验证的 sing-box 回退目标: ${selectedTarget}" "cdn_risk=no，评分=C" "实测候选: ${probed}"
    else
        realityTargetStatusBlock green "REALITY 自动推荐" "已选择: ${selectedTarget}" "cdn_risk=no，评分=${selectedScore}" "实测候选: ${probed}"
    fi
    return 0
}

selectDefaultRealityTarget() {
    if selectScannedRealityTarget; then
        return 0
    fi
    if selectAutoRecommendedRealityTarget; then
        return 0
    fi
    realityTargetStatusBlock red "REALITY 目标站" "没有通过安全门槛的可用目标" "请刷新目标库或手工输入后重试"
    return 1
}

parseRealityTargetInput() {
    local targetInput=$1
    local parsed targetHost targetPort
    parsed=$(parseHostPort "${targetInput}" 443)
    targetHost=${parsed%:*}
    targetPort=${parsed##*:}
    if ! validateRealityTarget "${targetHost}" "${targetPort}"; then
        realityTargetStatusBlock red "REALITY 目标站" "伪装目标不合法: ${targetInput}"
        return 1
    fi
    if [[ -n "${AUTO_REALITY_SERVER_NAME:-}" ]] && ! padmIsValidHostName "${AUTO_REALITY_SERVER_NAME}"; then
        realityTargetStatusBlock red "REALITY SNI" "SNI 不合法: ${AUTO_REALITY_SERVER_NAME}"
        return 1
    fi
    realityTargetHost=${targetHost}
    realityTargetPort=${targetPort}
    realitySNI=${AUTO_REALITY_SERVER_NAME:-${realityTargetHost}}
}

writeRealityTargetCacheLine() {
    local target=$1
    local score=$2
    local pqc=$3
    local certLength=$4
    local tls13=$5
    local checkedAt=$6
    local note=$7
    local refreshedIp=${8:-}
    local refreshedAsn=${9:-}
    local refreshedAsOrg=${10:-}
    local refreshedNetworkMatch=${11:-}
    local refreshedCdnRisk=${12:-}
    local parsed host line sni name category cdnRisk ip asn asOrg networkMatch
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    sni=${host}
    name=${host}
    category=manual
    cdnRisk=unknown
    ip=unknown
    asn=unknown
    asOrg=unknown
    networkMatch=unknown
    line=$(realityTargetResultLine "${target}" 2>/dev/null || true)
    if [[ -n "${line}" ]]; then
        sni=$(realityTargetResultField "${line}" 2)
        name=$(realityTargetResultField "${line}" 3)
        category=$(realityTargetResultField "${line}" 4)
        cdnRisk=$(realityTargetResultField "${line}" 5)
        ip=$(realityTargetResultField "${line}" 6)
        asn=$(realityTargetResultField "${line}" 7)
        asOrg=$(realityTargetResultField "${line}" 8)
        networkMatch=$(realityTargetResultField "${line}" 9)
    fi
    if [[ -n "${refreshedIp}" ]]; then
        ip=${refreshedIp}
        asn=${refreshedAsn:-unknown}
        asOrg=${refreshedAsOrg:-unknown}
        networkMatch=${refreshedNetworkMatch:-unknown}
    fi
    [[ -z "${refreshedCdnRisk}" ]] || cdnRisk=${refreshedCdnRisk}
    writeRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}"
}

scoreRealityTargetFromTlsPing() {
    local tlsPingResult=$1
    local sniResult
    local score="FAIL"
    local pqc="no"
    local certLength="unknown"
    local tls13="unknown"
    local note="未检测到可用 TLS 1.3 握手"

    sniResult=$(printf '%s\n' "${tlsPingResult}" | awk '/Pinging with SNI/{inSni=1; next} inSni')
    if printf '%s\n' "${sniResult}" | grep -qi "TLS Post-Quantum key exchange:.*X25519MLKEM768"; then
        pqc="yes"
    fi
    certLength=$(printf '%s\n' "${sniResult}" | awk '/Certificate chain/{print $5; exit}')
    [[ "${certLength}" =~ ^[0-9]+$ ]] || certLength="unknown"
    if printf '%s\n' "${sniResult}" | grep -qi "TLS.*1\.3\|TLSv1\.3"; then
        tls13="yes"
    fi

    if [[ "${tls13}" != "yes" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "${score}" "${pqc}" "${certLength}" "${tls13}" "${note}"
        return 0
    fi

    if [[ "${pqc}" == "yes" ]]; then
        if [[ "${certLength}" =~ ^[0-9]+$ && "${certLength}" -gt 3500 ]]; then
            score="A"
            note="TLS 1.3 + X25519MLKEM768 可用，证书链长度满足 Xray 要求"
        else
            score="B"
            note="TLS 1.3 + X25519MLKEM768 可用，但证书链长度未超过 3500，不适合 ML-DSA-65/PQC A 级使用"
        fi
    else
        score="C"
        note="TLS 1.3 可用，但未检测到 X25519MLKEM768，仅适合作为普通 Reality 备选"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${score}" "${pqc}" "${certLength}" "${tls13}" "${note}"
}

scannerRealityNetworkProfile() {
    local ip=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local origin=${4:-}
    local asnCacheFile=${5:-}
    local profile candidateAsn candidateOrg networkMatch
    profile=$(lookupRealityTargetAsnCached "${ip}" "${asnCacheFile}" "${origin}" || true)
    if [[ -n "${profile}" ]]; then
        candidateAsn=${profile%%$'\t'*}
        candidateOrg=${profile#*$'\t'}
    else
        candidateAsn=unknown
        candidateOrg=unknown
    fi
    networkMatch=scanner_local
    if [[ -n "${currentAsn}" && "${candidateAsn}" == "${currentAsn}" ]]; then
        networkMatch=same_asn
    elif [[ -n "${currentOrg}" && "${candidateOrg}" != "unknown" ]] && realityTargetProviderMatches "${currentOrg}" "${candidateOrg}"; then
        networkMatch=same_provider
    elif [[ "${candidateAsn}" != "unknown" ]]; then
        networkMatch=different_network
    fi
    printf '%s\t%s\t%s\n' "${candidateAsn}" "${candidateOrg}" "${networkMatch}"
}

normalizeRealityScannerCsv() {
    local sourceFile=$1
    awk '
function parseCsv(line, fields,    ch, count, i, key, quoted) {
    for (key in fields) delete fields[key]
    count = 1
    fields[count] = ""
    quoted = 0
    for (i = 1; i <= length(line); i++) {
        ch = substr(line, i, 1)
        if (ch == "\"") {
            if (quoted && substr(line, i + 1, 1) == "\"") {
                fields[count] = fields[count] "\""
                i++
            } else {
                quoted = !quoted
            }
        } else if (ch == "," && !quoted) {
            count++
            fields[count] = ""
        } else {
            fields[count] = fields[count] ch
        }
    }
    return quoted ? 0 : count
}
NR == 1 {
    sub(/\r$/, "")
    count = parseCsv($0, fields)
    if (!count) exit 2
    for (i = 1; i <= count; i++) columns[fields[i]] = i
    if (!("IP" in columns) || !("ORIGIN" in columns) || !("CERT_DOMAIN" in columns) || !("CERT_ISSUER" in columns) || !("GEO_CODE" in columns)) exit 2
    next
}
{
    sub(/\r$/, "")
    count = parseCsv($0, fields)
    if (!count) exit 3
    if (fields[columns["IP"]] == "") next
    printf "%s\t%s\t%s\t%s\t%s\n", fields[columns["IP"]], fields[columns["ORIGIN"]], fields[columns["CERT_DOMAIN"]], fields[columns["CERT_ISSUER"]], fields[columns["GEO_CODE"]]
}
END {
    if (NR == 0) exit 2
}
' "${sourceFile}"
}

probeRealityScannerCandidate() {
    local detector=$1
    local ip=$2
    local domain=$3
    local issuer=$4
    local currentAsn=${5:-}
    local currentOrg=${6:-}
    local networkMode=${7:-lookup}
    local origin=${8:-}
    local asnCacheFile=${9:-}
    local target tlsPingResult tlsState result score pqc certLength tls13 note checkedAt profile candidateAsn candidateOrg networkMatch cdnRisk dnsProvider

    trap - EXIT INT TERM
    target=$(formatRealityTarget "${domain}" 443)
    tlsPingResult=$(probeRealityTargetTls "${detector}" "${ip}" "${domain}" 443)
    tlsState=$(realityTargetTlsPingState "${tlsPingResult}")
    result=$(scoreRealityTargetFromTlsPing "${tlsPingResult}")
    IFS=$'\t' read -r score pqc certLength tls13 note <<<"${result}"
    if [[ "${score}" == "FAIL" ]]; then
        printf 'FAIL\t%s\n' "${target}"
        return 0
    fi
    if [[ "${networkMode}" == "same_asn" && -n "${currentAsn}" && -n "${currentOrg}" ]]; then
        candidateAsn=${currentAsn}
        candidateOrg=${currentOrg}
        networkMatch=same_asn
    else
        profile=$(scannerRealityNetworkProfile "${ip}" "${currentAsn}" "${currentOrg}" "${origin}" "${asnCacheFile}")
        IFS=$'\t' read -r candidateAsn candidateOrg networkMatch <<<"${profile}"
    fi
    dnsProvider=$(realityTargetDnsCdnProvider "${domain}" 2>/dev/null || true)
    cdnRisk=$(realityTargetAddressCdnRisk "${detector}" "${ip}" 443 "${candidateAsn}" "${tlsState}" "${candidateOrg}" "${dnsProvider}")
    checkedAt=$(date +%s)
    printf 'OK\t'
    formatRealityTargetResultLine "${target}" "${domain}" "${domain}" "scanner" "${cdnRisk}" "${ip}" "${candidateAsn}" "${candidateOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "RealiTLScanner: ${issuer}; ${note}"
}

importRealityScannerResults() {
    local sourceFile=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local summaryVar=${4:-}
    local networkMode=${5:-lookup}
    local seenDomainsFile=${6:-}
    local maxJobs=${PADM_REALITY_SECONDARY_JOBS:-8}
    local detector ip origin domain issuer domainKey record target score cdnRisk _geo
    local normalizedFile resultLinesFile failedTargetsFile probeDir asnCacheFile jobFile doneFile probeRecord probeStatus probePayload currentDomain
    local index=0 activeIndex slot pid running=0 madeProgress imported=0 skipped=0 duplicateCount=0 processed=0 totalRecords importStart lastProgressAt=0 now countA=0 countB=0 countC=0 countFail=0
    local -a candidates=() activeSlots=() jobPids=() jobFiles=() jobDoneFiles=() jobTargets=() jobDomains=()
    local -A seenDomains=()
    [[ -f "${sourceFile}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 导入" "CSV 不存在: ${sourceFile}"
        return 1
    }
    if ! detector=$(realityTargetDetector); then
        realityTargetStatusBlock yellow "RealiTLScanner 导入" "未找到 xray，无法二次检测 RealiTLScanner 结果"
        return 1
    fi
    if [[ -z "${currentAsn}" || -z "${currentOrg}" ]]; then
        local networkProfile rest
        if networkProfile=$(currentRealityNetworkProfile 2>/dev/null); then
            rest=${networkProfile#*$'\t'}
            currentAsn=${rest%%$'\t'*}
            currentOrg=${rest#*$'\t'}
        fi
    fi
    [[ "${maxJobs}" =~ ^[1-9][0-9]*$ ]] || maxJobs=8
    (( maxJobs > 16 )) && maxJobs=16
    importStart=$(date +%s)
    padmCreateTempPath normalizedFile || return 1
    if ! normalizeRealityScannerCsv "${sourceFile}" >"${normalizedFile}"; then
        padmRemoveCleanupPath "${normalizedFile}"
        realityTargetStatusBlock red "RealiTLScanner 导入" "CSV 表头或记录格式不兼容: ${sourceFile}" "需要字段: IP, ORIGIN, CERT_DOMAIN, CERT_ISSUER, GEO_CODE"
        return 1
    fi
    if [[ -n "${seenDomainsFile}" && -f "${seenDomainsFile}" ]]; then
        while IFS= read -r domainKey; do
            [[ -n "${domainKey}" ]] && seenDomains["${domainKey}"]=1
        done <"${seenDomainsFile}"
    fi
    while IFS= read -r record; do
        IFS=$'\t' read -r ip origin domain issuer _geo <<<"${record}"
        if ! realityTargetScannerRecordAllowed "${domain}"; then
            skipped=$((skipped + 1))
            continue
        fi
        domainKey=${domain,,}
        if [[ -v "seenDomains[${domainKey}]" ]]; then
            duplicateCount=$((duplicateCount + 1))
            skipped=$((skipped + 1))
            continue
        fi
        seenDomains["${domainKey}"]=1
        if [[ -n "${seenDomainsFile}" ]]; then
            printf '%s\n' "${domainKey}" >>"${seenDomainsFile}" || return 1
        fi
        candidates+=("${record}")
    done <"${normalizedFile}"
    totalRecords=${#candidates[@]}
    padmCreateTempPath resultLinesFile || { padmRemoveCleanupPath "${normalizedFile}"; return 1; }
    padmCreateTempPath failedTargetsFile || { padmRemoveCleanupPath "${normalizedFile}"; padmRemoveCleanupPath "${resultLinesFile}"; return 1; }
    padmCreateTempPath probeDir -d || { padmRemoveCleanupPath "${normalizedFile}"; padmRemoveCleanupPath "${resultLinesFile}"; padmRemoveCleanupPath "${failedTargetsFile}"; return 1; }
    asnCacheFile="${probeDir}/asn-cache.tsv"
    : >"${asnCacheFile}"
    if (( totalRecords > 0 )); then
        realityTargetProgressLine "RealiTLScanner TLS/CDN 二次检测 0/${totalRecords} 并发：${maxJobs} 已耗时：0s"
        lastProgressAt=${importStart}
    fi
    while (( index < totalRecords || running > 0 )); do
        while (( index < totalRecords && running < maxJobs )); do
            IFS=$'\t' read -r ip origin domain issuer _geo <<<"${candidates[${index}]}"
            target=$(formatRealityTarget "${domain}" 443)
            jobFile="${probeDir}/${index}.result"
            doneFile="${jobFile}.done"
            (
                probeRealityScannerCandidate "${detector}" "${ip}" "${domain}" "${issuer}" "${currentAsn}" "${currentOrg}" "${networkMode}" "${origin}" "${asnCacheFile}" >"${jobFile}"
                : >"${doneFile}"
            ) &
            jobPids[${index}]=$!
            jobFiles[${index}]=${jobFile}
            jobDoneFiles[${index}]=${doneFile}
            jobTargets[${index}]=${target}
            jobDomains[${index}]=${domain}
            activeSlots+=("${index}")
            index=$((index + 1))
            running=$((running + 1))
        done

        madeProgress=false
        for activeIndex in "${!activeSlots[@]}"; do
            slot=${activeSlots[${activeIndex}]}
            pid=${jobPids[${slot}]}
            if [[ -f "${jobDoneFiles[${slot}]}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
                wait "${pid}" 2>/dev/null || true
                jobPids[${slot}]=
                unset "activeSlots[${activeIndex}]"
                running=$((running - 1))
                processed=$((processed + 1))
                currentDomain=${jobDomains[${slot}]}
                madeProgress=true
            fi
        done
        activeSlots=("${activeSlots[@]}")

        if [[ "${madeProgress}" == "false" && "${running}" -gt 0 ]]; then
            command sleep 0.05
            continue
        fi
        if [[ "${madeProgress}" == "true" ]]; then
            now=$(date +%s)
            if (( lastProgressAt == 0 || now - lastProgressAt >= 10 || processed == totalRecords )); then
                realityTargetProgressLine "RealiTLScanner TLS/CDN 二次检测 ${processed}/${totalRecords} 当前：${currentDomain:-未知} 并发：${maxJobs} 已耗时：$((now - importStart))s"
                lastProgressAt=${now}
            fi
        fi
    done

    for ((slot = 0; slot < totalRecords; slot++)); do
        probeRecord=
        [[ -f "${jobFiles[${slot}]}" ]] && probeRecord=$(<"${jobFiles[${slot}]}")
        probeStatus=${probeRecord%%$'\t'*}
        probePayload=${probeRecord#*$'\t'}
        case "${probeStatus}" in
        OK)
            if [[ -n "${probePayload}" ]]; then
                printf '%s\n' "${probePayload}" >>"${resultLinesFile}"
                score=$(realityTargetResultField "${probePayload}" 10)
                cdnRisk=$(realityTargetResultField "${probePayload}" 5)
                case "${score}" in
                A)
                    if [[ "${cdnRisk}" == "no" ]]; then
                        countA=$((countA + 1))
                        imported=$((imported + 1))
                    else
                        countFail=$((countFail + 1))
                        skipped=$((skipped + 1))
                    fi
                    ;;
                B) countB=$((countB + 1)); skipped=$((skipped + 1)) ;;
                C) countC=$((countC + 1)); skipped=$((skipped + 1)) ;;
                *) countFail=$((countFail + 1)); skipped=$((skipped + 1)) ;;
                esac
            else
                printf '%s\n' "${jobTargets[${slot}]}" >>"${failedTargetsFile}"
                countFail=$((countFail + 1))
                skipped=$((skipped + 1))
            fi
            ;;
        FAIL)
            printf '%s\n' "${probePayload:-${jobTargets[${slot}]}}" >>"${failedTargetsFile}"
            countFail=$((countFail + 1))
            skipped=$((skipped + 1))
            ;;
        *)
            printf '%s\n' "${jobTargets[${slot}]}" >>"${failedTargetsFile}"
            countFail=$((countFail + 1))
            skipped=$((skipped + 1))
            ;;
        esac
    done
    writeRealityTargetResultLines "${resultLinesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    padmRemoveCleanupPath "${normalizedFile}"
    padmRemoveCleanupPath "${resultLinesFile}"
    padmRemoveCleanupPath "${failedTargetsFile}"
    padmRemoveCleanupPath "${probeDir}"
    if [[ -n "${summaryVar}" ]]; then
        printf -v "${summaryVar}" '%s\t%s\t%s\t%s\t%s\t%s' "${imported}" "${skipped}" "${countA}" "${countB}" "${countC}" "${countFail}"
    fi
    realityTargetStatusBlock green "RealiTLScanner 导入" "TLS/CDN 二次检测: ${totalRecords}" "并发: ${maxJobs}" "重复域名: ${duplicateCount}" "可选 A: ${imported}" "非候选/跳过: ${skipped}" "A: ${countA}" "B记录: ${countB}" "C记录: ${countC}" "风险/FAIL: ${countFail}" "耗时: $(($(date +%s) - importStart))s"
}


realityScannerRangeFromIp() {
    local ip=$1
    local cidr=$2
    local a b c d block baseC baseD
    [[ "${ip}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    a=${BASH_REMATCH[1]}
    b=${BASH_REMATCH[2]}
    c=${BASH_REMATCH[3]}
    d=${BASH_REMATCH[4]}
    case "${cidr}" in
    28)
        baseD=$((d / 16 * 16))
        printf '%s.%s.%s.%s/28' "${a}" "${b}" "${c}" "${baseD}"
        ;;
    24)
        printf '%s.%s.%s.0/24' "${a}" "${b}" "${c}"
        ;;
    18 | 19 | 20 | 21 | 22 | 23)
        block=$((1 << (24 - cidr)))
        baseC=$((c / block * block))
        printf '%s.%s.%s.0/%s' "${a}" "${b}" "${baseC}" "${cidr}"
        ;;
    *)
        return 1
        ;;
    esac
}

selectRealityScannerRange() {
    local currentIp=$1
    local selectRange manualRange range28 range24 range23 range22 range21 range20 range19 range18
    selectedRealityScannerRange=
    if [[ -n "${currentIp}" ]]; then
        range28=$(realityScannerRangeFromIp "${currentIp}" 28 || true)
        range24=$(realityScannerRangeFromIp "${currentIp}" 24 || true)
        range23=$(realityScannerRangeFromIp "${currentIp}" 23 || true)
        range22=$(realityScannerRangeFromIp "${currentIp}" 22 || true)
        range21=$(realityScannerRangeFromIp "${currentIp}" 21 || true)
        range20=$(realityScannerRangeFromIp "${currentIp}" 20 || true)
        range19=$(realityScannerRangeFromIp "${currentIp}" 19 || true)
        range18=$(realityScannerRangeFromIp "${currentIp}" 18 || true)
    fi
    echoContent title "\n┌─ RealiTLScanner 扫描范围选择 ───────────────────────"
    menuRecommendedItem 1 "默认 /24（254 台）" "${range24:-无法自动计算，需手动输入}"
    menuItem 2 "快速 /28（14 台）" "${range28:-无法自动计算，需手动输入}"
    menuItem 3 "扩大 /23（510 台）" "${range23:-无法自动计算，需手动输入}"
    menuItem 4 "扩大 /22（1022 台）" "${range22:-无法自动计算，需手动输入}"
    menuItem 5 "扩大 /21（2046 台）" "${range21:-无法自动计算，需手动输入}"
    menuItem 6 "扩大 /20（4094 台）" "${range20:-无法自动计算，需手动输入}"
    menuItem 7 "扩大 /19（8190 台）" "${range19:-无法自动计算，需手动输入}"
    menuItem 8 "扩大 /18（16382 台）" "${range18:-无法自动计算，需手动输入}"
    menuItem 9 "手动输入" "输入自定义 IP/CIDR、IP、域名或 RealiTLScanner 支持的 addr"
    menuClose
    autoRead reality_scanner_range_menu "请选择扫描范围[默认1]:" selectRange
    case "${selectRange:-1}" in
    1)
        selectedRealityScannerRange=${range24}
        ;;
    2)
        selectedRealityScannerRange=${range28}
        ;;
    3)
        selectedRealityScannerRange=${range23}
        ;;
    4)
        selectedRealityScannerRange=${range22}
        ;;
    5)
        selectedRealityScannerRange=${range21}
        ;;
    6)
        selectedRealityScannerRange=${range20}
        ;;
    7)
        selectedRealityScannerRange=${range19}
        ;;
    8)
        selectedRealityScannerRange=${range18}
        ;;
    9)
        autoRead reality_scanner_range_manual "请输入扫描范围:" manualRange
        selectedRealityScannerRange=${manualRange}
        ;;
    *)
        return 1
        ;;
    esac
}

ensureRealityScannerBinary() {
    local scannerDir=$1
    local scannerBin=$2
    local assetName=
    local stageDir=
    local stageBin=

    padmIsSafeAbsolutePath "${scannerDir%/}" || return 1
    padmIsSafeAbsolutePath "${scannerBin}" || return 1
    [[ "${scannerBin}" == "${scannerDir%/}/"* ]] || return 1

    case "$(uname -m)" in
    amd64 | x86_64) assetName="RealiTLScanner-linux-amd64" ;;
    armv8 | aarch64) assetName="RealiTLScanner-linux-arm64" ;;
    *) return 1 ;;
    esac

    if [[ -x "${scannerBin}" ]]; then
        return 0
    fi

    mkdir -p "${scannerDir}" || return 1
    padmCreateTempPath stageDir -d "${scannerDir%/}/.scanner-download.XXXXXX" || return 1
    stageBin="${stageDir}/${assetName}"
    realityTargetStatusBlock yellow "RealiTLScanner 下载" "正在下载官方 Release 二进制"
    if ! downloadGitHubReleaseAsset -P "${stageDir}" "XTLS/RealiTLScanner" latest "${assetName}"; then
        realityTargetStatusBlock red "RealiTLScanner 下载" "下载 Release 资产失败: ${assetName}"
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    if [[ ! -f "${stageBin}" ]]; then
        realityTargetStatusBlock red "RealiTLScanner 下载" "Release 资产不存在: ${assetName}"
        padmRemoveCleanupPath "${stageDir}"
        return 1
    fi
    mv "${stageBin}" "${scannerBin}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    chmod 755 "${scannerBin}" || { padmRemoveCleanupPath "${stageDir}"; return 1; }
    padmRemoveCleanupPath "${stageDir}"
}

runRealityScannerQuietly() {
    local outputFile=$1
    shift
    "$@" >"${outputFile}.log" 2>&1
}

runRealityScannerRange() {
    local scanRange=$1
    local scannerDir scannerBin outputFile startAt elapsed scannerStatus scannerPid
    [[ -n "${scanRange}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "扫描范围为空"
        return 1
    }
    scannerDir=$(realityTargetTmpPath RealiTLScanner)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
    outputFile=$(realityScannerOutputPath "$(date +%s)")
    startAt=$(date +%s)
    realityTargetProgressLine "RealiTLScanner 扫描范围：${scanRange} 已耗时：0s"
    runRealityScannerQuietly "${outputFile}" "${scannerBin}" -addr "${scanRange}" -thread 20 -timeout 3 -out "${outputFile}" &
    scannerPid=$!
    while kill -0 "${scannerPid}" >/dev/null 2>&1; do
        sleep 10
        realityTargetProgressLine "RealiTLScanner 扫描范围：${scanRange} 已耗时：$(($(date +%s) - startAt))s"
    done
    scannerStatus=0
    wait "${scannerPid}" || scannerStatus=$?
    if [[ ${scannerStatus} -ne 0 ]]; then
        if [[ ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock red "RealiTLScanner 扫描" "执行失败，且未生成有效结果文件" "日志: ${outputFile}.log"
            return 1
        fi
        realityTargetStatusBlock yellow "RealiTLScanner 扫描" "返回非零状态，但已生成结果文件" "继续导入结果" "日志: ${outputFile}.log"
    fi
    elapsed=$(( $(date +%s) - startAt ))
    realityTargetStatusBlock green "RealiTLScanner 扫描" "扫描完成" "耗时: ${elapsed}s" "结果: ${outputFile}"
    importRealityScannerResults "${outputFile}"
}

runRealityScannerTargetFile() {
    local targetFile=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local scannerDir scannerBin outputFile batchFile seenDomainsFile startAt elapsed scannerStatus scannerPid total batchSize batchIndex processed batchCount totalStartAt totalElapsed importSummary batchImported batchSkipped batchA batchB batchC batchFail totalImported=0 totalSkipped=0 totalA=0 totalB=0 totalC=0 totalFail=0
    [[ -f "${targetFile}" && -s "${targetFile}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "目标列表为空"
        return 1
    }
    scannerDir=$(realityTargetTmpPath RealiTLScanner)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
    padmCreateTempPath seenDomainsFile || return 1
    total=$(wc -l <"${targetFile}" | tr -d ' ')
    batchSize=${total}
    (( total >= 1000 )) && batchSize=1000
    (( total >= 5000 )) && batchSize=2000
    batchIndex=0
    processed=0
    totalStartAt=$(date +%s)
    while (( processed < total )); do
        batchIndex=$((batchIndex + 1))
        padmCreateTempPath batchFile || return 1
        sed -n "$((processed + 1)),$((processed + batchSize))p" "${targetFile}" >"${batchFile}"
        batchCount=$(wc -l <"${batchFile}" | tr -d ' ')
        [[ "${batchCount}" -gt 0 ]] || {
            padmRemoveCleanupPath "${batchFile}"
            break
        }
        outputFile=$(realityScannerOutputPath "$(date +%s)" "sample-${batchIndex}")
        startAt=$(date +%s)
        realityTargetProgressLine "RealiTLScanner 抽样扫描进度：$((processed + 1))-$((processed + batchCount))/${total} 已耗时：0s"
        runRealityScannerQuietly "${outputFile}" "${scannerBin}" -in "${batchFile}" -thread 20 -timeout 3 -out "${outputFile}" &
        scannerPid=$!
        while kill -0 "${scannerPid}" >/dev/null 2>&1; do
            sleep 10
            realityTargetProgressLine "RealiTLScanner 抽样扫描进度：$((processed + 1))-$((processed + batchCount))/${total} 已耗时：$(($(date +%s) - startAt))s"
        done
        scannerStatus=0
        wait "${scannerPid}" || scannerStatus=$?
        padmRemoveCleanupPath "${batchFile}"
        if [[ ${scannerStatus} -ne 0 && ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock yellow "RealiTLScanner 扫描" "抽样批次失败且无结果" "进度: $((processed + batchCount))/${total}" "继续扫描剩余目标" "日志: ${outputFile}.log"
            processed=$((processed + batchCount))
            continue
        fi
        elapsed=$(( $(date +%s) - startAt ))
        processed=$((processed + batchCount))
        realityTargetStatusBlock green "RealiTLScanner 扫描" "抽样批次完成" "进度: ${processed}/${total}" "耗时: ${elapsed}s" "结果: ${outputFile}"
        if [[ -s "${outputFile}" ]]; then
            importRealityScannerResults "${outputFile}" "${currentAsn}" "${currentOrg}" importSummary same_asn "${seenDomainsFile}"
            IFS=$'\t' read -r batchImported batchSkipped batchA batchB batchC batchFail <<<"${importSummary}"
            totalImported=$((totalImported + batchImported))
            totalSkipped=$((totalSkipped + batchSkipped))
            totalA=$((totalA + batchA))
            totalB=$((totalB + batchB))
            totalC=$((totalC + batchC))
            totalFail=$((totalFail + batchFail))
        fi
    done
    padmRemoveCleanupPath "${seenDomainsFile}"
    totalElapsed=$(( $(date +%s) - totalStartAt ))
    realityTargetStatusBlock green "RealiTLScanner 抽样扫描汇总" "扫描目标: ${total}" "可选 A: ${totalImported}" "非候选/跳过: ${totalSkipped}" "A: ${totalA}" "B记录: ${totalB}" "C记录: ${totalC}" "风险/FAIL: ${totalFail}" "总耗时: ${totalElapsed}s"
}


runRealityScannerPrefixFile() {
    local prefixFile=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local scannerDir scannerBin outputFile seenDomainsFile startAt elapsed scannerStatus scannerPid prefix total index=0
    [[ -f "${prefixFile}" && -s "${prefixFile}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "prefix 列表为空"
        return 1
    }
    scannerDir=$(realityTargetTmpPath RealiTLScanner)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
    padmCreateTempPath seenDomainsFile || return 1
    total=$(wc -l <"${prefixFile}" | tr -d ' ')
    while IFS= read -r prefix; do
        [[ -n "${prefix}" ]] || continue
        index=$((index + 1))
        outputFile=$(realityScannerOutputPath "$(date +%s)" "${index}")
        startAt=$(date +%s)
        realityTargetProgressLine "RealiTLScanner 扫描 prefix ${index}/${total}：${prefix} 已耗时：0s"
        runRealityScannerQuietly "${outputFile}" "${scannerBin}" -addr "${prefix}" -thread 20 -timeout 3 -out "${outputFile}" &
        scannerPid=$!
        while kill -0 "${scannerPid}" >/dev/null 2>&1; do
            sleep 10
            realityTargetProgressLine "RealiTLScanner 扫描 prefix ${index}/${total}：${prefix} 已耗时：$(($(date +%s) - startAt))s"
        done
        scannerStatus=0
        wait "${scannerPid}" || scannerStatus=$?
        if [[ ${scannerStatus} -ne 0 && ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock yellow "RealiTLScanner 扫描" "prefix 扫描失败且无结果: ${prefix}" "继续扫描剩余 prefix" "日志: ${outputFile}.log"
            continue
        fi
        elapsed=$(( $(date +%s) - startAt ))
        realityTargetStatusBlock green "RealiTLScanner 扫描" "prefix 完成: ${prefix}" "进度: ${index}/${total}" "耗时: ${elapsed}s" "结果: ${outputFile}"
        [[ -s "${outputFile}" ]] && importRealityScannerResults "${outputFile}" "${currentAsn}" "${currentOrg}" "" same_asn "${seenDomainsFile}"
    done <"${prefixFile}"
    padmRemoveCleanupPath "${seenDomainsFile}"
}

runRealityScannerAdvanced() {
    local currentIp scanRange confirm selectedRealityScannerRange
    currentIp=$(realityTargetPublicIPv4 2>/dev/null || true)
    realityTargetStatusBlock yellow "RealiTLScanner 风险提示" "会扫描目标网段 TLS 证书" "作者建议本地运行；云端扫描可能导致 VPS 被标记"
    autoRead reality_scanner_confirm "确认在本机运行高级扫描？[y/n]:" confirm
    [[ "${confirm}" == "y" ]] || return 1
    selectRealityScannerRange "${currentIp}" || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "扫描范围选择无效"
        return 1
    }
    scanRange=${selectedRealityScannerRange}
    runRealityScannerRange "${scanRange}"
}

runRealityScannerSameAsnPrefixes() {
    local networkProfile currentIp rest currentAsn currentOrg allPrefixFile confirm selectedRealityScannerPrefixFile selectedRealityScannerRange selectedRealityAsnPrefixTotal selectedRealityAsnAddressTotal selectedRealityAsnSampleSize selectedRealityAsnFullScan
    if ! networkProfile=$(currentRealityNetworkProfile); then
        realityTargetStatusBlock yellow "同 ASN 前缀扫描" "无法识别本机公网 ASN"
        return 1
    fi
    currentIp=${networkProfile%%$'\t'*}
    rest=${networkProfile#*$'\t'}
    currentAsn=${rest%%$'\t'*}
    currentOrg=${rest#*$'\t'}
    realityTargetStatusBlock yellow "同 ASN 前缀扫描" "本机公网网络: ${currentIp} ${currentAsn} ${currentOrg}" "正在从 RIPEstat 拉取 announced prefixes"
    padmCreateTempPath allPrefixFile || return 1
    if ! fetchRealityAsnPrefixes "${currentAsn}" >"${allPrefixFile}" || [[ ! -s "${allPrefixFile}" ]]; then
        padmRemoveCleanupPath "${allPrefixFile}"
        realityTargetStatusBlock red "同 ASN 前缀扫描" "未获取到 ${currentAsn} 的 IPv4 前缀"
        return 1
    fi
    if ! selectRealityAsnScanPlan "${currentAsn}" "${allPrefixFile}"; then
        padmRemoveCleanupPath "${allPrefixFile}"
        return 1
    fi
    padmRemoveCleanupPath "${allPrefixFile}"
    realityTargetStatusBlock yellow "RealiTLScanner 风险提示" "扫描计划: ${selectedRealityScannerRange}" "公告 prefix 数: ${selectedRealityAsnPrefixTotal}" "本次将扫描 IP: ${selectedRealityAsnAddressTotal}" "会扫描目标网段 TLS 证书；云端扫描可能导致 VPS 被标记"
    autoRead reality_asn_scanner_confirm "确认开始扫描？[y/n]:" confirm
    if [[ "${confirm}" != "y" ]]; then
        padmRemoveCleanupPath "${selectedRealityScannerPrefixFile}"
        return 1
    fi
    if [[ "${selectedRealityAsnFullScan}" == "true" ]]; then
        runRealityScannerPrefixFile "${selectedRealityScannerPrefixFile}" "${currentAsn}" "${currentOrg}"
        padmRemoveCleanupPath "${selectedRealityScannerPrefixFile}"
    else
        runRealityScannerTargetFile "${selectedRealityScannerPrefixFile}" "${currentAsn}" "${currentOrg}"
        padmRemoveCleanupPath "${selectedRealityScannerPrefixFile}"
    fi
}

showRealityTargetCertificateChain() {
    local target=$1
    local parsed host port tmpDir sClientOutput certCount=0 certFile subject issuer notBefore notAfter san fingerprint leafSubject leafIssuer leafSan intermediateSubject intermediateIssuer intermediateNotAfter upperSubject upperIssuer upperNotAfter analysis
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    if ! command -v openssl >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 证书链" "未找到 openssl，无法查看证书链"
        return 1
    fi
    padmCreateTempPath tmpDir -d || return 1
    if ! sClientOutput=$(timeout 15 openssl s_client -connect "${host}:${port}" -servername "${host}" -showcerts </dev/null 2>/dev/null); then
        padmRemoveCleanupPath "${tmpDir}"
        realityTargetStatusBlock red "REALITY 证书链" "证书链获取失败: ${target}"
        return 1
    fi
    printf '%s\n' "${sClientOutput}" | awk -v dir="${tmpDir}" '
        /-----BEGIN CERTIFICATE-----/ {count++; file=sprintf("%s/cert%d.pem", dir, count)}
        file != "" {print > file}
        /-----END CERTIFICATE-----/ {close(file); file=""}
    '
    for certFile in "${tmpDir}"/cert*.pem; do
        [[ -e "${certFile}" ]] || continue
        certCount=$((certCount + 1))
        subject=$(openssl x509 -in "${certFile}" -noout -subject 2>/dev/null | sed 's/^subject=//; s/, /, /g')
        issuer=$(openssl x509 -in "${certFile}" -noout -issuer 2>/dev/null | sed 's/^issuer=//; s/, /, /g')
        notBefore=$(openssl x509 -in "${certFile}" -noout -startdate 2>/dev/null | sed 's/^notBefore=//')
        notAfter=$(openssl x509 -in "${certFile}" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
        fingerprint=$(openssl x509 -in "${certFile}" -noout -fingerprint -sha256 2>/dev/null | sed 's/^sha256 Fingerprint=//')
        san=$(openssl x509 -in "${certFile}" -noout -ext subjectAltName 2>/dev/null | awk 'NR > 1 {gsub(/^ +/, ""); gsub(/DNS:/, ""); print}' | paste -sd ' ' -)
        case "${certCount}" in
        1)
            leafSubject=${subject}
            leafIssuer=${issuer}
            leafSan=${san:-无 SAN}
            ;;
        2)
            intermediateSubject=${subject}
            intermediateIssuer=${issuer}
            intermediateNotAfter=${notAfter}
            ;;
        3)
            upperSubject=${subject}
            upperIssuer=${issuer}
            upperNotAfter=${notAfter}
            ;;
        esac
        realityTargetStatusBlock skyBlue "REALITY 证书链 #${certCount}" "Subject: ${subject}" "Issuer: ${issuer}" "有效期: ${notBefore} → ${notAfter}" "SAN: ${san:-无 SAN}" "SHA256: ${fingerprint}"
    done
    padmRemoveCleanupPath "${tmpDir}"
    if [[ ${certCount} -eq 0 ]]; then
        realityTargetStatusBlock red "REALITY 证书链" "未解析到证书: ${target}"
        return 1
    fi
    analysis="链长 ${certCount}"
    if [[ " ${leafSan} " == *" ${host}"* || "${leafSubject}" == *"CN=${host}"* ]]; then
        analysis+="，SAN/Subject 匹配 ${host}"
    else
        analysis+="，SAN/Subject 未确认匹配 ${host}"
    fi
    [[ -n "${leafIssuer}" ]] && analysis+="，叶子证书由 ${leafIssuer} 签发"
    if [[ ${certCount} -ge 3 ]]; then
        analysis+="；中间链 ${intermediateSubject:-未知} → ${intermediateIssuer:-未知}，上级链 ${upperSubject:-未知} → ${upperIssuer:-未知}"
    elif [[ ${certCount} -eq 2 ]]; then
        analysis+="；中间链 ${intermediateSubject:-未知} → ${intermediateIssuer:-未知}"
    fi
    realityTargetStatusBlock green "REALITY 证书链分析" "${analysis}" "叶子 SAN: ${leafSan:-无 SAN}" "中间证书有效期至: ${intermediateNotAfter:-未知}" "上级链有效期至: ${upperNotAfter:-未知}"
}

showRealityTargetQuality() {
    local target=$1
    local detector='' probeResult cdnRisk score pqc certLength tls13 note checkedAt detectStart detectSeconds
    local parsed host port sni ip asn asOrg networkProfile rest currentAsn='' currentOrg='' networkMatch=unknown color=green cachedLine='' name category
    detector=$(realityTargetDetector 2>/dev/null || true)
    if [[ -z "${detector}" ]] && ! command -v openssl >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 目标站检测" "缺少 Xray/OpenSSL，无法在线检测"
        return 1
    fi
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    target=$(formatRealityTarget "${host}" "${port}")
    cachedLine=$(realityTargetResultLine "${target}" 2>/dev/null || true)
    sni=${host}
    name=${host}
    category=manual
    if [[ -n "${cachedLine}" ]]; then
        sni=$(realityTargetResultField "${cachedLine}" 2)
        name=$(realityTargetResultField "${cachedLine}" 3)
        category=$(realityTargetResultField "${cachedLine}" 4)
    elif [[ "${host}" == "${realityTargetHost:-}" ]]; then
        sni=${realitySNI:-${host}}
    fi
    realityTargetStatusBlock yellow "REALITY 目标站检测" "正在检测全部 A/AAAA: ${target}" "SNI: ${sni}"
    detectStart=$(date +%s)
    if ! probeResult=$(probeRealityTargetEndpoint "${detector}" "${target}" "${sni}"); then
        realityTargetStatusBlock red "REALITY 目标站检测" "目标地址解析失败: ${target}"
        return 1
    fi
    IFS=$'\t' read -r cdnRisk ip asn asOrg score pqc certLength tls13 note <<<"${probeResult}"
    if networkProfile=$(currentRealityNetworkProfile 2>/dev/null); then
        rest=${networkProfile#*$'\t'}
        currentAsn=${rest%%$'\t'*}
        currentOrg=${rest#*$'\t'}
        if [[ "${asn}" == "${currentAsn}" ]]; then
            networkMatch=same_asn
        elif [[ "${asn}" != "unknown" ]] && realityTargetProviderMatches "${currentOrg}" "${asOrg}"; then
            networkMatch=same_provider
        elif [[ "${asn}" != "unknown" ]]; then
            networkMatch=different_network
        fi
    fi
    checkedAt=$(date +%s)
    detectSeconds=$((checkedAt - detectStart))
    writeRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}" || return 1
    [[ "${cdnRisk}" == "no" && "${score}" != "FAIL" ]] || color=red
    [[ "${cdnRisk}" == "no" && ( "${score}" == "B" || "${score}" == "C" ) ]] && color=yellow
    realityTargetStatusBlock "${color}" "REALITY 目标站检测" "cdn_risk: ${cdnRisk}" "评分: $(realityTargetScoreStyle "${score}")" "X25519MLKEM768: ${pqc}" "TLS1.3: ${tls13}" "证书链长度: ${certLength}" "目标地址: ${ip} ${asn} ${asOrg}" "网络关系: ${networkMatch}" "耗时: ${detectSeconds}s" "结论: ${note}" "仅检测告警，未自动切换配置"
    [[ "${cdnRisk}" == "no" && "${score}" != "FAIL" ]]
}

showRealityTargetQualityActions() {
    local target=$1
    local action confirm
    echoContent title "\n┌─ REALITY 目标站后续操作 ─────────────────────────────"
    menuItem 1 "查看/切换 A 级目标" "打开目标库中的 A 级目标并切换"
    menuItem 2 "加入目标站黑名单" "后续不参与目标库刷新和扫描导入"
    menuReturnItem 3 "返回" "回到 REALITY 目标站管理"
    menuClose
    autoRead reality_target_quality_action "请选择后续操作[默认3=返回]:" action
    case "${action:-3}" in
    1)
        if selectRealityTargetFromScanResults; then
            autoConfirm reality_target_confirm "确认切换到 ${realityTargetHost}:${realityTargetPort}，SNI=${realitySNI}？" n confirm
            if [[ "${confirm}" == "y" ]]; then
                changeInstalledRealityTarget "${realityTargetHost}:${realityTargetPort}" "${realitySNI}"
            fi
        fi
        ;;
    2)
        autoConfirm reality_target_block_confirm "确认将 ${target} 加入目标站黑名单？" n confirm
        [[ "${confirm}" == "y" ]] && addRealityTargetBlockedCandidate "${target}" "manual_reject_after_quality_check"
        ;;
    3|r|R|"")
        return 0
        ;;
    *)
        coreSelectionErrorCard "选择错误"
        ;;
    esac
}

showRealityTargetCachedQuality() {
    local target=$1
    showRealityTargetQuality "${target}" || return 1
    showRealityTargetCertificateChain "${target}" || true
    showRealityTargetQualityActions "${target}" || true
}

realityTargetFilterTitle() {
    case "$1" in
    same_asn|同ASN) printf '同 ASN\n' ;;
    same_provider|同提供商|相近网络) printf '同提供商\n' ;;
    local_network|同网络|本机网络) printf '同网络\n' ;;
    scanner|扫描)
        printf 'RealiTLScanner\n' ;;
    all|全部|*) printf '全部\n' ;;
    esac
}

realityTargetScanResultFilterMatches() {
    local score=$1
    local networkMatch=$2
    local filter=${3:-all}
    local category=${4:-}
    [[ "${score}" == "A" ]] || return 1
    case "${filter}" in
    same_asn|同ASN)
        [[ "${networkMatch}" == "same_asn" ]]
        ;;
    same_provider|同提供商|相近网络)
        [[ "${networkMatch}" == "same_provider" ]]
        ;;
    local_network|同网络|本机网络)
        [[ "${networkMatch}" == "same_asn" || "${networkMatch}" == "same_provider" ]]
        ;;
    scanner|扫描)
        [[ "${category}" == "scanner" ]]
        ;;
    all|全部|*)
        return 0
        ;;
    esac
}

selectRealityTargetScanResultFilter() {
    local selected
    {
        echoContent title "\n┌─ REALITY A 级目标筛选 ─────────────────────────────"
        menuItem 1 "全部" "显示目标库内所有 A 级目标"
        menuItem 2 "同 ASN" "只看与本机 ASN 相同的 A 级目标"
        menuItem 3 "同提供商" "只看同一提供商的 A 级目标"
        menuItem 4 "同网络" "显示同 ASN 和同提供商的 A 级目标"
        menuItem 5 "RealiTLScanner" "只看网段扫描发现的 A 级目标"
        menuReturnItem 6 "返回" "回到 REALITY 目标站管理"
        menuClose
    } >&2
    autoRead reality_target_result_filter "请选择筛选条件[默认1=全部]：" selected
    case "${selected:-1}" in
    1) printf 'all\n' ;;
    2) printf 'same_asn\n' ;;
    3) printf 'same_provider\n' ;;
    4) printf 'local_network\n' ;;
    5) printf 'scanner\n' ;;
    6|r|R) printf 'return\n' ;;
    *) return 1 ;;
    esac
}

showRealityTargetScanResults() {
    local filter=${1:-all}
    local mode=${2:-interactive}
    local page=${3:-1} pageSize=${REALITY_TARGET_RESULT_PAGE_SIZE:-10} total maxPage choice
    local line itemIndex=0 pageIndex=1 start end target sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note checkedTime titleFilter selectedLine selectedTarget selectedSni parsed absoluteIndex
    local -a sortedResults=()
    # Keep one sorted snapshot while paging; results change only after leaving this menu.
    mapfile -t sortedResults < <(sortedRealityTargetResults)
    if [[ "${#sortedResults[@]}" -eq 0 ]]; then
        realityTargetStatusBlock yellow "REALITY A 级目标" "暂无 A 级目标"
        return 1
    fi
    if [[ "${filter}" == "return" ]]; then
        return 0
    fi
    while true; do
        total=0
        for line in "${sortedResults[@]}"; do
            IFS=$'\t' read -r _target _sni _name category _cdnRisk _ip _asn _asOrg networkMatch score _pqc _certLength _tls13 _checkedAt _note <<<"${line}"
            realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" && total=$((total + 1))
        done
        maxPage=$(( (total + pageSize - 1) / pageSize ))
        (( maxPage < 1 )) && maxPage=1
        (( page > maxPage )) && page=${maxPage}
        (( page < 1 )) && page=1
        start=$(( (page - 1) * pageSize + 1 ))
        end=$(( page * pageSize ))
        titleFilter=$(realityTargetFilterTitle "${filter}")
        echoContent title "\n┌─ REALITY A 级目标：${titleFilter} ───────────────────────────────"
        menuLine "筛选条件：${filter}；第 ${page}/${maxPage} 页；总数：${total}；n 下一页；p 上一页；f 重新筛选；r 返回"
        itemIndex=0
        pageIndex=1
        for line in "${sortedResults[@]}"; do
            IFS=$'\t' read -r target sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note <<<"${line}"
            realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" || continue
            itemIndex=$((itemIndex + 1))
            (( itemIndex < start || itemIndex > end )) && continue
            checkedTime=$(date -d "@${checkedAt}" "+%F %T" 2>/dev/null || printf '%s' "${checkedAt}")
            menuItem "${pageIndex}" "${target}" "${score} | X25519MLKEM768=${pqc} | cert=${certLength} | TLS1.3=${tls13} | network=${networkMatch}"
            menuLine "    cdn_risk=${cdnRisk} checked=${checkedTime} SNI=${sni} IP=${ip} ASN=${asn} ${asOrg}"
            menuLine "    name=${name} category=${category}"
            [[ -n "${note}" ]] && menuLine "    ${note}"
            pageIndex=$((pageIndex + 1))
        done
        [[ "${total}" == "0" ]] && menuLine "当前筛选没有 A 级目标"
        menuClose
        if [[ "${mode}" == "once" ]]; then
            return 0
        fi
        autoRead reality_target_result_page "请选择本页编号切换，n/p/f/r，回车返回:" choice
        case "${choice}" in
        n|N)
            (( page < maxPage )) && page=$((page + 1))
            ;;
        p|P)
            (( page > 1 )) && page=$((page - 1))
            ;;
        f|F)
            filter=$(selectRealityTargetScanResultFilter) || return 1
            [[ "${filter}" == "return" ]] && return 0
            page=1
            ;;
        r|R|"")
            return 0
            ;;
        *)
            if [[ "${choice}" =~ ^[0-9]+$ ]]; then
                absoluteIndex=$(( (page - 1) * pageSize + choice ))
                selectedLine=
                itemIndex=0
                for line in "${sortedResults[@]}"; do
                    IFS=$'\t' read -r _target _sni _name category _cdnRisk _ip _asn _asOrg networkMatch score _pqc _certLength _tls13 _checkedAt _note <<<"${line}"
                    realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" || continue
                    itemIndex=$((itemIndex + 1))
                    if [[ "${itemIndex}" == "${absoluteIndex}" ]]; then
                        selectedLine=${line}
                        break
                    fi
                done
                if [[ -z "${selectedLine}" ]]; then
                    errorCard "本页编号无效，请重新选择"
                    continue
                fi
                selectedTarget=$(realityTargetResultField "${selectedLine}" 1)
                selectedSni=$(realityTargetResultField "${selectedLine}" 2)
                parsed=$(parseHostPort "${selectedTarget}" 443)
                realityTargetHost=${parsed%:*}
                realityTargetPort=${parsed##*:}
                realitySNI=${AUTO_REALITY_SERVER_NAME:-${selectedSni:-${realityTargetHost}}}
                return 2
            fi
            errorCard "输入无效，请输入编号或 n/p/f/r"
            ;;
        esac
    done
}

realityTargetResultLineByFilteredIndex() {
    local filter=$1
    local wanted=$2
    local line score networkMatch index=0
    [[ "${wanted}" =~ ^[0-9]+$ ]] || return 1
    while IFS= read -r line; do
        IFS=$'\t' read -r _target _sni _name category _cdnRisk _ip _asn _asOrg networkMatch score _pqc _certLength _tls13 _checkedAt _note <<<"${line}"
        realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" || continue
        index=$((index + 1))
        if [[ "${index}" == "${wanted}" ]]; then
            printf '%s\n' "${line}"
            return 0
        fi
    done < <(sortedRealityTargetResults)
    return 1
}

selectRealityTargetFromScanResults() {
    showRealityTargetScanResults
    [[ "$?" == "2" ]]
}

probeRealityTargetRecord() {
    local detector=$1
    local record=$2
    local currentAsn=$3
    local currentOrg=$4
    local asnCacheFile=${5:-}
    local target sni name category cdnRisk _oldIp _oldAsn _oldAsOrg _oldNetworkMatch _oldScore _oldPqc _oldCertLength _oldTls13 _oldCheckedAt _oldNote
    local endpointResult ip candidateAsn candidateOrg score pqc certLength tls13 note networkMatch checkedAt

    trap - EXIT INT TERM
    IFS=$'\t' read -r target sni name category cdnRisk _oldIp _oldAsn _oldAsOrg _oldNetworkMatch _oldScore _oldPqc _oldCertLength _oldTls13 _oldCheckedAt _oldNote <<<"${record}"
    if ! endpointResult=$(probeRealityTargetEndpoint "${detector}" "${target}" "${sni}" "" all "${asnCacheFile}"); then
        printf 'NETWORK_FAIL\t%s\n' "${target}"
        return 0
    fi
    IFS=$'\t' read -r cdnRisk ip candidateAsn candidateOrg score pqc certLength tls13 note <<<"${endpointResult}"
    if [[ "${category}" == "scanner" && "${_oldNote}" == RealiTLScanner:* ]]; then
        note="${_oldNote%%; *}; ${note}"
    fi
    networkMatch=unknown
    if [[ "${candidateAsn}" != "unknown" && "${candidateAsn}" == "${currentAsn}" ]]; then
        networkMatch=same_asn
    elif [[ "${candidateAsn}" != "unknown" && -n "${currentAsn}" ]] && realityTargetProviderMatches "${currentOrg}" "${candidateOrg}"; then
        networkMatch=same_provider
    elif [[ "${candidateAsn}" != "unknown" && -n "${currentAsn}" ]]; then
        networkMatch=different_network
    fi
    checkedAt=$(date +%s)
    printf 'OK\t'
    formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${candidateAsn}" "${candidateOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}"
}

scanLocalAsnRealityTargets() {
    local refreshScope=${1:-recommended}
    local detector networkProfile currentIp currentAsn currentOrg rest line parsed host target networkMatch score cdnRisk scanStart scanSeconds totalCandidates lastProgressAt=0 now
    local maxJobs=${PADM_REALITY_SECONDARY_JOBS:-8}
    local resultsFile refreshSource resultLinesFile failedTargetsFile probeDir asnCacheFile jobFile doneFile probeRecord probeStatus probePayload
    local index=0 activeIndex slot pid running=0 madeProgress processed=0 resolved=0 failed=0 sameAsn=0 sameProvider=0 differentNetwork=0
    local -a candidates=() activeSlots=() jobPids=() jobFiles=() jobDoneFiles=() jobTargets=()
    case "${refreshScope}" in
    recommended | all) ;;
    *) return 1 ;;
    esac
    if ! detector=$(realityTargetDetector); then
        realityTargetStatusBlock yellow "REALITY 目标站扫描" "未找到 xray，无法扫描目标质量" "安装核心后再执行扫描"
        return 1
    fi
    if ! command -v timeout >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 目标站扫描" "未找到 timeout，无法安全限制 TLS 检测时长"
        return 1
    fi
    if ! networkProfile=$(currentRealityNetworkProfile); then
        realityTargetStatusBlock yellow "REALITY 目标站扫描" "无法识别本机公网 ASN" "已跳过同 ASN 扫描"
        return 1
    fi
    [[ "${maxJobs}" =~ ^[1-9][0-9]*$ ]] || maxJobs=8
    (( maxJobs > 16 )) && maxJobs=16
    resultsFile=$(realityTargetManagedResultsFile) || return 1
    if [[ "${refreshScope}" == "all" ]]; then
        refreshSource="全部内置候选"
    elif [[ -s "${resultsFile}" ]]; then
        refreshSource="目标库"
    else
        refreshSource="推荐候选初始化"
    fi
    while IFS= read -r line; do
        candidates+=("${line}")
    done < <(realityTargetRefreshRecords "${refreshScope}")
    scanStart=$(date +%s)
    totalCandidates=${#candidates[@]}
    padmCreateTempPath resultLinesFile || return 1
    padmCreateTempPath failedTargetsFile || { padmRemoveCleanupPath "${resultLinesFile}"; return 1; }
    padmCreateTempPath probeDir -d || { padmRemoveCleanupPath "${resultLinesFile}"; padmRemoveCleanupPath "${failedTargetsFile}"; return 1; }
    asnCacheFile="${probeDir}/asn-cache.tsv"
    : >"${asnCacheFile}"
    currentIp=${networkProfile%%$'\t'*}
    rest=${networkProfile#*$'\t'}
    currentAsn=${rest%%$'\t'*}
    currentOrg=${rest#*$'\t'}
    realityTargetStatusBlock yellow "REALITY 目标库刷新" "本机公网网络: ${currentIp} ${currentAsn} ${currentOrg}" "检测来源: ${refreshSource}" "目标库文件: ${resultsFile}"
    if (( totalCandidates > 0 )); then
        realityTargetProgressLine "REALITY 目标库刷新 0/${totalCandidates} 并发：${maxJobs} 已耗时：0s"
        lastProgressAt=${scanStart}
    fi
    while (( index < totalCandidates || running > 0 )); do
        while (( index < totalCandidates && running < maxJobs )); do
            line=${candidates[${index}]}
            target=${line%%$'\t'*}
            jobFile="${probeDir}/${index}.result"
            doneFile="${jobFile}.done"
            (
                probeRealityTargetRecord "${detector}" "${line}" "${currentAsn}" "${currentOrg}" "${asnCacheFile}" >"${jobFile}"
                : >"${doneFile}"
            ) &
            jobPids[${index}]=$!
            jobFiles[${index}]=${jobFile}
            jobDoneFiles[${index}]=${doneFile}
            jobTargets[${index}]=${target}
            activeSlots+=("${index}")
            index=$((index + 1))
            running=$((running + 1))
        done

        madeProgress=false
        for activeIndex in "${!activeSlots[@]}"; do
            slot=${activeSlots[${activeIndex}]}
            pid=${jobPids[${slot}]}
            if [[ -f "${jobDoneFiles[${slot}]}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
                wait "${pid}" 2>/dev/null || true
                jobPids[${slot}]=
                unset "activeSlots[${activeIndex}]"
                running=$((running - 1))
                processed=$((processed + 1))
                target=${jobTargets[${slot}]}
                madeProgress=true
            fi
        done
        activeSlots=("${activeSlots[@]}")

        if [[ "${madeProgress}" == "false" && "${running}" -gt 0 ]]; then
            command sleep 0.05
            continue
        fi
        if [[ "${madeProgress}" == "true" ]]; then
            now=$(date +%s)
            if (( lastProgressAt == 0 || now - lastProgressAt >= 10 || processed == totalCandidates )); then
                parsed=$(parseHostPort "${target}" 443)
                host=${parsed%:*}
                realityTargetProgressLine "REALITY 目标库刷新 ${processed}/${totalCandidates} 当前：${host} 并发：${maxJobs} 已耗时：$((now - scanStart))s"
                lastProgressAt=${now}
            fi
        fi
    done

    for ((slot = 0; slot < totalCandidates; slot++)); do
        probeRecord=
        [[ -f "${jobFiles[${slot}]}" ]] && probeRecord=$(<"${jobFiles[${slot}]}")
        probeStatus=${probeRecord%%$'\t'*}
        probePayload=${probeRecord#*$'\t'}
        case "${probeStatus}" in
        OK)
            if [[ -n "${probePayload}" ]]; then
                printf '%s\n' "${probePayload}" >>"${resultLinesFile}"
                score=$(realityTargetResultField "${probePayload}" 10)
                cdnRisk=$(realityTargetResultField "${probePayload}" 5)
                if [[ "${cdnRisk}" == "no" && "${score}" == "A" ]]; then
                    networkMatch=$(realityTargetResultField "${probePayload}" 9)
                    case "${networkMatch}" in
                    same_asn) sameAsn=$((sameAsn + 1)) ;;
                    same_provider) sameProvider=$((sameProvider + 1)) ;;
                    *) differentNetwork=$((differentNetwork + 1)) ;;
                    esac
                    resolved=$((resolved + 1))
                else
                    failed=$((failed + 1))
                fi
            else
                printf '%s\n' "${jobTargets[${slot}]}" >>"${failedTargetsFile}"
                failed=$((failed + 1))
            fi
            ;;
        NETWORK_FAIL|FAIL)
            printf '%s\n' "${probePayload:-${jobTargets[${slot}]}}" >>"${failedTargetsFile}"
            failed=$((failed + 1))
            ;;
        *)
            printf '%s\n' "${jobTargets[${slot}]}" >>"${failedTargetsFile}"
            failed=$((failed + 1))
            ;;
        esac
    done

    writeRealityTargetResultLines "${resultLinesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    padmRemoveCleanupPath "${resultLinesFile}"
    padmRemoveCleanupPath "${failedTargetsFile}"
    padmRemoveCleanupPath "${probeDir}"
    scanSeconds=$(( $(date +%s) - scanStart ))
    realityTargetStatusBlock green "REALITY 目标库刷新" "复测完成" "目标: ${processed}" "并发: ${maxJobs}" "A 级目标: ${resolved}" "same_asn: ${sameAsn}" "same_provider: ${sameProvider}" "different_network: ${differentNetwork}" "非候选/失败: ${failed}" "耗时: ${scanSeconds}s"
    if [[ "$(realityTargetResultCount)" -gt 0 ]]; then
        realityTargetStatusBlock green "REALITY 目标库刷新" "自动推荐将只使用 cdn_risk=no 的 A 级目标"
    else
        realityTargetStatusBlock yellow "REALITY 目标库刷新" "未得到 cdn_risk=no 的 A 级目标" "不会写入未经检测的兜底目标"
    fi
}

showRealityTargetPqcStatus() {
    local target
    if [[ -z "${realityTargetHost:-}" ]]; then
        realityTargetStatusBlock yellow "REALITY PQC/ML-DSA-65" "当前未读取到 Reality 目标站"
        return 1
    fi
    target=$(formatRealityTarget "${realityTargetHost}" "${realityTargetPort:-443}")
    echoContent title "\n┌─ REALITY PQC/ML-DSA-65 状态 ──────────────────────"
    menuLine "目标站: ${target}"
    menuLine "SNI: ${realitySNI:-未知}"
    menuLine "当前 mldsa65Verify: ${currentRealityMldsa65Verify:-未启用}"
    menuLine "说明: A 级目标适合启用 X25519MLKEM768 + ML-DSA-65"
    menuClose
    showRealityTargetCachedQuality "${target}" || true
}

realityXrayVisionConfigPath() {
    printf '%s\n' "${PADM_REALITY_XRAY_VISION_CONFIG_FILE:-/etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json}"
}

realityXrayXhttpConfigPath() {
    printf '%s\n' "${PADM_REALITY_XRAY_XHTTP_CONFIG_FILE:-/etc/padm/xray/conf/12_VLESS_XHTTP_inbounds.json}"
}

realitySingBoxVisionConfigPath() {
    printf '%s\n' "${PADM_REALITY_SINGBOX_VISION_CONFIG_FILE:-/etc/padm/sing-box/conf/config/07_VLESS_vision_reality_inbounds.json}"
}

realitySingBoxGrpcConfigPath() {
    printf '%s\n' "${PADM_REALITY_SINGBOX_GRPC_CONFIG_FILE:-/etc/padm/sing-box/conf/config/08_VLESS_vision_gRPC_inbounds.json}"
}

applyRealityTargetToInstalledConfigs() {
    local target=$1
    local sni=$2
    local parsed host port changed=false
    local applyLog
    local xrayRealityConfigPath xrayXhttpConfigPath singBoxRealityConfigPath singBoxGrpcConfigPath
    REALITY_TARGET_APPLY_FAILURE_LOG=
    REALITY_TARGET_APPLY_FAILURE_PATH=
    xrayRealityConfigPath=$(realityXrayVisionConfigPath)
    xrayXhttpConfigPath=$(realityXrayXhttpConfigPath)
    singBoxRealityConfigPath=$(realitySingBoxVisionConfigPath)
    singBoxGrpcConfigPath=$(realitySingBoxGrpcConfigPath)
    applyLog=$(realityTargetTmpPath padm-reality-target-apply.log)
    rm -f "${applyLog}" >/dev/null 2>&1 || true
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    if ! validateRealityTarget "${host}" "${port}"; then
        realityTargetStatusBlock red "REALITY 目标站" "伪装目标不合法: ${target}"
        return 1
    fi
    [[ -n "${sni}" ]] || sni=${host}
    if ! padmIsValidHostName "${sni}"; then
        realityTargetStatusBlock red "REALITY SNI" "SNI 不合法: ${sni}"
        return 1
    fi

    if [[ -f "${xrayRealityConfigPath}" ]]; then
        if ! updateRoutingJsonConfig "${xrayRealityConfigPath}" '
          .inbounds[1].streamSettings.realitySettings.target = $target |
          .inbounds[1].streamSettings.realitySettings.serverNames = [$sni]
        ' --arg target "${host}:${port}" --arg sni "${sni}" 2>"${applyLog}"; then
            REALITY_TARGET_APPLY_FAILURE_LOG="${applyLog}"
            REALITY_TARGET_APPLY_FAILURE_PATH="${xrayRealityConfigPath}"
            return 1
        fi
        changed=true
    fi

    if [[ -f "${xrayXhttpConfigPath}" ]]; then
        if ! updateRoutingJsonConfig "${xrayXhttpConfigPath}" '
          .inbounds[0].streamSettings.realitySettings.target = $target |
          .inbounds[0].streamSettings.realitySettings.serverNames = [$sni] |
          .inbounds[0].streamSettings.xhttpSettings.host = $sni
        ' --arg target "${host}:${port}" --arg sni "${sni}" 2>"${applyLog}"; then
            REALITY_TARGET_APPLY_FAILURE_LOG="${applyLog}"
            REALITY_TARGET_APPLY_FAILURE_PATH="${xrayXhttpConfigPath}"
            return 1
        fi
        changed=true
    fi

    if [[ -f "${singBoxRealityConfigPath}" ]]; then
        if ! updateRoutingJsonConfig "${singBoxRealityConfigPath}" '
          .inbounds[0].tls.server_name = $sni |
          .inbounds[0].tls.reality.handshake.server = $host |
          .inbounds[0].tls.reality.handshake.server_port = ($port | tonumber)
        ' --arg host "${host}" --arg port "${port}" --arg sni "${sni}" 2>"${applyLog}"; then
            REALITY_TARGET_APPLY_FAILURE_LOG="${applyLog}"
            REALITY_TARGET_APPLY_FAILURE_PATH="${singBoxRealityConfigPath}"
            return 1
        fi
        changed=true
    fi

    if [[ -f "${singBoxGrpcConfigPath}" ]]; then
        if ! updateRoutingJsonConfig "${singBoxGrpcConfigPath}" '
          .inbounds[0].tls.server_name = $sni |
          .inbounds[0].tls.reality.handshake.server = $host |
          .inbounds[0].tls.reality.handshake.server_port = ($port | tonumber)
        ' --arg host "${host}" --arg port "${port}" --arg sni "${sni}" 2>"${applyLog}"; then
            REALITY_TARGET_APPLY_FAILURE_LOG="${applyLog}"
            REALITY_TARGET_APPLY_FAILURE_PATH="${singBoxGrpcConfigPath}"
            return 1
        fi
        changed=true
    fi

    if [[ "${changed}" != "true" ]]; then
        rm -f "${applyLog}" >/dev/null 2>&1 || true
        realityTargetStatusBlock yellow "REALITY 目标站" "未发现可更新的 Reality 配置文件"
        return 1
    fi

    rm -f "${applyLog}" >/dev/null 2>&1 || true
    realityTargetHost=${host}
    realityTargetPort=${port}
    realitySNI=${sni}
    xrayVLESSRealitySNI=${sni}
    xrayVLESSRealityXHTTPSNI=${sni}
    singBoxVLESSRealityVisionSNI=${sni}
    singBoxVLESSRealityGRPCSNI=${sni}
    return 0
}

restoreRealityTargetRuntimeState() {
    realityTargetHost=$1
    realityTargetPort=$2
    realitySNI=$3
    xrayVLESSRealitySNI=$4
    xrayVLESSRealityXHTTPSNI=$5
    singBoxVLESSRealityVisionSNI=$6
    singBoxVLESSRealityGRPCSNI=$7
}

validateRealityTargetConfigAfterChange() {
    local logFile
    if [[ -f "$(realityXrayVisionConfigPath)" || -f "$(realityXrayXhttpConfigPath)" ]]; then
        if [[ -x "/etc/padm/xray/xray" ]]; then
            logFile=$(realityTargetTmpPath padm-reality-target-xray-test.log)
            /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1 || return 1
        fi
    fi
    if [[ -f "$(realitySingBoxVisionConfigPath)" || -f "$(realitySingBoxGrpcConfigPath)" ]]; then
        if [[ -x "/etc/padm/sing-box/sing-box" ]]; then
            logFile=$(realityTargetTmpPath padm-reality-target-sing-box-test.log)
            singBoxMergeConfigForValidation /etc/padm/sing-box/sing-box "${logFile}" || return 1
        fi
    fi
}

backupRealityTargetConfigs() {
    local backupDir=$1
    local xrayRealityConfigPath xrayXhttpConfigPath singBoxRealityConfigPath singBoxGrpcConfigPath
    local status=0
    xrayRealityConfigPath=$(realityXrayVisionConfigPath)
    xrayXhttpConfigPath=$(realityXrayXhttpConfigPath)
    singBoxRealityConfigPath=$(realitySingBoxVisionConfigPath)
    singBoxGrpcConfigPath=$(realitySingBoxGrpcConfigPath)
    mkdir -p "${backupDir}/xray" "${backupDir}/sing-box" || return 1
    if [[ -f "${xrayRealityConfigPath}" ]]; then
        cp "${xrayRealityConfigPath}" "${backupDir}/xray/07_VLESS_vision_reality_inbounds.json" || status=1
    fi
    if [[ -f "${xrayXhttpConfigPath}" ]]; then
        cp "${xrayXhttpConfigPath}" "${backupDir}/xray/12_VLESS_XHTTP_inbounds.json" || status=1
    fi
    if [[ -f "${singBoxRealityConfigPath}" ]]; then
        cp "${singBoxRealityConfigPath}" "${backupDir}/sing-box/07_VLESS_vision_reality_inbounds.json" || status=1
    fi
    if [[ -f "${singBoxGrpcConfigPath}" ]]; then
        cp "${singBoxGrpcConfigPath}" "${backupDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json" || status=1
    fi
    return "${status}"
}

restoreRealityTargetConfigs() {
    local backupDir=$1
    local status=0
    if [[ -f "${backupDir}/xray/07_VLESS_vision_reality_inbounds.json" ]]; then
        restoreManagedFileFromBackup "${backupDir}/xray/07_VLESS_vision_reality_inbounds.json" "$(realityXrayVisionConfigPath)" 644 || status=1
    fi
    if [[ -f "${backupDir}/xray/12_VLESS_XHTTP_inbounds.json" ]]; then
        restoreManagedFileFromBackup "${backupDir}/xray/12_VLESS_XHTTP_inbounds.json" "$(realityXrayXhttpConfigPath)" 644 || status=1
    fi
    if [[ -f "${backupDir}/sing-box/07_VLESS_vision_reality_inbounds.json" ]]; then
        restoreManagedFileFromBackup "${backupDir}/sing-box/07_VLESS_vision_reality_inbounds.json" "$(realitySingBoxVisionConfigPath)" 644 || status=1
    fi
    if [[ -f "${backupDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json" ]]; then
        restoreManagedFileFromBackup "${backupDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json" "$(realitySingBoxGrpcConfigPath)" 644 || status=1
    fi
    return "${status}"
}

refreshSubscriptionsAfterRealityTargetChange() {
    if declare -F subscriptionCurrentRoleNormalized >/dev/null 2>&1 &&
        [[ "$(subscriptionCurrentRoleNormalized 2>/dev/null || true)" == "controlled" ]]; then
        return 0
    fi
    if ! declare -F refreshPublishedSubscriptions >/dev/null 2>&1 || ! declare -F showAccounts >/dev/null 2>&1 || ! declare -F readNginxSubscribe >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 目标站" "订阅刷新依赖未完整加载，已跳过订阅刷新" "通过 install.sh 菜单执行时会自动刷新"
        return 0
    fi
    readNginxSubscribe
    if [[ -n "${subscribePort:-}" || -f "${nginxConfigPath:-/etc/nginx/conf.d/}subscribe.conf" ]]; then
        refreshPublishedSubscriptions
    else
        realityTargetStatusBlock yellow "REALITY 目标站" "未启用订阅服务，已跳过订阅刷新"
    fi
}

changeInstalledRealityTarget() {
    local target=$1
    local sni=$2
    local backupDir
    local applyFailureLog applyFailurePath
    local previousRealityTargetHost="${realityTargetHost:-}"
    local previousRealityTargetPort="${realityTargetPort:-}"
    local previousRealitySNI="${realitySNI:-}"
    local previousXrayVLESSRealitySNI="${xrayVLESSRealitySNI:-}"
    local previousXrayVLESSRealityXHTTPSNI="${xrayVLESSRealityXHTTPSNI:-}"
    local previousSingBoxVLESSRealityVisionSNI="${singBoxVLESSRealityVisionSNI:-}"
    local previousSingBoxVLESSRealityGRPCSNI="${singBoxVLESSRealityGRPCSNI:-}"
    validateRealityTargetSelection manual "${target}" "${sni}" || return 1
    padmCreateTempPath backupDir -d "$(realityTargetTmpPath 'padm-reality-target.XXXXXX')" || return 1
    if ! backupRealityTargetConfigs "${backupDir}"; then
        padmRemoveCleanupPath "${backupDir}"
        realityTargetStatusBlock red "REALITY 目标站" "配置备份失败，已取消切换"
        return 1
    fi
    if ! applyRealityTargetToInstalledConfigs "${target}" "${sni}"; then
        applyFailureLog="${REALITY_TARGET_APPLY_FAILURE_LOG:-}"
        applyFailurePath="${REALITY_TARGET_APPLY_FAILURE_PATH:-}"
        if ! restoreRealityTargetConfigs "${backupDir}"; then
            if [[ -n "${applyFailureLog}" ]]; then
                realityTargetStatusBlock red "REALITY 目标站" "配置应用失败，且回滚配置失败" "失败文件: ${applyFailurePath}" "备份目录: ${backupDir}" "排查日志: ${applyFailureLog}"
            else
                realityTargetStatusBlock red "REALITY 目标站" "配置应用失败，且回滚配置失败" "备份目录: ${backupDir}"
            fi
            padmForgetCleanupPath "${backupDir}"
            return 1
        fi
        padmRemoveCleanupPath "${backupDir}"
        if [[ -n "${applyFailureLog}" ]]; then
            realityTargetStatusBlock red "REALITY 目标站" "配置应用失败，已回滚" "失败文件: ${applyFailurePath}" "排查日志: ${applyFailureLog}"
        fi
        return 1
    fi
    if ! validateRealityTargetConfigAfterChange; then
        if ! restoreRealityTargetConfigs "${backupDir}"; then
            realityTargetStatusBlock red "REALITY 目标站" "配置校验失败，且回滚配置失败" "备份目录: ${backupDir}"
            padmForgetCleanupPath "${backupDir}"
            return 1
        fi
        restoreRealityTargetRuntimeState "${previousRealityTargetHost}" "${previousRealityTargetPort}" "${previousRealitySNI}" "${previousXrayVLESSRealitySNI}" "${previousXrayVLESSRealityXHTTPSNI}" "${previousSingBoxVLESSRealityVisionSNI}" "${previousSingBoxVLESSRealityGRPCSNI}"
        padmRemoveCleanupPath "${backupDir}"
        realityTargetStatusBlock red "REALITY 目标站" "配置校验失败，已回滚" "Xray 日志: $(realityTargetTmpPath padm-reality-target-xray-test.log)" "sing-box 日志: $(realityTargetTmpPath padm-reality-target-sing-box-test.log)"
        return 1
    fi
    if ! PADM_SKIP_CONTROLLER_REFRESH=1 reloadCore; then
        if ! restoreRealityTargetConfigs "${backupDir}"; then
            realityTargetStatusBlock red "REALITY 目标站" "核心重载失败，且回滚配置失败" "备份目录: ${backupDir}"
            padmForgetCleanupPath "${backupDir}"
            return 1
        fi
        restoreRealityTargetRuntimeState "${previousRealityTargetHost}" "${previousRealityTargetPort}" "${previousRealitySNI}" "${previousXrayVLESSRealitySNI}" "${previousXrayVLESSRealityXHTTPSNI}" "${previousSingBoxVLESSRealityVisionSNI}" "${previousSingBoxVLESSRealityGRPCSNI}"
        local rollbackMessage
        coreSetRollbackResultMessage rollbackMessage "核心重载失败" "已回滚配置" reloadCore "恢复旧配置后重载仍失败，请检查核心服务日志"
        if [[ "${rollbackMessage}" == "核心重载失败，已回滚配置" ]]; then
            realityTargetStatusBlock red "REALITY 目标站" "${rollbackMessage}"
        else
            realityTargetStatusBlock red "REALITY 目标站" "核心重载失败，已回滚配置" "恢复旧配置后重载仍失败，请检查核心服务日志"
        fi
        padmRemoveCleanupPath "${backupDir}"
        return 1
    fi
    padmRemoveCleanupPath "${backupDir}"
    if ! refreshSubscriptionsAfterRealityTargetChange; then
        realityTargetStatusBlock yellow "REALITY 目标站" "目标站已更新为 ${realityTargetHost}:${realityTargetPort}" "SNI=${realitySNI}" "订阅刷新失败，请检查订阅输出后重试"
        return 1
    fi
    realityTargetStatusBlock green "REALITY 目标站" "已更新为 ${realityTargetHost}:${realityTargetPort}" "SNI=${realitySNI}"
}
