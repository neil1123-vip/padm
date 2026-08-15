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
