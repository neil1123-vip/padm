#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

regressionModuleManifestReady() {
    [[ "${PADM_FAKE_MODULE_MANIFEST_READY:-0}" == "1" ]]
}

regressionScriptModulesReady() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]] || return 1
    regressionModuleManifestReady || return 1
    [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]] || return 0
    [[ -f "${SCRIPT_REF_FILE}" ]] || return 1
    [[ "$(<"${SCRIPT_EXPECTED_REF_FILE}")" == "$(<"${SCRIPT_REF_FILE}")" ]]
}

regressionEnsureScriptModules() {
    local remoteRef= expectedRef=
    if [[ "${PADM_FORCE_SCRIPT_MODULE_REFRESH:-}" == "1" ]]; then
        remoteRef=$(fetchRemoteRef || true)
        refreshScriptModules "${remoteRef}"
        [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
        return 0
    fi
    if regressionScriptModulesReady; then
        return 0
    fi
    if [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]]; then
        expectedRef=$(<"${SCRIPT_EXPECTED_REF_FILE}")
    fi
    if [[ "${PADM_SKIP_REMOTE_REF_CHECK:-}" == "1" ]]; then
        refreshScriptModules "${expectedRef}"
        return 0
    fi

    remoteRef="${expectedRef}"
    [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef || true)
    refreshScriptModules "${remoteRef}"
    [[ -n "${remoteRef}" ]] && printf '%s\n' "${remoteRef}" >"${SCRIPT_EXPECTED_REF_FILE}"
}

runCleanupTrapRegression() {
    local tmpDir exitProbe intProbe intOutput termProbe termOutput

    tmpDir=$(mktemp -d)
    exitProbe="${tmpDir}/exit.XXXXXX"
    intProbe="${tmpDir}/int.XXXXXX"
    termProbe="${tmpDir}/term.XXXXXX"
    intOutput="${tmpDir}/int.out"
    termOutput="${tmpDir}/term.out"
    bash -c 'source "$1"; padmCreateTempPath p "$2"; exit 0' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${exitProbe}"
    [[ ! -e "${exitProbe}" ]]
    set +e
    bash -c 'source "$1"; padmCreateTempPath p "$2"; kill -INT $$; exit 99' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${intProbe}" >"${intOutput}" 2>&1
    local intStatus=$?
    bash -c 'source "$1"; padmCreateTempPath p "$2"; kill -TERM $$; exit 99' _ "${PROJECT_ROOT}/shell/core/runtime.sh" "${termProbe}" >"${termOutput}" 2>&1
    local termStatus=$?
    set -e
    [[ ${intStatus} -eq 130 ]]
    [[ ${termStatus} -eq 143 ]]
    [[ ! -e "${intProbe}" ]]
    [[ ! -e "${termProbe}" ]]
    rm -rf "${tmpDir}"
}

resolveReleaseWorkflowVersionForRegression() {
    local isReleaseCommit=$1
    local currentVersion=$2
    local latestTag=$3
    local commits=$4
    local releaseVersion needsBump

    if [[ "${isReleaseCommit}" == "true" ]]; then
        releaseVersion="${currentVersion}"
        needsBump=false
    else
        releaseVersion="v$(nextScriptVersionFromCommits "${latestTag}" "${commits}")"
        if [[ "${releaseVersion}" != "${currentVersion}" ]]; then
            needsBump=true
        else
            needsBump=false
        fi
    fi
    printf '%s %s\n' "${releaseVersion}" "${needsBump}"
}

runReleaseWorkflowVersionRegression() {
    local result
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'fix(update): harden script refresh rollback')
    [[ "${result}" == "v1.2.1 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'feat(subscription): add new flow')
    [[ "${result}" == "v1.3.0 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v1.2.0 v1.2.0 $'style: whitespace only')
    [[ "${result}" == "v1.2.0 false" ]]
    result=$(resolveReleaseWorkflowVersionForRegression false v0.0.0 v0.0.0 $'feat(core): initial release')
    [[ "${result}" == "v0.1.0 true" ]]
    result=$(resolveReleaseWorkflowVersionForRegression true v1.3.0 v1.2.0 $'chore(release): v1.3.0')
    [[ "${result}" == "v1.3.0 false" ]]
}

runNginxBlogAutoInstallRegression() {
    local oldAutoInstall="${AUTO_INSTALL:-}"
    local staticDir="${TMP_DIR}/nginx-blog-auto/"
    mkdir -p "${staticDir}"
    : >"${staticDir}/check"
    printf 'keep\n' >"${staticDir}/index.html"

    nginxStaticPath="${staticDir}"
    lastInstallationConfig=
    AUTO_INSTALL=true
    autoRead() {
        return 1
    }
    nginxBlog
    [[ "$(<"${staticDir}/index.html")" == "keep" ]]
    AUTO_INSTALL="${oldAutoInstall}"
}

runXrayTrafficStatsJqCompatibilityRegression() (
    local fakeBin="${TMP_DIR}/fake-xray-stats-bin"
    mkdir -p "${fakeBin}"
    cat >"${fakeBin}/xray" <<'SH'
#!/usr/bin/env bash
cat <<'JSON'
{"stat":[{"name":"user>>>team-uplink","value":3},{"name":"user>>>team-uplink","value":4},{"name":"user>>>team-downlink","value":5},{"name":"user>>>team-downlink","value":"6"},{"name":"user>>>ignored-uplink","value":7},{"name":"inbound>>>api>>>traffic>>>uplink","value":99}]}
JSON
SH
    chmod +x "${fakeBin}/xray"
    XRAY_STATS_BINARY="${fakeBin}/xray"
    collectXrayTrafficStatsSnapshot '["team","missing"]' | jq -e '. == [{"account":"team","upload":7,"download":11},{"account":"missing","upload":0,"download":0}]' >/dev/null
)

runLocalTrafficAccountsBatchRegression() (
    local xrayConfig="${TMP_DIR}/traffic-xray-conf/"
    local singBoxConfig="${TMP_DIR}/traffic-sing-box-conf/"
    local accounts
    local snapshot
    local reloadMarker="${TMP_DIR}/traffic-reload"
    local originalStats
    local originalPolicy
    mkdir -p "${xrayConfig}" "${singBoxConfig}"
    configPath="${xrayConfig}"
    singBoxConfigPath="${singBoxConfig}"
    coreInstallType=1
    cat >"${xrayConfig}01_inbounds.json" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"email":"sub_team_a-vless"},{"email":"admin-root"}]}},{"users":[{"name":"sub_team_b-hysteria2"}]}]}
JSON
    cat >"${singBoxConfig}02_inbounds.json" <<'JSON'
{"inbounds":[{"users":[{"username":"sub_team_a-tuic"},{"username":"ops"}]}]}
JSON
    accounts=$(collectLocalTrafficAccounts)
    jq -R -s 'split("\n") | map(select(length > 0))' <<<"${accounts}" | jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' >/dev/null

    printf '{bad-json\n' >"${singBoxConfig}03_inbounds.json"
    if collectLocalTrafficAccounts >/dev/null 2>&1; then
        return 1
    fi
    snapshot=$(collectLocalTrafficSnapshot)
    jq -e '.ok == false and (.items | length) == 0' <<<"${snapshot}" >/dev/null

    rm -f "${singBoxConfig}03_inbounds.json" "${reloadMarker}" "${xrayConfig}13_stats_api.json" "${xrayConfig}12_policy.json"
    printf '{bad-json\n' >"${xrayConfig}12_policy.json"
    if ensureXrayTrafficStatsConfig >/dev/null 2>&1; then
        return 1
    fi
    [[ ! -e "${xrayConfig}13_stats_api.json" ]]
    [[ "$(<"${xrayConfig}12_policy.json")" == "{bad-json" ]]

    cat >"${xrayConfig}13_stats_api.json" <<'JSON'
{"stats":{"old":true}}
JSON
    cat >"${xrayConfig}12_policy.json" <<'JSON'
{"policy":{"levels":{"0":{"statsUserUplink":false,"statsUserDownlink":false}},"system":{"statsInboundUplink":false,"statsInboundDownlink":false,"statsOutboundUplink":false,"statsOutboundDownlink":false}}}
JSON
    originalStats=$(<"${xrayConfig}13_stats_api.json")
    originalPolicy=$(<"${xrayConfig}12_policy.json")
    reloadCore() {
        printf 'reload\n' >"${reloadMarker}"
        return 1
    }
    if ensureXrayTrafficStatsConfig >/dev/null 2>&1; then
        return 1
    fi
    [[ -e "${reloadMarker}" ]]
    [[ "$(<"${xrayConfig}13_stats_api.json")" == "${originalStats}" ]]
    [[ "$(<"${xrayConfig}12_policy.json")" == "${originalPolicy}" ]]
)

runCheckLogBackupMissingRestoreRegression() (
    local root="${TMP_DIR}/check-log-backup-restore"
    local restoreBackupDir
    mkdir -p "${root}"
    printf 'old-policy\n' >"${root}/policy.json"

    checkLogBackupCreate restoreBackupDir "${root}/stats.json" "${root}/policy.json"
    printf 'new-stats\n' >"${root}/stats.json"
    printf 'new-policy\n' >"${root}/policy.json"

    checkLogBackupRestore "${restoreBackupDir}"
    [[ ! -e "${root}/stats.json" ]]
    [[ "$(<"${root}/policy.json")" == "old-policy" ]]
)

runDpkgInstalledPatternRegression() {
    printf 'ii  ufw                             0.36.2-6                                all          program for managing a Netfilter firewall\n' | grep -Eq '^[[:space:]]*ii[[:space:]]+ufw[[:space:]]'
    printf 'ii  netfilter-persistent            1.0.20                                   all          boot-time loader for netfilter rules\n' | grep -Eq '^[[:space:]]*ii[[:space:]]+netfilter-persistent[[:space:]]'
}

runDpkgQueryInstalledPatternRegression() {
    printf 'ii ' | grep -q '^ii'
    if printf 'un ' | grep -q '^ii'; then
        return 1
    fi
}

runRhelLikeDetectionRegression() {
    local osRelease="${TMP_DIR}/alma-os-release"
    local oldOsReleaseFile="${PADM_OS_RELEASE_FILE:-}"

    cat >"${osRelease}" <<'EOF'
NAME="AlmaLinux"
VERSION="9.7 (Moss Jungle Cat)"
ID="almalinux"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.7"
EOF
    PADM_OS_RELEASE_FILE="${osRelease}"
    PADM_YUM_REPOS_DIR="${TMP_DIR}/yum.repos.d"
    initVar
    checkSystem
    [[ "${release}" == "centos" ]]
    [[ "${packageManager}" == "yum" ]]
    [[ "${centosVersion}" == "9" ]]
    [[ "${rhelLike}" == "true" ]]
    [[ "${osReleaseId}" == "almalinux" ]]
    [[ "${installType}" == *"--disablerepo=epel"* ]]
    PADM_OS_RELEASE_FILE="${oldOsReleaseFile}"
    PADM_YUM_REPOS_DIR=
}

runFedoraDetectionRegression() {
    local osRelease="${TMP_DIR}/fedora-os-release"
    local oldOsReleaseFile="${PADM_OS_RELEASE_FILE:-}"

    cat >"${osRelease}" <<'EOF'
NAME="Fedora Linux"
VERSION="43 (Cloud Edition)"
ID=fedora
VERSION_ID=43
EOF
    PADM_OS_RELEASE_FILE="${osRelease}"
    PADM_YUM_REPOS_DIR="${TMP_DIR}/fedora-yum.repos.d"
    initVar
    checkSystem
    [[ "${release}" == "fedora" ]]
    [[ "${packageManager}" == "yum" ]]
    [[ "${centosVersion}" == "43" ]]
    [[ "${rhelLike}" == "true" ]]
    [[ "${osReleaseId}" == "fedora" ]]
    [[ "${installType}" == "yum -y install" ]]
    PADM_OS_RELEASE_FILE="${oldOsReleaseFile}"
    PADM_YUM_REPOS_DIR=
}

runMenuSmokeLightRegression() {
    local actions=
    local output=
    local oldCoreInstallType="${coreInstallType:-}"
    coreInstallType=
    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }
    resetMenuActions() {
        actions=
    }
    menu() { recordMenuAction menu; }
    menuLine() { output+="$*"$'\n'; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    menuClose() { return 0; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
    manageXHTTP() { recordMenuAction manageXHTTP; }
    manageHysteria() { recordMenuAction manageHysteria; }
    manageTuic() { recordMenuAction manageTuic; }
    addCorePort() { recordMenuAction addCorePort; }
    manageCDN() { recordMenuAction manageCDN; }

    installMenu <<<"6"
    assertMenuAction selectCoreInstall
    grep -q "不知道怎么选时，建议直接选 1" <<<"${output}"
    grep -q "entry 是客户端连接地址" <<<"${output}"

    resetMenuActions
    installXray() { recordMenuAction installXray; }
    installXrayService() { recordMenuAction installXrayService; }
    initXrayConfig() { recordMenuAction initXrayConfig; }
    cleanUp() { recordMenuAction cleanUp; }
    checkGFWStatue() { recordMenuAction checkGFWStatue; }
    showAccounts() { recordMenuAction showAccounts; }
    installTools() { recordMenuAction installTools; }
    readLastInstallationConfig() { recordMenuAction readLastInstallationConfig; }
    unInstallSubscribe() { recordMenuAction unInstallSubscribe; }
    handleNginx() { recordMenuAction "handleNginx:$*"; }
    serviceQueueRestart() { recordMenuAction "serviceQueueRestart:$*"; }
    serviceQueueApply() { recordMenuAction serviceQueueApply; }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() { recordMenuAction refreshSubscriptionWireGuardNginxControl; }
    installXrayReality
    assertMenuAction 'handleNginx:stop'
    assertMenuAction refreshSubscriptionWireGuardNginxControl
    assertMenuAction serviceQueueApply
    [[ "$(protocolMenuDescription 10)" == "TLS 指纹抗性优先；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 13)" == "sing-box AnyTLS 按需；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runUpdatePadmVersionPromptRegression() {
    local installDir outputLog errorLog downloadLog oldTmpDir
    local restoreFailureDir restoreFailureErrorLog restoreFailureDownloadLog
    local replaceFailureDir replaceFailureErrorLog replaceFailureDownloadLog
    local chmodFailureDir chmodFailureErrorLog chmodFailureDownloadLog
    local updateTmpRoot
    installDir="${TMP_DIR}/update-padm-install"
    outputLog="${TMP_DIR}/update-padm-output.log"
    errorLog="${TMP_DIR}/update-padm-error.log"
    downloadLog="${TMP_DIR}/update-padm-download.log"
    restoreFailureDir="${TMP_DIR}/update-padm-restore-failure"
    restoreFailureErrorLog="${TMP_DIR}/update-padm-restore-failure-error.log"
    restoreFailureDownloadLog="${TMP_DIR}/update-padm-restore-failure-download.log"
    replaceFailureDir="${TMP_DIR}/update-padm-replace-failure"
    replaceFailureErrorLog="${TMP_DIR}/update-padm-replace-failure-error.log"
    replaceFailureDownloadLog="${TMP_DIR}/update-padm-replace-failure-download.log"
    chmodFailureDir="${TMP_DIR}/update-padm-chmod-failure"
    chmodFailureErrorLog="${TMP_DIR}/update-padm-chmod-failure-error.log"
    chmodFailureDownloadLog="${TMP_DIR}/update-padm-chmod-failure-download.log"
    updateTmpRoot="${TMP_DIR}/update-padm-tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${installDir}" "${restoreFailureDir}" "${replaceFailureDir}" "${chmodFailureDir}" "${updateTmpRoot}"

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${installDir}/install.sh"
    chmod 700 "${installDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${errorLog}"
        release=debian
        PADM_INSTALL_DIR="${installDir}"
        TMPDIR="${updateTmpRoot}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${downloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry\n'
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }

        updatePadm 1
    ) >"${outputLog}" 2>&1 && return 1
    grep -q '新版入口执行失败，已恢复旧入口' "${errorLog}"
    "${installDir}/install.sh" | grep -q 'old-entry'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${restoreFailureDir}/install.sh"
    chmod 700 "${restoreFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${restoreFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${restoreFailureDir}"
        TMPDIR="${updateTmpRoot}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${restoreFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry\n'
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        mv() {
            if [[ "$1" == "${restoreFailureDir}/install.sh.bak" && "$2" == "${restoreFailureDir}/install.sh" ]]; then
                return 1
            fi
            command mv "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-restore-failure-run.log" 2>&1 && return 1
    grep -q '新版入口执行失败，旧入口恢复失败' "${restoreFailureErrorLog}"
    [[ -f "${restoreFailureDir}/install.sh.bak" ]]

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${replaceFailureDir}/install.sh"
    chmod 700 "${replaceFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${replaceFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${replaceFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${replaceFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry\n'
exit 0
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() {
            if [[ "$1" == "chmod" && "$2" == "700" && "$3" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            "$@"
        }
        mv() {
            if [[ "$1" == "${replaceFailureDir}/install.sh.bak" && "$2" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            command mv "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-replace-restore-failure-run.log" 2>&1 && return 1
    grep -q '更新入口替换失败，旧入口恢复失败' "${replaceFailureErrorLog}"
    [[ -f "${replaceFailureDir}/install.sh.bak" ]]
    "${replaceFailureDir}/install.sh" | grep -q 'new-entry'

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${chmodFailureDir}/install.sh"
    chmod 700 "${chmodFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${chmodFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${chmodFailureDir}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${chmodFailureDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
exit 23
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        sudo() {
            if [[ "$1" == "chmod" && "$2" == "700" && "$3" == "${chmodFailureDir}/install.sh" && -f "${chmodFailureDir}/install.sh.bak" ]]; then
                return 1
            fi
            "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-chmod-restore-failure-run.log" 2>&1 && return 1
    grep -q '新版入口执行失败，旧入口恢复失败' "${chmodFailureErrorLog}"
    [[ ! -e "${chmodFailureDir}/install.sh.bak" ]]
    "${chmodFailureDir}/install.sh" | grep -q 'old-entry'
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshRestoresBackupRegression() {
    local fixtureDir archiveRoot outputLog archiveDirName refreshTmpRoot oldTmpDir restoreFailureDir restoreFailureArchiveRoot restoreFailureOutputLog restoreFailureTmpRoot
    fixtureDir="${TMP_DIR}/install-refresh-restore"
    archiveDirName="padm-main"
    archiveRoot="${fixtureDir}/archive/${archiveDirName}"
    outputLog="${fixtureDir}/refresh.log"
    refreshTmpRoot="${fixtureDir}/tmp"
    restoreFailureDir="${TMP_DIR}/install-refresh-restore-failure"
    restoreFailureArchiveRoot="${restoreFailureDir}/archive/${archiveDirName}"
    restoreFailureOutputLog="${restoreFailureDir}/refresh.log"
    restoreFailureTmpRoot="${restoreFailureDir}/tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${fixtureDir}/shell" "${fixtureDir}/documents" "${archiveRoot}/shell" "${archiveRoot}/documents" "${refreshTmpRoot}"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-doc\n' >"${fixtureDir}/documents/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'new-doc\n' >"${archiveRoot}/documents/marker"
    printf 'new-readme\n' >"${archiveRoot}/README.md"

    (
        set +e
        TMPDIR="${refreshTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        REPO_ARCHIVE_DIR="${archiveDirName}"
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        REPO_ZIP_URL="fixture.tar.gz"
        command() {
            if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        curl() { tar -cz -C "${fixtureDir}/archive" "${REPO_ARCHIVE_DIR}"; }
        cp() {
            if [[ "$1" == "-R" && "$2" == "${archiveRoot}/documents" ]]; then
                return 1
            fi
            command cp "$@"
        }
        refreshScriptModules new-ref
    ) >"${outputLog}" 2>&1
    grep -q '完整安装包替换失败，已恢复旧模块' "${outputLog}"
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/documents/marker")" == "old-doc" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]

    mkdir -p "${restoreFailureDir}/shell" "${restoreFailureDir}/documents" "${restoreFailureArchiveRoot}/shell" "${restoreFailureArchiveRoot}/documents" "${restoreFailureTmpRoot}"
    printf 'old-shell\n' >"${restoreFailureDir}/shell/marker"
    printf 'old-doc\n' >"${restoreFailureDir}/documents/marker"
    printf 'old-readme\n' >"${restoreFailureDir}/README.md"
    printf 'new-shell\n' >"${restoreFailureArchiveRoot}/shell/marker"
    printf 'new-doc\n' >"${restoreFailureArchiveRoot}/documents/marker"
    printf 'new-readme\n' >"${restoreFailureArchiveRoot}/README.md"

    (
        set +e
        TMPDIR="${restoreFailureTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${restoreFailureDir}"
        REPO_ARCHIVE_DIR="${archiveDirName}"
        SCRIPT_REF_FILE="${restoreFailureDir}/.padm-ref"
        SCRIPT_MANIFEST_FILE="${restoreFailureDir}/.padm-module-manifest"
        REPO_ZIP_URL="fixture.tar.gz"
        command() {
            if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        curl() { tar -cz -C "${restoreFailureDir}/archive" "${REPO_ARCHIVE_DIR}"; }
        cp() {
            if [[ "$1" == "-R" && "$2" == "${restoreFailureArchiveRoot}/documents" ]]; then
                return 1
            fi
            command cp "$@"
        }
        mv() {
            if [[ "$1" == "${restoreFailureDir}/.padm-update-backup/documents" && "$2" == "${restoreFailureDir}/documents" ]]; then
                return 1
            fi
            command mv "$@"
        }
        refreshScriptModules new-ref
    ) >"${restoreFailureOutputLog}" 2>&1
    grep -q '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录' "${restoreFailureOutputLog}"
    [[ -d "${restoreFailureDir}/.padm-update-backup" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallEnsureModulesRegression() {
    local fixtureDir marker
    fixtureDir="${TMP_DIR}/install-entry"
    marker="${fixtureDir}/refresh-called"
    mkdir -p "${fixtureDir}/shell/core"
    touch "${fixtureDir}/shell/core/bootstrap.sh"
    printf 'old-ref\n' >"${fixtureDir}/.padm-ref"

    local savedScriptDir="${SCRIPT_DIR:-}"
    local savedScriptRefFile="${SCRIPT_REF_FILE:-}"
    local savedScriptExpectedRefFile="${SCRIPT_EXPECTED_REF_FILE:-}"
    local savedRepoRefUrl="${REPO_REF_URL:-}"
    local savedRepoZipUrl="${REPO_ZIP_URL:-}"
    local savedRepoArchiveDir="${REPO_ARCHIVE_DIR:-}"
    local savedPadmSkipRemoteRefCheck="${PADM_SKIP_REMOTE_REF_CHECK:-}"

    SCRIPT_DIR="${fixtureDir}"
    SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
    SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
    refreshScriptModules() { printf '%s\n' "$1" >"${marker}"; }
    fetchRemoteRef() { return 1; }
    regressionEnsureScriptModules
    [[ ! -e "${marker}" ]]

    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    regressionEnsureScriptModules
    [[ -f "${marker}" ]]

    rm -f "${marker}"
    mkdir -p "${fixtureDir}/shell/core"
    touch "${fixtureDir}/shell/core/bootstrap.sh"
    fetchRemoteRef() { printf 'new-ref\n'; }
    regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "new-ref" ]]

    printf 'manifest-ok\n' >"${fixtureDir}/.padm-module-manifest"
    PADM_FAKE_MODULE_MANIFEST_READY=1
    rm -f "${marker}"
    regressionEnsureScriptModules
    [[ ! -e "${marker}" ]]

    printf 'expected-ref\n' >"${fixtureDir}/.padm-entry-ref"
    printf 'old-ref\n' >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "expected-ref" ]]

    printf 'expected-ref\n' >"${fixtureDir}/.padm-entry-ref"
    printf 'expected-ref\n' >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    PADM_FAKE_MODULE_MANIFEST_READY=0 regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "expected-ref" ]]

    unset PADM_FAKE_MODULE_MANIFEST_READY
    rm -f "${fixtureDir}/.padm-module-manifest"

    rm -f "${marker}" "${fixtureDir}/.padm-entry-ref"
    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    regressionEnsureScriptModules
    [[ "$(<"${marker}")" == "new-ref" ]]

    SCRIPT_DIR="${savedScriptDir}"
    SCRIPT_REF_FILE="${savedScriptRefFile}"
    SCRIPT_EXPECTED_REF_FILE="${savedScriptExpectedRefFile}"
    REPO_REF_URL="${savedRepoRefUrl}"
    REPO_ZIP_URL="${savedRepoZipUrl}"
    REPO_ARCHIVE_DIR="${savedRepoArchiveDir}"
    if [[ -n "${savedPadmSkipRemoteRefCheck}" ]]; then
        PADM_SKIP_REMOTE_REF_CHECK="${savedPadmSkipRemoteRefCheck}"
    else
        unset PADM_SKIP_REMOTE_REF_CHECK
    fi
}

runAliasInstallSameTargetRegression() {
    local fixtureDir outputLog cpLog oldScriptDir oldPadmInstallDir oldHome
    fixtureDir="${TMP_DIR}/alias-install-same-target"
    outputLog="${fixtureDir}/output.log"
    cpLog="${fixtureDir}/cp.log"
    mkdir -p "${fixtureDir}"
    cat >"${fixtureDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF

    oldScriptDir="${SCRIPT_DIR:-}"
    oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
    oldHome="${HOME}"
    SCRIPT_DIR="${fixtureDir}"
    PADM_INSTALL_DIR="${fixtureDir}"
    HOME="${fixtureDir}/home"
    mkdir -p "${HOME}"

    (
        cp() { printf 'cp %s\n' "$*" >>"${cpLog}"; command cp "$@"; }
        chmod() { :; }
        ln() { :; }
        aliasInstall
    ) >"${outputLog}" 2>&1

    [[ ! -s "${outputLog}" ]]
    [[ ! -e "${cpLog}" ]]

    SCRIPT_DIR="${oldScriptDir}"
    HOME="${oldHome}"
    if [[ -n "${oldPadmInstallDir}" ]]; then
        PADM_INSTALL_DIR="${oldPadmInstallDir}"
    else
        unset PADM_INSTALL_DIR
    fi
}

runInstallModulePathsRegression() {
    local outputList moduleTmpRoot fixtureDir oldTmpDir moduleListBefore moduleListAfter
    outputList="${TMP_DIR}/install-module-paths.txt"
    moduleTmpRoot="${TMP_DIR}/install-module-paths-tmp"
    fixtureDir="${TMP_DIR}/install-entry-manifest"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${moduleTmpRoot}" "${fixtureDir}/shell/core"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    cat >"${fixtureDir}/shell/core/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
source "${CORE_DIR}/version.sh"
EOF
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/core/version.sh"
    (
        TMPDIR="${moduleTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${PROJECT_ROOT}"
        SCRIPT_MANIFEST_FILE="${TMP_DIR}/install-module-paths-manifest"
        SCRIPT_EXPECTED_REF_FILE="${TMP_DIR}/install-module-paths-entry-ref"
        SCRIPT_REF_FILE="${TMP_DIR}/install-module-paths-ref"
        moduleListBefore=$(find "${moduleTmpRoot}" -maxdepth 1 -type f -name 'padm-modules.*' | wc -l | tr -d ' ')
        modulePaths
        scriptModulesReady >/dev/null
        moduleListAfter=$(find "${moduleTmpRoot}" -maxdepth 1 -type f -name 'padm-modules.*' | wc -l | tr -d ' ')
        [[ "${moduleListBefore}" == "0" && "${moduleListAfter}" == "0" ]]
    ) | sort >"${outputList}"
    grep -q '^install\.sh$' "${outputList}"
    grep -q '^shell/core/bootstrap\.sh$' "${outputList}"
    grep -q '^shell/validate_install\.sh$' "${outputList}"
    grep -q '^shell/core/menu\.sh$' "${outputList}"
    grep -q '^shell/subscription/wireguard_control\.sh$' "${outputList}"
    ! grep -q '^REQUIRED_MODULE_PATHS' "${PROJECT_ROOT}/install.sh"
    (
        TMPDIR="${moduleTmpRoot}"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        writeModuleManifest "${SCRIPT_MANIFEST_FILE}"
        scriptModulesReady >/dev/null
        printf '# changed\n' >>"${fixtureDir}/install.sh"
        ! scriptModulesReady >/dev/null
    )
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runAliasInstallMetadataCopyRegression() {
    local sourceDir targetDir oldScriptDir oldPadmInstallDir oldHome
    sourceDir="${TMP_DIR}/alias-install-source"
    targetDir="${TMP_DIR}/alias-install-target"
    mkdir -p "${sourceDir}/shell" "${sourceDir}/documents" "${sourceDir}/assets" "${targetDir}"
    cat >"${sourceDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF
    printf 'shell\n' >"${sourceDir}/shell/marker"
    printf 'docs\n' >"${sourceDir}/documents/marker"
    printf 'assets\n' >"${sourceDir}/assets/marker"
    printf 'manifest\n' >"${sourceDir}/.padm-module-manifest"
    printf 'local-ref\n' >"${sourceDir}/.padm-ref"
    printf 'expected-ref\n' >"${sourceDir}/.padm-entry-ref"

    oldScriptDir="${SCRIPT_DIR:-}"
    oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
    oldHome="${HOME}"
    SCRIPT_DIR="${sourceDir}"
    PADM_INSTALL_DIR="${targetDir}"
    HOME="${TMP_DIR}/alias-install-home"
    mkdir -p "${HOME}"

    (
        chmod() { :; }
        ln() { :; }
        aliasInstall
    )

    cmp -s "${sourceDir}/.padm-module-manifest" "${targetDir}/.padm-module-manifest"
    cmp -s "${sourceDir}/.padm-ref" "${targetDir}/.padm-ref"
    cmp -s "${sourceDir}/.padm-entry-ref" "${targetDir}/.padm-entry-ref"

    SCRIPT_DIR="${oldScriptDir}"
    HOME="${oldHome}"
    if [[ -n "${oldPadmInstallDir}" ]]; then
        PADM_INSTALL_DIR="${oldPadmInstallDir}"
    else
        unset PADM_INSTALL_DIR
    fi
}

runInstallEntrySymlinkPathRegression() {
    local fixtureDir realDir linkDir
    fixtureDir="${TMP_DIR}/install-entry-real"
    realDir="${fixtureDir}/real"
    linkDir="${fixtureDir}/link"
    mkdir -p "${realDir}" "${linkDir}"
    printf '#!/usr/bin/env bash\n' >"${realDir}/install.sh"
    (
        eval "$(awk '
            /^resolveScriptPath\(\)/ { capture = 1 }
            /^SCRIPT_PATH=\$\(resolveScriptPath / { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        readlink() {
            if [[ "$1" == "${linkDir}/padm-rel" ]]; then
                printf '../real/install.sh\n'
                return 0
            fi
            if [[ "$1" == "${linkDir}/padm-abs" ]]; then
                printf '%s/install.sh\n' "${realDir}"
                return 0
            fi
            return 1
        }
        [[ "$(resolveScriptPath "${realDir}/install.sh")" == "${realDir}/install.sh" ]]
        [[ "$(resolveScriptPath "${linkDir}/padm-rel")" == "${realDir}/install.sh" ]]
        [[ "$(resolveScriptPath "${linkDir}/padm-abs")" == "${realDir}/install.sh" ]]
    )
}

runLocaleEchoContentUnsetPrintNRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/locale.sh"
        output=$(echoContent text "locale-smoke")
        [[ "${output}" == *"locale-smoke"* ]]
    )
}

runShowAccountsOptionalStepRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        readInstallType() { return 0; }
        readInstallProtocolType() { currentInstallProtocolType=; return 0; }
        readConfigHostPathUUID() { return 0; }
        readSingBoxConfig() { return 0; }
        initSubscribeLocalConfig() { return 0; }
        showVlessTcpAccounts() { return 0; }
        showVlessWsAccounts() { return 0; }
        showTrojanGrpcAccounts() { return 0; }
        showVmessWsAccounts() { return 0; }
        showTrojanAccounts() { return 0; }
        showVlessGrpcAccounts() { return 0; }
        showHysteriaAccounts() { return 0; }
        showVlessRealityAccounts() { return 0; }
        showVlessRealityGrpcAccounts() { return 0; }
        showTuicAccounts() { return 0; }
        showNaiveAccounts() { return 0; }
        showVmessHTTPUpgradeAccounts() { return 0; }
        showVlessRealityXHTTPAccounts() { return 0; }
        showAnyTlsAccounts() { return 0; }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/subscription/accounts.sh"
        showAccounts >/dev/null
    )
}

runAllowPortOptionalProtocolRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        ufw() { return 1; }
        systemctl() { return 1; }
        rc-update() { return 1; }
        dpkg-query() { return 1; }
        iptables() { return 1; }
        netfilter-persistent() { return 1; }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/network.sh"
        allowPort 24443
    )
}

runCoreClientOptionalArgsRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        currentClients='[{"id":"u1","email":"acct-one"},{"uuid":"u2","name":"acct-two"}]'
        protocolSelectionIncludes() { return 1; }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        initXrayClients 7 >/dev/null
        initSingBoxClients 7 >/dev/null
    )
}

runSingBoxServiceMainPidTemplateRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        release=debian
        find() {
            if [[ "$*" == "/bin /usr/bin -name systemctl" ]]; then
                printf '/usr/bin/systemctl\n'
                return 0
            fi
            command find "$@"
        }
        bootStartup() { return 0; }
        commitGeneratedFile() { cp "$1" "${TMP_DIR}/sing-box.service" && return 0; }
        progressCard() { return 0; }
        errorCard() { return 1; }
        coreSingBoxServiceTemplate() { printf '%s\n' "${TMP_DIR}/sing-box.service.XXXXXX"; }
        padmCreateTempPath() { printf -v "$1" '%s' "$(mktemp "$2")"; }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        installSingBoxService 1 >/dev/null 2>&1 || true
        grep -q 'ExecReload=/bin/kill -HUP \$MAINPID' "${TMP_DIR}/sing-box.service"
    )
}

runRegressionPlatform() {
    runRegressionStep release-workflow-version runReleaseWorkflowVersionRegression &&
        runRegressionStep cleanup-trap runCleanupTrapRegression &&
        runRegressionStep check-log-backup-restore runCheckLogBackupMissingRestoreRegression &&
        runRegressionStep update-padm-version-prompt runUpdatePadmVersionPromptRegression &&
        runRegressionStep install-refresh-restore runInstallRefreshRestoresBackupRegression &&
        runRegressionStep install-entry-refresh runInstallEnsureModulesRegression &&
        runRegressionStep install-module-paths runInstallModulePathsRegression &&
        runRegressionStep install-entry-symlink runInstallEntrySymlinkPathRegression &&
        runRegressionStep alias-install-metadata runAliasInstallMetadataCopyRegression &&
        runRegressionStep alias-install-same-target runAliasInstallSameTargetRegression &&
        runRegressionStep xray-stats-jq runXrayTrafficStatsJqCompatibilityRegression &&
        runRegressionStep local-traffic-accounts runLocalTrafficAccountsBatchRegression &&
        runRegressionStep dpkg-installed-pattern runDpkgInstalledPatternRegression &&
        runRegressionStep dpkg-query-installed-pattern runDpkgQueryInstalledPatternRegression &&
        runRegressionStep rhel-like-detection runRhelLikeDetectionRegression &&
        runRegressionStep fedora-detection runFedoraDetectionRegression
}

runRegressionFast() {
    runRegressionStep platform runRegressionPlatform &&
        runRegressionStep locale-unset-printN runLocaleEchoContentUnsetPrintNRegression &&
        runRegressionStep show-accounts-optional-step runShowAccountsOptionalStepRegression &&
        runRegressionStep allow-port-optional-protocol runAllowPortOptionalProtocolRegression &&
        runRegressionStep core-client-optional-args runCoreClientOptionalArgsRegression &&
        runRegressionStep singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression &&
        runRegressionStep nginx-blog-auto-install runNginxBlogAutoInstallRegression &&
        runRegressionStep ui-smoke-light runMenuSmokeLightRegression
}

regressionName=${1:-fast}
case "${regressionName}" in
fast)
    regressionRunner=runRegressionFast
    ;;
platform)
    regressionRunner=runRegressionPlatform
    ;;
*)
    printf 'usage: %s [fast|platform]\n' "$0" >&2
    exit 2
    ;;
esac

runRegressionStep "total:${regressionName}" "${regressionRunner}"
echo "subscription-groups-regression-ok:${regressionName}"
