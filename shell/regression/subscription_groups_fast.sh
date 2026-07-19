#!/usr/bin/env bash
set -euo pipefail

REGRESSION_ENTRY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=/dev/null
source "${REGRESSION_ENTRY_DIR}/regression/bootstrap.sh"

regressionModuleManifestReady() {
    [[ "${PADM_FAKE_MODULE_MANIFEST_READY:-0}" == "1" ]]
}

regressionScriptModulesReady() {
    local expectedRef localRef
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]] || return 1
    regressionModuleManifestReady || return 1
    [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]] || return 0
    [[ -f "${SCRIPT_REF_FILE}" ]] || return 1
    expectedRef=$(<"${SCRIPT_EXPECTED_REF_FILE}")
    localRef=$(<"${SCRIPT_REF_FILE}")
    regressionScriptRefIsValid "${expectedRef}" || return 1
    regressionScriptRefIsValid "${localRef}" || return 1
    [[ "${expectedRef}" == "${localRef}" ]]
}

regressionScriptModuleFilesPresent() {
    [[ -f "${SCRIPT_DIR}/shell/core/bootstrap.sh" ]]
}

regressionScriptRefIsValid() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

regressionEnsureScriptModules() {
    local remoteRef= expectedRef=
    if [[ "${PADM_FORCE_SCRIPT_MODULE_REFRESH:-}" == "1" ]]; then
        remoteRef="${PADM_SCRIPT_MODULE_REF:-}"
        [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef) || return 1
        regressionScriptRefIsValid "${remoteRef}" || return 1
        refreshScriptModules "${remoteRef}" || return 1
        return 0
    fi
    if regressionScriptModulesReady; then
        return 0
    fi
    if [[ -f "${SCRIPT_EXPECTED_REF_FILE}" ]]; then
        expectedRef=$(<"${SCRIPT_EXPECTED_REF_FILE}")
    fi
    if [[ "${PADM_SKIP_REMOTE_REF_CHECK:-}" == "1" ]]; then
        return 1
    fi

    remoteRef="${expectedRef}"
    [[ -n "${remoteRef}" ]] || remoteRef=$(fetchRemoteRef) || return 1
    regressionScriptRefIsValid "${remoteRef}" || return 1
    refreshScriptModules "${remoteRef}" || return 1
}

runRegressionBootstrapLocalEnvFallbackRegression() {
    local root="${TMP_DIR}/bootstrap-local-env-fallback"
    local outputFile="${root}/output"
    local missingTmp="${root}/missing-tmp"
    local missingHome="${root}/missing-home"

    mkdir -p "${root}"
    TMPDIR="${missingTmp}" HOME="${missingHome}" bash -c '
        set -euo pipefail
        source "$1"
        printf "TMPDIR=%s\n" "${TMPDIR}" >"$2"
        printf "HOME=%s\n" "${HOME}" >>"$2"
        [[ -d "${TMPDIR}" && -w "${TMPDIR}" ]]
        [[ -d "${HOME}" && -w "${HOME}" ]]
    ' _ "${PROJECT_ROOT}/shell/regression/bootstrap.sh" "${outputFile}"

    grep -q "^TMPDIR=${PROJECT_ROOT}/.tmp-msys/tmp$" "${outputFile}"
    grep -q "^HOME=${PROJECT_ROOT}/.tmp-msys/home$" "${outputFile}"
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

    (
        local retainedPath="${tmpDir}/retained"
        printf 'keep\n' >"${retainedPath}"
        PADM_CLEANUP_PATHS=()
        padmRegisterCleanupPath "${retainedPath}"
        rm() { return 1; }
        padmRemoveCleanupPath "${retainedPath}"
        [[ -e "${retainedPath}" ]]
        [[ "${PADM_CLEANUP_PATHS[*]}" == *"${retainedPath}"* ]]
        unset -f rm
        padmRemoveCleanupPath "${retainedPath}"
        [[ ! -e "${retainedPath}" ]]
        [[ -z "${PADM_CLEANUP_PATHS[*]}" ]]
    )
    rm -rf "${tmpDir}"
}

runCleanupTrapRelativePathRegression() {
    local rootRel="${TMP_DIR}/cleanup-trap-relative"
    local root
    local keepDir
    local trapScript
    local createdPath
    local rc

    mkdir -p "${rootRel}/base" "${rootRel}/other"
    root=$(cd -- "${rootRel}" && pwd -P)
    keepDir="${root}/other"
    trapScript="${root}/run.sh"
    printf 'keep\n' >"${keepDir}/sentinel"

    cat >"${trapScript}" <<'SH'
#!/usr/bin/env bash
set -e
source "$1"
mkdir -p base
cd base
padmCreateTempPath p ./relative-cleanup.XXXXXX
printf '%s\n' "$(cd -- "$(dirname -- "$p")" && pwd -P)/$(basename -- "$p")" >created.path
cd ../other
exit 0
SH
    chmod +x "${trapScript}"

    set +e
    (
        cd -- "${root}" &&
            "${trapScript}" "${PROJECT_ROOT}/shell/core/runtime.sh"
    ) >/dev/null 2>&1
    rc=$?
    set -e
    createdPath=$(<"${root}/base/created.path")
    [[ "${rc}" == "0" ]]
    [[ -f "${keepDir}/sentinel" ]]
    [[ "${createdPath}" == "${root}/base/relative-cleanup."* ]]
    [[ ! -e "${createdPath}" ]]
}

runCommitGeneratedFileRejectsDirectoryTargetRegression() (
    local root="${TMP_DIR}/commit-generated-file-directory-target"
    local targetPath="${root}/target.conf"
    local tmpFile
    local status

    mkdir -p "${targetPath}"
    padmCreateTempPath tmpFile "${root}/.target.write.XXXXXX"
    printf 'new\n' >"${tmpFile}"

    set +e
    commitGeneratedFile "${tmpFile}" "${targetPath}" 644
    status=$?
    set -e

    [[ "${status}" -ne 0 ]]
    [[ -f "${tmpFile}" ]]
    [[ -d "${targetPath}" ]]
    [[ ! -e "${targetPath}/$(basename -- "${tmpFile}")" ]]
    padmRemoveCleanupPath "${tmpFile}"
)

runGitHubReleaseAssetDirectFallbackRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local root="${TMP_DIR}/github-release-direct-fallback"
        local outputDir="${root}/out"
        local downloadLog="${root}/download.calls"
        local expectedAssetSha256
        local expectedAssetSize
        mkdir -p "${outputDir}"
        expectedAssetSha256=$(printf 'asset-content\n' | sha256sum | awk '{print $1}')
        expectedAssetSize=$(printf 'asset-content\n' | wc -c | tr -d ' ')
        [[ "$(githubReleaseAssetPinnedDigest badafans/warp-reg v1.0 main-linux-amd64)" == 'sha256:95e97d92bda8f343e0ba0b7a7402c5947fb4204fdb0d368fd53dbddb664de895' ]]
        [[ "$(githubReleaseAssetPinnedDigest badafans/warp-reg v1.0 main-linux-arm64)" == 'sha256:eb7a29853466f805755caddcebeedfbfb36cccd73a4eb950a1eb82915fa17f9b' ]]
        ! githubReleaseAssetPinnedDigest example/repo v1.2.4 asset.tar.gz
        fetchUrlToStdout() {
            case "$1" in
            */v1.2.3)
                return 1
                ;;
            */v1.2.4)
                printf '{"assets":[{"name":"asset.tar.gz","browser_download_url":"https://github.com/example/repo/releases/download/v1.2.4/asset.tar.gz","size":%s}]}\n' "${expectedAssetSize}"
                ;;
            */v1.2.5)
                printf '{"assets":[{"name":"asset.tar.gz","browser_download_url":"https://github.com/example/repo/releases/download/v1.2.5/asset.tar.gz","size":%s,"digest":"sha256:%s"}]}\n' "${expectedAssetSize}" "${expectedAssetSha256}"
                ;;
            */v1.2.6)
                printf '{"assets":[{"name":"asset.tar.gz","browser_download_url":"https://github.com/example/repo/releases/download/v1.2.6/asset.tar.gz","size":%s,"digest":"sha256:%s"}]}\n' "${expectedAssetSize}" "${expectedAssetSha256}"
                ;;
            */releases/latest)
                printf '{"assets":[{"name":"asset.tar.gz","browser_download_url":"https://github.com/example/repo/releases/download/v2.0.0/asset.tar.gz","size":%s,"digest":"sha256:%s"}]}\n' "${expectedAssetSize}" "${expectedAssetSha256}"
                ;;
            */tags/latest)
                return 1
                ;;
            *)
                return 1
                ;;
            esac
        }
        downloadFile() {
            printf '%s\n' "${3:-}" >>"${downloadLog}"
            mkdir -p "${2}"
            printf 'asset-content\n' >"${2%/}/asset.tar.gz"
            return 0
        }
        if downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.3 asset.tar.gz; then
            return 1
        fi
        [[ ! -e "${downloadLog}" ]] || return 1
        if downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.4 asset.tar.gz; then
            return 1
        fi
        [[ ! -e "${downloadLog}" ]] || return 1
        githubReleaseAssetPinnedDigest() {
            [[ "$1:$2:$3" == 'example/repo:v1.2.4:asset.tar.gz' ]] || return 1
            printf 'sha256:%s\n' "${expectedAssetSha256}"
        }
        downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.4 asset.tar.gz || return 1
        unset -f githubReleaseAssetPinnedDigest
        downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.5 asset.tar.gz || return 1
        [[ "$(<"${outputDir}/asset.tar.gz")" == "asset-content" ]] || return 1
        grep -qxF 'https://github.com/example/repo/releases/download/v1.2.5/asset.tar.gz' "${downloadLog}" || return 1
        command() {
            if [[ "${1:-}" == "-v" && "${2:-}" == "sha256sum" ]]; then
                return 1
            fi
            builtin command "$@"
        }
        if downloadGitHubReleaseAsset -P "${outputDir}" example/repo v1.2.6 asset.tar.gz; then
            return 1
        fi
        [[ ! -e "${outputDir}/asset.tar.gz" ]] || return 1
        unset -f command
        downloadGitHubReleaseAsset -P "${outputDir}" example/repo latest asset.tar.gz || return 1
        grep -qxF 'https://github.com/example/repo/releases/download/v2.0.0/asset.tar.gz' "${downloadLog}" || return 1
    )
}

runDownloadArgumentMissingValueRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local root="${TMP_DIR}/download-arg-missing-value"
        local calls="${root}/wget.calls"
        mkdir -p "${root}"
        cd "${root}"
        curl() { return 1; }
        wget() {
            printf '%s\n' "$*" >>"${calls}"
            printf 'payload\n'
        }
        downloadFile -O https://example.invalid/file.tar.gz
        grep -qx -- '-T 30 -t 2 -qO- https://example.invalid/file.tar.gz' "${calls}"
        [[ "$(<"${root}/file.tar.gz")" == "payload" ]]
    )
}

runFetchUrlWgetHardLimitRegression() (
    set -euo pipefail
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/core/runtime.sh"
    local outputFile="${TMP_DIR}/fetch-url-wget-hard-limit.out"
    curl() { return 63; }
    wget() { head -c 6291456 /dev/zero; }

    if fetchUrlToStdout https://example.invalid/oversized 1 >"${outputFile}"; then
        return 1
    fi
    [[ ! -s "${outputFile}" ]]
)

runGitHubReleaseArgumentMissingValueRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local root="${TMP_DIR}/github-release-arg-missing-value"
        mkdir -p "${root}"
        cd "${root}"
        fetchUrlToStdout() {
            printf '{"assets":[{"name":"asset.tar.gz","browser_download_url":"https://example.invalid/asset.tar.gz"}]}\n'
        }
        downloadFile() {
            printf 'download:%s\n' "$*" >download.calls
            return 0
        }
        ! downloadGitHubReleaseAsset -P --bad-dir example/repo v1.2.3 asset.tar.gz
        [[ ! -e "${root}/--bad-dir" ]]
        [[ ! -e "${root}/download.calls" ]]
    )
}

runCleanDirectoryContentSafetyRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        local rootRel="${TMP_DIR}/clean-directory-safety"
        local root safeDir unsafeDir
        mkdir -p "${rootRel}/safe" "${rootRel}/unsafe"
        root=$(cd -- "${rootRel}" && pwd -P)
        safeDir="${root}/safe"
        unsafeDir="${root}/unsafe"
        printf 'keep\n' >"${unsafeDir}/sentinel"
        printf 'remove\n' >"${safeDir}/child"
        padmIsSafeAbsolutePath() { [[ "$1" == "${safeDir}" ]]; }
        (
            cd "${unsafeDir}"
            ! cleanDirectoryContent "."
            ! cleanDirectoryContent ".."
            ! cleanDirectoryContent "relative"
            [[ -f sentinel ]]
        )
        cleanDirectoryContent "${safeDir}"
        [[ -d "${safeDir}" ]]
        [[ ! -e "${safeDir}/child" ]]
    )
}

runRemoveNginxDefaultConfSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/remove-nginx-default-conf-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        local successLog="${root}/success.log"
        mkdir -p "${unsafeRoot}" "${nginxRoot}"

        writeDefaultNginxConf() {
            printf 'server {\n    listen 80 default_server;\n    server_name  localhost;\n}\n' >"$1"
        }

        writeDefaultNginxConf "${unsafeRoot}/default.conf"
        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! removeNginxDefaultConf
            [[ -f default.conf ]]
        )

        REGRESSION_SUCCESS_CARD_LOG="${successLog}"
        writeDefaultNginxConf "${nginxRoot}/default.conf"
        nginxConfigPath="${nginxRoot}/"
        removeNginxDefaultConf
        [[ ! -e "${nginxRoot}/default.conf" ]]
        grep -qx '删除Nginx默认配置' "${successLog}"
    )
}

runCleanAgentNginxConfSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/clean-agent-nginx-conf-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        local managedFiles=(alone.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf checkPortOpen.conf)
        local file
        mkdir -p "${unsafeRoot}" "${nginxRoot}"
        PADM_REALITY_STREAM_CONF_FILE="${root}/stream.conf"
        PADM_REALITY_STREAM_STATE_FILE="${root}/stream-state.json"
        PADM_REALITY_STREAM_NGINX_CONF="${root}/missing-nginx.conf"

        for file in "${managedFiles[@]}"; do
            printf 'managed\n' >"${unsafeRoot}/${file}"
        done
        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! cleanAgentNginxConf
            for file in "${managedFiles[@]}"; do
                [[ -f "${file}" ]]
            done
        )

        for file in "${managedFiles[@]}"; do
            printf 'managed\n' >"${nginxRoot}/${file}"
        done
        printf 'stream\n' >"${PADM_REALITY_STREAM_CONF_FILE}"
        printf 'state\n' >"${PADM_REALITY_STREAM_STATE_FILE}"
        nginxConfigPath="${nginxRoot}/"
        cleanAgentNginxConf
        for file in "${managedFiles[@]}"; do
            [[ ! -e "${nginxRoot}/${file}" ]]
        done
        [[ ! -e "${PADM_REALITY_STREAM_CONF_FILE}" ]]
        [[ ! -e "${PADM_REALITY_STREAM_STATE_FILE}" ]]
    )
}

runUninstallSubscribeNginxPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/uninstall-subscribe-nginx-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        local firewallLog="${root}/firewall.log"
        mkdir -p "${unsafeRoot}" "${nginxRoot}"

        printf 'subscribe\n' >"${unsafeRoot}/subscribe.conf"
        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! unInstallSubscribe
            [[ -f subscribe.conf ]]
        )

        printf 'server {\n    listen 39778 ssl;\n}\n' >"${nginxRoot}/subscribe.conf"
        nginxConfigPath="${nginxRoot}/"
        denyPort() { printf '%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"; }
        : >"${firewallLog}"
        unInstallSubscribe
        [[ ! -e "${nginxRoot}/subscribe.conf" ]]
        grep -qx '39778:tcp' "${firewallLog}"
        grep -qx '39778:udp' "${firewallLog}"
    )
}

runCheckPortOpenNginxPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/check-port-open-nginx-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        mkdir -p "${unsafeRoot}" "${nginxRoot}"

        nginx() { return 0; }

        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! writeCheckPortOpenNginxConfig 2443 example.com ""
            [[ ! -e checkPortOpen.conf ]]
            [[ ! -e checkPortOpen.conf.tmp ]]
        )

        nginxConfigPath="${nginxRoot}/"
        writeCheckPortOpenNginxConfig 2443 example.com ""
        grep -q 'listen 2443;' "${nginxRoot}/checkPortOpen.conf"
        removeCheckPortOpenNginxConfig
        [[ ! -e "${nginxRoot}/checkPortOpen.conf" ]]
    )
}

runWriteSubscribeNginxPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/write-subscribe-nginx-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        mkdir -p "${unsafeRoot}" "${nginxRoot}"

        nginx() { return 0; }

        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! writeSubscribeNginxConfig <<'EOF'
server {}
EOF
            [[ ! -e subscribe.conf ]]
            [[ ! -e subscribe.conf.tmp ]]
        )

        nginxConfigPath="${nginxRoot}/"
        writeSubscribeNginxConfig <<'EOF'
server {}
EOF
        grep -q 'server {}' "${nginxRoot}/subscribe.conf"
    )
}

runWriteWireGuardControlNginxPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/write-wireguard-control-nginx-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        local subscribeRoot="${root}/public-subscribe"
        mkdir -p "${unsafeRoot}" "${nginxRoot}" "${root}/static" "${subscribeRoot}"

        nginx() { return 0; }
        subscriptionWireGuardReadState() { printf '%s\n' '{"address":"10.77.0.1/24","control_port":39778}'; }
        fail2banPadmControlLogFile() { printf '%s\n' "${TMP_DIR}/wg-control-access.log"; }
        subscriptionControlPort() { printf '%s\n' 39999; }
        nginxStaticPath="${root}/static"
        export PADM_SUBSCRIBE_DIR="${subscribeRoot}"

        (
            cd "${unsafeRoot}"
            nginxConfigPath='relative-nginx/'
            ! ensureSubscriptionWireGuardNginxConfig
            [[ ! -e relative-nginx ]]
            [[ ! -e padm-control-wg.conf ]]
        )

        nginxConfigPath="${nginxRoot}/"
        rm -f "${nginxRoot}/padm-control-wg.conf"
        ensureSubscriptionWireGuardNginxConfig
        grep -q 'listen 10.77.0.1:39778;' "${nginxRoot}/padm-control-wg.conf"
        grep -q 'proxy_connect_timeout 5s;' "${nginxRoot}/padm-control-wg.conf"
        grep -q 'proxy_send_timeout 180s;' "${nginxRoot}/padm-control-wg.conf"
        grep -q 'proxy_read_timeout 195s;' "${nginxRoot}/padm-control-wg.conf"
        grep -q "alias ${subscribeRoot}/\\\$1/\\\$2;" "${nginxRoot}/padm-control-wg.conf"

        subscriptionWireGuardReadState() { printf '%s\n' '{"address":"10.77.0.1/24","control_port":"39778;\nserver{}"}'; }
        ! ensureSubscriptionWireGuardNginxConfig

        local wireGuardRoot="${root}/wireguard"
        mkdir -p "${wireGuardRoot}"
        export PADM_WIREGUARD_CONTROL_DIR="${wireGuardRoot}"
        subscriptionWireGuardConfigFile() { printf '%s\n' "${wireGuardRoot}/wg-padm.conf"; }
        printf 'private-key\n' >"${wireGuardRoot}/private.key"
        subscriptionWireGuardReadState() {
            printf '%s\n' '{"address":"10.77.0.1/24","listen_port":51820,"peers":[{"id":"edge","address":"10.77.0.2/32","public_key":"pub\nkey","enabled":true}]}'
        }
        ! writeSubscriptionWireGuardConfig
        [[ ! -e "${wireGuardRoot}/wg-padm.conf" ]]

        (
            set -euo pipefail
            local rollbackRoot="${root}/rollback-failure"
            local rollbackNginx="${rollbackRoot}/nginx"
            local rollbackPublic="${rollbackRoot}/public"
            local rollbackTarget
            local rollbackBackup
            mkdir -p "${rollbackNginx}" "${rollbackPublic}"
            nginx() { return 1; }
            nginxConfigPath="${rollbackNginx}/"
            export PADM_SUBSCRIBE_DIR="${rollbackPublic}"
            fail2banPadmControlLogFile() { printf '%s/access.log\n' "${rollbackRoot}"; }
            subscriptionWireGuardReadState() { printf '%s\n' '{"address":"10.77.0.1/24","control_port":39778}'; }
            rollbackTarget="${rollbackNginx}/padm-control-wg.conf"
            printf 'old config\n' >"${rollbackTarget}"
            eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
            local commitCount=0
            commitGeneratedFile() {
                commitCount=$((commitCount + 1))
                [[ "${commitCount}" != "3" ]] || return 1
                originalCommitGeneratedFile "$@"
            }
            ! ensureSubscriptionWireGuardNginxConfig
            rollbackBackup=$(find "${rollbackNginx}" -maxdepth 1 -type f -name '.padm-control-wg.conf.backup.*' -print)
            [[ -n "${rollbackBackup}" ]]
            grep -qxF 'old config' "${rollbackBackup}"
            ! grep -qxF 'old config' "${rollbackTarget}"
        )
    )
}

runSubscriptionWireGuardFirewallLifecycleRegression() (
    set -euo pipefail
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

    local root="${TMP_DIR}/wireguard-firewall-lifecycle"
    local actions=
    local allowAdds=true
    local applyFail=true
    local status
    mkdir -p "${root}/wireguard" "${root}/nginx"
    export PADM_WIREGUARD_CONTROL_DIR="${root}/wireguard"
    nginxConfigPath="${root}/nginx/"

    subscriptionWireGuardConfigFile() { printf '%s\n' "${root}/wg-padm.conf"; }
    autoRead() { printf -v "$3" '%s' main.example.com; }
    installSubscriptionWireGuardTools() { return 0; }
    subscriptionWireGuardEnsureKeys() {
        printf 'private-key\n' >"$(subscriptionWireGuardPrivateKeyFile)"
        printf 'public-key\n' >"$(subscriptionWireGuardPublicKeyFile)"
    }
    subscriptionWireGuardPublicKey() { printf '%s\n' 'MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE='; }
    allowPort() {
        actions+="allow:$1:${2:-tcp}"$'\n'
        PADM_LAST_ALLOW_PORT_ADDED=false
        [[ "${allowAdds}" == "true" ]] || return 0
        PADM_LAST_ALLOW_PORT_ADDED=true
        padmTrackPortAllowTransactionKey "port:ufw:${2:-tcp}:$1"
    }
    padmRollbackPortAllowTransaction() {
        actions+="rollback"$'\n'
        PADM_PORT_ALLOW_TRANSACTION_KEYS=
    }
    applySubscriptionWireGuardService() {
        [[ "${applyFail}" != "true" ]] || return 1
        printf 'wireguard\n' >"$(subscriptionWireGuardConfigFile)"
    }
    stopSubscriptionWireGuardControlService() {
        actions+="stop"$'\n'
    }
    refreshSubscriptionWireGuardNginxControl() { actions+="refresh"$'\n'; }
    serviceQueueApply() { actions+="queue-apply"$'\n'; }
    installSubscriptionControlService() { actions+="install-control"$'\n'; }
    nginxRunning() { return 1; }
    denyPort() {
        actions+="deny:$1:${2:-tcp}"$'\n'
    }

    set +e
    initSubscriptionWireGuardMain >/dev/null 2>&1
    status=$?
    set -e
    [[ "${status}" -ne 0 ]]
    grep -qx 'allow:51820:udp' <<<"${actions}"
    grep -qx 'rollback' <<<"${actions}"
    subscriptionWireGuardReadState | jq -e '.enabled == false and .firewall_owned == false' >/dev/null

    actions=
    applyFail=false
    initSubscriptionWireGuardMain >/dev/null
    grep -qx 'allow:51820:udp' <<<"${actions}"
    subscriptionWireGuardReadState | jq -e '.enabled == true and .role == "main" and .firewall_owned == true' >/dev/null

    actions=
    disableSubscriptionWireGuardControl >/dev/null
    grep -qx 'stop' <<<"${actions}"
    grep -qx 'deny:51820:udp' <<<"${actions}"
    subscriptionWireGuardReadState | jq -e '.enabled == false and .firewall_owned == false' >/dev/null

    actions=
    restartSubscriptionWireGuardControl >/dev/null
    grep -qx 'allow:51820:udp' <<<"${actions}"
    subscriptionWireGuardReadState | jq -e '.enabled == true and .role == "main" and .firewall_owned == true' >/dev/null

    disableSubscriptionWireGuardControl >/dev/null
    actions=
    allowAdds=false
    initSubscriptionWireGuardMain >/dev/null
    subscriptionWireGuardReadState | jq -e '.enabled == true and .role == "main" and .firewall_owned == false' >/dev/null

    actions=
    disableSubscriptionWireGuardControl >/dev/null
    ! grep -q '^deny:' <<<"${actions}"
)

runSubscriptionWireGuardNginxDisableLifecycleRegression() (
    set -euo pipefail
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

    local root="${TMP_DIR}/wireguard-nginx-disable-lifecycle"
    local actions=
    local nginxRuntimeState=true
    local queueFail=false
    local status
    local nginxTarget
    mkdir -p "${root}/wireguard" "${root}/nginx"
    export PADM_WIREGUARD_CONTROL_DIR="${root}/wireguard"
    nginxConfigPath="${root}/nginx/"
    nginxTarget="${nginxConfigPath}padm-control-wg.conf"

    subscriptionWireGuardConfigFile() { printf '%s\n' "${root}/wg-padm.conf"; }
    stopSubscriptionWireGuardControlService() { actions+="stop-wireguard"$'\n'; }
    applySubscriptionWireGuardService() {
        actions+="restore-wireguard"$'\n'
        printf 'restored-wireguard\n' >"$(subscriptionWireGuardConfigFile)"
    }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
    serviceQueueRestart() { actions+="queue:$1:restart"$'\n'; }
    serviceQueueApply() {
        actions+="queue-apply"$'\n'
        nginxRuntimeState=false
        [[ "${queueFail}" != "true" ]]
    }
    handleNginx() {
        actions+="nginx:$1"$'\n'
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
    }

    resetWireGuardNginxDisableFixture() {
        actions=
        nginxRuntimeState=true
        subscriptionWireGuardWriteState '.enabled = true | .role = "controlled" | .address = "10.77.0.2/24"' >/dev/null
        printf 'old-wireguard\n' >"$(subscriptionWireGuardConfigFile)"
        printf 'old-nginx\n' >"${nginxTarget}"
    }

    resetWireGuardNginxDisableFixture
    disableSubscriptionWireGuardControl >/dev/null
    subscriptionWireGuardReadState | jq -e '.enabled == false' >/dev/null
    [[ ! -e "${nginxTarget}" ]]
    [[ "${nginxRuntimeState}" == "false" ]]
    grep -qx 'stop-wireguard' <<<"${actions}"
    grep -qx 'queue:nginx:restart' <<<"${actions}"
    grep -qx 'queue-apply' <<<"${actions}"

    resetWireGuardNginxDisableFixture
    queueFail=true
    set +e
    disableSubscriptionWireGuardControl >/dev/null 2>&1
    status=$?
    set -e
    [[ "${status}" -ne 0 ]]
    subscriptionWireGuardReadState | jq -e '.enabled == true and .role == "controlled"' >/dev/null
    grep -qx 'restored-wireguard' "$(subscriptionWireGuardConfigFile)"
    grep -qx 'old-nginx' "${nginxTarget}"
    [[ "${nginxRuntimeState}" == "true" ]]
    grep -qx 'nginx:start' <<<"${actions}"
)

runWriteAloneNginxPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/write-alone-nginx-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        mkdir -p "${unsafeRoot}" "${nginxRoot}"

        nginx() { return 0; }

        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            ! writeAloneNginxConfig <<'EOF'
server {}
EOF
            [[ ! -e alone.conf ]]
            [[ ! -e alone.conf.tmp ]]
        )

        nginxConfigPath="${nginxRoot}/"
        writeAloneNginxConfig <<'EOF'
server {}
EOF
        grep -q 'server {}' "${nginxRoot}/alone.conf"
    )
}

runCleanLastInstallationSkipsDuplicateNginxCleanupRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/clean-last-installation-nginx-safety"
        local unsafeRoot="${root}/unsafe"
        local cleanupLog="${root}/cleanup.log"
        local managedFiles=(alone.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf checkPortOpen.conf)
        local file
        mkdir -p "${unsafeRoot}"
        for file in "${managedFiles[@]}"; do
            printf 'managed\n' >"${unsafeRoot}/${file}"
        done
        cd "${unsafeRoot}"

        currentDefaultPort=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        xrayVLESSRealityXHTTPort=
        singBoxVLESSVisionPort=
        singBoxVLESSRealityVisionPort=
        singBoxVLESSRealityGRPCPort=
        singBoxHysteria2Port=
        singBoxTuicPort=
        singBoxSocks5Port=
        hysteriaPort=
        tuicPort=
        nginxConfigPath=
        nginxStaticPath="${root}/static"

        handleXray() { return 0; }
        handleSingBox() { return 0; }
        handleNginx() { return 0; }
        runCoreServiceActionAllowFailure() {
            "$@"
        }
        cleanAgentNginxConf() {
            printf 'clean-agent\n' >>"${cleanupLog}"
            return 0
        }
        cleanDirectoryContent() {
            printf 'clean-dir:%s\n' "$1" >>"${cleanupLog}"
            return 0
        }
        rm() {
            local arg safeArgs=()
            printf 'rm:%s\n' "$*" >>"${cleanupLog}"
            for arg in "$@"; do
                [[ "${arg}" == -* ]] && { safeArgs+=("${arg}"); continue; }
                [[ "${arg}" == /* ]] && return 0
                safeArgs+=("${arg}")
            done
            command rm "${safeArgs[@]}"
        }
        systemctl() { return 0; }
        lsof() { return 1; }
        autoRead() { printf -v "$3" 'n'; }
        readInstallType() { return 0; }
        mkdirTools() { return 0; }

        cleanLastInstallationConfig >/dev/null
        grep -qx 'clean-agent' "${cleanupLog}"
        for file in "${managedFiles[@]}"; do
            [[ -f "${file}" ]]
        done
    )
}

runInstallNginxAlpineDefaultPathSafetyRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/install-nginx-alpine-default-path-safety"
        local unsafeRoot="${root}/unsafe"
        local nginxRoot="${root}/nginx conf.d"
        local openRcServiceFile="${root}/init.d/nginx"
        local bootLog="${root}/boot.log"
        local rc
        mkdir -p "${unsafeRoot}" "${nginxRoot}" "$(dirname -- "${openRcServiceFile}")"
        printf 'default\n' >"${unsafeRoot}/default.conf"
        printf 'nginx-openrc\n' >"${openRcServiceFile}"

        release=alpine
        export PADM_NGINX_OPENRC_SERVICE_FILE="${openRcServiceFile}"
        beginPackageInstallTransaction() { PADM_PACKAGE_TRANSACTION_STARTED=true; }
        endPackageInstallTransaction() { return 0; }
        installPackageTracked() { return 0; }
        bootStartup() { printf '%s\n' "$*" >>"${bootLog}"; }
        failPackageInstallTransaction() { exit 77; }

        (
            cd "${unsafeRoot}"
            nginxConfigPath=
            set +e
            ( installNginxTools )
            rc=$?
            set -e
            [[ "${rc}" == "77" ]]
            [[ -f default.conf ]]
        )

        printf 'default\n' >"${nginxRoot}/default.conf"
        nginxConfigPath="${nginxRoot}/"
        installNginxTools
        [[ ! -e "${nginxRoot}/default.conf" ]]
        grep -qx 'nginx' "${bootLog}"
    )
}

runInstallNginxStaticRejectsUnsafePathRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/install-nginx-static-unsafe-path"
        local scriptDir="${root}/script"
        local staticDir="${root}/relative-static"
        local unzipLog="${root}/unzip.log"
        mkdir -p "${scriptDir}/assets/static-sites/templates" "${staticDir}"
        printf 'zip\n' >"${scriptDir}/assets/static-sites/templates/html1.zip"
        cd "${root}"

        SCRIPT_DIR="${scriptDir}"
        nginxStaticPath="relative-static/"
        cleanDirectoryContent() { return 1; }
        unzip() {
            printf 'unzip\n' >"${unzipLog}"
            return 0
        }
        renderNginxStaticTemplate() {
            printf 'render\n' >"${root}/render.log"
        }

        ! installNginxStaticTemplate 1
        [[ ! -e "${staticDir}/html1.zip" ]]
        [[ ! -e "${unzipLog}" ]]
    )
}

runInstallNginxStaticPreservesLiveSiteOnUnzipFailureRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/install-nginx-static-unzip-failure"
        local scriptDir="${root}/script"
        local staticDir="${root}/static"
        mkdir -p "${scriptDir}/assets/static-sites/templates" "${staticDir}"
        printf 'zip\n' >"${scriptDir}/assets/static-sites/templates/html1.zip"
        printf 'keep\n' >"${staticDir}/index.html"
        printf 'marker\n' >"${staticDir}/check"

        SCRIPT_DIR="${scriptDir}"
        nginxStaticPath="${staticDir}"
        unzip() {
            local targetDir=
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -d)
                    targetDir=$2
                    shift 2
                    ;;
                *)
                    shift
                    ;;
                esac
            done
            [[ -n "${targetDir}" ]]
            printf 'partial\n' >"${targetDir}/index.html"
            return 1
        }
        renderNginxStaticTemplate() {
            printf 'render\n' >"${root}/render.log"
        }

        ! installNginxStaticTemplate 1
        [[ "$(<"${staticDir}/index.html")" == "keep" ]]
        [[ "$(<"${staticDir}/check")" == "marker" ]]
        [[ ! -e "${root}/render.log" ]]
        ! compgen -G "${root}/.static.*" >/dev/null

        local missingRoot="${TMP_DIR}/install-nginx-static-missing-local-template"
        local missingScriptDir="${missingRoot}/script"
        local missingStaticDir="${missingRoot}/static"
        local downloadMarker="${missingRoot}/download.log"
        mkdir -p "${missingScriptDir}/assets/static-sites/templates" "${missingStaticDir}"
        printf 'keep\n' >"${missingStaticDir}/index.html"
        SCRIPT_DIR="${missingScriptDir}"
        nginxStaticPath="${missingStaticDir}"
        downloadFile() {
            printf 'download\n' >"${downloadMarker}"
            [[ "$1" == "-O" ]] || return 1
            printf 'zip\n' >"$2"
        }
        unzip() {
            return 0
        }
        renderNginxStaticTemplate() {
            printf 'render\n' >"${missingRoot}/render.log"
        }

        ! installNginxStaticTemplate 1
        [[ ! -e "${downloadMarker}" ]]
        [[ -f "${missingStaticDir}/index.html" ]] || return 1
        [[ "$(<"${missingStaticDir}/index.html")" == "keep" ]]
    )
}

runCleanLastInstallationRejectsUnsafeStaticPathRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/clean-last-installation-static-safety"
        local staticDir="${root}/relative-static"
        local errorLog="${root}/errors.log"
        local rc
        mkdir -p "${staticDir}"
        printf 'check\n' >"${staticDir}/check"
        cd "${root}"

        currentDefaultPort=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        xrayVLESSRealityXHTTPort=
        singBoxVLESSVisionPort=
        singBoxVLESSRealityVisionPort=
        singBoxVLESSRealityGRPCPort=
        singBoxHysteria2Port=
        singBoxTuicPort=
        singBoxSocks5Port=
        hysteriaPort=
        tuicPort=
        nginxStaticPath="relative-static"

        handleXray() { return 0; }
        handleSingBox() { return 0; }
        handleNginx() { return 0; }
        runCoreServiceActionAllowFailure() {
            "$@"
        }
        cleanAgentNginxConf() { return 0; }
        cleanDirectoryContent() { return 0; }
        systemctl() { return 0; }
        lsof() { return 1; }
        autoRead() { printf -v "$3" 'n'; }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        rm() {
            if [[ "$*" == "-rf relative-static" ]]; then
                command rm -rf relative-static
                return 0
            fi
            return 0
        }

        set +e
        cleanLastInstallationConfig >/dev/null
        rc=$?
        set -e
        [[ "${rc}" != "0" ]]
        [[ -f "${staticDir}/check" ]]
        grep -q '静态站点目录' "${errorLog}"
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

runAutoInstallDoesNotReadMissingRequiredValueRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        AUTO_INSTALL=true
        AUTO_INSTALL_TYPE=custom
        AUTO_DOMAIN=
        local value=unset
        autoRead domain "请输入要配置的域名" value <<<"rc=\$?"
        [[ -z "${value:-}" ]]
    )
}

runAutoInstallTlsDomainMissingReturnsRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local logFile="${TMP_DIR}/auto-install-tls-domain-missing.log"

        parseInstallArgs --install-type custom --core sing-box --protocols 4 --entry-host 45.221.113.40 --reuse-last no
        errorCard() { printf 'error:%s\n' "$*" >>"${logFile}"; }
        initVar() { printf 'initVar\n' >>"${logFile}"; }
        mkdirTools() { printf 'mkdirTools\n' >>"${logFile}"; }

        set +e
        autoInstallValidateRequiredInputs
        local status=$?
        set -e

        [[ "${status}" -ne 0 ]]
        grep -q '域名不可为空' "${logFile}"
        ! grep -q 'initVar' "${logFile}"
        ! grep -q 'mkdirTools' "${logFile}"
    )
}

runAutoInstallTwoDigitSingleProtocolRegression() {
    local outputFile
    outputFile="${TMP_DIR}/auto-install-two-digit-single-protocol.txt"
    (
        source "${PROJECT_ROOT}/shell/core/bootstrap.sh"
        AUTO_INSTALL=true
        installTools() { :; }
        initTLSNginxConfig() { return 1; }
        readAcmeTLS() { :; }
        errorCard() { printf 'ERROR:%s\n' "$*"; }
        statusCard() { :; }
        progressCard() { printf 'PROGRESS:%s\n' "$*"; }
        successCard() { :; }
        readLastInstallationConfig() { :; }
        unInstallSubscribe() { :; }
        protocolSelectionShowRiskNotes() { :; }
        customSingBoxInstall 31
    ) >"${outputFile}" 2>&1 || true
    ! grep -q '多选请使用英文逗号分隔' "${outputFile}"
    grep -q 'TUIC' "${outputFile}"
}

runParseInstallArgsMissingValueRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        parseInstallArgs --domain --port 443 --core sing-box --unknown-option ignored --user alice
        [[ -z "${AUTO_DOMAIN}" ]]
        [[ "${AUTO_PORT}" == "443" ]]
        [[ "${AUTO_CORE}" == "sing-box" ]]
        [[ "${AUTO_USER}" == "alice" ]]
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
        singboxUsers=$(initSingBoxClients 1)
        jq -e '.[0].email == "padm-abcdef12-VLESS_TCP/TLS_Vision"' <<<"${xrayUsers}" >/dev/null
        jq -e '.[0].name == "padm-abcdef12-VLESS_Reality_Vision"' <<<"${singboxUsers}" >/dev/null

        currentClients='{}'
        if initXrayClients 1 >/dev/null 2>&1 || initSingBoxClients 1 >/dev/null 2>&1; then
            return 1
        fi
        currentClients='[{"id":"11111111-1111-1111-1111-111111111111"}]'
        if initXrayClients 1 >/dev/null 2>&1 || initSingBoxClients 1 >/dev/null 2>&1; then
            return 1
        fi
    )
}

resolveReleaseWorkflowVersionForRegression() {
    local isReleaseCommit=$1
    local currentVersion=$2
    local latestTag=$3
    local commits=$4
    local releaseVersion needsBump
    local baseVersion major minor patch bump commitMessage

    releaseWorkflowCommitRequiresMajorBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:|BREAKING CHANGE:'
    }

    releaseWorkflowCommitRequiresMinorBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^feat(\([^)]*\))?:'
    }

    releaseWorkflowCommitRequiresPatchBump() {
        local commitMessage=$1
        echo "${commitMessage}" | grep -qE '^(fix|perf|refactor|docs|test|build|ci|chore)(\([^)]*\))?:'
    }

    if [[ "${isReleaseCommit}" == "true" ]]; then
        releaseVersion="${currentVersion}"
        needsBump=false
    else
        baseVersion=${latestTag#v}
        major=${baseVersion%%.*}
        minor=${baseVersion#*.}
        minor=${minor%%.*}
        patch=${baseVersion##*.}
        bump=none

        while IFS= read -r commitMessage; do
            if releaseWorkflowCommitRequiresMajorBump "${commitMessage}"; then
                bump=major
                break
            elif [[ "${bump}" != "minor" ]] && releaseWorkflowCommitRequiresMinorBump "${commitMessage}"; then
                bump=minor
            elif [[ "${bump}" == "none" ]] && releaseWorkflowCommitRequiresPatchBump "${commitMessage}"; then
                bump=patch
            fi
        done <<<"${commits}"

        case "${bump}" in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        esac

        releaseVersion="v${major}.${minor}.${patch}"
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

runVersionHelpersRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/version.sh"

        local nextVersion versionFile standaloneVersionFile
        nextVersion=$(nextScriptVersionFromCommits v1.2.0 $'fix(update): harden script refresh rollback')
        [[ "${nextVersion}" == "1.2.1" ]]
        nextVersion=$(nextScriptVersionFromCommits v1.2.0 $'feat(subscription): add new flow')
        [[ "${nextVersion}" == "1.3.0" ]]
        nextVersion=$(nextScriptVersionFromCommits v1.2.0 $'style: whitespace only')
        [[ "${nextVersion}" == "1.2.0" ]]

        versionFile="${TMP_DIR}/version-helper-version.sh"
        cat >"${versionFile}" <<'EOF'
#!/usr/bin/env bash
SCRIPT_VERSION="1.2.0"
EOF
        setScriptVersion v1.2.3 "${versionFile}"
        grep -q '^SCRIPT_VERSION="1\.2\.3"$' "${versionFile}"

        standaloneVersionFile="${TMP_DIR}/version-helper-standalone-version.sh"
        cat >"${standaloneVersionFile}" <<'EOF'
#!/usr/bin/env bash
SCRIPT_VERSION="1.2.0"
EOF
        bash -c '
            set -euo pipefail
            source "$1"
            setScriptVersion v1.2.4 "$2"
            grep -q "^SCRIPT_VERSION=\"1\\.2\\.4\"$" "$2"
        ' _ "${PROJECT_ROOT}/shell/core/version.sh" "${standaloneVersionFile}"
    )
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
    source "${PROJECT_ROOT}/shell/core/network.sh"
    source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    local natStateFile="${TMP_DIR}/port-hopping-nat.state"
    local allowCalls=0
    local denyCalls=0
    local allowPortShouldFail=false
    local downloadCount=0
    local inputCount=0
    local rangeMode=invalid-hyphen
    local iptablesDeleteShouldFail=false
    local iptablesSaveShouldFail=false
    local rc
    local uploadCount=0
    local warnLog="${TMP_DIR}/port-hopping-warn.log"
    : >"${warnLog}"
    : >"${natStateFile}"

    statusCard() {
        printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >>"${warnLog}"
    }
    autoRead() {
        case "$1" in
        hysteria_port)
            inputCount=$((inputCount + 1))
            if [[ "${inputCount}" == "1" ]]; then
                printf -v "$3" '%s' '12abc'
            else
                printf -v "$3" '%s' '16295'
            fi
            ;;
        tuic_port)
            inputCount=$((inputCount + 1))
            if [[ "${inputCount}" == "1" ]]; then
                printf -v "$3" '%s' '12abc'
            else
                printf -v "$3" '%s' '26451'
            fi
            ;;
        port_hopping_range)
            inputCount=$((inputCount + 1))
            if [[ "${rangeMode}" == "single" && "${inputCount}" == "1" ]]; then
                printf -v "$3" '%s' '33001'
            elif [[ "${inputCount}" == "1" ]]; then
                printf -v "$3" '%s' '33000-33005x'
            else
                printf -v "$3" '%s' '33000-33005'
            fi
            ;;
        hysteria_download_speed)
            downloadCount=$((downloadCount + 1))
            if [[ "${downloadCount}" == "1" ]]; then
                printf -v "$3" '%s' '120abc'
            else
                printf -v "$3" '%s' '120'
            fi
            ;;
        hysteria_upload_speed)
            uploadCount=$((uploadCount + 1))
            if [[ "${uploadCount}" == "1" ]]; then
                printf -v "$3" '%s' '60abc'
            else
                printf -v "$3" '%s' '60'
            fi
            ;;
        *)
            printf -v "$3" '%s' ''
            ;;
        esac
    }
    allowPort() {
        printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${warnLog}"
        allowCalls=$((allowCalls + 1))
        [[ "${allowPortShouldFail}" != "true" ]]
    }
    denyPort() {
        printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${warnLog}"
        denyCalls=$((denyCalls + 1))
    }
    readSingBoxConfig() {
        hysteriaPort=
        tuicPort=
    }
    hysteria2RequireSingBoxField() { return 0; }
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
            [[ "${iptablesDeleteShouldFail}" != "true" ]] || return 1
            if [[ "$*" == *"--comment neil1123-vip_hysteria2_portHopping"* ]]; then
                awk '!/neil1123-vip_hysteria2_portHopping/' "${natStateFile}" >"${natStateFile}.tmp"
                mv "${natStateFile}.tmp" "${natStateFile}"
                return 0
            fi
            if [[ "$*" == *"--comment neil1123-vip_tuic_portHopping"* ]]; then
                awk '!/neil1123-vip_tuic_portHopping/' "${natStateFile}" >"${natStateFile}.tmp"
                mv "${natStateFile}.tmp" "${natStateFile}"
                return 0
            fi
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
        [[ "${iptablesSaveShouldFail}" != "true" ]] || return 1
        [[ -s "${natStateFile}" ]] && cat "${natStateFile}"
        return 0
    }

    rhelLike=false
    downloadCount=0
    uploadCount=0
    : >"${warnLog}"
    initHysteria2Network
    grep -q '带宽不合法' "${warnLog}"
    [[ "${hysteria2ClientDownloadSpeed}" == "120" ]]
    [[ "${hysteria2ClientUploadSpeed}" == "60" ]]

    inputCount=0
    initHysteriaPort
    grep -q '端口不合法' "${warnLog}"
    ! grep -q 'allow:12abc' "${warnLog}"
    grep -q 'allow:16295:tcp' "${warnLog}"
    grep -q 'allow:16295:udp' "${warnLog}"

    inputCount=0
    : >"${warnLog}"
    initTuicPort
    grep -q '端口不合法' "${warnLog}"
    ! grep -q 'allow:12abc' "${warnLog}"
    grep -q 'allow:26451:tcp' "${warnLog}"
    grep -q 'allow:26451:udp' "${warnLog}"

    inputCount=0
    : >"${warnLog}"
    portHoppingStart=
    portHoppingEnd=
    addPortHopping hysteria2 16295
    [[ -s "${natStateFile}" ]]
    padmFirewallStateHas 'forward:iptables:hysteria2:33000:33005:16295'
    grep -q '范围不合法' "${warnLog}"
    [[ "${allowCalls}" == "5" ]]
    grep -Eq '端口跳跃持久化|未检测到 netfilter-persistent' "${warnLog}"

    rangeMode=single
    inputCount=0
    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    : >"${natStateFile}"
    addPortHopping hysteria2 16295
    grep -q '范围不合法' "${warnLog}"
    grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"
    rangeMode=invalid-hyphen

    readPortHopping hysteria2 16295
    [[ "${hysteria2PortHoppingStart}" == "33000" ]]
    [[ "${hysteria2PortHoppingEnd}" == "33005" ]]

    deletePortHoppingRules hysteria2 33000 33005 16295
    grep -q 'keep-other-rule' "${natStateFile}"
    ! grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"
    grep -qx 'deny:33000:33005:udp' "${warnLog}"
    ! padmFirewallStateHas 'forward:iptables:hysteria2:33000:33005:16295'

    : >"${natStateFile}"
    hysteria2PortHoppingStart=33000
    hysteria2PortHoppingEnd=33005
    tuicPortHoppingStart=
    tuicPortHoppingEnd=
    addPortHopping tuic 26451
    grep -q 'neil1123-vip_tuic_portHopping' "${natStateFile}"
    padmFirewallStateHas 'forward:iptables:tuic:33000:33005:26451'
    readPortHopping tuic 26451
    [[ "${tuicPortHoppingStart}" == "33000" ]]
    [[ "${tuicPortHoppingEnd}" == "33005" ]]

    : >"${natStateFile}"
    inputCount=1
    hysteria2PortHoppingStart=
    hysteria2PortHoppingEnd=
    iptablesSaveShouldFail=true
    set +e
    addPortHopping hysteria2 16295 >/dev/null 2>&1
    rc=$?
    set -e
    iptablesSaveShouldFail=false
    [[ "${rc}" == "1" ]]
    ! grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"

    inputCount=1
    allowPortShouldFail=true
    set +e
    addPortHopping hysteria2 16295 >/dev/null 2>&1
    rc=$?
    set -e
    allowPortShouldFail=false
    [[ "${rc}" == "1" ]]
    ! grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"

    cat >"${natStateFile}" <<'EOF'
-A PREROUTING -p udp -m udp --dport 33000:33005 -m comment --comment neil1123-vip_hysteria2_portHopping -j DNAT --to-destination :16295
EOF
    iptablesDeleteShouldFail=true
    set +e
    deletePortHoppingRules hysteria2 33000 33005 16295 >/dev/null 2>&1
    rc=$?
    set -e
    iptablesDeleteShouldFail=false
    [[ "${rc}" == "1" ]]
    grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"
    [[ "${denyCalls}" == "1" ]]
    cleanupPadmFirewallRules
    ! grep -q 'neil1123-vip_hysteria2_portHopping' "${natStateFile}"
    [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

    (
        local firewalldLog="${TMP_DIR}/port-hopping-firewalld.log"
        local masquerade=false
        local firewalldActive=true
        local removeFailurePort=
        local rc
        local port spec
        local -A forwardPorts=()
        PADM_FIREWALL_STATE_FILE="${TMP_DIR}/port-hopping-firewall.state"
        rm -f "${PADM_FIREWALL_STATE_FILE}"
        : >"${firewalldLog}"
        rhelLike=true
        inputCount=1
        hysteria2PortHoppingStart=
        hysteria2PortHoppingEnd=
        systemctl() {
            if [[ "$*" == "status firewalld" && "${firewalldActive}" == "true" ]]; then
                printf 'Active: active (running)\n'
            fi
            [[ "${firewalldActive}" == "true" ]]
        }
        sudo() { "$@"; }
        firewall-cmd() {
            local originalArgs=" $* "
            local -a filteredArgs=()
            local arg
            if [[ "$*" != "--reload" && "${originalArgs}" != *" --zone=public "* ]]; then
                return 1
            fi
            for arg in "$@"; do
                [[ "${arg}" == "--zone=public" || "${arg}" == "--permanent" ]] || filteredArgs+=("${arg}")
            done
            set -- "${filteredArgs[@]}"
            case "$1" in
            --query-masquerade) [[ "${masquerade}" == "true" ]] ;;
            --query-forward-port=*)
                spec=${1#--query-forward-port=port=}
                port=${spec%%:*}
                [[ -n "${forwardPorts[${port}]:-}" ]]
                ;;
            --reload) return 0 ;;
            --list-forward-ports)
                for port in "${!forwardPorts[@]}"; do
                    printf 'port=%s:proto=udp:toport=16295\n' "${port}"
                done
                ;;
            --add-masquerade)
                masquerade=true
                printf 'masquerade:add\n' >>"${firewalldLog}"
                ;;
            --remove-masquerade)
                masquerade=false
                printf 'masquerade:remove\n' >>"${firewalldLog}"
                ;;
            --add-forward-port=*)
                spec=${1#--add-forward-port=port=}
                port=${spec%%:*}
                forwardPorts[${port}]=1
                ;;
            --remove-forward-port=*)
                spec=${1#--remove-forward-port=port=}
                port=${spec%%:*}
                [[ "${port}" != "${removeFailurePort}" ]] || { removeFailurePort=; return 1; }
                [[ -n "${forwardPorts[${port}]:-}" ]] || return 1
                unset 'forwardPorts['"${port}"']'
                ;;
            esac
        }
        firewall-offline-cmd() {
            printf 'offline:%s\n' "$*" >>"${firewalldLog}"
            firewall-cmd "$@"
        }
        allowPort() { padmFirewallStateAdd 'port:firewalld:udp:33000:33005'; }
        denyPort() {
            printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewalldLog}"
            padmFirewallStateRemove 'port:firewalld:udp:33000:33005'
        }

        addPortHopping hysteria2 16295
        padmFirewallStateHas masquerade:firewalld
        padmFirewallStateHas 'forward:firewalld:udp:33000:33005:16295:owned=33000,33001,33002,33003,33004,33005'
        deletePortHoppingRules hysteria2 33000 33005 16295
        grep -qx 'masquerade:add' "${firewalldLog}"
        grep -qx 'masquerade:remove' "${firewalldLog}"
        grep -qx 'deny:33000:33005:udp' "${firewalldLog}"
        [[ "${masquerade}" == "false" ]]
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

        forwardPorts[33002]=1
        masquerade=true
        inputCount=1
        addPortHopping hysteria2 16295
        padmFirewallStateHas 'forward:firewalld:udp:33000:33005:16295:owned=33000,33001,33003,33004,33005'
        deletePortHoppingRules hysteria2 33000 33005 16295
        [[ -n "${forwardPorts[33002]:-}" ]]
        [[ "${#forwardPorts[@]}" == "1" ]]
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
        unset 'forwardPorts[33002]'
        masquerade=false

        inputCount=1
        addPortHopping hysteria2 16295
        firewalldActive=false
        deletePortHoppingRules hysteria2 33000 33005 16295
        [[ "${#forwardPorts[@]}" == "0" ]]
        grep -q '^offline:' "${firewalldLog}"
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
        firewalldActive=true

        inputCount=1
        addPortHopping hysteria2 16295
        removeFailurePort=33003
        set +e
        deletePortHoppingRules hysteria2 33000 33005 16295 >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        padmFirewallStateHas 'forward:firewalld:udp:33000:33005:16295:owned=33000,33001,33002,33003,33004,33005'
        deletePortHoppingRules hysteria2 33003 33003 16295
        [[ "${#forwardPorts[@]}" == "0" ]]
        grep -qx 'deny:33000:33005:udp' "${firewalldLog}"
        [[ "${masquerade}" == "false" ]]
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

        inputCount=1
        addPortHopping hysteria2 16295
        cleanupPadmFirewallRules
        [[ "${#forwardPorts[@]}" == "0" ]]
        [[ "${masquerade}" == "false" ]]
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    )
)

runPortHoppingMenuUsesCommandLookupRegression() (
    set -euo pipefail
    source "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    local actionLog="${TMP_DIR}/port-hopping-menu-command-lookup.log"
    local findLog="${TMP_DIR}/port-hopping-menu-find.log"
    local exitLog="${TMP_DIR}/port-hopping-menu-exit.log"
    : >"${actionLog}"
    : >"${findLog}"
    : >"${exitLog}"

    find() {
        printf 'find-called:%s\n' "$*" >>"${findLog}"
        return 1
    }
    exit() {
        printf 'exit-called:%s\n' "${1:-}" >>"${exitLog}"
        return 97
    }
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "iptables" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    autoRead() {
        printf -v "$3" '%s' '3'
    }
    readPortHopping() {
        hysteria2PortHoppingStart=33000
        hysteria2PortHoppingEnd=33005
    }
    statusCard() {
        printf '%s|%s\n' "$1" "$2" >>"${actionLog}"
    }
    menuItem() { :; }
    menuClose() { :; }
    echoContent() { :; }

    singBoxHysteria2Port=16295
    portHoppingMenu hysteria2
    [[ ! -s "${findLog}" ]]
    [[ ! -s "${exitLog}" ]]
    grep -q '当前端口跳跃范围为: 33000-33005' "${actionLog}"

    : >"${actionLog}"
    : >"${exitLog}"
    command() {
        if [[ "${1:-}" == "-v" && "${2:-}" == "iptables" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    rhelLike=true
    systemctl() { [[ "$*" == "is-active --quiet firewalld" ]]; }
    portHoppingMenu hysteria2
    [[ ! -s "${exitLog}" ]]
    grep -q '当前端口跳跃范围为: 33000-33005' "${actionLog}"

    local menuReadCount=0
    : >"${actionLog}"
    autoRead() {
        menuReadCount=$((menuReadCount + 1))
        if [[ "${menuReadCount}" == "1" ]]; then
            printf -v "$3" '%s' 'invalid'
        else
            printf -v "$3" '%s' '3'
        fi
    }
    readPortHopping() {
        [[ "$1" == "hysteria2" ]]
        hysteria2PortHoppingStart=33000
        hysteria2PortHoppingEnd=33005
    }
    portHoppingMenu hysteria2
    [[ "${menuReadCount}" == "2" ]]
    grep -q '当前端口跳跃范围为: 33000-33005' "${actionLog}"
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
    jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' <<<"${accounts}" >/dev/null

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

runManagedFileBackupManifestRegression() (
    local rootRel="${TMP_DIR}/managed-file-backup-manifest"
    local root
    local backupDir

    mkdir -p "${rootRel}/targets"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    backupDir="${root}/backup"
    printf 'old-one\n' >"${root}/targets/one.json"

    padmWriteManagedFileBackupManifest "${backupDir}" \
        "xray/one.json" "${root}/targets/one.json" \
        "xray/two.json" "${root}/targets/two.json"
    [[ -f "${backupDir}/xray/one.json" ]]
    [[ -f "${backupDir}/manifest" ]]

    printf 'new-one\n' >"${root}/targets/one.json"
    printf 'new-two\n' >"${root}/targets/two.json"

    padmRestoreManagedFileBackupManifest "${backupDir}"
    [[ "$(<"${root}/targets/one.json")" == "old-one" ]]
    [[ ! -e "${root}/targets/two.json" ]]
)

runManagedFileBackupManifestValidatorRegression() (
    local rootRel="${TMP_DIR}/managed-file-backup-manifest-validator"
    local root
    local backupDir
    local targetFile
    local originalContent
    local status

    mkdir -p "${rootRel}/targets"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    backupDir="${root}/backup"
    targetFile="${root}/targets/live.json"
    printf '{"version":"old"}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")

    padmWriteManagedFileBackupManifest "${backupDir}" "xray/live.json" "${targetFile}"
    printf '{"version":"new"}\n' >"${targetFile}"

    onlyRejectRestoreTarget() {
        [[ "$1" != "${targetFile}" ]]
    }
    set +e
    padmRestoreManagedFileBackupManifest "${backupDir}" onlyRejectRestoreTarget
    status=$?
    set -e
    unset -f onlyRejectRestoreTarget

    [[ "${status}" -ne 0 ]]
    [[ "$(<"${targetFile}")" == '{"version":"new"}' ]]
    [[ "${originalContent}" == '{"version":"old"}' ]]
)

runRemoveManagedFilesIgnoreFailureRegression() (
    local rootRel="${TMP_DIR}/remove-managed-files-ignore-failure"
    local root
    local fileA
    local fileB

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    fileA="${root}/a.bak"
    fileB="${root}/b.bak"
    printf 'a\n' >"${fileA}"
    printf 'b\n' >"${fileB}"

    rm() {
        if [[ "$1" == "-f" && "$2" == "--" && "$3" == "${fileA}" ]]; then
            return 1
        fi
        command rm "$@"
    }
    removeManagedFilesIfPresentIgnoreFailure "${fileA}" "${fileB}"
    unset -f rm

    [[ -f "${fileA}" ]]
    [[ ! -e "${fileB}" ]]
)

runRemoveManagedPathIgnoreFailureRegression() (
    local rootRel="${TMP_DIR}/remove-managed-path-ignore-failure"
    local root
    local dirA
    local dirB

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    dirA="${root}/a"
    dirB="${root}/b"
    mkdir -p "${dirA}" "${dirB}"

    rm() {
        if [[ "$1" == "-rf" && "$2" == "--" && "$3" == "${dirA}" ]]; then
            return 1
        fi
        command rm "$@"
    }
    removeManagedPathIfPresentIgnoreFailure "${dirA}" "${dirB}"
    unset -f rm

    [[ -d "${dirA}" ]]
    [[ ! -e "${dirB}" ]]
)

runCheckLogBackupMissingRestoreRegression() (
    local root="${TMP_DIR}/check-log-backup-restore"
    local backupDir
    local restoreBackupDir
    mkdir -p "${root}"
    printf 'old-policy\n' >"${root}/policy.json"

    checkLogBackupCreate backupDir "${root}/policy.json"
    [[ -n "${backupDir}" && -d "${backupDir}" ]]
    padmRemoveCleanupPath "${backupDir}"

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
    local unsupportedOsRelease="${TMP_DIR}/unsupported-os-release"
    local oldOsReleaseFile="${PADM_OS_RELEASE_FILE:-}"
    local rc

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

    getenforce() { printf 'Enforcing\n'; }
    set +e
    (checkCentosSELinux >/dev/null 2>&1)
    rc=$?
    set -e
    unset -f getenforce
    [[ "${rc}" == "1" ]]

    : >"${unsupportedOsRelease}"
    set +e
    (
        release=
        PADM_OS_RELEASE_FILE="${unsupportedOsRelease}"
        grep() { return 1; }
        checkSystem >/dev/null 2>&1
    )
    rc=$?
    set -e
    [[ "${rc}" == "1" ]]

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
    errorCard() { recordMenuAction "errorCard:$1"; }
    autoRead() {
        local targetVar=$3
        local input=
        IFS= read -r input || input=
        printf -v "${targetVar}" '%s' "${input}"
    }
    selectCoreInstall() { recordMenuAction selectCoreInstall; }
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
    [[ "$(protocolMenuDescription 5)" == "推荐；sing-box / tcp / tls" ]]
    [[ "$(protocolMenuDescription 4)" == "推荐；sing-box / tcp / tls" ]]
    coreInstallType="${oldCoreInstallType}"
}

runUpdatePadmVersionPromptRegression() {
    local installDir outputLog errorLog downloadLog oldTmpDir
    local restoreFailureDir restoreFailureErrorLog restoreFailureDownloadLog
    local replaceFailureDir replaceFailureErrorLog replaceFailureDownloadLog
    local stageFailureDir stageFailureErrorLog stageFailureDownloadLog
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
    stageFailureDir="${TMP_DIR}/update-padm-stage-failure"
    stageFailureErrorLog="${TMP_DIR}/update-padm-stage-failure-error.log"
    stageFailureDownloadLog="${TMP_DIR}/update-padm-stage-failure-download.log"
    updateTmpRoot="${TMP_DIR}/update-padm-tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${installDir}" "${restoreFailureDir}" "${replaceFailureDir}" "${stageFailureDir}" "${updateTmpRoot}"
    installDir=$(cd -- "${installDir}" && pwd -P)
    restoreFailureDir=$(cd -- "${restoreFailureDir}" && pwd -P)
    replaceFailureDir=$(cd -- "${replaceFailureDir}" && pwd -P)
    stageFailureDir=$(cd -- "${stageFailureDir}" && pwd -P)

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
            if [[ "$1" == "-f" && "$2" == "--" && "$3" == "${restoreFailureDir}/install.sh.bak" && "$4" == "${restoreFailureDir}/install.sh" ]]; then
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
        TMPDIR="${updateTmpRoot}"

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
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "$2" == "${replaceFailureDir}/install.sh" ]]; then
                return 1
            fi
            originalCommitGeneratedFile "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-replace-failure-run.log" 2>&1 && return 1
    grep -q '更新入口提交失败，已取消更新' "${replaceFailureErrorLog}"
    [[ ! -e "${replaceFailureDir}/install.sh.bak" ]]
    "${replaceFailureDir}/install.sh" | grep -q 'old-entry'
    ! compgen -G "${replaceFailureDir}/.install.sh.install.*" >/dev/null

    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${stageFailureDir}/install.sh"
    chmod 700 "${stageFailureDir}/install.sh"
    (
        REGRESSION_ERROR_CARD_LOG="${stageFailureErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${stageFailureDir}"
        TMPDIR="${updateTmpRoot}"

        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${stageFailureDownloadLog}"
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
        cp() {
            local targetPath="${@: -1}"
            case "${targetPath}" in
            "${stageFailureDir}"/.install.sh.install.*)
                return 1
                ;;
            esac
            command cp "$@"
        }

        updatePadm 1
    ) >"${TMP_DIR}/update-padm-stage-failure-run.log" 2>&1 && return 1
    grep -q '更新入口暂存失败，已取消更新' "${stageFailureErrorLog}"
    [[ ! -e "${stageFailureDir}/install.sh.bak" ]]
    "${stageFailureDir}/install.sh" | grep -q 'old-entry'
    ! compgen -G "${stageFailureDir}/.install.sh.install.*" >/dev/null

    (
        local unsafeRoot="${TMP_DIR}/update-padm-unsafe-target"
        local unsafeErrorLog="${TMP_DIR}/update-padm-unsafe-error.log"
        mkdir -p "${unsafeRoot}"
        unsafeRoot=$(cd -- "${unsafeRoot}" && pwd -P)
        unsafeErrorLog="$(cd -- "$(dirname -- "${unsafeErrorLog}")" && pwd -P)/$(basename -- "${unsafeErrorLog}")"
        : >"${unsafeErrorLog}"
        cd "${unsafeRoot}"
        REGRESSION_ERROR_CARD_LOG="${unsafeErrorLog}"
        release=debian
        PADM_INSTALL_DIR="unsafe-target"
        ! updatePadm 1
        [[ ! -e "${unsafeRoot}/unsafe-target/install.sh" ]]
        [[ ! -e "${unsafeRoot}/unsafe-target/install.sh.bak" ]]
        grep -q '更新入口目录异常' "${unsafeErrorLog}"
    )

    (
        local dirTargetRoot="${TMP_DIR}/update-padm-directory-target"
        local dirTargetErrorLog="${TMP_DIR}/update-padm-directory-target-error.log"
        local dirTargetDownloadLog="${TMP_DIR}/update-padm-directory-target-download.log"
        mkdir -p "${dirTargetRoot}"
        dirTargetRoot=$(cd -- "${dirTargetRoot}" && pwd -P)
        dirTargetErrorLog="$(cd -- "$(dirname -- "${dirTargetErrorLog}")" && pwd -P)/$(basename -- "${dirTargetErrorLog}")"
        : >"${dirTargetErrorLog}"
        : >"${dirTargetDownloadLog}"
        mkdir -p "${dirTargetRoot}/install.sh"
        REGRESSION_ERROR_CARD_LOG="${dirTargetErrorLog}"
        release=debian
        PADM_INSTALL_DIR="${dirTargetRoot}"
        helperLog="${dirTargetRoot}/manual-check.log"
        : >"${helperLog}"
        coreSetManualCheckMessage() {
            printf "manual-check:%s|%s\n" "$2" "$3" >>"${helperLog}"
            printf -v "$1" "%s，请手动检查%s" "$2" "$3"
        }
        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$2" >>"${dirTargetDownloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'new-entry-ok\n'
exit 0
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }
        ! updatePadm 1
        [[ -d "${dirTargetRoot}/install.sh" ]]
        [[ ! -e "${dirTargetRoot}/install.sh/install.sh" ]]
        [[ ! -e "${dirTargetRoot}/install.sh.bak" ]]
        [[ ! -s "${dirTargetDownloadLog}" ]]
        grep -q "manual-check:更新入口目标异常| ${dirTargetRoot}/install.sh" "${helperLog}"
        grep -q "更新入口目标异常，请手动检查 ${dirTargetRoot}/install.sh" "${dirTargetErrorLog}"
    )
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runUpdatePadmSingleRefRegression() {
    local root installDir updateTmpRoot downloadLog execLog errorLog oldTmpDir
    root="${TMP_DIR}/update-padm-single-ref"
    installDir="${root}/install"
    updateTmpRoot="${root}/tmp"
    downloadLog="${root}/download.log"
    execLog="${root}/exec.log"
    errorLog="${root}/error.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${installDir}" "${updateTmpRoot}"
    : >"${downloadLog}"
    : >"${execLog}"
    : >"${errorLog}"
    installDir=$(cd -- "${installDir}" && pwd -P)
    updateTmpRoot=$(cd -- "${updateTmpRoot}" && pwd -P)
    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${installDir}/install.sh"
    chmod 700 "${installDir}/install.sh"

    (
        REGRESSION_ERROR_CARD_LOG="${errorLog}"
        release=debian
        PADM_INSTALL_DIR="${installDir}"
        TMPDIR="${updateTmpRoot}"
        export PADM_UPDATE_SINGLE_REF_EXEC_LOG="${execLog}"
        fetchRemoteRef() { printf '1111111111111111111111111111111111111111\n'; }
        downloadFile() {
            while [[ $# -gt 0 ]]; do
                case "$1" in
                -P)
                    mkdir -p "$2"
                    printf '%s\n' "$*" >>"${downloadLog}"
                    cat >"$2/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
printf 'force:%s\n' "${PADM_FORCE_SCRIPT_MODULE_REFRESH:-}" >"${PADM_UPDATE_SINGLE_REF_EXEC_LOG}"
printf 'ref:%s\n' "${PADM_SCRIPT_MODULE_REF:-}" >>"${PADM_UPDATE_SINGLE_REF_EXEC_LOG}"
exit 0
EOF
                    return 0
                    ;;
                esac
                shift
            done
            return 1
        }

        updatePadm 1
    ) >"${root}/run.log" 2>&1

    grep -q 'https://raw.githubusercontent.com/neil1123-vip/padm/1111111111111111111111111111111111111111/install.sh' "${downloadLog}"
    grep -qx 'force:1' "${execLog}"
    grep -qx 'ref:1111111111111111111111111111111111111111' "${execLog}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshRefFailClosedRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local fixtureDir outputLog downloadLog oldTmpDir
        fixtureDir="${TMP_DIR}/install-refresh-ref-fail-closed"
        mkdir -p "${fixtureDir}"
        outputLog="${fixtureDir}/refresh.log"
        downloadLog="${fixtureDir}/downloads.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/tmp"
        printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${fixtureDir}/install.sh"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf 'old-doc\n' >"${fixtureDir}/documents/marker"
        printf 'old-readme\n' >"${fixtureDir}/README.md"

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
            scriptIsSafeAbsolutePath() { return 0; }
            fetchRemoteRef() { printf '2222222222222222222222222222222222222222\n'; }
            downloadRepoArchive() {
                local archiveUrl=$1
                local extractDir=$2
                printf '%s\n' "${archiveUrl}" >>"${downloadLog}"
                if [[ "${archiveUrl}" == *"dddddddddddddddddddddddddddddddddddddddd.tar.gz" ]]; then
                    return 1
                fi
                rm -rf "${extractDir}"
                mkdir -p "${extractDir}/padm-main/shell" "${extractDir}/padm-main/documents" || return 1
                printf 'new-shell\n' >"${extractDir}/padm-main/shell/marker"
                printf 'new-doc\n' >"${extractDir}/padm-main/documents/marker"
                printf 'new-readme\n' >"${extractDir}/padm-main/README.md"
                return 0
            }
            ( refreshScriptModules dddddddddddddddddddddddddddddddddddddddd )
            refreshStatus=$?
            [[ "${refreshStatus}" -ne 0 ]]
        ) >"${outputLog}" 2>&1

        ! grep -q '回退到主分支最新完整安装包' "${outputLog}"
        [[ "$(wc -l <"${downloadLog}" | tr -d ' ')" == "1" ]]
        grep -q 'dddddddddddddddddddddddddddddddddddddddd.tar.gz' "${downloadLog}"
        ! grep -q '回退到主分支最新完整安装包' "${PROJECT_ROOT}/install.sh"
        [[ ! -f "${fixtureDir}/.padm-ref" ]]
        [[ ! -f "${fixtureDir}/.padm-entry-ref" ]]
        [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
        [[ "$(<"${fixtureDir}/documents/marker")" == "old-doc" ]]
        [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]

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
        mkdir -p "${fixtureDir}"
        archiveRoot="${fixtureDir}/archive"
        outputLog="${fixtureDir}/refresh.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${archiveRoot}/padm-main/shell/core" "${archiveRoot}/padm-main/documents" "${archiveRoot}/padm-main/assets" "${fixtureDir}/shell" "${fixtureDir}/tmp"
        printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${fixtureDir}/install.sh"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf '3333333333333333333333333333333333333333\n' >"${fixtureDir}/.padm-ref"
        printf '3333333333333333333333333333333333333333\n' >"${fixtureDir}/.padm-entry-ref"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
        printf '# bootstrap fixture\n' >"${archiveRoot}/padm-main/shell/core/bootstrap.sh"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/shell/validate_install.sh"
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
            scriptIsSafeAbsolutePath() { return 0; }
            command() {
                if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                    return 0
                fi
                builtin command "$@"
            }
            curl() { tar -cz -C "${archiveRoot}" padm-main; }
            if refreshScriptModules ""; then
                exit 0
            fi
            exit 1
        ) >"${outputLog}" 2>&1 && return 1

        [[ "$(<"${fixtureDir}/.padm-ref")" == "3333333333333333333333333333333333333333" ]]
        [[ "$(<"${fixtureDir}/.padm-entry-ref")" == "3333333333333333333333333333333333333333" ]]
        [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]

        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runInstallRefreshRejectsUnsafeScriptDirRegression() {
    local root archiveRoot outputLog oldTmpDir
    root="${TMP_DIR}/install-refresh-unsafe-script-dir"
    archiveRoot="${root}/archive/padm-main"
    outputLog="${root}/refresh.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${archiveRoot}/shell" "${root}/relative-script/shell" "${root}/tmp"
    printf '#!/usr/bin/env bash\n' >"${archiveRoot}/install.sh"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'keep\n' >"${root}/relative-script/shell/sentinel"

    (
        set +e
        cd "${root}"
        TMPDIR="${root}/tmp"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="relative-script"
        REPO_ARCHIVE_DIR="padm-main"
        SCRIPT_REF_FILE="${SCRIPT_DIR}/.padm-ref"
        SCRIPT_EXPECTED_REF_FILE="${SCRIPT_DIR}/.padm-entry-ref"
        SCRIPT_MANIFEST_FILE="${SCRIPT_DIR}/.padm-module-manifest"
        REPO_ZIP_URL="fixture.tar.gz"
        command() {
            if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        curl() { tar -cz -C "${root}/archive" padm-main; }
        refreshScriptModules 4444444444444444444444444444444444444444
    ) >"${outputLog}" 2>&1 && return 1

    grep -q '脚本目录异常' "${outputLog}"
    [[ -f "${root}/relative-script/shell/sentinel" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshRejectsUnsafeArchiveRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local fixtureDir archiveRoot outputLog oldTmpDir
        fixtureDir="${TMP_DIR}/install-refresh-unsafe-archive"
        mkdir -p "${fixtureDir}"
        archiveRoot="${fixtureDir}/archive"
        outputLog="${fixtureDir}/refresh.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${archiveRoot}/padm-main/shell/core" "${fixtureDir}/shell" "${fixtureDir}/tmp"
        printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${fixtureDir}/install.sh"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
        printf '# bootstrap fixture\n' >"${archiveRoot}/padm-main/shell/core/bootstrap.sh"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/shell/validate_install.sh"
        printf 'new-shell\n' >"${archiveRoot}/padm-main/shell/marker"
        printf 'escape\n' >"${archiveRoot}/escape.txt"

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
            scriptIsSafeAbsolutePath() { return 0; }
            command() {
                if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                    return 0
                fi
                builtin command "$@"
            }
            curl() { tar -cz -C "${archiveRoot}" padm-main --transform='s#^escape.txt$#../escape.txt#' escape.txt; }
            refreshScriptModules 4444444444444444444444444444444444444444
        ) >"${outputLog}" 2>&1 && return 1

        grep -q '完整安装包结构异常，请重新执行安装命令' "${outputLog}"
        [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
        [[ ! -e "${fixtureDir}/escape.txt" ]]
        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runInstallRefreshRejectsUnsupportedArchiveEntriesRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local fixtureDir archiveRoot outputLog oldTmpDir
        fixtureDir="${TMP_DIR}/install-refresh-unsupported-archive-entry"
        mkdir -p "${fixtureDir}"
        archiveRoot="${fixtureDir}/archive"
        outputLog="${fixtureDir}/refresh.log"
        oldTmpDir="${TMPDIR:-}"
        mkdir -p "${archiveRoot}/padm-main/shell/core" "${fixtureDir}/shell" "${fixtureDir}/tmp"
        printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${fixtureDir}/install.sh"
        printf 'old-shell\n' >"${fixtureDir}/shell/marker"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
        printf '# bootstrap fixture\n' >"${archiveRoot}/padm-main/shell/core/bootstrap.sh"
        printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/shell/validate_install.sh"
        printf 'new-shell\n' >"${archiveRoot}/padm-main/shell/marker"
        mkfifo "${archiveRoot}/padm-main/unsupported.pipe"

        runFixtureRefresh() (
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
            scriptIsSafeAbsolutePath() { return 0; }
            command() {
                if [[ "$1" == "-v" && "$2" == "curl" ]]; then
                    return 0
                fi
                builtin command "$@"
            }
            curl() { tar -cz -C "${archiveRoot}" padm-main; }
            refreshScriptModules 4444444444444444444444444444444444444444
        )

        runFixtureRefresh >"${outputLog}" 2>&1 && return 1

        grep -q '完整安装包结构异常，请重新执行安装命令' "${outputLog}"
        [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
        [[ ! -e "${fixtureDir}/unsupported.pipe" ]]

        rm "${archiveRoot}/padm-main/unsupported.pipe"
        truncate -s 104857601 "${archiveRoot}/padm-main/oversized.bin"
        runFixtureRefresh >"${outputLog}" 2>&1 && return 1

        grep -q '完整安装包结构异常，请重新执行安装命令' "${outputLog}"
        [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
        [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
        [[ ! -e "${fixtureDir}/oversized.bin" ]]
        if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    )
}

runRemoveInstallPathRetryRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local rootRel="${TMP_DIR}/remove-install-path-retry"
        local root
        local target
        local attemptsFile
        mkdir -p "${rootRel}/target/child"
        root=$(cd -- "${rootRel}" && pwd -P)
        target="${root}/target"
        attemptsFile="${root}/attempts.log"
        printf 'data\n' >"${target}/child/file"
        : >"${attemptsFile}"

        rm() {
            printf '%s\n' "$*" >>"${attemptsFile}"
            if [[ "$1" == "-rf" && "$2" == "--" && "$3" == "${target}" ]]; then
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

runRemoveInstallPathFileModeRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local rootRel="${TMP_DIR}/remove-install-path-file-mode"
        local root
        local target
        local rmLog
        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        target="${root}/target.service"
        rmLog="${root}/rm.log"
        printf 'unit\n' >"${target}"
        : >"${rmLog}"

        rm() {
            printf '%s\n' "$*" >>"${rmLog}"
            command rm "$@"
        }

        removeInstallPath "${target}" "服务文件"
        [[ ! -e "${target}" ]]
        grep -qxF -- "-f -- ${target}" "${rmLog}"
        ! grep -q -- "-rf ${target}" "${rmLog}"
    )
}

runUninstallPadmRootScopeRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local rootRel="${TMP_DIR}/remove-install-path-padm-root-scope"
        local root
        local padmRoot
        local rmLog
        local serviceLog
        local errorLog
        local successLog
        mkdir -p "${rootRel}/etc/padm/xray/conf" "${rootRel}/etc/padm/custom"
        root=$(cd -- "${rootRel}" && pwd -P)
        padmRoot="${root}/etc/padm"
        rmLog="${root}/rm.log"
        serviceLog="${root}/service.log"
        errorLog="${root}/error.log"
        successLog="${root}/success.log"
        printf 'managed\n' >"${padmRoot}/xray/conf/00_log.json"
        printf 'keep\n' >"${padmRoot}/custom/keep"
        : >"${rmLog}"
        : >"${serviceLog}"
        : >"${errorLog}"
        : >"${successLog}"

        PADM_INSTALL_DIR="${padmRoot}"
        PADM_SUBSCRIPTION_GROUPS_DIR="${padmRoot}/subscribe_groups"
        PADM_SUBSCRIBE_LOCAL_DIR="${padmRoot}/subscribe_local"
        PADM_SUBSCRIBE_DIR="${padmRoot}/subscribe"
        PADM_REALITY_TARGET_RESULTS_FILE="${padmRoot}/reality_targets_results.tsv"
        PADM_REALITY_TARGET_BLOCKED_FILE="${padmRoot}/reality_target_blocked.tsv"
        PADM_REALITY_ENTRY_HOST_FILE="${padmRoot}/reality_entry_host"
        PADM_VLESS_ENCRYPTION_STATE_FILE="${padmRoot}/vless_encryption.json"
        PADM_WARP_DIR="${padmRoot}/warp"
        REGRESSION_ERROR_CARD_LOG="${errorLog}"
        REGRESSION_SUCCESS_CARD_LOG="${successLog}"

        rm() {
            printf '%s\n' "$*" >>"${rmLog}"
            command rm "$@"
        }

        autoRead() { printf -v "$3" 'y'; }
        menu() { return 0; }
        pgrep() { return 1; }
        runCoreServiceActionAllowFailure() {
            printf '%s:%s\n' "$1" "$2" >>"${serviceLog}"
            return 0
        }
        systemctl() {
            printf 'systemctl:%s\n' "$*" >>"${serviceLog}"
            return 0
        }
        cleanupSubscriptionWireGuardControlOnUninstall() { return 0; }
        cleanupFail2banManagedFilesOnUninstall() { return 0; }
        removePadmNginxConfigFragments() { return 0; }
        unInstallSubscribe() { return 0; }

        release=centos
        coreInstallType=1
        singBoxConfigPath=
        nginxStaticPath="${root}/static"

        unInstall >/dev/null
        [[ ! -e "${padmRoot}/xray/conf/00_log.json" ]]
        [[ -f "${padmRoot}/custom/keep" ]]
        ! grep -qxF -- "-rf ${padmRoot}" "${rmLog}"
        grep -qx 'handleNginx:stop' "${serviceLog}"
        grep -qx 'handleXray:stop' "${serviceLog}"
        [[ ! -s "${errorLog}" ]]
    )
}

runRemoveInstallPathSafetyRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local rootRel="${TMP_DIR}/remove-install-path-safety"
        local root
        local safeTarget
        local errorLog
        local status
        mkdir -p "${rootRel}/safe-target" "${rootRel}/cwd"
        root=$(cd -- "${rootRel}" && pwd -P)
        safeTarget="${root}/safe-target"
        errorLog="${root}/errors.log"
        printf 'safe\n' >"${safeTarget}/file"
        printf 'keep\n' >"${root}/cwd/sentinel"
        : >"${errorLog}"
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        (
            cd "${root}/cwd"
            set +e
            removeInstallPath "." "当前目录"
            status=$?
            set -e
            [[ "${status}" -ne 0 ]]
            [[ -f sentinel ]]
            set +e
            removeInstallPath ".." "父目录"
            status=$?
            set -e
            [[ "${status}" -ne 0 ]]
            [[ -f sentinel ]]
            set +e
            removeInstallPath "relative" "相对目录"
            status=$?
            set -e
            [[ "${status}" -ne 0 ]]
            [[ -f sentinel ]]
        )
        removeInstallPath "${safeTarget}" "安全目标"
        [[ ! -e "${safeTarget}" ]]
        grep -q '路径异常' "${errorLog}"
    )
}

runInstallRefreshRestoresBackupRegression() {
    local fixtureDir archiveRoot outputLog archiveDirName refreshTmpRoot oldTmpDir restoreFailureDir restoreFailureArchiveRoot restoreFailureOutputLog restoreFailureTmpRoot
    fixtureDir="${TMP_DIR}/install-refresh-restore"
    archiveDirName="padm-main"
    mkdir -p "${fixtureDir}"
    archiveRoot="${fixtureDir}/archive/${archiveDirName}"
    outputLog="${fixtureDir}/refresh.log"
    refreshTmpRoot="${fixtureDir}/tmp"
    restoreFailureDir="${TMP_DIR}/install-refresh-restore-failure"
    mkdir -p "${restoreFailureDir}"
    restoreFailureArchiveRoot="${restoreFailureDir}/archive/${archiveDirName}"
    restoreFailureOutputLog="${restoreFailureDir}/refresh.log"
    restoreFailureTmpRoot="${restoreFailureDir}/tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/assets" "${archiveRoot}/shell" "${archiveRoot}/documents" "${archiveRoot}/assets" "${refreshTmpRoot}"
    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${fixtureDir}/install.sh"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-doc\n' >"${fixtureDir}/documents/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    command cp "${fixtureDir}/install.sh" "${archiveRoot}/install.sh"
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
        scriptIsSafeAbsolutePath() { return 0; }
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
        refreshScriptModules 5555555555555555555555555555555555555555
    ) >"${outputLog}" 2>&1
    grep -q '完整安装包替换失败，已恢复旧模块' "${outputLog}"
    [[ "$(<"${fixtureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/documents/marker")" == "old-doc" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]

    mkdir -p "${restoreFailureDir}/shell" "${restoreFailureDir}/documents" "${restoreFailureDir}/assets" "${restoreFailureArchiveRoot}/shell" "${restoreFailureArchiveRoot}/documents" "${restoreFailureArchiveRoot}/assets" "${restoreFailureTmpRoot}"
    printf '#!/usr/bin/env bash\nprintf "old-entry\\n"\n' >"${restoreFailureDir}/install.sh"
    printf 'old-shell\n' >"${restoreFailureDir}/shell/marker"
    printf 'old-doc\n' >"${restoreFailureDir}/documents/marker"
    printf 'old-readme\n' >"${restoreFailureDir}/README.md"
    command cp "${restoreFailureDir}/install.sh" "${restoreFailureArchiveRoot}/install.sh"
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
        scriptIsSafeAbsolutePath() { return 0; }
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
        refreshScriptModules 5555555555555555555555555555555555555555
    ) >"${restoreFailureOutputLog}" 2>&1
    grep -q '完整安装包替换失败，旧模块恢复失败，请手动检查备份目录' "${restoreFailureOutputLog}"
    [[ "$(<"${restoreFailureDir}/install.sh")" == $'#!/usr/bin/env bash\nprintf "old-entry\\n"' ]]
    [[ -d "${restoreFailureDir}/.padm-update-backup" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshSignalRestoresAndExitsRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/install-refresh-signal"
    local fixtureDir="${root}/target"
    local archiveRoot="${root}/archive/padm-main"
    local oldTmpDir="${TMPDIR:-}"
    local status

    mkdir -p \
        "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/assets" "${root}/tmp" \
        "${archiveRoot}/shell" "${archiveRoot}/documents" "${archiveRoot}/assets"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-docs\n' >"${fixtureDir}/documents/marker"
    printf 'old-assets\n' >"${fixtureDir}/assets/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    command cp "${fixtureDir}/install.sh" "${archiveRoot}/install.sh"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'new-docs\n' >"${archiveRoot}/documents/marker"
    printf 'new-assets\n' >"${archiveRoot}/assets/marker"
    printf 'new-readme\n' >"${archiveRoot}/README.md"

    TMPDIR="${root}/tmp"
    eval "$(awk '
        /^scriptTmpPath\(\)/ { capture = 1 }
        /^ensureScriptModules\(\)/ { capture = 0 }
        capture { print }
    ' "${PROJECT_ROOT}/install.sh")"
    SCRIPT_DIR="${fixtureDir}"
    REPO_ARCHIVE_DIR=padm-main
    SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
    SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
    SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
    scriptIsSafeAbsolutePath() { return 0; }
    downloadRepoArchive() {
        local _url=$1
        local extractDir=$2
        mkdir -p "${extractDir}"
        command cp -R "${archiveRoot}" "${extractDir}/padm-main"
    }
    cp() {
        if [[ "${1:-}" == "-R" && "${2:-}" == */extract/padm-main/shell ]]; then
            kill -TERM "${BASHPID:-$$}"
            printf 'continued\n' >"${root}/continued"
        fi
        command cp "$@"
    }

    set +e
    ( refreshScriptModules 7777777777777777777777777777777777777777 ) >"${root}/output.log" 2>&1
    status=$?
    set -e

    [[ "${status}" == "143" ]]
    [[ ! -e "${root}/continued" ]]
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/documents/marker")" == "old-docs" ]]
    [[ "$(<"${fixtureDir}/assets/marker")" == "old-assets" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]
    [[ ! -e "${fixtureDir}/.padm-update-backup" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runInstallModuleLockSerializesLoadRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/install-module-lock"
    local firstReady="${root}/first-ready"
    local releaseFirst="${root}/release-first"
    local secondReady="${root}/second-ready"
    local firstPid secondPid

    mkdir -p "${root}"
    eval "$(awk '
        /^scriptTmpPath\(\)/ { capture = 1 }
        /^scriptDownloadUrlToFileBounded\(\)/ { capture = 0 }
        capture { print }
    ' "${PROJECT_ROOT}/install.sh")"
    SCRIPT_MODULE_LOCK_DIR="${root}/lock"
    scriptIsSafeAbsolutePath() { return 0; }

    (
        scriptModuleLockAcquire
        : >"${firstReady}"
        while [[ ! -e "${releaseFirst}" ]]; do sleep 0.05; done
        scriptModuleLockRelease
    ) &
    firstPid=$!
    while [[ ! -e "${firstReady}" ]]; do sleep 0.05; done

    (
        scriptModuleLockAcquire
        : >"${secondReady}"
        scriptModuleLockRelease
    ) &
    secondPid=$!
    sleep 0.2
    [[ ! -e "${secondReady}" ]]
    : >"${releaseFirst}"
    wait "${firstPid}"
    wait "${secondPid}"
    [[ -e "${secondReady}" && ! -e "${SCRIPT_MODULE_LOCK_DIR}" ]]
)

runInstallRefreshRejectsEntryMismatchRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/install-refresh-entry-mismatch"
    local fixtureDir="${root}/target"
    local archiveRoot="${root}/archive/padm-main"
    local oldTmpDir="${TMPDIR:-}"

    mkdir -p \
        "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/assets" "${root}/tmp" \
        "${archiveRoot}/shell" "${archiveRoot}/documents" "${archiveRoot}/assets"
    printf '#!/usr/bin/env bash\nprintf old\n' >"${fixtureDir}/install.sh"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    printf '#!/usr/bin/env bash\nprintf new\n' >"${archiveRoot}/install.sh"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'new-readme\n' >"${archiveRoot}/README.md"

    set +e
    (
        TMPDIR="${root}/tmp"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_PATH="${fixtureDir}/install.sh"
        SCRIPT_DIR="${fixtureDir}"
        REPO_ARCHIVE_DIR=padm-main
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        scriptIsSafeAbsolutePath() { return 0; }
        downloadRepoArchive() { command cp -R "${archiveRoot}" "$2/padm-main"; }
        refreshScriptModules 8888888888888888888888888888888888888888
    ) >"${root}/output.log" 2>&1
    local status=$?
    set -e

    [[ "${status}" -ne 0 ]]
    grep -q '入口脚本与完整安装包版本不一致' "${root}/output.log"
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ ! -e "${fixtureDir}/.padm-ref" && ! -e "${fixtureDir}/.padm-entry-ref" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runInstallRefreshRefCommitRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/install-refresh-ref-rollback"
    local fixtureDir="${root}/target"
    local archiveRoot="${root}/archive/padm-main"
    local oldTmpDir="${TMPDIR:-}"
    local newRef=9999999999999999999999999999999999999999

    mkdir -p \
        "${fixtureDir}/shell" "${fixtureDir}/documents" "${fixtureDir}/assets" "${root}/tmp" \
        "${archiveRoot}/shell" "${archiveRoot}/documents" "${archiveRoot}/assets"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    command cp "${fixtureDir}/install.sh" "${archiveRoot}/install.sh"
    printf 'old-shell\n' >"${fixtureDir}/shell/marker"
    printf 'old-readme\n' >"${fixtureDir}/README.md"
    printf 'old-manifest\n' >"${fixtureDir}/.padm-module-manifest"
    printf '1111111111111111111111111111111111111111\n' >"${fixtureDir}/.padm-ref"
    printf '1111111111111111111111111111111111111111\n' >"${fixtureDir}/.padm-entry-ref"
    printf 'new-shell\n' >"${archiveRoot}/shell/marker"
    printf 'new-readme\n' >"${archiveRoot}/README.md"

    set +e
    (
        TMPDIR="${root}/tmp"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        REPO_ARCHIVE_DIR=padm-main
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        scriptIsSafeAbsolutePath() { return 0; }
        downloadRepoArchive() { command cp -R "${archiveRoot}" "$2/padm-main"; }
        writeModuleManifest() { printf 'new-manifest\n' >"$1"; }

        writeScriptModuleRefs "${newRef}"
        [[ "$(<"${SCRIPT_REF_FILE}")" == "${newRef}" ]]
        [[ "$(<"${SCRIPT_EXPECTED_REF_FILE}")" == "${newRef}" ]]
        printf '1111111111111111111111111111111111111111\n' >"${SCRIPT_REF_FILE}"
        printf '1111111111111111111111111111111111111111\n' >"${SCRIPT_EXPECTED_REF_FILE}"
        writeScriptModuleRefs() { printf '%s\n' "$1" >"${SCRIPT_REF_FILE}"; return 1; }

        refreshScriptModules "${newRef}"
    ) >"${root}/output.log" 2>&1
    local status=$?
    set -e

    [[ "${status}" -ne 0 ]]
    grep -q '完整安装包替换失败，已恢复旧模块' "${root}/output.log"
    [[ "$(<"${fixtureDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${fixtureDir}/README.md")" == "old-readme" ]]
    [[ "$(<"${fixtureDir}/.padm-module-manifest")" == "old-manifest" ]]
    [[ "$(<"${fixtureDir}/.padm-ref")" == "1111111111111111111111111111111111111111" ]]
    [[ "$(<"${fixtureDir}/.padm-entry-ref")" == "1111111111111111111111111111111111111111" ]]
    [[ ! -e "${fixtureDir}/.padm-update-backup" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runInstallRefreshSingleArchiveGuardRegression() {
    local archiveGuard
    archiveGuard=$(awk '
        /^refreshScriptModules\(\)/ { capture = 1 }
        /^ensureScriptModules\(\)/ { capture = 0 }
        capture && /! -d "\$\{archiveDir\}\/shell"/ { guard = 1 }
        capture && /! -d "\$\{archiveDir\}\/documents"/ { documents = 1 }
        capture && /! -d "\$\{archiveDir\}\/assets"/ { assets = 1 }
        capture && /! -f "\$\{archiveDir\}\/README.md"/ { readme = 1 }
        END { print guard ":" documents ":" assets ":" readme }
    ' "${PROJECT_ROOT}/install.sh")
    [[ "${archiveGuard}" == "1:1:1:1" ]]
}

runNoThirdPartyQrServiceRegression() {
    ! grep -R "api.qrserver.com" \
        "${PROJECT_ROOT}/shell/core" \
        "${PROJECT_ROOT}/shell/subscription"
}

runInstallRefreshDownloadBoundsRegression() (
    set -euo pipefail

    local root="${TMP_DIR}/install-refresh-download-bounds"
    local archiveRoot="${root}/archive"
    local curlLog="${root}/curl.log"
    local wgetLog="${root}/wget.log"
    local oldTmpDir="${TMPDIR:-}"

    mkdir -p "${archiveRoot}/padm-main/shell/core" "${root}/tmp"
    printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/install.sh"
    printf '# bootstrap fixture\n' >"${archiveRoot}/padm-main/shell/core/bootstrap.sh"
    printf '#!/usr/bin/env bash\n' >"${archiveRoot}/padm-main/shell/validate_install.sh"

    TMPDIR="${root}/tmp"
    eval "$(awk '
        /^scriptTmpPath\(\)/ { capture = 1 }
        /^ensureScriptModules\(\)/ { capture = 0 }
        capture { print }
    ' "${PROJECT_ROOT}/install.sh")"

    command() {
        if [[ "$1" == "-v" && "$2" == "curl" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    curl() {
        local outputFile=
        printf '%s\n' "$*" >"${curlLog}"
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == "-o" && $# -ge 2 ]]; then
                outputFile=$2
                break
            fi
            shift
        done
        [[ -n "${outputFile}" ]] || return 1
        tar -cz -C "${archiveRoot}" padm-main >"${outputFile}"
    }
    downloadRepoArchive "https://example.invalid/padm.tar.gz" "${root}/curl-extract"
    grep -q -- '--connect-timeout' "${curlLog}"
    grep -q -- '--max-time' "${curlLog}"
    grep -q -- '--max-filesize' "${curlLog}"

    command() {
        if [[ "$1" == "-v" && "$2" == "curl" ]]; then
            return 1
        fi
        if [[ "$1" == "-v" && "$2" == "wget" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    wget() {
        printf '%s\n' "$*" >"${wgetLog}"
        tar -cz -C "${archiveRoot}" padm-main
    }
    downloadRepoArchive "https://example.invalid/padm.tar.gz" "${root}/wget-extract"
    grep -q -- '-T' "${wgetLog}"
    grep -q -- '-t' "${wgetLog}"
    grep -q -- '-qO-' "${wgetLog}"

    wget() { head -c 32 /dev/zero; }
    if scriptDownloadUrlToFileBounded "https://example.invalid/oversized" "${root}/oversized" 16; then
        return 1
    fi
    [[ "$(wc -c <"${root}/oversized" | tr -d ' ')" == "17" ]]

    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runRemoteControlSystemctlStubDefaultStopDisableRegression() {
    local explicitStopDisableCount
    explicitStopDisableCount=$(awk '
        /runSubscriptionControlServiceInstallRegression\(\) \(/ { capture = 1 }
        capture && /cat >"\$\{fakeBin\}\/systemctl" <<'SH'/ { in_stub = 1 }
        in_stub && /^stop\)$/ { count++ }
        in_stub && /^disable\)$/ { count++ }
        in_stub && /^SH$/ { in_stub = 0; capture = 0 }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/regression/subscription_groups_legacy.sh")
    [[ "${explicitStopDisableCount}" == "0" ]]
}

runRegressionFastParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-parallel-composition.log"

    runRegressionPlatform() {
        printf 'platform-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-started" ]]; do
            sleep 0.05
        done
        printf 'platform-finish\n' >>"${callLog}"
    }
    runRegressionFastOnly() {
        printf 'fast-only-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-started"
        printf 'fast-only-finish\n' >>"${callLog}"
    }

    runRegressionFast
    grep -qx 'platform-start' "${callLog}"
    grep -qx 'fast-only-start' "${callLog}"
    awk '
        $0 == "platform-start" { platformStart = NR }
        $0 == "fast-only-start" { fastOnlyStart = NR }
        $0 == "platform-finish" { platformFinish = NR }
        END { exit !(platformStart && fastOnlyStart && platformFinish && fastOnlyStart < platformFinish) }
    ' "${callLog}"
)

runRegressionFastOnlyParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-only-parallel-composition.log"

    runRegressionFastOnlySafety() {
        printf 'safety-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-output-started" ]]; do
            sleep 0.05
        done
        printf 'safety-finish\n' >>"${callLog}"
    }
    runRegressionFastOnlyOutput() {
        printf 'output-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-output-started"
        printf 'output-finish\n' >>"${callLog}"
    }
    runRegressionFastOnlyCore() {
        printf 'core\n' >>"${callLog}"
    }

    runRegressionFastOnly
    grep -qx 'safety-start' "${callLog}"
    grep -qx 'output-start' "${callLog}"
    awk '
        $0 == "safety-start" { safetyStart = NR }
        $0 == "output-start" { outputStart = NR }
        $0 == "safety-finish" { safetyFinish = NR }
        END { exit !(safetyStart && outputStart && safetyFinish && outputStart < safetyFinish) }
    ' "${callLog}"
)

runRegressionFastOnlyOutputParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-fast-only-output-parallel-composition.log"

    runRegressionFastOnlyOutputAutoInstall() {
        printf 'auto-install-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/fast-only-subscription-started" ]]; do
            sleep 0.05
        done
        printf 'auto-install-finish\n' >>"${callLog}"
    }
    runRegressionFastOnlyOutputRest() {
        printf 'rest-start\n' >>"${callLog}"
        : >"${TMP_DIR}/fast-only-subscription-started"
        printf 'rest-finish\n' >>"${callLog}"
    }

    runRegressionFastOnlyOutput
    grep -qx 'auto-install-start' "${callLog}"
    grep -qx 'rest-start' "${callLog}"
    awk '
        $0 == "auto-install-start" { autoInstallStart = NR }
        $0 == "rest-start" { restStart = NR }
        $0 == "auto-install-finish" { autoInstallFinish = NR }
        END { exit !(autoInstallStart && restStart && autoInstallFinish && restStart < autoInstallFinish) }
    ' "${callLog}"
)

runRegressionPlatformHotParallelCompositionRegression() (
    set -euo pipefail
    local callLog="${TMP_DIR}/regression-platform-hot-parallel-composition.log"

    runRegressionPlatformUpdate() {
        printf 'update-start\n' >>"${callLog}"
        while [[ ! -f "${TMP_DIR}/platform-refresh-started" ]]; do
            sleep 0.05
        done
        printf 'update-finish\n' >>"${callLog}"
    }
    runRegressionPlatformRefresh() {
        printf 'refresh-start\n' >>"${callLog}"
        : >"${TMP_DIR}/platform-refresh-started"
        printf 'refresh-finish\n' >>"${callLog}"
    }
    runRegressionPlatformRest() {
        printf 'rest\n' >>"${callLog}"
    }

    runRegressionPlatform
    grep -qx 'update-start' "${callLog}"
    grep -qx 'refresh-start' "${callLog}"
    awk '
        $0 == "update-start" { updateStart = NR }
        $0 == "refresh-start" { refreshStart = NR }
        $0 == "update-finish" { updateFinish = NR }
        END { exit !(updateStart && refreshStart && updateFinish && refreshStart < updateFinish) }
    ' "${callLog}"
)

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

runSubscriptionMenuDeadEntryCountRegression() {
    local deadEntryCount
    deadEntryCount=$(awk '
        /^(manageAdminSubscription|manageUserSubscription|manageSubscriptionWireGuardControlMenu|showSubscriptionDiagnosticsOverview)\(\) \{/ { count++ }
        END { print count + 0 }
    ' "${PROJECT_ROOT}/shell/subscription/menu.sh")
    [[ "${deadEntryCount}" == "0" ]]
}

runUnusedHelperFunctionCountRegression() {
    local helperCount
    helperCount=$(
        {
            awk '/^(check_apt_update)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/validate_install.sh"
            awk '/^(check_nginx)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/validate_install.sh"
            awk '/^(subscriptionRequireMainFeatures)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/menu.sh"
            awk '/^(subscriptionMainFeaturesAvailable|remoteSubscribeFile|toggleSubscriptionSourceMenu|showSubscriptionMultiServerStatus|showSubscriptionOperationsStatus|showSubscriptionControlledStatusOverview|showSubscriptionControlledControlDetails|subscriptionServiceConfigured|syncAndShowUserSubscriptionLinks|removeSubscriptionGroupSyncCron|subscriptionGroupSyncCronStatus|userJsonCard)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/menu.sh"
            awk '/^(showUserSubscriptionQuota)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/traffic.sh"
            awk '/^(xrayRealityXHTTPConfigFile)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/output.sh"
            awk '/^(testSubscriptionWireGuardControl|subscriptionWireGuardDefaultMainAddress|subscriptionWireGuardDefaultNetwork|subscriptionWireGuardInstalled)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
            awk '/^(subscriptionControlHealthRetryCount|subscriptionControlHealthRetryDelay)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/control.sh"
            awk '/^(subscriptionSyncAccountPrefix)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/sync.sh"
            awk '/^(protocolSelectionNeedsNginx|protocolSelectionNeedsReality|protocolSelectionNeedsUdp|protocolSelectionTransportHas|protocolSelectionSecurityHas|xrayProtocolFilename|xrayProtocolMenuLine|currentProtocolHasAll|protocolSelectionNeedsTLS|xrayProtocolIdByFilename|xrayProtocolEnabled|xrayProtocolDisplayName|xrayEnabledProtocolDisplayList|xrayProtocolCapability|protocolSelectionHasAll)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/protocols.sh"
            awk '/^(getDLCNameByRuleLine)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/routing_rules.sh"
            awk '/^(unInstallSniffing)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/routing_rules.sh"
            awk '/^(cleanXrayGeoFiles|coreSingBoxCompatTempDirTemplate|coreXrayCompatTempDirTemplate|singBoxCompatibilityConfigFiles|xrayCompatibilityConfigFiles|coreAlpineInitTemplate|coreSingBoxServiceTemplate|coreXrayServiceTemplate|coreXrayConfigTestLog|coreXrayStrictConfigTestLog|coreXrayUpgradeTestLog|coreXrayPrereleaseAuditLog|coreSingBoxConfigTestLog|coreSingBoxUpgradeTestLog|coreSingBoxPrereleaseAuditLog|getXrayCurrentVersion|updateXray)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/cores.sh"
            awk '/^(disableRunningService|handleFirewall)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/services.sh"
            awk '/^(singBoxDnsHostsTag|singBoxDnsRoutingTag|singBoxDnsResolverTag)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/routing_dns.sh"
            awk '/^(checkRealityDest|initTCPBrutal)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"
            awk '/^(realityTargetBlockedCandidateCount|realityTargetBlockedCandidateLineByIndex|realityTargetScanFile|realityTargetRecentlyFailed|realityTargetScanResultCount|realityTargetScanLineByIndex|realityTargetScanField|showRealityTargetCandidates|selectRealityTargetFromCandidates|realityScannerDir|realityTargetBlockedCandidatesFile|realityTargetResultsFile)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/reality_targets.sh"
            awk '/^(realityTargetImportScannerCandidates|writeRealityTargetScanLine|realityAsnPrefixTotalAddressCount|filterRealityAsnPrefixesByMask|realityTargetCachedLine|selectRealityAsnPrefixSet|realityTargetXrayTestLog|realityTargetSingBoxTestLog)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/reality_targets.sh"
            awk '/^(realityTargetCandidateExists|writeRealityTargetCandidateLine|realityTargetCacheFile|realityTargetResultLineByIndex|realityTargetResultLineByTargetIp|realityAsnPrefixAddressCount|realityTargetApplyLog|realityTargetBackupTemplate)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/reality_targets.sh"
            awk '/^(realityAsnPrefixMask)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/reality_targets.sh"
            awk '/^(normalizeSubscriptionSourceInput)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/subscription/menu.sh"
            awk '/^(initSingBoxHysteria2Config)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/singbox.sh"
            awk '/^(menuTitle|infoCard)\(\) \{/ { count++ } END { print count + 0 }' "${PROJECT_ROOT}/shell/core/locale.sh"
        } | awk '{ sum += $1 } END { print sum + 0 }'
    )
    [[ "${helperCount}" == "0" ]]
}

runLegacyUsersModuleRemovedRegression() {
    [[ ! -e "${PROJECT_ROOT}/shell/core/users.sh" ]]
    ! grep -q 'source "${CORE_DIR}/users.sh"' "${PROJECT_ROOT}/shell/core/bootstrap.sh"
    ! grep -q 'source "${PROJECT_ROOT}/shell/core/users.sh"' "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
}

runInstallEnsureModulesRegression() {
    local fixtureDir marker
    local latestRef=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    local expectedRef=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
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
    unset PADM_SKIP_REMOTE_REF_CHECK
    refreshScriptModules() {
        printf '%s\n' "$1" >"${marker}"
        printf '%s\n' "$1" >"${SCRIPT_REF_FILE}"
        printf '%s\n' "$1" >"${SCRIPT_EXPECTED_REF_FILE}"
        mkdir -p "${SCRIPT_DIR}/shell/core"
        touch "${SCRIPT_DIR}/shell/core/bootstrap.sh"
    }
    fetchRemoteRef() { return 1; }
    if regressionEnsureScriptModules; then
        return 1
    fi
    [[ ! -e "${marker}" ]] || return 1

    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    if regressionEnsureScriptModules; then
        return 1
    fi
    [[ ! -e "${marker}" ]] || return 1

    rm -f "${marker}"
    mkdir -p "${fixtureDir}/shell/core"
    touch "${fixtureDir}/shell/core/bootstrap.sh"
    fetchRemoteRef() { printf 'new-ref\n'; }
    if regressionEnsureScriptModules; then
        return 1
    fi
    [[ ! -e "${marker}" ]] || return 1

    fetchRemoteRef() { printf '%s\n' "${latestRef}"; }
    regressionEnsureScriptModules || return 1
    [[ -f "${marker}" && "$(<"${marker}")" == "${latestRef}" ]] || return 1
    [[ -f "${SCRIPT_EXPECTED_REF_FILE}" && "$(<"${SCRIPT_EXPECTED_REF_FILE}")" == "${latestRef}" ]] || return 1

    printf 'manifest-ok\n' >"${fixtureDir}/.padm-module-manifest"
    PADM_FAKE_MODULE_MANIFEST_READY=1
    rm -f "${marker}"
    regressionEnsureScriptModules || return 1
    [[ ! -e "${marker}" ]] || return 1

    printf '%s\n' "${expectedRef}" >"${fixtureDir}/.padm-entry-ref"
    printf '%s\n' "${latestRef}" >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    regressionEnsureScriptModules || return 1
    [[ -f "${marker}" && "$(<"${marker}")" == "${expectedRef}" ]] || return 1

    printf '%s\n' "${expectedRef}" >"${fixtureDir}/.padm-entry-ref"
    printf '%s\n' "${expectedRef}" >"${fixtureDir}/.padm-ref"
    rm -f "${marker}"
    PADM_SKIP_REMOTE_REF_CHECK=1
    if PADM_FAKE_MODULE_MANIFEST_READY=0 regressionEnsureScriptModules; then
        return 1
    fi
    [[ ! -e "${marker}" ]] || return 1

    unset PADM_FAKE_MODULE_MANIFEST_READY
    unset PADM_SKIP_REMOTE_REF_CHECK
    rm -f "${fixtureDir}/.padm-module-manifest"

    rm -f "${marker}" "${fixtureDir}/.padm-entry-ref"
    rm -f "${fixtureDir}/shell/core/bootstrap.sh"
    regressionEnsureScriptModules || return 1
    [[ -f "${marker}" && "$(<"${marker}")" == "${latestRef}" ]] || return 1

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

runInstallEnsureModulesRejectsProtectedWorktreeRegression() {
    local fixtureDir marker errorLog oldTmpDir
    fixtureDir="${TMP_DIR}/install-entry-protected-worktree"
    marker="${fixtureDir}/refresh-called"
    errorLog="${fixtureDir}/errors.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${fixtureDir}/shell/core" "${fixtureDir}/tmp" "${fixtureDir}/.git"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    cat >"${fixtureDir}/shell/core/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
source "${CORE_DIR}/version.sh"
EOF
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/core/version.sh"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/validate_install.sh"
    printf 'deadbeef  install.sh\n' >"${fixtureDir}/.padm-module-manifest"
    printf 'old-ref\n' >"${fixtureDir}/.padm-ref"
    : >"${errorLog}"

    (
        set +e
        TMPDIR="${fixtureDir}/tmp"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^loadScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        PADM_REGRESSION_PROTECT_WORKTREE=1
        PADM_REGRESSION_WORKTREE_ROOT="${fixtureDir}"
        refreshScriptModules() {
            printf '%s\n' "$1" >"${marker}"
            return 0
        }
        fetchRemoteRef() { printf 'new-ref\n'; }

        ensureScriptModules
    ) >"${fixtureDir}/stdout.log" 2>"${errorLog}" && return 1

    [[ ! -e "${marker}" ]]
    grep -q '回归工作区' "${errorLog}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallRefreshRejectsProtectedWorktreeRegression() {
    local fixtureDir outputLog oldTmpDir
    fixtureDir="${TMP_DIR}/install-refresh-protected-worktree"
    outputLog="${fixtureDir}/refresh.log"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${fixtureDir}/shell" "${fixtureDir}/tmp" "${fixtureDir}/.git"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    printf 'keep\n' >"${fixtureDir}/shell/marker"

    (
        set +e
        TMPDIR="${fixtureDir}/tmp"
        eval "$(awk '
            /^scriptTmpPath\(\)/ { capture = 1 }
            /^ensureScriptModules\(\)/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        SCRIPT_DIR="${fixtureDir}"
        SCRIPT_REF_FILE="${fixtureDir}/.padm-ref"
        SCRIPT_EXPECTED_REF_FILE="${fixtureDir}/.padm-entry-ref"
        SCRIPT_MANIFEST_FILE="${fixtureDir}/.padm-module-manifest"
        PADM_REGRESSION_PROTECT_WORKTREE=1
        PADM_REGRESSION_WORKTREE_ROOT="${fixtureDir}"
        refreshScriptModules 6666666666666666666666666666666666666666
    ) >"${outputLog}" 2>&1 && return 1

    grep -q '回归工作区' "${outputLog}"
    [[ "$(<"${fixtureDir}/shell/marker")" == "keep" ]]
    [[ ! -e "${fixtureDir}/.padm-update-backup" ]]
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runRegressionFrameworkExportsProtectedWorktreeEnvRegression() (
    unset PADM_REGRESSION_FRAMEWORK_ENV_LOADED
    unset PADM_REGRESSION_PROTECT_WORKTREE
    unset PADM_REGRESSION_WORKTREE_ROOT
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT}/shell/regression/framework/env.sh"
    [[ "${PADM_REGRESSION_PROTECT_WORKTREE}" == "1" ]]
    [[ "${PADM_REGRESSION_WORKTREE_ROOT}" == "${PROJECT_ROOT}" ]]
)
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

runAliasInstallRejectsUnsafeTargetRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/alias-install-unsafe-target"
        local sourceDir="${root}/source"
        local targetDir="${root}/unsafe-target"
        mkdir -p "${sourceDir}/shell" "${sourceDir}/documents" "${sourceDir}/assets" "${targetDir}/shell"
        cat >"${sourceDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF
        printf 'keep\n' >"${targetDir}/shell/sentinel"

        local oldScriptDir="${SCRIPT_DIR:-}"
        local oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
        local oldHome="${HOME:-}"
        SCRIPT_DIR="${sourceDir}"
        PADM_INSTALL_DIR="unsafe-target"
        HOME="${root}/home"
        mkdir -p "${HOME}"
        cd "${root}"

        (
            cp() { :; }
            chmod() { :; }
            ln() { :; }
            ! aliasInstall
        )

        [[ -f "${targetDir}/shell/sentinel" ]]

        SCRIPT_DIR="${oldScriptDir}"
        HOME="${oldHome}"
        if [[ -n "${oldPadmInstallDir}" ]]; then
            PADM_INSTALL_DIR="${oldPadmInstallDir}"
        else
            unset PADM_INSTALL_DIR
        fi
    )
}

runAliasInstallRejectsUnsafeHomeFallbackRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/alias-install-unsafe-home"
        local sourceDir="${root}/source"
        local targetDir="${root}/target"
        mkdir -p "${sourceDir}" "${targetDir}"
        cat >"${root}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF

        local oldScriptDir="${SCRIPT_DIR:-}"
        local oldPadmInstallDir="${PADM_INSTALL_DIR:-}"
        local oldHome="${HOME:-}"
        SCRIPT_DIR="${sourceDir}"
        PADM_INSTALL_DIR="${targetDir}"
        HOME="."
        cd "${root}"

        (
            cp() { :; }
            chmod() { :; }
            ln() { :; }
            aliasInstall || true
        )

        [[ -f "${root}/install.sh" ]]

        SCRIPT_DIR="${oldScriptDir}"
        if [[ -n "${oldPadmInstallDir}" ]]; then
            PADM_INSTALL_DIR="${oldPadmInstallDir}"
        else
            unset PADM_INSTALL_DIR
        fi
        if [[ -n "${oldHome}" ]]; then
            HOME="${oldHome}"
        else
            unset HOME
        fi
    )
}

runInstallModulePathsRegression() {
    local outputList moduleTmpRoot fixtureDir oldTmpDir moduleListBefore moduleListAfter
    outputList="${TMP_DIR}/install-module-paths.txt"
    moduleTmpRoot="${TMP_DIR}/install-module-paths-tmp"
    fixtureDir="${TMP_DIR}/install-entry-manifest"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${moduleTmpRoot}" "${fixtureDir}/shell/core" "${fixtureDir}/documents" "${fixtureDir}/assets"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    printf 'fixture\n' >"${fixtureDir}/README.md"
    printf 'document\n' >"${fixtureDir}/documents/template.json"
    printf 'asset\n' >"${fixtureDir}/assets/template.txt"
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
    grep -q '^README\.md$' "${outputList}"
    grep -q '^documents/' "${outputList}"
    grep -q '^assets/' "${outputList}"
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

runInstallModuleManifestCompleteRegression() {
    local fixtureDir moduleTmpRoot oldTmpDir
    fixtureDir="${TMP_DIR}/install-module-manifest-complete"
    moduleTmpRoot="${TMP_DIR}/install-module-manifest-complete-tmp"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${moduleTmpRoot}" "${fixtureDir}/shell/core" "${fixtureDir}/documents" "${fixtureDir}/assets"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    printf 'fixture\n' >"${fixtureDir}/README.md"
    printf 'document\n' >"${fixtureDir}/documents/template.json"
    printf 'asset\n' >"${fixtureDir}/assets/template.txt"
    cat >"${fixtureDir}/shell/core/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
source "${CORE_DIR}/version.sh"
EOF
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/core/version.sh"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/validate_install.sh"
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
        awk '$2 != "shell/core/version.sh"' "${SCRIPT_MANIFEST_FILE}" >"${SCRIPT_MANIFEST_FILE}.tmp"
        mv "${SCRIPT_MANIFEST_FILE}.tmp" "${SCRIPT_MANIFEST_FILE}"
        ! scriptModulesReady >/dev/null
    )
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runInstallModuleManifestRequiresSha256Regression() {
    local fixtureDir moduleTmpRoot oldPath oldTmpDir
    fixtureDir="${TMP_DIR}/install-module-manifest-requires-sha256"
    moduleTmpRoot="${TMP_DIR}/install-module-manifest-requires-sha256-tmp"
    oldPath="${PATH}"
    oldTmpDir="${TMPDIR:-}"
    mkdir -p "${moduleTmpRoot}" "${fixtureDir}/missing-bin" "${fixtureDir}/shell/core" "${fixtureDir}/documents" "${fixtureDir}/assets"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/install.sh"
    printf 'fixture\n' >"${fixtureDir}/README.md"
    printf 'document\n' >"${fixtureDir}/documents/template.json"
    printf 'asset\n' >"${fixtureDir}/assets/template.txt"
    cat >"${fixtureDir}/shell/core/bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
source "${CORE_DIR}/version.sh"
EOF
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/core/version.sh"
    printf '#!/usr/bin/env bash\n' >"${fixtureDir}/shell/validate_install.sh"
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
        PATH="${fixtureDir}/missing-bin"
        hash -r
        ! writeModuleManifest "${SCRIPT_MANIFEST_FILE}"
        ! moduleManifestReady "${SCRIPT_MANIFEST_FILE}"
    )
    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runSubscribeNginxLocationPatternRegression() {
    local strictPattern='location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/([A-Fa-f0-9]{32})$ {'
    grep -qF "${strictPattern}" "${PROJECT_ROOT}/shell/subscription/subscription.sh"
    grep -qF "${strictPattern}" "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
    grep -A3 -F "${strictPattern}" "${PROJECT_ROOT}/shell/subscription/subscription.sh" | grep -qF 'access_log off;'
    grep -A3 -F "${strictPattern}" "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh" | grep -qF 'access_log off;'
    ! grep -qF 'location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {' "${PROJECT_ROOT}/shell/subscription/subscription.sh"
    ! grep -qF 'location ~ ^/s/(clashMeta|default|clashMetaProfiles|sing-box|sing-box_profiles)/(.*) {' "${PROJECT_ROOT}/shell/subscription/wireguard_control.sh"
}

runInstallEarlyCapabilityListRegression() {
    local outputFile
    outputFile="${TMP_DIR}/install-early-capability-list.txt"
    (
        eval "$(awk '
            /^installEarlyCapabilityRegistry\(\)/ { capture = 1 }
            /^installHandleEarlyCapabilityListArgs "\$@"/ { capture = 0 }
            capture { print }
        ' "${PROJECT_ROOT}/install.sh")"
        installHandleEarlyCapabilityListArgs --list-protocols
    ) >"${outputFile}"
    grep -q '^1[[:space:]]\+VLESS Reality Vision[[:space:]]\+node[[:space:]]\+recommended' "${outputFile}"
    grep -q '^2[[:space:]]\+VLESS Reality XHTTP[[:space:]]\+node[[:space:]]\+recommended' "${outputFile}"
    grep -q '^31[[:space:]]\+TUIC[[:space:]]\+node[[:space:]]\+advanced' "${outputFile}"
    ! grep -q 'padm 管理面板' "${outputFile}"
}

runInstallMenuRecommendedIdsRegression() {
    grep -q 'customXrayInstall 1 domain' "${PROJECT_ROOT}/shell/core/menu.sh"
    grep -q 'customXrayInstall 2' "${PROJECT_ROOT}/shell/core/menu.sh"
    grep -q 'customSingBoxInstall 5' "${PROJECT_ROOT}/shell/core/menu.sh"
    ! grep -q 'customXrayInstall 7 domain' "${PROJECT_ROOT}/shell/core/menu.sh"
    ! grep -q 'customXrayInstall 12' "${PROJECT_ROOT}/shell/core/menu.sh"
    ! grep -q 'customSingBoxInstall 10' "${PROJECT_ROOT}/shell/core/menu.sh"
}

runValidateInstallLoadsRuntimeRegression() {
    grep -q 'shell/core/runtime\.sh' "${PROJECT_ROOT}/shell/validate_install.sh"
    (
        eval "$(awk '/^check_service_manager\(\)/,/^}/' "${PROJECT_ROOT}/shell/validate_install.sh")"
        command() {
            if [[ "$1" == "-v" && "$2" == "systemctl" ]]; then
                return 1
            fi
            if [[ "$1" == "-v" && "$2" == "rc-service" ]]; then
                return 0
            fi
            builtin command "$@"
        }
        check_command() { printf '%s\n' "$1"; }
        [[ "$(check_service_manager)" == "rc-service" ]]
    )
}

runValidateInstallTempRootStaysInParentShellRegression() {
    ! grep -q 'root=$(validate_tmp_root)' "${PROJECT_ROOT}/shell/validate_install.sh"
    grep -q 'validate_tmp_root >/dev/null' "${PROJECT_ROOT}/shell/validate_install.sh"
}

runAliasInstallMetadataCopyRegression() {
    local sourceDir targetDir chmodLog shortcutLog shortcutOutput oldScriptDir oldPadmInstallDir oldHome
    sourceDir="${TMP_DIR}/alias-install-source"
    targetDir="${TMP_DIR}/alias-install-target"
    chmodLog="${TMP_DIR}/alias-install-chmod.log"
    shortcutLog="${TMP_DIR}/alias-install-shortcut.log"
    shortcutOutput="${TMP_DIR}/alias-install-shortcut.out"
    mkdir -p "${sourceDir}/shell" "${sourceDir}/documents" "${sourceDir}/assets" "${targetDir}"
    cat >"${sourceDir}/install.sh" <<'EOF'
#!/usr/bin/env bash
ensureScriptModules() { :; }
EOF
    printf 'shell\n' >"${sourceDir}/shell/marker"
    printf 'docs\n' >"${sourceDir}/documents/marker"
    printf 'assets\n' >"${sourceDir}/assets/marker"
    printf 'readme\n' >"${sourceDir}/README.md"
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
    cmp -s "${sourceDir}/README.md" "${targetDir}/README.md"
    cmp -s "${sourceDir}/.padm-ref" "${targetDir}/.padm-ref"
    cmp -s "${sourceDir}/.padm-entry-ref" "${targetDir}/.padm-entry-ref"

    printf 'old-shell\n' >"${targetDir}/shell/marker"
    printf 'old-docs\n' >"${targetDir}/documents/marker"
    printf 'old-assets\n' >"${targetDir}/assets/marker"
    printf 'old-readme\n' >"${targetDir}/README.md"
    printf 'old-manifest\n' >"${targetDir}/.padm-module-manifest"
    printf 'old-ref\n' >"${targetDir}/.padm-ref"
    printf 'old-entry-ref\n' >"${targetDir}/.padm-entry-ref"
    printf 'old-install\n' >"${targetDir}/install.sh"
    chmod 700 "${targetDir}/install.sh"

    (
        eval "$(declare -f syncInstallDirectoryTree | sed '1s/^syncInstallDirectoryTree/originalSyncInstallDirectoryTree/')"
        chmod() {
            printf '%s\n' "$*" >>"${chmodLog}"
        }
        syncInstallDirectoryTree() {
            if [[ "${2}" == "${targetDir}/documents" ]]; then
                return 71
            fi
            originalSyncInstallDirectoryTree "$@"
        }
        ! aliasInstall
    )

    [[ "$(<"${targetDir}/shell/marker")" == "old-shell" ]]
    [[ "$(<"${targetDir}/documents/marker")" == "old-docs" ]]
    [[ "$(<"${targetDir}/assets/marker")" == "old-assets" ]]
    [[ "$(<"${targetDir}/README.md")" == "old-readme" ]]
    [[ "$(<"${targetDir}/.padm-module-manifest")" == "old-manifest" ]]
    [[ "$(<"${targetDir}/.padm-ref")" == "old-ref" ]]
    [[ "$(<"${targetDir}/.padm-entry-ref")" == "old-entry-ref" ]]
    [[ "$(<"${targetDir}/install.sh")" == "old-install" ]]
    grep -Fqx "700 ${targetDir}/install.sh" "${chmodLog}"

    : >"${shortcutLog}"
    if (
        ln() {
            printf '%s\n' "$*" >>"${shortcutLog}"
            return 71
        }
        chmod() { :; }
        aliasInstall
    ) >"${shortcutOutput}" 2>&1; then
        return 1
    fi
    grep -Fqx -- "-s ${targetDir}/install.sh /usr/bin/padm" "${shortcutLog}"
    ! grep -q '快捷方式创建成功' "${shortcutOutput}"

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
    mkdir -p "${fixtureDir}/real" "${fixtureDir}/link"
    fixtureDir=$(cd -- "${fixtureDir}" && pwd -P)
    realDir="${fixtureDir}/real"
    linkDir="${fixtureDir}/link"
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
        initSubscribeLocalConfig() { return 1; }
        if showAccounts >/dev/null 2>&1; then
            return 1
        fi
    )
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local callLog="${TMP_DIR}/account-display-first-failure.log"
        configPath="${TMP_DIR}/account-display-first-failure/"
        currentDefaultPort=443
        singBoxVLESSVisionPort=
        : >"${callLog}"
        currentProtocolHas() { [[ "$1" == "27" ]]; }
        subscribeSectionTitle() { return 0; }
        subscribeAccountTitle() { return 0; }
        subscriptionAccountProfile() {
            if [[ "$1" == *first* ]]; then
                printf 'first\037id-first\037\037\037\037\037\n'
            else
                printf 'second\037id-second\037\037\037\037\037\n'
            fi
        }
        jq() {
            if [[ " $* " == *" -c "* ]]; then
                printf '%s\n' '{"email":"first","id":"id-first"}' '{"email":"second","id":"id-second"}'
            else
                printf '[]\n'
            fi
        }
        defaultBase64Code() {
            printf '%s\n' "$3" >>"${callLog}"
            [[ "$3" != "first" ]]
        }
        if showVlessTcpAccounts >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${callLog}")" == "first" ]]
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

        local cleanCalls=0
        cleanDirectoryContent() {
            cleanCalls=$((cleanCalls + 1))
            [[ "${cleanCalls}" != "1" ]]
        }
        if initSubscribeLocalConfig >/dev/null 2>&1; then
            return 1
        fi
        [[ "${cleanCalls}" == "1" ]]

        local appendCalls=
        appendDefaultSubscribeLine() { appendCalls=default; return 1; }
        appendClashMetaSubscribeBlock() { appendCalls=clash; return 0; }
        appendSingBoxSubscribeLocalConfig() { appendCalls=sing-box; return 0; }
        if appendStandardTLSSubscribeOutputs user default clash filter; then
            return 1
        fi
        [[ "${appendCalls}" == "default" ]]
    )
}

runSubscriptionSyncPathSafetyRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local rootRel="${TMP_DIR}/subscription-sync-path-safety"
        local root
        local safeSourceRel
        local safeLocalRel
        local safePublicRel
        local safeConfigRel
        local relativeConfigRel
        local safeLocal
        local safePublic
        local safeConfig
        local backupDir
        local configBackupDir
        local restoreConfigBackupDir
        local originalRelativeConfig
        local status
        local tmpRootAbs

        mkdir -p "${rootRel}"
        root=$(cd -- "${rootRel}" && pwd -P)
        tmpRootAbs=$(cd -- "${TMP_DIR}" && pwd -P)
        safeSourceRel="${rootRel}/safe-source"
        safeLocalRel="${rootRel}/safe-local"
        safePublicRel="${rootRel}/safe-public"
        safeConfigRel="${rootRel}/safe-config"
        relativeConfigRel="${rootRel}/relative-config"
        safeLocal="${root}/safe-local"
        safePublic="${root}/safe-public"
        safeConfig="${root}/safe-config"
        mkdir -p "${safeSourceRel}" "${safeLocalRel}/default" "${safeLocalRel}/clashMeta" "${safeLocalRel}/sing-box" "${safePublicRel}/default" "${safeConfigRel}" "${relativeConfigRel}"
        printf 'safe\n' >"${safeSourceRel}/file"
        printf 'local\n' >"${safeLocalRel}/default/user"
        printf 'public\n' >"${safePublicRel}/default/user"
        printf '{"inbounds":[{"settings":{"clients":[{"email":"sub_safe-main"}]}}]}\n' >"${safeConfigRel}/02_VLESS_TCP_inbounds.json"
        printf '{"inbounds":[{"settings":{"clients":[{"email":"sub_relative-main"}]}}]}\n' >"${relativeConfigRel}/02_VLESS_TCP_inbounds.json"

        set +e
        subscriptionSyncBackupPath "relative-source" "${root}/backup" local
        status=$?
        set -e
        [[ "${status}" -ne 0 ]]

        padmCreateTempPath backupDir -d "${TMP_DIR}/subscription-sync-path-safety-backup.XXXXXX"
        printf 'dir\n' >"${backupDir}/local.exists"
        mkdir -p "${backupDir}/local/default"
        printf 'backup\n' >"${backupDir}/local/default/user"

        set +e
        subscriptionSyncRestoreBackupPath "relative-target" "${backupDir}" local
        status=$?
        set -e
        [[ "${status}" -ne 0 ]]

        (
            cd -- "${root}"
            TMPDIR="${tmpRootAbs}"
            configPath="relative-config/"
            singBoxConfigPath=
            originalRelativeConfig=$(<"${root}/relative-config/02_VLESS_TCP_inbounds.json")
            subscriptionSyncCreateConfigBackups configBackupDir
            [[ -f "${configBackupDir}/manifest" ]]
            grep -q $'\t'"${root}/relative-config/02_VLESS_TCP_inbounds.json" "${configBackupDir}/manifest"
            padmCreateTempPath restoreConfigBackupDir -d "${tmpRootAbs}/subscription-sync-config-restore-backup.XXXXXX"
            printf '{"inbounds":[]}\n' >"${restoreConfigBackupDir}/000000.json"
            printf '%s\t%s\n' "${restoreConfigBackupDir}/000000.json" "relative-config/02_VLESS_TCP_inbounds.json" >"${restoreConfigBackupDir}/manifest"
            set +e
            subscriptionSyncRestoreConfigBackups "${restoreConfigBackupDir}"
            status=$?
            set -e
            [[ "${status}" -ne 0 ]]
            [[ "$(<"${root}/relative-config/02_VLESS_TCP_inbounds.json")" == "${originalRelativeConfig}" ]]
            padmRemoveCleanupPath "${restoreConfigBackupDir}"
            padmRemoveCleanupPath "${configBackupDir}"
        )

        PADM_SUBSCRIBE_LOCAL_DIR="${safeLocal}"
        PADM_SUBSCRIBE_DIR="${safePublic}"
        subscriptionSyncCreateSubscribeOutputBackups backupDir
        [[ -d "${backupDir}" ]]
        padmRemoveCleanupPath "${backupDir}"
    )
}

runSubscriptionSyncConfigRestoreRejectsDirectoryTargetRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/subscription-sync-config-directory-target"
        local backupDir
        local targetFile="${root}/safe-config/02_VLESS_TCP_inbounds.json"
        local status

        mkdir -p "${root}/safe-config" "${targetFile}"
        configPath="${root}/safe-config/"
        singBoxConfigPath=
        padmCreateTempPath backupDir -d "${TMP_DIR}/subscription-sync-config-directory-target-backup.XXXXXX"
        printf '{"inbounds":[]}\n' >"${backupDir}/000000.json"
        printf '%s\t%s\n' "${backupDir}/000000.json" "${targetFile}" >"${backupDir}/manifest"

        set +e
        subscriptionSyncRestoreConfigBackups "${backupDir}"
        status=$?
        set -e

        [[ "${status}" -ne 0 ]]
        [[ -d "${targetFile}" ]]
        [[ ! -e "${targetFile}/000000.json" ]]
        padmRemoveCleanupPath "${backupDir}"
    )
}

runSubscriptionSyncCreateLocalApplyBackupsRollbackRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/subscription-sync-create-local-apply-backups-rollback"
        local configBackupDir=
        local outputBackupDir=
        local expectedConfigBackup="${root}/created-config-backup"
        local status

        mkdir -p "${root}"
        subscriptionSyncCreateConfigBackups() {
            local resultVar=$1
            mkdir -p "${expectedConfigBackup}" || return 1
            printf -v "${resultVar}" '%s' "${expectedConfigBackup}"
        }
        subscriptionSyncCreateSubscribeOutputBackups() {
            return 1
        }

        set +e
        subscriptionSyncCreateLocalApplyBackups configBackupDir outputBackupDir
        status=$?
        set -e

        [[ "${status}" -ne 0 ]]
        [[ -z "${configBackupDir}" ]]
        [[ -z "${outputBackupDir}" ]]
        [[ ! -e "${expectedConfigBackup}" ]]
    )
}

runStateReadersClearStaleValuesRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/state.sh"
        local root="${TMP_DIR}/state-readers-clear-stale-values"

        mkdir -p "${root}/home" "${root}/nginx" "${root}/probe"
        HOME="${root}/home"
        currentHost=missing.example.com
        domain=
        installedDNSAPIStatus=true
        readAcmeTLS
        [[ -z "${installedDNSAPIStatus}" ]]

        nginxConfigPath="${root}/nginx/"
        subscribePort=39778
        subscribeDomain=stale.example.com
        subscribeType=https
        readNginxSubscribe
        [[ -z "${subscribePort}" && -z "${subscribeDomain}" && -z "${subscribeType}" ]]

        cat >"${root}/probe/09_tuic_inbounds.json" <<'JSON'
{"inbounds":[{"listen_port":443}]}
JSON
        (
            cd -- "${root}/probe"
            coreInstallType=2
            configPath=
            singBoxConfigPath=
            currentInstallProtocolType=",9,"
            frontingType=09_tuic_inbounds
            readInstallProtocolType
            [[ "${currentInstallProtocolType}" == "," && -z "${frontingType}" ]]
        )
    )
}

runReadInstallTypeKeepsSingBoxShardsRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/state.sh"
        local root="${TMP_DIR}/read-install-type-sing-box-shards"
        local xrayBinary="${root}/xray/xray"
        local xrayConfigDir="${root}/xray/conf"
        local singBoxBinary="${root}/sing-box/sing-box"
        local singBoxConfigDir="${root}/sing-box/conf/config"

        mkdir -p "${xrayConfigDir}" "${singBoxConfigDir}"
        : >"${xrayBinary}"
        : >"${singBoxBinary}"
        printf '{"inbounds":[]}\n' >"${singBoxConfigDir}/02_other_inbounds.json"
        export PADM_XRAY_BINARY="${xrayBinary}"
        export PADM_XRAY_CONF_DIR="${xrayConfigDir}"
        export PADM_SINGBOX_BINARY="${singBoxBinary}"
        export PADM_SINGBOX_CONFIG_DIR="${singBoxConfigDir}"

        readInstallType
        [[ "${coreInstallType}" == "2" ]]
        [[ "${singBoxConfigPath}" == "${singBoxConfigDir}/" ]]

        : >"${singBoxConfigDir}/config.json"
        rm -f "${singBoxConfigDir}/02_other_inbounds.json"
        printf '{"inbounds":[]}\n' >"${singBoxConfigDir}/09_tuic_inbounds.json"
        readInstallType
        [[ "${coreInstallType}" == "2" ]]
        [[ "${singBoxConfigPath}" == "${singBoxConfigDir}/" ]]
    )
}

runCheckLogBackupOutputVariableRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/check-log-backup-output-variable"
        local createdBackupDir=

        mkdir -p "${root}"
        printf 'old\n' >"${root}/target"
        checkLogBackupCreate createdBackupDir "${root}/target"
        [[ -n "${createdBackupDir}" && -d "${createdBackupDir}" ]]
        padmRemoveCleanupPath "${createdBackupDir}"
    )
}

runSuppressedRegressionFailurePropagationRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/framework/registry.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/framework/runtime.sh"
        regressionSuppressedFailureFixture() { return 23; }
        listSuppressedFailureFixture() { printf '%s\n' suppressed-failure-fixture; }
        registerRegressionFunctionLeaf suppressed-failure-fixture regressionSuppressedFailureFixture

        local status
        set +e
        (
            PADM_REGRESSION_SUPPRESS_DONE=1 runFrameworkSequentialRegressionSelectorList listSuppressedFailureFixture
        ) >/dev/null 2>&1
        status=$?
        set -e
        [[ "${status}" == "23" ]]
    )
}

runSubscriptionSyncConfigRestoreRejectsUnmanagedFileRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/subscription-sync-config-unmanaged-target"
        local backupDir
        local targetFile="${root}/safe-config/custom.json"
        local originalContent
        local status

        mkdir -p "${root}/safe-config"
        printf '{"custom":"keep"}\n' >"${targetFile}"
        originalContent=$(<"${targetFile}")
        configPath="${root}/safe-config/"
        singBoxConfigPath=
        padmCreateTempPath backupDir -d "${TMP_DIR}/subscription-sync-config-unmanaged-target-backup.XXXXXX"
        printf '{"inbounds":[]}\n' >"${backupDir}/000000.json"
        printf '%s\t%s\n' "${backupDir}/000000.json" "${targetFile}" >"${backupDir}/manifest"

        set +e
        subscriptionSyncRestoreConfigBackups "${backupDir}"
        status=$?
        set -e

        [[ "${status}" -ne 0 ]]
        [[ "$(<"${targetFile}")" == "${originalContent}" ]]
        padmRemoveCleanupPath "${backupDir}"
    )
}

runRestoreManagedFileFromBackupRejectsDirectoryTargetRegression() (
    local root="${TMP_DIR}/restore-managed-file-directory-target"
    local backupFile="${root}/backup.json"
    local targetFile="${root}/live.json"
    local status

    mkdir -p "${targetFile}"
    printf '{"restored":true}\n' >"${backupFile}"

    set +e
    restoreManagedFileFromBackup "${backupFile}" "${targetFile}" 644
    status=$?
    set -e

    [[ "${status}" -ne 0 ]]
    [[ -d "${targetFile}" ]]
    [[ ! -e "${targetFile}/.live.json.restore"* ]]
)

runSubscriptionSyncMissingRestoreScopeRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local root="${TMP_DIR}/subscription-sync-missing-restore-scope"
        local backupDir
        local rmLog

        rmLog="${root}/rm.log"
        padmIsSafeAbsolutePath() { return 0; }
        mkdir -p "${root}"
        : >"${rmLog}"

        padmCreateTempPath backupDir -d "${TMP_DIR}/subscription-sync-missing-restore-scope-backup.XXXXXX"
        subscriptionSyncBackupPath "${root}/subscribe_local" "${backupDir}" local
        subscriptionSyncBackupPath "${root}/subscribe" "${backupDir}" public

        mkdir -p \
            "${root}/subscribe_local/default" \
            "${root}/subscribe_local/clashMeta" \
            "${root}/subscribe_local/sing-box" \
            "${root}/subscribe_local/custom" \
            "${root}/subscribe/default" \
            "${root}/subscribe/clashMeta" \
            "${root}/subscribe/clashMetaProfiles" \
            "${root}/subscribe/sing-box" \
            "${root}/subscribe/sing-box_profiles" \
            "${root}/subscribe/custom"
        printf 'managed\n' >"${root}/subscribe_local/default/generated"
        printf 'managed\n' >"${root}/subscribe_local/clashMeta/generated"
        printf '[]\n' >"${root}/subscribe_local/sing-box/generated"
        printf 'salt\n' >"${root}/subscribe_local/subscribeSalt"
        printf 'keep\n' >"${root}/subscribe_local/custom/keep"
        printf 'managed\n' >"${root}/subscribe/default/generated"
        printf 'managed\n' >"${root}/subscribe/clashMeta/generated"
        printf 'managed\n' >"${root}/subscribe/clashMetaProfiles/generated"
        printf 'managed\n' >"${root}/subscribe/sing-box/generated"
        printf 'managed\n' >"${root}/subscribe/sing-box_profiles/generated"
        printf 'keep\n' >"${root}/subscribe/custom/keep"

        (
            rm() {
                printf 'rm:%s\n' "$*" >>"${rmLog}"
                command rm "$@"
            }
            subscriptionSyncRestoreBackupPath "${root}/subscribe_local" "${backupDir}" local
            subscriptionSyncRestoreBackupPath "${root}/subscribe" "${backupDir}" public
        )

        [[ -f "${root}/subscribe_local/custom/keep" ]]
        [[ -f "${root}/subscribe/custom/keep" ]]
        [[ ! -e "${root}/subscribe_local/default" ]]
        [[ ! -e "${root}/subscribe_local/clashMeta" ]]
        [[ ! -e "${root}/subscribe_local/sing-box" ]]
        [[ ! -e "${root}/subscribe_local/subscribeSalt" ]]
        [[ ! -e "${root}/subscribe/default" ]]
        [[ ! -e "${root}/subscribe/clashMeta" ]]
        [[ ! -e "${root}/subscribe/clashMetaProfiles" ]]
        [[ ! -e "${root}/subscribe/sing-box" ]]
        [[ ! -e "${root}/subscribe/sing-box_profiles" ]]
        ! grep -qxF "rm:-rf -- ${root}/subscribe_local" "${rmLog}"
        ! grep -qxF "rm:-rf -- ${root}/subscribe" "${rmLog}"

        padmRemoveCleanupPath "${backupDir}"
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
        cat >"${xrayRoot}/08_VLESS_vision_gRPC_inbounds.json" <<'JSON'
{"inbounds":[{"port":17694,"settings":{"clients":[{"email":"sub_xray_grpc-vless_reality_grpc","id":"44444444-4444-4444-4444-444444444444"}]},"streamSettings":{"realitySettings":{"serverNames":["www.cloudflare.com"],"publicKey":"xray-grpc-public-key","privateKey":"xray-grpc-private-key","target":"www.cloudflare.com:443","mldsa65Seed":"","mldsa65Verify":""},"grpcSettings":{"serviceName":"grpc"}}}]}
JSON
        cat >"${xrayRoot}/04_trojan_GRPc_inbounds.json" <<'JSON'
{"inbounds":[{"listen":"127.0.0.1","port":31304,"protocol":"trojan","settings":{"clients":[{"email":"sub_trojan_grpc-trojan_grpc","password":"trojan-grpc-pass"}]},"streamSettings":{"network":"grpc","security":"none","grpcSettings":{"serviceName":"padmtrojangrpc"}}}]}
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
        realityEntryHost() { printf 'entry.example.com'; }
        appendDefaultSubscribeLine() {
            printf 'default:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        appendClashMetaSubscribeBlock() {
            printf 'clash:%s\n' "$1" >>"${captureLog}"
        }
        appendSingBoxSubscribeLocalConfig() {
            printf 'singbox:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        initSubscribeLocalConfig() { return 0; }

        showAccounts >/dev/null

        grep -q 'default:sub_grpc:' "${captureLog}"
        grep -q 'default:sub_naive:' "${captureLog}"
        grep -q 'default:sub_httpupgrade:' "${captureLog}"
        grep -q 'default:sub_anytls:' "${captureLog}"
        grep -q 'default:sub_xray_grpc:.*@entry.example.com:17694' "${captureLog}"
        grep -q 'default:sub_xray_grpc:.*sni=www.cloudflare.com' "${captureLog}"
        grep -q 'default:sub_trojan_grpc:trojan://trojan-grpc-pass@cdn.example.com:443' "${captureLog}"
        grep -q 'singbox:sub_trojan_grpc:.*"type":"trojan"' "${captureLog}"
        grep -q 'singbox:sub_trojan_grpc:.*"service_name":"padmtrojangrpc"' "${captureLog}"
        grep -q 'singbox:.*"tag":"sub_xray_grpc-vless_reality_grpc"' "${captureLog}"
        grep -q 'singbox:.*"server_port":17694' "${captureLog}"
        grep -q 'singbox:.*"server_name":"www.cloudflare.com"' "${captureLog}"
        grep -q 'default:sub_grpc:.*sni=nodejs.org' "${captureLog}"
        grep -q 'default:sub_grpc:.*pbk=grpc-public-key' "${captureLog}"

        local httpupgradeLink httpupgradeJson
        httpupgradeLink=$(grep '^default:sub_httpupgrade:vmess://' "${captureLog}" | head -n 1)
        httpupgradeJson=$(printf '%s' "${httpupgradeLink#default:sub_httpupgrade:vmess://}" | base64 -d)
        printf '%s\n' "${httpupgradeJson}" | grep -q '"port":24443'
        printf '%s\n' "${httpupgradeJson}" | grep -q '"path":"/padmhttp"'
    )
}

runShowAccountsSingBoxRealityGrpcRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/show-accounts-singbox-reality-grpc"
        local singBoxRoot="${root}/etc/padm/sing-box/conf/config"
        local captureLog="${root}/capture.log"

        mkdir -p "${singBoxRoot}"
        : >"${captureLog}"
        cat >"${singBoxRoot}/08_VLESS_vision_gRPC_inbounds.json" <<'JSON'
{"inbounds":[{"type":"vless","listen_port":15210,"users":[{"uuid":"22222222-2222-2222-2222-222222222222","name":"sub_grpc-VLESS_Reality_gPRC"}],"tls":{"server_name":"www.ibm.com","reality":{"private_key":"singbox-private-key","handshake":{"server":"www.ibm.com","server_port":443}}},"transport":{"type":"grpc","service_name":"grpc"}}]}
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

        readInstallType() {
            coreInstallType=2
            configPath="${singBoxRoot}/"
            singBoxConfigPath="${singBoxRoot}/"
            ctlPath="${root}/etc/padm/sing-box/sing-box"
        }
        readConfigHostPathUUID() {
            currentHost=45.221.113.40
            return 0
        }
        readSingBoxConfig() { return 0; }
        subscribeSectionTitle() { return 0; }
        subscribeAccountTitle() { return 0; }
        subscribeOutputTitle() { return 0; }
        realityEntryHost() { printf '45.221.113.40'; }
        appendDefaultSubscribeLine() {
            printf 'default:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        appendClashMetaSubscribeBlock() { return 0; }
        appendSingBoxSubscribeLocalConfig() {
            printf 'singbox:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        initSubscribeLocalConfig() { return 0; }

        showAccounts >/dev/null

        grep -q 'default:sub_grpc:.*@45.221.113.40:15210' "${captureLog}"
        grep -q 'default:sub_grpc:.*sni=www.ibm.com' "${captureLog}"
        grep -q 'default:sub_grpc:.*pbk=grpc-public-key' "${captureLog}"
        grep -q 'singbox:.*"server_port":15210' "${captureLog}"
        grep -q 'singbox:.*"server_name":"www.ibm.com"' "${captureLog}"
        grep -q 'singbox:.*"public_key":"grpc-public-key"' "${captureLog}"
    )
}

runTrojanGrpcAccountUsesTemplateFilenameRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        if ! grep -q '04_trojan_GRPc_inbounds\.json' "${PROJECT_ROOT}/shell/subscription/accounts_protocols.sh"; then
            printf 'assert-fail:trojan grpc account reader must use generated 04_trojan_GRPc_inbounds.json filename\n' >&2
            return 1
        fi
        if grep -q '04_trojan_gRPC_inbounds\.json' "${PROJECT_ROOT}/shell/subscription/accounts_protocols.sh"; then
            printf 'assert-fail:trojan grpc account reader uses non-generated 04_trojan_gRPC_inbounds.json filename\n' >&2
            return 1
        fi
    )
}

runTrojanFallbackSubscribeUsesTlsEntryRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/trojan-fallback-subscribe-entry"
        local xrayRoot="${root}/etc/padm/xray/conf"
        local tlsRoot="${root}/etc/padm/tls"
        local captureLog="${root}/capture.log"
        local oldTlsDir="${PADM_TLS_DIR:-}"

        mkdir -p "${xrayRoot}" "${tlsRoot}"
        : >"${captureLog}"
        export PADM_SUBSCRIBE_LOCAL_DIR="${root}/subscribe_local"
        export PADM_TLS_DIR="${tlsRoot}"
        mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/default" "${PADM_SUBSCRIBE_LOCAL_DIR}/clashMeta" "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box"

        cat >"${xrayRoot}/04_trojan_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"port":31296,"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[{"email":"sub_fallback-trojan_tcp","password":"fallback-pass"}],"fallbacks":[{"dest":"31300","xver":1}]},"streamSettings":{"network":"tcp","security":"none","tcpSettings":{"acceptProxyProtocol":true}}}]}
JSON
        cat >"${xrayRoot}/02_VLESS_TCP_inbounds.json" <<'JSON'
{"inbounds":[{"port":443,"protocol":"vless","settings":{"clients":[{"id":"11111111-1111-4111-8111-111111111111","email":"fronting"}],"fallbacks":[{"dest":31296,"xver":1}]},"streamSettings":{"network":"tcp","security":"tls","tlsSettings":{"certificates":[{"certificateFile":"/etc/padm/tls/tls.example.com.crt","keyFile":"/etc/padm/tls/tls.example.com.key"}]}}}]}
JSON
        cat >"${xrayRoot}/02_dokodemodoor_inbounds_443_default.json" <<'JSON'
{"inbounds":[{"port":443,"settings":{"port":443}}]}
JSON
        printf 'crt\n' >"${tlsRoot}/tls.example.com.crt"
        printf 'key\n' >"${tlsRoot}/tls.example.com.key"

        coreInstallType=1
        configPath="${xrayRoot}/"
        singBoxConfigPath="${root}/etc/padm/sing-box/conf/config/"
        nginxConfigPath="${root}/etc/nginx/conf.d/"
        domain=tls.example.com
        currentInstallProtocolType=
        frontingType=
        currentHost=
        currentDefaultPort=

        subscribeSectionTitle() { return 0; }
        subscribeAccountTitle() { return 0; }
        subscribeOutputTitle() { return 0; }
        appendDefaultSubscribeLine() {
            printf 'default:%s:%s\n' "$1" "$2" >>"${captureLog}"
        }
        appendClashMetaSubscribeBlock() {
            printf 'clash:%s\n' "$1" >>"${captureLog}"
        }

        readInstallProtocolType
        readConfigHostPathUUID
        if [[ "${frontingType}" != "02_VLESS_TCP_inbounds" ]]; then
            printf 'assert-fail:trojan fallback frontingType=%s\n' "${frontingType}" >&2
            return 1
        fi
        if [[ "${currentPort}" != "443" || "${currentDefaultPort}" != "443" ]]; then
            printf 'assert-fail:trojan fallback entry port current=%s default=%s\n' "${currentPort}" "${currentDefaultPort}" >&2
            return 1
        fi
        showTrojanAccounts >/dev/null

        if ! grep -q 'default:sub_fallback:trojan://fallback-pass@tls\.example\.com:443' "${captureLog}"; then
            sed -n '1,120p' "${captureLog}" >&2
            printf 'assert-fail:trojan fallback default subscribe entry missing\n' >&2
            return 1
        fi
        if ! jq -e '.[0].server == "tls.example.com"' "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_fallback" >/dev/null; then
            cat "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_fallback" >&2
            printf 'assert-fail:trojan fallback sing-box server missing\n' >&2
            return 1
        fi
        if ! jq -e '.[0].server_port == 443' "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_fallback" >/dev/null; then
            cat "${PADM_SUBSCRIBE_LOCAL_DIR}/sing-box/sub_fallback" >&2
            printf 'assert-fail:trojan fallback sing-box port missing\n' >&2
            return 1
        fi
        if grep -q 'trojan://fallback-pass@:' "${captureLog}"; then
            printf 'assert-fail:trojan fallback subscribe host/port empty\n' >&2
            return 1
        fi
        if [[ -n "${oldTlsDir}" ]]; then
            export PADM_TLS_DIR="${oldTlsDir}"
        else
            unset PADM_TLS_DIR
        fi
    )
}

runTrojanFallbackTemplateCreatesTlsFrontendRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/trojan-fallback-template-frontend"
        local xrayRoot="${root}/etc/padm/xray/conf"
        local tlsRoot="${root}/etc/padm/tls"
        local vlessFile="${xrayRoot}/02_VLESS_TCP_inbounds.json"
        local trojanFile="${xrayRoot}/04_trojan_TCP_inbounds.json"
        mkdir -p "${xrayRoot}" "${tlsRoot}"

        selectCustomInstallType=",29,"
        currentUUID="11111111-1111-4111-8111-111111111111"
        currentClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"main"}]'
        currentHost=example.com
        domain=example.com
        port=443
        add=example.com
        customPath=padm
        configPath="${xrayRoot}/"
        lastInstallationConfig=true

        addXrayOutbound() { return 0; }
        removeXrayTemplateConfigFiles() { return 0; }
        randomPathFunction() { currentPath=padm; customPath=padm; }
        initRealityProfile() { return 0; }
        initXrayXHTTPort() { return 0; }
        initRealityKey() { return 0; }
        initRealityMldsa65() { return 0; }
        writeGeneratedJsonFile() {
            local targetPath=$1
            if [[ "${targetPath}" == /etc/padm/* ]]; then
                targetPath="${root}${targetPath}"
            fi
            mkdir -p "$(dirname -- "${targetPath}")"
            shift 2
            cat >"${targetPath}"
        }

        initXrayConfig custom 1 true >/dev/null

        [[ -f "${trojanFile}" ]]
        [[ -f "${vlessFile}" ]]
        jq -e '.inbounds[0].port == 443' "${vlessFile}" >/dev/null
        jq -e '.inbounds[0].streamSettings.tlsSettings.certificates[0].certificateFile == "/etc/padm/tls/example.com.crt"' "${vlessFile}" >/dev/null
        jq -e '.inbounds[0].settings.fallbacks[] | select(.dest == 31296 or .dest == "31296")' "${vlessFile}" >/dev/null
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

        selectCustomInstallType=",23,"
        currentUUID="11111111-1111-4111-8111-111111111111"
        currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"main-VMess_HTTPUpgrade"}]'
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

        singBoxNginxConfig() { return 1; }
        rm -f "${singBoxRoot}/11_VMess_HTTPUpgrade_inbounds.json"
        : >"${actionLog}"
        set +e
        initSingBoxConfig custom 1 true >/dev/null 2>&1
        local rc=$?
        set -e
        [[ "${rc}" != "0" ]]
        [[ ! -e "${singBoxRoot}/11_VMess_HTTPUpgrade_inbounds.json" ]]
        ! grep -q 'boot:nginx' "${actionLog}"

        singBoxNginxConfig() { printf 'server {}\n' >"${nginxRoot}/sing_box_VMess_HTTPUpgrade.conf"; }
        randomPathFunction() { return 1; }
        set +e
        initSingBoxConfig custom 1 true >/dev/null 2>&1
        rc=$?
        set -e
        [[ "${rc}" != "0" ]]
        [[ ! -e "${singBoxRoot}/11_VMess_HTTPUpgrade_inbounds.json" ]]
    )
}

runSingBoxHttpUpgradeRejectsUnsafeNginxPathRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"

        local root="${TMP_DIR}/httpupgrade-unsafe-nginx-path"
        local unsafeRoot="${root}/unsafe"
        local singBoxRoot="${root}/etc/padm/sing-box/conf/config"
        local rc
        mkdir -p "${unsafeRoot}" "${singBoxRoot}"
        printf 'stale\n' >"${unsafeRoot}/sing_box_VMess_HTTPUpgrade.conf"
        cd "${unsafeRoot}"

        selectCustomInstallType=",23,"
        currentUUID="11111111-1111-4111-8111-111111111111"
        currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"main-VMess_HTTPUpgrade"}]'
        lastInstallationConfig=true
        currentHost=example.com
        domain=example.com
        singBoxVMessHTTPUpgradePort=
        singBoxConfigPath="${singBoxRoot}/"
        nginxConfigPath=

        collectTLSProfile() { tlsCertDomain=example.com; }
        readSingBoxPortResult() {
            local -n resultRef=$1
            resultRef=(24443)
        }
        initSingBoxClients() { printf '[]'; }
        checkDNSIP() { return 0; }
        stopSingBoxBeforeTemplateWrite() { return 0; }
        randomPathFunction() { currentPath=httpup; }
        checkPortOpen() { return 0; }
        singBoxNginxConfig() { return 0; }
        bootStartup() { return 0; }
        handleNginx() { return 0; }
        runCoreServiceActionAllowFailure() {
            "$@"
        }
        writeGeneratedJsonFile() {
            cat >/dev/null
        }

        set +e
        initSingBoxConfig custom 1 true >/dev/null
        rc=$?
        set -e
        [[ "${rc}" != "0" ]]
        [[ -f sing_box_VMess_HTTPUpgrade.conf ]]
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
        currentClients='[{"id":"u1","email":"acct \"one"},{"uuid":"u2","name":"acct \"two"}]'
        protocolSelectionIncludes() {
            local type=$1
            local target=$2
            [[ ",${type}," == *",${target},"* ]]
        }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        local xrayUsers singboxUsers
        xrayUsers=$(initXrayClients 1)
        singboxUsers=$(initSingBoxClients 1)
        jq -e 'any(.[]; .email == "acct \"one-vless_reality_vision" and .id == "u1")' <<<"${xrayUsers}" >/dev/null
        jq -e 'any(.[]; .name == "acct \"two-VLESS_Reality_Vision" and .uuid == "u2")' <<<"${singboxUsers}" >/dev/null
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
        padmCreateTempPath() { printf -v "$1" '%s' "$(mktemp "$2")"; }
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        installSingBoxService 1 >/dev/null 2>&1
        grep -q 'ExecReload=/bin/kill -HUP \$MAINPID' "${TMP_DIR}/sing-box.service"

        bootStartup() { return 1; }
        if (installSingBoxService 1 >/dev/null 2>&1); then
            return 1
        fi
        if (installXrayService 1 >/dev/null 2>&1); then
            return 1
        fi
    )
}

runCheckGFWStatusServiceWaitRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
        local successLog="${TMP_DIR}/check-gfw-success.log"
        local errorLog="${TMP_DIR}/check-gfw-error.log"
        local xrayAttempts=0

        export REGRESSION_SUCCESS_CARD_LOG="${successLog}"
        export REGRESSION_ERROR_CARD_LOG="${errorLog}"
        export PADM_CHECK_GFW_SERVICE_ATTEMPTS=4
        export PADM_CHECK_GFW_SERVICE_INTERVAL=0.01

        readInstallType() { coreInstallType=1; }
        xrayRunning() {
            xrayAttempts=$((xrayAttempts + 1))
            [[ "${xrayAttempts}" -ge 3 ]]
        }

        checkGFWStatue 1
        [[ "${xrayAttempts}" -ge 3 ]]
        grep -q '服务启动成功' "${successLog}"

        xrayAttempts=0
        : >"${errorLog}"
        xrayRunning() {
            xrayAttempts=$((xrayAttempts + 1))
            return 1
        }
        if checkGFWStatue 1; then
            return 1
        fi
        grep -q '服务启动失败' "${errorLog}"
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

runCoreRunningFallsBackToServiceStateRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        local root="${TMP_DIR}/core-running-service-state"
        mkdir -p "${root}"
        PADM_XRAY_SYSTEMD_SERVICE_FILE="${root}/xray.service"
        PADM_XRAY_OPENRC_SERVICE_FILE="${root}/xray.openrc"
        PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${root}/sing-box.service"
        PADM_SINGBOX_OPENRC_SERVICE_FILE="${root}/sing-box.openrc"
        : >"${PADM_XRAY_SYSTEMD_SERVICE_FILE}"
        : >"${PADM_SINGBOX_SYSTEMD_SERVICE_FILE}"
        pgrep() { return 1; }
        padmCommandExists() { [[ "$1" == "systemctl" ]]; }
        systemctl() {
            [[ "$1" == "is-active" && "$2" == "--quiet" && ( "$3" == "xray.service" || "$3" == "sing-box.service" ) ]]
        }
        singBoxMergedConfigFile() { printf '%s\n' "/etc/padm/sing-box/conf/config.json"; }
        xrayRunning
        singBoxRunning
    )
}

runXrayConfiguredServicePathRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        local root="${TMP_DIR}/xray-configured-service-path"
        local customXray="${root}/custom/xray"
        local customConf="${root}/custom/conf"
        local validateLog="${root}/validate.log"
        local serviceState="${root}/running"

        mkdir -p "${customConf}" "$(dirname "${customXray}")"
        export PADM_XRAY_BINARY="${customXray}"
        export PADM_XRAY_CONF_DIR="${customConf}"
        printf '{"log":{}}\n' >"${customConf}/00_log.json"
        cat >"${customXray}" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PADM_FAKE_XRAY_VALIDATE_LOG}"
[[ "$1" == "-test" && "$2" == "-confdir" && "$3" == "${PADM_XRAY_CONF_DIR}" ]]
SH
        chmod +x "${customXray}"
        export PADM_FAKE_XRAY_VALIDATE_LOG="${validateLog}"

        pgrep() { printf '4242\n'; }
        padmReadProcExe() { printf '%s\n' "${customXray}"; }
        padmReadProcCmdline() { printf '%s run -confdir %s' "${customXray}" "${customConf}"; }
        xrayRunning

        rm -f "${serviceState}" "${validateLog}"
        pgrep() { return 1; }
        xrayRunning() { [[ -f "${serviceState}" ]]; }
        find() {
            case "$*" in
            '/bin /usr/bin -name systemctl' | '/etc/systemd/system/ -name xray.service')
                printf '%s\n' "${root}/systemctl"
                ;;
            esac
        }
        systemctl() {
            [[ "$1" == "start" && "$2" == "xray.service" ]] && : >"${serviceState}"
        }
        xrayConfigValidationFailureCard() { return 1; }
        successCard() { return 0; }
        errorCard() { return 1; }
        uiStyle() { shift; printf '%s' "$*"; }
        menuLine() { return 0; }

        handleXray start
        grep -qx -- "-test -confdir ${customConf}" "${validateLog}"
    )
}

runSingBoxRunningIgnoresClientProcessRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/services.sh"
        singBoxMergedConfigFile() { printf '%s\n' "/etc/padm/sing-box/conf/config.json"; }
        PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${TMP_DIR}/sing-box.service"
        PADM_SINGBOX_OPENRC_SERVICE_FILE="${TMP_DIR}/sing-box.openrc"
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
        export PADM_FAIL2BAN_SSHD_BACKEND=systemd

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

        [[ "$(fail2banRecommendedProfileName)" == "sshd+control" ]]
        [[ "$(fail2banProfileLabel "$(fail2banRecommendedProfileName)")" == "SSH + 控制面防护" ]]
        fail2banWriteManagedFilter
        fail2banWriteNginxScanFilter
        fail2banWriteManagedJail sshd+control false
        grep -q '^\[sshd\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^enabled = true' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^backend = systemd$' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd$' "${PADM_FAIL2BAN_JAIL_FILE}"
        ! awk '
            /^\[/ {
                section=$0
                next
            }
            section == "[sshd]" && /^[[:space:]]*logpath[[:space:]]*=/ {
                found=1
            }
            END { exit found ? 0 : 1 }
        ' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^\[padm-control\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^\[nginx-scan-basic\]' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '^enabled = false$' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q "logpath = ${root//\\/\\\\}/nginx/padm-control-access.log" "${PADM_FAIL2BAN_JAIL_FILE}" || grep -q 'logpath = .*/nginx/padm-control-access.log' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q "logpath = ${root//\\/\\\\}/nginx/access.log" "${PADM_FAIL2BAN_JAIL_FILE}" || grep -q 'logpath = .*/nginx/access.log' "${PADM_FAIL2BAN_JAIL_FILE}"
        grep -q '/s/control/' "${PADM_FAIL2BAN_FILTER_FILE}"
        grep -Eq 'wp-login\.php|\.env|phpmyadmin|actuator' "${PADM_FAIL2BAN_NGINX_SCAN_FILTER_FILE}"

        export PADM_FAIL2BAN_SSHD_BACKEND=$'systemd\n[evil]\nenabled = true'
        ! fail2banWriteManagedJail sshd false
        export PADM_FAIL2BAN_SSHD_BACKEND=systemd
        export PADM_FAIL2BAN_CONTROL_LOG_FILE=$'/var/log/nginx/padm-control-access.log\nbackend = systemd'
        ! fail2banWriteManagedJail sshd+control false
        export PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/nginx/padm-control-access.log"
        subscriptionWireGuardReadState() {
            jq -n --arg port $'39778\nlogpath = /tmp/evil.log' '{enabled:true, role:"main", address:"10.77.0.1/24", control_port:$port, peers:[{id:"edge-a"}]}'
        }
        ! fail2banWriteManagedJail sshd+control false
        subscriptionWireGuardReadState() {
            jq -n '{enabled:true, role:"main", address:"10.77.0.1/24", control_port:39778, peers:[{id:"edge-a"}]}'
        }

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

        subscriptionWireGuardControlEnabled() { return 1; }
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

runFail2banSshdSystemdBackendRegression() {
    (
        set -euo pipefail
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/fail2ban.sh"

        local root="${TMP_DIR}/fail2ban-sshd-systemd"
        mkdir -p "${root}/fail2ban/jail.d" "${root}/nginx"
        export PADM_FAIL2BAN_JAIL_FILE="${root}/fail2ban/jail.d/padm.local"
        export PADM_FAIL2BAN_CONTROL_LOG_FILE="${root}/nginx/padm-control-access.log"
        export PADM_FAIL2BAN_NGINX_ACCESS_LOG_FILE="${root}/nginx/access.log"
        export PADM_FAIL2BAN_SSHD_BACKEND=systemd

        subscriptionWireGuardReadState() {
            jq -n '{control_port:39778}'
        }

        fail2banWriteManagedJail sshd+control false
        awk '
            /^\[/ {
                section=$0
                next
            }
            section == "[sshd]" && /^backend = systemd$/ {
                backend=1
            }
            section == "[sshd]" && /^journalmatch = _SYSTEMD_UNIT=ssh.service \+ _COMM=sshd$/ {
                journal=1
            }
            section == "[sshd]" && /^[[:space:]]*logpath[[:space:]]*=/ {
                logpath=1
            }
            END {
                exit (backend && journal && !logpath) ? 0 : 1
            }
        ' "${PADM_FAIL2BAN_JAIL_FILE}"
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
        fail2banApplyNginxScanExtension() { recordMenuAction "fail2banApplyNginxScanExtension:$1"; }

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
        statusFile=$(coreTmpFilePath padm-sing-box-compat-audit.status)
        warnFile=$(coreTmpFilePath padm-sing-box-compat-audit.warn)
        logFile=$(coreTmpFilePath padm-sing-box-compat-audit.log)
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
        statusFile=$(coreTmpFilePath padm-xray-compat-audit.status)
        warnFile=$(coreTmpFilePath padm-xray-compat-audit.warn)
        logFile=$(coreTmpFilePath padm-xray-compat-audit.log)
        collectXrayCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
        grep -q '^fail:' "${statusFile}"
        grep -q '旧 users schema' "${logFile}"
        grep -q 'echForceQuery' "${logFile}"
        grep -q 'legacy reverse' "${logFile}"
        grep -q 'trustedXForwardedFor' "${logFile}"
    )
}

runXrayCompatibilityTrustedXffRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/xray-compat-trusted-xff"
        local xrayRoot="${root}/etc/padm/xray"
        export PADM_XRAY_BINARY="${xrayRoot}/xray"
        export PADM_XRAY_CONF_DIR="${xrayRoot}/conf"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${PADM_XRAY_BINARY}"
        chmod +x "${PADM_XRAY_BINARY}"
        cat >"${PADM_XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json" <<'JSON'
{"inbounds":[{"streamSettings":{"network":"xhttp","sockopt":{"trustedXForwardedFor":"1.2.3.4"},"xhttpSettings":{}},"settings":{"clients":[]}}]}
JSON
        local statusFile warnFile logFile
        statusFile=$(coreTmpFilePath padm-xray-compat-trusted-xff.status)
        warnFile=$(coreTmpFilePath padm-xray-compat-trusted-xff.warn)
        logFile=$(coreTmpFilePath padm-xray-compat-trusted-xff.log)
        collectXrayCompatibilityFindings "${statusFile}" "${logFile}" "${warnFile}"
        ! grep -q 'trustedXForwardedFor' "${logFile}"
        ! grep -q 'trustedXForwardedFor' "${warnFile}"
    )
}

runXrayConfiguredValidationPathRegression() {
    (
        set -euo pipefail
        local root="${TMP_DIR}/xray-configured-validation-path"
        local xrayRoot="${root}/custom-xray"
        local validateLog="${root}/validate.log"
        local xhttpConfig="${xrayRoot}/conf/12_VLESS_XHTTP_inbounds.json"
        local alpnConfig="${xrayRoot}/conf/27_tls.json"
        export PADM_XRAY_BINARY="${xrayRoot}/xray"
        export PADM_XRAY_CONF_DIR="${xrayRoot}/conf"
        export PADM_XHTTP_CONFIG_FILE="${xhttpConfig}"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        cat >"${PADM_XRAY_BINARY}" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${PADM_FAKE_XRAY_VALIDATE_LOG}"
[[ "$1" == "-test" && "$2" == "-confdir" && "$3" == "${PADM_XRAY_CONF_DIR}" ]]
SH
        chmod +x "${PADM_XRAY_BINARY}"
        export PADM_FAKE_XRAY_VALIDATE_LOG="${validateLog}"
        cat >"${xhttpConfig}" <<'JSON'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"mode":"auto"}}}]}
JSON
        cat >"${alpnConfig}" <<'JSON'
{"inbounds":[{"streamSettings":{"tlsSettings":{"alpn":["http/1.1"]}}}]}
JSON
        coreInstallType=1
        refreshXHTTPSubscriptions() { return 0; }
        reloadCore() { return 0; }
        traditionalTlsFallbackConfigFile() { printf '%s\n' "${alpnConfig}"; }

        validateXHTTPConfigUpdate
        applyTraditionalTlsAlpn '["h2","http/1.1"]'
        [[ "$(grep -c -- "-test -confdir ${PADM_XRAY_CONF_DIR}" "${validateLog}")" == "2" ]]
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

runRegressionPlatformUpdate() {
    runRegressionStep update-padm-version-prompt runUpdatePadmVersionPromptRegression &&
        runRegressionStep update-padm-single-ref runUpdatePadmSingleRefRegression
}

runRegressionPlatformRefresh() {
    runRegressionStep install-refresh-ref-fail-closed runInstallRefreshRefFailClosedRegression &&
        runRegressionStep install-refresh-keep-ref-on-lookup-fail runInstallRefreshKeepsRefWhenRemoteLookupFailsRegression &&
        runRegressionStep install-refresh-rejects-unsafe-script-dir runInstallRefreshRejectsUnsafeScriptDirRegression &&
        runRegressionStep install-refresh-rejects-unsafe-archive runInstallRefreshRejectsUnsafeArchiveRegression &&
        runRegressionStep install-refresh-rejects-unsupported-archive-entry runInstallRefreshRejectsUnsupportedArchiveEntriesRegression &&
        runRegressionStep install-refresh-restore runInstallRefreshRestoresBackupRegression &&
        runRegressionStep install-refresh-signal-restores-and-exits runInstallRefreshSignalRestoresAndExitsRegression &&
        runRegressionStep install-module-lock-serializes-load runInstallModuleLockSerializesLoadRegression &&
        runRegressionStep install-refresh-rejects-entry-mismatch runInstallRefreshRejectsEntryMismatchRegression &&
        runRegressionStep install-refresh-ref-commit-rollback runInstallRefreshRefCommitRollbackRegression &&
        runRegressionStep install-refresh-single-archive-guard runInstallRefreshSingleArchiveGuardRegression
}

runRegressionPlatformRest() {
    runRegressionStep release-workflow-version runReleaseWorkflowVersionRegression &&
        runRegressionStep version-helpers runVersionHelpersRegression &&
        runRegressionStep regression-bootstrap-local-env-fallback runRegressionBootstrapLocalEnvFallbackRegression &&
        runRegressionStep cleanup-trap runCleanupTrapRegression &&
        runRegressionStep cleanup-trap-relative-path runCleanupTrapRelativePathRegression &&
        runRegressionStep clean-directory-safety runCleanDirectoryContentSafetyRegression &&
        runRegressionStep managed-file-backup-manifest runManagedFileBackupManifestRegression &&
        runRegressionStep managed-file-backup-manifest-validator runManagedFileBackupManifestValidatorRegression &&
        runRegressionStep remove-managed-files-ignore-failure runRemoveManagedFilesIgnoreFailureRegression &&
        runRegressionStep remove-managed-path-ignore-failure runRemoveManagedPathIgnoreFailureRegression &&
        runRegressionStep check-log-backup-restore runCheckLogBackupMissingRestoreRegression &&
        runRegressionStep remote-control-systemctl-stub-default-stop-disable runRemoteControlSystemctlStubDefaultStopDisableRegression &&
        runRegressionStep regression-fast-parallel-composition runRegressionFastParallelCompositionRegression &&
        runRegressionStep regression-fast-only-parallel-composition runRegressionFastOnlyParallelCompositionRegression &&
        runRegressionStep regression-fast-only-output-parallel-composition runRegressionFastOnlyOutputParallelCompositionRegression &&
        runRegressionStep regression-platform-hot-parallel-composition runRegressionPlatformHotParallelCompositionRegression &&
        runRegressionStep remote-control-function-stub-default-stop-disable runRemoteControlFunctionStubDefaultStopDisableRegression &&
        runRegressionStep tuic-protocol-single-default-branch runTuicProtocolSingleDefaultBranchRegression &&
        runRegressionStep tls-dns-api-single-default-branch runTlsDnsApiSingleDefaultBranchRegression &&
        runRegressionStep tls-ca-single-default-branch runTlsCaSingleDefaultBranchRegression &&
        runRegressionStep reality-target-single-default-branch runRealityTargetSingleDefaultBranchRegression &&
        runRegressionStep auto-install-type-single-custom-branch runAutoInstallTypeSingleCustomBranchRegression &&
        runRegressionStep subscription-menu-wrapper-count runSubscriptionMenuWrapperCountRegression &&
        runRegressionStep subscription-menu-dead-entry-count runSubscriptionMenuDeadEntryCountRegression &&
        runRegressionStep unused-helper-function-count runUnusedHelperFunctionCountRegression &&
        runRegressionStep legacy-users-module-removed runLegacyUsersModuleRemovedRegression &&
        runRegressionStep install-entry-refresh runInstallEnsureModulesRegression &&
        runRegressionStep install-module-paths runInstallModulePathsRegression &&
        runRegressionStep install-module-manifest-complete runInstallModuleManifestCompleteRegression &&
        runRegressionStep install-module-manifest-requires-sha256 runInstallModuleManifestRequiresSha256Regression &&
        runRegressionStep subscribe-nginx-location-pattern runSubscribeNginxLocationPatternRegression &&
        runRegressionStep install-early-capability-list runInstallEarlyCapabilityListRegression &&
        runRegressionStep install-menu-recommended-ids runInstallMenuRecommendedIdsRegression &&
        runRegressionStep validate-install-loads-runtime runValidateInstallLoadsRuntimeRegression &&
        runRegressionStep validate-install-temp-root-parent-shell runValidateInstallTempRootStaysInParentShellRegression &&
        runRegressionStep install-entry-symlink runInstallEntrySymlinkPathRegression &&
        runRegressionStep alias-install-metadata runAliasInstallMetadataCopyRegression &&
        runRegressionStep alias-install-same-target runAliasInstallSameTargetRegression &&
        runRegressionStep alias-install-rejects-unsafe-target runAliasInstallRejectsUnsafeTargetRegression &&
        runRegressionStep alias-install-rejects-unsafe-home runAliasInstallRejectsUnsafeHomeFallbackRegression &&
        runRegressionStep xray-stats-jq runXrayTrafficStatsJqCompatibilityRegression &&
        runRegressionStep local-traffic-accounts runLocalTrafficAccountsBatchRegression &&
        runRegressionStep dpkg-installed-pattern runDpkgInstalledPatternRegression &&
        runRegressionStep dpkg-query-installed-pattern runDpkgQueryInstalledPatternRegression &&
        runRegressionStep rhel-like-detection runRhelLikeDetectionRegression &&
        runRegressionStep fedora-detection runFedoraDetectionRegression &&
        runRegressionStep port-hopping-without-persistent runPortHoppingWithoutPersistentRegression &&
        runRegressionStep port-hopping-menu-command-lookup runPortHoppingMenuUsesCommandLookupRegression
}

runRegressionPlatform() {
    runParallelFastTotals "${TMP_DIR}/platform-hot-parallel-${BASHPID:-$$}" \
        update runRegressionPlatformUpdate \
        refresh runRegressionPlatformRefresh \
        rest runRegressionPlatformRest
}

runParallelFastTotals() {
    local orchestrationRoot=$1
    shift
    local -a labels=()
    local -a runners=()
    local -a logs=()
    local -a pids=()
    local -a statuses=()
    local status=0
    local i

    if [[ $# -eq 0 || $(( $# % 2 )) -ne 0 ]]; then
        printf 'runParallelFastTotals expects label/runner pairs\n' >&2
        return 2
    fi

    mkdir -p "${orchestrationRoot}"
    while [[ $# -gt 0 ]]; do
        labels+=("$1")
        runners+=("$2")
        logs+=("${orchestrationRoot}/$1.log")
        shift 2
    done

    set +e
    for i in "${!runners[@]}"; do
        (
            trap - EXIT INT TERM
            set -e
            runRegressionStep "${labels[$i]}" "${runners[$i]}"
        ) >"${logs[$i]}" 2>&1 &
        pids[$i]=$!
    done
    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        statuses[$i]=$?
    done
    set -e

    for i in "${!logs[@]}"; do
        [[ -f "${logs[$i]}" ]] && cat "${logs[$i]}"
        if [[ "${statuses[$i]}" -ne 0 && "${status}" -eq 0 ]]; then
            status=${statuses[$i]}
        fi
    done

    return "${status}"
}

runRegressionFastOnlySafety() {
    runRegressionStep commit-generated-file-directory-target runCommitGeneratedFileRejectsDirectoryTargetRegression &&
        runRegressionStep restore-managed-file-directory-target runRestoreManagedFileFromBackupRejectsDirectoryTargetRegression &&
        runRegressionStep github-release-direct-fallback runGitHubReleaseAssetDirectFallbackRegression &&
        runRegressionStep download-arg-missing-value runDownloadArgumentMissingValueRegression &&
        runRegressionStep fetch-url-wget-hard-limit runFetchUrlWgetHardLimitRegression &&
        runRegressionStep github-release-arg-missing-value runGitHubReleaseArgumentMissingValueRegression &&
        runRegressionStep remove-install-path-retry runRemoveInstallPathRetryRegression &&
        runRegressionStep remove-install-path-file-mode runRemoveInstallPathFileModeRegression &&
        runRegressionStep uninstall-padm-root-scope runUninstallPadmRootScopeRegression &&
        runRegressionStep remove-install-path-safety runRemoveInstallPathSafetyRegression &&
        runRegressionStep remove-nginx-default-conf-safety runRemoveNginxDefaultConfSafetyRegression &&
        runRegressionStep clean-agent-nginx-conf-safety runCleanAgentNginxConfSafetyRegression &&
        runRegressionStep uninstall-subscribe-nginx-path-safety runUninstallSubscribeNginxPathSafetyRegression &&
        runRegressionStep check-port-open-nginx-path-safety runCheckPortOpenNginxPathSafetyRegression &&
        runRegressionStep write-subscribe-nginx-path-safety runWriteSubscribeNginxPathSafetyRegression &&
        runRegressionStep write-wireguard-control-nginx-path-safety runWriteWireGuardControlNginxPathSafetyRegression &&
        runRegressionStep wireguard-firewall-lifecycle runSubscriptionWireGuardFirewallLifecycleRegression &&
        runRegressionStep wireguard-nginx-disable-lifecycle runSubscriptionWireGuardNginxDisableLifecycleRegression &&
        runRegressionStep write-alone-nginx-path-safety runWriteAloneNginxPathSafetyRegression &&
        runRegressionStep clean-last-installation-nginx-safety runCleanLastInstallationSkipsDuplicateNginxCleanupRegression &&
        runRegressionStep install-nginx-alpine-default-path-safety runInstallNginxAlpineDefaultPathSafetyRegression &&
        runRegressionStep install-nginx-static-unsafe-path runInstallNginxStaticRejectsUnsafePathRegression &&
        runRegressionStep install-nginx-static-unzip-failure runInstallNginxStaticPreservesLiveSiteOnUnzipFailureRegression &&
        runRegressionStep clean-last-installation-static-safety runCleanLastInstallationRejectsUnsafeStaticPathRegression &&
        runRegressionStep subscription-sync-path-safety runSubscriptionSyncPathSafetyRegression &&
        runRegressionStep subscription-sync-config-directory-target runSubscriptionSyncConfigRestoreRejectsDirectoryTargetRegression &&
        runRegressionStep subscription-sync-create-local-apply-backups-rollback runSubscriptionSyncCreateLocalApplyBackupsRollbackRegression &&
        runRegressionStep state-readers-clear-stale-values runStateReadersClearStaleValuesRegression &&
        runRegressionStep read-install-type-keeps-sing-box-shards runReadInstallTypeKeepsSingBoxShardsRegression &&
        runRegressionStep check-log-backup-output-variable runCheckLogBackupOutputVariableRegression &&
        runRegressionStep suppressed-regression-failure-propagation runSuppressedRegressionFailurePropagationRegression &&
        runRegressionStep subscription-sync-config-unmanaged-target runSubscriptionSyncConfigRestoreRejectsUnmanagedFileRegression &&
        runRegressionStep subscription-sync-missing-restore-scope runSubscriptionSyncMissingRestoreScopeRegression &&
        runRegressionStep no-third-party-qr-service runNoThirdPartyQrServiceRegression &&
        runRegressionStep install-refresh-download-bounds runInstallRefreshDownloadBoundsRegression
}

runRegressionFastOnlyOutputAutoInstall() {
    runRegressionStep auto-install-generated-identity runAutoInstallGeneratedIdentityRegression &&
        runRegressionStep auto-install-empty-defaults runAutoInstallAllowsEmptyDefaultRegression &&
        runRegressionStep auto-install-missing-required-no-stdin runAutoInstallDoesNotReadMissingRequiredValueRegression &&
        runRegressionStep auto-install-tls-domain-missing-returns runAutoInstallTlsDomainMissingReturnsRegression &&
        runRegressionStep auto-install-two-digit-single-protocol runAutoInstallTwoDigitSingleProtocolRegression
}

runRegressionFastOnlyOutputRest() {
    runRegressionStep client-name-suffix-preserves-random-prefix runClientNameSuffixPreservesRandomPrefixRegression &&
        runRegressionStep subscribe-local-cleanup runInitSubscribeLocalConfigCleansAllFormatsRegression &&
        runRegressionStep subscription-output-random-user runSubscriptionOutputRandomUserRegression &&
        runRegressionStep show-accounts-optional-step runShowAccountsOptionalStepRegression &&
        runRegressionStep show-accounts-xray-singbox-assist runShowAccountsXrayWithSingBoxAssistRegression &&
        runRegressionStep show-accounts-singbox-reality-grpc runShowAccountsSingBoxRealityGrpcRegression &&
        runRegressionStep trojan-grpc-account-template-filename runTrojanGrpcAccountUsesTemplateFilenameRegression &&
        runRegressionStep trojan-fallback-subscribe-entry runTrojanFallbackSubscribeUsesTlsEntryRegression &&
        runRegressionStep trojan-fallback-template-frontend runTrojanFallbackTemplateCreatesTlsFrontendRegression &&
        runRegressionStep parse-install-args-missing-value runParseInstallArgsMissingValueRegression &&
        runRegressionStep locale-unset-printN runLocaleEchoContentUnsetPrintNRegression &&
        runRegressionStep httpupgrade-incremental-starts-nginx runSingBoxHttpUpgradeIncrementalStartsNginxRegression &&
        runRegressionStep httpupgrade-rejects-unsafe-nginx-path runSingBoxHttpUpgradeRejectsUnsafeNginxPathRegression &&
        runRegressionStep allow-port-optional-protocol runAllowPortOptionalProtocolRegression &&
        runRegressionStep core-client-optional-args runCoreClientOptionalArgsRegression
}

runRegressionFastOnlyOutput() {
    runParallelFastTotals "${TMP_DIR}/fast-only-output-parallel-${BASHPID:-$$}" \
        auto-install runRegressionFastOnlyOutputAutoInstall \
        rest runRegressionFastOnlyOutputRest
}

runRegressionFastOnlyCore() {
    runRegressionStep singbox-mainpid-template runSingBoxServiceMainPidTemplateRegression &&
        runRegressionStep check-gfw-status-service-wait runCheckGFWStatusServiceWaitRegression &&
        runRegressionStep service-wait-state runServiceWaitForStateRegression &&
        runRegressionStep core-running-service-state runCoreRunningFallsBackToServiceStateRegression &&
        runRegressionStep warp-config-generation-failure runWarpConfigGenerationFailureRegression &&
        runRegressionStep fail2ban-profile runFail2banProfileRegression &&
        runRegressionStep fail2ban-sshd-systemd-backend runFail2banSshdSystemdBackendRegression &&
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

runRegressionFastOnly() {
    runParallelFastTotals "${TMP_DIR}/fast-only-parallel-${BASHPID:-$$}" \
        safety runRegressionFastOnlySafety \
        output runRegressionFastOnlyOutput \
        core runRegressionFastOnlyCore
}

runRegressionFast() {
    runParallelFastTotals "${TMP_DIR}/fast-parallel-${BASHPID:-$$}" \
        platform runRegressionPlatform \
        fast-only runRegressionFastOnly
}

if [[ "${PADM_REGRESSION_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

printf 'use shell/subscription_groups_regression.sh <selector>\n' >&2
exit 2
