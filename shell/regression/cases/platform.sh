#!/usr/bin/env bash

runPadmBbrManagedCleanupRegression() (
    local root="${TMP_DIR}/padm-bbr-managed-cleanup"
    local repeatStatus="${root}/repeat.status"
    local repeatHelper="${root}/repeat.helper"
    local tempFailStatus="${root}/temp-fail.status"
    local tempFailHelper="${root}/temp-fail.helper"
    local applyFailStatus="${root}/apply-fail.status"
    local applyFailHelper="${root}/apply-fail.helper"
    local disableStatus="${root}/disable.status"
    local disableHelper="${root}/disable.helper"
    local thirdPartyStatus="${root}/third-party.status"
    local thirdPartyHelper="${root}/third-party.helper"
    local thirdPartyMarker="${root}/third-party.executed"
    local thirdPartyPathLog="${root}/third-party.path"
    local thirdPartyUrlLog="${root}/third-party.url"
    local thirdPartyHashLog="${root}/third-party.hash"
    mkdir -p "${root}"

    rm -f "${thirdPartyMarker}" "${thirdPartyPathLog}" "${thirdPartyUrlLog}" "${thirdPartyHashLog}"
    : >"${thirdPartyStatus}"
    : >"${thirdPartyHelper}"
    bash -c '
        set -e
        export TMPDIR="$1"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        marker=$5
        pathLog=$6
        urlLog=$7
        hashLog=$8
        warnCard() { printf "warn:%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" >>"${helperLog}"; }
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        autoConfirm() { printf -v "$4" y; }
        curl() {
            local outputFile= url=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=${2:-}
                    shift 2
                    ;;
                http://* | https://*)
                    url=$1
                    shift
                    ;;
                *) shift ;;
                esac
            done
            [[ -n "${outputFile}" && -n "${url}" ]] || return 1
            printf "%s\n" "${url}" >>"${urlLog}"
            case "${url}" in
            https://api.github.com/repos/ylx2016/Linux-NetSpeed/commits/master)
                printf "%s\n" "{" "  \"sha\": \"0123456789abcdef0123456789abcdef01234567\"" "}" >"${outputFile}"
                ;;
            https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/0123456789abcdef0123456789abcdef01234567/tcpx.sh)
                cat >"${outputFile}" <<SH
#!/usr/bin/env bash
printf executed >"${marker}"
printf "%s\n" "\$0" >"${pathLog}"
SH
                ;;
            *) return 1 ;;
            esac
        }
        sha256sum() {
            printf "sha256sum:%s\n" "$1" >>"${hashLog}"
            return 1
        }
        runThirdPartyTcpAccelerationScript
    ' _ "${root}" "${PROJECT_ROOT}" "${thirdPartyStatus}" "${thirdPartyHelper}" "${thirdPartyMarker}" "${thirdPartyPathLog}" "${thirdPartyUrlLog}" "${thirdPartyHashLog}"
    [[ -f "${thirdPartyMarker}" && "$(<"${thirdPartyMarker}")" == "executed" ]] || return 1
    grep -qxF 'https://api.github.com/repos/ylx2016/Linux-NetSpeed/commits/master' "${thirdPartyUrlLog}" || return 1
    grep -qxF 'https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/0123456789abcdef0123456789abcdef01234567/tcpx.sh' "${thirdPartyUrlLog}" || return 1
    ! grep -qxF 'https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcpx.sh' "${thirdPartyUrlLog}" || return 1
    [[ ! -s "${thirdPartyHashLog}" ]] || return 1
    local executedThirdPartyPath
    [[ -f "${thirdPartyPathLog}" ]] || return 1
    executedThirdPartyPath=$(<"${thirdPartyPathLog}")
    [[ "${executedThirdPartyPath}" == "${root}/padm-tcpx."*/tcpx.sh ]] || return 1
    [[ ! -e "${root}/padm-tcpx.sh" ]] || return 1
    [[ ! -e "$(dirname -- "${executedThirdPartyPath}")" ]] || return 1

    cat >"${root}/repeat-sysctl.conf" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    cat >"${root}/repeat.state" <<'EOF'
previous_congestion=reno
previous_qdisc=cake
EOF
    : >"${repeatStatus}"
    : >"${repeatHelper}"
    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/repeat-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/repeat.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "bbr\n" ;;
            net.core.default_qdisc) printf "fq\n" ;;
            *) return 0 ;;
            esac
        }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        commitGeneratedFile() { printf "unexpected-commit:%s\n" "$2" >>"${helperLog}"; return 1; }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${repeatStatus}" "${repeatHelper}"
    grep -qx "sysctl:-p ${root}/repeat-sysctl.conf" "${repeatHelper}"
    ! grep -q '^unexpected-commit:' "${repeatHelper}"
    grep -q 'BBR 已启用|沿用已有 padm 配置和首次启用前状态' "${repeatStatus}"
    grep -qx 'previous_congestion=reno' "${root}/repeat.state"
    grep -qx 'previous_qdisc=cake' "${root}/repeat.state"

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/temp-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/temp-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { printf "ensure-dir:%s\n" "$1" >>"${helperLog}"; return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            if [[ "${createCount}" -eq 1 ]]; then
                local path="$TMPDIR/state-stage"
                : >"${path}"
                printf -v "${resultVar}" "%s" "${path}"
                return 0
            fi
            return 1
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFileIfPresent() { printf "remove-file:%s\n" "$1" >>"${helperLog}"; return 0; }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${tempFailStatus}" "${tempFailHelper}"
    grep -q "remove-file:${root}/temp-fail.state" "${tempFailHelper}" || return 1
    grep -q 'BBR 启用失败|无法创建 sysctl 临时文件' "${tempFailStatus}" || return 1

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/apply-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/apply-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            local path="$TMPDIR/stage-${createCount}"
            : >"${path}"
            printf -v "${resultVar}" "%s" "${path}"
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 0; }
        restorePadmBbrRuntime() { printf "restore:%s:%s\n" "$1" "$2" >>"${helperLog}"; }
        sysctl() {
            if [[ "$1" == "-p" ]]; then
                return 1
            fi
            printf "sysctl:%s\n" "$*" >>"${helperLog}"
            return 0
        }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${applyFailStatus}" "${applyFailHelper}"
    grep -q "remove-files:${root}/apply-fail-sysctl.conf|${root}/apply-fail.state" "${applyFailHelper}" || return 1
    grep -q 'restore:cubic:fq_codel' "${applyFailHelper}" || return 1
    grep -q 'BBR 启用失败|sysctl 应用失败，已删除本次写入并尝试恢复原运行值' "${applyFailStatus}" || return 1

    bash -c '
        set -e
        export TMPDIR="$1"
        export PADM_BBR_SYSCTL_CONF="$1/apply-cleanup-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/apply-cleanup-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        createCount=0
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        padmBbrAvailable() { return 0; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        readSysctlValue() {
            case "$1" in
            net.ipv4.tcp_congestion_control) printf "cubic\n" ;;
            net.core.default_qdisc) printf "fq_codel\n" ;;
            *) return 0 ;;
            esac
        }
        padmEnsureSafeDirectory() { return 0; }
        padmCreateTempPath() {
            local resultVar=$1
            createCount=$((createCount + 1))
            local path="$TMPDIR/stage-${createCount}"
            : >"${path}"
            printf -v "${resultVar}" "%s" "${path}"
        }
        commitGeneratedFile() { printf "commit:%s\n" "$2" >>"${helperLog}"; return 0; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 1; }
        restorePadmBbrRuntime() { printf "restore:%s:%s\n" "$1" "$2" >>"${helperLog}"; }
        sysctl() {
            if [[ "$1" == "-p" ]]; then
                return 1
            fi
            printf "sysctl:%s\n" "$*" >>"${helperLog}"
            return 0
        }
        enableOfficialBbrFq
    ' _ "${root}" "${PROJECT_ROOT}" "${applyFailStatus}" "${applyFailHelper}"
    grep -q "manual-check:sysctl 应用失败，且本次写入清理失败| ${root}/apply-cleanup-fail-sysctl.conf 和 ${root}/apply-cleanup-fail.state" "${applyFailHelper}" || return 1
    grep -q 'BBR 启用失败|sysctl 应用失败，且本次写入清理失败，请手动检查 '"${root}"'/apply-cleanup-fail-sysctl.conf 和 '"${root}"'/apply-cleanup-fail.state' "${applyFailStatus}" || return 1

    printf 'net.core.default_qdisc = fq\n' >"${root}/disable-sysctl.conf" || return 1
    printf 'previous_congestion=reno\nprintf sourced >"%s"\nprevious_qdisc=cake\n' "${root}/disable-sourced.marker" >"${root}/disable.state" || return 1
    bash -c '
        set -e
        export PADM_BBR_SYSCTL_CONF="$1/disable-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/disable.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 0; }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        disablePadmBbr
    ' _ "${root}" "${PROJECT_ROOT}" "${disableStatus}" "${disableHelper}"
    grep -q "remove-files:${root}/disable-sysctl.conf|${root}/disable.state" "${disableHelper}" || return 1
    grep -q 'sysctl:--system' "${disableHelper}" || return 1
    grep -q 'sysctl:-w net.ipv4.tcp_congestion_control=reno' "${disableHelper}" || return 1
    grep -q 'sysctl:-w net.core.default_qdisc=cake' "${disableHelper}" || return 1
    [[ ! -e "${root}/disable-sourced.marker" ]]
    grep -q 'padm BBR 已关闭|已删除 '"${root}"'/disable-sysctl.conf' "${disableStatus}" || return 1

    printf 'net.core.default_qdisc = fq\n' >"${root}/disable-cleanup-fail-sysctl.conf" || return 1
    printf 'previous_congestion=reno\nprevious_qdisc=cake\n' >"${root}/disable-cleanup-fail.state" || return 1
    bash -c '
        set -e
        export PADM_BBR_SYSCTL_CONF="$1/disable-cleanup-fail-sysctl.conf"
        export PADM_BBR_STATE_FILE="$1/disable-cleanup-fail.state"
        source "$2/shell/core/runtime.sh"
        source "$2/shell/core/entry_helpers.sh"
        statusLog=$3
        helperLog=$4
        statusCard() { printf "%s|%s|%s\n" "$1" "$2" "${3:-}" >>"${statusLog}"; }
        bbrInstall() { printf "menu\n" >>"${helperLog}"; }
        printNetworkOptimizationStatus() { printf "print-status\n" >>"${helperLog}"; }
        removeManagedFilesIfPresent() { printf "remove-files:%s|%s\n" "$1" "$2" >>"${helperLog}"; return 1; }
        sysctl() { printf "sysctl:%s\n" "$*" >>"${helperLog}"; return 0; }
        disablePadmBbr
    ' _ "${root}" "${PROJECT_ROOT}" "${disableStatus}" "${disableHelper}"
    grep -q 'padm BBR 关闭失败|配置文件清理失败，请手动检查 '"${root}"'/disable-cleanup-fail-sysctl.conf 和 '"${root}"'/disable-cleanup-fail.state' "${disableStatus}" || return 1
)

writeInstallToolsAcmeFixture() {
    local acmeDir=$1
    mkdir -p "${acmeDir}/dnsapi"
    printf '#!/usr/bin/env sh\nexit 0\n' >"${acmeDir}/acme.sh"
    printf '#!/usr/bin/env sh\n' >"${acmeDir}/dnsapi/dns_cf.sh"
    printf '#!/usr/bin/env sh\n' >"${acmeDir}/dnsapi/dns_ali.sh"
}

writeInstallToolsAcmeArchiveFixture() {
    local archiveFile=$1
    local commitRef=$2
    local archiveRoot="${archiveFile}.source"
    writeInstallToolsAcmeFixture "${archiveRoot}/acme.sh-${commitRef}"
    tar -czf "${archiveFile}" -C "${archiveRoot}" "acme.sh-${commitRef}"
}

runInstallToolsCertificateDependencyRegression() (
    local statusLog="${TMP_DIR}/install-tools-cert-status.log"
    local fakeHome="${TMP_DIR}/install-tools-cert-home"
    local nginxCommandLog="${TMP_DIR}/install-tools-nginx-command.log"
    writeInstallToolsAcmeFixture "${fakeHome}/.acme.sh"
    HOME="${fakeHome}"
    export REGRESSION_STATUS_CARD_LOG="${statusLog}"
    export REGRESSION_SUCCESS_CARD_LOG="${statusLog}"
    PADM_INSTALL_LOG="${TMP_DIR}/install-tools-install.log"
    : >"${statusLog}"
    release=debian
    rhelLike=false
    upgrade=true
    updateReleaseInfoChange=true
    packageManager=apt
    selectCustomInstallType=",1,"
    realityOnlyWithDomain=
    command() {
        if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    runWithTimeout() { return 0; }
    runPackageCommandWithProgress() { return 0; }
    waitAptProcess() { return 0; }
    installBasePackages() { return 0; }
    installNginxTools() { printf 'unexpected-nginx\n' >>"${statusLog}"; return 1; }
    nginx() { return 0; }
    protocolSelectionSkipsNginx() { return 0; }
    beginPackageInstallTransaction() { PADM_PACKAGE_TRANSACTION_STARTED=; }
    completePackageInstallTransaction() { return 0; }

    installTools 1
    grep -q "跳过安装 acme.sh" "${statusLog}"

    : >"${statusLog}"
    realityOnlyWithDomain=true
    installTools 1
    grep -q "跳过安装 acme.sh" "${statusLog}"

    for selectCustomInstallType in ",1," ",2," ",26,"; do
        ! protocolSelectionNeedsLocalCertificate "${selectCustomInstallType}"
    done

    : >"${statusLog}"
    selectCustomInstallType=",3,"
    realityOnlyWithDomain=
    installTools 1
    ! grep -q "跳过安装 acme.sh" "${statusLog}"

    : >"${nginxCommandLog}"
    protocolSelectionSkipsNginx() { return 1; }
    nginx() {
        printf '%s\n' "$*" >>"${nginxCommandLog}"
        [[ "${1:-}" == "-v" ]] || return 1
        printf 'nginx version: nginx/1.26.0\n' >&2
    }
    installTools 1
    [[ -s "${nginxCommandLog}" ]]
    ! grep -vx -- '-v' "${nginxCommandLog}"
    ! grep -q 'unexpected-nginx' "${statusLog}"
)

runInstallToolsAcmeResultFailureRegression() {
    (
        local fakeHome="${TMP_DIR}/install-tools-acme-result-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-result-tmp"
        local errorLog="${TMP_DIR}/install-tools-acme-result-error.log"
        local statusLog="${TMP_DIR}/install-tools-acme-result-status.log"
        local acmeRunCommandLog="${TMP_DIR}/install-tools-acme-result-command.log"
        local installStatus

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${acmeRunCommandLog}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        mkdir -p "${fakeHome}/.acme.sh"
        printf 'legacy-state\n' >"${fakeHome}/.acme.sh/account.conf"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        : >"${errorLog}"
        : >"${statusLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                printf '%s\n' "${2:-}" >"${acmeRunCommandLog}"
                mkdir -p "${fakeHome}/.acme.sh"
                printf 'partial-install\n' >"${fakeHome}/.acme.sh/partial.txt"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            writeInstallToolsAcmeArchiveFixture "${outputFile}" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        }
        tail() { return 0; }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "acme.sh安装结果校验失败" "${errorLog}"
        [[ -s "${acmeRunCommandLog}" ]]
        grep -q -- '--install' "${acmeRunCommandLog}"
        ! grep -qF "${tmpRoot}/padm-tls/acme.sh" "${acmeRunCommandLog}"
        grep -Eq "cd \\\"${tmpRoot}/padm-tls\\.[^/]+/acme\\.sh-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\"" "${acmeRunCommandLog}"
        grep -qF '&& sh ./acme.sh --install' "${acmeRunCommandLog}"
        [[ ! -d "${tmpRoot}/padm-tls" ]]
        [[ ! -e "${fakeHome}/.acme.sh/acme.sh" ]]
        [[ "$(<"${fakeHome}/.acme.sh/account.conf")" == "legacy-state" ]]
        [[ ! -e "${fakeHome}/.acme.sh/partial.txt" ]]
        if regressionFindHasMatches "${tmpRoot}" -maxdepth 1 -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi
    )
}

runInstallToolsAcmeCommitFailureRegression() {
    (
        local fakeHome="${TMP_DIR}/install-tools-acme-commit-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-commit-tmp"
        local errorLog="${TMP_DIR}/install-tools-acme-commit-error.log"
        local statusLog="${TMP_DIR}/install-tools-acme-commit-status.log"
        local runMarker="${TMP_DIR}/install-tools-acme-commit-run"
        local installStatus

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${runMarker}"
        mkdir -p "${fakeHome}" "${tmpRoot}"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        : >"${errorLog}"
        : >"${statusLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                : >"${runMarker}"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o)
                    outputFile=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            writeInstallToolsAcmeArchiveFixture "${outputFile}" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        }
        mv() { return 1; }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "acme安装包提交失败" "${errorLog}"
        [[ ! -e "${runMarker}" ]]
        [[ ! -d "${tmpRoot}/padm-tls" ]]
        if regressionFindHasMatches "${tmpRoot}" -type f -name 'acme.tar.gz.download.*'; then
            return 1
        fi
    )
}

runInstallToolsAcmeDownloadBoundsRegression() {
    (
        local fakeHome="${TMP_DIR}/install-tools-acme-download-bounds-home"
        local tmpRoot="${TMP_DIR}/install-tools-acme-download-bounds-tmp"
        local curlLog="${TMP_DIR}/install-tools-acme-download-bounds-curl.log"

        rm -rf "${fakeHome}" "${tmpRoot}"
        rm -f "${curlLog}"
        mkdir -p "${fakeHome}/.acme.sh" "${tmpRoot}"
        printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
        HOME="${fakeHome}"
        TMPDIR="${tmpRoot}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-acme-download-bounds-install.log"
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() {
            if [[ "${2:-}" == *"acme.sh"* ]]; then
                writeInstallToolsAcmeFixture "${fakeHome}/.acme.sh"
            fi
            return 0
        }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        resolveGitHubCommitRef() { [[ "$1" == "acmesh-official/acme.sh" && "$2" == "master" ]] && printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n'; }
        curl() {
            local outputFile=
            printf '%s\n' "$*" >"${curlLog}"
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -o) outputFile=$2; shift 2 ;;
                *) shift ;;
                esac
            done
            [[ -n "${outputFile}" ]] || return 1
            writeInstallToolsAcmeArchiveFixture "${outputFile}" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        }

        installTools 1 >/dev/null 2>&1
        grep -q -- '--connect-timeout 10' "${curlLog}"
        grep -q -- '--max-time 120' "${curlLog}"
        grep -q -- '--max-filesize 5242880' "${curlLog}"
        grep -q 'github.com/acmesh-official/acme.sh/archive/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.tar.gz' "${curlLog}"
        [[ -f "${fakeHome}/.acme.sh/dnsapi/dns_cf.sh" ]]
        [[ -f "${fakeHome}/.acme.sh/dnsapi/dns_ali.sh" ]]
    )
}

runInstallToolsRefreshFailureRegression() (
    local failure=$1
    local errorLog="${TMP_DIR}/install-tools-${failure}-error.log"
    local fakeHome="${TMP_DIR}/install-tools-${failure}-home"
    local expectedError installStatus
    PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE="${TMP_DIR}/install-tools-${failure}-base-called"

    mkdir -p "${fakeHome}/.acme.sh"
    printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
    HOME="${fakeHome}"
    export REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_INSTALL_LOG="${TMP_DIR}/install-tools-${failure}-install.log"
    : >"${errorLog}"
    release=debian
    rhelLike=false
    packageManager=apt
    installType=true
    removeType=true
    selectCustomInstallType=",7,"
    case "${failure}" in
    update)
        upgrade=false
        updateReleaseInfoChange=true
        expectedError="系统软件源刷新失败"
        ;;
    release-info)
        upgrade=true
        updateReleaseInfoChange=false
        expectedError="系统软件源 release 信息刷新失败"
        printf 'Repository changed its value\n' >"${PADM_INSTALL_LOG}"
        ;;
    esac
    protocolSelectionSkipsNginx() { return 0; }
    protocolSelectionNeedsLocalCertificate() { return 0; }
    waitAptProcess() { return 0; }
    installBasePackages() { : >"${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}"; }
    runPackageCommandWithProgress() {
        [[ "${failure}" == "release-info" ]] && { printf 'changed\n' >"$4"; return; }
        [[ "$1" != "检查、安装更新" ]]
    }
    runWithTimeout() {
        [[ "${failure}" != "release-info" || "$1" != "300" ]]
    }

    set +e
    (installTools 1) >/dev/null 2>&1
    installStatus=$?
    set -e
    [[ "${installStatus}" -ne 0 ]]
    [[ ! -e "${PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE}" ]]
    grep -q "${expectedError}" "${errorLog}"
)

runInstallToolsUsesConfiguredInstallLogRegression() {
    (
        local fakeHome="${TMP_DIR}/install-tools-log-home"
        local logRoot="${TMP_DIR}/custom-log"
        local callLog="${TMP_DIR}/install-tools-log-calls.log"
        local statusLog="${TMP_DIR}/install-tools-log-status.log"
        local errorLog="${TMP_DIR}/install-tools-log-error.log"
        local installStatus
        local resolvedInstallLog

        rm -rf "${fakeHome}" "${logRoot}"
        mkdir -p "${fakeHome}"
        : >"${callLog}"
        : >"${statusLog}"
        : >"${errorLog}"
        HOME="${fakeHome}"
        PADM_INSTALL_LOG="${logRoot}/install.log"
        resolvedInstallLog=$(padmResolveManagedAbsolutePath "${PADM_INSTALL_LOG}")
        export REGRESSION_STATUS_CARD_LOG="${statusLog}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_REGRESSION_BASE_PACKAGE_CALLED_FILE=
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",7,"
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        runWithTimeout() { return 0; }
        waitAptProcess() { return 0; }
        packageInstalled() { return 1; }
        installBasePackages() { installPackageTracked "基础工具" curl; }
        installNginxTools() { return 0; }
        nginx() { return 0; }
        protocolSelectionSkipsNginx() { return 0; }
        protocolSelectionNeedsLocalCertificate() { return 1; }
        runPackageCommandWithProgress() {
            printf '%s|%s\n' "$1" "$4" >>"${callLog}"
            return 0
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        installStatus=$?
        set -e
        [[ "${installStatus}" == "0" ]]
        [[ -f "${resolvedInstallLog}" ]]
        [[ "$(grep -cF "|${resolvedInstallLog}" "${callLog}")" == "2" ]]
        grep -q "^检查、安装更新|${resolvedInstallLog}\$" "${callLog}"
        grep -q "^安装基础工具|${resolvedInstallLog}\$" "${callLog}"
    )
}

runInstallToolsNginxReinstallFailureRegression() {
    (
        local errorLog="${TMP_DIR}/install-tools-nginx-reinstall-error.log"
        local fakeHome="${TMP_DIR}/install-tools-nginx-reinstall-home"

        mkdir -p "${fakeHome}/.acme.sh"
        printf '#!/usr/bin/env sh\n' >"${fakeHome}/.acme.sh/acme.sh"
        HOME="${fakeHome}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        PADM_INSTALL_LOG="${TMP_DIR}/install-tools-nginx-reinstall-install.log"
        : >"${errorLog}"
        release=debian
        rhelLike=false
        upgrade=true
        updateReleaseInfoChange=true
        packageManager=apt
        installType=true
        removeType=true
        selectCustomInstallType=",1,"
        unInstallNginxStatus=y
        protocolSelectionSkipsNginx() { return 1; }
        protocolSelectionNeedsLocalCertificate() { return 0; }
        runWithTimeout() { return 0; }
        runPackageCommandWithProgress() { return 0; }
        waitAptProcess() { return 0; }
        installBasePackages() { return 0; }
        command() {
            if [[ "$1" == "-v" && "$2" == "qrencode" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        nginx() {
            [[ "${1:-}" == "-v" ]] && { printf 'nginx version: nginx/1.12.0\n' >&2; return 0; }
            return 0
        }
        autoRead() {
            printf -v "$3" 'y'
        }
        installNginxTools() {
            return 42
        }

        set +e
        (
            installTools 1
        ) >/dev/null 2>&1
        local installStatus=$?
        set -e
        [[ "${installStatus}" -ne 0 ]]
        grep -q "Nginx重装失败" "${errorLog}"
    )
}

runAptKeyInstallFailureRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/apt-key-error.log"
        local curlCalls="${TMP_DIR}/apt-key-curl-calls.log"
        local keyRootRel="${TMP_DIR}/apt-key-commit-failure"
        local keyRoot keyringFile
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        : >"${curlCalls}"
        release=debian
        removeType=true
        PADM_INSTALLED_PACKAGES="new-dependency"
        curl() {
            printf '%s\n' "$*" >>"${curlCalls}"
            return 22
        }
        gpg() {
            [[ "${1:-}" == "--dearmor" ]] || return 1
            cat
        }
        sudo() {
            "$@"
        }

        set +e
        (
            installAptKeyringFromUrl https://example.invalid/key.gpg "${TMP_DIR}/missing-keyring.gpg" "测试源"
        ) >/dev/null 2>&1
        local keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        grep -q "测试源 apt key 下载失败" "${errorLog}"
        grep -q "https://example.invalid/key.gpg" "${curlCalls}"
        grep -q -- '--connect-timeout 10 --max-time 120 --max-filesize 1048576' "${curlCalls}"
        ! compgen -G "${TMP_DIR}/.missing-keyring.gpg.aptkey.*" >/dev/null

        mkdir -p "${keyRootRel}"
        keyRoot=$(cd -- "${keyRootRel}" && pwd -P)
        keyringFile="${keyRoot}/existing-keyring.gpg"
        printf 'old-keyring\n' >"${keyringFile}"
        : >"${errorLog}"
        curl() {
            local outputFile=
            while [[ $# -gt 0 ]]; do
                if [[ "$1" == "-o" ]]; then
                    outputFile=$2
                    break
                fi
                shift
            done
            [[ -n "${outputFile}" ]] || return 1
            printf 'new-keyring\n' >"${outputFile}"
        }
        sha256sum() {
            printf '%064d  %s\n' 0 "$1"
        }

        set +e
        (
            installAptKeyringFromUrl https://nginx.org/keys/nginx_signing.key "${keyringFile}" Nginx "${PADM_NGINX_SIGNING_KEY_SHA256}"
        ) >/dev/null 2>&1
        keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-keyring" ]]
        grep -q "Nginx apt key sha256 校验失败" "${errorLog}"
        ! compgen -G "${keyRoot}/.existing-keyring.gpg.aptkey.*" >/dev/null

        : >"${errorLog}"
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${keyringFile}" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }

        set +e
        (
            installAptKeyringFromUrl https://example.invalid/key.gpg "${keyringFile}" "测试源"
        ) >/dev/null 2>&1
        keyStatus=$?
        set -e
        [[ "${keyStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-keyring" ]]
        grep -q "测试源 apt key 提交失败" "${errorLog}"
        ! compgen -G "${keyRoot}/.existing-keyring.gpg.aptkey.*" >/dev/null

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f curl gpg sudo sha256sum commitGeneratedFile
    )
}

runNginxAptRepoRefreshRollbackRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-apt-refresh-error.log"
        local rootRel="${TMP_DIR}/nginx-apt-refresh-rollback"
        local root repoRoot keyringRoot curlCalls
        local keyringFile repoFile pinFile
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        curlCalls="${TMP_DIR}/nginx-apt-refresh-curl-calls.log"
        : >"${curlCalls}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        repoRoot="${root}/apt"
        keyringRoot="${root}/keyrings"
        keyringFile="${keyringRoot}/nginx-archive-keyring.gpg"
        repoFile="${repoRoot}/sources.list.d/nginx.list"
        pinFile="${repoRoot}/preferences.d/99nginx"
        mkdir -p "$(dirname "${repoFile}")" "$(dirname "${pinFile}")" "${keyringRoot}"
        printf 'old-key\n' >"${keyringFile}"
        printf 'old-repo\n' >"${repoFile}"
        printf 'old-pin\n' >"${pinFile}"
        release=debian
        packageManager=apt
        removeType=true
        PADM_NGINX_APT_KEYRING_FILE="${keyringFile}"
        PADM_NGINX_APT_REPO_FILE="${repoFile}"
        PADM_NGINX_APT_PIN_FILE="${pinFile}"
        installPackageTracked() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 0; }
        lsb_release() { [[ "$1" == "-cs" ]] && printf 'bookworm\n'; }
        curl() {
            local url=${!#}
            local outputFile=
            printf '%s\n' "$*" >>"${curlCalls}"
            case "${url}" in
            https://nginx.org/packages/mainline/debian/dists/bookworm/Release)
                return 0
                ;;
            https://nginx.org/keys/nginx_signing.key)
                while [[ $# -gt 0 ]]; do
                    if [[ "$1" == "-o" ]]; then
                        outputFile=$2
                        break
                    fi
                    shift
                done
                [[ -n "${outputFile}" ]] || return 1
                printf 'new-key\n' >"${outputFile}"
                return 0
                ;;
            *)
                return 1
                ;;
            esac
        }
        gpg() {
            [[ "${1:-}" == "--dearmor" ]] || return 1
            cat
        }
        sha256sum() { printf '%s  %s\n' "${PADM_NGINX_SIGNING_KEY_SHA256}" "$1"; }
        refreshAptAfterRepoChange() { return 1; }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        [[ "$(<"${keyringFile}")" == "old-key" ]]
        [[ "$(<"${repoFile}")" == "old-repo" ]]
        [[ "$(<"${pinFile}")" == "old-pin" ]]
        grep -q "Nginx apt 源刷新失败" "${errorLog}"
        grep -q -- '--connect-timeout 10 --max-time 30 --max-filesize 1048576 https://nginx.org/packages/mainline/debian/dists/bookworm/Release' "${curlCalls}"
        ! compgen -G "${keyringRoot}/.nginx-archive-keyring.gpg.aptkey.*" >/dev/null
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset PADM_NGINX_APT_KEYRING_FILE PADM_NGINX_APT_REPO_FILE PADM_NGINX_APT_PIN_FILE
        unset -f installPackageTracked nginxServiceInstalled bootStartup lsb_release curl gpg sha256sum refreshAptAfterRepoChange
    )
}

runNginxYumMainlineEnableFailureRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-yum-mainline-error.log"
        local rootRel="${TMP_DIR}/nginx-yum-mainline-rollback"
        local root repoDir rpmKeyFile
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        repoDir="${root}/repos"
        rpmKeyFile="${root}/rpm-gpg/RPM-GPG-KEY-nginx"
        mkdir -p "${repoDir}"
        mkdir -p "$(dirname "${rpmKeyFile}")"
        printf 'old-yum-repo\n' >"${repoDir}/nginx.repo"
        printf 'old-rpm-key\n' >"${rpmKeyFile}"
        release=centos
        packageManager=yum
        removeType=true
        PADM_YUM_REPOS_DIR="${repoDir}"
        PADM_NGINX_RPM_KEY_FILE="${rpmKeyFile}"
        installPackageTracked() { return 0; }
        packageInstalled() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 0; }
        downloadUrlToFileBounded() { printf 'new-rpm-key\n' >"$2"; }
        sha256sum() { printf '%s  %s\n' "${PADM_NGINX_SIGNING_KEY_SHA256}" "$1"; }
        sudo() {
            [[ "$1" == "yum-config-manager" && "$2" == "--enable" && "$3" == "nginx-mainline" ]] && return 1
            "$@"
        }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        grep -q "Nginx yum mainline 源启用失败" "${errorLog}"
        [[ "$(<"${repoDir}/nginx.repo")" == "old-yum-repo" ]]
        [[ "$(<"${rpmKeyFile}")" == "old-rpm-key" ]]
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f installPackageTracked packageInstalled nginxServiceInstalled bootStartup downloadUrlToFileBounded sha256sum sudo
        unset PADM_YUM_REPOS_DIR PADM_NGINX_RPM_KEY_FILE
    )
}

runNginxAlpineDefaultConfRollbackRegression() {
    (
        local oldErrorLog="${REGRESSION_ERROR_CARD_LOG:-}"
        local errorLog="${TMP_DIR}/nginx-alpine-default-conf-error.log"
        local rootRel="${TMP_DIR}/nginx-alpine-default-conf-rollback"
        local root defaultConf
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        : >"${errorLog}"
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        defaultConf="${root}/nginx/default.conf"
        mkdir -p "$(dirname "${defaultConf}")"
        printf 'old-default-conf\n' >"${defaultConf}"
        release=alpine
        packageManager=apk
        removeType=true
        nginxConfigFilePath() {
            [[ "$1" == "default.conf" ]] && printf '%s\n' "${defaultConf}"
        }
        installPackageTracked() { return 0; }
        nginxServiceInstalled() { return 0; }
        bootStartup() { return 1; }

        set +e
        (
            installNginxTools
        ) >/dev/null 2>&1
        local nginxStatus=$?
        set -e
        [[ "${nginxStatus}" -ne 0 ]]
        [[ "$(<"${defaultConf}")" == "old-default-conf" ]]
        grep -q "Nginx开机自启配置失败" "${errorLog}"
        if regressionFindHasMatches "${root}" -type d -name 'padm-package-managed-backup.*'; then
            return 1
        fi

        if [[ -n "${oldErrorLog}" ]]; then
            REGRESSION_ERROR_CARD_LOG="${oldErrorLog}"
        else
            unset REGRESSION_ERROR_CARD_LOG
        fi
        unset -f nginxConfigFilePath installPackageTracked nginxServiceInstalled bootStartup
    )
}

runBasePackageBatchRegression() {
    local commands=(sudo wget curl unzip socat tar crontab jq ld openssl ping6 ping lsb_release lsof dig iptables-save nginx)
    local cmd
    local oldTotal="${PADM_INSTALL_STEP_TOTAL:-}"
    local oldIndex="${PADM_INSTALL_STEP_INDEX:-}"
    local oldTitle="${PADM_INSTALL_PROGRESS_TITLE:-}"

    command() {
        if [[ "$1" == "-v" ]]; then
            for cmd in "${commands[@]}"; do
                [[ "$2" == "${cmd}" ]] && return 1
            done
        fi
        builtin command "$@"
    }
    (
        local capturedTimeout=
        grep() {
            case "$*" in
            *centos*) return 1 ;;
            *debian*) return 0 ;;
            *) return 1 ;;
            esac
        }
        initVar
        checkSystem
        [[ "${installType}" == *"--no-install-recommends"* ]]
        PADM_INSTALL_LOG="${TMP_DIR}/base-package-install.log"
        packageInstalled() { return 1; }
        runPackageCommandWithProgress() {
            capturedTimeout=$2
            return 0
        }
        installPackageTracked "测试" padm-missing-package
        [[ "${capturedTimeout}" == "900" ]]
    )
    initVar
    packageManager=yum
    release=centos
    centosVersion=10
    selectCustomInstallType=",1,"
    rhelLike=true
    protocolSelectionSkipsNginx() { return 1; }
    local capturedDisplay=
    local capturedPackages=
    installPackageTracked() {
        capturedDisplay=$1
        shift
        capturedPackages="$*"
    }

    initInstallProgress
    [[ "${PADM_INSTALL_STEP_TOTAL}" == "3" ]]
    installBasePackages
    [[ "${capturedDisplay}" == "基础工具" ]]
    [[ "${capturedPackages}" == *"sudo"* ]]
    [[ "${capturedPackages}" == *"bind-utils"* ]]
    [[ "${capturedPackages}" == *"iptables"* ]]
    [[ "${capturedPackages}" != *"iptables-legacy"* ]]
    [[ "${capturedPackages}" == *"iputils"* ]]
    PADM_INSTALL_STEP_TOTAL=1
    PADM_INSTALL_STEP_INDEX=2
    nextInstallProgressTitle "安装nginx"
    [[ "${PADM_INSTALL_PROGRESS_TITLE}" == "工具依赖 3/3：安装nginx" ]]
    PADM_INSTALL_STEP_TOTAL="${oldTotal}"
    PADM_INSTALL_STEP_INDEX="${oldIndex}"
    PADM_INSTALL_PROGRESS_TITLE="${oldTitle}"
}

runPackageRollbackFailureRegression() {
    (
        local removedFile="${TMP_DIR}/package-rollback-removed.log"
        local errorLog="${TMP_DIR}/package-rollback-error.log"
        local helperLog="${TMP_DIR}/package-rollback-helper.log"
        local oldInstalled="${PADM_INSTALLED_PACKAGES:-}"
        local oldFailures="${PADM_PACKAGE_ROLLBACK_FAILURES:-}"
        local oldManagedFailures="${PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES:-}"
        local oldRemoveType="${removeType:-}"
        local rc

        runWithTimeout() {
            printf '%s\n' "$2" >>"${removedFile}"
            [[ "$2" != *"bad-package" ]]
        }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }

        removeType='DEBIAN_FRONTEND=noninteractive apt-get -y autoremove'
        PADM_INSTALLED_PACKAGES="ok-package bad-package"
        : >"${errorLog}"
        : >"${helperLog}"
        if rollbackPackageInstallTransaction; then
            return 1
        fi
        grep -qxF "${removeType} ok-package" "${removedFile}"
        grep -qxF "${removeType} bad-package" "${removedFile}"
        [[ "${PADM_INSTALLED_PACKAGES}" == "" ]]
        [[ "${PADM_PACKAGE_ROLLBACK_FAILURES}" == "bad-package" ]]

        PADM_INSTALLED_PACKAGES="ok-package bad-package"
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=()
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "软件包安装失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:回滚部分软件包失败|bad-package' "${helperLog}"
        grep -q '回滚部分软件包失败，请手动检查bad-package' "${errorLog}"

        adapterRollbackPackageManagedFiles() { return 0; }
        rollbackPackageInstallTransaction() {
            PADM_PACKAGE_ROLLBACK_FAILURES='bad-package'
            return 1
        }
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=('/tmp/repo-backup')
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "软件包安装失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:已尝试回滚系统源改动，但部分软件包回滚失败|bad-package' "${helperLog}"
        grep -q '已尝试回滚系统源改动，但部分软件包回滚失败，请手动检查bad-package' "${errorLog}"

        adapterRollbackPackageManagedFiles() { return 1; }
        rollbackPackageInstallTransaction() { return 0; }
        PADM_PACKAGE_MANAGED_ROLLBACK_DIRS=('/tmp/repo-backup')
        PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES='repo-backup-a repo-backup-b'
        : >"${errorLog}"
        : >"${helperLog}"
        set +e
        (
            failPackageInstallTransaction "系统软件源刷新失败" >/dev/null 2>&1
        )
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        grep -q 'manual-check:已回滚本次新增软件包，但系统源改动恢复失败|repo-backup-a repo-backup-b' "${helperLog}"
        grep -q '已回滚本次新增软件包，但系统源改动恢复失败，请手动检查repo-backup-a repo-backup-b' "${errorLog}"

        if [[ -n "${oldInstalled}" ]]; then
            PADM_INSTALLED_PACKAGES="${oldInstalled}"
        else
            unset PADM_INSTALLED_PACKAGES
        fi
        if [[ -n "${oldFailures}" ]]; then
            PADM_PACKAGE_ROLLBACK_FAILURES="${oldFailures}"
        else
            unset PADM_PACKAGE_ROLLBACK_FAILURES
        fi
        if [[ -n "${oldManagedFailures}" ]]; then
            PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES="${oldManagedFailures}"
        else
            unset PADM_PACKAGE_MANAGED_ROLLBACK_FAILURES
        fi
        removeType="${oldRemoveType}"
        unset -f runWithTimeout
        unset -f adapterRollbackPackageManagedFiles
        unset -f errorCard
        unset -f coreSetManualCheckMessage
    )
}

runPackageCommandStdinRegression() {
    local oldPath="${PATH}"
    local fakeBin="${TMP_DIR}/stdin-fake-bin"
    local fdTargetFile="${TMP_DIR}/stdin-fd-target"
    local sessionFile="${TMP_DIR}/stdin-session"
    local parentSession

    parentSession=$(cut -d ' ' -f 6 "/proc/$$/stat")
    mkdir -p "${fakeBin}"
    cat >"${fakeBin}/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
    chmod +x "${fakeBin}/timeout"
    PATH="${fakeBin}:${PATH}"
    source "${PROJECT_ROOT}/shell/core/adapters.sh"
    PADM_INSTALL_STEP_INDEX=0
    PADM_INSTALL_STEP_TOTAL=1
    runPackageCommandWithProgress "stdin-check" 10 "readlink /proc/\$\$/fd/0 >\"${fdTargetFile}\"; cut -d ' ' -f 6 /proc/\$\$/stat >\"${sessionFile}\"" "${TMP_DIR}/stdin-install.log"
    [[ "$(<"${fdTargetFile}")" == "/dev/null" ]]
    [[ "$(tr -d ' ' <"${sessionFile}")" =~ ^[0-9]+$ ]]
    [[ "$(tr -d ' ' <"${sessionFile}")" != "${parentSession}" ]]
    PATH="${oldPath}"
}

runRealityScannerBinaryRegression() {
    local scannerDirRel="${TMP_DIR}/scanner-bin"
    local scannerDir=
    local scannerRoot=
    local scannerBin=
    local scannerOutputFile="${TMP_DIR}/scanner-output.csv"
    local scannerOutput=
    local capturedRepo= capturedVersion= capturedAsset= capturedDir=

    mkdir -p "${scannerDirRel}"
    scannerDir="$(cd -- "${scannerDirRel}" && pwd -P)"
    scannerRoot=${scannerDir}
    scannerBin="${scannerDir}/RealiTLScanner"

    rm() {
        if [[ "$#" -eq 2 && "$1" == "-rf" && "$2" == "${scannerDir}" ]]; then
            return 0
        fi
        command rm "$@"
    }
    mkdir() {
        if [[ "$#" -eq 2 && "$1" == "-p" && "$2" == "${scannerDir}" ]]; then
            return 0
        fi
        command mkdir "$@"
    }
    downloadGitHubReleaseAsset() {
        capturedDir=$2
        capturedRepo=$3
        capturedVersion=$4
        capturedAsset=$5
        cat >"${capturedDir}/${capturedAsset}" <<'SH'
#!/usr/bin/env bash
printf 'scanner-row-stdout\n'
printf 'scanner-row-stderr\n' >&2
SH
        return 0
    }
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}"
    [[ -x "${scannerBin}" ]]
    [[ "${capturedRepo}" == "XTLS/RealiTLScanner" ]]
    [[ "${capturedVersion}" == "latest" ]]
    [[ "${capturedAsset}" == "RealiTLScanner-linux-amd64" ]]
    unset -f rm mkdir downloadGitHubReleaseAsset

    realityTargetTmpPath() { printf '%s\n' "${scannerRoot}"; }
    realityScannerOutputPath() { printf '%s\n' "${scannerOutputFile}"; }
    realityTargetProgressLine() { printf 'progress:%s\n' "$1"; }
    realityTargetStatusBlock() { return 0; }
    importRealityScannerResults() { return 0; }
    sleep() { command sleep 0.01; }
    scannerOutput=$(runRealityScannerRange "198.51.100.0/28" 2>&1)
    grep -q '^progress:RealiTLScanner 扫描范围' <<<"${scannerOutput}"
    ! grep -q 'scanner-row-' <<<"${scannerOutput}"
    grep -qx 'scanner-row-stdout' "${scannerOutputFile}.log"
    grep -qx 'scanner-row-stderr' "${scannerOutputFile}.log"
}

runRealityScannerDownloadFailureKeepsExistingDirRegression() {
    local root="${TMP_DIR}/scanner-download-failure"
    local scannerDir="${root}/scanner"
    local scannerBin="${scannerDir}/RealiTLScanner"
    local rmLog="${root}/rm.log"
    local rc

    padmIsSafeAbsolutePath() { return 0; }
    mkdir -p "${scannerDir}"
    printf 'keep\n' >"${scannerDir}/sentinel"
    : >"${rmLog}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    downloadGitHubReleaseAsset() { return 1; }
    set +e
    ensureRealityScannerBinary "${scannerDir}" "${scannerBin}" >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ "$(<"${scannerDir}/sentinel")" == "keep" ]]
    ! grep -qxF "rm:-rf ${scannerDir}" "${rmLog}"
    unset -f rm downloadGitHubReleaseAsset
}

runRealityScannerRejectsUnsafeDirRegression() (
    local rootRel="${TMP_DIR}/scanner-unsafe-dir"
    local root rmLog
    local rc

    mkdir -p "${rootRel}/relative-scanner"
    root=$(cd -- "${rootRel}" && pwd -P)
    rmLog="${root}/rm.log"
    printf 'keep\n' >"${root}/relative-scanner/sentinel"
    : >"${rmLog}"

    cd "${root}"
    realityTargetTmpPath() { printf '%s\n' "relative-scanner"; }
    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        command rm "$@"
    }
    curl() { return 1; }
    jq() { return 1; }

    set +e
    runRealityScannerRange "198.51.100.0/24" >/dev/null 2>&1
    rc=$?
    set -e

    [[ "${rc}" == "1" ]]
    [[ ! -s "${rmLog}" ]]
    [[ -d "${root}/relative-scanner" ]]
    [[ "$(<"${root}/relative-scanner/sentinel")" == "keep" ]]
)
