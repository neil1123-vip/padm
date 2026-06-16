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

regressionScriptModuleFilesPresent() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]
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
        if regressionScriptModuleFilesPresent; then
            return 0
        fi
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

runGitHubReleaseAssetDirectFallbackRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local root="${TMP_DIR}/github-release-direct-fallback"
        local outputDir="${root}/out"
        mkdir -p "${outputDir}"
        curl() { return 22; }
        wget() {
            if [[ "${1:-}" == "-qO-" ]]; then
                if [[ "${2:-}" == "https://api.github.com/repos/example/repo/releases/tags/v1.2.3" ]]; then
                    return 1
                fi
                if [[ "${2:-}" == "https://github.com/example/repo/releases/download/v1.2.3/asset.tar.gz" ]]; then
                    printf 'asset-content\n'
                    return 0
                fi
            elif [[ "${1:-}" == "-c" && "${2:-}" == "-q" && "${3:-}" == "-P" ]]; then
                mkdir -p "${4}"
                printf 'asset-content\n' >"${4}/asset.tar.gz"
                return 0
            fi
            return 1
        }
        downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.3 asset.tar.gz
        [[ "$(<"${outputDir}/asset.tar.gz")" == "asset-content" ]]
    )
}

runAutoInstallGeneratedIdentityRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        AUTO_INSTALL=true
        AUTO_UUID=
        AUTO_USER=
        uuidgen() { printf 'ABCDEF12-3456-7890-ABCD-EF1234567890\n'; }
        local generatedUUID generatedUser
        generatedUUID=$(autoValueForKey core_init_uuid)
        generatedUser=$(autoValueForKey core_init_username)
        [[ "${generatedUUID}" == "abcdef12-3456-7890-abcd-ef1234567890" ]]
        [[ "${generatedUser}" == "padm-abcdef12" ]]
    )
}

runDefaultRandomUserNameRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local uuid name
        uuid='ABCDEF12-3456-7890-ABCD-EF1234567890'
        name=$(defaultRandomUserNameFromUuid "${uuid}")
        [[ "${name}" == "padm-abcdef12" ]]
    )
}

runAutoInstallAllowsEmptyDefaultRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        AUTO_INSTALL=true
        AUTO_PORT=
        AUTO_REALITY_SERVER_NAME=
        local value=
        autoRead reality_port "端口:" value
        [[ -z "${value:-}" ]]
        autoRead reality_server_name "请输入SNI[回车默认等于目标 host]:" value
        [[ -z "${value:-}" ]]
    )
}

runClientNameSuffixPreservesRandomPrefixRegression() {
    (
        set -euo pipefail
        currentClients='[{"id":"11111111-1111-1111-1111-111111111111","email":"padm-abcdef12-VLESS_TCP/TLS_Vision"},{"uuid":"22222222-2222-2222-2222-222222222222","name":"padm-abcdef12-VLESS_Reality_Vision"}]'
        protocolSelectionIncludes() {
            local type=$1
            local target=$2
            [[ ",${type}," == *",${target},"* ]]
        }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        local xrayUsers singboxUsers
        xrayUsers=$(initXrayClients 0)
        singboxUsers=$(initSingBoxClients 7)
        jq -e '.[0].email == "padm-abcdef12-VLESS_TCP/TLS_Vision"' <<<"${xrayUsers}" >/dev/null
        jq -e '.[0].name == "padm-abcdef12-VLESS_Reality_Vision"' <<<"${singboxUsers}" >/dev/null
    )
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

runPortHoppingWithoutPersistentRegression() (
    set -euo pipefail
    AUTO_INSTALL=
    lastInstallationConfig=
    source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    local natStateFile="${TMP_DIR}/port-hopping-nat.state"
    local allowCalls=0
    local warnLog="${TMP_DIR}/port-hopping-warn.log"
    : >"${warnLog}"
    : >"${natStateFile}"

    statusCard() {
        printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >>"${warnLog}"
    }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    autoRead() {
        printf -v "$3" '%s' '33000-33005'
    }
    allowPort() { allowCalls=$((allowCalls + 1)); return 0; }
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "netfilter-persistent" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    sudo() { "$@"; }
    iptables() {
        if [[ "$*" == *"-A PREROUTING"* ]]; then
            if [[ "$*" == *"neil1123-vip_tuic_portHopping"* ]]; then
                cat >"${natStateFile}" <<'EOF'
-A PREROUTING -p udp -m udp --dport 12000:12005 -m comment --comment keep-other-rule -j DNAT --to-destination :12095
-A PREROUTING -p udp -m udp --dport 33000:33005 -m comment --comment neil1123-vip_tuic_portHopping -j DNAT --to-destination :26451
EOF
            else
                cat >"${natStateFile}" <<'EOF'
-A PREROUTING -p udp -m udp --dport 12000:12005 -m comment --comment keep-other-rule -j DNAT --to-destination :12095
-A PREROUTING -p udp -m udp --dport 33000:33005 -m comment --comment neil1123-vip_hysteria2_portHopping -j DNAT --to-destination :16295
EOF
            fi
            return 0
        fi
        if [[ "$*" == *"-D PREROUTING"* ]]; then
            local line=${*: -1}
            if [[ "${line}" == "2" ]]; then
                printf '%s\n' "-A PREROUTING -p udp -m udp --dport 12000:12005 -m comment --comment keep-other-rule -j DNAT --to-destination :12095" >"${natStateFile}"
            elif [[ "${line}" == "1" ]]; then
                : >"${natStateFile}"
            fi
            return 0
        fi
        if [[ "$*" == *"-L PREROUTING --line-numbers"* ]]; then
            if [[ -s "${natStateFile}" ]]; then
                printf '1   DNAT       udp  --  anywhere anywhere udp dpts:12000:12005 /* keep-other-rule */ to::12095\n'
                if grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"; then
                    printf '2   DNAT       udp  --  anywhere anywhere udp dpts:33000:33005 /* neil1123-vip_hysteria2_portHopping */ to::16295\n'
                fi
                if grep -q 'neil1123-vip_tuic_portHopping' "${natStateFile}"; then
                    printf '2   DNAT       udp  --  anywhere anywhere udp dpts:33000:33005 /* neil1123-vip_tuic_portHopping */ to::26451\n'
                fi
            fi
            return 0
        fi
        return 0
    }
    iptables-save() {
        [[ -s "${natStateFile}" ]] && cat "${natStateFile}"
        return 0
    }

    rhelLike=false
    portHoppingStart=
    portHoppingEnd=
    addPortHopping hysteria2 16295
    [[ -s "${natStateFile}" ]]
    [[ "${allowCalls}" == "1" ]]
    grep -Eq '端口跳跃持久化|未检测到 netfilter-persistent' "${warnLog}"

    readPortHopping hysteria2 16295
    [[ "${hysteria2PortHoppingStart}" == "33000" ]]
    [[ "${hysteria2PortHoppingEnd}" == "33005" ]]

    deletePortHoppingRules hysteria2 33000 33005 16295
    grep -q 'keep-other-rule' "${natStateFile}"
    ! grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"

    : >"${natStateFile}"
    hysteria2PortHoppingStart=33000
    hysteria2PortHoppingEnd=33005
    tuicPortHoppingStart=
    tuicPortHoppingEnd=
    addPortHopping tuic 26451
    grep -q 'neil1123-vip_tuic_portHopping' "${natStateFile}"
    readPortHopping tuic 26451
    [[ "${tuicPortHoppingStart}" == "33000" ]]
    [[ "${tuicPortHoppingEnd}" == "33005" ]]
)

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

runSubscriptionOutputRandomUserRegression() (
    local subscribeCaptureDir="${TMP_DIR}/subscribe-output-random-user"
    export PADM_SUBSCRIBE_LOCAL_DIR="${subscribeCaptureDir}"
    rm -rf "${subscribeCaptureDir}"
    currentHost="tls.example.com"
    defaultBase64Code vlesstcp 443 "padm-abcdef12-VLESS_TCP/TLS_Vision" uuid-tls "" ""
    [[ -f "${subscribeCaptureDir}/default/padm-abcdef12" ]]
    [[ ! -e "${subscribeCaptureDir}/default/padm" ]]
    [[ -f "${subscribeCaptureDir}/sing-box/padm-abcdef12" ]]
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
    manageFail2ban() { recordMenuAction manageFail2ban; }
    updatePadm() { recordMenuAction "updatePadm:$*"; }
    showPadmScriptInstallStatus() { recordMenuAction showPadmScriptInstallStatus; }
    bbrInstall() { recordMenuAction bbrInstall; }

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
    resetMenuActions
    output=
    systemScriptMenu <<<"3"
    assertMenuAction manageFail2ban
    grep -q "Fail2ban 防护" <<<"${output}"
    resetMenuActions
    systemScriptMenu <<<"1"
    assertMenuAction 'updatePadm:1'
    resetMenuActions
    systemScriptMenu <<<"2"
    assertMenuAction showPadmScriptInstallStatus
    resetMenuActions
    systemScriptMenu <<<"4"
    assertMenuAction bbrInstall
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

runInstallRefreshFallbackMainRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local fixtureDir archiveRoot outputLog oldTmpDir
        fixtureDir="${TMP_DIR}/install-refresh-fallback-main"
        archiveRoot="${fixtureDir}/archive"
        outputLog="${fixtureDir}/refresh.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${archiveRoot}/padm-main/shell" "${archiveRoot}/padm-main/documents" "${archiveRoot}/padm-main/assets" "${fixtureDir}/shell" "${fixtureDir}/documents"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf 'old-doc\n' >"${fixtureDir}/documents/marker"
        printf 'old-readme\n' >"${fixtureDir}/README.md"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
        printf 'new-shell\n' >"${archiveRoot}/padm-main/shell/marker"
        printf 'new-doc\n' >"${archiveRoot}/padm-main/documents/marker"
        printf 'new-readme\n' >"${archiveRoot}/padm-main/README.md"

        (
            set +e
            TMPDIR="${fixtureDir}/tmp"
            eval "$(awk '
                /^scriptTmpPath\(\)/ { capture = 1 }
                /^ensureScriptModules\(\)/ { capture = 0 }
                capture { print }
            ' "${PROJECT_ROOT}/install.sh")"
            SCRIPT_DIR="${fixtureDir}"
            REPO_ARCHIVE_DIR="padm-main"
            SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
            SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
            SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
            REPO_ZIP_URL="fixture.tar.gz"
            command() {
                if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                    return 0
                fi
                builtin command "$@"
            }
            curl() {
                if [[ "$*" == *"dead-ref.tar.gz"* ]]; then
                    return 22
                fi
                tar -cz -C "${archiveRoot}" padm-main
            }
            refreshScriptModules dead-ref
        ) >"${outputLog}" 2>&1

        grep -q '指定版本完整安装包不可用，回退到主分支最新完整安装包' "${outputLog}"
        [[ ! -f "${fixtureDir}/.padm-ref" || "$(<"${fixtureDir}/.padm-ref")" != "dead-ref" ]]
        [[ ! -f "${fixtureDir}/.padm-entry-ref" || "$(<"${fixtureDir}/.padm-entry-ref")" != "dead-ref" ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "new-shell" ]]
        [[ "$(<"${fixtureDir}/documents/marker")" == "new-doc" ]]
        [[ "$(<"${fixtureDir}/README.md")" == "new-readme" ]]

        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runInstallRefreshKeepsRefWhenRemoteLookupFailsRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local fixtureDir archiveRoot outputLog oldTmpDir
        fixtureDir="${TMP_DIR}/install-refresh-keep-ref-on-lookup-fail"
        archiveRoot="${fixtureDir}/archive"
        outputLog="${fixtureDir}/refresh.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${archiveRoot}/padm-main/shell" "${archiveRoot}/padm-main/documents" "${archiveRoot}/padm-main/assets" "${fixtureDir}/shell"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf 'keep-ref\n' >"${fixtureDir}/.padm-ref"
        printf 'keep-ref\n' >"${fixtureDir}/.padm-entry-ref"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
        printf 'new-shell\n' >"${archiveRoot}/padm-main/shell/marker"
        printf 'new-readme\n' >"${archiveRoot}/padm-main/README.md"

        (
            set +e
            TMPDIR="${fixtureDir}/tmp"
            eval "$(awk '
                /^scriptTmpPath\(\)/ { capture = 1 }
                /^ensureScriptModules\(\)/ { capture = 0 }
                capture { print }
            ' "${PROJECT_ROOT}/install.sh")"
            SCRIPT_DIR="${fixtureDir}"
            REPO_ARCHIVE_DIR="padm-main"
            SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
            SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
            SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
            REPO_ZIP_URL="fixture.tar.gz"
            command() {
                if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                    return 0
                fi
                builtin command "$@"
            }
            curl() { tar -cz -C "${archiveRoot}" padm-main; }
            refreshScriptModules ""
        ) >"${outputLog}" 2>&1

        [[ "$(<"${fixtureDir}/.padm-ref")" == "keep-ref" ]]
        [[ "$(<"${fixtureDir}/.padm-entry-ref")" == "keep-ref" ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "new-shell" ]]

        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runRemoveInstallPathRetryRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/remove-install-path-retry"
        local target="${root}/target"
        local attemptsFile="${root}/attempts.log"
        mkdir -p "${target}/child"
        printf 'data\n' >"${target}/child/file"
        : >"${attemptsFile}"

        rm() {
            printf '%s\n' "$*" >>"${attemptsFile}"
            if [[ "$1" == "-rf" && "$2" == "${target}" ]]; then
                local count
                count=$(wc -l <"${attemptsFile}")
                if [[ "${count}" == "1" ]]; then
                    return 1
                fi
                command rm -rf -- "${target}"
                return 0
            fi
            command rm "$@"
        }

        removeInstallPath "${target}" "目标目录"
        [[ ! -e "${target}" ]]
        [[ "$(wc -l <"${attemptsFile}")" == "2" ]]
    )
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

runInstallRefreshSingleArchiveGuardRegression() {
    local archiveGuardCount
    archiveGuardCount=$(awk '
        /^refreshScriptModules\(\)/ { capture = 1 }
        /^ensureScriptModules\(\)/ { capture = 0 }
        capture && /\[\[ ! -d "\$\{archiveDir\}\/shell" \]\]/ { count++ }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/install.sh")
    [[ "${archiveGuardCount}" == "1" ]]
}

runRegressionDispatcherSingleLegacyFallbackRegression() {
    local legacyDispatchCount
    legacyDispatchCount=$(awk '
        /exec bash "\$\{SCRIPT_DIR\}\/regression\/subscription_groups_legacy\.sh" "\$@"/ { count++ }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/subscription_groups_regression.sh")
    [[ "${legacyDispatchCount}" == "1" ]]
}

runRemoteControlSystemctlStubDefaultStopDisableRegression() {
    local explicitStopDisableCount
    explicitStopDisableCount=$(awk '
        /runSubscriptionControlServiceInstallRegression\(\) \(/ { capture = 1 }
        capture && /cat >"\$\{fakeBin\}\/systemctl" <<\x27SH\x27/ { in_stub = 1 }
        in_stub && /^stop\)$/ { count++ }
        in_stub && /^disable\)$/ { count++ }
        in_stub && /^SH$/ { in_stub = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh")
    [[ "${explicitStopDisableCount}" == "0" ]]
}

runRemoteControlFunctionStubDefaultStopDisableRegression() {
    local explicitStopDisableCount
    explicitStopDisableCount=$(awk '
        /systemctl\(\) \{/ { capture = 1 }
        capture && /stop \| disable\)/ { count++ }
        capture && /^    }$/ { capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/regression/subscription_groups_remote_control.sh")
    [[ "${explicitStopDisableCount}" == "0" ]]
}

runTuicProtocolSingleDefaultBranchRegression() {
    local explicitCubicCount
    explicitCubicCount=$(awk '
        /initTuicProtocol\(\) \{/ { capture = 1 }
        capture && /case \$\{selectTuicAlgorithm\} in/ { in_case = 1 }
        in_case && /tuicAlgorithm="cubic"/ { count++ }
        in_case && /^        esac$/ { in_case = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh")
    [[ "${explicitCubicCount}" == "1" ]]
}

runTlsDnsApiSingleDefaultBranchRegression() {
    local explicitCloudflareCount
    explicitCloudflareCount=$(awk '
        /switchDNSAPI\(\) \{/ { capture = 1 }
        capture && /case \$\{selectDNSAPIType\} in/ { in_case = 1 }
        in_case && /dnsAPIType="cloudflare"/ { count++ }
        in_case && /^        esac$/ { in_case = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/core/tls.sh")
    [[ "${explicitCloudflareCount}" == "1" ]]
}

runTlsCaSingleDefaultBranchRegression() {
    local explicitLetsEncryptCount
    explicitLetsEncryptCount=$(awk '
        /switchSSLType\(\) \{/ { capture = 1 }
        capture && /case \$\{selectSSLType\} in/ { in_case = 1 }
        in_case && /sslType="letsencrypt"/ { count++ }
        in_case && /^        esac$/ { in_case = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/core/tls.sh")
    [[ "${explicitLetsEncryptCount}" == "1" ]]
}

runRealityTargetSingleDefaultBranchRegression() {
    local explicitDefaultTargetCount
    explicitDefaultTargetCount=$(awk '
        /collectRealityProfile\(\) \{/ { capture = 1 }
        capture && /case "\$\{selectRealityTargetMode\}" in/ { in_case = 1 }
        in_case && /^[[:space:]]*selectDefaultRealityTarget$/ { count++ }
        in_case && /^    esac$/ { in_case = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh")
    [[ "${explicitDefaultTargetCount}" == "3" ]]
}

runAutoInstallTypeSingleCustomBranchRegression() {
    local explicitCustomMenuCount
    explicitCustomMenuCount=$(awk '
        /autoValueForKey\(\) \{/ { capture = 1 }
        capture && /case "\$\{AUTO_INSTALL_TYPE\}" in/ { in_case = 1 }
        in_case && /printf '\''5'\''/ { count++ }
        in_case && /^        esac$/ { in_case = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/core/runtime.sh")
    [[ "${explicitCustomMenuCount}" == "1" ]]
}

runSubscriptionMenuWrapperCountRegression() {
    local wrapperCount
    wrapperCount=$(awk '
        /^(manageSubscriptionQuickStart|manageSubscriptionMultiServerQuickStart|showUserSubscriptionLinksMenu|showSubscriptionControlPlaneDetails|manageLocalSubscription|manageSharedSubscriptions|createUserSubscription|manageMainControllerSubscriptions|manageControlledSubscription|manageSubscriptionMainControlMenu|manageSubscriptionDiagnostics)\(\) \{/ { count++ }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/subscription/menu.sh")
    [[ "${wrapperCount}" == "0" ]]
}

runUnusedHelperFunctionCountRegression() {
    local helperCount
    helperCount=$(
        {
            awk '/^(check_apt_update)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/validate_install.sh"
            awk '/^(subscriptionRequireMainFeatures)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/menu.sh"
            awk '/^(showUserSubscriptionQuota)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/traffic.sh"
            awk '/^(menuTitle|infoCard)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/locale.sh"
        } | awk '{ sum += $1 } END { print sum + 0 }'
    )
    [[ "${helperCount}" == "0" ]]
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
    [[ ! -e "${marker}" ]]

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
    grep -q '^shell/core/fail2ban\.sh$' "${outputList}"
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

runInitSubscribeLocalConfigCleansAllFormatsRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/subscribe-local-cleanup"
        export PADM_SUBSCRIBE_LOCAL_DIR="${root}/subscribe_local"
        mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/default" "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta" "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box"
        printf '%s\n' old-default >"${PADM_SUBSCRIBE_LOCAL_DIR}/default/main"
        printf '%s\n' old-clash >"${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta/main"
        printf '[]\n' >"${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/main"
        cleanDirectoryContent() {
            local targetPath=$1
            mkdir -p "${targetPath}"
            find "${targetPath}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/subscription/subscription.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/subscription/output.sh"
        initSubscribeLocalConfig
        [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/default/main" ]]
        [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta/main" ]]
        [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/main" ]]
    )
}

runShowAccountsXrayWithSingBoxAssistRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/show-accounts-xray-singbox-assist"
        local xrayRoot="${root}/etc/padm/xray/conf"
        local singBoxRoot="${root}/etc/padm/sing-box/conf/config"
        local nginxRoot="${root}/etc/nginx/conf.d"
        local captureLog="${root}/capture.log"

        mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
        : >"${captureLog}"
        export PADM_SUBSCRIBE_LOCAL_DIR="${root}/subscribe_local"
        mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/default" "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta" "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box"

        cat >"${xrayRoot}/07_VLESS_vision_reality_inbounds.json" <<'JSON'
{"inbounds":[{"port":443},{"settings":{"clients":[{"email":"sub_base-vless_reality_vision","id":"11111111-1111-1111-1111-111111111111"}]},"streamSettings":{"realitySettings":{"serverNames":["www.ibm.com"],"publicKey":"pub","privateKey":"priv","target":"www.ibm.com:443","mldsa65Seed":"","mldsa65Verify":""}}}]}
JSON
        cat >"${singBoxRoot}/08_VLESS_vision_gRPC_inbounds.json" <<'JSON'
{"inbounds":[{"type":"vless","listen_port":20888,"users":[{"uuid":"22222222-2222-2222-2222-222222222222","name":"sub_grpc-VLESS_Reality_gPRC"}],"tls":{"server_name":"nodejs.org","reality":{"handshake":{"server":"nodejs.org","server_port":443}}},"transport":{"type":"grpc","service_name":"grpc"}}]}
JSON
        cat >"${singBoxRoot}/10_naive_inbounds.json" <<'JSON'
{"inbounds":[{"type":"naive","listen_port":33577,"users":[{"username":"sub_naive-singbox_naive","password":"naive-pass"}]}]}
JSON
        cat >"${singBoxRoot}/11_VMess_HTTPUpgrade_inbounds.json" <<'JSON'
{"inbounds":[{"type":"vmess","listen_port":31306,"users":[{"uuid":"33333333-3333-3333-3333-333333333333","name":"sub_httpupgrade-VMess_HTTPUpgrade","alterId":0}],"transport":{"type":"httpupgrade","path":"/padmhttp"}}]}
JSON
        cat >"${singBoxRoot}/13_anytls_inbounds.json" <<'JSON'
{"inbounds":[{"type":"anytls","listen_port":40251,"users":[{"name":"sub_anytls-anytls","password":"anytls-pass"}]}]}
JSON
        local fakeXray="${root}/etc/padm/xray/xray"
        mkdir -p "$(dirname "${fakeXray}")"
        cat >"${fakeXray}" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "x25519" && "${2:-}" == "-i" ]]; then
    printf 'PrivateKey: %s\n' "${3:-}"
    printf 'Password (PublicKey): grpc-public-key\n'
    exit 0
fi
exit 1
EOF
        chmod +x "${fakeXray}"
        export PADM_XRAY_BINARY="${fakeXray}"
        cat >"${nginxRoot}/sing_box_VMess_HTTPUpgrade.conf" <<'EOF'
server {
    listen 24443 ssl;
    server_name upgrade.example.com;
}
EOF

        readInstallType() {
            coreInstallType=1
            configPath="${xrayRoot}/"
            singBoxConfigPath="${singBoxRoot}/"
            ctlPath="${fakeXray}"
            nginxConfigPath="${nginxRoot}/"
        }
        readConfigHostPathUUID() {
            currentHost=example.com
            currentPath=padm
            currentCDNAddress=cdn.example.com
            currentDefaultPort=443
            singBoxVMessHTTPUpgradePath=/padmhttp
            return 0
        }
        readSingBoxConfig() { return 0; }
        subscribeSectionTitle() { return 0; }
        subscribeAccountTitle() { return 0; }
        subscribeOutputTitle() { return 0; }
        echoContent() { return 0; }
        menuClose() { return 0; }
        realityEntryHost() { printf 'entry.example.com'; }
        appendDefaultSubscribeLine() {
            printf 'default:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        appendClashMetaSubscribeBlock() {
            printf 'clash:%s\n' "$1" >>"${captureLog}"
        }
        appendSingBoxSubscribeLocalConfig() {
            printf 'singbox:%s\n' "$1" >>"${captureLog}"
        }
        initSubscribeLocalConfig() { return 0; }

        showAccounts >/dev/null

        grep -q 'default:sub_grpc:' "${captureLog}"
        grep -q 'default:sub_naive:' "${captureLog}"
        grep -q 'default:sub_httpupgrade:' "${captureLog}"
        grep -q 'default:sub_anytls:' "${captureLog}"
        grep -q 'default:sub_grpc:.*sni=nodejs.org' "${captureLog}"
        grep -q 'default:sub_grpc:.*pbk=grpc-public-key' "${captureLog}"

        local httpupgradeLink httpupgradeJson
        httpupgradeLink=$(grep '^default:sub_httpupgrade:vmess://' "${captureLog}" | head -n 1)
        httpupgradeJson=$(printf '%s' "${httpupgradeLink#default:sub_httpupgrade:vmess://}" | base64 -d)
        printf '%s\n' "${httpupgradeJson}" | grep -q '"port":24443'
        printf '%s\n' "${httpupgradeJson}" | grep -q '"path":"/padmhttp"'
    )
}

runSingBoxHttpUpgradeIncrementalStartsNginxRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/httpupgrade-incremental-starts-nginx"
        local singBoxRoot="${root}/etc/padm/sing-box/conf/config"
        local nginxRoot="${root}/etc/nginx/conf.d"
        local actionLog="${root}/actions.log"
        mkdir -p "${singBoxRoot}" "${nginxRoot}"
        : >"${actionLog}"

        selectCustomInstallType=",11,"
        currentUUID="11111111-1111-4111-8111-111111111111"
        currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"main-VLESS_TCP/TLS_Vision"}]'
        lastInstallationConfig=true
        currentHost=example.com
        domain=example.com
        singBoxVMessHTTPUpgradePort=
        singBoxConfigPath="${singBoxRoot}/"
        nginxConfigPath="${nginxRoot}/"

        collectTLSProfile() { tlsCertDomain=example.com; }
        readSingBoxPortResult() {
            local -n resultRef=$1
            resultRef=(24443)
        }
        initSingBoxClients() { printf '[]'; }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 0; }
        stopSingBoxBeforeTemplateWrite() { return 0; }
        randomPathFunction() { currentPath=httpup; }
        checkPortOpen() { return 0; }
        singBoxNginxConfig() {
            printf 'server {}\n' >"${nginxRoot}/sing_box_VMess_HTTPUpgrade.conf"
        }
        bootStartup() {
            printf 'boot:%s\n' "$1" >>"${actionLog}"
        }
        handleNginx() {
            printf 'nginx:%s\n' "$1" >>"${actionLog}"
            return 0
        }
        runCoreServiceActionAllowFailure() {
            "$@"
        }
        writeGeneratedJsonFile() {
            local targetPath=$1
            if [[ "${targetPath}" == /etc/padm/* ]]; then
                targetPath="${root}${targetPath}"
            fi
            local targetDir
            targetDir=$(dirname -- "${targetPath}")
            mkdir -p "${targetDir}"
            shift 2
            cat >"${targetPath}"
        }

        initSingBoxConfig custom 1 true >/dev/null

        grep -q 'boot:nginx' "${actionLog}"
        grep -q 'nginx:start' "${actionLog}"
        [[ -f "${singBoxRoot}/11_VMess_HTTPUpgrade_inbounds.json" ]]
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

runServicesProcRaceRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        readlink() { return 1; }
        tr() { return 1; }
        pgrep() { printf '1234\n'; }
        padmReadProcExe "/proc/1234/exe" >/dev/null
        [[ -z "$(padmReadProcCmdline "/proc/1234/cmdline")" ]]
        ! nginxRunning
        ! singBoxRunning
        ! xrayRunning
    )
}

runSingBoxRunningIgnoresClientProcessRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        singBoxMergedConfigFile() { printf '%s\n' "/etc/padm/sing-box/conf/config.json"; }
        singBoxSystemdServiceFile() { printf '%s\n' "${TMP_DIR}/sing-box.service"; }
        singBoxOpenRcServiceFile() { printf '%s\n' "${TMP_DIR}/sing-box.openrc"; }
        : >"${TMP_DIR}/sing-box.service"
        pgrep() { printf '2001\n2002\n'; }
        padmReadProcExe() { printf '/etc/padm/sing-box/sing-box\n'; }
        padmReadProcCmdline() {
            if [[ "$1" == "/proc/2001/cmdline" ]]; then
                printf '/etc/padm/sing-box/sing-box run -c /tmp/padm-client.json'
            else
                printf '/etc/padm/sing-box/sing-box run -c /etc/padm/sing-box/conf/config.json'
            fi
        }
        singBoxRunning
        pgrep() { printf '2001\n'; }
        ! singBoxRunning
    )
}

runServiceWaitForStateRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        local root="${TMP_DIR}/service-wait-state"
        mkdir -p "${root}"
        serviceRunning() { [[ -f "${root}/running" ]]; }
        (
            sleep 1.4
            : >"${root}/running"
        ) &
        waitForServiceState serviceRunning running 25 0.1
        rm -f "${root}/running"
        waitForServiceState serviceRunning stopped 2 0.1
    )
}

runWarpConfigGenerationFailureRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/warp-config-generation-failure"
        local warpDir="${root}/warp"
        local singBoxRoot="${root}/sing-box/"
        mkdir -p "${warpDir}" "${singBoxRoot}"

        export PADM_WARP_DIR="${warpDir}"
        singBoxConfigPath="${singBoxRoot}"
        coreInstallType=2
        warpRegCoreCPUVendor="main-linux-amd64"
        address="172.16.0.2/32"

        autoRead() {
            if [[ "$1" == "warp_reg_install" ]]; then
                printf -v "$3" '%s' 'n'
            else
                printf -v "$3" '%s' ''
            fi
        }
        downloadGitHubReleaseAsset() { return 1; }
        errorCard() { return 0; }
        statusCard() { return 0; }
        successCard() { return 0; }
        progressCard() { return 0; }
        echoContent() { return 0; }
        menuLine() { return 0; }
        menuItem() { return 0; }
        menuDangerItem() { return 0; }
        menuReturnItem() { return 0; }
        menuClose() { return 0; }
        reloadCore() { return 0; }

        cat >"${warpDir}/warp-reg" <<'EOF'
#!/usr/bin/env bash
printf 'Post "https://api.cloudflareclient.com/v0a2158/reg": EOF\n'
exit 1
EOF
        chmod +x "${warpDir}/warp-reg"

        ! readConfigWarpReg
        [[ ! -f "${warpDir}/config" ]]

        if addSingBoxWireGuardEndpoints IPv4 >/dev/null 2>&1; then
            return 1
        fi
        [[ ! -f "${singBoxRoot}wireguard_endpoints_IPv4.json" ]]
        [[ ! -f "${warpDir}/config" ]]
    )
}

runFail2banProfileRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/fail2ban.sh"

        local root="${TMP_DIR}/fail2ban-profile"
        mkdir -p "${root}/fail2ban/jail.d" "${root}/fail2ban/filter.d" "${root}/nginx"
        export PADM_FAIL2BAN_JAIL_FILE="${root}/fail2ban/jail.d/padm.local"
        export PADM_FAIL2BAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-control.conf"
        export PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE="${root}/fail2ban/filter.d/padm-nginx-scan-basic.conf"
        export PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/nginx/padm-control-access.log"
        export PADM_FAIL2BAN_NGINX_ACCESS_LOG_FILE="${root}/nginx/access.log"
        export PADM_FAIL2BAN_VALIDATE_LOG="${root}/fail2ban/validate.log"

        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", control_port:39778, peers:[{id:"edge-a"}]}'
        }
        subscriptionWireGuardControlEnabled() { return 0; }
        fail2banServiceActive() { return 1; }
        fail2banServiceEnabled() { return 1; }
        fail2banInstalled() { return 0; }
        fail2banValidateManagedConfig() { return 0; }
        fail2banStartOrReloadService() { return 0; }
        refreshSubscriptionWireGuardNginxControl() { return 0; }
        serviceQueueApply() { return 0; }
        errorCard() { return 1; }
        successCard() { return 0; }

        [[ "$(fail2banRecommendedProfileName)" == "sshd+control" ]]
        [[ "$(fail2banProfileLabel "$(fail2banRecommendedProfileName)")" == "SSH + 控制面防护" ]]
        fail2banWriteManagedFilter
        fail2banWriteNginxScanFilter
        fail2banWriteManagedJail sshd+control false
        grep -q '^\[sshd\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^enabled = true' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^\[padm-control\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^\[nginx-scan-basic\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^enabled = false$' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q "logpath = ${root//\\/\\\\}/nginx/padm-control-access.log" "${PADM_FAIL2BAN_JAIL_FILE}" || grep -q 'logpath = .*/nginx/padm-control-access.log' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q "logpath = ${root//\\/\\\\}/nginx/access.log" "${PADM_FAIL2BAN_JAIL_FILE}" || grep -q 'logpath = .*/nginx/access.log' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '/s/control/' "${PADM_FAIL2BAN_FILTER_FILE}"
        grep -Eq 'wp-login\.php|\.env|phpmyadmin|actuator' "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd,padm-control" ]]
        [[ "$(fail2banCurrentProfileName)" == "sshd+control" ]]
        ! fail2banCurrentNginxScanEnabled
        [[ "$(fail2banNginxScanStatusText)" == "默认关闭" ]]

        fail2banWriteManagedJail sshd false
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd" ]]
        [[ "$(fail2banCurrentProfileName)" == "sshd" ]]
        ! fail2banCurrentNginxScanEnabled
        cat >"${PADM_FAIL2BAN_JAIL_FILE}" <<'EOF'
[sshd]
enabled = true
[padm-control]
enabled = true
EOF
        ! fail2banManagedJailHasSection nginx-scan-basic
        ! fail2banCurrentNginxScanEnabled
        [[ "$(fail2banNginxScanStatusText)" == "默认关闭" ]]

        fail2banWriteManagedJail sshd+control true
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd,padm-control,nginx-scan-basic" ]]
        fail2banCurrentNginxScanEnabled
        [[ "$(fail2banNginxScanStatusText)" == "已启用" ]]

        subscriptionWireGuardControlEnabled() { return 1; }
        [[ "$(fail2banRecommendedProfileName)" == "sshd" ]]
        ! fail2banApplyProfile sshd+control

        subscriptionWireGuardControlEnabled() { return 0; }
        fail2banApplyProfile sshd+control true
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd,padm-control,nginx-scan-basic" ]]
        fail2banApplyProfile sshd false
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd" ]]
        ! fail2banCurrentNginxScanEnabled
        fail2banApplyNginxScanExtension enable
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd,nginx-scan-basic" ]]
        fail2banCurrentNginxScanEnabled
        fail2banApplyNginxScanExtension disable
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd" ]]
        ! fail2banCurrentNginxScanEnabled

        cat >"${PADM_FAIL2BAN_JAIL_FILE}" <<'EOF'
[sshd]
enabled = false
[padm-control]
enabled = false
[nginx-scan-basic]
enabled = true
EOF
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "nginx-scan-basic" ]]
        [[ "$(fail2banCurrentProfileName)" == "disabled" ]]
        fail2banApplyNginxScanExtension disable
        [[ "$(fail2banCurrentEnabledJailsCsv)" == "sshd" ]]
        ! fail2banCurrentNginxScanEnabled
    )
}

runFail2banMenuRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/fail2ban.sh"

        local actions=
        local output=
        recordMenuAction() {
            actions+="$1"$'\n'
        }
        assertMenuAction() {
            grep -qxF "$1" <<<"${actions}"
        }
        menuLine() { output+="$*"$'\n'; }
        menuItem() { output+="$2 $3"$'\n'; }
        menuDangerItem() { output+="$2 $3"$'\n'; }
        menuReturnItem() { output+="$2 $3"$'\n'; }
        menuClose() { return 0; }
        echoContent() { return 0; }
        uiStyle() { shift; printf '%s' "$*"; }
        autoRead() {
            local targetVar=$3
            local input=
            IFS= read -r input || input=
            printf -v "${targetVar}" '%s' "${input}"
        }
        fail2banRoleText() { printf '主控'; }
        fail2banControlSurfaceText() { printf '已检测到 /s/control/'; }
        fail2banCurrentProfileLabel() { printf 'SSH + 控制面防护'; }
        fail2banNginxScanStatusText() { printf '默认关闭'; }
        showFail2banRuntimeStatus() { recordMenuAction showFail2banRuntimeStatus; }
        fail2banRecommendedProfileName() { printf 'sshd+control\n'; }
        fail2banApplyProfile() { recordMenuAction "fail2banApplyProfile:$1:${2:-}"; }
        fail2banApplyNginxScanExtension() { recordMenuAction "fail2banApplyNginxScanExtension:$1"; }
        showFail2banBans() { recordMenuAction showFail2banBans; }
        systemScriptMenu() { recordMenuAction systemScriptMenu; }
        errorCard() { recordMenuAction "errorCard:$1"; }

        manageFail2ban <<<"5"
        grep -q "启用站点扫描扩展防护" <<<"${output}"
        grep -q "关闭站点扫描扩展防护" <<<"${output}"
        assertMenuAction "fail2banApplyNginxScanExtension:enable"

        actions=
        output=
        manageFail2ban <<<"6"
        assertMenuAction "fail2banApplyNginxScanExtension:disable"
    )
}

runSingBoxCompatibilityAuditRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/singbox-compat-audit"
        export PADM_SINGBOX_BINARY="${TMP_DIR}/fake-sing-box-bin"
        mkdir -p "${root}/conf/config"
        singBoxConfigPath="${root}/conf/config/"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${PADM_SINGBOX_BINARY}"
        chmod +x "${PADM_SINGBOX_BINARY}"
        cat >"${root}/conf/config.json" <<'JSON'
{"dns":{"servers":[{"address":"local","strategy":"ipv4_only"}],"rules":[{"outbound":"legacy-out"}]},"outbounds":[{"type":"wireguard","tag":"legacy-wg"},{"type":"block","tag":"legacy-block"}],"endpoints":[{"type":"wireguard","tag":"new-endpoint"}]}
JSON
        local statusFile warnFile logFile
        statusFile=$(singBoxCompatibilityAuditStatusFile)
        warnFile=$(singBoxCompatibilityAuditWarnFile)
        logFile=$(singBoxCompatibilityAuditLog)
        collectSingBoxCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
        grep -q '^fail:' "${statusFile}"
        grep -q 'old WireGuard outbound' "${logFile}"
        grep -q 'legacy special outbound' "${logFile}"
        grep -q '旧 DNS server 格式' "${logFile}"
    )
}

runSingBoxPrereleaseDryRunRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/singbox-prerelease"
        export PADM_SINGBOX_BINARY="${TMP_DIR}/fake-sing-box-bin"
        singBoxConfigPath="${root}/conf/config/"
        mkdir -p "${root}/conf/config"
        printf '#!/usr/bin/env bash\nif [[ \"$1\" == \"version\" ]]; then echo \"sing-box version 1.13.13\"; fi\n' >"${PADM_SINGBOX_BINARY}"
        chmod +x "${PADM_SINGBOX_BINARY}"
        printf '{"inbounds":[]}\n' >"${root}/conf/config.json"
        downloadSingBoxReleaseBinaryToTemp() {
            local _version=$1
            local _outVar=$2
            local _tmpVar=${3:-}
            printf -v "${_outVar}" '%s' "${PADM_SINGBOX_BINARY}"
            [[ -n "${_tmpVar}" ]] && printf -v "${_tmpVar}" '%s' "${TMP_DIR}/fake-download"
        }
        validateSingBoxConfigWithBinary() {
            local binary=$1
            local logFile=$2
            printf 'checked %s\n' "${binary}" >"${logFile}"
            [[ "${binary}" == "${PADM_SINGBOX_BINARY}" ]]
        }
        : >"${REGRESSION_STATUS_CARD_LOG:-/dev/null}"
        checkSingBoxPrereleaseCompatibility "v1.14.0-alpha.test" "${TMP_DIR}/prerelease.log"
        grep -q '目标版本: v1.14.0-alpha.test' "${REGRESSION_STATUS_CARD_LOG:-/dev/null}"
        grep -q 'checked' "${TMP_DIR}/prerelease.log"
    )
}

runXrayStrictValidationRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/xray-strict-validation"
        local xrayRoot="${root}/etc/padm/xray"
        export PADM_XRAY_BINARY="${xrayRoot}/xray"
        export PADM_XRAY_CONF_DIR="${xrayRoot}/conf"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        cat >"${PADM_XRAY_BINARY}" <<'EOF'
#!/usr/bin/env bash
if [[ "${XRAY_JSON_STRICT:-}" == "true" ]]; then
    printf 'strict-ok\n'
else
    printf 'normal-ok\n'
fi
exit 0
EOF
        chmod +x "${PADM_XRAY_BINARY}"
        printf '{"log":{}}\n' >"${PADM_XRAY_CONF_DIR}/00_log.json"
        showXrayStrictValidation "${TMP_DIR}/xray-strict.log"
        grep -q 'strict-ok' "${TMP_DIR}/xray-strict.log"
    )
}

runXrayCompatibilityAuditRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/xray-compat-audit"
        local xrayRoot="${root}/etc/padm/xray"
        export PADM_XRAY_BINARY="${xrayRoot}/xray"
        export PADM_XRAY_CONF_DIR="${xrayRoot}/conf"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${PADM_XRAY_BINARY}"
        chmod +x "${PADM_XRAY_BINARY}"
        cat >"${PADM_XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json" <<'JSON'
{"inbounds":[{"streamSettings":{"network":"xhttp"},"settings":{"clients":[{"email":"sub-x"}]}}],"echForceQuery":true}
JSON
        cat >"${PADM_XRAY_CONF_DIR}/00_reverse.json" <<'JSON'
{"reverse":{"bridges":[]}}
JSON
        local statusFile warnFile logFile
        statusFile=$(xrayCompatibilityAuditStatusFile)
        warnFile=$(xrayCompatibilityAuditWarnFile)
        logFile=$(xrayCompatibilityAuditLog)
        collectXrayCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
        grep -q '^fail:' "${statusFile}"
        grep -q '旧 users schema' "${logFile}"
        grep -q 'echForceQuery' "${logFile}"
        grep -q 'legacy reverse' "${logFile}"
        grep -q 'trustedXForwardedFor' "${logFile}"
    )
}

runXrayPrereleaseDryRunRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/xray-prerelease"
        local xrayRoot="${root}/etc/padm/xray"
        export PADM_XRAY_BINARY="${xrayRoot}/xray"
        export PADM_XRAY_CONF_DIR="${xrayRoot}/conf"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        printf '{"log":{}}\n' >"${PADM_XRAY_CONF_DIR}/00_log.json"
        printf '#!/usr/bin/env bash\nif [[ \"$1\" == \"--version\" ]]; then printf \"Xray 26.0.0 test\\n\"; exit 0; fi\nprintf \"checked:%s:%s\\n\" \"${XRAY_JSON_STRICT:-false}\" \"$*\"\nexit 0\n' >"${PADM_XRAY_BINARY}"
        chmod +x "${PADM_XRAY_BINARY}"
        downloadXrayReleaseBinaryToTemp() {
            local _version=$1
            local _outVar=$2
            local _tmpVar=${3:-}
            printf -v "${_outVar}" '%s' "${PADM_XRAY_BINARY}"
            [[ -n "${_tmpVar}" ]] && printf -v "${_tmpVar}" '%s' "${TMP_DIR}/fake-xray-download"
        }
        validateXrayConfigWithBinary() {
            local binary=$1
            local logFile=$2
            printf 'checked:normal:%s\n' "${binary}" >"${logFile}"
            [[ "${binary}" == "${PADM_XRAY_BINARY}" ]]
        }
        validateXrayConfigStrictWithBinary() {
            local binary=$1
            local logFile=$2
            printf 'checked:strict:%s\n' "${binary}" >"${logFile}"
            [[ "${binary}" == "${PADM_XRAY_BINARY}" ]]
        }
        checkXrayPrereleaseCompatibility "v26.6.1" "${TMP_DIR}/xray-prerelease.log"
        grep -q '\[普通模式校验\]' "${TMP_DIR}/xray-prerelease.log"
        grep -q '\[严格模式校验\]' "${TMP_DIR}/xray-prerelease.log"
        grep -q 'checked:normal:' "${TMP_DIR}/xray-prerelease.log"
        grep -q 'checked:strict:' "${TMP_DIR}/xray-prerelease.log"
    )
}

runRegressionPlatform() {
    runRegressionStep release-workflow-version runReleaseWorkflowVersionRegression &&
        runRegressionStep cleanup-trap runCleanupTrapRegression &&
        runRegressionStep check-log-backup-restore runCheckLogBackupMissingRestoreRegression &&
        runRegressionStep update-padm-version-prompt runUpdatePadmVersionPromptRegression &&
        runRegressionStep install-refresh-fallback-main runInstallRefreshFallbackMainRegression &&
        runRegressionStep install-refresh-keep-ref-on-lookup-fail runInstallRefreshKeepsRefWhenRemoteLookupFailsRegression &&
        runRegressionStep install-refresh-restore runInstallRefreshRestoresBackupRegression &&
        runRegressionStep install-refresh-single-archive-guard runInstallRefreshSingleArchiveGuardRegression &&
        runRegressionStep regression-dispatcher-single-legacy-fallback runRegressionDispatcherSingleLegacyFallbackRegression &&
        runRegressionStep remote-control-systemctl-stub-default-stop-disable runRemoteControlSystemctlStubDefaultStopDisableRegression &&
        runRegressionStep remote-control-function-stub-default-stop-disable runRemoteControlFunctionStubDefaultStopDisableRegression &&
        runRegressionStep tuic-protocol-single-default-branch runTuicProtocolSingleDefaultBranchRegression &&
        runRegressionStep tls-dns-api-single-default-branch runTlsDnsApiSingleDefaultBranchRegression &&
        runRegressionStep tls-ca-single-default-branch runTlsCaSingleDefaultBranchRegression &&
        runRegressionStep reality-target-single-default-branch runRealityTargetSingleDefaultBranchRegression &&
        runRegressionStep auto-install-type-single-custom-branch runAutoInstallTypeSingleCustomBranchRegression &&
        runRegressionStep subscription-menu-wrapper-count runSubscriptionMenuWrapperCountRegression &&
        runRegressionStep unused-helper-function-count runUnusedHelperFunctionCountRegression &&
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
        runRegressionStep fedora-detection runFedoraDetectionRegression &&
        runRegressionStep port-hopping-without-persistent runPortHoppingWithoutPersistentRegression
}

runRegressionFast() {
    runRegressionStep platform runRegressionPlatform &&
        runRegressionStep github-release-direct-fallback runGitHubReleaseAssetDirectFallbackRegression &&
        runRegressionStep remove-install-path-retry runRemoveInstallPathRetryRegression &&
        runRegressionStep auto-install-generated-identity runAutoInstallGeneratedIdentityRegression &&
        runRegressionStep auto-install-empty-defaults runAutoInstallAllowsEmptyDefaultRegression &&
        runRegressionStep client-name-suffix-preserves-random-prefix runClientNameSuffixPreservesRandomPrefixRegression &&
        runRegressionStep subscribe-local-cleanup runInitSubscribeLocalConfigCleansAllFormatsRegression &&
        runRegressionStep subscription-output-random-user runSubscriptionOutputRandomUserRegression &&
        runRegressionStep locale-unset-printN runLocaleEchoContentUnsetPrintNRegression &&
        runRegressionStep show-accounts-optional-step runShowAccountsOptionalStepRegression &&
        runRegressionStep show-accounts-xray-singbox-assist runShowAccountsXrayWithSingBoxAssistRegression &&
        runRegressionStep httpupgrade-incremental-starts-nginx runSingBoxHttpUpgradeIncrementalStartsNginxRegression &&
        runRegressionStep allow-port-optional-protocol runAllowPortOptionalProtocolRegression &&
        runRegressionStep core-client-optional-args runCoreClientOptionalArgsRegression &&
        runRegressionStep singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression &&
        runRegressionStep service-wait-state runServiceWaitForStateRegression &&
        runRegressionStep warp-config-generation-failure runWarpConfigGenerationFailureRegression &&
        runRegressionStep fail2ban-profile runFail2banProfileRegression &&
        runRegressionStep fail2ban-menu runFail2banMenuRegression &&
        runRegressionStep xray-strict-validation runXrayStrictValidationRegression &&
        runRegressionStep xray-compat-audit runXrayCompatibilityAuditRegression &&
        runRegressionStep xray-prerelease-dry-run runXrayPrereleaseDryRunRegression &&
        runRegressionStep singbox-compat-audit runSingBoxCompatibilityAuditRegression &&
        runRegressionStep singbox-prerelease-dry-run runSingBoxPrereleaseDryRunRegression &&
        runRegressionStep services-proc-race runServicesProcRaceRegression &&
        runRegressionStep singbox-ignore-client-proc runSingBoxRunningIgnoresClientProcessRegression &&
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
