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
    if declare -F padmTmpFilePath >/dev/null 2>&1; then
        padmTmpFilePath "${template}"
    else
        local tmpBase="${TMPDIR:-/tmp}"
        printf '%s\n' "${tmpBase%/}/${template}"
    fi
}

realityScannerDir() {
    realityTargetTmpPath RealiTLScanner
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

realityTargetXrayTestLog() {
    realityTargetTmpPath padm-reality-target-xray-test.log
}

realityTargetSingBoxTestLog() {
    realityTargetTmpPath padm-reality-target-sing-box-test.log
}

realityTargetApplyLog() {
    realityTargetTmpPath padm-reality-target-apply.log
}

realityTargetBackupTemplate() {
    realityTargetTmpPath 'padm-reality-target.XXXXXX'
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
    if [[ -n "${PADM_REALITY_TARGET_CANDIDATES_FILE:-}" && -f "${PADM_REALITY_TARGET_CANDIDATES_FILE}" ]]; then
        cat "${PADM_REALITY_TARGET_CANDIDATES_FILE}"
        return 0
    fi
    cat <<'EOF'
www.ibm.com|www.ibm.com|IBM|global|large_site|unknown|1|yes|远端实测 TLS1.3/PQC 可用且证书链较长，适合作为默认目标
www.microsoft.com|www.microsoft.com|Microsoft|global|large_site|unknown|2|yes|全球稳定大型 HTTPS 站点，适合作为稳定备选
www.reuters.com|www.reuters.com|Reuters|global|media|unknown|3|yes|远端实测 TLS1.3/PQC 可用且证书链很长，适合作为高质量备选
www.qualcomm.com|www.qualcomm.com|Qualcomm|global|large_site|unknown|94|yes|远端实测 TLS1.3/PQC 可用且证书链很长，适合作为高质量备选
nodejs.org|nodejs.org|Node.js|global|developer|unknown|92|yes|远端实测 TLS1.3/PQC 可用且证书链很长，开发者站点备选
www.vmware.com|www.vmware.com|VMware|global|large_site|unknown|90|yes|远端实测 TLS1.3/PQC 可用且证书链较长，适合作为企业站点备选
www.atlassian.com|www.atlassian.com|Atlassian|global|developer|unknown|89|yes|远端实测 TLS1.3/PQC 可用且证书链较长，开发者工具站点备选
www.jetbrains.com|www.jetbrains.com|JetBrains|global|developer|unknown|88|yes|远端实测 TLS1.3/PQC 可用且证书链达标，开发者工具站点备选
www.mongodb.com|www.mongodb.com|MongoDB|global|developer|unknown|87|yes|远端实测 TLS1.3/PQC 可用且证书链达标，数据库站点备选
www.asus.com|www.asus.com|ASUS|asia|large_site|unknown|86|yes|远端实测 TLS1.3/PQC 可用且证书链达标，亚洲硬件站点备选
www.bbc.com|www.bbc.com|BBC|global|media|unknown|85|yes|远端实测 TLS1.3/PQC 可用且证书链较长，媒体站点备选
www.nationalgeographic.com|www.nationalgeographic.com|National Geographic|global|media|unknown|84|yes|远端实测 TLS1.3/PQC 可用且证书链较长，媒体站点备选
tensorflow.org|tensorflow.org|TensorFlow|global|developer|unknown|83|yes|远端实测 TLS1.3/PQC 可用且证书链达标，AI/开发者站点备选
www.oracle.com|www.oracle.com|Oracle|global|large_site|unknown|82|yes|远端实测 TLS1.3 可用且证书链较长，大型企业站点备选
go.dev|go.dev|Go|global|developer|unknown|81|yes|远端实测 TLS1.3 可用且证书链较长，开发者站点备选
www.samsung.com|www.samsung.com|Samsung|asia|large_site|unknown|80|yes|亚洲网络常见大型站点，适合作为区域备选
www.nvidia.com|www.nvidia.com|NVIDIA|global|large_site|unknown|79|yes|大型科技站点，适合作为备选目标
www.amd.com|www.amd.com|AMD|global|large_site|unknown|78|yes|大型科技站点，适合作为备选目标
www.python.org|www.python.org|Python|global|developer|unknown|77|yes|开发者常见 HTTPS 站点，适合作为备选目标
react.dev|react.dev|React|global|developer|unknown|76|yes|开发者常见 HTTPS 站点，适合作为备选目标
vuejs.org|vuejs.org|Vue|global|developer|unknown|75|yes|开发者常见 HTTPS 站点，适合作为备选目标
www.cisco.com|www.cisco.com|Cisco|global|large_site|unknown|74|yes|大型企业站点，适合作为备选目标
www.mozilla.org|www.mozilla.org|Mozilla|global|large_site|unknown|73|yes|远端实测 TLS1.3/PQC 可用，大型 HTTPS 站点备选
developer.mozilla.org|developer.mozilla.org|MDN|global|developer|unknown|72|yes|远端实测 TLS1.3/PQC 可用，开发者文档站点备选
www.kernel.org|www.kernel.org|Linux Kernel|global|developer|unknown|71|yes|远端实测 TLS1.3/PQC 可用，开源基础设施站点备选
git-scm.com|git-scm.com|Git|global|developer|unknown|70|yes|远端实测 TLS1.3/PQC 可用，开发者工具站点备选
www.vultr.com|www.vultr.com|Vultr|global|cloud|unknown|69|yes|远端实测 TLS1.3/PQC 可用，云服务站点备选
www.linode.com|www.linode.com|Linode|global|cloud|unknown|68|yes|远端实测 TLS1.3/PQC 可用，云服务站点备选
www.spotify.com|www.spotify.com|Spotify|global|media|unknown|67|yes|远端实测 TLS1.3/PQC 可用，媒体站点备选
www.twitch.tv|www.twitch.tv|Twitch|global|media|unknown|66|yes|远端实测 TLS1.3/PQC 可用，媒体站点备选
www.wikipedia.org|www.wikipedia.org|Wikipedia|global|media|unknown|65|yes|远端实测 TLS1.3/PQC 可用，公共知识站点备选
www.wikimedia.org|www.wikimedia.org|Wikimedia|global|media|unknown|64|yes|远端实测 TLS1.3/PQC 可用，公共知识站点备选
addons.mozilla.org|addons.mozilla.org|Mozilla Add-ons|global|large_site|unknown|63|yes|大型 HTTPS 站点，适合作为备选目标
dl.google.com|dl.google.com|Google Download|global|large_site|unknown|62|yes|大型下载站点，部分地区可达性需自测
rust-lang.org|rust-lang.org|Rust|global|developer|unknown|61|yes|远端实测 TLS1.3/PQC 可用，开发者站点备选
www.ruby-lang.org|www.ruby-lang.org|Ruby|global|developer|unknown|60|yes|远端实测 TLS1.3/PQC 可用，开发者站点备选
www.perl.org|www.perl.org|Perl|global|developer|unknown|59|yes|远端实测 TLS1.3/PQC 可用，开发者站点备选
www.springer.com|www.springer.com|Springer|global|education|unknown|58|yes|远端实测 TLS1.3/PQC 可用，学术出版站点备选
www.nytimes.com|www.nytimes.com|New York Times|global|media|unknown|57|yes|远端实测 TLS1.3/PQC 可用，媒体站点备选
www.theguardian.com|www.theguardian.com|The Guardian|global|media|unknown|56|yes|远端实测 TLS1.3/PQC 可用，媒体站点备选
www.sony.com|www.sony.com|Sony|global|large_site|unknown|55|no|远端实测 TLS1.3 可用且证书链较长，但未检测到 PQC，手动备选
www.hp.com|www.hp.com|HP|global|large_site|unknown|54|no|远端实测 TLS1.3 可用，证书链接近 ML-DSA-65 建议，手动备选
www.redhat.com|www.redhat.com|Red Hat|global|developer|unknown|53|no|远端实测 TLS1.3 可用，手动备选
www.gnu.org|www.gnu.org|GNU|global|developer|unknown|52|no|远端实测 TLS1.3 可用，手动备选
www.debian.org|www.debian.org|Debian|global|developer|unknown|51|no|远端实测 TLS1.3 可用，手动备选
www.ubuntu.com|www.ubuntu.com|Ubuntu|global|developer|unknown|50|no|远端实测 TLS1.3 可用，手动备选
www.dell.com|www.dell.com|Dell|global|large_site|unknown|49|no|远端实测 TLS1.3 可用，手动备选
www.intel.com|www.intel.com|Intel|global|large_site|unknown|48|no|远端实测 TLS1.3 可用，手动备选
www.lenovo.com|www.lenovo.com|Lenovo|global|large_site|unknown|47|no|远端实测 TLS1.3 可用，手动备选
www.apple.com|www.apple.com|Apple|global|large_site|unknown|45|no|Xray 会提示 Apple/iCloud 类目标可能带来封锁风险，仅高级用户自选
www.google-analytics.com|www.google-analytics.com|Google Analytics|global|large_site|unknown|44|no|部分地区可达性和策略差异较大，默认降权
www.amazon.com|www.amazon.com|Amazon|global|large_site|unknown|43|no|大型站点，区域解析差异较大
m.media-amazon.com|m.media-amazon.com|Amazon Media|global|large_site|unknown|42|no|大型媒体站点，区域解析差异较大
www.swift.com|www.swift.com|Swift|global|large_site|unknown|41|no|大型站点，适合作为手动备选
www.java.com|www.java.com|Java|global|large_site|unknown|40|no|大型站点，适合作为手动备选
www.sap.com|www.sap.com|SAP|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.salesforce.com|www.salesforce.com|Salesforce|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.adobe.com|www.adobe.com|Adobe|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.autodesk.com|www.autodesk.com|Autodesk|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.servicenow.com|www.servicenow.com|ServiceNow|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.workday.com|www.workday.com|Workday|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.dropbox.com|www.dropbox.com|Dropbox|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.box.com|www.box.com|Box|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.okta.com|www.okta.com|Okta|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.zoom.com|www.zoom.com|Zoom|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.slack.com|www.slack.com|Slack|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.docusign.com|www.docusign.com|DocuSign|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.paypal.com|www.paypal.com|PayPal|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.visa.com|www.visa.com|Visa|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.mastercard.com|www.mastercard.com|Mastercard|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.americanexpress.com|www.americanexpress.com|American Express|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.hsbc.com|www.hsbc.com|HSBC|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.citi.com|www.citi.com|Citi|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.jpmorgan.com|www.jpmorgan.com|JPMorgan|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.goldmansachs.com|www.goldmansachs.com|Goldman Sachs|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.nasdaq.com|www.nasdaq.com|Nasdaq|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.londonstockexchange.com|www.londonstockexchange.com|London Stock Exchange|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.bloomberg.com|www.bloomberg.com|Bloomberg|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.ft.com|www.ft.com|Financial Times|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.wsj.com|www.wsj.com|Wall Street Journal|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.economist.com|www.economist.com|The Economist|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.apnews.com|www.apnews.com|Associated Press|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.npr.org|www.npr.org|NPR|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.pbs.org|www.pbs.org|PBS|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cnn.com|www.cnn.com|CNN|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cnbc.com|www.cnbc.com|CNBC|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.forbes.com|www.forbes.com|Forbes|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.wired.com|www.wired.com|Wired|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.theverge.com|www.theverge.com|The Verge|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.engadget.com|www.engadget.com|Engadget|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.arstechnica.com|www.arstechnica.com|Ars Technica|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.stackoverflow.com|www.stackoverflow.com|Stack Overflow|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
stackexchange.com|stackexchange.com|Stack Exchange|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
superuser.com|superuser.com|Super User|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
serverfault.com|serverfault.com|Server Fault|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
github.com|github.com|GitHub|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
docs.github.com|docs.github.com|GitHub Docs|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
about.gitlab.com|about.gitlab.com|GitLab|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
bitbucket.org|bitbucket.org|Bitbucket|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
code.visualstudio.com|code.visualstudio.com|Visual Studio Code|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
marketplace.visualstudio.com|marketplace.visualstudio.com|Visual Studio Marketplace|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.docker.com|www.docker.com|Docker|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
hub.docker.com|hub.docker.com|Docker Hub|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
kubernetes.io|kubernetes.io|Kubernetes|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
helm.sh|helm.sh|Helm|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
prometheus.io|prometheus.io|Prometheus|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
grafana.com|grafana.com|Grafana|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
elastic.co|elastic.co|Elastic|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.postgresql.org|www.postgresql.org|PostgreSQL|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.mysql.com|www.mysql.com|MySQL|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
mariadb.org|mariadb.org|MariaDB|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
redis.io|redis.io|Redis|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.nginx.com|www.nginx.com|NGINX|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
nginx.org|nginx.org|NGINX Open Source|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
httpd.apache.org|httpd.apache.org|Apache HTTP Server|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.apache.org|www.apache.org|Apache|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
maven.apache.org|maven.apache.org|Apache Maven|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
gradle.org|gradle.org|Gradle|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
cmake.org|cmake.org|CMake|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
llvm.org|llvm.org|LLVM|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
clang.llvm.org|clang.llvm.org|Clang|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
gcc.gnu.org|gcc.gnu.org|GCC|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.eclipse.org|www.eclipse.org|Eclipse|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.qt.io|www.qt.io|Qt|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.djangoproject.com|www.djangoproject.com|Django|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
flask.palletsprojects.com|flask.palletsprojects.com|Flask|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
fastapi.tiangolo.com|fastapi.tiangolo.com|FastAPI|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
laravel.com|laravel.com|Laravel|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
symfony.com|symfony.com|Symfony|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
rubyonrails.org|rubyonrails.org|Ruby on Rails|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
dotnet.microsoft.com|dotnet.microsoft.com|.NET|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
learn.microsoft.com|learn.microsoft.com|Microsoft Learn|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
developer.android.com|developer.android.com|Android Developers|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
android.com|android.com|Android|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.chromium.org|www.chromium.org|Chromium|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.openjdk.org|www.openjdk.org|OpenJDK|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
jdk.java.net|jdk.java.net|JDK Builds|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
crates.io|crates.io|Crates.io|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
docs.rs|docs.rs|Docs.rs|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
pypi.org|pypi.org|PyPI|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
npmjs.com|npmjs.com|npm|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
yarnpkg.com|yarnpkg.com|Yarn|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
pnpm.io|pnpm.io|pnpm|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
deno.com|deno.com|Deno|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
bun.sh|bun.sh|Bun|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
typescriptlang.org|typescriptlang.org|TypeScript|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
webpack.js.org|webpack.js.org|Webpack|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
vitejs.dev|vitejs.dev|Vite|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
svelte.dev|svelte.dev|Svelte|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
angular.dev|angular.dev|Angular|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
nuxt.com|nuxt.com|Nuxt|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
nextjs.org|nextjs.org|Next.js|global|developer|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
vercel.com|vercel.com|Vercel|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
netlify.com|netlify.com|Netlify|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.heroku.com|www.heroku.com|Heroku|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
render.com|render.com|Render|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
fly.io|fly.io|Fly.io|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
railway.app|railway.app|Railway|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.digitalocean.com|www.digitalocean.com|DigitalOcean|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.ovhcloud.com|www.ovhcloud.com|OVHcloud|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.hetzner.com|www.hetzner.com|Hetzner|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.scaleway.com|www.scaleway.com|Scaleway|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.oraclecloud.com|www.oraclecloud.com|Oracle Cloud|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
cloud.google.com|cloud.google.com|Google Cloud|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
aws.amazon.com|aws.amazon.com|AWS|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
azure.microsoft.com|azure.microsoft.com|Microsoft Azure|global|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.tencentcloud.com|www.tencentcloud.com|Tencent Cloud|asia|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.alibabacloud.com|www.alibabacloud.com|Alibaba Cloud|asia|cloud|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cloudflarestatus.com|www.cloudflarestatus.com|Cloudflare Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
status.aws.amazon.com|status.aws.amazon.com|AWS Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
status.cloud.google.com|status.cloud.google.com|Google Cloud Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
azure.status.microsoft|azure.status.microsoft|Azure Status|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.uptime.com|www.uptime.com|Uptime.com|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.pingdom.com|www.pingdom.com|Pingdom|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cloudflareblog.com|www.cloudflareblog.com|Cloudflare Blog|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.shopify.com|www.shopify.com|Shopify|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.stripe.com|www.stripe.com|Stripe|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
squareup.com|squareup.com|Square|global|finance|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.ebay.com|www.ebay.com|eBay|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.etsy.com|www.etsy.com|Etsy|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.airbnb.com|www.airbnb.com|Airbnb|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.booking.com|www.booking.com|Booking.com|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.expedia.com|www.expedia.com|Expedia|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.tripadvisor.com|www.tripadvisor.com|Tripadvisor|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.uber.com|www.uber.com|Uber|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.lyft.com|www.lyft.com|Lyft|global|large_site|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
soundcloud.com|soundcloud.com|SoundCloud|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
vimeo.com|vimeo.com|Vimeo|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.netflix.com|www.netflix.com|Netflix|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.hulu.com|www.hulu.com|Hulu|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.disneyplus.com|www.disneyplus.com|Disney+|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.imdb.com|www.imdb.com|IMDb|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.rottentomatoes.com|www.rottentomatoes.com|Rotten Tomatoes|global|media|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.metmuseum.org|www.metmuseum.org|The Met|global|education|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.britannica.com|www.britannica.com|Britannica|global|education|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.coursera.org|www.coursera.org|Coursera|global|education|unknown|39|no|未远端实测，适合手动检测或同 ASN 扫描后使用
www.cloudflare.com|www.cloudflare.com|Cloudflare|global|cdn|yes|35|no|远端实测 TLS1.3/PQC 可用但属于 CDN 目标，可能带来转发滥用风险
www.fastly.com|www.fastly.com|Fastly|global|cdn|yes|34|no|远端实测 TLS1.3/PQC 可用但属于 CDN 目标，仅高级用户自选
www.akamai.com|www.akamai.com|Akamai|global|cdn|yes|33|no|远端实测 TLS1.3/PQC 可用但属于 CDN 目标，仅高级用户自选
cloudflare.com|cloudflare.com|Cloudflare Root|global|cdn|yes|32|no|CDN 目标可能带来转发滥用风险，仅高级用户自选
EOF
}

realityTargetBlockedCandidatesFile() {
    printf '%s\n' "${PADM_REALITY_TARGET_BLOCKED_FILE:-/etc/padm/reality_target_blocked.tsv}"
}

realityTargetBlockedCandidates() {
    cat <<'EOF'
www.apple.com|Apple|xray_warn|Xray 会提示 Apple/iCloud 类目标可能带来封锁风险
www.google-analytics.com|Google Analytics|policy_variance|部分地区可达性和策略差异较大
www.cloudflare.com|Cloudflare|cdn|CDN 目标可能带来转发滥用风险
www.fastly.com|Fastly|cdn|CDN 目标可能带来转发滥用风险
www.akamai.com|Akamai|cdn|CDN 目标可能带来转发滥用风险
cloudflare.com|Cloudflare Root|cdn|CDN 目标可能带来转发滥用风险
EOF
    local customBlockedFile
    customBlockedFile=$(realityTargetBlockedCandidatesFile)
    [[ -f "${customBlockedFile}" ]] && cat "${customBlockedFile}"
}

addRealityTargetBlockedCandidate() {
    local target=$1
    local reason=${2:-manual}
    local parsed host blockedFile
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    [[ -n "${host}" ]] || return 1
    blockedFile=$(realityTargetBlockedCandidatesFile)
    mkdir -p "$(dirname "${blockedFile}")"
    if realityTargetCandidateBlocked "${host}"; then
        realityTargetStatusBlock yellow "REALITY 目标站黑名单" "已在黑名单中: ${host}"
        return 0
    fi
    printf '%s|%s|%s|%s\n' "${host}" "手动加入" "${reason}" "用户手动加入；后续不参与统一目标库刷新和扫描导入" >>"${blockedFile}"
    realityTargetStatusBlock green "REALITY 目标站黑名单" "已加入: ${host}" "后续不参与统一目标库刷新和 RealiTLScanner 导入" "当前已安装目标不会自动切换"
}

realityTargetCandidateBlocked() {
    local host=$1
    local line blocked normalizedBlocked
    while IFS='|' read -r blocked _; do
        normalizedBlocked=${blocked#www.}
        if [[ "${host}" == "${blocked}" || "${host}" == "${normalizedBlocked}" || "${host}" == *."${normalizedBlocked}" || "${host}" == *."${blocked}" ]]; then
            return 0
        fi
    done < <(realityTargetBlockedCandidates)
    return 1
}

realityTargetCandidates() {
    local line host _rest blockedLine blocked normalizedBlocked skip
    local blockedHosts=()
    while IFS='|' read -r blocked _rest; do
        blockedHosts+=("${blocked}")
    done < <(realityTargetBlockedCandidates)
    while IFS= read -r line; do
        IFS='|' read -r host _rest <<<"${line}"
        skip=false
        for blocked in "${blockedHosts[@]}"; do
            normalizedBlocked=${blocked#www.}
            if [[ "${host}" == "${blocked}" || "${host}" == "${normalizedBlocked}" || "${host}" == *."${normalizedBlocked}" || "${host}" == *."${blocked}" ]]; then
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

realityTargetResultsFile() {
    printf '%s\n' "${PADM_REALITY_TARGET_RESULTS_FILE:-/etc/padm/reality_targets_results.tsv}"
}

realityTargetResultCount() {
    local resultsFile
    resultsFile=$(realityTargetResultsFile)
    [[ -f "${resultsFile}" ]] || {
        printf '0\n'
        return 0
    }
    awk -F'\t' '$10 == "A" || $10 == "B" {count++} END{print count + 0}' "${resultsFile}"
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

removeRealityTargetResultLine() {
    local target=$1
    local resultsFile tmpFile
    resultsFile=$(realityTargetResultsFile)
    [[ -f "${resultsFile}" ]] || return 0
    tmpFile="${resultsFile}.tmp"
    awk -F'\t' -v target="${target}" '$1 != target' "${resultsFile}" >"${tmpFile}"
    mv "${tmpFile}" "${resultsFile}"
}

removeRealityTargetCandidateLine() {
    local target=$1
    local parsed host candidatesFile tmpFile
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    candidatesFile=${PADM_REALITY_TARGET_CANDIDATES_FILE:-}
    [[ -n "${candidatesFile}" && -f "${candidatesFile}" ]] || return 0
    tmpFile="${candidatesFile}.tmp"
    awk -F'|' -v host="${host}" '$1 != host' "${candidatesFile}" >"${tmpFile}"
    mv "${tmpFile}" "${candidatesFile}"
}

removeRealityTargetFromUnifiedLibrary() {
    local target=$1
    removeRealityTargetResultLine "${target}"
    removeRealityTargetCandidateLine "${target}"
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
    local resultsFile tmpFile
    resultsFile=$(realityTargetResultsFile)
    mkdir -p "$(dirname "${resultsFile}")"
    tmpFile="${resultsFile}.tmp"
    if [[ -f "${resultsFile}" ]]; then
        awk -F'\t' -v target="${target}" '$1 != target' "${resultsFile}" >"${tmpFile}"
    else
        : >"${tmpFile}"
    fi
    formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${asn}" "${asOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}" >>"${tmpFile}"
    mv "${tmpFile}" "${resultsFile}"
}

writeRealityTargetResultLines() {
    local linesFile=$1
    local resultsFile tmpFile
    [[ -s "${linesFile}" ]] || return 0
    resultsFile=$(realityTargetResultsFile)
    mkdir -p "$(dirname "${resultsFile}")"
    tmpFile="${resultsFile}.tmp"
    if [[ -f "${resultsFile}" ]]; then
        awk -F'\t' '
          NR == FNR {
            if (!($1 in seen)) order[++count] = $1
            seen[$1] = 1
            line[$1] = $0
            next
          }
          !($1 in seen) { print }
          END {
            for (i = 1; i <= count; i++) print line[order[i]]
          }
        ' "${linesFile}" "${resultsFile}" >"${tmpFile}"
    else
        awk -F'\t' '
          {
            if (!($1 in seen)) order[++count] = $1
            seen[$1] = 1
            line[$1] = $0
          }
          END {
            for (i = 1; i <= count; i++) print line[order[i]]
          }
        ' "${linesFile}" >"${tmpFile}"
    fi
    mv "${tmpFile}" "${resultsFile}"
}

removeRealityTargetsFromUnifiedLibrary() {
    local targetsFile=$1
    local resultsFile candidatesFile tmpFile hostsFile target parsed host
    [[ -s "${targetsFile}" ]] || return 0
    resultsFile=$(realityTargetResultsFile)
    if [[ -f "${resultsFile}" ]]; then
        tmpFile="${resultsFile}.tmp"
        awk -F'\t' 'NR == FNR {targets[$1] = 1; next} !($1 in targets)' "${targetsFile}" "${resultsFile}" >"${tmpFile}"
        mv "${tmpFile}" "${resultsFile}"
    fi
    candidatesFile=${PADM_REALITY_TARGET_CANDIDATES_FILE:-}
    [[ -n "${candidatesFile}" && -f "${candidatesFile}" ]] || return 0
    hostsFile="${targetsFile}.hosts"
    : >"${hostsFile}"
    while IFS= read -r target; do
        [[ -n "${target}" ]] || continue
        parsed=$(parseHostPort "${target}" 443)
        host=${parsed%:*}
        printf '%s\n' "${host}" >>"${hostsFile}"
    done <"${targetsFile}"
    tmpFile="${candidatesFile}.tmp"
    awk -F'|' 'NR == FNR {hosts[$1] = 1; next} !($1 in hosts)' "${hostsFile}" "${candidatesFile}" >"${tmpFile}"
    mv "${tmpFile}" "${candidatesFile}"
    rm -f "${hostsFile}"
}

sortedRealityTargetResults() {
    local resultsFile
    resultsFile=$(realityTargetResultsFile)
    [[ -f "${resultsFile}" ]] || return 1
    awk -F'\t' '
      {
        scoreRank = ($10 == "A" ? 4 : ($10 == "B" ? 3 : ($10 == "C" ? 2 : ($10 == "FAIL" ? 0 : 1))))
        networkRank = ($9 == "same_asn" ? 4 : ($9 == "same_provider" ? 3 : ($9 == "different_network" ? 2 : 1)))
        cdnRank = ($5 == "no" ? 3 : ($5 == "unknown" ? 2 : 1))
        certRank = ($12 ~ /^[0-9]+$/ ? $12 : 0)
        checked = ($14 ~ /^[0-9]+$/ ? $14 : 0)
        printf "%d\t%d\t%d\t%d\t%d\t%s\n", scoreRank, networkRank, cdnRank, certRank, checked, $0
      }
    ' "${resultsFile}" | sort -t $'\t' -k1,1nr -k2,2nr -k3,3nr -k4,4nr -k5,5nr | cut -f6-
}

bestScannedRealityTargetLine() {
    sortedRealityTargetResults | awk -F'\t' '$10 == "A" || $10 == "B" {print; found=1; exit} END{if (!found) exit 1}'
}

selectScannedRealityTarget() {
    local line target sni parsed
    line=$(bestScannedRealityTargetLine) || return 1
    target=$(realityTargetResultField "${line}" 1)
    sni=$(realityTargetResultField "${line}" 2)
    parsed=$(parseHostPort "${target}" 443)
    realityTargetHost=${parsed%:*}
    realityTargetPort=${parsed##*:}
    realitySNI=${AUTO_REALITY_SERVER_NAME:-${sni:-${realityTargetHost}}}
}

resolveRealityTargetIPv4() {
    local host=$1
    local resolved=
    if command -v dig >/dev/null 2>&1; then
        resolved=$(dig +short A "${host}" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print; exit}')
    fi
    if [[ -z "${resolved}" ]] && command -v getent >/dev/null 2>&1; then
        resolved=$(getent ahostsv4 "${host}" | awk '/STREAM/ {print $1; exit}')
    fi
    if [[ -z "${resolved}" ]] && command -v host >/dev/null 2>&1; then
        resolved=$(host "${host}" | awk '/has address/ {print $4; exit}')
    fi
    [[ -n "${resolved}" ]] || return 1
    printf '%s\n' "${resolved}"
}

normalizeAsnOrg() {
    local value=$1
    printf '%s\n' "${value}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g'
}

lookupRealityTargetAsn() {
    local ip=$1
    local response asn org
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    response=$(curl -fsSL --connect-timeout 5 --max-time 10 "https://api.bgpview.io/ip/${ip}" 2>/dev/null || true)
    if [[ -n "${response}" ]] && command -v jq >/dev/null 2>&1; then
        asn=$(printf '%s\n' "${response}" | jq -r '.data.prefixes[0].asn.asn // empty' 2>/dev/null)
        org=$(printf '%s\n' "${response}" | jq -r '.data.prefixes[0].asn.name // empty' 2>/dev/null)
        if [[ -n "${asn}" ]]; then
            printf '%s\t%s\n' "AS${asn}" "$(normalizeAsnOrg "${org}")"
            return 0
        fi
    fi
    response=$(curl -fsSL --connect-timeout 5 --max-time 10 "https://ipinfo.io/${ip}/org" 2>/dev/null || true)
    if [[ "${response}" =~ ^AS[0-9]+ ]]; then
        asn=$(printf '%s\n' "${response}" | awk '{print $1}')
        org=$(printf '%s\n' "${response}" | cut -d' ' -f2-)
        printf '%s\t%s\n' "${asn}" "$(normalizeAsnOrg "${org}")"
        return 0
    fi
    return 1
}

currentRealityNetworkProfile() {
    local currentIp profile
    currentIp=$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)
    [[ "${currentIp}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    profile=$(lookupRealityTargetAsn "${currentIp}") || return 1
    printf '%s\t%s\n' "${currentIp}" "${profile}"
}

realityTargetAsnSummary() {
    local host=$1
    local ip profile asn org
    ip=$(resolveRealityTargetIPv4 "${host}") || {
        printf '未知（解析失败）\n'
        return 1
    }
    profile=$(lookupRealityTargetAsn "${ip}") || {
        printf '%s（ASN 未识别）\n' "${ip}"
        return 1
    }
    asn=${profile%%$'\t'*}
    org=${profile#*$'\t'}
    printf '%s %s %s\n' "${ip}" "${asn}" "${org}"
}

currentRealityAsnSummary() {
    local profile ip rest asn org
    profile=$(currentRealityNetworkProfile) || {
        printf '未知（公网 ASN 未识别）\n'
        return 1
    }
    ip=${profile%%$'\t'*}
    rest=${profile#*$'\t'}
    asn=${rest%%$'\t'*}
    org=${rest#*$'\t'}
    printf '%s %s %s\n' "${ip}" "${asn}" "${org}"
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
    command -v curl >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    response=$(curl -fsSL --connect-timeout 10 --max-time 30 "https://stat.ripe.net/data/announced-prefixes/data.json?resource=${asn}" 2>/dev/null) || return 1
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
    local rangesFile prefix range first last count generated=0 prefixIndex offset ip maxAttempts attempts nextIp
    declare -a rangeFirsts=()
    declare -a rangeLasts=()
    declare -a rangeCounts=()
    declare -a rangeNexts=()
    padmCreateTempPath rangesFile || return 1
    while IFS= read -r prefix; do
        range=$(realityAsnPrefixUsableRange "${prefix}" || true)
        [[ -n "${range}" ]] && printf '%s\n' "${range}" >>"${rangesFile}"
    done <"${prefixFile}"
    while IFS=$'\t' read -r first last count; do
        rangeFirsts+=("${first}")
        rangeLasts+=("${last}")
        rangeCounts+=("${count}")
        rangeNexts+=("${first}")
    done <"${rangesFile}"
    padmRemoveCleanupPath "${rangesFile}"
    : >"${outputFile}"
    [[ "${#rangeFirsts[@]}" -gt 0 && "${targetCount}" -gt 0 ]] || return 1
    while (( generated < targetCount )); do
        for prefixIndex in "${!rangeFirsts[@]}"; do
            (( generated >= targetCount )) && break
            first=${rangeFirsts[${prefixIndex}]}
            last=${rangeLasts[${prefixIndex}]}
            count=${rangeCounts[${prefixIndex}]}
            nextIp=${rangeNexts[${prefixIndex}]}
            if (( nextIp > last )); then
                continue
            fi
            offset=$((RANDOM % count))
            ip=$((first + offset))
            maxAttempts=${count}
            attempts=0
            while (( attempts < maxAttempts )); do
                if (( ip < first || ip > last )); then
                    ip=${first}
                fi
                if (( ip >= nextIp )); then
                    printf '%s\n' "$(realityIntToIpv4 "${ip}")" >>"${outputFile}"
                    rangeNexts[${prefixIndex}]=$((ip + 1))
                    generated=$((generated + 1))
                    break
                fi
                ip=$((ip + 1))
                attempts=$((attempts + 1))
            done
        done
        if (( generated < targetCount )); then
            local hasRemaining=false
            for prefixIndex in "${!rangeFirsts[@]}"; do
                if (( rangeNexts[${prefixIndex}] <= rangeLasts[${prefixIndex}] )); then
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

realityTargetDetector() {
    if [[ -x "/etc/padm/xray/xray" ]]; then
        printf '%s\n' "/etc/padm/xray/xray"
    elif command -v xray >/dev/null 2>&1; then
        command -v xray
    else
        return 1
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
    "" | all | 全部)
        return 0
        ;;
    recommended | 推荐)
        [[ "${recommended}" == "yes" ]]
        return
        ;;
    developer | dev | 开发者)
        [[ "${category}" == "developer" ]]
        return
        ;;
    media | 媒体)
        [[ "${category}" == "media" ]]
        return
        ;;
    asia | 亚洲)
        [[ "${region}" == "asia" ]]
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
    local filter=${1:-recommended}
    local page=${2:-1}
    local pageSize=${3:-12}
    local total start end line index=1 host sni name region category cdn rank recommended note marker
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
            IFS='|' read -r host sni name region category cdn rank recommended note <<<"${line}"
            marker=""
            [[ "${cdn}" == "yes" ]] && marker="谨慎"
            menuItem "${index}" "${host}:443" "${name} ${marker} ${region}/${category} SNI=${sni}"
            [[ -n "${note}" ]] && menuLine "    ${note}"
        fi
        index=$((index + 1))
    done < <(realityTargetFilteredCandidates "${filter}")
    menuClose
}

selectRealityTargetCandidateInteractive() {
    local filter=${1:-recommended}
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
            menuLine "可输入：recommended/developer/media/asia/manual/all，或任意关键词"
            menuClose
            autoRead reality_target_filter "请输入筛选条件[回车推荐]：" filter
            filter=${filter:-recommended}
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
    local detector line host sni name category cdn target tlsPingResult result score pqc certLength tls13 note checkedAt
    local probeLimit probed=0 bestRank=0 bestCert=0 bestHost= bestPort=443 bestSni= bestTarget= bestScore= bestPqc= bestCertLength=
    local scoreRank certRank

    if ! detector=$(realityTargetDetector); then
        realityTargetStatusBlock yellow "REALITY 自动推荐" "未找到 xray，无法实测目标质量" "已回退默认目标 www.ibm.com:443"
        return 1
    fi

    probeLimit=${PADM_REALITY_AUTO_PROBE_LIMIT:-10}
    [[ "${probeLimit}" =~ ^[0-9]+$ && "${probeLimit}" -gt 0 ]] || probeLimit=10

    while IFS= read -r line; do
        IFS='|' read -r host sni name _region category cdn _rank _recommended _note <<<"${line}"
        target=$(formatRealityTarget "${host}" 443)
        probed=$((probed + 1))
        realityTargetStatusBlock yellow "REALITY 自动推荐" "正在实测: ${target}" "SNI: ${sni}" "进度: ${probed}/${probeLimit}"
        checkedAt=$(date +%s)
        if tlsPingResult=$("${detector}" tls ping "${target}" 2>&1); then
            result=$(scoreRealityTargetFromTlsPing "${tlsPingResult}")
        else
            result=$(scoreRealityTargetFromTlsPing "")
        fi
        IFS=$'\t' read -r score pqc certLength tls13 note <<<"${result}"
        writeRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdn}" "unknown" "unknown" "unknown" "auto_probe" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "自动推荐实测: ${note}"

        case "${score}" in
        A) scoreRank=4 ;;
        B) scoreRank=3 ;;
        *) scoreRank=0 ;;
        esac
        certRank=0
        [[ "${certLength}" =~ ^[0-9]+$ ]] && certRank=${certLength}
        if (( scoreRank > bestRank || (scoreRank == bestRank && certRank > bestCert) )); then
            bestRank=${scoreRank}
            bestCert=${certRank}
            bestHost=${host}
            bestSni=${sni}
            bestTarget=${target}
            bestScore=${score}
            bestPqc=${pqc}
            bestCertLength=${certLength}
        fi
        (( probed >= probeLimit )) && break
    done < <(realityTargetFilteredCandidates recommended)

    if (( bestRank >= 3 )); then
        realityTargetHost=${bestHost}
        realityTargetPort=${bestPort}
        realitySNI=${AUTO_REALITY_SERVER_NAME:-${bestSni}}
        realityTargetStatusBlock green "REALITY 自动推荐" "已选择: ${bestTarget}" "评分: ${bestScore}" "X25519MLKEM768: ${bestPqc}" "证书链长度: ${bestCertLength}" "实测候选: ${probed}"
        return 0
    fi

    realityTargetStatusBlock yellow "REALITY 自动推荐" "推荐候选未得到 A/B 级实测结果" "已回退默认目标 www.ibm.com:443"
    return 1
}

selectDefaultRealityTarget() {
    if selectScannedRealityTarget; then
        return 0
    fi
    if selectAutoRecommendedRealityTarget; then
        return 0
    fi
    realityTargetHost=www.ibm.com
    realityTargetPort=443
    realitySNI=${AUTO_REALITY_SERVER_NAME:-www.ibm.com}
}

selectRandomRealityTargetCandidate() {
    local count randomNum line host sni
    count=$(realityTargetCandidateCount)
    randomNum=$(randomNum 1 "${count}")
    line=$(realityTargetCandidateLineByIndex "${randomNum}") || line=$(realityTargetCandidateLineByIndex 1)
    host=$(realityTargetCandidateField "${line}" 1)
    sni=$(realityTargetCandidateField "${line}" 2)
    realityTargetHost=${host}
    realityTargetPort=443
    realitySNI=${AUTO_REALITY_SERVER_NAME:-${sni}}
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
    local parsed host
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    writeRealityTargetResultLine "${target}" "${host}" "${host}" "manual" "unknown" "unknown" "unknown" "unknown" "unknown" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}"
}

scoreRealityTargetFromTlsPing() {
    local tlsPingResult=$1
    local score="FAIL"
    local pqc="no"
    local certLength="unknown"
    local tls13="unknown"
    local note="未检测到可用 TLS 1.3 握手"

    if echo "${tlsPingResult}" | grep -qi "TLS Post-Quantum key exchange:.*X25519MLKEM768"; then
        pqc="yes"
    fi
    certLength=$(echo "${tlsPingResult}" | awk '/Pinging with SNI/{inSni=1; next} inSni && /Certificate chain/{print $5; exit}')
    [[ "${certLength}" =~ ^[0-9]+$ ]] || certLength="unknown"
    if echo "${tlsPingResult}" | grep -qi "TLS.*1\.3\|TLSv1\.3"; then
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
    local profile candidateAsn candidateOrg networkMatch
    profile=$(lookupRealityTargetAsn "${ip}" || true)
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

importRealityScannerResults() {
    local sourceFile=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local summaryVar=${4:-}
    local detector ip origin domain issuer geo target tlsPingResult result score pqc certLength tls13 note checkedAt imported=0 skipped=0 processed=0 totalRecords importStart lastProgressAt=0 now profile candidateAsn candidateOrg networkMatch countA=0 countB=0 countC=0 countFail=0
    local resultLinesFile failedTargetsFile
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
    totalRecords=$(awk -F, 'NR > 1 && $1 != "" {count++} END{print count + 0}' "${sourceFile}")
    padmCreateTempPath resultLinesFile || return 1
    padmCreateTempPath failedTargetsFile || { padmRemoveCleanupPath "${resultLinesFile}"; return 1; }
    importStart=$(date +%s)
    while IFS=, read -r ip origin domain issuer geo; do
        [[ "${ip}" == "IP" ]] && continue
        processed=$((processed + 1))
        domain=${domain#\"}
        domain=${domain%\"}
        issuer=${issuer#\"}
        issuer=${issuer%\"}
        now=$(date +%s)
        if (( lastProgressAt == 0 || now - lastProgressAt >= 10 || processed == totalRecords )); then
            realityTargetProgressLine "RealiTLScanner 二次检测 ${processed}/${totalRecords} 当前：${domain:-未知} 已耗时：$((now - importStart))s"
            lastProgressAt=${now}
        fi
        if ! realityTargetScannerRecordAllowed "${domain}"; then
            skipped=$((skipped + 1))
            continue
        fi
        target=$(formatRealityTarget "${domain}" 443)
        checkedAt=$(date +%s)
        profile=$(scannerRealityNetworkProfile "${ip}" "${currentAsn}" "${currentOrg}")
        IFS=$'\t' read -r candidateAsn candidateOrg networkMatch <<<"${profile}"
        if ! tlsPingResult=$("${detector}" tls ping -ip "${ip}" "${target}" 2>&1); then
            printf '%s\n' "${target}" >>"${failedTargetsFile}"
            countFail=$((countFail + 1))
            skipped=$((skipped + 1))
            continue
        fi
        result=$(scoreRealityTargetFromTlsPing "${tlsPingResult}")
        IFS=$'\t' read -r score pqc certLength tls13 note <<<"${result}"
        checkedAt=$(date +%s)
        if [[ "${score}" == "FAIL" ]]; then
            printf '%s\n' "${target}" >>"${failedTargetsFile}"
            countFail=$((countFail + 1))
            skipped=$((skipped + 1))
            continue
        fi
        formatRealityTargetResultLine "${target}" "${domain}" "${domain}" "scanner" "unknown" "${ip}" "${candidateAsn}" "${candidateOrg}" "${networkMatch}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "RealiTLScanner: ${issuer}; ${note}" >>"${resultLinesFile}"
        case "${score}" in
        A) countA=$((countA + 1)) ;;
        B) countB=$((countB + 1)) ;;
        C) countC=$((countC + 1)) ;;
        esac
        imported=$((imported + 1))
    done < "${sourceFile}"
    writeRealityTargetResultLines "${resultLinesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    padmRemoveCleanupPath "${resultLinesFile}"
    padmRemoveCleanupPath "${failedTargetsFile}"
    if [[ -n "${summaryVar}" ]]; then
        printf -v "${summaryVar}" '%s\t%s\t%s\t%s\t%s\t%s' "${imported}" "${skipped}" "${countA}" "${countB}" "${countC}" "${countFail}"
    fi
    realityTargetStatusBlock green "RealiTLScanner 导入" "写入: ${imported}" "剔除/跳过: ${skipped}" "A: ${countA}" "B: ${countB}" "C: ${countC}" "FAIL剔除: ${countFail}" "耗时: $(($(date +%s) - importStart))s"
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
    local version=
    local assetName="RealiTLScanner-linux-64"

    if [[ -x "${scannerBin}" ]]; then
        return 0
    fi

    rm -rf "${scannerDir}"
    mkdir -p "${scannerDir}"
    realityTargetStatusBlock yellow "RealiTLScanner 下载" "正在下载官方 Release 二进制"
    version=$(curl -fsSL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/XTLS/RealiTLScanner/releases?per_page=1" | jq -r '.[0].tag_name // empty') || return 1
    if [[ -z "${version}" ]]; then
        realityTargetStatusBlock red "RealiTLScanner 下载" "未获取到最新 Release 版本"
        return 1
    fi
    if ! downloadGitHubReleaseAsset -P "${scannerDir}" "XTLS/RealiTLScanner" "${version}" "${assetName}"; then
        realityTargetStatusBlock red "RealiTLScanner 下载" "下载 Release 资产失败: ${assetName}"
        return 1
    fi
    if [[ ! -f "${scannerDir}/${assetName}" ]]; then
        realityTargetStatusBlock red "RealiTLScanner 下载" "Release 资产不存在: ${assetName}"
        return 1
    fi
    mv "${scannerDir}/${assetName}" "${scannerBin}"
    chmod 755 "${scannerBin}"
}

runRealityScannerRange() {
    local scanRange=$1
    local scannerDir scannerBin outputFile startAt elapsed scannerStatus scannerPid
    [[ -n "${scanRange}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "扫描范围为空"
        return 1
    }
    scannerDir=$(realityScannerDir)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
    outputFile=$(realityScannerOutputPath "$(date +%s)")
    startAt=$(date +%s)
    realityTargetProgressLine "RealiTLScanner 扫描范围：${scanRange} 已耗时：0s"
    "${scannerBin}" -addr "${scanRange}" -thread 20 -timeout 3 -out "${outputFile}" &
    scannerPid=$!
    while kill -0 "${scannerPid}" >/dev/null 2>&1; do
        sleep 10
        realityTargetProgressLine "RealiTLScanner 扫描范围：${scanRange} 已耗时：$(($(date +%s) - startAt))s"
    done
    scannerStatus=0
    wait "${scannerPid}" || scannerStatus=$?
    if [[ ${scannerStatus} -ne 0 ]]; then
        if [[ ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock red "RealiTLScanner 扫描" "执行失败，且未生成有效结果文件"
            return 1
        fi
        realityTargetStatusBlock yellow "RealiTLScanner 扫描" "返回非零状态，但已生成结果文件" "继续导入结果"
    fi
    elapsed=$(( $(date +%s) - startAt ))
    realityTargetStatusBlock green "RealiTLScanner 扫描" "扫描完成" "耗时: ${elapsed}s" "结果: ${outputFile}"
    importRealityScannerResults "${outputFile}"
}

runRealityScannerTargetFile() {
    local targetFile=$1
    local currentAsn=${2:-}
    local currentOrg=${3:-}
    local scannerDir scannerBin outputFile batchFile startAt elapsed scannerStatus scannerPid total batchSize batchIndex processed batchCount totalStartAt totalElapsed importSummary batchImported batchSkipped batchA batchB batchC batchFail totalImported=0 totalSkipped=0 totalA=0 totalB=0 totalC=0 totalFail=0
    [[ -f "${targetFile}" && -s "${targetFile}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "目标列表为空"
        return 1
    }
    scannerDir=$(realityScannerDir)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
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
        "${scannerBin}" -in "${batchFile}" -thread 20 -timeout 3 -out "${outputFile}" &
        scannerPid=$!
        while kill -0 "${scannerPid}" >/dev/null 2>&1; do
            sleep 10
            realityTargetProgressLine "RealiTLScanner 抽样扫描进度：$((processed + 1))-$((processed + batchCount))/${total} 已耗时：$(($(date +%s) - startAt))s"
        done
        scannerStatus=0
        wait "${scannerPid}" || scannerStatus=$?
        padmRemoveCleanupPath "${batchFile}"
        if [[ ${scannerStatus} -ne 0 && ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock yellow "RealiTLScanner 扫描" "抽样批次失败且无结果" "进度: $((processed + batchCount))/${total}" "继续扫描剩余目标"
            processed=$((processed + batchCount))
            continue
        fi
        elapsed=$(( $(date +%s) - startAt ))
        processed=$((processed + batchCount))
        realityTargetStatusBlock green "RealiTLScanner 扫描" "抽样批次完成" "进度: ${processed}/${total}" "耗时: ${elapsed}s" "结果: ${outputFile}"
        if [[ -s "${outputFile}" ]]; then
            importRealityScannerResults "${outputFile}" "${currentAsn}" "${currentOrg}" importSummary
            IFS=$'\t' read -r batchImported batchSkipped batchA batchB batchC batchFail <<<"${importSummary}"
            totalImported=$((totalImported + batchImported))
            totalSkipped=$((totalSkipped + batchSkipped))
            totalA=$((totalA + batchA))
            totalB=$((totalB + batchB))
            totalC=$((totalC + batchC))
            totalFail=$((totalFail + batchFail))
        fi
    done
    totalElapsed=$(( $(date +%s) - totalStartAt ))
    realityTargetStatusBlock green "RealiTLScanner 抽样扫描汇总" "扫描目标: ${total}" "写入结果: ${totalImported}" "剔除/跳过: ${totalSkipped}" "A: ${totalA}" "B: ${totalB}" "C: ${totalC}" "FAIL剔除: ${totalFail}" "总耗时: ${totalElapsed}s"
}


runRealityScannerPrefixFile() {
    local prefixFile=$1
    local scannerDir scannerBin outputFile startAt elapsed scannerStatus scannerPid prefix total index=0
    [[ -f "${prefixFile}" && -s "${prefixFile}" ]] || {
        realityTargetStatusBlock red "RealiTLScanner 扫描" "prefix 列表为空"
        return 1
    }
    scannerDir=$(realityScannerDir)
    scannerBin="${scannerDir}/RealiTLScanner"
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" || return 1
    total=$(wc -l <"${prefixFile}" | tr -d ' ')
    while IFS= read -r prefix; do
        [[ -n "${prefix}" ]] || continue
        index=$((index + 1))
        outputFile=$(realityScannerOutputPath "$(date +%s)" "${index}")
        startAt=$(date +%s)
        realityTargetProgressLine "RealiTLScanner 扫描 prefix ${index}/${total}：${prefix} 已耗时：0s"
        "${scannerBin}" -addr "${prefix}" -thread 20 -timeout 3 -out "${outputFile}" &
        scannerPid=$!
        while kill -0 "${scannerPid}" >/dev/null 2>&1; do
            sleep 10
            realityTargetProgressLine "RealiTLScanner 扫描 prefix ${index}/${total}：${prefix} 已耗时：$(($(date +%s) - startAt))s"
        done
        scannerStatus=0
        wait "${scannerPid}" || scannerStatus=$?
        if [[ ${scannerStatus} -ne 0 && ! -s "${outputFile}" ]]; then
            realityTargetStatusBlock yellow "RealiTLScanner 扫描" "prefix 扫描失败且无结果: ${prefix}" "继续扫描剩余 prefix"
            continue
        fi
        elapsed=$(( $(date +%s) - startAt ))
        realityTargetStatusBlock green "RealiTLScanner 扫描" "prefix 完成: ${prefix}" "进度: ${index}/${total}" "耗时: ${elapsed}s" "结果: ${outputFile}"
        [[ -s "${outputFile}" ]] && importRealityScannerResults "${outputFile}"
    done <"${prefixFile}"
}

runRealityScannerAdvanced() {
    local currentIp scanRange confirm selectedRealityScannerRange
    currentIp=$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ipify.org 2>/dev/null || true)
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
        runRealityScannerPrefixFile "${selectedRealityScannerPrefixFile}"
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
    local detector tlsPingResult result score pqc certLength tls13 note checkedAt detectStart detectSeconds
    if ! detector=$(realityTargetDetector); then
        realityTargetStatusBlock yellow "REALITY 目标站检测" "未找到 xray，无法在线检测" "安装核心后可在 REALITY 管理中检测"
        return 1
    fi
    realityTargetStatusBlock yellow "REALITY 目标站检测" "正在检测: ${target}"
    detectStart=$(date +%s)
    if ! tlsPingResult=$("${detector}" tls ping "${target}" 2>&1); then
        checkedAt=$(date +%s)
        detectSeconds=$((checkedAt - detectStart))
        removeRealityTargetFromUnifiedLibrary "${target}"
        realityTargetStatusBlock red "REALITY 目标站检测" "目标站检测失败: ${target}" "耗时: ${detectSeconds}s" "已从统一目标库记录中剔除"
        return 1
    fi
    result=$(scoreRealityTargetFromTlsPing "${tlsPingResult}")
    score=$(printf '%s\n' "${result}" | awk -F'\t' '{print $1}')
    pqc=$(printf '%s\n' "${result}" | awk -F'\t' '{print $2}')
    certLength=$(printf '%s\n' "${result}" | awk -F'\t' '{print $3}')
    tls13=$(printf '%s\n' "${result}" | awk -F'\t' '{print $4}')
    note=$(printf '%s\n' "${result}" | awk -F'\t' '{print $5}')
    checkedAt=$(date +%s)
    detectSeconds=$((checkedAt - detectStart))
    writeRealityTargetCacheLine "${target}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}"
    realityTargetStatusBlock green "REALITY 目标站检测" "评分: $(realityTargetScoreStyle "${score}")" "X25519MLKEM768: ${pqc}" "TLS1.3: ${tls13}" "证书链长度: ${certLength}" "耗时: ${detectSeconds}s" "结论: ${note}"
}

showRealityTargetQualityActions() {
    local target=$1
    local action confirm
    echoContent title "\n┌─ REALITY 目标站后续操作 ─────────────────────────────"
    menuItem 1 "去查看/切换检测结果" "打开检测结果列表，在原切换菜单里选择 A/B 级目标"
    menuItem 2 "加入目标站黑名单" "后续不参与统一目标库刷新和扫描导入"
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
        errorCard "选择错误"
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
    A|a) printf 'A 级\n' ;;
    B|b) printf 'B 级\n' ;;
    AB|ab|available|可选) printf 'A/B 可选\n' ;;
    same_asn|同ASN) printf '同 ASN\n' ;;
    same_provider|同提供商|相近网络) printf '同提供商\n' ;;
    local_network|同网络|本机网络) printf '同网络\n' ;;
    C|c) printf 'C 级\n' ;;
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
    case "${filter}" in
    A|a)
        [[ "${score}" == "A" ]]
        ;;
    B|b)
        [[ "${score}" == "B" ]]
        ;;
    AB|ab|available|可选)
        [[ "${score}" == "A" || "${score}" == "B" ]]
        ;;
    same_asn|同ASN)
        [[ "${networkMatch}" == "same_asn" ]]
        ;;
    same_provider|同提供商|相近网络)
        [[ "${networkMatch}" == "same_provider" ]]
        ;;
    local_network|同网络|本机网络)
        [[ "${networkMatch}" == "same_asn" || "${networkMatch}" == "same_provider" ]]
        ;;
    C|c)
        [[ "${score}" == "C" ]]
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
        echoContent title "\n┌─ REALITY 检测结果范围 ─────────────────────────────"
        menuItem 1 "A 级" "TLS1.3 + X25519MLKEM768 + 证书链长度达标"
        menuItem 2 "B 级" "TLS1.3 + X25519MLKEM768，证书链长度未达 A 级"
        menuItem 3 "A/B 可选" "只看可用于切换的结果"
        menuItem 4 "同 ASN" "只看 network=same_asn"
        menuItem 5 "同提供商" "只看 network=same_provider"
        menuItem 6 "同网络" "显示 same_asn 和 same_provider"
        menuItem 7 "C 级" "TLS1.3 可用但未检测到 X25519MLKEM768"
        menuItem 8 "RealiTLScanner" "只看 category=scanner 的网段扫描结果"
        menuItem 9 "全部" "显示所有实测结果"
        menuReturnItem 10 "返回" "回到 REALITY 目标站管理"
        menuClose
    } >&2
    autoRead reality_target_result_filter "请选择查看范围[默认3=A/B可选]:" selected
    case "${selected:-3}" in
    1) printf 'A\n' ;;
    2) printf 'B\n' ;;
    3) printf 'AB\n' ;;
    4) printf 'same_asn\n' ;;
    5) printf 'same_provider\n' ;;
    6) printf 'local_network\n' ;;
    7) printf 'C\n' ;;
    8) printf 'scanner\n' ;;
    9) printf 'all\n' ;;
    10|r|R) printf 'return\n' ;;
    *) return 1 ;;
    esac
}

showRealityTargetScanResults() {
    local filter=${1:-}
    local mode=${2:-interactive}
    local page=${3:-1} pageSize=${REALITY_TARGET_RESULT_PAGE_SIZE:-10} total maxPage choice
    local line itemIndex=0 pageIndex=1 start end target sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note checkedTime marker titleFilter selectedLine selectedScore selectedTarget selectedSni parsed absoluteIndex
    if ! sortedRealityTargetResults >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 目标站结果" "暂无 Reality 目标站检测结果"
        return 1
    fi
    if [[ -z "${filter}" ]]; then
        filter=$(selectRealityTargetScanResultFilter) || return 1
    fi
    if [[ "${filter}" == "return" ]]; then
        return 0
    fi
    while true; do
        total=0
        while IFS= read -r line; do
            IFS=$'\t' read -r _target _sni _name category _cdnRisk _ip _asn _asOrg networkMatch score _pqc _certLength _tls13 _checkedAt _note <<<"${line}"
            realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" && total=$((total + 1))
        done < <(sortedRealityTargetResults)
        maxPage=$(( (total + pageSize - 1) / pageSize ))
        (( maxPage < 1 )) && maxPage=1
        (( page > maxPage )) && page=${maxPage}
        (( page < 1 )) && page=1
        start=$(( (page - 1) * pageSize + 1 ))
        end=$(( page * pageSize ))
        titleFilter=$(realityTargetFilterTitle "${filter}")
        echoContent title "\n┌─ REALITY 目标站实测结果：${titleFilter} ───────────────────────────"
        menuLine "筛选条件：${filter}；第 ${page}/${maxPage} 页；总数：${total}；n 下一页；p 上一页；f 重新筛选；r 返回"
        itemIndex=0
        pageIndex=1
        while IFS= read -r line; do
            IFS=$'\t' read -r target sni name category cdnRisk ip asn asOrg networkMatch score pqc certLength tls13 checkedAt note <<<"${line}"
            realityTargetScanResultFilterMatches "${score}" "${networkMatch}" "${filter}" "${category}" || continue
            itemIndex=$((itemIndex + 1))
            (( itemIndex < start || itemIndex > end )) && continue
            checkedTime=$(date -d "@${checkedAt}" "+%F %T" 2>/dev/null || printf '%s' "${checkedAt}")
            marker=""
            [[ "${score}" == "A" || "${score}" == "B" ]] && marker="可选"
            menuItem "${pageIndex}" "${target}" "${marker} ${score} | X25519MLKEM768=${pqc} | cert=${certLength} | TLS1.3=${tls13} | network=${networkMatch}"
            menuLine "    cdn_risk=${cdnRisk} checked=${checkedTime} SNI=${sni} IP=${ip} ASN=${asn} ${asOrg}"
            menuLine "    name=${name} category=${category}"
            [[ -n "${note}" ]] && menuLine "    ${note}"
            pageIndex=$((pageIndex + 1))
        done < <(sortedRealityTargetResults)
        [[ "${total}" == "0" ]] && menuLine "当前范围没有检测结果"
        menuClose
        if [[ "${mode}" == "once" ]]; then
            return 0
        fi
        autoRead reality_target_result_page "请选择本页编号切换 A/B，n/p/f/r，回车返回:" choice
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
                selectedLine=$(realityTargetResultLineByFilteredIndex "${filter}" "${absoluteIndex}") || {
                    errorCard "本页编号无效，请重新选择"
                    continue
                }
                selectedScore=$(realityTargetResultField "${selectedLine}" 10)
                if [[ "${selectedScore}" != "A" && "${selectedScore}" != "B" ]]; then
                    errorCard "只有 A/B 级检测结果可直接切换"
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

scanLocalAsnRealityTargets() {
    local detector networkProfile currentIp currentAsn currentOrg line host sni target name category cdnRisk ip candidateProfile candidateAsn candidateOrg source tlsPingResult result score pqc certLength tls13 note checkedAt scanned=0 resolved=0 failed=0 sameAsn=0 sameProvider=0 differentNetwork=0 scanStart scanSeconds totalCandidates lastProgressAt=0 now
    local resultLinesFile failedTargetsFile
    if ! detector=$(realityTargetDetector); then
        realityTargetStatusBlock yellow "REALITY 目标站扫描" "未找到 xray，无法扫描目标质量" "安装核心后再执行扫描"
        return 1
    fi
    if ! networkProfile=$(currentRealityNetworkProfile); then
        realityTargetStatusBlock yellow "REALITY 目标站扫描" "无法识别本机公网 ASN" "已跳过同 ASN 扫描"
        return 1
    fi
    scanStart=$(date +%s)
    totalCandidates=$(realityTargetCandidateCount)
    padmCreateTempPath resultLinesFile || return 1
    padmCreateTempPath failedTargetsFile || { padmRemoveCleanupPath "${resultLinesFile}"; return 1; }
    currentIp=${networkProfile%%$'\t'*}
    local rest=${networkProfile#*$'\t'}
    currentAsn=${rest%%$'\t'*}
    currentOrg=${rest#*$'\t'}
    realityTargetStatusBlock yellow "REALITY 目标库质量刷新" "本机公网网络: ${currentIp} ${currentAsn} ${currentOrg}" "正在复测统一目标库并写入结果表: $(realityTargetResultsFile)"

    while IFS= read -r line; do
        IFS='|' read -r host sni name _region category cdnRisk _rank _recommended _note <<<"${line}"
        target=$(formatRealityTarget "${host}" 443)
        scanned=$((scanned + 1))
        now=$(date +%s)
        if (( lastProgressAt == 0 || now - lastProgressAt >= 10 || scanned == totalCandidates )); then
            realityTargetProgressLine "REALITY 目标库质量刷新 ${scanned}/${totalCandidates} 当前：${host} 已耗时：$((now - scanStart))s"
            lastProgressAt=${now}
        fi
        if ! ip=$(resolveRealityTargetIPv4 "${host}"); then
            failed=$((failed + 1))
            continue
        fi
        if ! candidateProfile=$(lookupRealityTargetAsn "${ip}"); then
            failed=$((failed + 1))
            continue
        fi
        candidateAsn=${candidateProfile%%$'\t'*}
        candidateOrg=${candidateProfile#*$'\t'}
        source=different_network
        if [[ "${candidateAsn}" == "${currentAsn}" ]]; then
            source=same_asn
            sameAsn=$((sameAsn + 1))
        elif realityTargetProviderMatches "${currentOrg}" "${candidateOrg}"; then
            source=same_provider
            sameProvider=$((sameProvider + 1))
        else
            differentNetwork=$((differentNetwork + 1))
        fi
        resolved=$((resolved + 1))
        if ! tlsPingResult=$("${detector}" tls ping "${target}" 2>&1); then
            checkedAt=$(date +%s)
            result=$(scoreRealityTargetFromTlsPing "")
            IFS=$'\t' read -r score pqc certLength tls13 _note <<<"${result}"
            note="tls ping 失败，已从统一目标库剔除"
            printf '%s\n' "${target}" >>"${failedTargetsFile}"
            continue
        fi
        result=$(scoreRealityTargetFromTlsPing "${tlsPingResult}")
        IFS=$'\t' read -r score pqc certLength tls13 note <<<"${result}"
        checkedAt=$(date +%s)
        if [[ "${score}" == "FAIL" ]]; then
            printf '%s\n' "${target}" >>"${failedTargetsFile}"
            continue
        fi
        formatRealityTargetResultLine "${target}" "${sni}" "${name}" "${category}" "${cdnRisk}" "${ip}" "${candidateAsn}" "${candidateOrg}" "${source}" "${score}" "${pqc}" "${certLength}" "${tls13}" "${checkedAt}" "${note}" >>"${resultLinesFile}"
    done < <(realityTargetCandidates)

    writeRealityTargetResultLines "${resultLinesFile}"
    removeRealityTargetsFromUnifiedLibrary "${failedTargetsFile}"
    padmRemoveCleanupPath "${resultLinesFile}"
    padmRemoveCleanupPath "${failedTargetsFile}"
    scanSeconds=$(( $(date +%s) - scanStart ))
    realityTargetStatusBlock green "REALITY 目标库质量刷新" "复测完成" "候选: ${scanned}" "ASN 已识别: ${resolved}" "same_asn: ${sameAsn}" "same_provider: ${sameProvider}" "different_network: ${differentNetwork}" "解析/ASN 失败: ${failed}" "耗时: ${scanSeconds}s"
    if [[ "$(realityTargetResultCount)" -gt 0 ]]; then
        realityTargetStatusBlock green "REALITY 目标库质量刷新" "自动推荐将优先使用统一结果表中的 A/B 级目标"
    else
        realityTargetStatusBlock yellow "REALITY 目标库质量刷新" "未得到 A/B 级结果" "自动推荐仍回退到 www.ibm.com:443"
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
    applyLog=$(realityTargetApplyLog)
    rm -f "${applyLog}" >/dev/null 2>&1 || true
    parsed=$(parseHostPort "${target}" 443)
    host=${parsed%:*}
    port=${parsed##*:}
    if ! validateRealityTarget "${host}" "${port}"; then
        realityTargetStatusBlock red "REALITY 目标站" "伪装目标不合法: ${target}"
        return 1
    fi
    [[ -n "${sni}" ]] || sni=${host}

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
            logFile=$(realityTargetXrayTestLog)
            /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >"${logFile}" 2>&1 || return 1
        fi
    fi
    if [[ -f "$(realitySingBoxVisionConfigPath)" || -f "$(realitySingBoxGrpcConfigPath)" ]]; then
        if [[ -x "/etc/padm/sing-box/sing-box" ]]; then
            logFile=$(realityTargetSingBoxTestLog)
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
        cp "${backupDir}/xray/07_VLESS_vision_reality_inbounds.json" "$(realityXrayVisionConfigPath)" || status=1
    fi
    if [[ -f "${backupDir}/xray/12_VLESS_XHTTP_inbounds.json" ]]; then
        cp "${backupDir}/xray/12_VLESS_XHTTP_inbounds.json" "$(realityXrayXhttpConfigPath)" || status=1
    fi
    if [[ -f "${backupDir}/sing-box/07_VLESS_vision_reality_inbounds.json" ]]; then
        cp "${backupDir}/sing-box/07_VLESS_vision_reality_inbounds.json" "$(realitySingBoxVisionConfigPath)" || status=1
    fi
    if [[ -f "${backupDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json" ]]; then
        cp "${backupDir}/sing-box/08_VLESS_vision_gRPC_inbounds.json" "$(realitySingBoxGrpcConfigPath)" || status=1
    fi
    return "${status}"
}

refreshSubscriptionsAfterRealityTargetChange() {
    if ! declare -F subscribe >/dev/null 2>&1 || ! declare -F installSubscribe >/dev/null 2>&1 || ! declare -F showAccounts >/dev/null 2>&1 || ! declare -F readNginxSubscribe >/dev/null 2>&1; then
        realityTargetStatusBlock yellow "REALITY 目标站" "订阅刷新依赖未完整加载，已跳过订阅刷新" "通过 install.sh 菜单执行时会自动刷新"
        return 0
    fi
    readNginxSubscribe
    if [[ -n "${subscribePort:-}" || -f "${nginxConfigPath:-/etc/nginx/conf.d/}subscribe.conf" ]]; then
        subscribe false
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
    padmCreateTempPath backupDir -d "$(realityTargetBackupTemplate)" || return 1
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
        realityTargetStatusBlock red "REALITY 目标站" "配置校验失败，已回滚" "Xray 日志: $(realityTargetXrayTestLog)" "sing-box 日志: $(realityTargetSingBoxTestLog)"
        return 1
    fi
    if ! reloadCore; then
        if ! restoreRealityTargetConfigs "${backupDir}"; then
            realityTargetStatusBlock red "REALITY 目标站" "核心重载失败，且回滚配置失败" "备份目录: ${backupDir}"
            padmForgetCleanupPath "${backupDir}"
            return 1
        fi
        restoreRealityTargetRuntimeState "${previousRealityTargetHost}" "${previousRealityTargetPort}" "${previousRealitySNI}" "${previousXrayVLESSRealitySNI}" "${previousXrayVLESSRealityXHTTPSNI}" "${previousSingBoxVLESSRealityVisionSNI}" "${previousSingBoxVLESSRealityGRPCSNI}"
        if reloadCore; then
            realityTargetStatusBlock red "REALITY 目标站" "核心重载失败，已回滚配置"
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
