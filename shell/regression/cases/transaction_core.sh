#!/usr/bin/env bash

if ! declare -F regressionProtocolSelectionIncludesCompat >/dev/null 2>&1; then
    regressionProtocolSelectionIncludesCompat() {
        local selection=$1
        local protocolId=$2
        local mode=${3:-}

        [[ "${mode}" == "all" ]] && return 0
        if [[ "${protocolId}" == "11" ]] && [[ ",${selection}," == *",23,"* ]]; then
            return 0
        fi
        protocolSelectionHasAny "${selection}" "${protocolId}"
    }
fi

runSingBoxStatsBuildRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/sing-box-stats-build"
    local version=v1.14.0 candidateVersion=v1.14.0 tags=with_quic,with_v2ray_api
    local singBoxCoreCPUVendor=-linux-amd64
    local packageDir="sing-box-${version#v}${singBoxCoreCPUVendor}"
    local serviceRunning=true serviceStops=0 statsResult=0 migrationCalls=0
    local PADM_SINGBOX_BINARY="${root}/installed/sing-box" PADM_TMP_DIR="${root}/tmp"
    local singBoxConfigPath="${root}/installed/conf/config/"
    mkdir -p "${root}/payload/${packageDir}" "${singBoxConfigPath}" "${PADM_TMP_DIR}"
    : >"${root}/stats-calls"

    fetchUrlToStdout() {
        case "$1" in
        'https://api.github.com/repos/neil1123-vip/padm/releases?per_page=50&page=1')
            jq -cn '[{tag_name:"sing-box-v1.13.0",prerelease:false},
              {tag_name:"sing-box-v1.16.0-alpha.1",prerelease:true},
              {tag_name:"sing-box-v9.0.0",prerelease:false,draft:true},
              {tag_name:"sing-box-invalid",prerelease:false}] +
              [range(46) | {tag_name:"v3.7.6",prerelease:false}]' ;;
        'https://api.github.com/repos/neil1123-vip/padm/releases?per_page=50&page=2')
            printf '%s\n' '[{"tag_name":"sing-box-v1.14.0","prerelease":false}]' ;;
        'https://api.github.com/repos/XTLS/Xray-core/releases/latest')
            printf '%s\n' '{"tag_name":"v26.3.27"}' ;;
        *) return 1 ;;
        esac
    }
    [[ "$(coreLatestReleaseTag SagerNet/sing-box)" == v1.14.0 ]]
    [[ "$(coreReleaseTags SagerNet/sing-box false 20)" == $'v1.14.0\nv1.13.0' ]]
    [[ "$(coreLatestReleaseTag SagerNet/sing-box true)" == v1.16.0-alpha.1 ]]
    [[ "$(coreLatestReleaseTag XTLS/Xray-core)" == v26.3.27 ]]
    (
        local latestMetadata
        fetchUrlToStdout() {
            [[ "$1" == */releases/latest ]] && printf '%s\n' "${latestMetadata}" || printf '[]\n'
        }
        for latestMetadata in '{}' '{"tag_name":null}' $'{"tag_name":"v1"}\n{"tag_name":"v2"}'; do
            regressionExpectStatus 1 coreLatestReleaseTag XTLS/Xray-core || return 1
        done
        fetchUrlToStdout() { : >"${root}/invalid-repo-fetch"; return 99; }
        regressionExpectStatus 1 coreLatestReleaseTag XTLS/Xray-core/extra || return 1
        [[ ! -e "${root}/invalid-repo-fetch" ]] || return 1
    ) || return 1
    (
        # 列表与 latest 入口都只接受单个 JSON 文档，坏响应不输出版本。
        local releaseMetadata releaseRepo
        fetchUrlToStdout() { printf '%s\n' "${releaseMetadata}"; }
        for releaseRepo in XTLS/Xray-core SagerNet/sing-box; do
            for releaseMetadata in '' '{}' 'null' $'[]\n[{"tag_name":"sing-box-v1.14.0","prerelease":false}]'; do
                regressionExpectStatus 1 coreReleaseTags "${releaseRepo}" false 1 >"${root}/invalid-release-tags" 2>/dev/null || return 1
                [[ ! -s "${root}/invalid-release-tags" ]] || return 1
            done
        done
    ) || return 1
    fetchUrlToStdout() { printf '[]\n'; }
    regressionExpectStatus 1 coreLatestReleaseTag SagerNet/sing-box

    makeStatsPackage() {
        printf '#!/usr/bin/env bash\nprintf "sing-box version %s\\nTags: %s\\n"\n' "${candidateVersion#v}" "${tags}" >"${root}/payload/${packageDir}/sing-box"
        chmod 755 "${root}/payload/${packageDir}/sing-box"
        printf 'new-cronet\n' >"${root}/payload/${packageDir}/libcronet.so"
        tar -czf "${root}/${packageDir}.tar.gz" -C "${root}/payload" "${packageDir}"
    }
    downloadGitHubReleaseAsset() {
        [[ "$1" == -P && "$3" == neil1123-vip/padm && "$4" == "sing-box-${version}" && "$5" == "${packageDir}.tar.gz" ]] || return 1
        mkdir -p "$2"
        cp "${root}/${packageDir}.tar.gz" "$2/$5"
    }
    makeStatsPackage
    downloadSingBoxReleaseBinaryToTempDir "${version}" "${root}/good"
    [[ "$(singBoxV2rayApiCapability "${root}/good/${packageDir}/sing-box")" == supported ]]
    [[ "$(singBoxV2rayApiCapability "${root}/missing")" == unknown ]]
    tags=with_v2ray_apix
    makeStatsPackage
    regressionExpectStatus 4 downloadSingBoxReleaseBinaryToTempDir "${version}" "${root}/unsupported"
    tags=with_v2ray_api
    candidateVersion=v1.13.0
    makeStatsPackage
    regressionExpectStatus 4 downloadSingBoxReleaseBinaryToTempDir "${version}" "${root}/wrong-version"

    printf '#!/usr/bin/env bash\nprintf "sing-box version 1.14.0\\nTags: with_quic\\n"\n' >"${PADM_SINGBOX_BINARY}"
    chmod 755 "${PADM_SINGBOX_BINARY}"
    printf 'old-cronet\n' >"${root}/installed/libcronet.so"
    local originalBinary
    originalBinary=$(<"${PADM_SINGBOX_BINARY}")
    (
        local lastInstallationConfig=reused installCalls=0
        readInstallType() { return 0; }
        singBoxConfigInstalled() { return 0; }
        coreLatestReleaseTag() { printf 'v1.14.0\n'; }
        autoRead() { return 99; }
        installDownloadedSingBoxBinary() {
            [[ "$1" == "${version}" ]] || return 1
            installCalls=$((installCalls + 1))
        }
        installSingBoxApply 1
        [[ "${installCalls}" == 1 ]]
    )
    singBoxConfigInstalled() { return 0; }
    validateSingBoxConfigWithBinary() { return 0; }
    migrateSingBox116DeprecatedConfig() { migrationCalls=$((migrationCalls + 1)); }
    runCoreServiceActionAllowFailure() {
        [[ "$1" == handleSingBox ]] || return 1
        case "$2" in
        stop) serviceRunning=false; serviceStops=$((serviceStops + 1)) ;;
        start) serviceRunning=true ;;
        *) return 1 ;;
        esac
    }
    singBoxRunning() { [[ "${serviceRunning}" == true ]]; }
    ensureSingBoxTrafficStatsConfig() {
        [[ "$(singBoxV2rayApiCapability)" == supported ]] || return 1
        printf 'stats\n' >>"${root}/stats-calls"
        return "${statsResult}"
    }
    (
        local entry candidate candidateVersion downloadCalls=0
        local oldCronet
        oldCronet=$(<"${root}/installed/libcronet.so")
        padmCreateTempPath() {
            local candidateTmp
            [[ "$2" == -d ]] || return 1
            candidateTmp=$(mktemp -d "${PADM_TMP_DIR}/candidate.XXXXXX") || return 1
            printf -v "$1" '%s' "${candidateTmp}"
        }
        # 两种入口都在迁移和停服前重新核对版本，不依赖下载 helper 的旧校验结果。
        downloadSingBoxReleaseBinaryToTempDir() {
            local extractedDir="$2/${packageDir}"
            downloadCalls=$((downloadCalls + 1))
            mkdir -p "${extractedDir}"
            printf '#!/usr/bin/env bash\nprintf "sing-box version %s\\nTags: with_v2ray_api\\n"\n' "${candidateVersion}" >"${extractedDir}/sing-box"
            chmod 755 "${extractedDir}/sing-box"
            printf 'new-cronet\n' >"${extractedDir}/libcronet.so"
        }
        for entry in downloaded prepared; do
            for candidateVersion in 1.13.0 ''; do
                candidate=
                downloadCalls=0
                if [[ "${entry}" == prepared ]]; then
                    candidate="${root}/candidate"
                    downloadSingBoxReleaseBinaryToTempDir "${version}" "${candidate}"
                fi
                regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${candidate}"
                [[ "${downloadCalls}" == 1 ]]
                [[ "${serviceStops}" == 0 && "${migrationCalls}" == 0 && ! -s "${root}/stats-calls" ]]
                [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" ]]
                [[ "$(<"${root}/installed/libcronet.so")" == "${oldCronet}" ]]
            done
        done
    )
    regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${root}/unsupported"
    [[ "${serviceStops}" == 0 && "${migrationCalls}" == 0 && ! -s "${root}/stats-calls" ]]
    [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" ]]

    # 两个提交位置失败都恢复旧文件；二进制失败时不再写入 Cronet。
    local failAt
    for failAt in 1 2; do
        (
            local commitCalls=0 candidate="${root}/commit-fail-${failAt}"
            cp -a "${root}/good" "${candidate}"
            commitStagedCoreInstallFile() {
                commitCalls=$((commitCalls + 1))
                [[ "${commitCalls}" != "${failAt}" ]] || return 1
                command cp "$1" "$2"
            }
            regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${candidate}" || return 1
            [[ "${commitCalls}" == "${failAt}" && "${serviceStops}" == 1 && "${serviceRunning}" == true ]] || return 1
            [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" &&
                "$(<"${root}/installed/libcronet.so")" == old-cronet && ! -e "${candidate}" && ! -s "${root}/stats-calls" ]] || return 1
            ! compgen -G "${root}/installed/.*.bak.*" >/dev/null || return 1
        ) || return 1
    done

    statsResult=1
    regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${root}/good"
    [[ "$(wc -l <"${root}/stats-calls")" == 1 && "${serviceStops}" == 2 && "${serviceRunning}" == true ]]
    [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" ]]
    [[ "$(<"${root}/installed/libcronet.so")" == old-cronet ]]

    statsResult=0
    candidateVersion=${version}
    makeStatsPackage
    downloadSingBoxReleaseBinaryToTempDir "${version}" "${root}/good"
    installDownloadedSingBoxBinary "${version}" "${root}/good"
    [[ "$(wc -l <"${root}/stats-calls")" == 2 && "${serviceRunning}" == true ]]
    [[ "$(singBoxV2rayApiCapability)" == supported ]]
    [[ "$(<"${root}/installed/libcronet.so")" == new-cronet ]]
    (
        local lastInstallationConfig=reused
        printf '%s\n' "${originalBinary}" >"${PADM_SINGBOX_BINARY}"
        readInstallType() { return 0; }
        singBoxConfigInstalled() { return 1; }
        coreLatestReleaseTag() { printf 'v1.14.0\n'; }
        installDownloadedSingBoxBinary() { return 99; }
        padmCreateTempPath() {
            local installTemp
            if [[ "${2:-}" == -d ]]; then
                installTemp=$(mktemp -d "${PADM_TMP_DIR}/install.XXXXXX") || return 1
            else
                installTemp=$(mktemp "${PADM_TMP_DIR}/install.XXXXXX") || return 1
            fi
            printf -v "$1" '%s' "${installTemp}"
        }
        installSingBoxApply 1
        [[ "$(singBoxV2rayApiCapability)" == supported ]]
        [[ "$(<"${root}/installed/libcronet.so")" == new-cronet ]]
    )
    (
        source "${PROJECT_ROOT}/shell/subscription/traffic.sh"
        local PADM_SINGBOX_CONFIG_DIR="${singBoxConfigPath%/}"
        local expectedStats="${PADM_SINGBOX_CONFIG_DIR}/14_stats_api.json"
        singBoxConfigPath=
        printf '%s\n' '{"inbounds":[{"type":"hysteria2","users":[{"name":"sub_team_hy2","password":"test"}]}]}' >"${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json"
        singBoxMergeConfig() {
            cp "${expectedStats}" "$(singBoxMergedConfigFile)"
        }
        runServiceAction() {
            [[ "$*" == 'sing-box restart' ]] || return 99
            printf '%s\n' "$*" >>"${root}/stats-service"
        }
        reloadCore() { return 99; }
        downloadSingBoxReleaseBinaryToTempDir "${version}" "${root}/real-stats"
        installDownloadedSingBoxBinary "${version}" "${root}/real-stats"
        jq -e '.experimental.v2ray_api.stats.users == ["sub_team_hy2"]' "${expectedStats}" >/dev/null
        [[ "$(<"${root}/stats-service")" == 'sing-box restart' && -z "${singBoxConfigPath}" ]]
    )
    (
        local lastInstallationConfig=reused statsRollbackDir=
        local legacyFile="${singBoxConfigPath}stats-migration.json"
        printf '%s\n' "${originalBinary}" >"${PADM_SINGBOX_BINARY}"
        chmod 755 "${PADM_SINGBOX_BINARY}"
        printf 'old-cronet\n' >"${root}/installed/libcronet.so"
        printf '{"phase":"legacy"}\n' >"${legacyFile}"
        readInstallType() { return 0; }
        xrayRunning() { return 1; }
        coreLatestReleaseTag() { printf 'v1.14.0\n'; }
        eval "$(declare -f padmCreateTempPath | sed '1s/padmCreateTempPath/statsFixtureCreateTempPath/')"
        padmCreateTempPath() {
            if [[ "${2:-}" == -d && "${3:-}" == /etc/padm/* ]]; then
                statsFixtureCreateTempPath "$1" -d "${PADM_TMP_DIR}/install.XXXXXX"
            else
                statsFixtureCreateTempPath "$@"
            fi
        }
        coreTemplateConfigBackupCreate() { checkLogBackupCreate "$1" "${legacyFile}"; }
        migrateSingBox116DeprecatedConfig() {
            local savedMigration
            checkLogBackupCreate savedMigration "${legacyFile}" || return 1
            printf '{"phase":"migrated"}\n' >"${legacyFile}" || return 1
            printf -v "$1" '%s' "${savedMigration}"
        }
        runCoreServiceActionAllowFailure() {
            [[ "$1" != handleXray ]] || { [[ "$2" == stop ]]; return $?; }
            [[ "$1" == handleSingBox ]] || return 1
            case "$2" in
            stop) serviceRunning=false ;;
            start)
                local expectedPhase=legacy
                [[ "$(singBoxV2rayApiCapability)" != supported ]] || expectedPhase=migrated
                [[ -x "${PADM_SINGBOX_BINARY}" && "$(jq -r .phase "${legacyFile}")" == "${expectedPhase}" ]] || return 1
                serviceRunning=true
                ;;
            *) return 1 ;;
            esac
        }
        failAfterStatsUpgrade() {
            statsRollbackDir=${statsBinaryBackupDir}
            installSingBox 1 || return 1
            [[ "$(singBoxV2rayApiCapability)" == supported &&
                "$(<"${root}/installed/libcronet.so")" == new-cronet &&
                "$(jq -r .phase "${legacyFile}")" == migrated ]] || return 1
            return 7
        }
        # 升级自身成功后，下游安装失败仍须成套恢复旧核心、依赖、配置和运行态。
        regressionExpectStatus 7 coreInstallConfigTransaction sing-box failAfterStatsUpgrade
        [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" && -x "${PADM_SINGBOX_BINARY}" &&
            "$(<"${root}/installed/libcronet.so")" == old-cronet &&
            "$(jq -r .phase "${legacyFile}")" == legacy && "${serviceRunning}" == true &&
            -n "${statsRollbackDir}" && ! -e "${statsRollbackDir}" ]]
        rm -f -- "${root}/installed/libcronet.so"
        printf '%s\n' "${originalBinary}" >"${PADM_SINGBOX_BINARY}"
        chmod 755 "${PADM_SINGBOX_BINARY}"
        printf '{"phase":"legacy"}\n' >"${legacyFile}"
        serviceRunning=true
        statsRollbackDir=
        regressionExpectStatus 7 coreInstallConfigTransaction sing-box failAfterStatsUpgrade
        [[ "$(<"${PADM_SINGBOX_BINARY}")" == "${originalBinary}" && -x "${PADM_SINGBOX_BINARY}" &&
            ! -e "${root}/installed/libcronet.so" &&
            "$(jq -r .phase "${legacyFile}")" == legacy && "${serviceRunning}" == true &&
            -n "${statsRollbackDir}" && ! -e "${statsRollbackDir}" ]]
    )
)

runSingBoxCustomPathsRegression() (
    set -euo pipefail
    source "${PROJECT_ROOT}/shell/regression/bootstrap.sh"
    local root="${TMP_DIR}/sing-box custom paths" singBoxConfigPath=
    export PADM_SINGBOX_BINARY="${root}/bin/sing-box"
    export PADM_SINGBOX_CONFIG_DIR="${root}/conf/config"
    export PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${root}/sing-box.service"
    export PADM_SINGBOX_OPENRC_SERVICE_FILE="${root}/sing-box.init"
    export PADM_XRAY_BINARY="${root}/bin/xray"
    export PADM_XRAY_CONF_DIR="${root}/xray/conf"
    export PADM_XRAY_SYSTEMD_SERVICE_FILE="${root}/xray.service"
    export PADM_XRAY_OPENRC_SERVICE_FILE="${root}/xray.init"
    export PADM_TMP_DIR="${root}/tmp"
    mkdir -p "${root}/tmp" "${PADM_SINGBOX_CONFIG_DIR}" "${PADM_XRAY_CONF_DIR}"
    local serviceFinalizeLog="${root}/service-finalize.log"
    : >"${serviceFinalizeLog}"
    [[ "$(singBoxConfigShardDir)" == "${PADM_SINGBOX_CONFIG_DIR}/" ]]
    [[ "$(tuicConfigFile)" == "${PADM_SINGBOX_CONFIG_DIR}/09_tuic_inbounds.json" ]]
    singBoxConfigPath="${root}/staged/"
    [[ "$(singBoxConfigShardDir)" == "${singBoxConfigPath}" ]]
    singBoxConfigPath=

    (
        # 单独加载 runtime 与完整核心的路径解析保持一致。
        local PADM_XRAY_CONF_DIR="${root}/xray/conf/"
        source "${PROJECT_ROOT}/shell/core/runtime.sh"
        [[ "$(coreXrayConfigDir)" == "${PADM_XRAY_CONF_DIR%/}" ]]
        source "${PROJECT_ROOT}/shell/core/cores.sh"
        [[ "$(coreXrayConfigDir)" == "${PADM_XRAY_CONF_DIR%/}" ]]
        [[ "$(coreXrayBinaryPath)" == "${PADM_XRAY_BINARY}" ]]
        [[ "$(coreSingBoxBinaryPath)" == "${PADM_SINGBOX_BINARY}" ]]
    )

    (
        # 目录中的 glob 字符必须按字面处理，真实分片仍需进入升级校验。
        local singBoxConfigPath= configName
        local PADM_SINGBOX_CONFIG_DIR="${root}/config[1]*"
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
        regressionExpectStatus 1 singBoxConfigInstalled
        for configName in inbound.json 'inbound[1]*.json'; do
            printf '{}\n' >"${PADM_SINGBOX_CONFIG_DIR}/${configName}"
            singBoxConfigInstalled
            singBoxMergeConfigForValidation() { return 23; }
            regressionExpectStatus 1 validateSingBoxConfigWithBinary /usr/bin/true "${root}/literal-path-check.log"
            rm -f -- "${PADM_SINGBOX_CONFIG_DIR}/${configName}"
        done
        printf '{}\n' >"$(singBoxMergedConfigFile)"
        singBoxConfigInstalled
    )

    (
        # 仅设置目录覆盖时，DNS 检查和初始化不能读取或写入默认目录。
        local dnsConfigDir="${root}/dns-only/config"
        local PADM_SINGBOX_CONFIG_DIR="${dnsConfigDir}" singBoxConfigPath=
        mkdir -p "${dnsConfigDir}"
        coreSafeConfigDir() {
            [[ "${1%/}" == "${dnsConfigDir}" ]] || return 1
            printf '%s/\n' "${1%/}"
        }
        initSingBoxLocalDNSConfig check
        [[ ! -e "${dnsConfigDir}/dns.json" ]]
        initSingBoxLocalDNSConfig
        jq -e '.dns.servers == [{tag: "padm-local", type: "local"}]' "${dnsConfigDir}/dns.json" >/dev/null
        initSingBoxLocalDNSConfig check
    )

    (
        local probeBinary="${root}/xray-path-probe" pathCalls="${root}/path-calls"
        cp /usr/bin/true "${probeBinary}"
        xrayServiceBinaryPath() {
            printf 'x' >>"${pathCalls}"
            printf '%s\n' "${probeBinary}"
        }
        serviceInstalled xray
        [[ "$(<"${pathCalls}")" == x ]]
    )

    padmCommandExists() { [[ "$1" == systemctl || "$1" == rc-service ]]; }
    bootStartup() { return 0; }
    coreStartupServiceEnabled() { return 1; }
    checkLogBackupCreate() { printf -v "$1" '%s' ''; }
    coreInstallServiceBackupFinalize() { printf '%s\n' "$2" >>"${serviceFinalizeLog}"; }
    local release=debian
    (
        # 缺少服务管理器时不得创建服务文件、收尾备份或误报成功。
        local installer REGRESSION_SUCCESS_CARD_LOG="${root}/missing-manager-success.log"
        padmCommandExists() { return 1; }
        for installer in installSingBoxService installXrayService; do
            regressionExpectStatus 1 "${installer}" test >/dev/null || return 1
        done
        [[ ! -e "${PADM_SINGBOX_SYSTEMD_SERVICE_FILE}" && ! -e "${PADM_XRAY_SYSTEMD_SERVICE_FILE}" ]] || return 1
        [[ ! -s "${serviceFinalizeLog}" && ! -s "${REGRESSION_SUCCESS_CARD_LOG}" ]] || return 1
    ) || return 1
    installSingBoxService test >/dev/null
    grep -Fxq "ExecStart=\"${PADM_SINGBOX_BINARY}\" run -c \"${root}/conf/config.json\"" "${PADM_SINGBOX_SYSTEMD_SERVICE_FILE}"
    installAlpineStartup sing-box
    bash -n "${PADM_SINGBOX_OPENRC_SERVICE_FILE}"
    source "${PADM_SINGBOX_OPENRC_SERVICE_FILE}"
    [[ "${command}" == "${PADM_SINGBOX_BINARY}" ]]
    [[ "${command_args}" == "run -c \"${root}/conf/config.json\"" ]]
    installXrayService test >/dev/null
    grep -qx 'xray' "${serviceFinalizeLog}"
    grep -Fxq "ExecStart=\"${PADM_XRAY_BINARY}\" run -confdir \"${PADM_XRAY_CONF_DIR}\"" "${PADM_XRAY_SYSTEMD_SERVICE_FILE}"
    installAlpineStartup xray
    bash -n "${PADM_XRAY_OPENRC_SERVICE_FILE}"
    source "${PADM_XRAY_OPENRC_SERVICE_FILE}"
    [[ "${command}" == "${PADM_XRAY_BINARY}" ]]
    [[ "${command_args}" == "run -confdir \"${PADM_XRAY_CONF_DIR}\"" ]]

    local PADM_SINGBOX_LOG_CONFIG_FILE="${root}/conf/config/log.json"
    jq -n --arg output "${root}/conf/custom.log" '{log:{output:$output}}' >"${PADM_SINGBOX_LOG_CONFIG_FILE}"
    [[ "$(singBoxLogOutputFile)" == "${root}/conf/custom.log" ]]
    rm -f "${PADM_SINGBOX_LOG_CONFIG_FILE}"
    [[ "$(singBoxLogOutputFile)" == "${root}/conf/box.log" ]]
    (
        local managerLog="${root}/service-manager.log"
        : >"${managerLog}"
        padmCommandExists() { [[ "$1" == rc-service ]]; }
        systemctl() { printf 'systemd:%s\n' "$*" >>"${managerLog}"; return 1; }
        rc-service() { printf 'openrc:%s\n' "$*" >>"${managerLog}"; return 0; }
        singBoxRunning() { return 1; }
        singBoxMergeConfig() { return 0; }
        waitForServiceState() { return 0; }
        handleSingBox start >/dev/null 2>&1
        [[ "$(<"${managerLog}")" == 'openrc:sing-box start' ]]
    )
    (
        # 两套服务文件并存时，状态检查和启停必须使用同一个管理器。
        local service managerRc=3 managerLog="${root}/mixed-manager.log"
        release=debian
        pgrep() { return 1; }
        sleep() { return 0; }
        singBoxMergeConfig() { return 0; }
        validateXrayConfigWithBinary() { return 0; }
        padmCommandExists() { [[ "$1" == systemctl || "$1" == rc-service ]]; }
        systemctl() {
            printf 'systemd:%s\n' "$*" >>"${managerLog}"
            case "$1" in
            is-active) return "${managerRc}" ;;
            start) managerRc=0 ;;
            stop) managerRc=3 ;;
            esac
        }
        rc-service() { printf 'openrc:%s\n' "$*" >>"${managerLog}"; return 0; }
        for service in xray sing-box; do
            managerRc=3
            : >"${managerLog}"
            regressionExpectStatus 1 serviceRunning "${service}"
            runServiceAction "${service}" start >/dev/null 2>&1
            serviceRunning "${service}"
            runServiceAction "${service}" stop >/dev/null 2>&1
            regressionExpectStatus 1 serviceRunning "${service}"
            grep -qx "systemd:start ${service}.service" "${managerLog}"
            grep -qx "systemd:stop ${service}.service" "${managerLog}"
            ! grep -q '^openrc:' "${managerLog}"
        done
    )

    local -a procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${root}/conf/config.json") parsedArgs=()
    printf '%s\0' "${procArgsFixture[@]}" >"${root}/cmdline"
    padmReadProcArgs parsedArgs "${root}/cmdline"
    [[ "${#parsedArgs[@]}" == 4 && "${parsedArgs[3]}" == "${root}/conf/config.json" ]]
    pgrep() { printf '123\n'; }
    padmReadProcExe() { printf '%s\n' "${PADM_SINGBOX_BINARY}"; }
    padmReadProcArgs() { local -n argsRef=$1; argsRef=("${procArgsFixture[@]}"); }
    padmCommandExists() { return 1; }
    singBoxRunning
    procArgsFixture[3]="${root}/conf/config.json.old"
    regressionExpectStatus 1 singBoxRunning
    procArgsFixture[3]="${root}/conf/config.json old"
    regressionExpectStatus 1 singBoxRunning
    procArgsFixture[3]="${root}/other.json"
    regressionExpectStatus 1 singBoxRunning
    procArgsFixture[3]="${root}/conf/config.json"
    padmReadProcExe() { printf '%s (deleted)\n' "${PADM_SINGBOX_BINARY}"; }
    singBoxRunning
    (
        local config="${root}/conf/config.json" flag value expected
        # 对照真实 Cobra 参数：配置累加，帮助布尔取最后值，字符串值不当命令。
        procArgsFixture=("${PADM_SINGBOX_BINARY}" -c "${config}" run)
        singBoxRunning || return 1
        for flag in -c --config; do
            procArgsFixture=("${PADM_SINGBOX_BINARY}" run "${flag}=${config}" --disable-color)
            singBoxRunning || return 1
            procArgsFixture=("${PADM_SINGBOX_BINARY}" run "${flag}" "${root}/extra.json" "${flag}" "${config}")
            singBoxRunning || return 1
        done
        procArgsFixture=("${PADM_SINGBOX_BINARY}" run "-c${config}" "-D${root}" "-C${root}/conf")
        singBoxRunning || return 1
        for flag in --help -h; do
            for value in false False FALSE 0 f F true True TRUE 1 t T invalid; do
                expected=1
                [[ "${value}" != false && "${value}" != False && "${value}" != FALSE &&
                    "${value}" != 0 && "${value}" != f && "${value}" != F ]] || expected=0
                procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${config}" "${flag}=${value}")
                regressionExpectStatus "${expected}" singBoxRunning || return 1
            done
            procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${config}" "${flag}" "${flag}=false")
            singBoxRunning || return 1
            procArgsFixture+=("${flag}=true")
            regressionExpectStatus 1 singBoxRunning || return 1
        done
        procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${config}" -hh=false)
        singBoxRunning || return 1
        procArgsFixture=("${PADM_SINGBOX_BINARY}" run run -c "${config}" -- check --help)
        singBoxRunning || return 1
        procArgsFixture=("${PADM_SINGBOX_BINARY}" -c "${config}" -- run)
        regressionExpectStatus 1 singBoxRunning || return 1
        procArgsFixture=("${PADM_SINGBOX_BINARY}" -D run -c "${config}")
        regressionExpectStatus 1 singBoxRunning || return 1
        for flag in --help -h -dh --help=invalid -f; do
            procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${config}" "${flag}")
            regressionExpectStatus 1 singBoxRunning || return 1
        done
        procArgsFixture=("${PADM_SINGBOX_BINARY}" check -c "${config}")
        regressionExpectStatus 1 singBoxRunning || return 1
        procArgsFixture=("${PADM_SINGBOX_BINARY}" "" run -c "${config}")
        regressionExpectStatus 1 singBoxRunning || return 1
        procArgsFixture=("${PADM_SINGBOX_BINARY}" run -c "${config}" -D)
        regressionExpectStatus 1 singBoxRunning || return 1
    ) || return 1

    (
        local PADM_XRAY_BINARY="${root}/bin/custom-xray"
        local PADM_SINGBOX_BINARY="${root}/bin/custom-sing-box"
        local PADM_XRAY_CONF_DIR="${root}/custom-conf" service processBinary fixtureConfig
        # 候选进程名可以自定义；仍须拒绝其它可执行文件或配置。
        pgrep() { [[ "$1" == -f && "$2" == . ]] && printf '123\n'; }
        for service in xray sing-box; do
            if [[ "${service}" == xray ]]; then
                processBinary=${PADM_XRAY_BINARY}
                fixtureConfig=${PADM_XRAY_CONF_DIR}
                procArgsFixture=("${processBinary}" run -confdir "${fixtureConfig}")
            else
                processBinary=${PADM_SINGBOX_BINARY}
                fixtureConfig="${root}/conf/config.json"
                procArgsFixture=("${processBinary}" run -c "${fixtureConfig}")
            fi
            padmReadProcExe() { printf '%s\n' "${processBinary}"; }
            serviceRunning "${service}" || return 1
            procArgsFixture[3]+=.wrong
            regressionExpectStatus 1 serviceRunning "${service}" || return 1
            procArgsFixture[3]=${fixtureConfig}
            processBinary="${root}/other-core"
            regressionExpectStatus 1 serviceRunning "${service}" || return 1
        done
    ) || return 1

    local PADM_XRAY_BINARY="${root}/bin/xray" PADM_XRAY_CONF_DIR="${root}/xray/conf"
    local processBinary="${PADM_XRAY_BINARY}"
    procArgsFixture=("${PADM_XRAY_BINARY}" run -confdir "${PADM_XRAY_CONF_DIR}")
    padmReadProcExe() { printf '%s\n' "${processBinary}"; }
    xrayRunning
    procArgsFixture+=(-test)
    regressionExpectStatus 1 xrayRunning
    procArgsFixture[4]=-test=true
    regressionExpectStatus 1 xrayRunning
    unset 'procArgsFixture[4]'
    procArgsFixture[3]="${PADM_XRAY_CONF_DIR}.old"
    regressionExpectStatus 1 xrayRunning
    procArgsFixture[3]="${PADM_XRAY_CONF_DIR} old"
    regressionExpectStatus 1 xrayRunning
    procArgsFixture[3]=${PADM_XRAY_CONF_DIR}
    processBinary="${root}/other/xray"
    regressionExpectStatus 1 xrayRunning
    processBinary="${PADM_XRAY_BINARY} (deleted)"
    xrayRunning
    PADM_XRAY_CONF_DIR="${root}/xray/ -test /conf"
    procArgsFixture[3]=${PADM_XRAY_CONF_DIR}
    xrayRunning
    procArgsFixture=("${PADM_XRAY_BINARY}" -confdir "${PADM_XRAY_CONF_DIR}")
    xrayRunning
    (
        # 运行目录和辅助开关按最后有效值判断，不能误跳过托管服务启动。
        local flag boolValue actions=
        handleXray() { actions+="$1"$'\n'; }
        procArgsFixture=("${PADM_XRAY_BINARY}" run -confdir "${PADM_XRAY_CONF_DIR}" -confdir "${root}/foreign")
        regressionExpectStatus 1 xrayRunning || return 1
        runServiceAction xray start || return 1
        [[ "${actions}" == $'start\n' ]] || return 1
        for flag in -confdir --confdir; do
            procArgsFixture=("${PADM_XRAY_BINARY}" run "${flag}=${root}/foreign" "${flag}=${PADM_XRAY_CONF_DIR}")
            xrayRunning || return 1
            actions=
            runServiceAction xray start || return 1
            [[ -z "${actions}" ]] || return 1
            procArgsFixture=("${PADM_XRAY_BINARY}" run "${flag}" "${PADM_XRAY_CONF_DIR}" "${flag}" "${root}/foreign")
            regressionExpectStatus 1 xrayRunning || return 1
        done
        for flag in -test --test -dump --dump; do
            procArgsFixture=("${PADM_XRAY_BINARY}" run -confdir "${PADM_XRAY_CONF_DIR}" "${flag}")
            regressionExpectStatus 1 xrayRunning || return 1
            for boolValue in 0 f F false FALSE False; do
                procArgsFixture=("${PADM_XRAY_BINARY}" run --confdir="${PADM_XRAY_CONF_DIR}" "${flag}" "${flag}=${boolValue}")
                xrayRunning || return 1
            done
            procArgsFixture+=("${flag}=true")
            regressionExpectStatus 1 xrayRunning || return 1
        done
        for flag in -- positional; do
            procArgsFixture=("${PADM_XRAY_BINARY}" run -confdir "${PADM_XRAY_CONF_DIR}" "${flag}" -confdir "${root}/foreign" -test)
            xrayRunning || return 1
            procArgsFixture=("${PADM_XRAY_BINARY}" run "${flag}" -confdir "${PADM_XRAY_CONF_DIR}")
            regressionExpectStatus 1 xrayRunning || return 1
        done
        for flag in -c --c -config --config -format --format; do
            procArgsFixture=("${PADM_XRAY_BINARY}" run "${flag}" -test -confdir "${PADM_XRAY_CONF_DIR}")
            xrayRunning || return 1
            procArgsFixture=("${PADM_XRAY_BINARY}" run "${flag}" -confdir "${PADM_XRAY_CONF_DIR}")
            regressionExpectStatus 1 xrayRunning || return 1
        done
    ) || return 1
    (
        # 符号链接启动仍按原 argv 校验，/proc 的真实可执行路径不能误判为停服。
        local service realBinary linkBinary PADM_XRAY_CONF_DIR="${root}/xray/conf"
        local PADM_XRAY_BINARY PADM_SINGBOX_BINARY
        mkdir -p "${root}/real" "${root}/links"
        handleXray() { return 99; }
        handleSingBox() { return 99; }
        for service in xray sing-box; do
            realBinary="${root}/real/${service}"
            linkBinary="${root}/links/${service}"
            cp /usr/bin/true "${realBinary}"
            ln -s "${realBinary}" "${linkBinary}"
            if [[ "${service}" == xray ]]; then
                PADM_XRAY_BINARY="${linkBinary}"
                procArgsFixture=("${linkBinary}" run -confdir "${PADM_XRAY_CONF_DIR}")
            else
                PADM_SINGBOX_BINARY="${linkBinary}"
                procArgsFixture=("${linkBinary}" run -c "${root}/conf/config.json")
            fi
            processBinary="${realBinary}"
            serviceRunning "${service}" || return 1
            runServiceAction "${service}" start || return 1
            processBinary="${realBinary} (deleted)"
            serviceRunning "${service}" || return 1
            processBinary="${root}/foreign/${service}"
            regressionExpectStatus 1 serviceRunning "${service}" || return 1
            processBinary="${realBinary}"
            procArgsFixture[3]+=.old
            regressionExpectStatus 1 serviceRunning "${service}" || return 1
        done
    ) || return 1
    PADM_SINGBOX_BINARY="${root}/unsafe%path"
    regressionExpectStatus 1 installSingBoxService test >/dev/null
)

runCoreReleaseArchiveRejectsRegression() (
    local mode=$1
    local root="${TMP_DIR}/core-release-archive-${mode}"
    local tmpDir="${root}/tmp"
    local xrayRc singBoxRc
    local xrayListing singBoxListing singBoxLongListing singBoxExtract

    rm -rf "${root}"
    mkdir -p "${tmpDir}"
    if [[ "${mode}" == unsafe-path ]]; then
        # 正常 Unix 权限条目必须兼容旧版 awk，链接条目仍拒绝。
        python3 - "${tmpDir}/regular.zip" "${tmpDir}/linked.zip" <<'PY'
import sys
import zipfile
for path, mode in zip(sys.argv[1:], [0o100755, 0o120777]):
    with zipfile.ZipFile(path, "w") as archive:
        entry = zipfile.ZipInfo("xray")
        entry.create_system = 3
        entry.external_attr = mode << 16
        archive.writestr(entry, "payload")
PY
        validateCoreZipArchive "${tmpDir}/regular.zip" || return 1
        regressionExpectStatus 1 validateCoreZipArchive "${tmpDir}/linked.zip" || return 1
    fi
    xrayCoreCPUVendor=Xray-linux-64
    singBoxCoreCPUVendor=-linux-amd64
    if [[ "${mode}" == "symlink-payload" ]]; then
        xrayListing=xray
        singBoxListing=$'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so'
        singBoxLongListing=$'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/\n-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box\nlrwxrwxrwx root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so -> /tmp/libcronet.so'
        singBoxExtract=$'sing-box\ncronet'
    else
        xrayListing=../xray
        singBoxListing=../sing-box
        singBoxLongListing='-rw-r--r-- root/root 0 2026-01-01 00:00 ../sing-box'
        singBoxExtract=sing-box
    fi
    downloadGitHubReleaseAsset() {
        local outputDir= assetName=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -P) outputDir=$2; shift 2 ;;
            *) assetName=$1; shift ;;
            esac
        done
        mkdir -p "${outputDir}"
        : >"${outputDir}/${assetName}"
    }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf '%s\n' "${xrayListing}"
            return 0
        fi
        if [[ "${mode}" == "symlink-payload" && "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' 'lrwxrwxrwx  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        if [[ "${mode}" == "symlink-payload" ]]; then
            mkdir -p "${dest}/xray"
        else
            printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/xray"
            chmod 755 "${dest}/xray"
        fi
    }
    tar() {
        case "$1" in
        -tzf) printf '%s\n' "${singBoxListing}"; return 0 ;;
        -tvzf) printf '%s\n' "${singBoxLongListing}"; return 0 ;;
        -xOzf) printf '%s\n' "${singBoxExtract}"; return 0 ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C) dest=$2; shift 2 ;;
            *) shift ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nexit 0\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    downloadXrayReleaseBinaryToTempDir v1.2.3 "${tmpDir}/xray"
    xrayRc=$?
    downloadSingBoxReleaseBinaryToTempDir v1.2.3 "${tmpDir}/sing"
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" -ne 0 ]]
    [[ "${singBoxRc}" -ne 0 ]]
    (
        local candidateVersion=1.2.2 candidateExit=0
        local xrayPath="${tmpDir}/version-check/xray"
        mkdir -p "$(dirname -- "${xrayPath}")"
        validateCoreZipArchive() { return 0; }
        unzip() {
            printf '#!/usr/bin/env bash\nprintf "Xray %s\\n"\nexit %s\n' "${candidateVersion}" "${candidateExit}" >"${xrayPath}"
            chmod 755 "${xrayPath}"
        }
        regressionExpectStatus 4 downloadXrayReleaseBinaryToTempDir v1.2.3 "$(dirname -- "${xrayPath}")"
        candidateVersion=
        regressionExpectStatus 4 downloadXrayReleaseBinaryToTempDir v1.2.3 "$(dirname -- "${xrayPath}")"
        candidateVersion=1.2.3
        downloadXrayReleaseBinaryToTempDir v1.2.3 "$(dirname -- "${xrayPath}")"
        # 关闭 pipefail 后，失败探针也不得输出可被后续校验接受的版本。
        set +o pipefail
        candidateExit=42
        regressionExpectStatus 4 downloadXrayReleaseBinaryToTempDir v1.2.3 "$(dirname -- "${xrayPath}")"
        regressionExpectStatus 1 xrayBinaryVersion "${xrayPath}" >"${xrayPath}.version"
        [[ ! -s "${xrayPath}.version" ]]
        local singBoxPath="$(dirname -- "${xrayPath}")/sing-box"
        printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\nexit 42\n' >"${singBoxPath}"
        chmod 755 "${singBoxPath}"
        regressionExpectStatus 1 singBoxBinaryVersion "${singBoxPath}" >"${singBoxPath}.version"
        [[ ! -s "${singBoxPath}.version" ]]
    )
)

runCoreFirstInstallCommitFailureRollbackRegression() (
    local rootRel="${TMP_DIR}/core-first-install-commit-failure"
    local root
    local xrayDir
    local singBoxDir
    local errorLog
    local copyLog
    local rmLog
    local xrayRc singBoxRc

    mkdir -p "${rootRel}/tmp" "${rootRel}/sing-box"
    root=$(cd -- "${rootRel}" && pwd -P)
    xrayDir="${root}/xray"
    singBoxDir="${root}/sing-box"
    mkdir -p "${xrayDir}"
    printf 'old-geoip\n' >"${xrayDir}/geoip.dat"
    printf 'old-geosite\n' >"${xrayDir}/geosite.dat"
    printf 'old-geo-version\n' >"${xrayDir}/geo.version"
    printf 'old-cronet\n' >"${singBoxDir}/libcronet.so"
    errorLog="${root}/error.log"
    copyLog="${root}/copy.log"
    rmLog="${root}/rm.log"
    : >"${errorLog}"
    : >"${copyLog}"
    : >"${rmLog}"

    PADM_XRAY_BINARY="${xrayDir}/xray"
    PADM_SINGBOX_BINARY="${singBoxDir}/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64
    TMPDIR="${root}/tmp"

    readInstallType() { return 0; }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    handleXray() { return 0; }
    handleSingBox() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${TMPDIR}/core.XXXXXX") || return 1
        else
            path=$(mktemp "${TMPDIR}/core.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmCreateTempFileForTarget() {
        local resultVar=$1
        local targetFile=$2
        local targetDir targetName
        targetDir=$(dirname -- "${targetFile}")
        targetName=$(basename -- "${targetFile}")
        mkdir -p "${targetDir}" || return 1
        path=$(cd -- "${targetDir}" && mktemp ".${targetName}.install.XXXXXX") || return 1
        printf -v "${resultVar}" '%s' "${targetDir}/${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    padmForgetCleanupPath() { return 0; }
    removeManagedFileIfPresent() {
        printf 'rm:%s\n' "$1" >>"${rmLog}"
        command rm -f -- "$1"
    }
    commitGeneratedFile() {
        local tmpFile=$1
        local targetFile=$2
        local mode=$3
        [[ -n "${mode}" ]] && chmod "${mode}" "${tmpFile}" || return 1
        if [[ "${targetFile}" == "${PADM_SINGBOX_BINARY}" ]]; then
            return 1
        fi
        mv "${tmpFile}" "${targetFile}"
    }
    xrayInstalled() { return 1; }
    singBoxInstalled() { return 1; }
    ensureXrayGeoFiles() { return 1; }
    downloadXrayReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        (
            cd -- "${tmpDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >xray || return 1
            chmod 755 xray || return 1
        ) || return 1
        return 0
    }
    downloadSingBoxReleaseBinaryToTempDir() {
        local version=$1
        local tmpDir=$2
        local extractedDir="sing-box-${version/v/}${singBoxCoreCPUVendor}"
        (
            cd -- "${tmpDir}" || return 1
            mkdir -p "${extractedDir}" || return 1
            printf '#!/usr/bin/env bash\nexit 0\n' >"${extractedDir}/sing-box" || return 1
            printf 'cronet\n' >"${extractedDir}/libcronet.so" || return 1
            chmod 755 "${extractedDir}/sing-box" || return 1
        ) || return 1
        return 0
    }
    cp() {
        local sourcePath=$1
        local targetPath=$2
        printf '%s -> %s\n' "${sourcePath}" "${targetPath}" >>"${copyLog}"
        command cp "$@"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${xrayDir}/xray" ]]
    [[ "$(<"${xrayDir}/geoip.dat")" == 'old-geoip' ]] || return 1
    [[ "$(<"${xrayDir}/geosite.dat")" == 'old-geosite' ]] || return 1
    [[ "$(<"${xrayDir}/geo.version")" == 'old-geo-version' ]] || return 1
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ -e "${singBoxDir}/libcronet.so" ]] || return 1
    [[ "$(<"${singBoxDir}/libcronet.so")" == 'old-cronet' ]] || return 1
    grep -qxF "rm:${xrayDir}/xray" "${rmLog}"
    grep -q 'sing-box安装失败' "${errorLog}"
    ! grep -q 'cronet依赖回滚失败' "${errorLog}"

    rm -f "${singBoxDir}/libcronet.so"
    set +e
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e
    [[ "${singBoxRc}" == "1" ]]
    [[ ! -e "${singBoxDir}/sing-box" ]]
    [[ ! -e "${singBoxDir}/libcronet.so" ]] || return 1
    (
        local core installFunction originalBinary
        for core in xray sing-box; do
            if [[ "${core}" == xray ]]; then
                originalBinary=${PADM_XRAY_BINARY}
                installFunction=installXray
            else
                originalBinary=${PADM_SINGBOX_BINARY}
                installFunction=installSingBox
            fi
            printf 'old-broken-binary\n' >"${originalBinary}"
            chmod 644 "${originalBinary}"
            regressionExpectStatus 1 "${installFunction}" 1
            [[ "$(<"${originalBinary}")" == old-broken-binary && "$(stat -c %a "${originalBinary}")" == 644 ]]
        done
    )
)

runCoreUpgradePendingStartRollbackRegression() (
    local root="${TMP_DIR}/core-upgrade-pending"
    local core stopRc stopCalls candidateDir newBinary originalBinary serviceLog
    local version=v1.2.3 singBoxCoreCPUVendor=-linux-amd64
    local PADM_XRAY_BINARY PADM_SINGBOX_BINARY PADM_TMP_DIR="${root}/tmp"
    mkdir -p "${PADM_TMP_DIR}"
    xrayConfigInstalled() { return 1; }
    singBoxConfigInstalled() { return 1; }
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    handleUpgradeService() {
        printf '%s\n' "$1" >>"${serviceLog}"
        if [[ "$1" == stop ]]; then
            stopCalls=$((stopCalls + 1))
            [[ "${stopCalls}" -lt 2 ]] || return "${stopRc}"
            return 0
        fi
        return 1
    }
    handleXray() { handleUpgradeService "$@"; }
    handleSingBox() { handleUpgradeService "$@"; }

    (
        local missing mode caseRoot events
        handleXray() { events+="$1"$'\n'; }
        handleSingBox() { events+="$1"$'\n'; }
        for missing in binary cronet; do
            for mode in missing directory; do
                caseRoot="${root}/lost-${missing}-${mode}"
                mkdir -p "${caseRoot}"
                printf 'candidate\n' >"${caseRoot}/binary"
                printf 'candidate-cronet\n' >"${caseRoot}/cronet"
                printf 'old\n' >"${caseRoot}/binary.bak"
                printf 'old-cronet\n' >"${caseRoot}/cronet.bak"
                command rm -f -- "${caseRoot}/${missing}.bak"
                [[ "${mode}" != directory ]] || mkdir "${caseRoot}/${missing}.bak"
                local -A PADM_CORE_BINARY_INSTALL=(
                    [active]=true [name]=sing-box [binary]="${caseRoot}/binary"
                    [binaryBackup]="${caseRoot}/binary.bak" [cronet]="${caseRoot}/cronet"
                    [cronetBackup]="${caseRoot}/cronet.bak" [backupRoot]="${caseRoot}"
                    [action]=handleSingBox [running]=singBoxRunning [wasRunning]=true
                )
                events=
                regressionExpectStatus 1 rollbackDownloadedCoreBinaryInstallOnExit || return 1
                [[ "${events}" == $'stop\n' && -d "${caseRoot}" ]] || return 1
                [[ "${missing}" != binary || -f "${caseRoot}/cronet.bak" ]] || return 1
                [[ "${missing}" != cronet || -f "${caseRoot}/binary.bak" ]] || return 1
            done
        done
    ) || return 1

    (
        local core serviceLog="${root}/restore-stop.log"
        stopCalls=2
        for core in xray sing-box; do
            : >"${serviceLog}"
            stopRc=0
            coreTemplateRestoreServiceState "${core}" false
            [[ "$(<"${serviceLog}")" == stop ]]
            stopRc=1
            regressionExpectStatus 1 coreTemplateRestoreServiceState "${core}" false
        done
    )
    (
        local release restoreRc events= backup="${root}/startup-backup"
        checkLogBackupRestore() { events+=$'restore\n'; return "${restoreRc}"; }
        systemctl() { events+="systemd:$*"$'\n'; }
        rc-update() { events+="openrc:$*"$'\n'; }
        padmForgetCleanupPath() { events+=$'keep\n'; }
        padmRemoveCleanupPath() { events+=$'cleanup\n'; }
        for release in debian alpine; do
            restoreRc=1 events=
            regressionExpectStatus 1 restoreCoreStartupServiceInstall "${backup}" xray true
            [[ "${events}" == $'restore\nkeep\n' ]]
            restoreRc=0 events=
            restoreCoreStartupServiceInstall "${backup}" xray true
            if [[ "${release}" == debian ]]; then
                [[ "${events}" == $'restore\nsystemd:daemon-reload\nsystemd:enable xray.service\ncleanup\n' ]]
            else
                [[ "${events}" == $'restore\nopenrc:add xray default\ncleanup\n' ]]
            fi
        done
    )
    (
        local core release signal scope enabled fixture status installer serviceFile configFile events
        local PADM_XRAY_SYSTEMD_SERVICE_FILE PADM_SINGBOX_SYSTEMD_SERVICE_FILE
        local PADM_XRAY_OPENRC_SERVICE_FILE PADM_SINGBOX_OPENRC_SERVICE_FILE
        local PADM_TMP_DIR TMPDIR
        padmCommandExists() { [[ "$1" == systemctl ]]; }
        singBoxInstalled() { return 1; }
        coreTemplateConfigBackupCreate() { checkLogBackupCreate "$1" "${configFile}"; }
        handleXray() { printf '%s\n' "$1" >>"${events}"; }
        handleSingBox() { handleXray "$@"; }
        systemctl() {
            case "$1" in
            is-enabled) [[ -e "${fixture}/enabled" ]] ;;
            enable) touch "${fixture}/enabled" ;;
            disable) command rm -f "${fixture}/enabled" ;;
            daemon-reload) printf 'reload\n' >>"${events}" ;;
            *) return 1 ;;
            esac
        }
        rc-update() {
            case "$1" in
            show) [[ ! -e "${fixture}/enabled" ]] || printf '%s | default\n' "${core}" ;;
            add) touch "${fixture}/enabled"; printf 'reload\n' >>"${events}" ;;
            del) command rm -f "${fixture}/enabled"; printf 'reload\n' >>"${events}" ;;
            *) return 1 ;;
            esac
        }
        bootStartup() {
            touch "${fixture}/enabled"
            [[ "${scope}" != outer ]] || printf 'new-config\n' >"${configFile}"
            kill "-${signal}" "${BASHPID}"
        }
        # 替换模板后中断，独立调用和外层事务都必须恢复模板及原自启状态。
        for core in xray sing-box; do
            installer=installXrayService
            [[ "${core}" != sing-box ]] || installer=installSingBoxService
            for release in debian alpine; do
                for scope in standalone outer; do
                    for signal in INT TERM; do
                        for enabled in false true; do
                            fixture="${root}/startup-${core}-${release}-${scope}-${signal}-${enabled}"
                            PADM_TMP_DIR="${fixture}/tmp"
                            TMPDIR=${PADM_TMP_DIR}
                            mkdir -p "${PADM_TMP_DIR}"
                            serviceFile="${fixture}/service" configFile="${fixture}/config" events="${fixture}/events"
                            PADM_XRAY_SYSTEMD_SERVICE_FILE=${serviceFile} PADM_SINGBOX_SYSTEMD_SERVICE_FILE=${serviceFile}
                            PADM_XRAY_OPENRC_SERVICE_FILE=${serviceFile} PADM_SINGBOX_OPENRC_SERVICE_FILE=${serviceFile}
                            printf 'old-service\n' >"${serviceFile}"
                            printf 'old-config\n' >"${configFile}"
                            : >"${events}"
                            [[ "${enabled}" != true ]] || touch "${fixture}/enabled"
                            status=0
                            (
                                local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
                                local PADM_EXIT_ROLLBACK_OWNER= PADM_EXIT_ROLLBACKS=()
                                if [[ "${scope}" == outer ]]; then
                                    coreInstallConfigTransaction "${core}" "${installer}" test
                                else
                                    "${installer}" test
                                fi
                            ) >"${fixture}/output" 2>&1 || status=$?
                            [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]] || return 1
                            [[ "$(<"${serviceFile}")" == old-service && "$(<"${configFile}")" == old-config ]] || return 1
                            [[ "${enabled}" == "$([[ -e "${fixture}/enabled" ]] && printf true || printf false)" ]] || return 1
                            if [[ "${scope}" == outer ]]; then
                                [[ "$(head -n 1 "${events}")" == stop ]] || return 1
                            fi
                            [[ -z "$(find "${PADM_TMP_DIR}" -name 'padm-check-log-backup.*' -print)" ]] || return 1
                        done
                    done
                done
            done
        done
        (
            fixture="${root}/startup-restore-fail"
            PADM_TMP_DIR="${fixture}/tmp"
            TMPDIR=${PADM_TMP_DIR}
            mkdir -p "${PADM_TMP_DIR}"
            serviceFile="${fixture}/service" configFile="${fixture}/config" events="${fixture}/events"
            PADM_XRAY_SYSTEMD_SERVICE_FILE=${serviceFile}
            release=debian signal=TERM scope=standalone
            printf 'old-service\n' >"${serviceFile}"
            checkLogBackupRestore() { return 1; }
            errorCard() { printf '%s\n' "$*"; }
            status=0
            (
                local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
                local PADM_EXIT_ROLLBACK_OWNER= PADM_EXIT_ROLLBACKS=()
                installXrayService test
            ) >"${fixture}/output" 2>&1 || status=$?
            [[ "${status}" == 143 && "$(<"${serviceFile}")" != old-service ]] || return 1
            [[ -n "$(find "${PADM_TMP_DIR}" -name 'padm-check-log-backup.*' -print)" ]] || return 1
            grep -q '安装前服务状态恢复失败' "${fixture}/output"
        ) || return 1
    ) || return 1
    (
        local core failure events= configBackup= serviceBackup=
        coreTemplateConfigBackupCreate() {
            configBackup="${root}/config-backup"
            mkdir -p "${configBackup}"
            printf -v "$1" '%s' "${configBackup}"
        }
        checkLogBackupRestore() { events+=$'config-restore\n'; }
        restoreCoreStartupServiceInstall() {
            events+=$'service-restore\n'
            [[ "${failure}" != unit-fail ]] || return 1
            padmRemoveCleanupPath "$1"
        }
        xrayRunning() { return 0; }
        singBoxRunning() { return 0; }
        handleXray() { recordRecoveryAction "$@"; }
        handleSingBox() { recordRecoveryAction "$@"; }
        recordRecoveryAction() {
            events+="$1"$'\n'
            [[ "$1" != stop || "${failure}" != stop-fail ]]
        }
        failedServiceInstall() {
            serviceBackup="${root}/service-backup"
            mkdir -p "${serviceBackup}"
            coreInstallServiceBackupFinalize "${serviceBackup}" "${core}" true
            return 7
        }
        # 模板恢复前必须确认新核心已停止，恢复失败不能再启动原服务。
        for core in xray sing-box; do
            for failure in stop-fail unit-fail success; do
                events=
                regressionExpectStatus 7 coreInstallConfigTransaction "${core}" failedServiceInstall
                if [[ "${failure}" == stop-fail ]]; then
                    [[ "${events}" == $'stop\n' && -d "${configBackup}" && -d "${serviceBackup}" ]]
                elif [[ "${failure}" == unit-fail ]]; then
                    [[ "${events}" == $'stop\nconfig-restore\nservice-restore\n' && -d "${serviceBackup}" ]]
                else
                    [[ "${events}" == $'stop\nconfig-restore\nservice-restore\nstop\nstart\n' ]]
                    [[ ! -d "${configBackup}" && ! -d "${serviceBackup}" ]]
                fi
                command rm -rf -- "${configBackup}" "${serviceBackup}"
            done
        done
    )

    (
        local wasRunning recovery caseRoot failure
        local serviceRunning serviceLog originalBinary candidateDir
        eval "$(declare -f restoreManagedFileFromBackup | sed '1s/^restoreManagedFileFromBackup/realPendingRestoreManagedFileFromBackup/')"
        restoreManagedFileFromBackup() {
            [[ "${recovery}" != file-fail ]] || return 1
            realPendingRestoreManagedFileFromBackup "$@"
        }
        commitStagedCoreInstallFile() { return 1; }
        xrayRunning() { [[ "${serviceRunning}" == true ]]; }
        singBoxRunning() { [[ "${serviceRunning}" == true ]]; }
        handlePendingService() {
            printf '%s\n' "$1" >>"${serviceLog}"
            if [[ "$1" == stop ]]; then
                [[ "${failure}" != stop-running ]] || return 1
                serviceRunning=false
                [[ "${failure}" != stop-stopped ]] || return 1
            else
                [[ "${recovery}" != service-fail ]] || return 1
                serviceRunning=true
            fi
        }
        handleXray() { handlePendingService "$@"; }
        handleSingBox() { handlePendingService "$@"; }
        # stop 部分失败和提交失败都应恢复原运行态，恢复失败必须保留备份。
        for core in xray sing-box; do
            for failure in commit stop-running stop-stopped; do
            for wasRunning in false true; do
                for recovery in success file-fail service-fail; do
                    [[ "${wasRunning}" != false || "${recovery}" != service-fail ]] || continue
                    [[ "${failure}" == commit || "${recovery}" != file-fail ]] || continue
                    [[ "${failure}" != stop-running || "${recovery}" != service-fail ]] || continue
                    caseRoot="${root}/${core}-${failure}-${wasRunning}-${recovery}"
                    PADM_XRAY_BINARY="${caseRoot}/installed/xray"
                    PADM_SINGBOX_BINARY="${caseRoot}/installed/sing-box"
                    candidateDir="${caseRoot}/candidate"
                    serviceLog="${caseRoot}/service.log"
                    serviceRunning=${wasRunning}
                    mkdir -p "${caseRoot}/installed" "${candidateDir}"
                    : >"${serviceLog}"
                    if [[ "${core}" == xray ]]; then
                        originalBinary=${PADM_XRAY_BINARY}
                        printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${candidateDir}/xray"
                        chmod 755 "${candidateDir}/xray"
                    else
                        originalBinary=${PADM_SINGBOX_BINARY}
                        local extractedDir="${candidateDir}/sing-box-${version#v}${singBoxCoreCPUVendor}"
                        mkdir -p "${extractedDir}"
                        printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\n' >"${extractedDir}/sing-box"
                        printf 'new-cronet\n' >"${extractedDir}/libcronet.so"
                        chmod 755 "${extractedDir}/sing-box"
                    fi
                    if [[ "${core}" == sing-box ]]; then
                        printf 'old-cronet\n' >"$(coreSingBoxCronetPath)"
                    fi
                    printf 'old-binary\n' >"${originalBinary}"
                    chmod 755 "${originalBinary}"
                    if [[ "${core}" == xray ]]; then
                        regressionExpectStatus 1 installDownloadedXrayBinary "${version}" "${candidateDir}"
                    else
                        regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${candidateDir}"
                    fi
                    [[ "$(<"${originalBinary}")" == old-binary ]]
                    if [[ "${recovery}" == success ]]; then
                        [[ "${serviceRunning}" == "${wasRunning}" ]] || {
                            printf '%s 普通失败未恢复原运行状态: 原状态 %s，恢复后 %s\n' \
                                "${core}" "${wasRunning}" "${serviceRunning}" >&2
                            return 1
                        }
                        ! compgen -G "${originalBinary%/*}/.${originalBinary##*/}.bak.*" >/dev/null
                    else
                        [[ "${serviceRunning}" == false ]]
                        compgen -G "${originalBinary%/*}/.${originalBinary##*/}.bak.*" >/dev/null
                        [[ "${core}" != sing-box ]] ||
                            compgen -G "$(coreSingBoxInstallDir)/.libcronet.so.bak.*" >/dev/null
                    fi
                done
            done
            done
        done
    )

    # 启动失败但无进程时也要取消待启动任务；取消失败不能覆盖新文件或启动旧核心。
    for core in xray sing-box; do
        for stopRc in 0 1; do
            local caseRoot="${root}/${core}-${stopRc}"
            candidateDir="${caseRoot}/candidate"
            serviceLog="${caseRoot}/service.log"
            PADM_XRAY_BINARY="${caseRoot}/installed/xray"
            PADM_SINGBOX_BINARY="${caseRoot}/installed/sing-box"
            mkdir -p "${caseRoot}/installed" "${candidateDir}"
            : >"${serviceLog}"
            stopCalls=0
            if [[ "${core}" == xray ]]; then
                originalBinary=${PADM_XRAY_BINARY}
                newBinary="${candidateDir}/xray"
                printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${newBinary}"
            else
                originalBinary=${PADM_SINGBOX_BINARY}
                local extractedDir="${candidateDir}/sing-box-${version#v}${singBoxCoreCPUVendor}"
                mkdir -p "${extractedDir}"
                newBinary="${extractedDir}/sing-box"
                printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\n' >"${newBinary}"
                printf 'new-cronet\n' >"${extractedDir}/libcronet.so"
                printf 'old-cronet\n' >"$(coreSingBoxCronetPath)"
            fi
            printf 'old-binary\n' >"${originalBinary}"
            chmod 755 "${originalBinary}" "${newBinary}"
            if [[ "${core}" == xray ]]; then
                regressionExpectStatus 1 installDownloadedXrayBinary "${version}" "${candidateDir}"
            else
                regressionExpectStatus 1 installDownloadedSingBoxBinary "${version}" "${candidateDir}"
            fi
            [[ "$(stat -c %a "${originalBinary}")" == 755 ]]
            if [[ "${stopRc}" == 0 ]]; then
                [[ "$(<"${serviceLog}")" == $'stop\nstart\nstop' ]]
                [[ "$(<"${originalBinary}")" == old-binary ]]
                [[ "${core}" != sing-box || "$(<"$(coreSingBoxCronetPath)")" == old-cronet ]]
            else
                [[ "$(<"${serviceLog}")" == $'stop\nstart\nstop' ]]
                [[ "$(<"${originalBinary}")" != old-binary ]]
                compgen -G "${originalBinary%/*}/.${originalBinary##*/}.bak.*" >/dev/null
                [[ "${core}" != sing-box || "$(<"$(coreSingBoxCronetPath)")" == new-cronet ]]
            fi
        done
    done
    (
        # 启动命令失败但实际运行且版本正确时，仍完成升级并清理备份。
        local caseRoot="${root}/xray-success"
        local PADM_XRAY_BINARY="${caseRoot}/installed/xray"
        local candidateDir="${caseRoot}/candidate" serviceLog="${caseRoot}/service.log"
        local REGRESSION_SUCCESS_CARD_LOG="${caseRoot}/success.log" stopCalls=0 stopRc=0
        mkdir -p "${caseRoot}/installed" "${candidateDir}"
        printf 'old-binary\n' >"${PADM_XRAY_BINARY}"
        printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${candidateDir}/xray"
        chmod 755 "${PADM_XRAY_BINARY}" "${candidateDir}/xray"
        xrayRunning() { return 0; }
        installDownloadedXrayBinary "${version}" "${candidateDir}"
        [[ "$(stat -c %a "${PADM_XRAY_BINARY}")" == 755 ]]
        [[ "$(coreXrayCurrentVersion)" == "${version}" && ! -e "${candidateDir}" ]]
        [[ "$(<"${serviceLog}")" == $'stop\nstart' ]]
        grep -q 'Xray-core更新成功' "${REGRESSION_SUCCESS_CARD_LOG}"
        ! compgen -G "${PADM_XRAY_BINARY%/*}/.${PADM_XRAY_BINARY##*/}.bak.*" >/dev/null
    )
    for core in xray sing-box; do
        local retryRoot="${root}/${core}-backup-retry"
        (
            # 同秒重试成功不能覆盖或清理前次恢复失败保留的原始备份。
            local PADM_XRAY_BINARY="${retryRoot}/installed/xray"
            local PADM_SINGBOX_BINARY="${retryRoot}/installed/sing-box"
            local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
            local serviceRunning=false failStart=true failRestore=true
            local candidateDir="${retryRoot}/candidate" originalBinary installFunction
            local firstBinaryBackup firstCronetBackup= backup
            local -a writtenBackups=()
            mkdir -p "${retryRoot}/installed"
            eval "$(declare -f backupManagedFileToPath | sed '1s/^backupManagedFileToPath/realRetryBackupManagedFileToPath/')"
            eval "$(declare -f restoreManagedFileFromBackup | sed '1s/^restoreManagedFileFromBackup/realRetryRestoreManagedFileFromBackup/')"
            backupManagedFileToPath() {
                writtenBackups+=("$2")
                realRetryBackupManagedFileToPath "$@"
            }
            restoreManagedFileFromBackup() {
                [[ "${failRestore}" != true ]] || return 1
                realRetryRestoreManagedFileFromBackup "$@"
            }
            date() {
                [[ "$*" != +%s ]] || { printf '1700000000\n'; return 0; }
                command date "$@"
            }
            xrayRunning() { [[ "${serviceRunning}" == true ]]; }
            singBoxRunning() { [[ "${serviceRunning}" == true ]]; }
            ensureSingBoxTrafficStatsConfig() { return 0; }
            handleRetryService() {
                serviceRunning=false
                [[ "$1" != start ]] || {
                    [[ "${failStart}" != true ]] || return 1
                    serviceRunning=true
                }
                return 0
            }
            handleXray() { handleRetryService "$@"; }
            handleSingBox() { handleRetryService "$@"; }
            if [[ "${core}" == xray ]]; then
                originalBinary=${PADM_XRAY_BINARY}
                installFunction=installDownloadedXrayBinary
            else
                originalBinary=${PADM_SINGBOX_BINARY}
                installFunction=installDownloadedSingBoxBinary
                printf 'old-cronet\n' >"$(coreSingBoxCronetPath)"
            fi
            printf 'old-binary\n' >"${originalBinary}"
            chmod 755 "${originalBinary}"
            prepareRetryBinary() {
                mkdir -p "${candidateDir}"
                if [[ "${core}" == xray ]]; then
                    printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${candidateDir}/xray"
                    chmod 755 "${candidateDir}/xray"
                else
                    local extractedDir="${candidateDir}/sing-box-${version#v}${singBoxCoreCPUVendor}"
                    mkdir -p "${extractedDir}"
                    printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\n' >"${extractedDir}/sing-box"
                    chmod 755 "${extractedDir}/sing-box"
                    printf 'new-cronet\n' >"${extractedDir}/libcronet.so"
                fi
            }
            prepareRetryBinary
            regressionExpectStatus 1 "${installFunction}" "${version}" "${candidateDir}" || return 1
            firstBinaryBackup=${writtenBackups[0]}
            [[ -f "${firstBinaryBackup}" && "$(<"${firstBinaryBackup}")" == old-binary ]] || return 1
            if [[ "${core}" == sing-box ]]; then
                firstCronetBackup=${writtenBackups[1]}
                [[ -f "${firstCronetBackup}" && "$(<"${firstCronetBackup}")" == old-cronet ]] || return 1
            fi
            failStart=false failRestore=false
            prepareRetryBinary
            "${installFunction}" "${version}" "${candidateDir}" || return 1
            [[ -f "${firstBinaryBackup}" && "$(<"${firstBinaryBackup}")" == old-binary ]] || {
                printf '%s 同秒重试丢失原二进制备份\n' "${core}" >&2
                return 1
            }
            [[ -z "${firstCronetBackup}" || ( -f "${firstCronetBackup}" && "$(<"${firstCronetBackup}")" == old-cronet ) ]] || return 1
            for backup in "${writtenBackups[@]:${#writtenBackups[@]}/2}"; do
                [[ ! -e "${backup}" ]] || return 1
            done
            printf '%s\n' "${firstBinaryBackup}" "${firstCronetBackup}" >"${retryRoot}/retained-backups"
        ) || return 1
        while IFS= read -r backup; do
            [[ -z "${backup}" ]] || { [[ -f "${backup}" ]] && padmRemoveCleanupPath "${backup}"; } || return 1
        done <"${retryRoot}/retained-backups"
    done
)

runCoreInstallRejectsUnsafeBinaryPathRegression() (
    local root="${TMP_DIR}/core-install-unsafe-binary"
    local errorLog="${root}/error.log"
    local xrayRc singBoxRc

    mkdir -p "${root}"
    : >"${errorLog}"

    PADM_XRAY_BINARY="relative/xray"
    PADM_SINGBOX_BINARY="relative/sing-box"
    xrayCoreCPUVendor=linux-64
    singBoxCoreCPUVendor=-linux-amd64

    readInstallType() { return 0; }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    coreLatestReleaseTag() { printf 'v1.2.3\n'; }
    checkVersionNotEmpty() { [[ -n "$1" ]]; }
    ensureXrayGeoFiles() { return 0; }
    padmCreateTempPath() {
        local resultVar=$1
        local path
        shift
        if [[ "${1:-}" == "-d" ]]; then
            path=$(mktemp -d "${root}/tmp.XXXXXX") || return 1
        else
            path=$(mktemp "${root}/tmp.XXXXXX") || return 1
        fi
        printf -v "${resultVar}" '%s' "${path}"
    }
    padmRemoveCleanupPath() { rm -rf "$1"; }
    downloadGitHubReleaseAsset() { return 0; }
    unzip() {
        if [[ "${1:-}" == "-Z1" ]]; then
            printf 'xray\n'
            return 0
        fi
        if [[ "${1:-}" == "-Z" && "${2:-}" == "-l" ]]; then
            printf '%s\n' '-rwxr-xr-x  3.0 unx 0 b- 0% 2026-01-01 00:00 xray'
            return 0
        fi
        if [[ "${1:-}" == "-p" ]]; then
            printf 'xray\n'
            return 0
        fi
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -d)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${dest}/xray"
        chmod 755 "${dest}/xray"
    }
    tar() {
        case "${1:-}" in
        -tzf)
            printf 'sing-box-1.2.3-linux-amd64/\nsing-box-1.2.3-linux-amd64/sing-box\nsing-box-1.2.3-linux-amd64/libcronet.so\n'
            return 0
            ;;
        -tvzf)
            printf '%s\n' 'drwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/'
            printf '%s\n' '-rwxr-xr-x root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/sing-box'
            printf '%s\n' '-rw-r--r-- root/root 0 2026-01-01 00:00 sing-box-1.2.3-linux-amd64/libcronet.so'
            return 0
            ;;
        -xOzf)
            printf 'sing-box\ncronet\n'
            return 0
            ;;
        esac
        local dest=
        while [[ $# -gt 0 ]]; do
            case "$1" in
            -C)
                dest=$2
                shift 2
                ;;
            *)
                shift
                ;;
            esac
        done
        mkdir -p "${dest}/sing-box-1.2.3-linux-amd64"
        printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\n' >"${dest}/sing-box-1.2.3-linux-amd64/sing-box"
        printf 'cronet\n' >"${dest}/sing-box-1.2.3-linux-amd64/libcronet.so"
        chmod 755 "${dest}/sing-box-1.2.3-linux-amd64/sing-box"
    }

    set +e
    ( installXray 1 false >/dev/null 2>&1 )
    xrayRc=$?
    ( installSingBox 1 >/dev/null 2>&1 )
    singBoxRc=$?
    set -e

    [[ "${xrayRc}" == "1" ]]
    [[ "${singBoxRc}" == "1" ]]
    grep -q 'Xray-core安装路径异常' "${errorLog}"
    grep -q 'sing-box安装路径异常' "${errorLog}"
)

runCoreCleanupFailurePropagationRegression() (
    (
        autoRead() { IFS= read -r "$3"; }
        regressionExpectStatus 1 confirmCoreUpgrade Xray v1 stable </dev/null || return 1
        printf '%s' y | regressionExpectStatus 1 confirmCoreUpgrade Xray v1 stable || return 1
        regressionExpectStatus 0 confirmCoreUpgrade Xray v1 stable <<<y || return 1
    ) || return 1
    local root="${TMP_DIR}/core-cleanup-failure"
    local serviceLog="${root}/service.log"
    local rmLog="${root}/rm.log"
    local errorLog="${root}/error.log"
    local reachedFile="${root}/reached"
    local queueLog="${root}/queue.log"
    local rc

    mkdir -p "${root}/xray" "${root}/sing-box" "${root}/nginx"
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    nginxConfigPath="${root}/nginx/"
    PADM_REALITY_ENTRY_HOST_FILE="${root}/reality_entry_host"
    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"

    rm() {
        printf 'rm:%s\n' "$*" >>"${rmLog}"
        return 0
    }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        printf 'cleanup\n' >>"${queueLog}"
        return 1
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        return 0
    }

    SERVICE_QUEUE_ALLOW_FAILURE=previous
    regressionExpectStatus 1 cleanUp xrayDel >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -q 'Xray 服务停止失败，已取消清理旧核心' "${errorLog}"
    [[ ! -s "${rmLog}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    : >"${serviceLog}"
    : >"${rmLog}"
    : >"${errorLog}"
    : >"${queueLog}"
    command rm -f "${reachedFile}"
    readLastInstallationConfig() { return 0; }
    coreTemplateCollectInitialClients() { return 0; }
    readInstallTLSPort() { port=2443; return 0; }
    prepareSingBoxInstallInputs() { return 0; }
    collectEntryProfile() { realityEntryHost=cleanup.example.com; return 0; }
    persistRealityEntryProfile() { printf 'persist\n' >>"${queueLog}"; return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    initSingBoxConfig() { return 0; }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${queueLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${queueLog}"
        return 0
    }
    checkGFWStatue() {
        printf 'check\n' >>"${queueLog}"
        printf 'reached\n' >"${reachedFile}"
        return 0
    }
    showAccounts() {
        printf 'reached\n' >"${reachedFile}"
        return 0
    }

    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    ! grep -q '/etc/padm/xray' "${rmLog}"
    [[ "$(<"${queueLog}")" == $'cleanup\ncleanup' ]]
    [[ ! -e "${reachedFile}" ]]

    (
        local switchRoot="${root}/switch-rollback"
        local oldCoreDir="${switchRoot}/xray"
        local switchLog="${switchRoot}/switch.log"
        local xrayServiceRunning=true
        local switchRc

        mkdir -p "${oldCoreDir}"
        printf 'old-core\n' >"${oldCoreDir}/state"
        : >"${switchLog}"
        PADM_XRAY_BINARY="${oldCoreDir}/xray"
        rm() { command rm "$@"; }
        coreTemplateConfigBackupCreate() {
            printf -v "$1" '%s' "${switchRoot}/config-backup"
        }
        checkLogBackupRestore() {
            printf 'config-restore\n' >>"${switchLog}"
        }
        xrayRunning() { [[ "${xrayServiceRunning}" == "true" ]]; }
        singBoxRunning() { return 1; }
        handleXray() {
            if [[ "$1" == "start" && -f "${oldCoreDir}/state" ]]; then
                printf 'xray:start:restored\n' >>"${switchLog}"
                xrayServiceRunning=true
                return 0
            fi
            printf 'xray:%s:missing\n' "$1" >>"${switchLog}"
            return 1
        }
        failingSwitch() {
            xrayServiceRunning=false
            mv "${oldCoreDir}" "${oldCoreDir}.removed"
            return 7
        }

        regressionExpectStatus 7 coreSwitchConfigTransaction sing-box failingSwitch >/dev/null 2>&1 || return 1
        [[ "$(<"${oldCoreDir}/state")" == "old-core" ]] || return 1
        [[ "$(<"${switchLog}")" == $'config-restore\nxray:start:restored' ]] || return 1

        # 旧核心恢复失败时保持停服，提示实际备份路径并保留备份。
        local retainedBackup=
        adapterRestoreManagedRollbackBackup() { retainedBackup=$1; return 1; }
        failingSwitch() { xrayServiceRunning=false; return 7; }
        : >"${switchLog}"
        : >"${errorLog}"
        regressionExpectStatus 7 coreSwitchConfigTransaction sing-box failingSwitch >/dev/null 2>&1 || return 1
        [[ "$(<"${switchLog}")" == config-restore && "${xrayServiceRunning}" == false ]] || return 1
        [[ -n "${retainedBackup}" && -d "${retainedBackup}" ]] || return 1
        grep -qF "${retainedBackup}" "${errorLog}" || return 1
    ) || return 1
)

runCorePortFileTransactionRegression() {
    reloadCore() { return 99; }
    runServiceAction() { [[ "$*" == "xray restart" ]]; }
    local oldTmpDir="${TMPDIR:-}"
    local configRoot
    local portTmpRoot="${TMP_DIR}/core-port-tmp"
    mkdir -p "${portTmpRoot}"
    portTmpRoot=$(cd -- "${portTmpRoot}" && pwd -P) || return 1
    TMPDIR="${portTmpRoot}"
    mkdir -p "${configPath}"
    configRoot=$(cd -- "${configPath}" && pwd -P) || return 1
    configPath="${configRoot%/}/"
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2053.json" 2053 443 tcp dokodemo-door-newPort-2053
    writeCoreDokodemoInbound "${configPath}02_dokodemodoor_inbounds_2083_default.json" 2083 443 tcp dokodemo-door-newPort-2083
    local original2053 original2083 keptBackup
    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053.json")
    original2083=$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")
    (
        local configPath="${TMP_DIR}/core-port-invalid-default/"
        local defaultFile="${configPath}02_dokodemodoor_inbounds_2053_default.json"
        local owned fixture patch lookup output="${TMP_DIR}/core-port-invalid-default-result"
        mkdir -p "${configPath}" || return 1
        printf '%s\n' '{"inbounds":[{"port":443}]}' >"${configPath}02_VLESS_TCP_inbounds.json"
        writeCoreDokodemoInbound "${defaultFile}" 2053 443 tcp dokodemo-door-newPort-2053 || return 1
        owned=$(<"${defaultFile}")
        for patch in '.inbounds[0].protocol = "socks"' \
            '.inbounds[0].settings.network = "udp"' \
            '.inbounds[0].settings.address = "remote.example"' \
            '.inbounds[0].tag = "unmanaged"' \
            '.inbounds[0].port = 2083 | .inbounds[0].tag = "dokodemo-door-newPort-2083"' \
            '.inbounds[0].settings.port = 0' \
            '.inbounds[0].settings.port = 443.5' \
            '.inbounds += [.inbounds[0]]' \
            '., .'; do
            fixture=$(jq -c "${patch}" <<<"${owned}") || return 1
            printf '%s\n' "${fixture}" >"${defaultFile}"
            for lookup in corePortDefaultFile corePortForwardTarget; do
                regressionExpectStatus 1 "${lookup}" >"${output}" 2>/dev/null || return 1
                [[ ! -s "${output}" ]] || return 1
            done
            regressionExpectStatus 1 corePortSubscriptionPort 443 >"${output}" 2>/dev/null || return 1
            [[ ! -s "${output}" ]] || return 1
            regressionExpectStatus 1 corePortWriteAddFiles 2443 2443 443 2>/dev/null || return 1
            [[ "$(<"${defaultFile}")" == "${fixture}" &&
                ! -e "${configPath}02_dokodemodoor_inbounds_2053.json" &&
                ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]] || return 1
        done
        printf '%s\n' "${owned}" >"${defaultFile}"
        corePortWriteAddFiles 2443 2443 443 || return 1
        [[ ! -e "${defaultFile}" && -f "${configPath}02_dokodemodoor_inbounds_2053.json" &&
            "$(corePortSubscriptionPort 443)" == 2443 ]] || return 1
    ) || return 1
    if corePortApplyReloadTransaction corePortWriteAddFiles $'2053\n2083' 2053 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053.json")" == "${original2053}" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2083_default.json")" == "${original2083}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]

    corePortApplyReloadTransaction corePortWriteAddFiles $'2053\n2083' 2053 443
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083_default.json" ]]
    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 443' "${configPath}02_dokodemodoor_inbounds_2053_default.json" >/dev/null

    if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
        return 1
    fi
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    corePortApplyReloadTransaction corePortRemove 2083
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2083.json" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2053_default.json" ]]

    local reloadCalls=0 errorLog="${TMP_DIR}/core-port-reload-error.log"
    local reloadLog="${TMP_DIR}/core-port-reload-calls.log"
    local helperLog="${TMP_DIR}/core-port-helper.log"
    : >"${errorLog}"
    : >"${helperLog}"
    errorCard() {
        printf '%s\n' "$*" >>"${errorLog}"
    }
    eval "$(declare -f corePortReportBackupFailure | sed '1s/^corePortReportBackupFailure/originalCorePortReportBackupFailure/')"
    corePortReportBackupFailure() {
        printf 'backup\n' >>"${helperLog}"
        originalCorePortReportBackupFailure "$@"
    }
    eval "$(declare -f corePortReportRollbackFailure | sed '1s/^corePortReportRollbackFailure/originalCorePortReportRollbackFailure/')"
    corePortReportRollbackFailure() {
        printf 'rollback\n' >>"${helperLog}"
        originalCorePortReportRollbackFailure "$@"
    }

    : >"${errorLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${portTmpRoot}"/padm-core-port.*/.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
        [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
        [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
        if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        corePortBackupFiles() {
            return 1
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置备份失败" "${errorLog}"
    [[ "$(grep -c '^backup$' "${helperLog}")" == "1" ]]

    : >"${errorLog}"
    : >"${helperLog}"
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${configPath}".02_dokodemodoor_inbounds_2053_default.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 'bad-port' 2>/dev/null; then
            return 1
        fi
    ) || return 1
    grep -q "入口端口配置回滚失败" "${errorLog}"
    [[ "$(grep -c '^rollback$' "${helperLog}")" == "1" ]]
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    [[ -f "${keptBackup}/02_dokodemodoor_inbounds_2053_default.json" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    runServiceAction() {
        [[ "$*" == "xray restart" ]] || return 99
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }

    original2053=$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")
    if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    [[ ! -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]

    reloadCalls=0
    runServiceAction() {
        [[ "$*" == "xray restart" ]] || return 99
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    if corePortApplyReloadTransaction corePortRemove 2053 2>/dev/null; then
        return 1
    fi
    [[ "${reloadCalls}" == "2" ]]
    [[ "$(<"${configPath}02_dokodemodoor_inbounds_2053_default.json")" == "${original2053}" ]]
    grep -q "入口端口核心重载失败，已恢复旧配置" "${errorLog}"
    grep -q "恢复后核心重载仍失败" "${errorLog}" && return 1

    reloadCalls=0
    : >"${reloadLog}"
    : >"${errorLog}"
    runServiceAction() {
        [[ "$*" == "xray restart" ]] || return 99
        printf 'reload\n' >>"${reloadLog}"
        reloadCalls=$((reloadCalls + 1))
        [[ "${reloadCalls}" != "1" ]]
    }
    (
        cp() {
            local args=("$@")
            local sourcePath="${args[$((${#args[@]} - 2))]}"
            if [[ "${sourcePath}" == */padm-core-port.*/02_dokodemodoor_inbounds_2053_default.json ]]; then
                return 1
            fi
            command cp "$@"
        }
        if corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443 2>/dev/null; then
            return 1
        fi
    ) || return 1
    [[ "$(grep -c '^reload$' "${reloadLog}")" == "1" ]]
    grep -q "入口端口核心重载失败，且旧配置恢复失败" "${errorLog}"
    keptBackup=$(find "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*' -print -quit)
    [[ -n "${keptBackup}" && -d "${keptBackup}" ]]
    rm -rf "${keptBackup}"
    printf '%s\n' "${original2053}" >"${configPath}02_dokodemodoor_inbounds_2053_default.json"
    rm -f "${configPath}02_dokodemodoor_inbounds_2443_default.json"

    reloadCalls=0
    runServiceAction() {
        [[ "$*" == "xray restart" ]] || return 99
        reloadCalls=$((reloadCalls + 1))
        return 0
    }
    corePortApplyReloadTransaction corePortWriteAddFiles 2443 2443 443
    [[ "${reloadCalls}" == "1" ]]
    [[ -e "${configPath}02_dokodemodoor_inbounds_2443_default.json" ]]
    if regressionFindHasMatches "${portTmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-core-port.*'; then
        return 1
    fi

    (
        local firewallLog="${TMP_DIR}/core-port-firewall-lifecycle.log"
        local firewallErrorLog="${TMP_DIR}/core-port-firewall-errors.log"
        local PADM_FIREWALL_STATE_FILE="${TMP_DIR}/core-port-firewall.state"
        local denyShouldFail=false
        local denyTcpShouldFail=false
        local hysteriaPort=16295
        local mode=add-fail
        local deleteMenuReads=0
        local rc
        : >"${firewallLog}"
        : >"${firewallErrorLog}"
        eval "$(declare -f addCorePort | sed '1s/^addCorePort/originalAddCorePort/')"
        addCorePort() { return 0; }
        autoRead() {
            case "$1" in
            core_port_menu)
                if [[ "${mode}" == "delete" ]]; then
                    deleteMenuReads=$((deleteMenuReads + 1))
                    [[ "${deleteMenuReads}" == "1" ]] && printf -v "$3" 3 || printf -v "$3" 4
                else
                    printf -v "$3" 2
                fi
                ;;
            extra_core_ports) printf -v "$3" '2555,2666' ;;
            extra_core_default_port) printf -v "$3" 443 ;;
            extra_core_delete_port) printf -v "$3" 1 ;;
            esac
        }
        allowPort() {
            local key="port:ufw:${2:-tcp}:$1"
            PADM_LAST_ALLOW_PORT_ADDED=false
            padmFirewallStateHas "${key}" && return 0
            padmFirewallStateAdd "${key}" || return 1
            padmTrackPortAllowTransactionKey "${key}"
            PADM_LAST_ALLOW_PORT_ADDED=true
            printf 'allow:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
        }
        removeFirewallPortRule() { denyPort "$2" "$3"; }
        denyPort() {
            printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
            [[ "${denyShouldFail}" != "true" && ( "${denyTcpShouldFail}" != "true" || "${2:-tcp}" != "tcp" ) ]]
        }
        errorCard() { printf '%s\n' "$1" >>"${firewallErrorLog}"; }
        corePortListExtra() { return 0; }
        corePortResolveByIndex() { printf '2555\n'; }
        corePortForwardTarget() { printf '443\n'; }
        corePortApplyReloadTransaction() { [[ "${mode}" == "delete" ]]; }
        refreshProtocolSubscriptions() { return 0; }
        # 此夹具只验证防火墙生命周期，安装状态由本层给定，不读取真实配置。
        readSingBoxConfig() { hysteriaPort=16295; }
        coreInstallType=1
        customPort=

        regressionExpectStatus 1 originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
        grep -qx 'deny:2666:tcp' "${firewallLog}"
        grep -qx 'deny:2666:udp' "${firewallLog}"
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]

        # 复用旧规则不记入本次事务，失败时仅移除本次新增规则。
        padmFirewallStateAdd port:ufw:tcp:2555
        : >"${firewallLog}"
        regressionExpectStatus 1 originalAddCorePort >/dev/null 2>&1
        ! grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
        [[ "$(<"${PADM_FIREWALL_STATE_FILE}")" == port:ufw:tcp:2555 ]]
        padmFirewallStateRemove port:ufw:tcp:2555

        denyShouldFail=true
        : >"${firewallErrorLog}"
        set +e
        originalAddCorePort >/dev/null 2>&1
        rc=$?
        set -e
        denyShouldFail=false
        [[ "${rc}" == "1" ]]
        grep -qx '操作失败，且本次新增端口的防火墙规则回滚失败，请检查防火墙状态' "${firewallErrorLog}"
        padmFirewallStateHas port:ufw:tcp:2555

        mode=delete
        : >"${firewallLog}"
        originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"

        denyTcpShouldFail=true
        deleteMenuReads=0
        : >"${firewallLog}"
        regressionExpectStatus 1 originalAddCorePort >/dev/null 2>&1
        grep -qx 'deny:2555:tcp' "${firewallLog}"
        grep -qx 'deny:2555:udp' "${firewallLog}"
    )

    rm -rf "${configPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
}

runCoreInstallSignalRollbackRegression() (
    set -euo pipefail
    local release=debian
    local root="${TMP_DIR}/core-install-signal"
    local fixture core signal mode status
    mkdir -p "${root}"
    local TMPDIR="${root}"

    coreTemplateConfigBackupCreate() {
        checkLogBackupCreate "$1" "${fixture}/xray.conf" "${fixture}/sing-box.conf" "${fixture}/nginx.conf"
        printf '%s\n' "${!1}" >"${fixture}/config-backup"
    }
    coreSwitchCleanupBackupCreate() {
        adapterCreateManagedRollbackBackup "$1" "${fixture}/old-core"
    }
    checkLogBackupRestore() {
        [[ "${mode}" != restore-fail ]] || return 1
        [[ "${mode}" != repeat-signal ]] || kill -TERM "${BASHPID}"
        padmRestoreManagedFileBackupManifest "$1"
    }
    singBoxInstalled() { return 1; }
    xrayRunning() { grep -qx true "${fixture}/xray.running"; }
    singBoxRunning() { grep -qx true "${fixture}/sing-box.running"; }
    nginxRunning() { grep -qx true "${fixture}/nginx.running"; }
    handleXray() { signalServiceAction xray "$1"; }
    handleSingBox() { signalServiceAction sing-box "$1"; }
    handleNginx() { signalServiceAction nginx "$1"; }
    signalServiceAction() {
        printf '%s:%s\n' "$1" "$2" >>"${fixture}/service.log"
        if [[ "${mode}" == stop-fail && "$1" == "${core}" && "$2" == stop ]]; then
            return 1
        fi
        printf '%s\n' "$([[ "$2" == start ]] && printf true || printf false)" >"${fixture}/$1.running"
    }
    restoreCoreStartupServiceInstall() {
        [[ "$2" == "${core}" && "$3" == true ]]
        command cp "$1/service" "${fixture}/service"
        padmRemoveCleanupPath "$1"
    }
    removeFirewallPortRule() { printf '%s:%s:%s\n' "$@" >>"${fixture}/ports.log"; }
    padmFirewallStateRemove() { :; }
    errorCard() { printf '%s\n' "$@" >>"${fixture}/errors.log"; }
    childSignalOperation() {
        padmCreateTmpRootPath childTemp signal-child.XXXXXX -d
        printf '%s\n' "${childTemp}" >"${fixture}/child-temp"
        kill -TERM "${BASHPID}"
        printf 'continued\n' >"${fixture}/child-continued"
    }
    signalInstallOperation() {
        # 内层同名变量不能遮蔽信号回滚所需的外层快照。
        local backupDir="${fixture}/unrelated" title=unrelated
        local xrayWasRunning=false singBoxWasRunning=false manageNginx=false
        padmCreateTmpRootPath PADM_CORE_INSTALL_SERVICE_BACKUP_DIR signal-service.XXXXXX -d
        PADM_CORE_INSTALL_SERVICE_NAME=${core}
        PADM_CORE_INSTALL_SERVICE_WAS_ENABLED=true
        command cp "${fixture}/service" "${PADM_CORE_INSTALL_SERVICE_BACKUP_DIR}/service"
        printf 'new\n' >"${fixture}/service"
        printf 'new\n' >"${fixture}/xray.conf"
        printf 'new\n' >"${fixture}/sing-box.conf"
        printf 'new\n' >"${fixture}/nginx.conf"
        printf 'new\n' >"${fixture}/old-core/marker"
        printf 'false\n' >"${fixture}/xray.running"
        printf 'false\n' >"${fixture}/sing-box.running"
        printf 'false\n' >"${fixture}/nginx.running"
        PADM_PORT_ALLOW_TRANSACTION_KEYS=$'port:ufw:tcp:18443\nport:ufw:udp:18443'
        if [[ "${signal}" == CHILD ]]; then
            local childStatus=0
            (
                local PADM_PORT_ALLOW_TRANSACTION_ACTIVE=false
                padmRunPortAllowTransaction childSignalOperation
            ) || childStatus=$?
            [[ "${childStatus}" == 143 && -d "$(<"${fixture}/config-backup")" ]]
            [[ "$(<"${fixture}/xray.conf")" == new ]]
            return 7
        fi
        [[ "${signal}" != RETURN ]] || return 7
        [[ "${signal}" != SUCCESS ]] || return 0
        kill -"${signal/REPEAT/TERM}" "${BASHPID}"
        printf 'continued\n' >"${fixture}/continued"
    }

    for core in xray sing-box; do
        for signal in TERM INT RETURN CHILD REPEAT; do
            fixture="${root}/${core}-${signal}"
            mode=normal
            mkdir -p "${fixture}/old-core"
            printf 'old\n' >"${fixture}/old-core/marker"
            for mode in xray.conf sing-box.conf nginx.conf service; do
                printf 'old\n' >"${fixture}/${mode}"
            done
            mode=normal
            [[ "${signal}" != REPEAT && "${signal}" != RETURN ]] || mode=repeat-signal
            printf 'true\n' >"${fixture}/xray.running"
            printf 'false\n' >"${fixture}/sing-box.running"
            printf 'true\n' >"${fixture}/nginx.running"
            status=0
            ( coreSwitchConfigTransaction "${core}" padmRunPortAllowTransaction signalInstallOperation ) || status=$?
            case "${signal}" in
            TERM | REPEAT) [[ "${status}" == 143 ]] ;;
            INT) [[ "${status}" == 130 ]] ;;
            *) [[ "${status}" == 7 ]] ;;
            esac
            [[ ! -e "${fixture}/continued" && ! -e "${fixture}/child-continued" ]]
            for mode in xray.conf sing-box.conf nginx.conf service old-core/marker; do
                [[ "$(<"${fixture}/${mode}")" == old ]]
            done
            mode=normal
            [[ "$(<"${fixture}/xray.running")" == true ]]
            [[ "$(<"${fixture}/sing-box.running")" == false ]]
            [[ "$(<"${fixture}/nginx.running")" == true ]]
            grep -qx 'ufw:18443:tcp' "${fixture}/ports.log"
            grep -qx 'ufw:18443:udp' "${fixture}/ports.log"
            [[ ! -e "$(<"${fixture}/config-backup")" ]]
            [[ "${signal}" != CHILD || ! -e "$(<"${fixture}/child-temp")" ]]
        done
    done

    core=xray signal=SUCCESS mode=normal
    fixture="${root}/success"
    mkdir -p "${fixture}/old-core"
    for signal in xray.conf sing-box.conf nginx.conf service old-core/marker; do
        printf 'old\n' >"${fixture}/${signal}"
    done
    signal=SUCCESS
    printf 'true\n' >"${fixture}/xray.running"
    printf 'false\n' >"${fixture}/sing-box.running"
    printf 'true\n' >"${fixture}/nginx.running"
    ( coreSwitchConfigTransaction "${core}" padmRunPortAllowTransaction signalInstallOperation )
    [[ "$(<"${fixture}/xray.conf")" == new && "$(<"${fixture}/service")" == new ]]
    [[ ! -e "${fixture}/ports.log" && ! -e "$(<"${fixture}/config-backup")" ]]

    core=xray signal=TERM
    for mode in stop-fail restore-fail; do
        fixture="${root}/${mode}"
        mkdir -p "${fixture}/old-core"
        for signal in xray.conf sing-box.conf nginx.conf service old-core/marker; do
            printf 'old\n' >"${fixture}/${signal}"
        done
        signal=TERM
        printf 'true\n' >"${fixture}/xray.running"
        printf 'false\n' >"${fixture}/sing-box.running"
        printf 'true\n' >"${fixture}/nginx.running"
        status=0
        ( coreSwitchConfigTransaction "${core}" padmRunPortAllowTransaction signalInstallOperation ) || status=$?
        [[ "${status}" == 143 && "$(<"${fixture}/xray.conf")" == new ]]
        [[ -d "$(<"${fixture}/config-backup")" ]]
        grep -q '停止失败\|旧配置恢复失败' "${fixture}/errors.log"
    done

    (
        # 未登记新文件的子 shell 也不能清掉父 shell 的临时备份。
        padmCreateTmpRootPath parentTemp signal-parent.XXXXXX -d
        childStatus=0
        # Bash 5.2.21 需要后续命令处理待决 TERM，不能让 kill 成为最后一条命令。
        ( kill -TERM "${BASHPID}"; : ) || childStatus=$?
        [[ "${childStatus}" == 143 && -d "${parentTemp}" ]]
        padmRemoveCleanupPath "${parentTemp}"
    )
    status=0
    (
        padmCreateTmpRootPath scannerTemp signal-scanner.XXXXXX -d
        printf '%s\n' "${scannerTemp}" >"${root}/scanner-temp"
        trap 'cleanupRealityTargetJobs "" ""' EXIT
        exit 7
    ) || status=$?
    [[ "${status}" == 7 && ! -e "$(<"${root}/scanner-temp")" ]]

    fixture="${root}/package"
    mkdir -p "${fixture}"
    local commandString
    nextInstallProgressTitle() { PADM_INSTALL_PROGRESS_TITLE=$1; }
    printInstallProgressLine() { :; }
    status=0
    (
        printf -v commandString \
            '(sleep 2; printf continued >%q) & (sleep 0.2; kill -TERM %s) & wait' \
            "${fixture}/continued" "${BASHPID}"
        runPackageCommandWithProgress signal-test 10 "${commandString}" "${fixture}/install.log"
        printf 'returned\n' >"${fixture}/returned"
    ) || status=$?
    [[ "${status}" == 143 && ! -e "${fixture}/returned" ]]
    sleep 2
    [[ ! -e "${fixture}/continued" && ! -e "${fixture}/install.log.progress" ]]
    status=0
    runPackageCommandWithProgress normal-test 10 'printf normal; exit 7' "${fixture}/normal.log" || status=$?
    [[ "${status}" == 7 && "$(<"${fixture}/normal.log")" == normal ]]
    [[ ! -e "${fixture}/normal.log.progress" && -z "${PADM_EXIT_ROLLBACKS[*]}" ]]

    (
        source "${PROJECT_ROOT}/shell/subscription/accounts.sh"
        source "${PROJECT_ROOT}/shell/subscription/output.sh"
        eval "$(awk '/^cleanDirectoryContent\(\)/ { capture=1 } capture { print } capture && /^}/ { exit }' "${PROJECT_ROOT}/shell/core/runtime.sh")"
        local PADM_SUBSCRIBE_LOCAL_DIR category outputBackupDir selectCustomInstallType=",999,"
        mode=normal core=sing-box
        serviceQueueRestart() { :; }
        serviceQueueApply() { :; }
        checkGFWStatue() { :; }
        cleanUp() { :; }
        readInstallType() { :; }
        readInstallProtocolType() { :; }
        readConfigHostPathUUID() { :; }
        readSingBoxConfig() { :; }
        protocolCapabilityRegistry() { printf '1|Regression|node\n'; }
        currentProtocolHas() { return 0; }
        subscriptionAccountDisplayFunction() { printf 'signalOutputDisplayAccounts\n'; }
        signalOutputDisplayAccounts() {
            printf '%s\n' "${PADM_CORE_TEMPLATE_ROLLBACK[subscribeOutputBackupDir]}" >"${fixture}/output-backup"
            appendDefaultSubscribeLine new-user new-default
            kill -"${signal}" "${BASHPID}"
            :
        }
        for signal in INT TERM; do
            fixture="${root}/subscribe-${signal}"
            PADM_SUBSCRIBE_LOCAL_DIR="${fixture}/subscribe_local"
            for category in default clashMeta sing-box; do
                mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}"
                printf 'old-%s\n' "${category}" >"${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/old-user"
            done
            for category in xray.conf sing-box.conf nginx.conf; do
                printf 'old\n' >"${fixture}/${category}"
            done
            printf 'false\n' >"${fixture}/xray.running"
            printf 'false\n' >"${fixture}/sing-box.running"
            status=0
            ( coreInstallConfigTransaction sing-box completeCoreInstall sing-box 5 6 ) >/dev/null 2>&1 || status=$?
            if [[ "${signal}" == INT ]]; then [[ "${status}" == 130 ]]; else [[ "${status}" == 143 ]]; fi
            for category in default clashMeta sing-box; do
                [[ "$(<"${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/old-user")" == "old-${category}" ]]
                [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/new-user" ]]
            done
            outputBackupDir=$(<"${fixture}/output-backup")
            [[ -n "${outputBackupDir}" && ! -e "${outputBackupDir}" ]]
            [[ ! -e "$(<"${fixture}/config-backup")" ]]
        done
    )
    printf '核心信号回归: 前台取消\n'
    runCancelableInstallCommandRegression
    printf '核心信号回归: 二进制回滚\n'
    runCoreBinaryInstallSignalRollbackRegression
    printf '核心信号回归: 文件整组恢复\n'
    runCoreInstallFileSignalRollbackRegression
    printf '核心信号回归: 旧核心自启恢复\n'
    runCoreStartupSwitchRollbackRegression signal
)

runCoreInstallFileSignalRollbackRegression() (
    local root="${TMP_DIR}/core-install-file-signal"
    local fixture phase signal failure status failed=false
    local version=v1.14.0 singBoxCoreCPUVendor=-linux-amd64
    local PADM_SINGBOX_BINARY PADM_SINGBOX_CONFIG_DIR PADM_TMP_DIR
    local shard merged candidate cronet
    mkdir -p "${root}"
    eval "$(declare -f padmCreateTempPath | sed '1s/^padmCreateTempPath/fileSignalCreateTempPath/')"
    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/fileSignalCommitGeneratedFile/')"
    eval "$(declare -f restoreManagedFileFromBackup | sed '1s/^restoreManagedFileFromBackup/fileSignalRestoreManagedFileFromBackup/')"
    padmCreateTempPath() {
        if [[ "${2:-}" == -d && "${3:-}" == /etc/padm/* ]]; then
            fileSignalCreateTempPath "$1" -d "${PADM_TMP_DIR}/install.XXXXXX"
        else
            fileSignalCreateTempPath "$@"
        fi
        [[ ! -d "${!1}" ]] || printf '%s\n' "${!1}" >>"${fixture}/backups"
    }
    restoreManagedFileFromBackup() {
        if [[ "${phase}" == *-restore && ! -e "${fixture}/restore-signaled" ]]; then
            : >"${fixture}/restore-signaled"
            kill -"${signal}" "${BASHPID}"
        fi
        [[ "${failure}" != restore-fail ]] || return 1
        fileSignalRestoreManagedFileFromBackup "$@"
    }
    commitGeneratedFile() {
        # 只在实际目标上注入故障，不能匹配回滚登记前的同名备份。
        if [[ ! -e "${fixture}/commit-failed" &&
            ( ( "${phase}" == first-restore && "$2" == "${PADM_SINGBOX_BINARY}" ) ||
                ( "${phase}" == geo-restore && "$2" == "${fixture}/geo-target/geoip.dat" ) ) ]]; then
            : >"${fixture}/commit-failed"
            return 1
        fi
        fileSignalCommitGeneratedFile "$@" || return 1
        if [[ "${phase}" == migration-restore && "$2" == "${shard}" &&
            ! -e "${fixture}/commit-failed" ]]; then
            : >"${fixture}/commit-failed"
            return 1
        fi
        if [[ ( "${phase}" == migration && "$2" == "${shard}" ) ||
            ( "${phase}" == first-cronet && "$2" == "${cronet}" ) ||
            ( "${phase}" == first-binary && "$2" == "${PADM_SINGBOX_BINARY}" ) ||
            ( "${phase}" == geo-* && "$2" == "${fixture}/geo-target/${phase#geo-}" ) ]]; then
            kill -"${signal}" "${BASHPID}"
        fi
    }
    validateSingBoxConfigWithBinary() {
        [[ "${phase}" != validation ]] || kill -"${signal}" "${BASHPID}"
        return 0
    }
    checkLogBackupRestore() { padmRestoreManagedFileBackupManifest "$1"; }
    readInstallType() { :; }
    coreLatestReleaseTag() { printf 'v1.14.0\n'; }
    downloadSingBoxReleaseBinaryToTempDir() { cp -a "${candidate}/." "$2/"; }
    singBoxRunning() { return 1; }
    handleSingBox() { printf '%s\n' "$1" >>"${fixture}/services"; }
    errorCard() { printf '%s\n' "$*" >>"${fixture}/errors"; }
    successCard() { :; }

    for phase in migration validation first-cronet first-binary geo-geosite.dat geo-geoip.dat geo-geo.version \
        migration-restore first-restore geo-restore; do
        for signal in TERM INT; do
            for failure in normal restore-fail; do
                fixture="${root}/${phase}-${signal}-${failure}"
                PADM_TMP_DIR="${fixture}/tmp"
                PADM_SINGBOX_BINARY="${fixture}/installed/sing-box"
                PADM_SINGBOX_CONFIG_DIR="${fixture}/installed/conf/config"
                shard="${PADM_SINGBOX_CONFIG_DIR}/01.json"
                merged="${fixture}/installed/conf/config.json"
                cronet="${fixture}/installed/libcronet.so"
                candidate="${fixture}/candidate"
                mkdir -p "${PADM_TMP_DIR}" "${PADM_SINGBOX_CONFIG_DIR}" "${candidate}/sing-box-${version#v}${singBoxCoreCPUVendor}"
                printf '{"dns":{"independent_cache":true}}\n' >"${shard}"
                printf '{"legacy":true}\n' >"${merged}"
                printf 'old-cronet\n' >"${cronet}"
                printf '#!/usr/bin/env bash\nprintf "sing-box version 1.14.0\\nTags: with_v2ray_api\\n"\n' \
                    >"${candidate}/sing-box-${version#v}${singBoxCoreCPUVendor}/sing-box"
                printf 'new-cronet\n' >"${candidate}/sing-box-${version#v}${singBoxCoreCPUVendor}/libcronet.so"
                chmod 755 "${candidate}/sing-box-${version#v}${singBoxCoreCPUVendor}/sing-box"
                if [[ "${phase}" != first-* ]]; then
                    printf 'old-binary\n' >"${PADM_SINGBOX_BINARY}"
                    chmod 755 "${PADM_SINGBOX_BINARY}"
                fi
                mkdir -p "${fixture}/geo-stage" "${fixture}/geo-target"
                printf 'new-geosite\n' >"${fixture}/geo-stage/geosite.dat"
                printf 'new-geoip\n' >"${fixture}/geo-stage/geoip.dat"
                local geoFile
                for geoFile in geosite.dat geoip.dat geo.version; do
                    printf 'old-%s\n' "${geoFile}" >"${fixture}/geo-target/${geoFile}"
                done
                : >"${fixture}/backups"
                status=0
                (
                    local singBoxConfigPath=
                    local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
                    local PADM_EXIT_ROLLBACK_OWNER= PADM_EXIT_ROLLBACKS=()
                    case "${phase}" in
                    first-*) installSingBoxApply 1 ;;
                    geo-*) commitXrayGeoFilesFromStage "${fixture}/geo-stage" "${fixture}/geo-target" new-version ;;
                    *) installDownloadedSingBoxBinary "${version}" "${candidate}" ;;
                    esac || exit $?
                    printf 'continued\n' >"${fixture}/continued"
                ) 2>"${fixture}/errors" || status=$?
                if (
                    if [[ "${phase}" == *-restore ]]; then
                        [[ "${status}" == 1 && -e "${fixture}/restore-signaled" ]] || return 1
                    else
                        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]] || return 1
                    fi
                    [[ ! -e "${fixture}/continued" ]] || return 1
                    if [[ "${failure}" == normal ]]; then
                        case "${phase}" in
                        migration* | validation)
                            [[ "$(<"${shard}")" == '{"dns":{"independent_cache":true}}' &&
                                "$(<"${merged}")" == '{"legacy":true}' &&
                                "$(<"${PADM_SINGBOX_BINARY}")" == old-binary ]] || return 1
                            ;;
                        first-*) [[ ! -e "${PADM_SINGBOX_BINARY}" && "$(<"${cronet}")" == old-cronet ]] || return 1 ;;
                        geo-*)
                            for geoFile in geosite.dat geoip.dat geo.version; do
                                [[ "$(<"${fixture}/geo-target/${geoFile}")" == "old-${geoFile}" ]] || return 1
                            done
                            ;;
                        esac
                        while IFS= read -r backup; do [[ ! -e "${backup}" ]] || return 1; done <"${fixture}/backups"
                    else
                        [[ -s "${fixture}/errors" ]] || return 1
                        local backup kept=false
                        while IFS= read -r backup; do [[ ! -d "${backup}" ]] || kept=true; done <"${fixture}/backups"
                        [[ "${kept}" == true ]] || return 1
                    fi
                ); then
                    printf '文件事务中断通过: %s %s %s\n' "${phase}" "${signal}" "${failure}"
                else
                    printf '文件事务中断失败: %s %s %s，退出 %s\n' "${phase}" "${signal}" "${failure}" "${status}" >&2
                    cat "${fixture}/errors" >&2
                    failed=true
                fi
            done
        done
    done
    [[ "${failed}" == false ]]
)

runCoreBinaryInstallSignalRollbackRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/core-binary-install-signal"
    local fixture core signal phase wasRunning failure status backup originalBinary candidateDir installFunction
    local version=v1.2.3 singBoxCoreCPUVendor=-linux-amd64
    local PADM_XRAY_BINARY PADM_SINGBOX_BINARY PADM_TMP_DIR="${root}/tmp"
    mkdir -p "${PADM_TMP_DIR}"
    xrayConfigInstalled() { return 1; }
    singBoxConfigInstalled() { return 1; }
    xrayRunning() { grep -qx true "${fixture}/running"; }
    singBoxRunning() { grep -qx true "${fixture}/running"; }
    errorCard() { printf '%s\n' "$@" >>"${fixture}/errors.log"; }
    ensureSingBoxTrafficStatsConfig() { return 0; }
    eval "$(declare -f commitStagedCoreInstallFile | sed '1s/^commitStagedCoreInstallFile/signalRealCommitStagedCoreInstallFile/')"
    eval "$(declare -f backupManagedFileToPath | sed '1s/^backupManagedFileToPath/signalRealBackupManagedFileToPath/')"
    eval "$(declare -f restoreManagedFileFromBackup | sed '1s/^restoreManagedFileFromBackup/signalRealRestoreManagedFileFromBackup/')"
    backupManagedFileToPath() {
        signalRealBackupManagedFileToPath "$@" || return 1
        printf '%s\n' "$2" >>"${fixture}/backups"
    }
    restoreManagedFileFromBackup() {
        [[ "${failure}" != restore-fail || "$2" != "${originalBinary}" ]] || return 1
        signalRealRestoreManagedFileFromBackup "$@"
    }
    signalBinaryInstall() {
        [[ ! -e "${fixture}/signaled" ]] || return 0
        printf '%s\n' "${phase}" >"${fixture}/signaled"
        kill -"${signal}" "${BASHPID}"
    }
    commitStagedCoreInstallFile() {
        signalRealCommitStagedCoreInstallFile "$@" || return 1
        if [[ "${phase}" == binary && "$2" == "${originalBinary}" ]] ||
            [[ "${phase}" == cronet && "$2" == "$(coreSingBoxCronetPath)" ]]; then
            signalBinaryInstall
        fi
    }
    handleSignalBinaryService() {
        # 同名局部变量不能覆盖安装层保存的回滚快照。
        local oldBinary=unrelated backupBinary=unrelated cronetBackup=unrelated
        printf '%s\n' "$1" >>"${fixture}/service.log"
        [[ "${failure}" != stop-fail || "$1" != stop || ! -e "${fixture}/signaled" ]] || return 1
        printf '%s\n' "$([[ "$1" == start ]] && printf true || printf false)" >"${fixture}/running"
        [[ "${phase}" != "$1" ]] || signalBinaryInstall
    }
    handleXray() { handleSignalBinaryService "$@"; }
    handleSingBox() { handleSignalBinaryService "$@"; }

    for core in xray sing-box; do
        for signal in TERM INT; do
            for phase in stop binary cronet start; do
                [[ "${core}" != xray || "${phase}" != cronet ]] || continue
                for wasRunning in true false; do
                    for failure in normal stop-fail restore-fail; do
                        [[ "${failure}" == normal || ( "${phase}" == start && "${wasRunning}" == true ) ]] || continue
                        fixture="${root}/${core}-${signal}-${phase}-${wasRunning}-${failure}"
                        printf '二进制中断检查: %s %s %s %s %s\n' "${core}" "${signal}" "${phase}" "${wasRunning}" "${failure}"
                        candidateDir="${fixture}/candidate"
                        PADM_XRAY_BINARY="${fixture}/installed/xray"
                        PADM_SINGBOX_BINARY="${fixture}/installed/sing-box"
                        mkdir -p "${fixture}/installed" "${candidateDir}"
                        printf '%s\n' "${wasRunning}" >"${fixture}/running"
                        if [[ "${core}" == xray ]]; then
                            originalBinary=${PADM_XRAY_BINARY}
                            installFunction=installDownloadedXrayBinary
                            printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${candidateDir}/xray"
                            chmod 755 "${candidateDir}/xray"
                        else
                            originalBinary=${PADM_SINGBOX_BINARY}
                            installFunction=installDownloadedSingBoxBinary
                            local extractedDir="${candidateDir}/sing-box-${version#v}${singBoxCoreCPUVendor}"
                            mkdir -p "${extractedDir}"
                            printf '#!/usr/bin/env bash\nprintf "sing-box version 1.2.3\\nTags: with_v2ray_api\\n"\n' >"${extractedDir}/sing-box"
                            chmod 755 "${extractedDir}/sing-box"
                            printf 'new-cronet\n' >"${extractedDir}/libcronet.so"
                            printf 'old-cronet\n' >"$(coreSingBoxCronetPath)"
                        fi
                        printf 'old-binary\n' >"${originalBinary}"
                        chmod 755 "${originalBinary}"
                        status=0
                        (
                            local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
                            local PADM_EXIT_ROLLBACK_OWNER= PADM_EXIT_ROLLBACKS=()
                            padmRegisterCleanupPath "${candidateDir}"
                            "${installFunction}" "${version}" "${candidateDir}"
                            printf 'continued\n' >"${fixture}/continued"
                        ) || status=$?
                        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]]
                        [[ ! -e "${fixture}/continued" && -e "${fixture}/signaled" ]]
                        if [[ "${failure}" == normal ]]; then
                            [[ "$(<"${originalBinary}")" == old-binary ]] || {
                                printf '%s %s %s 未恢复旧二进制\n' "${core}" "${signal}" "${phase}" >&2
                                return 1
                            }
                            [[ "$(<"${fixture}/running")" == "${wasRunning}" ]] || {
                                printf '%s %s %s 未恢复原服务状态 %s\n' "${core}" "${signal}" "${phase}" "${wasRunning}" >&2
                                return 1
                            }
                            [[ "${core}" != sing-box || "$(<"$(coreSingBoxCronetPath)")" == old-cronet ]]
                        else
                            [[ "$(<"${originalBinary}")" != old-binary ]]
                            [[ "${failure}" != restore-fail || "$(<"${fixture}/running")" == false ]]
                            [[ "${core}" != sing-box || "${failure}" != stop-fail || "$(<"$(coreSingBoxCronetPath)")" == new-cronet ]]
                        fi
                        while IFS= read -r backup; do
                            if [[ "${failure}" == normal ]]; then
                                [[ ! -e "${backup}" ]] || return 1
                            else
                                [[ -f "${backup}" ]] || {
                                    printf '%s %s 回滚失败丢失备份 %s\n' "${core}" "${signal}" "${backup}" >&2
                                    return 1
                                }
                            fi
                        done <"${fixture}/backups"
                    done
                done
            done
        done
    done
    (
        local oldState
        eval "$(declare -f padmCreateTempPath | sed '1s/^padmCreateTempPath/firstXrayCreateTempPath/')"
        padmCreateTempPath() {
            if [[ "${2:-}" == -d && "${3:-}" == /etc/padm/* ]]; then
                firstXrayCreateTempPath "$1" -d "${PADM_TMP_DIR}/first-xray.XXXXXX"
            else
                firstXrayCreateTempPath "$@"
            fi
            [[ ! -d "${!1}" ]] || printf '%s\n' "${!1}" >>"${fixture}/roots"
        }
        readInstallType() { :; }
        coreLatestReleaseTag() { printf 'v1.2.3\n'; }
        downloadXrayReleaseBinaryToTempDir() { cp -a "${candidateDir}/." "$2/"; }
        ensureXrayGeoFiles() { [[ "${phase}" != geo ]] || signalBinaryInstall; }
        # 首装替换无文件或不可执行残留后，核心提交与 Geo 准备都不能留下半安装状态。
        for phase in binary geo; do
            for signal in TERM INT; do
                for oldState in absent broken; do
                    for failure in normal restore-fail; do
                        [[ "${failure}" != restore-fail || "${oldState}" == broken ]] || continue
                        fixture="${root}/first-xray-${phase}-${signal}-${oldState}-${failure}"
                        candidateDir="${fixture}/candidate"
                        PADM_XRAY_BINARY="${fixture}/installed/xray"
                        PADM_TMP_DIR="${fixture}/tmp"
                        originalBinary=${PADM_XRAY_BINARY}
                        mkdir -p "${fixture}/installed" "${candidateDir}" "${PADM_TMP_DIR}"
                        printf 'false\n' >"${fixture}/running"
                        printf '#!/usr/bin/env bash\nprintf "Xray 1.2.3\\n"\n' >"${candidateDir}/xray"
                        chmod 755 "${candidateDir}/xray"
                        if [[ "${oldState}" == broken ]]; then
                            printf 'old-binary\n' >"${originalBinary}"
                            chmod 644 "${originalBinary}"
                        fi
                        status=0
                        (
                            local PADM_CLEANUP_TRAP_INSTALLED= PADM_CLEANUP_PATHS=()
                            local PADM_EXIT_ROLLBACK_OWNER= PADM_EXIT_ROLLBACKS=()
                            installXrayApply 1
                            printf 'continued\n' >"${fixture}/continued"
                        ) || status=$?
                        [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]]
                        [[ ! -e "${fixture}/continued" && -e "${fixture}/signaled" ]]
                        [[ "$(<"${fixture}/running")" == false ]]
                        if [[ "${failure}" == normal ]]; then
                            if [[ "${oldState}" == broken ]]; then
                                [[ "$(<"${originalBinary}")" == old-binary && "$(stat -c %a "${originalBinary}")" == 644 ]]
                            else
                                [[ ! -e "${originalBinary}" ]]
                            fi
                            while IFS= read -r backup; do [[ ! -e "${backup}" ]] || return 1; done <"${fixture}/roots"
                        else
                            [[ "$(<"${originalBinary}")" != old-binary && -s "${fixture}/errors.log" ]]
                            while IFS= read -r backup; do
                                [[ -d "${backup}" && "$(<"${backup}/xray.bak")" == old-binary ]] || return 1
                            done <"${fixture}/roots"
                        fi
                        printf '首装 Xray 中断通过: %s %s %s %s\n' "${phase}" "${signal}" "${oldState}" "${failure}"
                    done
                done
            done
        done
    )
)

runCancelableInstallCommandRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/cancelable-install" fixture mode signal pid status started
    local release=alpine domain=cancel.example.com tlsDomain=cancel.example.com
    local sslType=letsencrypt dnsAPIStatus=n dnsAPIType= installedDNSAPIStatus=
    local commandString PADM_TLS_DIR TMPDIR captured cfAPIToken=fixture-token cfZoneID=fixture-zone
    local aliKey=fixture-key aliSecret=fixture-secret
    mkdir -p "${root}"
    TMPDIR="${root}"
    successCard() { :; }
    errorCard() { printf '%s\n' "$@" >>"${fixture}/errors"; }
    acmeExecutable() { printf '%s\n' "${fixture}/acme"; }
    allowPort() { :; }
    nginxRunning() { grep -qx true "${fixture}/nginx.running"; }
    xrayRunning() { grep -qx true "${fixture}/xray.running"; }
    singBoxRunning() { return 1; }
    handleNginx() { printf '%s\n' "$([[ "$1" == start ]] && printf true || printf false)" >"${fixture}/nginx.running"; }
    handleXray() { printf '%s\n' "$([[ "$1" == start ]] && printf true || printf false)" >"${fixture}/xray.running"; }
    checkDNSIP() { :; }
    subscriptionTcpPortHasListener() { nginxRunning; }
    subscriptionTcpPortListenersAreNginx() { :; }
    runSubscribeNginxAction() { handleNginx "$@"; }
    customSSLEmail() { :; }
    readAcmeTLS() { :; }
    tlsAcmeManagedCertificateRecords() {
        printf '%s\t%s\t%s\t%s\n' cancel.example.com "${fixture}/domain.conf" \
            "${PADM_TLS_DIR}/cancel.example.com.crt" "${PADM_TLS_DIR}/cancel.example.com.key"
    }
    sudo() { "$@"; }
    curl() { cancelableFixtureWorker; }
    wget() { cancelableFixtureWorker; }
    command() {
        if [[ "$*" == '-v curl' && "${mode}" == wget ]] ||
            [[ "$*" == '-v timeout' && "${mode}" == timeout-no-tool ]]; then
            return 1
        fi
        builtin command "$@"
    }
    cancelableFixtureWorker() {
        printf '%s\n' "${BASHPID}" >"${fixture}/worker"
        : >"${fixture}/started"
        sleep 4
        : >"${fixture}/continued"
    }
    cancelableFixtureOperation() {
        case "${mode}" in
        timeout | timeout-no-tool)
            printf -v commandString 'printf %%s "$BASHPID" >%q; touch %q; sleep 4; touch %q' \
                "${fixture}/worker" "${fixture}/started" "${fixture}/continued"
            runWithTimeout 10 "${commandString}"
            ;;
        curl | wget) downloadUrlToFileBounded fixture "${fixture}/download" 1024 10 ;;
        capture) padmCaptureCancelableCommand captured resolveGitHubCommitRef fixture/repo main ;;
        acme-install | acme-restore-failure)
            acmeInstallIsComplete() { return 1; }
            acmeInstallTargetIsSafe() { :; }
            acmeSafeHomeDir() { printf '%s\n' "${fixture}/acme-home"; }
            adapterManagedRollbackTemplate() { printf '%s\n' "${fixture}/backup.XXXXXX"; }
            resolveGitHubCommitRef() {
                printf 'new-account\n' >"${fixture}/acme-home/account"
                : >"${fixture}/acme-home/added"
                cancelableFixtureWorker
            }
            if [[ "${mode}" == acme-restore-failure ]]; then
                adapterRestoreManagedRollbackBackup() { return 1; }
            fi
            installAcmeTool
            ;;
        issue) acmeInstallSSL ;;
        issue-retry) selectAcmeInstallSSL ;;
        cloudflare | aliyun) dnsAPIType=${mode}; acmeInstallSSL ;;
        subscription)
            installTLS() { acmeInstallSSL; }
            subscriptionInstallTLSHttp01 "${domain}"
            ;;
        tls-flow)
            local HOME="${fixture}/home" PADM_REQUIRE_USABLE_TLS_CERTIFICATE=true
            mkdir -p "${HOME}/.acme.sh"
            switchSSLType() { :; }
            installTLS 1
            ;;
        sync | sync-missing) installTLSFromAcme ;;
        renew) renewManagedTLSCertificates ;;
        esac
    }
    for mode in timeout timeout-no-tool curl wget capture acme-install acme-restore-failure issue issue-retry cloudflare aliyun subscription tls-flow sync sync-missing renew; do
        for signal in TERM INT; do
            fixture="${root}/${mode}-${signal}"
            PADM_TLS_DIR="${fixture}/tls"
            mkdir -p "${PADM_TLS_DIR}"
            printf 'old-cert\n' >"${PADM_TLS_DIR}/${domain}.crt"
            printf 'old-key\n' >"${PADM_TLS_DIR}/${domain}.key"
            [[ "${mode}" != sync-missing ]] || rm "${PADM_TLS_DIR}/${domain}.key"
            mkdir -p "${fixture}/acme-home"
            printf 'old-account\n' >"${fixture}/acme-home/account"
            printf 'true\n' >"${fixture}/nginx.running"
            printf 'true\n' >"${fixture}/xray.running"
            dnsAPIType=
            printf "Le_Domain='%s'\nLe_Webroot='no'\n" "${domain}" >"${fixture}/domain.conf"
            cat >"${fixture}/acme" <<'EOF'
#!/usr/bin/env bash
fixture=$(dirname -- "$0")
printf '%s\n' "$BASHPID" >"${fixture}/worker"
if [[ "$1" == --issue && "$(basename -- "${fixture}")" == tls-flow-* ]]; then
    touch "${fixture}/issued"
    exit 0
fi
if [[ "$1" == --issue && "$(basename -- "${fixture}")" == issue-retry-* && ! -f "${fixture}/first-issue" ]]; then
    touch "${fixture}/first-issue"
    printf 'Could not validate email address as valid\n'
    exit 1
fi
if [[ "$1" == --installcert || "$1" == --cron ]]; then
    printf 'new-cert\n' >"${fixture}/tls/cancel.example.com.crt"
    printf 'new-key\n' >"${fixture}/tls/cancel.example.com.key"
fi
touch "${fixture}/started"
sleep 4
touch "${fixture}/continued"
EOF
            chmod 755 "${fixture}/acme"
            set -m
            (
                padmCreateTmpRootPath ownedTemp cancel-owned.XXXXXX -d
                printf '%s\n' "${ownedTemp}" >"${fixture}/temp"
                cancelableFixtureOperation
                : >"${fixture}/returned"
            ) >"${fixture}/output" 2>&1 &
            pid=$!
            set +m
            for ((started=0; started < 300; started++)); do
                [[ ! -e "${fixture}/started" ]] || break
                sleep 0.01
            done
            if [[ ! -e "${fixture}/started" ]]; then
                printf 'cancel fixture did not start: %s:%s\n' "${mode}" "${signal}" >&2
                cat "${fixture}/output" >&2
                kill -KILL -- "-${pid}" 2>/dev/null || true
                wait "${pid}" || true
                return 1
            fi
            started=$(date +%s%N)
            kill -"${signal}" "${pid}"
            status=0
            wait "${pid}" || status=$?
            [[ "${status}" == "$([[ "${signal}" == TERM ]] && printf 143 || printf 130)" ]]
            [[ $(( ($(date +%s%N) - started) / 1000000 )) -lt 3500 ]]
            [[ ! -e "${fixture}/continued" && ! -e "${fixture}/returned" && ! -e "$(<"${fixture}/temp")" ]]
            if [[ "${mode}" == sync || "${mode}" == renew || "${mode}" == tls-flow ]]; then
                [[ "$(<"${PADM_TLS_DIR}/${domain}.crt")" == old-cert &&
                    "$(<"${PADM_TLS_DIR}/${domain}.key")" == old-key ]]
                [[ "${mode}" != tls-flow || -e "${fixture}/issued" ]]
            elif [[ "${mode}" == sync-missing ]]; then
                [[ "$(<"${PADM_TLS_DIR}/${domain}.crt")" == old-cert && ! -e "${PADM_TLS_DIR}/${domain}.key" ]]
            elif [[ "${mode}" == acme-install ]]; then
                [[ "$(<"${fixture}/acme-home/account")" == old-account && ! -e "${fixture}/acme-home/added" ]]
                [[ -z "$(find "${fixture}" -name 'backup.*' -type d)" ]]
            elif [[ "${mode}" == acme-restore-failure ]]; then
                captured=$(find "${fixture}" -name 'backup.*' -type d)
                [[ -f "${captured}/manifest" && "$(<"${captured}/000000.dir/account")" == old-account ]]
                grep -q 'acme.sh 安装中断，目录恢复失败' "${fixture}/errors"
            fi
            if [[ "${mode}" == issue || "${mode}" == issue-retry || "${mode}" == subscription || "${mode}" == renew || "${mode}" == tls-flow ]]; then
                [[ "$(<"${fixture}/nginx.running")" == true ]]
                [[ "$(<"${fixture}/xray.running")" == true ]]
            fi
            [[ "$(ps -o stat= -p "$(<"${fixture}/worker")" 2>/dev/null || true)" != *[RS]* ]]
        done
    done

    local output status release=debian attempts="${root}/attempts"
    waitAptProcess() { :; }
    sleep() { :; }
    mode=wget
    wget() { head -c 32 /dev/zero; }
    if downloadUrlToFileBounded fixture "${root}/oversized" 16 10; then
        return 1
    fi
    [[ "$(wc -c <"${root}/oversized")" == 17 ]]
    mode=fallback
    curl() { return 1; }
    wget() { printf fallback; }
    downloadUrlToFileBounded fixture "${root}/fallback" 16 10
    [[ "$(<"${root}/fallback")" == fallback ]]
    # apt/dpkg 的重试、输出捕获和普通失败码不因托管改变。
    printf -v commandString 'printf "apt-get\\n" >>%q; [[ $(wc -l <%q) == 2 ]]' "${attempts}" "${attempts}"
    runWithTimeout 10 "${commandString}"
    [[ "$(wc -l <"${attempts}")" == 2 ]]
    padmCaptureCancelableCommand output printf 'quoted space\n\n'
    [[ "${output}" == 'quoted space' ]]
    status=0
    runWithTimeout 10 'printf failure; exit 7' >"${root}/failure.log" || status=$?
    [[ "${status}" == 7 && "$(<"${root}/failure.log")" == failure ]]
)

runCoreTemplateReturnFailureRegression() (
    local release=debian
    local root="${TMP_DIR}/core-template-return"
    local xrayRoot="${root}/xray"
    local singBoxRoot="${root}/sing-box"
    local nginxRoot="${root}/nginx"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local entryHostFile="${root}/reality_entry_host"
    local mode=xray
    local xrayRc singBoxRc
    local stopRc writeCalls=0 serviceLog="${TMP_DIR}/core-template-service.log"
    local singBoxServiceRunning=true
    local xrayServiceRunning=true

    mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
    PADM_XRAY_BINARY="${root}/xray-install/xray"
    configPath="${xrayRoot}/"
    singBoxConfigPath="${singBoxRoot}/"
    nginxConfigPath="${nginxRoot}/"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    PADM_REALITY_ENTRY_HOST_FILE="${entryHostFile}"
    : >"${firewallLog}"
    currentUUID=11111111-1111-4111-8111-111111111111
    currentClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"regression"}]'
    domain=tls.example.com
    currentHost=tls.example.com
    lastInstallationConfig=true
    selectCustomInstallType=",1,"
    singBoxVLESSVisionPort=10890
    singBoxVLESSWSPort=10891

    xrayTemplateConfigDir() { printf '%s\n' "${xrayRoot}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${singBoxRoot}"; }
    initXrayClients() { printf '[]\n'; }
    initSingBoxClients() { printf '[]\n'; }
    addXrayOutbound() { [[ "${mode}" != "xray-outbound" ]]; }
    checkDNSIP() { return 0; }
    removeNginxDefaultConf() { return 0; }
    randomPathFunction() { currentPath=template-path; }
    xrayRunning() { [[ "${xrayServiceRunning}" == "true" ]]; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            xrayServiceRunning=false
        elif [[ "$1" == "start" ]]; then
            xrayServiceRunning=true
        fi
    }
    singBoxRunning() { [[ "${singBoxServiceRunning}" == "true" ]]; }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        if [[ "$1" == "stop" ]]; then
            [[ "${mode}" != "stop-fail" ]] || return 1
            singBoxServiceRunning=false
        elif [[ "$1" == "start" ]]; then
            singBoxServiceRunning=true
        fi
    }
    checkPortOpen() { return 0; }
    initSingBoxPort() {
        # 输入预采集不能提前写防火墙，否则事务会误认为端口规则原本存在。
        [[ "${7:-false}" != true ]] || { printf '10890\n'; return 0; }
        if [[ "${mode}" == "state-drift" ]]; then
            padmTrackPortAllowTransactionKey "port:ufw:tcp:10890"
        else
            padmFirewallStateAdd "port:ufw:tcp:10890"
            padmFirewallStateAdd "port:ufw:udp:10890"
        fi
        printf '10890\n'
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
        return 0
    }
    writeGeneratedJsonFile() {
        local targetFile=$1
        local mappedTarget=${targetFile}
        shift 2
        writeCalls=$((writeCalls + 1))
        if [[ "${mode}" == "xray" && "${targetFile}" == "/etc/padm/xray/conf/09_routing.json" ]]; then
            return 1
        fi
        if [[ "${mode}" == "sing-box" && "${targetFile}" == "/etc/padm/sing-box/conf/config/03_VLESS_WS_inbounds.json" ]]; then
            return 1
        fi
        case "${targetFile}" in
        /etc/padm/xray/conf/*) mappedTarget="${xrayRoot}/${targetFile##*/}" ;;
        /etc/padm/sing-box/conf/config/*) mappedTarget="${singBoxRoot}/${targetFile##*/}" ;;
        esac
        cat >"${mappedTarget}"
    }

    printf '%s\n' 'old-xray-log' >"${xrayRoot}/00_log.json"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null
    [[ "$(<"${xrayRoot}/00_log.json")" == 'old-xray-log' ]]
    [[ ! -e "${xrayRoot}/12_policy.json" ]]
    [[ ! -e "${xrayRoot}/11_dns.json" ]]

    mode=xray-outbound
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null
    [[ ! -e "${xrayRoot}/09_routing.json" ]]

    mode=stop-fail
    selectCustomInstallType=",27,"
    writeCalls=0
    : >"${serviceLog}"
    SERVICE_QUEUE_ALLOW_FAILURE=previous
    rm -f "${firewallState}"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    [[ "${writeCalls}" == "0" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=sing-box
    selectCustomInstallType=",27,21,"
    writeCalls=0
    printf '%s\n' 'old-sing-box-inbound' >"${singBoxRoot}/02_VLESS_TCP_inbounds.json"
    : >"${serviceLog}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    [[ "${writeCalls}" != "0" ]]
    [[ "$(<"${singBoxRoot}/02_VLESS_TCP_inbounds.json")" == 'old-sing-box-inbound' ]]
    [[ ! -e "${singBoxRoot}/03_VLESS_WS_inbounds.json" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]
    grep -qx 'sing-box:start:true' "${serviceLog}"
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    mode=stop-fail
    writeCalls=0
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    regressionExpectFailure initSingBoxConfig custom 1 true 2>/dev/null
    ! grep -q ':tcp$' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    padmFirewallStateHas "port:ufw:tcp:10890"
    ! padmFirewallStateHas "port:ufw:udp:10890"
    rm -f "${firewallState}"

    readLastInstallationConfig() { return 0; }
    installTools() { return 0; }
    installSingBox() { return 0; }
    installSingBoxService() { return 0; }
    serviceQueueRestart() { return 0; }
    serviceQueueApply() { return 0; }
    checkGFWStatue() { return 0; }
    showAccounts() { return 0; }
    collectEntryProfile() {
        realityEntryHost=new-entry.example.com
        return 0
    }
    initSingBoxConfig() {
        local result=()
        readSingBoxPortResult result 10890 false
    }
    cleanUp() {
        xrayServiceRunning=false
        return 1
    }
    mode=install-failure
    printf 'old-entry.example.com\n' >"${entryHostFile}"
    rm -f "${firewallState}"
    : >"${firewallLog}"
    : >"${serviceLog}"
    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    grep -qx 'ufw:10890:udp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]
    [[ "$(<"${entryHostFile}")" == "old-entry.example.com" ]]
    [[ "${xrayServiceRunning}" == "true" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'sing-box:stop:true' "${serviceLog}"
    grep -qx 'sing-box:start:true' "${serviceLog}"

    mode=state-drift
    padmFirewallStateAdd "port:ufw:tcp:10890"
    : >"${firewallLog}"
    : >"${serviceLog}"
    regressionExpectStatus 1 installSingBoxReality >/dev/null 2>&1
    grep -qx 'ufw:10890:tcp' "${firewallLog}"
    ! grep -q ':udp$' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]
    [[ "$(<"${entryHostFile}")" == "old-entry.example.com" ]]
    [[ "${xrayServiceRunning}" == "true" ]]
    [[ "${singBoxServiceRunning}" == "true" ]]

    local manualUuid=11111111-1111-1111-1111-111111111111
    local manualUser=sub_manual
    local uuidGenerationLog="${root}/uuid-generation.log"
    local AUTO_INSTALL=true AUTO_UUID=${manualUuid} AUTO_USER=${manualUser}
    autoRead() {
        case "$1" in
        core_init_uuid) printf -v "$3" '%s' "${manualUuid}" ;;
        core_init_username) printf -v "$3" '%s' "${manualUser}" ;;
        *) return 1 ;;
        esac
    }
    collectTLSProfile() { tlsCertDomain=tls.example.com; }
    currentUUID=
    currentClients='[]'
    lastInstallationConfig=
    writeCalls=0
    regressionExpectFailure initXrayConfigApply custom 1 true 2>/dev/null
    [[ "${writeCalls}" == "0" ]]

    selectCustomInstallType=",27,"
    regressionExpectFailure initSingBoxConfigApply custom 1 true 2>/dev/null
    [[ "${writeCalls}" == "0" ]]

    manualUuid=not-a-uuid
    AUTO_UUID=${manualUuid}
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${xrayRc}" != "0" && "${singBoxRc}" != "0" ]]
    [[ "${writeCalls}" == "0" ]]

    manualUuid=
    manualUser=manual
    AUTO_UUID=
    AUTO_USER=${manualUser}
    : >"${uuidGenerationLog}"
    generateRandomUuidValue() {
        printf 'call\n' >>"${uuidGenerationLog}"
        return 1
    }
    set +e
    initXrayConfigApply custom 1 true 2>/dev/null
    xrayRc=$?
    initSingBoxConfigApply custom 1 true 2>/dev/null
    singBoxRc=$?
    set -e
    [[ "${xrayRc}" != "0" && "${singBoxRc}" != "0" ]]
    [[ "$(grep -c '^call$' "${uuidGenerationLog}")" == "2" ]]
    [[ "${writeCalls}" == "0" ]]
    currentUUID=11111111-1111-4111-8111-111111111111
    currentClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"regression"}]'
    lastInstallationConfig=true
    unset AUTO_INSTALL AUTO_UUID AUTO_USER

    mode=template
    initRealityProfile() { return 0; }
    initXrayRealityPort() { return 0; }
    initRealityKey() { return 1; }
    initRealityMldsa65() { return 0; }
    selectCustomInstallType=",1,"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null

    installSniffing() { return 1; }
    selectCustomInstallType=",999,"
    regressionExpectFailure initXrayConfig custom 1 true 2>/dev/null

    installSniffing() { return 0; }
    removeSingBoxConfig() { return 1; }
    setSniffRouting() { return 0; }
    mode=cleanup-fail
    selectCustomInstallType=",999,"
    regressionExpectFailure padmRunPortAllowTransaction initSingBoxConfigApply custom 1 2>/dev/null

    (
        local singBoxRoot="${root}/merged/config"
        local PADM_SINGBOX_CONFIG_DIR="${singBoxRoot}" singBoxConfigPath="${singBoxRoot}/"
        local singBoxServiceRunning=false xrayServiceRunning=false
        local mergedConfig mergedState
        mkdir -p "${singBoxRoot}"
        mergedConfig=$(singBoxMergedConfigFile)
        singBoxInstalled() { return 1; }
        handleSingBox() {
            printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            if [[ "$1" == start ]]; then
                printf 'new-merged-config\n' >"${mergedConfig}"
                singBoxServiceRunning=true
            else
                singBoxServiceRunning=false
            fi
        }
        failAfterSingBoxMerge() {
            printf 'new-sing-box-inbound\n' >"${singBoxRoot}/02_VLESS_TCP_inbounds.json"
            runCoreServiceActionAllowFailure handleSingBox start || return 1
            return 7
        }
        for mergedState in present absent; do
            printf 'old-sing-box-inbound\n' >"${singBoxRoot}/02_VLESS_TCP_inbounds.json"
            if [[ "${mergedState}" == present ]]; then
                printf 'old-merged-config\n' >"${mergedConfig}"
            else
                rm -f "${mergedConfig}"
            fi
            : >"${serviceLog}"
            regressionExpectStatus 7 coreInstallConfigTransaction sing-box failAfterSingBoxMerge >/dev/null 2>&1
            [[ "$(<"${singBoxRoot}/02_VLESS_TCP_inbounds.json")" == old-sing-box-inbound ]]
            [[ "${singBoxServiceRunning}" == false ]]
            grep -qx 'sing-box:start:true' "${serviceLog}"
            grep -qx 'sing-box:stop:true' "${serviceLog}"
            if [[ "${mergedState}" == present ]]; then
                [[ "$(<"${mergedConfig}")" == old-merged-config ]]
            else
                [[ ! -e "${mergedConfig}" ]]
            fi
        done
    )

    (
        source "${PROJECT_ROOT}/shell/subscription/accounts.sh"
        source "${PROJECT_ROOT}/shell/subscription/output.sh"
        eval "$(awk '/^cleanDirectoryContent\(\)/ { capture=1 } capture { print } capture && /^}/ { exit }' "${PROJECT_ROOT}/shell/core/runtime.sh")"
        local PADM_SUBSCRIBE_LOCAL_DIR="${root}/subscribe-output"
        local singBoxServiceRunning=false xrayServiceRunning=false
        local outputMode category backupPath
        eval "$(declare -f subscribeLocalOutputAppendLine | sed '1s/^subscribeLocalOutputAppendLine/installOutputAppendLine/')"
        eval "$(declare -f appendSingBoxSubscribeLocalConfig | sed '1s/^appendSingBoxSubscribeLocalConfig/installOutputAppendSingBox/')"
        eval "$(declare -f subscriptionSyncRestoreBackupPath | sed '1s/^subscriptionSyncRestoreBackupPath/installOutputRestoreBackupPath/')"
        singBoxInstalled() { return 1; }
        serviceQueueRestart() { :; }
        serviceQueueApply() { :; }
        checkGFWStatue() { :; }
        cleanUp() { :; }
        readInstallType() { :; }
        readInstallProtocolType() { :; }
        readConfigHostPathUUID() { :; }
        readSingBoxConfig() { :; }
        protocolCapabilityRegistry() { printf '1|Regression|node\n'; }
        currentProtocolHas() { return 0; }
        subscriptionAccountDisplayFunction() { printf 'installOutputDisplayAccounts\n'; }
        subscribeLocalOutputAppendLine() {
            [[ "$1" != "${PADM_SUBSCRIBE_LOCAL_DIR}/${outputMode}/new-user" ]] || return 7
            installOutputAppendLine "$@"
        }
        appendSingBoxSubscribeLocalConfig() {
            [[ "${outputMode}" != sing-box ]] || return 7
            installOutputAppendSingBox "$@"
        }
        subscriptionSyncRestoreBackupPath() {
            [[ "${outputMode}" != restore-fail ]] || return 1
            installOutputRestoreBackupPath "$@"
        }
        installOutputDisplayAccounts() {
            printf '%s\n' "${PADM_CORE_TEMPLATE_ROLLBACK[subscribeOutputBackupDir]}" >"${root}/output-backup"
            appendDefaultSubscribeLine new-user new-default || return 1
            [[ "${outputMode}" != display && "${outputMode}" != restore-fail ]] || return 7
            appendClashMetaSubscribeBlock new-user new-clash || return 1
            appendSingBoxSubscribeLocalConfig new-user '. + [{type:"vless",tag:"new-user"}]'
        }
        for outputMode in display default clashMeta sing-box success restore-fail; do
            for category in default clashMeta sing-box; do
                mkdir -p "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}"
                printf 'old-%s\n' "${category}" >"${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/old-user"
            done
            if [[ "${outputMode}" == success ]]; then
                coreInstallConfigTransaction sing-box completeCoreInstall sing-box 5 6 >/dev/null
            else
                regressionExpectStatus 1 coreInstallConfigTransaction sing-box completeCoreInstall sing-box 5 6 >/dev/null 2>&1
            fi
            backupPath=$(<"${root}/output-backup")
            [[ -n "${backupPath}" ]]
            if [[ "${outputMode}" == restore-fail ]]; then
                for category in default clashMeta sing-box; do
                    [[ "$(<"${backupPath}/local/${category}/old-user")" == "old-${category}" ]]
                done
                padmRemoveCleanupPath "${backupPath}"
                continue
            fi
            [[ ! -e "${backupPath}" ]]
            for category in default clashMeta sing-box; do
                if [[ "${outputMode}" == success ]]; then
                    [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/old-user" ]]
                    [[ -s "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/new-user" ]]
                else
                    [[ "$(<"${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/old-user")" == "old-${category}" ]]
                    [[ ! -e "${PADM_SUBSCRIBE_LOCAL_DIR}/${category}/new-user" ]]
                fi
            done
        done
    )
)

runCoreStartupSwitchRollbackRegression() (
    local root="${TMP_DIR}/core-startup-switch-${1:-return}" fixture core oldCore platform enabled mode status
    local release=debian selectCustomInstallType=",999," SERVICE_ACTIONS=
    local PADM_CORE_INSTALL_SERVICE_BACKUP_DIR= PADM_CORE_INSTALL_SERVICE_NAME=
    local PADM_CORE_TEMPLATE_TRANSACTION_ACTIVE=false
    local -a modes=(success output-fail disable-fail restore-fail target-service-restore-fail)
    [[ "${1:-}" != signal ]] || modes=(INT TERM)

    coreTemplateConfigBackupCreate() {
        checkLogBackupCreate "$1" "${fixture}/xray.conf" "${fixture}/sing-box.conf"
    }
    coreSwitchCleanupBackupCreate() { printf -v "$1" '%s' ''; }
    checkLogBackupRestore() { padmRestoreManagedFileBackupManifest "$1"; }
    singBoxInstalled() { return 1; }
    nginxRuntimeRequired() { return 1; }
    xrayRunning() { grep -qx true "${fixture}/xray.running"; }
    singBoxRunning() { grep -qx true "${fixture}/sing-box.running"; }
    handleXray() { startupSwitchService xray "$1"; }
    handleSingBox() { startupSwitchService sing-box "$1"; }
    startupSwitchService() {
        printf '%s\n' "$([[ "$2" == start ]] && printf true || printf false)" >"${fixture}/$1.running"
    }
    startupSwitchRegistration() {
        local service=$1 nextEnabled=$2
        printf 'startup:%s:%s\n' "${service}" "${nextEnabled}" >>"${fixture}/actions"
        [[ "${mode}" != restore-fail || "${nextEnabled}" != true ]] || return 1
        printf '%s\n' "${nextEnabled}" >"${fixture}/${service}.enabled"
        [[ "${mode}" != disable-fail || "${nextEnabled}" != false ]]
    }
    systemctl() {
        case "$1" in
        is-enabled) grep -qx true "${fixture}/${3%.service}.enabled" ;;
        enable) startupSwitchRegistration "${2%.service}" true ;;
        disable) startupSwitchRegistration "${2%.service}" false ;;
        daemon-reload) return 0 ;;
        *) return 1 ;;
        esac
    }
    rc-update() {
        case "$1" in
        show)
            local service
            for service in xray sing-box; do
                if grep -qx true "${fixture}/${service}.enabled"; then
                    printf '%s | default\n' "${service}"
                fi
            done
            return 0
            ;;
        add) startupSwitchRegistration "$2" true ;;
        del) startupSwitchRegistration "$2" false ;;
        *) return 1 ;;
        esac
    }
    serviceQueueRestart() { :; }
    serviceQueueApply() { startupSwitchService "${core}" start; }
    checkGFWStatue() { :; }
    cleanUp() { printf 'cleaned\n' >"${fixture}/${oldCore}.conf"; }
    subscribeLocalBaseDir() { printf '%s/subscribe_local\n' "${fixture}"; }
    subscriptionSyncBackupPath() { :; }
    subscriptionSyncRestoreBackupPath() { :; }
    errorCard() { printf '%s\n' "$*" >>"${fixture}/errors"; }
    restoreCoreStartupServiceInstall() {
        padmForgetCleanupPath "$1"
        return 1
    }
    showAccounts() {
        if [[ "${mode}" == target-service-restore-fail ]]; then
            padmCreateTmpRootPath PADM_CORE_INSTALL_SERVICE_BACKUP_DIR target-service-restore.XXXXXX -d || return 1
            PADM_CORE_INSTALL_SERVICE_NAME=${core}
            printf '%s\n' "${PADM_CORE_INSTALL_SERVICE_BACKUP_DIR}" >"${fixture}/service-backup"
        fi
        if [[ "${mode}" == INT || "${mode}" == TERM ]]; then
            kill -"${mode}" "${BASHPID}"
            :
        elif [[ "${mode}" != success ]]; then
            return 7
        fi
    }
    # 使用真实平台登记 helper，文件夹具跨子 shell 记录取消后的 enabled 与运行态。
    for platform in systemd openrc; do
        release=debian
        [[ "${platform}" != openrc ]] || release=alpine
        for core in xray sing-box; do
            oldCore=sing-box
            [[ "${core}" != sing-box ]] || oldCore=xray
            for enabled in true false; do
                for mode in "${modes[@]}"; do
                    [[ "${enabled}" == true || ( "${mode}" != disable-fail && "${mode}" != restore-fail ) ]] || continue
                    fixture="${root}/${platform}-${core}-${enabled}-${mode}"
                    mkdir -p "${fixture}"
                    printf 'old\n' >"${fixture}/xray.conf"
                    printf 'old\n' >"${fixture}/sing-box.conf"
                    printf false >"${fixture}/${core}.running"
                    printf true >"${fixture}/${oldCore}.running"
                    printf false >"${fixture}/${core}.enabled"
                    printf '%s\n' "${enabled}" >"${fixture}/${oldCore}.enabled"
                    : >"${fixture}/actions"
                    : >"${fixture}/errors"
                    status=0
                    ( coreSwitchConfigTransaction "${core}" completeCoreInstall "${core}" 5 6 ) >/dev/null 2>&1 || status=$?
                    if [[ "${mode}" == success ]]; then
                        [[ "${status}" == 0 && "$(<"${fixture}/${oldCore}.enabled")" == false &&
                            "$(<"${fixture}/${oldCore}.running")" == false && "$(<"${fixture}/${core}.running")" == true ]]
                        [[ "${enabled}" != true ]] || grep -qx "startup:${oldCore}:false" "${fixture}/actions"
                    else
                        case "${mode}" in
                        INT) [[ "${status}" == 130 ]] ;;
                        TERM) [[ "${status}" == 143 ]] ;;
                        disable-fail) [[ "${status}" == 1 ]] ;;
                        *) [[ "${status}" == 7 ]] ;;
                        esac
                        [[ "$(<"${fixture}/xray.conf")" == old && "$(<"${fixture}/sing-box.conf")" == old &&
                            "$(<"${fixture}/${core}.running")" == false ]]
                        if [[ "${mode}" == target-service-restore-fail ]]; then
                            [[ "$(<"${fixture}/${oldCore}.running")" == false && -d "$(<"${fixture}/service-backup")" ]]
                            grep -q '核心服务运行状态恢复失败' "${fixture}/errors"
                            padmRemoveCleanupPath "$(<"${fixture}/service-backup")"
                        else
                            [[ "$(<"${fixture}/${oldCore}.running")" == true ]]
                        fi
                        if [[ "${mode}" == restore-fail ]]; then
                            [[ "$(<"${fixture}/${oldCore}.enabled")" == false ]]
                            grep -q '开机自启恢复失败' "${fixture}/errors"
                            ! grep -q '失败，已恢复旧配置' "${fixture}/errors"
                        else
                            [[ "$(<"${fixture}/${oldCore}.enabled")" == "${enabled}" ]]
                            [[ "${enabled}" != true ]] || grep -qx "startup:${oldCore}:true" "${fixture}/actions"
                        fi
                    fi
                done
            done
        done
    done
)

runCoreInstallServiceActionFailureRegression() (
    local release=debian
    local root="${TMP_DIR}/core-install-service-action"
    local serviceLog="${root}/service.log"
    local callLog="${root}/calls.log"
    local errorLog="${root}/errors.log"
    local reachedFile="${root}/reached"
    local firewallState="${root}/firewall.state"
    local firewallLog="${root}/firewall.log"
    local entryHostFile="${root}/reality_entry_host"
    local xrayRoot="${root}/xray"
    local singBoxRoot="${root}/sing-box"
    local nginxRoot="${root}/nginx"
    local PADM_XRAY_BINARY="${xrayRoot}/xray"
    local PADM_XRAY_CONF_DIR="${xrayRoot}"
    local PADM_SINGBOX_CONFIG_DIR="${singBoxRoot}"
    local PADM_SUBSCRIBE_LOCAL_DIR="${root}/subscribe_local"
    local PADM_REALITY_STREAM_CONF_FILE="${nginxRoot}/stream.conf"
    local PADM_REALITY_STREAM_STATE_FILE="${nginxRoot}/stream.json"
    local PADM_REALITY_STREAM_NGINX_CONF="${nginxRoot}/nginx.conf"
    local mode rc nginxRuntimeState
    local xrayRuntimeState=false singBoxRuntimeState=false
    local failStopTarget=

    mkdir -p "${xrayRoot}" "${singBoxRoot}" "${nginxRoot}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_FIREWALL_STATE_FILE="${firewallState}"
    PADM_REALITY_ENTRY_HOST_FILE="${entryHostFile}"
    configPath="${xrayRoot}/"
    singBoxConfigPath="${singBoxRoot}/"
    nginxConfigPath="${nginxRoot}/"
    # 真实备份和回滚只访问夹具，不能触碰 runner 预装的核心或 Nginx 配置。
    xrayTemplateConfigDir() { printf '%s\n' "${xrayRoot}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${singBoxRoot}"; }
    printf 'existing-nginx-main\n' >"${PADM_REALITY_STREAM_NGINX_CONF}"
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    protocolRegistryMenu() { return 0; }
    readLastInstallationConfig() { return 0; }
    coreTemplateCollectInitialClients() { return 0; }
    readInstallTLSPort() { port=2443; return 0; }
    prepareXrayInstallInputs() { return 0; }
    prepareSingBoxInstallInputs() { return 0; }
    unInstallSubscribe() { return 0; }
    installTools() { printf 'installTools:%s\n' "$*" >>"${callLog}"; return 0; }
    initTLSNginxConfig() { printf 'initTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    installTLS() { printf 'installTLS:%s\n' "$*" >>"${callLog}"; return 0; }
    randomPathFunction() {
        printf 'path:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "path-fail" ]]
    }
    nginxBlog() {
        printf 'nginxBlog:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "blog-fail" ]]
    }
    updateRedirectNginxConf() {
        printf 'redirect\n' >>"${callLog}"
        [[ "${mode}" == "redirect-fail" ]] && return 1
        nginxRuntimeState=false
        return 0
    }
    installXray() {
        printf 'installXray:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-install-exit" ]] && exit 1
        return 0
    }
    installXrayService() {
        printf 'installXrayService:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == "xray-service-fail" ]] && return 1
        return 0
    }
    initXrayConfig() {
        printf 'initXrayConfig:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "xray-config-fail" ]]
    }
    installSingBox() { printf 'installSingBox:%s\n' "$*" >>"${callLog}"; return 0; }
    installSingBoxService() { printf 'installSingBoxService:%s\n' "$*" >>"${callLog}"; return 0; }
    initSingBoxConfig() { printf 'initSingBoxConfig:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanUp() { printf 'cleanup:%s\n' "$*" >>"${callLog}"; return 0; }
    cleanAgentNginxConf() { printf 'clean-nginx\n' >>"${callLog}"; return 0; }
    installCronTLS() {
        printf 'cron:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" != "cron-fail" ]]
    }
    customPortFunction() {
        padmFirewallStateAdd 'port:ufw:tcp:2443' || return 1
        padmTrackPortAllowTransactionKey 'port:ufw:tcp:2443'
        printf 'customPort\n' >>"${callLog}"
    }
    removeFirewallPortRule() {
        printf '%s:%s:%s\n' "$1" "$2" "$3" >>"${firewallLog}"
    }
    subscriptionWireGuardControlEnabled() { return 0; }
    refreshSubscriptionWireGuardNginxControl() {
        printf 'wg-refresh\n' >>"${callLog}"
        [[ "${mode}" != "wg-refresh-fail" ]] || return 1
        serviceQueueRefresh nginx
    }
    serviceQueueRefresh() {
        printf 'queueRefresh:%s\n' "$*" >>"${callLog}"
        SERVICE_ACTIONS="${SERVICE_ACTIONS}
$1:refresh"
    }
    serviceQueueRestart() { serviceQueueAdd "$1" restart; }
    serviceQueueStart() { printf 'queueStart:%s\n' "$*" >>"${callLog}"; serviceQueueAdd "$1" start; }
    serviceQueueApply() {
        local entry service action status=0 previousAllowFailure=${SERVICE_QUEUE_ALLOW_FAILURE:-}
        printf 'queueApply\n' >>"${callLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=true
        while read -r entry; do
            [[ -n "${entry}" ]] || continue
            service=${entry%%:*}
            action=${entry#*:}
            runServiceAction "${service}" "${action}" || status=1
        done <<<"${SERVICE_ACTIONS}"
        SERVICE_ACTIONS=
        SERVICE_QUEUE_ALLOW_FAILURE=${previousAllowFailure}
        return "${status}"
    }
    checkGFWStatue() {
        printf 'health:%s:%s\n' "$1" "$2" >>"${callLog}"
        printf 'reached\n' >"${reachedFile}"
        [[ "${mode}" != "check-gfw-fail" ]]
    }
    showAccounts() { printf 'reached\n' >"${reachedFile}"; return 0; }
    handleNginx() {
        printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ -n "${2:-}" ]] && printf 'nginx-mode:%s\n' "$*" >>"${serviceLog}"
        [[ "${mode}" == "nginx-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "nginx-start-fail" && "$1" == "start" && "${2:-}" != "restore" ]] && return 1
        [[ "$1" == "stop" ]] && nginxRuntimeState=false
        [[ "$1" == "start" ]] && nginxRuntimeState=true
        return 0
    }
    nginxRunning() { [[ "${nginxRuntimeState}" == "true" ]]; }
    xrayRunning() { [[ "${xrayRuntimeState}" == "true" ]]; }
    singBoxRunning() { [[ "${singBoxRuntimeState}" == "true" ]]; }
    handleXray() {
        printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${mode}" == "xray-stop-fail" && "$1" == "stop" ]] && return 1
        [[ "${mode}" == "xray-start-fail" && "$1" == "start" ]] && return 1
        [[ "${failStopTarget}" == xray && "$1" == stop && "${xrayRuntimeState}" == true ]] && return 1
        [[ "$1" != start || "${singBoxRuntimeState}" != true ]] || return 1
        [[ "$1" == "stop" ]] && xrayRuntimeState=false
        [[ "$1" == "start" ]] && xrayRuntimeState=true
        return 0
    }
    handleSingBox() {
        printf 'sing-box:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
        [[ "${failStopTarget}" == sing-box && "$1" == stop && "${singBoxRuntimeState}" == true ]] && return 1
        [[ "$1" != start || "${xrayRuntimeState}" != true ]] || return 1
        [[ "$1" == "stop" ]] && singBoxRuntimeState=false
        [[ "$1" == "start" ]] && singBoxRuntimeState=true
        return 0
    }
    validateXrayConfigWithBinary() { return 0; }
    singBoxMergeConfig() { return 0; }
    checkNginxConfig() { return 0; }

    resetInstallServiceFixture() {
        mode=$1
        failStopTarget=
        : >"${serviceLog}"
        : >"${callLog}"
        : >"${errorLog}"
        : >"${firewallLog}"
        rm -f "${reachedFile}"
        rm -f "${firewallState}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        realityOnlyWithDomain=
        currentHost=install.example.com
        domain=install.example.com
        AUTO_ENTRY_HOST=
        AUTO_DOMAIN=install.example.com
        AUTO_REALITY_DOMAIN=
        realityEntryHost=
        nginxRuntimeState=true
        xrayRuntimeState=false
        singBoxRuntimeState=false
        SERVICE_ACTIONS=
        rm -f "${entryHostFile}"
    }

    resetInstallServiceFixture nginx-stop-fail
    regressionExpectStatus 0 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    grep -q '^installXray:' "${callLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    ! grep -q '^clean-nginx$' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "$(<"${entryHostFile}")" == "install.example.com" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture singbox-reality-grpc
    regressionExpectStatus 0 customSingBoxInstall 26 >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    grep -q '^installSingBox:' "${callLog}"
    grep -qx 'cleanup:xrayDel' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "$(<"${entryHostFile}")" == "install.example.com" ]]

    resetInstallServiceFixture path-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'path:4' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture blog-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'nginxBlog:6' "${callLog}"
    ! grep -q '^installXray:' "${callLog}"

    resetInstallServiceFixture cron-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'cron:10' "${callLog}"
    ! grep -q '^queueApply$' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    resetInstallServiceFixture wg-refresh-fail
    regressionExpectStatus 0 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    grep -q '^installXray:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-config-fail
    SERVICE_ACTIONS="existing:start"
    regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^wg-refresh$' "${callLog}"
    ! grep -q '^queueRefresh:nginx$' "${callLog}"
    grep -qx 'initXrayConfig:custom 3' "${callLog}"
    ! grep -q '^cleanup:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]]
    [[ "${SERVICE_ACTIONS}" == "existing:start" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    for mode in xray-install-exit xray-service-fail; do
        resetInstallServiceFixture "${mode}"
        regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
        ! grep -q '^nginx:' "${serviceLog}"
        ! grep -q '^wg-refresh$' "${callLog}"
        ! grep -q '^queueRefresh:nginx$' "${callLog}"
        grep -q '^installXray:' "${callLog}"
        if [[ "${mode}" == "xray-service-fail" ]]; then
            grep -q '^installXrayService:' "${callLog}"
        else
            ! grep -q '^installXrayService:' "${callLog}"
        fi
        [[ "${nginxRuntimeState}" == "true" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    done

    resetInstallServiceFixture check-gfw-fail
    regressionExpectStatus 1 installXrayReality >/dev/null 2>&1
    ! grep -q '^nginx:' "${serviceLog}"
    ! grep -q '^cleanup:' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]] || return 1

    resetInstallServiceFixture nginx-start-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'nginx:start:true' "${serviceLog}"
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-service-fail
    btDomain=panel.example.com
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'customPort' "${callLog}"
    grep -qx 'ufw:2443:tcp' "${firewallLog}"
    [[ ! -e "${firewallState}" ]]

    resetInstallServiceFixture redirect-fail
    regressionExpectStatus 1 customXrayInstall 21 >/dev/null 2>&1
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^nginx:start:' "${serviceLog}"
    ! grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture no-local-cert
    regressionExpectStatus 0 customXrayInstall 2 >/dev/null 2>&1
    ! grep -q '^clean-nginx$' "${callLog}"
    ! grep -q '^initTLS:' "${callLog}"
    ! grep -q '^installTLS:' "${callLog}"
    ! grep -q '^nginxBlog:' "${callLog}"
    ! grep -q '^cron:' "${callLog}"
    ! grep -q '^nginx:' "${serviceLog}"
    grep -q '^installXray:' "${callLog}"
    [[ -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture xray-start-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'xray:stop:true' "${serviceLog}"
    grep -qx 'xray:start:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'queueStart:nginx' "${callLog}"
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    grep -q '^installXray:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture redirect-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'redirect' "${callLog}"
    ! grep -q '^xray:stop:' "${serviceLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture nginx-stop-fail
    regressionExpectStatus 1 singBoxInstall >/dev/null 2>&1
    grep -qx 'nginx:stop:true' "${serviceLog}"
    ! grep -q '^installSingBox:' "${callLog}"
    [[ ! -e "${reachedFile}" ]]
    [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]

    resetInstallServiceFixture blog-fail
    regressionExpectStatus 1 xrayCoreInstall >/dev/null 2>&1
    grep -qx 'nginxBlog:10' "${callLog}"
    ! grep -q '^redirect$' "${callLog}"

    resetInstallServiceFixture cron-fail
    regressionExpectStatus 1 singBoxInstall >/dev/null 2>&1
    grep -qx 'cron:8' "${callLog}"
    grep -qx 'nginx:stop:true' "${serviceLog}"
    grep -qx 'nginx:start:true' "${serviceLog}" || return 1
    grep -qx 'nginx-mode:start restore' "${serviceLog}" || return 1
    [[ "${nginxRuntimeState}" == "true" ]] || return 1
    ! grep -q '^queueApply$' "${callLog}"

    # 六个入口检查目标核心后才删除旧文件；失败时先释放新核心端口再恢复旧服务。
    local install target oldCore
    for install in installXrayReality customXrayInstall xrayCoreInstall installSingBoxReality customSingBoxInstall singBoxInstall; do
        target=xray
        oldCore=sing-box
        [[ "${install}" != *SingBox* && "${install}" != singBox* ]] || { target=sing-box; oldCore=xray; }
        resetInstallServiceFixture check-gfw-fail
        [[ "${oldCore}" != xray ]] || xrayRuntimeState=true
        [[ "${oldCore}" != sing-box ]] || singBoxRuntimeState=true
        regressionExpectStatus 1 "${install}" 1 domain </dev/null
        grep -q "^health:[0-9]*:${target}$" "${callLog}"
        ! grep -q '^cleanup:' "${callLog}"
        serviceRunning "${oldCore}"
        ! serviceRunning "${target}"
        grep -q "^${oldCore}:start:true$" "${serviceLog}"
        resetInstallServiceFixture check-gfw-fail
        failStopTarget=${target}
        [[ "${oldCore}" != xray ]] || xrayRuntimeState=true
        [[ "${oldCore}" != sing-box ]] || singBoxRuntimeState=true
        regressionExpectStatus 1 "${install}" 1 domain </dev/null
        serviceRunning "${target}"
        ! serviceRunning "${oldCore}"
        ! grep -q "^${oldCore}:start:" "${serviceLog}"
        grep -q '新核心停止失败' "${errorLog}"
        resetInstallServiceFixture success
        [[ "${oldCore}" != xray ]] || xrayRuntimeState=true
        [[ "${oldCore}" != sing-box ]] || singBoxRuntimeState=true
        regressionExpectStatus 0 "${install}" 1 domain </dev/null
        grep -q "^health:[0-9]*:${target}$" "${callLog}"
        grep -qx "${oldCore}:stop:true" "${serviceLog}"
        [[ "$(grep -E '^(health|cleanup):' "${callLog}")" == health:*"${target}"$'\n'cleanup:* ]]
        serviceRunning "${target}"
        ! serviceRunning "${oldCore}"
        resetInstallServiceFixture success
        regressionExpectStatus 0 "${install}" 1 domain </dev/null
        grep -qx "${oldCore}:stop:true" "${serviceLog}"
        serviceRunning "${target}"
    done

    grep -qx 'existing-nginx-main' "${PADM_REALITY_STREAM_NGINX_CONF}"
    (
        # 使用真实备份，保证失败后配置和 Nginx 运行态一起回到安装前。
        local rollbackRoot="${root}/nginx-rollback" core oldCore initialState failure
        local nginxConfigPath="${rollbackRoot}/conf/"
        local PADM_REALITY_STREAM_CONF_FILE="${rollbackRoot}/stream.conf"
        local PADM_REALITY_STREAM_STATE_FILE="${rollbackRoot}/stream.json"
        local PADM_REALITY_STREAM_NGINX_CONF="${rollbackRoot}/nginx.conf"
        local PADM_REALITY_ENTRY_HOST_FILE="${rollbackRoot}/entry-host"
        local file before after keptBackup= stopFailed=false restoreFailed=false
        local realRestoreSource events=
        local -a files=(default.conf alone.conf sing_box_VMess_HTTPUpgrade.conf subscribe.conf checkPortOpen.conf)
        mkdir -p "${nginxConfigPath}" "${rollbackRoot}/xray" "${rollbackRoot}/sing-box"
        xrayTemplateConfigDir() { printf '%s\n' "${rollbackRoot}/xray"; }
        singBoxTemplateConfigDir() { printf '%s\n' "${rollbackRoot}/sing-box"; }
        coreSwitchCleanupBackupCreate() { printf -v "$1" '%s' ''; }
        realRestoreSource=$(declare -f checkLogBackupRestore)
        eval "${realRestoreSource/checkLogBackupRestore/restoreNginxRegressionFiles}"
        checkLogBackupRestore() {
            events+=$'restore\n'
            if [[ "${restoreFailed}" == true ]]; then
                keptBackup=$1
                return 1
            fi
            restoreNginxRegressionFiles "$@"
        }
        padmForgetCleanupPath() {
            [[ ! -d "$1" ]] || keptBackup=$1
            return 0
        }
        handleNginx() {
            events+="nginx:$1"$'\n'
            if [[ "$1" == stop ]]; then
                [[ "${stopFailed}" != true ]] || return 1
                nginxRuntimeState=false
            else
                # 文件未恢复完成时不能启动，尤其不能继续使用新 fallback。
                after=$(find "${rollbackRoot}" -type f -exec sha256sum {} + | LC_ALL=C sort)
                [[ "${after}" == "${before}" ]] || return 1
                nginxRuntimeState=true
            fi
        }
        failingNginxInstall() {
            printf '{"new":true}\n' >"${rollbackRoot}/${core}/00_log.json"
            printf 'new-fallback\n' >"${nginxConfigPath}alone.conf"
            rm -f "${nginxConfigPath}default.conf" "${nginxConfigPath}subscribe.conf" \
                "${PADM_REALITY_STREAM_CONF_FILE}" "${PADM_REALITY_STREAM_STATE_FILE}"
            printf 'new-main-without-stream\n' >"${PADM_REALITY_STREAM_NGINX_CONF}"
            printf 'new-detect\n' >"${nginxConfigPath}checkPortOpen.conf"
            nginxRuntimeState=true
            [[ "${failure}" != pending* ]] || nginxRuntimeState=false
            if [[ "${failure}" == core-stop ]]; then
                xrayRuntimeState=false singBoxRuntimeState=false
                [[ "${core}" != xray ]] || xrayRuntimeState=true
                [[ "${core}" != sing-box ]] || singBoxRuntimeState=true
            fi
            events+=$'install-failed\n'
            return 7
        }
        for core in xray sing-box; do
            selectCustomInstallType=,21,
            oldCore=sing-box
            [[ "${core}" != sing-box ]] || oldCore=xray
            for initialState in true false; do
                for failure in none restore stop core-stop pending pending-stop; do
                    printf '{"old":true}\n' >"${rollbackRoot}/${core}/00_log.json"
                    for file in "${files[@]}"; do
                        printf 'old:%s\n' "${file}" >"${nginxConfigPath}${file}"
                    done
                    printf 'old-stream\n' >"${PADM_REALITY_STREAM_CONF_FILE}"
                    printf '{"old":true}\n' >"${PADM_REALITY_STREAM_STATE_FILE}"
                    printf 'old-main-with-stream\n' >"${PADM_REALITY_STREAM_NGINX_CONF}"
                    before=$(find "${rollbackRoot}" -type f -exec sha256sum {} + | LC_ALL=C sort)
                    nginxRuntimeState=${initialState}
                    xrayRuntimeState=false singBoxRuntimeState=false
                    keptBackup= events= stopFailed=false restoreFailed=false
                    failStopTarget=
                    : >"${serviceLog}"
                    [[ "${failure}" != restore ]] || restoreFailed=true
                    [[ "${failure}" != stop && "${failure}" != pending-stop ]] || stopFailed=true
                    if [[ "${failure}" == core-stop ]]; then
                        failStopTarget=${core}
                        [[ "${oldCore}" != xray ]] || xrayRuntimeState=true
                        [[ "${oldCore}" != sing-box ]] || singBoxRuntimeState=true
                    fi
                    regressionExpectStatus 7 coreSwitchConfigTransaction "${core}" failingNginxInstall
                    if [[ "${failure}" == none || "${failure}" == pending ]]; then
                        after=$(find "${rollbackRoot}" -type f -exec sha256sum {} + | LC_ALL=C sort)
                        [[ "${before}" == "${after}" && "${nginxRuntimeState}" == "${initialState}" &&
                            -z "${keptBackup}" ]]
                        [[ "${events}" == $'install-failed\nnginx:stop\nrestore\n'* ]]
                        [[ "${initialState}" != true ]] || [[ "${events}" == *$'nginx:start\n' ]]
                    else
                        [[ -d "${keptBackup}" && "${events}" != *nginx:start* ]]
                        [[ "${failure}" != restore || "${nginxRuntimeState}" == false ]]
                        [[ "${failure}" != stop || "${nginxRuntimeState}" == true ]]
                        [[ "${failure}" != pending-stop || "${nginxRuntimeState}" == false ]]
                        if [[ "${failure}" == stop || "${failure}" == core-stop || "${failure}" == pending-stop ]]; then
                            [[ "${events}" != *restore* ]]
                            grep -qx '{"new":true}' "${rollbackRoot}/${core}/00_log.json"
                        fi
                        if [[ "${failure}" == core-stop ]]; then
                            serviceRunning "${core}"
                            ! serviceRunning "${oldCore}"
                            ! grep -q ':start:' "${serviceLog}"
                        fi
                        command rm -rf -- "${keptBackup}"
                    fi
                done
            done
        done
    )
    runCoreStartupSwitchRollbackRegression
)

runSingBoxMergeConfigTransactionRegression() (
    local root="${TMP_DIR}/sing-box-merge-config-transaction"
    local confDir="${root}/conf"
    local shardDir="${confDir}/config"
    local binary="${root}/fake-sing-box"
    local outputFile="${confDir}/config.json"
    local checkLog="${root}/check.log"
    local commitMarker="${root}/commit.log"
    local logFile="${root}/merge.log"
    local mergeCalls="${root}/merge-calls.log"
    local rc

    mkdir -p "${shardDir}"
    cat >"${binary}" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "check" ]]; then
    shift
    config=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -c)
            config=$2
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    printf 'check:%s\n' "${config}" >>"${PADM_FAKE_SINGBOX_CHECK_LOG}"
    [[ "${PADM_FAKE_SINGBOX_CHECK_MODE:-success}" == "success" ]]
    exit
fi
[[ "$1" == "merge" ]] || exit 2
printf 'merge\n' >>"${PADM_FAKE_SINGBOX_MERGE_LOG}"
output=$2
shift 2
dest=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    -D)
        dest=$2
        shift 2
        ;;
    -C)
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done
[[ -n "${dest}" ]] || exit 2
case "${PADM_FAKE_SINGBOX_MERGE_MODE:-success}" in
fail)
    exit 1
    ;;
empty)
    : >"${dest%/}/${output}"
    exit 0
    ;;
*)
    printf '{"merged":true}\n' >"${dest%/}/${output}"
    exit 0
    ;;
esac
SH
    chmod +x "${binary}"
    PADM_SINGBOX_BINARY="${binary}"
    singBoxConfigPath="${shardDir}/"
    export PADM_FAKE_SINGBOX_CHECK_LOG="${checkLog}"
    export PADM_FAKE_SINGBOX_MERGE_LOG="${mergeCalls}"

    printf '{"old":true}\n' >"${outputFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=fail
    regressionExpectStatus 1 singBoxMergeConfig >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    : >"${mergeCalls}"
    printf '%s\n' '{"outbounds":[{"type":"direct","domain_resolver":{"server":"padm-local"}}]}' >"${shardDir}/01_missing_resolver.json"
    regressionExpectStatus 1 singBoxMergeConfig >/dev/null 2>&1
    [[ ! -s "${mergeCalls}" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    [[ ! -e "${shardDir}/dns.json" ]]
    rm -f "${shardDir}/01_missing_resolver.json"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=empty
    regressionExpectStatus 1 singBoxMergeConfig >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    mv() {
        local args=("$@")
        if [[ "${args[$((${#args[@]} - 1))]}" == "${outputFile}" ]]; then
            printf 'commit\n' >"${commitMarker}"
            return 1
        fi
        command mv "$@"
    }
    set +e
    (
        singBoxMergeConfig >/dev/null 2>&1
    )
    rc=$?
    set -e
    unset -f mv
    [[ "${rc}" == "1" ]]
    [[ -e "${commitMarker}" ]]
    [[ "$(<"${outputFile}")" == '{"old":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    singBoxMergeConfig
    [[ "$(<"${outputFile}")" == '{"merged":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null

    printf '{"runtime":true}\n' >"${outputFile}"
    : >"${checkLog}"
    : >"${logFile}"
    export PADM_FAKE_SINGBOX_MERGE_MODE=success
    export PADM_FAKE_SINGBOX_CHECK_MODE=success
    singBoxMergeConfigForValidation "${binary}" "${logFile}" check
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null
    : >"${checkLog}"
    export PADM_FAKE_SINGBOX_CHECK_MODE=fail
    regressionExpectStatus 1 singBoxMergeConfigForValidation "${binary}" "${logFile}" check >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    grep -q '^check:' "${checkLog}"
    ! grep -qx "check:${outputFile}" "${checkLog}"
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null
    regressionExpectStatus 1 singBoxMergeConfig check >/dev/null 2>&1
    [[ "$(<"${outputFile}")" == '{"runtime":true}' ]]
    ! compgen -G "${confDir}/.config.json.merge.*" >/dev/null
    export PADM_FAKE_SINGBOX_CHECK_MODE=success
    singBoxV2rayApiSupported() { return 1; }
    local statsConfig="${shardDir}/14_stats_api.json"
    local statsBefore='{"experimental":{"v2ray_api":{}}}'
    printf '%s\n' "${statsBefore}" >"${statsConfig}"
    (
        # 直接服务预检失败时，统计分片和旧合并配置必须一起保持。
        local failure commitReached=false
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/realCommitGeneratedFile/')"
        commitGeneratedFile() {
            if [[ "${failure}" == commit && "$2" == "${outputFile}" ]]; then
                commitReached=true
                return 1
            fi
            realCommitGeneratedFile "$@"
        }
        for failure in merge check commit; do
            export PADM_FAKE_SINGBOX_MERGE_MODE=success PADM_FAKE_SINGBOX_CHECK_MODE=success
            case "${failure}" in
            merge) export PADM_FAKE_SINGBOX_MERGE_MODE=fail ;;
            check) export PADM_FAKE_SINGBOX_CHECK_MODE=fail ;;
            esac
            regressionExpectStatus 1 singBoxMergeConfig check >/dev/null 2>&1
            [[ -f "${statsConfig}" && "$(<"${statsConfig}")" == "${statsBefore}" &&
                "$(<"${outputFile}")" == '{"runtime":true}' ]]
        done
        [[ "${commitReached}" == true ]]
    )
    (
        # 恢复失败时保留独立备份，不让退出清理丢失最后的原分片。
        local keptBackup= cleanupPath
        export PADM_FAKE_SINGBOX_CHECK_MODE=fail
        checkLogBackupRestore() { keptBackup=$1; return 1; }
        errorCard() { return 0; }
        regressionExpectStatus 1 singBoxMergeConfig check
        [[ -d "${keptBackup}" && "$(<"${keptBackup}/000000.json")" == "${statsBefore}" ]]
        for cleanupPath in "${PADM_CLEANUP_PATHS[@]}"; do
            [[ "${cleanupPath}" != "${keptBackup}" ]]
        done
        cp "${keptBackup}/000000.json" "${statsConfig}"
        padmRemoveCleanupPath "${keptBackup}"
    )
    singBoxMergeConfig check
    [[ ! -e "${statsConfig}" ]]
    [[ "$(<"${outputFile}")" == '{"merged":true}' ]]
    (
        # 非普通分片必须在备份与删除前拒绝，不能把链接记作缺失后丢失它。
        local kind
        : >"${mergeCalls}"
        for kind in directory fifo link dangling; do
            case "${kind}" in
            directory) mkdir "${statsConfig}" ;;
            fifo) mkfifo "${statsConfig}" ;;
            link) ln -s "${confDir}" "${statsConfig}" ;;
            dangling) ln -s "${root}/missing-stats" "${statsConfig}" ;;
            esac
            regressionExpectStatus 1 singBoxMergeConfig check
            [[ ! -s "${mergeCalls}" && "$(<"${outputFile}")" == '{"merged":true}' ]]
            if [[ "${kind}" == directory ]]; then
                rmdir "${statsConfig}"
            else
                [[ -e "${statsConfig}" || -L "${statsConfig}" ]]
                rm "${statsConfig}"
            fi
        done
    )
)

runSingBoxUninstallFailurePropagationRegression() (
    local root="${TMP_DIR}/sing-box-uninstall-failure"
    local configDir="${root}/conf/config/"
    local mergedConfig="${root}/conf/config.json"
    local serviceLog="${root}/service.log"
    local firewallLog="${root}/firewall.log"
    local errorLog="${root}/error.log"
    local refreshLog="${root}/refresh.log"
    local startCalls=0
    local rc oldConfig mode refreshStatus=0 denyStatus=0

    mkdir -p "${configDir}"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
    printf '{"inbounds":[{"type":"vless","listen_port":2443}]}\n' >"${configDir}02_other_inbounds.json"
    printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${mergedConfig}"
    oldConfig=$(<"${configDir}09_tuic_inbounds.json")
    : >"${serviceLog}"
    : >"${firewallLog}"
    : >"${errorLog}"
    : >"${refreshLog}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    PADM_SINGBOX_BINARY="${root}/missing-sing-box"
    PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${root}/sing-box.service"

    (
        local mode caseRoot backupDir calls
        readInstallType() { [[ "${mode}" != read-fail ]]; }
        systemctl() { [[ "${mode}" != registration-fail ]]; }
        handleSingBox() { printf '%s\n' "$1" >>"${calls}"; }
        for mode in restore-fail read-fail registration-fail success; do
            caseRoot="${root}/rollback-${mode}"
            calls="${caseRoot}/calls"
            mkdir -p "${caseRoot}"
            : >"${calls}"
            printf 'old\n' >"${caseRoot}/config"
            checkLogBackupCreate backupDir "${caseRoot}/config" || return 1
            printf 'new\n' >"${caseRoot}/config"
            [[ "${mode}" != restore-fail ]] || command rm -- "${backupDir}/000000.json"
            regressionExpectStatus 1 singBoxProtocolUninstallRollback \
                "${backupDir}" true false true test || return 1
            if [[ "${mode}" == success ]]; then
                [[ "$(<"${calls}")" == start && ! -e "${backupDir}" ]] || return 1
            else
                [[ ! -s "${calls}" && -d "${backupDir}" ]] || return 1
                [[ "${mode}" == restore-fail || "$(<"${caseRoot}/config")" == old ]] || return 1
                padmRemoveCleanupPath "${backupDir}" || return 1
            fi
        done
    ) || return 1

    (
        # 合并配置位于分片目录的父目录，最后协议删除后必须清理核心注册。
        source "${PROJECT_ROOT}/shell/core/state.sh"
        local lastRoot="${root}/last-protocol"
        local PADM_XRAY_BINARY="${lastRoot}/missing-xray"
        local PADM_SINGBOX_BINARY="${lastRoot}/sing-box"
        local PADM_SINGBOX_CONFIG_DIR="${lastRoot}/conf/config"
        local PADM_SKIP_CONTROLLER_REFRESH=1 actions=
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
        printf '#!/bin/sh\nexit 0\n' >"${PADM_SINGBOX_BINARY}"
        chmod +x "${PADM_SINGBOX_BINARY}"
        printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' \
            >"${PADM_SINGBOX_CONFIG_DIR}/09_tuic_inbounds.json"
        cp "${PADM_SINGBOX_CONFIG_DIR}/09_tuic_inbounds.json" "${lastRoot}/conf/config.json"
        singBoxRunning() { return 1; }
        coreStartupServiceEnabled() { return 1; }
        readPortHopping() { tuicPortHoppingStart=; tuicPortHoppingEnd=; }
        singBoxMergeConfigForValidation() { return 0; }
        singBoxRemoveServiceRegistration() { actions+=$'registration\n'; }
        cleanCoreInstallDirectory() { actions+=$'cleanup\n'; }
        denyPort() { return 0; }
        refreshProtocolSubscriptions() { return 0; }
        readInstallType
        [[ "${coreInstallType}" == 2 ]]
        unInstallSingBox tuic
        [[ ! -e "${lastRoot}/conf/config.json" ]]
        [[ -z "${coreInstallType}" && -z "${singBoxConfigPath}" ]]
        [[ "${actions}" == $'registration\ncleanup\n' ]]
    )

    (
        # 中断恢复先停止新服务；不可恢复的核心清理中断只保留备份。
        local signalName signalCase signalPhase signalDelivered signalRoot expectedRc resultRc
        local signalShard signalMerged signalUnit signalBinary signalCalls signalErrors signalBackup
        local signalWasRunning signalRelease
        eval "$(declare -f removeManagedFileIfPresent | sed '1s/^removeManagedFileIfPresent/originalUninstallSignalRemove/')"
        eval "$(declare -f checkLogBackupCreate | sed '1s/^checkLogBackupCreate/originalUninstallSignalBackup/')"
        eval "$(declare -f checkLogBackupRestore | sed '1s/^checkLogBackupRestore/originalUninstallSignalRestore/')"
        uninstallSignalAt() {
            if [[ "${signalPhase}" == "$1" && "${signalDelivered}" == false ]]; then
                signalDelivered=true
                kill "-${signalName}" "${BASHPID}"
            fi
            return 0
        }
        checkLogBackupCreate() {
            originalUninstallSignalBackup "$@" || return 1
            printf '%s\n' "${!1}" >"${signalRoot}/backup-path"
        }
        checkLogBackupRestore() {
            printf 'restore\n' >>"${signalCalls}"
            originalUninstallSignalRestore "$@" || return 1
            uninstallSignalAt ordinary
        }
        removeManagedFileIfPresent() {
            originalUninstallSignalRemove "$@" || return 1
            case "$1" in
            "${signalShard}") uninstallSignalAt shard ;;
            "${signalMerged}") uninstallSignalAt merged ;;
            "${signalUnit}") uninstallSignalAt registration ;;
            esac
            return 0
        }
        singBoxMergedConfigFile() { printf '%s\n' "${signalMerged}"; }
        singBoxRunning() { [[ "$(<"${signalRoot}/running")" == true ]]; }
        coreStartupServiceEnabled() { [[ "$(<"${signalRoot}/enabled")" == true ]]; }
        readPortHopping() { tuicPortHoppingStart=; tuicPortHoppingEnd=; }
        readInstallType() {
            singBoxConfigPath=
            if [[ -f "${signalShard}" || -f "${signalRoot}/conf/config/02_other_inbounds.json" ]]; then
                singBoxConfigPath="${signalRoot}/conf/config/"
            fi
            uninstallSignalAt read
        }
        runCoreServiceActionAllowFailure() {
            case "$2" in
            stop)
                printf 'stop\n' >>"${signalCalls}"
                [[ "${signalCase}" != stop-fail || "${signalDelivered}" == false ]] || return 1
                printf false >"${signalRoot}/running"
                uninstallSignalAt stop
                ;;
            start)
                if [[ -f "${signalShard}" ]]; then
                    printf 'start:old\n' >>"${signalCalls}"
                else
                    printf 'start:new\n' >>"${signalCalls}"
                fi
                printf true >"${signalRoot}/running"
                uninstallSignalAt start
                ;;
            esac
            return 0
        }
        singBoxMergeConfigForValidation() {
            printf '{"generation":"new"}\n' >"${signalMerged}"
            uninstallSignalAt validate
            [[ "${signalCase}" != ordinary ]]
        }
        systemctl() {
            printf 'systemctl:%s\n' "$*" >>"${signalCalls}"
            case "$1" in
            disable) printf false >"${signalRoot}/enabled" ;;
            enable) printf true >"${signalRoot}/enabled" ;;
            esac
            return 0
        }
        rc-update() {
            printf 'rc-update:%s\n' "$*" >>"${signalCalls}"
            case "$1" in
            del) printf false >"${signalRoot}/enabled" ;;
            add) printf true >"${signalRoot}/enabled" ;;
            esac
            return 0
        }
        cleanCoreInstallDirectory() {
            rm -f "${signalBinary}" || return 1
            uninstallSignalAt cleanup
        }
        denyPort() { return 0; }
        refreshManagedProtocolSubscriptions() { uninstallSignalAt refresh; }
        errorCard() { printf '%s\n' "$*" >>"${signalErrors}"; }
        statusCard() { return 0; }
        successCard() { return 0; }
        for signalName in INT TERM; do
            expectedRc=130
            [[ "${signalName}" != TERM ]] || expectedRc=143
            for signalCase in stop shard merged read validate start registration cleanup refresh stop-fail stopped alpine ordinary; do
                case "${signalCase}" in
                stop-fail|stopped|alpine|ordinary) [[ "${signalName}" == TERM ]] || continue ;;
                esac
                signalPhase=${signalCase} signalWasRunning=true signalRelease=debian
                case "${signalCase}" in
                stop-fail) signalPhase=start ;;
                stopped) signalPhase=read; signalWasRunning=false ;;
                alpine) signalPhase=registration; signalRelease=alpine ;;
                esac
                signalDelivered=false
                signalRoot="${root}/signal-${signalName}-${signalCase}"
                signalShard="${signalRoot}/conf/config/09_tuic_inbounds.json"
                signalMerged="${signalRoot}/conf/config.json"
                signalUnit="${signalRoot}/sing-box.service"
                signalBinary="${signalRoot}/sing-box"
                signalCalls="${signalRoot}/calls.log" signalErrors="${signalRoot}/errors.log"
                mkdir -p "${signalRoot}/conf/config" "${signalRoot}/tmp" || return 1
                printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${signalShard}"
                printf '{"generation":"old"}\n' >"${signalMerged}"
                printf old-unit >"${signalUnit}"
                printf '#!/bin/sh\nexit 0\n' >"${signalBinary}"
                chmod +x "${signalBinary}" || return 1
                printf '%s' "${signalWasRunning}" >"${signalRoot}/running"
                printf true >"${signalRoot}/enabled"
                : >"${signalCalls}"
                : >"${signalErrors}"
                case "${signalPhase}" in
                registration|cleanup) ;;
                *) printf '{"inbounds":[{"type":"vless","listen_port":2443}]}\n' >"${signalRoot}/conf/config/02_other_inbounds.json" ;;
                esac
                (
                    local release=${signalRelease} PADM_TMP_DIR="${signalRoot}/tmp"
                    local PADM_SINGBOX_BINARY="${signalBinary}"
                    local PADM_SINGBOX_SYSTEMD_SERVICE_FILE="${signalUnit}"
                    local PADM_SINGBOX_OPENRC_SERVICE_FILE="${signalUnit}"
                    local singBoxConfigPath="${signalRoot}/conf/config/" normalStatus
                    if unInstallSingBox tuic; then normalStatus=0; else normalStatus=$?; fi
                    if [[ "${signalCase}" == ordinary ]]; then
                        printf '%s\n' "${normalStatus}" >"${signalRoot}/normal-status"
                        kill "-${signalName}" "${BASHPID}"
                    fi
                    exit "${normalStatus}"
                ) >/dev/null 2>&1 && resultRc=0 || resultRc=$?
                [[ "${resultRc}" == "${expectedRc}" ]] || return 1
                signalBackup=$(<"${signalRoot}/backup-path")
                if [[ "${signalPhase}" == cleanup ]]; then
                    [[ ! -e "${signalShard}" && ! -e "${signalMerged}" && ! -e "${signalUnit}" &&
                        ! -e "${signalBinary}" && -d "${signalBackup}" ]] || return 1
                    [[ "$(<"${signalRoot}/running")" == false && "$(<"${signalRoot}/enabled")" == false ]] || return 1
                    ! grep -Eq '^(restore|start:)' "${signalCalls}" || return 1
                    jq -e '.inbounds[0].type == "tuic"' "${signalBackup}/000000.json" >/dev/null || return 1
                elif [[ "${signalCase}" == stop-fail ]]; then
                    [[ ! -e "${signalShard}" && -d "${signalBackup}" &&
                        "$(<"${signalRoot}/running")" == true ]] || return 1
                    jq -e '.generation == "new"' "${signalMerged}" >/dev/null || return 1
                    ! grep -Eq '^(restore|start:old)$' "${signalCalls}" || return 1
                    grep -q '中断后服务停止失败' "${signalErrors}" || return 1
                    jq -e '.inbounds[0].type == "tuic"' "${signalBackup}/000000.json" >/dev/null || return 1
                elif [[ "${signalPhase}" == refresh ]]; then
                    [[ ! -e "${signalShard}" && ! -e "${signalBackup}" &&
                        "$(<"${signalRoot}/running")" == true ]] || return 1
                    jq -e '.generation == "new"' "${signalMerged}" >/dev/null || return 1
                    [[ "$(<"${signalCalls}")" == $'stop\nstart:new' ]] || return 1
                else
                    jq -e '.inbounds[0].type == "tuic"' "${signalShard}" >/dev/null || return 1
                    jq -e '.generation == "old"' "${signalMerged}" >/dev/null || return 1
                    [[ "$(<"${signalUnit}")" == old-unit && ! -e "${signalBackup}" &&
                        "$(<"${signalRoot}/running")" == "${signalWasRunning}" &&
                        "$(<"${signalRoot}/enabled")" == true ]] || return 1
                    [[ "$(grep -c '^restore$' "${signalCalls}")" == 1 ]] || return 1
                    if [[ "${signalWasRunning}" == true ]]; then
                        grep -qx start:old "${signalCalls}" || return 1
                    else
                        ! grep -q '^start:' "${signalCalls}" || return 1
                    fi
                    if [[ "${signalPhase}" == start ]]; then
                        [[ "$(<"${signalCalls}")" == $'stop\nstart:new\nstop\nrestore\nstart:old' ]] || return 1
                    elif [[ "${signalPhase}" == registration ]]; then
                        if [[ "${signalRelease}" == alpine ]]; then
                            grep -qx 'rc-update:add sing-box default' "${signalCalls}" || return 1
                        else
                            grep -qx 'systemctl:enable sing-box.service' "${signalCalls}" || return 1
                        fi
                    elif [[ "${signalCase}" == ordinary ]]; then
                        [[ "$(<"${signalRoot}/normal-status")" == 1 &&
                            "$(<"${signalCalls}")" == $'stop\nrestore\nstart:old' ]] || return 1
                    fi
                fi
            done
        done
    ) || return 1

    singBoxConfigPath="${configDir}"
    readInstallType() { singBoxConfigPath="${configDir}"; }
    readPortHopping() {
        tuicPortHoppingStart=
        tuicPortHoppingEnd=
    }
    singBoxRunning() { return 0; }
    coreStartupServiceEnabled() { return 1; }
    runCoreServiceActionAllowFailure() {
        printf '%s:%s\n' "$1" "$2" >>"${serviceLog}"
        if [[ "$2" == "start" ]]; then
            startCalls=$((startCalls + 1))
            [[ "${startCalls}" != "1" ]]
        fi
    }
    denyPort() {
        printf 'deny:%s:%s\n' "$1" "${2:-tcp}" >>"${firewallLog}"
        return "${denyStatus}"
    }
    refreshProtocolSubscriptions() { printf 'refresh:%s\n' "$1" >>"${refreshLog}"; return "${refreshStatus}"; }
    subscriptionNotifyControllerRefresh() { printf 'notify\n' >>"${refreshLog}"; }

    (
        # 跳跃规则读取失败时，不能删除配置、停止服务或刷新订阅。
        readPortHopping() { return 1; }
        regressionExpectStatus 1 unInstallSingBox tuic
        [[ "$(<"${configDir}09_tuic_inbounds.json")" == "${oldConfig}" && -f "${mergedConfig}" ]]
        [[ ! -s "${serviceLog}" && ! -s "${firewallLog}" && ! -s "${refreshLog}" ]]
        grep -q '端口跳跃读取失败，已取消卸载' "${errorLog}"
    )
    : >"${errorLog}"

    if unInstallSingBox tuic; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    [[ "$(<"${configDir}09_tuic_inbounds.json")" == "${oldConfig}" ]]
    [[ -f "${mergedConfig}" ]]
    [[ "${startCalls}" == "2" ]]
    [[ ! -s "${firewallLog}" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -q 'sing-box 服务重启失败，已恢复旧配置和服务状态' "${errorLog}"

    singBoxRunning() { return 1; }
    runCoreServiceActionAllowFailure() { return 0; }
    readPortHopping() {
        tuicPortHoppingStart=33000
        tuicPortHoppingEnd=33005
    }
    deletePortHoppingRules() {
        printf 'hopping:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${firewallLog}"
    }
    # 删除已生效时都同步订阅；后续失败不恢复已移除的协议。
    for mode in success firewall refresh; do
        printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
        printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${mergedConfig}"
        : >"${serviceLog}"
        : >"${firewallLog}"
        : >"${errorLog}"
        : >"${refreshLog}"
        denyStatus=0 refreshStatus=0
        [[ "${mode}" != firewall ]] || denyStatus=1
        [[ "${mode}" != refresh ]] || refreshStatus=1
        if [[ "${mode}" == success ]]; then
            unInstallSingBox tuic
        else
            regressionExpectStatus 1 unInstallSingBox tuic
        fi
        [[ ! -e "${configDir}09_tuic_inbounds.json" && ! -e "${mergedConfig}" ]]
        grep -qx 'hopping:tuic:33000:33005:26451' "${firewallLog}"
        grep -qx 'deny:26451:tcp' "${firewallLog}"
        grep -qx 'deny:26451:udp' "${firewallLog}"
        grep -qx 'refresh:sing-box tuic' "${refreshLog}"
        if [[ "${mode}" == refresh ]]; then
            [[ "$(wc -l <"${refreshLog}")" == 1 ]]
            grep -q '已卸载，但订阅刷新失败' "${errorLog}"
        else
            [[ "$(wc -l <"${refreshLog}")" == 2 ]]
            grep -qx notify "${refreshLog}"
        fi
        [[ "${mode}" != firewall ]] || grep -q '已卸载，但防火墙规则回收失败' "${errorLog}"
    done
    denyStatus=0 refreshStatus=0

    (
        # firewalld 停用时运行态为空，协议卸载仍逐条回收永久规则归属。
        local PADM_FIREWALL_STATE_FILE="${root}/inactive-firewalld.state"
        printf '%s\n' 'forward:firewalld:udp:33000:33005:26451:owned=33000,33001,33002,33003,33004,33005' \
            'forward:firewalld:udp:34000:34002:26451:owned=34000,34001,34002' \
            >"${PADM_FIREWALL_STATE_FILE}"
        printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${configDir}09_tuic_inbounds.json"
        printf '{"inbounds":[{"type":"tuic","listen_port":26451}]}\n' >"${mergedConfig}"
        : >"${firewallLog}"
        readPortHopping() { tuicPortHoppingStart=; tuicPortHoppingEnd=; }
        deletePortHoppingRules() {
            local key
            key=$(padmFirewalldForwardStateKeyForTarget "$4") || return 1
            printf 'hopping:%s:%s:%s:%s\n' "$1" "$2" "$3" "$4" >>"${firewallLog}"
            padmFirewallStateRemove "${key}"
        }
        unInstallSingBox tuic
        [[ "$(grep -cx 'hopping:tuic:::26451' "${firewallLog}")" == 2 ]]
        [[ ! -e "${configDir}09_tuic_inbounds.json" ]]
        [[ ! -e "${PADM_FIREWALL_STATE_FILE}" ]]
    )

    (
        # Hy2 卸载只移除自己的受管 UDP 别名，Xray 失败仍保留已卸载状态。
        local aliasRoot="${root}/hy2-aliases" coreInstallType=1
        local configPath="${aliasRoot}/xray/" singBoxConfigPath="${aliasRoot}/sing-box/"
        local udpFile="${configPath}02_dokodemodoor_inbounds_hysteria_2053.json"
        local secondFile="${configPath}02_dokodemodoor_inbounds_hysteria_2083.json"
        local tcpFile="${configPath}02_dokodemodoor_inbounds_2053_default.json"
        local otherFile="${configPath}02_dokodemodoor_inbounds_hysteria_2087.json"
        local ignoredFile="${configPath}02_dokodemodoor_inbounds_hysteria_2096.json"
        local multiFile="${configPath}02_dokodemodoor_inbounds_hysteria_2097.json"
        local badFile="${configPath}02_dokodemodoor_inbounds_hysteria_2099.json"
        local udpBefore secondBefore tcpBefore otherBefore ignoredBefore multiBefore reloadCalls mode
        mkdir -p "${configPath}" "${singBoxConfigPath}" || return 1
        writeCoreDokodemoInbound "${tcpFile}" 2053 443 tcp dokodemo-door-newPort-2053 || return 1
        writeCoreDokodemoInbound "${otherFile}" 2087 17295 udp dokodemo-door-newPort-hysteria-2087 || return 1
        writeCoreDokodemoInbound "${ignoredFile}" 2096 16295 udp unmanaged || return 1
        jq -n '{inbounds:[{port:2097,protocol:"dokodemo-door",tag:"dokodemo-door-newPort-hysteria-2097",
            settings:{port:16295,network:"udp",address:"127.0.0.1"}},{port:31337,protocol:"socks"}]}' >"${multiFile}" || return 1
        tcpBefore=$(<"${tcpFile}") otherBefore=$(<"${otherFile}") ignoredBefore=$(<"${ignoredFile}")
        multiBefore=$(<"${multiFile}")
        readInstallType() { coreInstallType=1; }
        readPortHopping() { hysteria2PortHoppingStart=; hysteria2PortHoppingEnd=; }
        reloadXrayProtocolCore() {
            reloadCalls=$((reloadCalls + 1))
            [[ "${mode}" != reload || "${reloadCalls}" != 1 ]]
        }
        for mode in success reload noalias; do
            printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${singBoxConfigPath}06_hysteria2_inbounds.json"
            printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${aliasRoot}/config.json"
            singBoxMergedConfigFile() { printf '%s/config.json\n' "${aliasRoot}"; }
            rm -f "${udpFile}" "${secondFile}"
            if [[ "${mode}" != noalias ]]; then
                writeCoreDokodemoInbound "${udpFile}" 2053 16295 udp dokodemo-door-newPort-hysteria-2053 || return 1
                writeCoreDokodemoInbound "${secondFile}" 2083 16295 udp dokodemo-door-newPort-hysteria-2083 || return 1
                udpBefore=$(<"${udpFile}") secondBefore=$(<"${secondFile}")
            fi
            : >"${firewallLog}"
            : >"${refreshLog}"
            : >"${errorLog}"
            reloadCalls=0
            if [[ "${mode}" == reload ]]; then
                regressionExpectStatus 1 unInstallSingBox hysteria2 || return 1
                [[ "$(<"${udpFile}")" == "${udpBefore}" && "$(<"${secondFile}")" == "${secondBefore}" &&
                    "${reloadCalls}" == 2 ]] || return 1
                grep -q 'Hysteria2 已卸载，但 UDP 入口清理失败' "${errorLog}" || return 1
                ! grep -Eq '^deny:(2053|2083):' "${firewallLog}" || return 1
            else
                unInstallSingBox hysteria2 || return 1
                [[ ! -e "${udpFile}" && ! -e "${secondFile}" ]] || return 1
                if [[ "${mode}" == success ]]; then
                    [[ "${reloadCalls}" == 1 ]] || return 1
                    grep -qx 'deny:2053:udp' "${firewallLog}" || return 1
                    grep -qx 'deny:2083:udp' "${firewallLog}" || return 1
                else
                    [[ "${reloadCalls}" == 0 ]] || return 1
                    ! grep -Eq '^deny:(2053|2083):' "${firewallLog}" || return 1
                fi
            fi
            [[ ! -e "${singBoxConfigPath}06_hysteria2_inbounds.json" && ! -e "${aliasRoot}/config.json" &&
                "$(<"${tcpFile}")" == "${tcpBefore}" && "$(<"${otherFile}")" == "${otherBefore}" &&
                "$(<"${ignoredFile}")" == "${ignoredBefore}" && "$(<"${multiFile}")" == "${multiBefore}" ]] || return 1
            ! grep -Eq '^deny:(2053|2083):tcp$|^deny:(2087|2096):' "${firewallLog}" || return 1
            grep -qx 'deny:16295:tcp' "${firewallLog}" || return 1
            grep -qx 'deny:16295:udp' "${firewallLog}" || return 1
            [[ "$(<"${refreshLog}")" == $'refresh:sing-box hysteria2\nnotify' ]] || return 1
        done
        # 后面的多根 JSON 候选失败时，前面已识别的别名也不能提前被改动。
        writeCoreDokodemoInbound "${udpFile}" 2053 16295 udp dokodemo-door-newPort-hysteria-2053 || return 1
        udpBefore=$(<"${udpFile}")
        printf '{}\n{}\n' >"${badFile}"
        : >"${firewallLog}"
        reloadCalls=0
        regressionExpectStatus 1 corePortSyncHysteriaAliases 16295 || return 1
        [[ "$(<"${udpFile}")" == "${udpBefore}" && "$(<"${badFile}")" == $'{}\n{}' &&
            "${reloadCalls}" == 0 && ! -s "${firewallLog}" ]] || return 1
    ) || return 1

    local alpineConfigDir="${root}/alpine/conf/config/"
    local alpineMergedConfig="${root}/alpine/conf/config.json"
    local openRcService="${root}/alpine/sing-box"
    local rcUpdateLog="${root}/alpine/rc-update.log"
    local cleanupMode keptBackup=
    mkdir -p "${alpineConfigDir}"
    PADM_SINGBOX_OPENRC_SERVICE_FILE="${openRcService}"
    release=alpine
    readInstallType() { singBoxConfigPath=; }
    readPortHopping() {
        hysteria2PortHoppingStart=
        hysteria2PortHoppingEnd=
    }
    coreStartupServiceEnabled() { return 0; }
    rc-update() {
        printf '%s\n' "$*" >>"${rcUpdateLog}"
    }
    cleanCoreInstallDirectory() { [[ "${cleanupMode}" == success ]]; }
    padmForgetCleanupPath() { keptBackup=$1; }
    for cleanupMode in success failure; do
        printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineConfigDir}06_hysteria2_inbounds.json"
        printf '{"inbounds":[{"type":"hysteria2","listen_port":16295}]}\n' >"${alpineMergedConfig}"
        printf '#!/sbin/openrc-run\n' >"${openRcService}"
        : >"${rcUpdateLog}"
        : >"${firewallLog}"
        : >"${refreshLog}"
        : >"${errorLog}"
        singBoxConfigPath="${alpineConfigDir}"
        if [[ "${cleanupMode}" == success ]]; then
            unInstallSingBox hysteria2
        else
            regressionExpectStatus 1 unInstallSingBox hysteria2
            [[ -d "${keptBackup}" && -f "${keptBackup}/000000.json" ]]
            grep -q 'sing-box 核心清理失败' "${errorLog}"
        fi
        grep -qx 'del sing-box default' "${rcUpdateLog}"
        [[ ! -e "${openRcService}" && ! -e "${alpineConfigDir}06_hysteria2_inbounds.json" && ! -e "${alpineMergedConfig}" ]]
        grep -qx 'deny:16295:tcp' "${firewallLog}"
        grep -qx 'deny:16295:udp' "${firewallLog}"
        [[ "$(<"${refreshLog}")" == $'refresh:sing-box hysteria2\nnotify' ]]
    done

    singBoxConfigPath=
    release=debian
    : >"${serviceLog}"
    : >"${errorLog}"
    : >"${refreshLog}"
    handleSingBox() {
        printf 'handle:%s\n' "$1" >>"${serviceLog}"
        return 1
    }
    runCoreServiceActionAllowFailure() { "$@"; }

    if unInstallSingBox >/dev/null 2>&1; then
        rc=0
    else
        rc=$?
    fi
    [[ "${rc}" == "1" ]]
    [[ ! -s "${refreshLog}" ]]
    grep -qx 'handle:stop' "${serviceLog}"
    grep -q 'sing-box 服务停止失败，已取消卸载' "${errorLog}"
)

runSingBoxLogTransactionRegression() (
    local root="${TMP_DIR}/sing-box-log-transaction"
    local targetPath="${root}/conf/config/log.json"
    local serviceLog="${root}/service.log"
    local errorLog="${root}/error.log"
    local applyMode rc keptBackup

    set +e
    mkdir -p "$(dirname "${targetPath}")" || return 1
    export PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}"
    export PADM_SINGBOX_CONFIG_DIR="${root}/conf/config"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${serviceLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply:%s\n' "${applyMode}" >>"${serviceLog}"
        [[ "${applyMode}" == "fail" ]] && return 1
        return 0
    }
    errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
    runSingBoxLogCase() {
        local disabled=$1
        local expectedRc=$2
        local rcFile="${root}/sing-box-log.rc"
        PADM_REGRESSION_APPLY_MODE="${applyMode}" \
            PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
            bash -c '
                set +e
                source "$1/shell/core/runtime.sh"
                source "$1/shell/core/services.sh"
                source "$1/shell/core/singbox.sh"
                source "$1/shell/core/cores.sh"
                serviceLog=$2
                errorLog=$3
                disabled=$4
                rcFile=$5
                singBoxRunning() { return 0; }
                serviceQueueRestart() {
                    printf "restart:%s\n" "$1" >>"${serviceLog}"
                    return 0
                }
                serviceQueueApply() {
                    printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                    [[ "${PADM_REGRESSION_APPLY_MODE}" == "fail" ]] && return 1
                    return 0
                }
                errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
                singBoxLog "${disabled}" >/dev/null 2>&1
                printf "%s\n" "$?" >"${rcFile}"
            ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${disabled}" "${rcFile}" || return 1
        rc=$(<"${rcFile}") || return 1
        if [[ "${rc}" != "${expectedRc}" ]]; then
            printf 'singBoxLog rc mismatch: expected=%s actual=%s\n' "${expectedRc}" "${rc}" >&2
            return 1
        fi
        return 0
    }

    (
        # 生成失败时旧配置未变，不应创建备份或请求服务动作。
        local original='{"log":{"disabled":true,"level":"warning"}}'
        printf '%s\n' "${original}" >"${targetPath}" || return 1
        : >"${serviceLog}" || return 1
        singBoxRunning() { return 0; }
        jq() {
            [[ "${1:-}" != -n ]] || return 1
            command jq "$@"
        }
        regressionExpectStatus 1 singBoxLog false >/dev/null 2>&1 || return 1
        [[ "$(<"${targetPath}")" == "${original}" && ! -s "${serviceLog}" ]] || return 1
        ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    ) || return 1

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    rm -f "${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    runSingBoxLogCase false 1 || return 1
    [[ ! -e "${targetPath}" ]] || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q 'sing-box 日志配置重载失败' "${errorLog}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}" || return 1
    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=fail
    PADM_REGRESSION_APPLY_MODE="${applyMode}" \
        PADM_SINGBOX_LOG_CONFIG_FILE="${targetPath}" \
        bash -c '
            set +e
            source "$1/shell/core/runtime.sh"
            source "$1/shell/core/services.sh"
            source "$1/shell/core/singbox.sh"
            source "$1/shell/core/cores.sh"
            serviceLog=$2
            errorLog=$3
            rcFile=$4
            singBoxRunning() { return 0; }
            serviceQueueRestart() {
                printf "restart:%s\n" "$1" >>"${serviceLog}"
                return 0
            }
            serviceQueueApply() {
                printf "apply:%s\n" "${PADM_REGRESSION_APPLY_MODE}" >>"${serviceLog}"
                return 1
            }
            errorCard() { printf "%s\n" "$*" >>"${errorLog}"; }
            restoreManagedFileFromBackup() { return 1; }
            date() { printf "1700000000\n"; }
            singBoxLog false >/dev/null 2>&1
            printf "%s\n" "$?" >"${rcFile}"
            # 同秒重试成功也不能覆盖或清除上一次恢复失败后保留的备份。
            shopt -s nullglob
            backups=("${PADM_SINGBOX_LOG_CONFIG_FILE%/*}/.log.json.bak."*)
            [[ "${#backups[@]}" == 1 ]] || exit 1
            keptBackup=${backups[0]}
            printf "%s\n" "${keptBackup}" >"${rcFile}.backup"
            serviceQueueApply() { return 0; }
            singBoxLog false >/dev/null 2>&1 || exit 1
            [[ -f "${keptBackup}" ]] || exit 1
            jq -e ".log.disabled == true and .log.level == \"warning\"" "${keptBackup}" >/dev/null || exit 1
        ' _ "${PROJECT_ROOT}" "${serviceLog}" "${errorLog}" "${root}/sing-box-log-restore-fail.rc" || return 1
    rc=$(<"${root}/sing-box-log-restore-fail.rc") || return 1
    [[ "${rc}" == "1" ]] || return 1
    jq -e --arg output "${root}/conf/box.log" '.log.disabled == false and .log.level == "debug" and .log.output == $output' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:fail' "${serviceLog}" || return 1
    grep -q '旧配置恢复失败' "${errorLog}" || return 1
    keptBackup=$(<"${root}/sing-box-log-restore-fail.rc.backup") || return 1
    [[ -n "${keptBackup}" && -f "${keptBackup}" ]] || return 1
    jq -e '.log.disabled == true and .log.level == "warning"' "${keptBackup}" >/dev/null || return 1
    rm -f "${keptBackup}" || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1

    : >"${serviceLog}" || return 1
    : >"${errorLog}" || return 1
    applyMode=success
    runSingBoxLogCase false 0 || return 1
    jq -e --arg output "${root}/conf/box.log" '.log.disabled == false and .log.level == "debug" and .log.output == $output' "${targetPath}" >/dev/null || return 1
    grep -qx 'restart:sing-box' "${serviceLog}" || return 1
    grep -qx 'apply:success' "${serviceLog}" || return 1
    [[ ! -s "${errorLog}" ]] || return 1
    ! compgen -G "$(dirname "${targetPath}")/.log.json.*" >/dev/null || return 1
    (
        # 使用真实分派器验证运行态恢复，不以队列成功代替服务成功。
        local running=true starts=0
        source "${PROJECT_ROOT}/shell/core/services.sh"
        singBoxRunning() { [[ "${running}" == true ]]; }
        singBoxMergeConfig() { return 0; }
        handleSingBox() {
            printf '%s\n' "$1" >>"${serviceLog}"
            if [[ "$1" == stop ]]; then
                running=false
            else
                starts=$((starts + 1))
                [[ "${starts}" -ne 1 ]] || return 1
                running=true
            fi
            return 0
        }
        : >"${serviceLog}"
        printf '{"log":{"disabled":true,"level":"warning"}}\n' >"${targetPath}"
        regressionExpectStatus 1 singBoxLog false >/dev/null 2>&1 || return 1
        [[ "${running}" == true && "${starts}" == 2 ]] || return 1
        jq -e '.log.disabled == true and .log.level == "warning"' "${targetPath}" >/dev/null || return 1
        [[ "$(<"${serviceLog}")" == $'stop\nstart\nstop\nstart' ]] || return 1
        running=false
        : >"${serviceLog}"
        singBoxLog false >/dev/null 2>&1 || return 1
        [[ "${running}" == false && ! -s "${serviceLog}" ]] || return 1
        regressionExpectStatus 1 singBoxLog invalid >/dev/null 2>&1 || return 1
    ) || return 1
    return 0
)

runSingBoxProtocolReloadFailureRegression() (
    local root="${TMP_DIR}/sing-box-protocol-reload-failure"
    local reachedFile="${root}/accounts"
    local callLog="${root}/calls.log"
    local anyTlsLog="${root}/anytls.log"
    local tuicRc hysteriaRc install collectionSource portSource networkSource tuicSource
    local PADM_SINGBOX_CONFIG_DIR="${root}/config"

    collectionSource=$(declare -f coreTemplateCollectInitialClients)
    portSource=$(declare -f readSingBoxPortResult)
    networkSource=$(declare -f initHysteria2Network)
    tuicSource=$(declare -f initTuicProtocol)
    mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
    : >"${callLog}"
    : >"${anyTlsLog}"
    coreTemplateCollectInitialClients() { return 0; }
    # 原场景只验证事务与服务；输入前置另用真实 helper 覆盖。
    readSingBoxPortResult() { local -n ports=$1; ports=(18443); }
    initHysteria2Network() { return 0; }
    initTuicProtocol() { return 0; }
    readPortHopping() {
        hysteria2PortHoppingStart= hysteria2PortHoppingEnd=
        tuicPortHoppingStart= tuicPortHoppingEnd=
    }

    (
        local dependencyRoot="${root}/reality-tls"
        local certificateLog="${dependencyRoot}/certificate.log"
        local transactionLog="${dependencyRoot}/transaction.log"
        local xrayLog="${dependencyRoot}/xray.log"
        local certificateAvailable=false confirmValue=y rc
        local AUTO_DOMAIN=install.example.com
        local domain=parent.example.com tlsEnabled=false tlsCertDomain=parent.example.com
        local tlsSNI=parent-sni tlsCertFile=parent.crt tlsKeyFile=parent.key

        mkdir -p "${dependencyRoot}"
        : >"${certificateLog}"
        : >"${transactionLog}"
        : >"${xrayLog}"
        coreInstallType=1
        selectCoreType=1
        currentInstallProtocolType=',1,'
        protocolSelectionNeedsCertificate() { return 1; }
        singBoxLocalCertificateAvailable() { [[ "${certificateAvailable}" == "true" ]]; }
        autoConfirm() { printf -v "$4" '%s' "${confirmValue}"; }
        installAcmeTool() { printf 'acme\n' >>"${certificateLog}"; }
        nginxRunning() { return 0; }
        xrayRunning() { return 0; }
        singBoxRunning() { return 1; }
        initTLSNginxConfig() {
            [[ -z "${selectCoreType}" ]] || return 1
            printf 'init\n' >>"${certificateLog}"
        }
        installTLS() {
            printf 'tls\n' >>"${certificateLog}"
            certificateAvailable=true
            collectTLSProfile
        }
        installCronTLS() { printf 'cron\n' >>"${certificateLog}"; }
        restoreServicesAfterTLSRenewal() { printf 'restore:%s\n' "$*" >>"${certificateLog}"; }
        customXrayInstall() { printf '%s\n' "$*" >>"${xrayLog}"; return 1; }
        coreInstallConfigTransaction() { printf 'transaction:%s\n' "$1" >>"${transactionLog}"; }

        certificateAvailable=true
        singBoxHysteria2Install >/dev/null 2>&1
        grep -qx 'transaction:sing-box' "${transactionLog}"
        [[ ! -s "${certificateLog}" && ! -s "${xrayLog}" ]]
        [[ "${currentInstallProtocolType}" == ',1,' ]]

        : >"${certificateLog}"
        : >"${transactionLog}"
        certificateAvailable=false
        confirmValue=y
        singBoxHysteria2Install >/dev/null 2>&1
        grep -qx 'transaction:sing-box' "${transactionLog}"
        [[ "$(tr '\n' ',' <"${certificateLog}")" == 'acme,init,tls,cron,restore:true true false,' ]]
        [[ ! -s "${xrayLog}" ]]
        [[ "${selectCoreType}" == "1" && "${currentInstallProtocolType}" == ',1,' ]]
        [[ "${domain}" == parent.example.com && "${tlsEnabled}" == false && "${tlsCertDomain}" == parent.example.com &&
            "${tlsSNI}" == parent-sni && "${tlsCertFile}" == parent.crt && "${tlsKeyFile}" == parent.key ]]

        # 域名输入后依赖安装失败也不能改写父菜单的 TLS 状态。
        : >"${certificateLog}"
        : >"${transactionLog}"
        certificateAvailable=false
        installAcmeTool() { return 1; }
        regressionExpectStatus 1 singBoxHysteria2Install >/dev/null 2>&1
        [[ "${domain}" == parent.example.com && "${tlsCertDomain}" == parent.example.com &&
            ! -s "${transactionLog}" ]]

        : >"${certificateLog}"
        : >"${transactionLog}"
        certificateAvailable=false
        confirmValue=n
        regressionExpectStatus 1 singBoxHysteria2Install >/dev/null 2>&1
        [[ ! -s "${certificateLog}" && ! -s "${transactionLog}" && ! -s "${xrayLog}" ]]
        [[ "${currentInstallProtocolType}" == ',1,' ]]
    )

    currentInstallProtocolType=',4,'
    installSingBox() {
        printf 'install:%s\n' "$*" >>"${anyTlsLog}"
        return 1
    }
    set +e
    (singBoxProtocolInstallApply TUIC >/dev/null 2>&1)
    tuicRc=$?
    (singBoxProtocolInstallApply Hysteria2 >/dev/null 2>&1)
    hysteriaRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    [[ "${hysteriaRc}" == "1" ]]
    [[ "$(wc -l <"${anyTlsLog}" | tr -d ' ')" == "2" ]]

    currentInstallProtocolType=
    protocolSelectionNeedsCertificate() { return 1; }
    set +e
    (singBoxTuicInstall >/dev/null 2>&1)
    tuicRc=$?
    (singBoxHysteria2Install >/dev/null 2>&1)
    hysteriaRc=$?
    set -e
    [[ "${tuicRc}" == "1" ]]
    [[ "${hysteriaRc}" == "1" ]]

    protocolSelectionNeedsCertificate() { return 0; }
    coreInstallConfigTransaction() {
        local core=$1
        local operation=$2
        shift 2
        printf 'transaction:%s\n' "${core}" >>"${callLog}"
        "${operation}" "$@"
    }
    installSingBox() {
        printf 'install:%s\n' "$*" >>"${callLog}"
        return 0
    }
    initSingBoxConfig() {
        printf 'config:%s\n' "$*" >>"${callLog}"
        return 0
    }
    installSingBoxService() {
        printf 'service:%s\n' "$*" >>"${callLog}"
        return 0
    }
    reloadCore() {
        printf 'reload\n' >>"${callLog}"
        return 99
    }
    serviceQueueRestart() {
        printf 'restart:%s\n' "$1" >>"${callLog}"
        return 0
    }
    serviceQueueApply() {
        printf 'apply\n' >>"${callLog}"
        return 1
    }
    showAccounts() {
        printf 'accounts\n' >"${reachedFile}"
        return 0
    }

    regressionExpectStatus 1 singBoxTuicInstall >/dev/null 2>&1
    grep -qx 'transaction:sing-box' "${callLog}"
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'restart:sing-box' "${callLog}"
    grep -qx 'apply' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -qx 'restart:xray' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    : >"${callLog}"
    rm -f "${reachedFile}"
    regressionExpectStatus 1 singBoxHysteria2Install >/dev/null 2>&1
    grep -qx 'transaction:sing-box' "${callLog}"
    grep -qx 'config:custom 2 true' "${callLog}"
    grep -qx 'restart:sing-box' "${callLog}"
    grep -qx 'apply' "${callLog}"
    ! grep -qx 'reload' "${callLog}"
    ! grep -qx 'restart:xray' "${callLog}"
    [[ ! -e "${reachedFile}" ]]

    : >"${callLog}"
    rm -f "${reachedFile}"
    serviceQueueApply() {
        printf 'apply\n' >>"${callLog}"
        return 0
    }
    subscriptionNotifyControllerRefresh() {
        printf 'notify\n' >>"${callLog}"
        return 0
    }
    singBoxProtocolInstallApply TUIC >/dev/null 2>&1
    singBoxProtocolInstallApply Hysteria2 >/dev/null 2>&1
    [[ "$(grep -c '^notify$' "${callLog}")" == "2" ]]

    # 账号输出失败必须让安装事务失败，不能通知控制器刷新。
    showAccounts() { printf 'accounts\n' >"${reachedFile}"; return 7; }
    for install in singBoxTuicInstall singBoxHysteria2Install; do
        : >"${callLog}"
        regressionExpectStatus 1 "${install}" >/dev/null 2>&1
        [[ -f "${reachedFile}" ]]
        ! grep -qx 'notify' "${callLog}"
    done

    (
        # 使用真实账号采集和转换，覆盖提前确认、独立账号重装及局部状态隔离。
        eval "${collectionSource}"
        local PADM_SINGBOX_CONFIG_DIR="${root}/accounts-config"
        local mainUuid=11111111-1111-4111-8111-111111111111
        local newUuid=22222222-2222-4222-8222-222222222222
        local currentUUID="${mainUuid}" currentClients lastInstallationConfig=parent-history
        local selectCustomInstallType=,1, singBoxHysteria2CredentialMode=parent-mode
        local PADM_INSTALL_CLIENTS_PREPARED=parent-value
        local events= capturedUsers= inputFd nextInput protocolId credential configFile sourceClients input invalid
        currentClients="[{\"id\":\"${mainUuid}\",\"email\":\"main\"}]"
        sourceClients=${currentClients}
        unset AUTO_INSTALL AUTO_UUID AUTO_USER AUTO_REUSE_LAST
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
        singBoxEnsureTLSDependency() { events+=$'tls\n'; }
        coreInstallConfigTransaction() { events+=$'transaction\n'; shift; "$@"; }
        installSingBox() { events+=$'download\n'; }
        initSingBoxConfig() {
            [[ "${PADM_INSTALL_CLIENTS_PREPARED}" == true ]] || return 1
            [[ -n "${currentClients:-}" ]] ||
                coreTemplateCollectInitialClients sing-box "${singBoxHysteria2CredentialMode}" || return 1
            capturedUsers=$(initSingBoxClients "${selectCustomInstallType//,/}") || return 1
        }
        installSingBoxService() { return 0; }
        serviceQueueRestart() { [[ "$1" == sing-box ]]; }
        serviceQueueApply() { return 0; }
        showAccounts() { events+=$'accounts\n'; }
        subscriptionNotifyControllerRefresh() { events+=$'notify\n'; }

        for install in singBoxHysteria2Install singBoxTuicInstall; do
            protocolId=3 credential=independent-password
            [[ "${install}" != singBoxTuicInstall ]] || { protocolId=31; credential=${newUuid}; }
            configFile=$(singBoxTemplateConfigFile "$(protocolCapabilityMeta "${protocolId}" config_file)")

            # 拒绝复用后在密码或用户名处 EOF，不申请证书、不下载、不进入事务。
            for input in n $'n\nindependent-password\n'; do
                events=
                regressionExpectStatus 1 "${install}" < <(printf '%s' "${input}") >/dev/null 2>&1
                [[ -z "${events}" && "${currentClients}" == "${sourceClients}" ]]
            done
            events=
            exec {inputFd}< <(printf 'n\n%s\nindependent\nnext-parent-action\n' "${credential}")
            "${install}" <&"${inputFd}" >/dev/null 2>&1
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action &&
                "${events}" == $'tls\ntransaction\ntls\ndownload\naccounts\nnotify\n' ]]
            [[ "${currentClients}" == "${sourceClients}" && "${currentUUID}" == "${mainUuid}" &&
                "${selectCustomInstallType}" == ,1, && "${lastInstallationConfig}" == parent-history &&
                "${singBoxHysteria2CredentialMode}" == parent-mode &&
                "${PADM_INSTALL_CLIENTS_PREPARED}" == parent-value && -z "${AUTO_UUID:-}${AUTO_USER:-}" ]]
            exec {inputFd}<&-
            jq -e --arg credential "${credential}" --arg suffix "$(protocolCapabilityMeta "${protocolId}" protocol)" '
                length == 1 and .[0].password == $credential and .[0].name == ("independent-singbox_" + $suffix)
            ' <<<"${capturedUsers}" >/dev/null
            # TUIC 的密码可以独立于 UUID，重装不得将它替换成 UUID。
            [[ "${protocolId}" != 31 ]] || capturedUsers=$(jq '.[0].password = "tuic-independent-password"' <<<"${capturedUsers}")
            jq -n --argjson users "${capturedUsers}" '{inbounds:[{listen_port:18443,users:$users}]}' >"${configFile}"
            events=
            exec {inputFd}< <(printf '\nnext-parent-action\n')
            "${install}" <&"${inputFd}" >/dev/null 2>&1
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && "${currentClients}" == "${sourceClients}" ]]
            if [[ "${protocolId}" == 3 ]]; then
                jq -e '.[0].password == "independent-password"' <<<"${capturedUsers}" >/dev/null
            else
                jq -e --arg uuid "${newUuid}" '.[0].uuid == $uuid and .[0].password == "tuic-independent-password"' <<<"${capturedUsers}" >/dev/null
            fi
            exec {inputFd}<&-

            # 空或损坏的目标用户不能回退主核心用户并覆盖原文件。
            for invalid in null '[]' '[{}]' '[{"name":"broken","password":""}]' '[{"name":"broken","password":7}]'; do
                jq -n --argjson users "${invalid}" '{inbounds:[{users:$users}]}' >"${configFile}"
                events=
                AUTO_INSTALL=true regressionExpectStatus 1 "${install}" </dev/null >/dev/null 2>&1
                [[ -z "${events}" && "${currentClients}" == "${sourceClients}" ]]
                jq -e --argjson users "${invalid}" '.inbounds[0].users == $users' "${configFile}" >/dev/null
            done
            rm -f "${configFile}"
        done
    )

    (
        # 真实采集和模板：取消无副作用，磁盘默认值与失败重试不受会话缓存影响。
        eval "${collectionSource}"
        eval "${portSource}"
        eval "${networkSource}"
        eval "${tuicSource}"
        local PADM_SINGBOX_CONFIG_DIR="${root}/preflight-config"
        local capturedConfig="${root}/preflight.json" configFile protocolId input inputFd remaining
        local uuid=11111111-1111-4111-8111-111111111111 coreVersion=1.10.0
        local tlsCalls=0 transactions=0 downloads=0 allows=0 applyMode=success
        local singBoxHysteria2Port=19997 singBoxTuicPort=19996
        local singBoxConfigPath=parent-path/ hysteriaPort=19999 tuicPort=19998 tuicAlgorithm=cubic
        local tuicAuthTimeout=stale tuicHeartbeat=stale tuicZeroRttHandshake=false
        local hysteria2BandwidthMode=brutal hysteria2ClientDownloadSpeed=999 hysteria2ClientUploadSpeed=888
        local hysteria2ObfsType=gecko hysteria2ObfsPassword=stale hysteria2Masquerade=https://stale.example.com
        local lastInstallationConfig=parent-history AUTO_PORT=
        local -a result=()
        unset AUTO_INSTALL AUTO_UUID AUTO_USER AUTO_REUSE_LAST
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}"
        singBoxEnsureTLSDependency() {
            [[ "${2:-}" != true || -z "${lastInstallationConfig}" ]] || return 1
            tlsCalls=$((tlsCalls + 1))
        }
        coreInstallConfigTransaction() { transactions=$((transactions + 1)); shift; "$@"; }
        installSingBox() { downloads=$((downloads + 1)); coreVersion=1.14.0; }
        getSingBoxCurrentVersion() { printf '%s\n' "${coreVersion}"; }
        allowPort() { allows=$((allows + 1)); [[ "$1" == "${AUTO_PORT}" && "${2:-tcp}" == udp ]]; }
        collectTLSProfile() { tlsCertDomain=installed.example.com; }
        writeGeneratedJsonFile() { cat >"${capturedConfig}"; }
        setSniffRouting() { return 0; }
        initSingBoxConfig() { initSingBoxConfigApply "$@"; }
        installSingBoxService() { return 0; }
        serviceQueueRestart() { [[ "$1" == sing-box ]]; }
        serviceQueueApply() { [[ "${applyMode}" == success ]]; }
        showAccounts() { return 0; }
        subscriptionNotifyControllerRefresh() { return 0; }

        for protocolId in 3 31; do
            configFile=$(singBoxTemplateConfigFile "$(protocolCapabilityMeta "${protocolId}" config_file)")
            jq -n --arg uuid "${uuid}" --arg id "${protocolId}" '{
                inbounds:[{listen_port:18443, users:[{password:"disk-password",name:"disk-user"} +
                    (if $id == "31" then {uuid:$uuid} else {} end)],
                    up_mbps:72,down_mbps:38,obfs:{type:"salamander",password:"disk-obfs"},
                    masquerade:"https://disk.example.com",congestion_control:"bbr",
                    auth_timeout:"4s",heartbeat:"12s",zero_rtt_handshake:true}]
            }' >"${configFile}"

            for input in '' $'n\n\n24444' $'n\n\n24444\n2'; do
                regressionExpectStatus 1 singBoxProtocolInstall "${protocolId}" < <(printf '%s' "${input}") >/dev/null 2>&1
                [[ "${tlsCalls}${transactions}${downloads}${allows}" == 0000 ]]
            done
            if [[ "${protocolId}" == 3 ]]; then
                regressionExpectStatus 1 singBoxProtocolInstall 3 < <(printf 'n\n\n24444\n2\ngecko\nnew-obfs\n') >/dev/null 2>&1
                [[ "${tlsCalls}${transactions}${downloads}${allows}" == 0000 ]]
            fi
            [[ "${hysteria2BandwidthMode}" == brutal && "${hysteria2ClientDownloadSpeed}" == 999 &&
                "${hysteria2ObfsPassword}" == stale && "${tuicAlgorithm}" == cubic && -z "${AUTO_PORT}" ]]

            # 版本检查发生在升级后；应用阶段使用已采集输入，不能再读取下一层菜单。
            input=$'n\n\n24444\n3\n'
            [[ "${protocolId}" != 3 ]] || input=$'n\n\n24444\n2\ngecko\nnew-obfs\nhttps://new.example.com\n'
            coreVersion=1.10.0
            applyMode=failure
            regressionExpectStatus 1 singBoxProtocolInstall "${protocolId}" < <(printf '%s' "${input}") >/dev/null 2>&1
            [[ "${tlsCalls}${transactions}${downloads}${allows}" == 2111 ]]
            jq -e '.inbounds[0].listen_port == 24444' "${capturedConfig}" >/dev/null
            [[ "${hysteria2BandwidthMode}" == brutal && "${hysteria2ClientDownloadSpeed}" == 999 &&
                "${tuicAlgorithm}" == cubic && "${tuicAuthTimeout}" == stale && -z "${AUTO_PORT}" &&
                "${singBoxConfigPath}" == parent-path/ && "${lastInstallationConfig}" == parent-history ]]

            # 一次回车复用磁盘的全部用户、端口和参数，不沿用失败操作或读取下一层菜单。
            input=$'\n'
            applyMode=success
            exec {inputFd}< <(printf '%snext-parent-action\n' "${input}")
            singBoxProtocolInstall "${protocolId}" <&"${inputFd}" >/dev/null 2>&1
            read -r -u "${inputFd}" remaining
            exec {inputFd}<&-
            [[ "${remaining}" == next-parent-action && "${tlsCalls}${transactions}${downloads}${allows}" == 4222 ]]
            jq -e '.inbounds[0].listen_port == 18443 and .inbounds[0].users[0].password == "disk-password"' "${capturedConfig}" >/dev/null
            if [[ "${protocolId}" == 3 ]]; then
                jq -e '.inbounds[0] | .up_mbps == 72 and .down_mbps == 38 and
                    .obfs == {type:"salamander",password:"disk-obfs"} and .masquerade == "https://disk.example.com"' "${capturedConfig}" >/dev/null
            else
                jq -e '.inbounds[0] | .congestion_control == "bbr" and .auth_timeout == "4s" and
                    .heartbeat == "12s" and .zero_rtt_handshake == true' "${capturedConfig}" >/dev/null
            fi
            tlsCalls=0 transactions=0 downloads=0 allows=0
            (
                # 自动重装默认全部保留；显式 no 重填本协议，不继承旧用户和高级设置。
                local AUTO_INSTALL=true AUTO_REUSE_LAST= AUTO_UUID= AUTO_USER= AUTO_PORT=
                singBoxProtocolInstall "${protocolId}" </dev/null >/dev/null 2>&1
                jq -e '.inbounds[0].listen_port == 18443 and .inbounds[0].users[0].password == "disk-password"' "${capturedConfig}" >/dev/null
                AUTO_REUSE_LAST=invalid
                regressionExpectStatus 1 singBoxProtocolInstall "${protocolId}" </dev/null >/dev/null 2>&1
                [[ "${tlsCalls}${transactions}${downloads}${allows}" == 2111 ]]
                AUTO_REUSE_LAST=no AUTO_UUID=${uuid} AUTO_USER=new-user AUTO_PORT=25444
                singBoxProtocolInstall "${protocolId}" </dev/null >/dev/null 2>&1
                jq -e --arg uuid "${uuid}" '.inbounds[0] | .listen_port == 25444 and
                    (.users | length == 1) and .users[0].password == $uuid and
                    (.users[0].name | startswith("new-user-"))' "${capturedConfig}" >/dev/null
                if [[ "${protocolId}" == 3 ]]; then
                    jq -e '.inbounds[0] | .up_mbps == 100 and .down_mbps == 50 and
                        (has("obfs") | not) and .masquerade.status_code == 404' "${capturedConfig}" >/dev/null
                else
                    jq -e '.inbounds[0] | .congestion_control == "cubic" and .auth_timeout == "3s" and
                        .heartbeat == "10s" and .zero_rtt_handshake == false' "${capturedConfig}" >/dev/null
                fi
                [[ "${tlsCalls}${transactions}${downloads}${allows}" == 4222 &&
                    "${lastInstallationConfig}" == parent-history && "${tuicAuthTimeout}" == stale &&
                    "${hysteria2ObfsPassword}" == stale && "${AUTO_PORT}" == 25444 ]]
            )
            rm -f "${configFile}"
        done

        # 非法自动端口在证书和下载之前失败；合法自动端口不消耗交互输入。
        AUTO_INSTALL=true AUTO_PORT=invalid AUTO_UUID=${uuid} AUTO_USER=auto-user
        currentClients= currentUUID=
        regressionExpectStatus 1 singBoxProtocolInstall 31 </dev/null >/dev/null 2>&1
        [[ "${tlsCalls}${transactions}${downloads}${allows}" == 0000 ]]
        AUTO_PORT=24444
        menuReadChoice() { printf -v "$3" '%s' 2; }
        singBoxProtocolInstall 31 </dev/null >/dev/null 2>&1
        [[ "${tlsCalls}${transactions}${downloads}${allows}" == 2111 && "${AUTO_PORT}" == 24444 ]]
    )

    (
        # 更换监听端口前拒绝遗留跳跃范围；同端口、无范围和首次安装不受影响。
        local PADM_SINGBOX_CONFIG_DIR="${root}/reinstall-hopping"
        local AUTO_INSTALL=true AUTO_REUSE_LAST=no AUTO_UUID=11111111-1111-4111-8111-111111111111 AUTO_USER=hopping-user AUTO_PORT=
        local protocolId configFile configBefore hoppingMode readCalls tlsCalls transactions networkCalls errorMessage
        local readType readTarget
        local selectCustomInstallType singBoxHysteria2Port= singBoxTuicPort=
        local -A PADM_INSTALL_SINGBOX_PORTS=()
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}" || return 1
        coreTemplateCollectInitialClients() { return 0; }
        readSingBoxPortResult() { local -n fixturePorts=$1; fixturePorts=("${AUTO_PORT}"); }
        initHysteria2Network() { networkCalls=$((networkCalls + 1)); }
        initTuicProtocol() { networkCalls=$((networkCalls + 1)); }
        singBoxEnsureTLSDependency() { tlsCalls=$((tlsCalls + 1)); }
        coreInstallConfigTransaction() { transactions=$((transactions + 1)); }
        corePortSyncHysteriaAliases() { return 0; }
        errorCard() { errorMessage=$*; }
        readPortHopping() {
            readCalls=$((readCalls + 1))
            readType=$1 readTarget=$2
            [[ "${hoppingMode}" != readfail ]] || return 1
            if [[ "${hoppingMode}" == range ]]; then
                case "$1" in
                hysteria2) hysteria2PortHoppingStart=20000; hysteria2PortHoppingEnd=20100 ;;
                tuic) tuicPortHoppingStart=20000; tuicPortHoppingEnd=20100 ;;
                esac
            fi
        }
        for protocolId in 3 31; do
            configFile=$(singBoxTemplateConfigFile "$(protocolCapabilityMeta "${protocolId}" config_file)") || return 1
            jq -n --arg uuid "${AUTO_UUID}" --arg id "${protocolId}" '{
                inbounds:[{listen_port:18443,users:[{name:"disk-user",password:"disk-password"} +
                    (if $id == "31" then {uuid:$uuid} else {} end)]}]
            }' >"${configFile}" || return 1
            configBefore=$(<"${configFile}")
            for hoppingMode in range readfail empty sameport; do
                readCalls=0 tlsCalls=0 transactions=0 networkCalls=0 errorMessage= readType= readTarget=
                AUTO_PORT=24444
                [[ "${hoppingMode}" != sameport ]] || AUTO_PORT=18443
                if [[ "${hoppingMode}" == range || "${hoppingMode}" == readfail ]]; then
                    regressionExpectStatus 1 singBoxProtocolInstall "${protocolId}" </dev/null || return 1
                    [[ "${readCalls}${tlsCalls}${transactions}${networkCalls}" == 1000 &&
                        "$(<"${configFile}")" == "${configBefore}" ]] || return 1
                    if [[ "${hoppingMode}" == range ]]; then
                        [[ "${errorMessage}" == *请先到端口跳跃管理删除* ]] || return 1
                    else
                        [[ "${errorMessage}" == *旧端口跳跃规则读取失败* ]] || return 1
                    fi
                    readCalls=0 errorMessage=
                    selectCustomInstallType=",${protocolId},"
                    regressionExpectStatus 1 prepareSingBoxInstallInputs </dev/null || return 1
                    [[ "${readCalls}${networkCalls}" == 10 &&
                        "$(<"${configFile}")" == "${configBefore}" &&
                        -z "${PADM_INSTALL_SINGBOX_PORTS[${protocolId}]:-}" ]] || return 1
                else
                    singBoxProtocolInstall "${protocolId}" </dev/null || return 1
                    [[ "${tlsCalls}${transactions}${networkCalls}" == 111 && -z "${errorMessage}" ]] || return 1
                    if [[ "${hoppingMode}" == sameport ]]; then
                        [[ "${readCalls}" == 0 ]] || return 1
                    else
                        [[ "${readCalls}" == 1 ]] || return 1
                    fi
                fi
                if [[ "${readCalls}" == 1 ]]; then
                    [[ "${readTarget}" == 18443 ]] || return 1
                    [[ "${protocolId}:${readType}" == 3:hysteria2 || "${protocolId}:${readType}" == 31:tuic ]] || return 1
                fi
            done
            rm -f "${configFile}"
            hoppingMode=readfail AUTO_PORT=24444 readCalls=0 tlsCalls=0 transactions=0 networkCalls=0
            singBoxProtocolInstall "${protocolId}" </dev/null || return 1
            [[ "${readCalls}${tlsCalls}${transactions}${networkCalls}" == 0111 ]] || return 1
        done
    ) || return 1

    (
        # 重装完成后才迁移 UDP 别名，迁移失败不撤销已生效的新 Hy2 入站。
        local aliasRoot="${root}/hy2-aliases" coreInstallType=1
        local PADM_SINGBOX_CONFIG_DIR="${aliasRoot}/sing-box" configPath="${aliasRoot}/xray/"
        local AUTO_INSTALL=true AUTO_REUSE_LAST=no AUTO_UUID=11111111-1111-4111-8111-111111111111 AUTO_USER=alias-user AUTO_PORT=
        local udpFile="${configPath}02_dokodemodoor_inbounds_hysteria_2053.json"
        local secondFile="${configPath}02_dokodemodoor_inbounds_hysteria_2083.json"
        local tcpFile="${configPath}02_dokodemodoor_inbounds_2053_default.json"
        local otherFile="${configPath}02_dokodemodoor_inbounds_hysteria_2087.json"
        local ignoredFile="${configPath}02_dokodemodoor_inbounds_hysteria_2096.json"
        local errorLog="${aliasRoot}/errors" denyLog="${aliasRoot}/deny"
        local udpBefore secondBefore tcpBefore otherBefore ignoredBefore reloadCalls transactions mode
        mkdir -p "${PADM_SINGBOX_CONFIG_DIR}" "${configPath}" || return 1
        writeCoreDokodemoInbound "${tcpFile}" 2053 443 tcp dokodemo-door-newPort-2053 || return 1
        writeCoreDokodemoInbound "${otherFile}" 2087 17295 udp dokodemo-door-newPort-hysteria-2087 || return 1
        writeCoreDokodemoInbound "${ignoredFile}" 2096 16295 udp unmanaged || return 1
        tcpBefore=$(<"${tcpFile}") otherBefore=$(<"${otherFile}") ignoredBefore=$(<"${ignoredFile}")
        coreTemplateCollectInitialClients() { return 0; }
        readSingBoxPortResult() { local -n ports=$1; ports=("${AUTO_PORT}"); }
        singBoxEnsureTLSDependency() { return 0; }
        initHysteria2Network() { return 0; }
        coreInstallConfigTransaction() {
            transactions=$((transactions + 1))
            printf '{"inbounds":[{"type":"hysteria2","listen_port":%s,"users":[{"name":"disk-user","password":"disk-password"}]}]}\n' \
                "${AUTO_PORT}" >"${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json"
        }
        errorCard() { printf '%s\n' "$*" >>"${errorLog}"; }
        denyPort() { printf '%s\n' "$*" >>"${denyLog}"; }
        reloadXrayProtocolCore() {
            reloadCalls=$((reloadCalls + 1))
            [[ "${mode}" != reload || "${reloadCalls}" != 1 ]]
        }
        for mode in success reload noalias sameport; do
            printf '{"inbounds":[{"type":"hysteria2","listen_port":16295,"users":[{"name":"disk-user","password":"disk-password"}]}]}\n' \
                >"${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json"
            rm -f "${udpFile}" "${secondFile}"
            if [[ "${mode}" != noalias ]]; then
                writeCoreDokodemoInbound "${udpFile}" 2053 16295 udp dokodemo-door-newPort-hysteria-2053 || return 1
                writeCoreDokodemoInbound "${secondFile}" 2083 16295 udp dokodemo-door-newPort-hysteria-2083 || return 1
                udpBefore=$(<"${udpFile}") secondBefore=$(<"${secondFile}")
            fi
            : >"${errorLog}"
            : >"${denyLog}"
            reloadCalls=0 transactions=0 AUTO_PORT=24444
            [[ "${mode}" != sameport ]] || AUTO_PORT=16295
            if [[ "${mode}" == reload ]]; then
                regressionExpectStatus 1 singBoxHysteria2Install </dev/null || return 1
                [[ "$(<"${udpFile}")" == "${udpBefore}" && "$(<"${secondFile}")" == "${secondBefore}" &&
                    "${reloadCalls}" == 2 ]] || return 1
                grep -q 'Hysteria2 已安装，但 UDP 入口同步失败' "${errorLog}" || return 1
            else
                singBoxHysteria2Install </dev/null || return 1
                if [[ "${mode}" == success ]]; then
                    [[ "${reloadCalls}" == 1 ]] || return 1
                    jq -e '.inbounds[0].port == 2053 and .inbounds[0].settings.port == 24444' "${udpFile}" >/dev/null || return 1
                    jq -e '.inbounds[0].settings.port == 24444' "${secondFile}" >/dev/null || return 1
                else
                    [[ "${reloadCalls}" == 0 ]] || return 1
                    if [[ "${mode}" == sameport ]]; then
                        [[ "$(<"${udpFile}")" == "${udpBefore}" && "$(<"${secondFile}")" == "${secondBefore}" ]] || return 1
                    else
                        [[ ! -e "${udpFile}" && ! -e "${secondFile}" ]] || return 1
                    fi
                fi
            fi
            jq -e --argjson port "${AUTO_PORT}" '.inbounds[0].listen_port == $port' \
                "${PADM_SINGBOX_CONFIG_DIR}/06_hysteria2_inbounds.json" >/dev/null || return 1
            [[ "${transactions}" == 1 && ! -s "${denyLog}" &&
                "$(<"${tcpFile}")" == "${tcpBefore}" && "$(<"${otherFile}")" == "${otherBefore}" &&
                "$(<"${ignoredFile}")" == "${ignoredBefore}" ]] || return 1
        done
    ) || return 1

    (
        local transactionRoot="${root}/transaction"
        local configBackup="${transactionRoot}/config-backup"
        local serviceBackup="${transactionRoot}/service-backup"
        local transactionLog="${transactionRoot}/transaction.log"
        local transactionRc
        mkdir -p "${transactionRoot}"
        # Reload the original transaction after the caller-order mock above.
        source "${PROJECT_ROOT}/shell/core/core_templates.sh"
        coreTemplateConfigBackupCreate() {
            printf -v "$1" '%s' "${configBackup}"
            return 0
        }
        checkLogBackupRestore() {
            printf 'config-restore\n' >>"${transactionLog}"
            return 0
        }
        padmRemoveCleanupPath() {
            printf 'cleanup:%s\n' "$1" >>"${transactionLog}"
            return 0
        }
        padmForgetCleanupPath() {
            printf 'forget:%s\n' "$1" >>"${transactionLog}"
            return 0
        }
        xrayRunning() { return 1; }
        singBoxRunning() { return 1; }
        restoreCoreStartupServiceInstall() {
            printf 'service-restore:%s:%s\n' "$2" "$3" >>"${transactionLog}"
            return 0
        }
        failingInstall() {
            coreInstallServiceBackupFinalize "${serviceBackup}" sing-box false
            return 7
        }
        regressionExpectStatus 7 coreInstallConfigTransaction sing-box failingInstall >/dev/null 2>&1
        grep -qx 'config-restore' "${transactionLog}"
        grep -qx 'service-restore:sing-box:false' "${transactionLog}"
    )
)

runGeoUpdateReloadFailureRegression() (
    local root="${TMP_DIR}/geo-update-reload-failure"
    local callLog="${root}/calls.log"
    local statusLog="${root}/status.log"
    local geoVersionFile="${root}/geo-version.txt"
    local geoCronLog="${root}/geo-cron.log"
    local handlerSource
    local mode=reload-fail
    local rc

    mkdir -p "${root}"
    (
        # 非普通 Geo 目标在读取备份前拒绝；普通文件与缺失目标保持原合同。
        local fifoPath="${root}/geo-fifo" regularPath="${root}/geo-regular"
        local backupPath="${root}/geo-backup"
        mkfifo "${fifoPath}" || return 1
        regressionExpectStatus 1 padmWriteManagedFileBackupManifest "${backupPath}" geo "${fifoPath}" || return 1
        [[ -p "${fifoPath}" && ! -e "${backupPath}/geo" ]] || return 1
        padmWriteManagedFileBackupManifest "${backupPath}" geo "${root}/missing-geo" || return 1
        [[ ! -e "${backupPath}/geo" ]] || return 1
        printf 'old-geo\n' >"${regularPath}" || return 1
        padmWriteManagedFileBackupManifest "${backupPath}" geo "${regularPath}" || return 1
        [[ "$(<"${backupPath}/geo")" == old-geo ]] || return 1
    ) || return 1
    (
        # Geo 版本沿用核心发布解析；请求失败或坏响应不开始暂存和下载。
        local target="${root}/lookup-target" latestGeoMetadata geoFetchStatus=0
        mkdir -p "${target}"
        printf 'old-geosite\n' >"${target}/geosite.dat"
        printf 'old-geoip\n' >"${target}/geoip.dat"
        fetchUrlToStdout() {
            [[ "${geoFetchStatus}" == 0 ]] || return 1
            [[ "$1" == */releases/latest ]] && printf '%s\n' "${latestGeoMetadata}" || printf '[]\n'
        }
        eval "$(declare -f padmCreateTempPath | sed '1s/padmCreateTempPath/originalGeoCreateTempPath/')"
        padmCreateTempPath() {
            [[ "$2" == -d ]] || { originalGeoCreateTempPath "$@"; return; }
            printf -v "$1" '%s' "${root}/lookup-stage"
            mkdir -p "${root}/lookup-stage"
        }
        downloadXrayGeoFilesToStage() { [[ "$2" == geo-version ]] || return 1; printf 'download\n' >>"${callLog}"; }
        commitXrayGeoFilesFromStage() { [[ "$3" == geo-version ]] || return 1; printf 'commit\n' >>"${callLog}"; }
        latestGeoMetadata='{"tag_name":"geo-version"}'
        : >"${callLog}"
        ensureXrayGeoFiles "${target}" force || return 1
        [[ "$(<"${callLog}")" == $'download\ncommit' ]] || return 1
        for latestGeoMetadata in '{}' '{"tag_name":null}' $'{"tag_name":"v1"}\n{"tag_name":"v2"}'; do
            : >"${callLog}"
            regressionExpectStatus 1 ensureXrayGeoFiles "${target}" force || return 1
            [[ ! -e "${root}/lookup-stage" && ! -s "${callLog}" ]] || return 1
        done
        geoFetchStatus=1
        regressionExpectStatus 1 ensureXrayGeoFiles "${target}" force || return 1
        [[ "$(<"${target}/geosite.dat")" == old-geosite && "$(<"${target}/geoip.dat")" == old-geoip && ! -s "${callLog}" ]] || return 1
    ) || return 1
    (
        # 任一 Geo 文件提交失败都恢复整组旧数据，成功时一次替换整组。
        local stage="${root}/stage" target="${root}/target"
        local failAt commitCalls file
        mkdir -p "${stage}" "${target}"
        printf 'new-geosite\n' >"${stage}/geosite.dat"
        printf 'new-geoip\n' >"${stage}/geoip.dat"
        eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalGeoCommitGeneratedFile/')"
        commitGeneratedFile() {
            commitCalls=$((commitCalls + 1))
            [[ "${commitCalls}" != "${failAt}" ]] || return 1
            originalGeoCommitGeneratedFile "$@"
        }
        for failAt in 1 2 3 0; do
            commitCalls=0
            for file in geosite.dat geoip.dat geo.version; do
                printf 'old-%s\n' "${file}" >"${target}/${file}"
            done
            if [[ "${failAt}" != 0 ]]; then
                regressionExpectStatus 1 commitXrayGeoFilesFromStage "${stage}" "${target}" new-version || return 1
                for file in geosite.dat geoip.dat geo.version; do
                    [[ "$(<"${target}/${file}")" == "old-${file}" ]] || return 1
                done
            else
                commitXrayGeoFilesFromStage "${stage}" "${target}" new-version || return 1
                [[ "$(<"${target}/geosite.dat")" == new-geosite && "$(<"${target}/geoip.dat")" == new-geoip ]] || return 1
                [[ "$(<"${target}/geo.version")" == new-version ]] || return 1
            fi
            [[ "$(find "${target}" -type f | wc -l)" == 3 ]] || return 1
        done
    ) || return 1
    (
        local file mode target backup
        for file in geosite.dat geoip.dat geo.version; do
            for mode in missing directory; do
                target="${root}/lost-${file}-${mode}"
                backup="${target}/backup"
                mkdir -p "${target}"
                printf 'old\n' >"${target}/${file}"
                padmWriteManagedFileBackupManifest "${backup}" "${file}" "${target}/${file}" || return 1
                command rm -f -- "${backup}/${file}"
                [[ "${mode}" != directory ]] || mkdir "${backup}/${file}"
                printf 'new\n' >"${target}/${file}"
                local -A PADM_XRAY_GEO_COMMIT=([active]=true [backup]="${backup}")
                # 必需备份丢失不能删除当前数据，恢复失败也不能清理备份目录。
                regressionExpectStatus 1 rollbackXrayGeoCommitOnExit || return 1
                [[ "$(<"${target}/${file}")" == new && -d "${backup}" ]] || return 1
            done
        done
        target="${root}/originally-missing"
        backup="${target}/backup"
        padmWriteManagedFileBackupManifest "${backup}" geosite.dat "${target}/geosite.dat" || return 1
        printf 'new\n' >"${target}/geosite.dat"
        PADM_XRAY_GEO_COMMIT=([active]=true [backup]="${backup}")
        rollbackXrayGeoCommitOnExit || return 1
        [[ ! -e "${target}/geosite.dat" && ! -e "${backup}" ]]
    ) || return 1
    : >"${callLog}"
    : >"${statusLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    ensureXrayGeoFiles() {
        printf 'geo:%s\n' "$*" >>"${callLog}"
        [[ "${mode}" == ensure-fail* ]] && return 1
        printf 'new-version\n' >"${geoVersionFile}"
        return 0
    }
    xrayGeoDisplayVersion() {
        cat "${geoVersionFile}"
    }
    reloadCore() {
        return 99
    }
    coreXrayInstallDir() { printf '%s\n' "${root}"; }
    xrayRunning() { [[ "${mode}" != stopped ]]; }
    runServiceAction() {
        [[ "$*" == 'xray restart' ]] || return 99
        printf 'reload\n' >>"${callLog}"
        [[ "${mode}" == reload-success || "${mode}" == ensure-fail-reload-success ]]
    }
    statusCard() {
        printf '%s\n' "$*" >>"${statusLog}"
    }

    mode=ensure-fail
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    grep -qx "geo:${root} force" "${callLog}"
    ! grep -q '^reload$' "${callLog}"

    # 下载失败仍重试已落盘数据的 pending 恢复，失败保留标记，成功不伪报更新成功。
    printf '' >"${root}/geo.reload.pending"
    mode=ensure-fail-reload-fail
    : >"${callLog}"
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1 || return 1
    [[ "$(<"${callLog}")" == $'geo:'"${root}"$' force\nreload' &&
        "$(<"${geoVersionFile}")" == old-version && -f "${root}/geo.reload.pending" ]] || return 1
    mode=ensure-fail-reload-success
    : >"${callLog}"
    : >"${statusLog}"
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1 || return 1
    [[ "$(<"${callLog}")" == $'geo:'"${root}"$' force\nreload' &&
        "$(<"${geoVersionFile}")" == old-version && ! -e "${root}/geo.reload.pending" ]] || return 1
    grep -q '已恢复上次更新后的 Xray 服务' "${statusLog}" || return 1
    ! grep -q '更新完毕' "${statusLog}" || return 1
    : >"${statusLog}"

    mode=reload-fail
    : >"${callLog}"
    printf 'old-version\n' >"${geoVersionFile}"
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    grep -qx "geo:${root} force" "${callLog}"
    grep -qx 'reload' "${callLog}"
    grep -q 'Xray 重载失败' "${statusLog}"
    ! grep -q '更新完毕' "${statusLog}"
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    [[ "$(grep -c '^reload$' "${callLog}")" == 2 && -f "${root}/geo.reload.pending" ]]
    mode=stopped
    regressionExpectStatus 1 updateGeoSite >/dev/null 2>&1
    [[ "$(grep -c '^reload$' "${callLog}")" == 3 && -f "${root}/geo.reload.pending" ]]
    mode=reload-success
    updateGeoSite >/dev/null 2>&1
    [[ "$(grep -c '^reload$' "${callLog}")" == 4 && ! -e "${root}/geo.reload.pending" ]]
    mode=stopped
    : >"${callLog}"
    : >"${statusLog}"
    updateGeoSite >/dev/null 2>&1
    ! grep -q '^reload$' "${callLog}"
    grep -q 'Xray 当前未运行，启动后生效' "${statusLog}"

    (
        local coreInstallType=1 cronMode reads="${root}/cron-reads" writes="${root}/cron-writes"
        readUserCrontabContent() {
            printf 'read\n' >>"${reads}"
            [[ "${cronMode}" != read-fail ]] || return 1
            [[ "${cronMode}" != exists ]] || printf '35 1 * * * bash /etc/padm/install.sh UpdateGeo\n'
            return 0
        }
        installUserCrontabContent() {
            printf '%s\n' "$1" >>"${writes}"
            [[ "${cronMode}" != write-fail ]]
        }
        for cronMode in exists read-fail write-fail success; do
            : >"${reads}"
            : >"${writes}"
            local expected=1
            [[ "${cronMode}" != exists && "${cronMode}" != success ]] || expected=0
            regressionExpectStatus "${expected}" installCronUpdateGeo >/dev/null 2>&1 || return 1
            [[ "$(wc -l <"${reads}")" == 1 ]] || return 1
            if [[ "${cronMode}" == exists || "${cronMode}" == read-fail ]]; then
                [[ ! -s "${writes}" ]] || return 1
            else
                grep -q 'UpdateGeo' "${writes}" || return 1
            fi
        done
    ) || return 1

    handlerSource=$(awk '/^handleScriptCommand\(\)/,/^}/ { print }' "${PROJECT_ROOT}/install.sh")
    handlerSource=${handlerSource//\/etc\/padm\/crontab_updateGeoSite.log/${geoCronLog}}
    eval "${handlerSource}"
    updateGeoSite() {
        printf 'geo-failed\n'
        return 23
    }
    cronName=UpdateGeo
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "23" ]]
    ! grep -q 'geo更新日期:' "${geoCronLog}"

    updateGeoSite() {
        printf 'geo-updated\n'
        return 0
    }
    : >"${geoCronLog}"
    set +e
    (handleScriptCommand)
    rc=$?
    set -e
    [[ "${rc}" == "0" ]]
    grep -q '^geo-updated$' "${geoCronLog}"
    grep -q '^geo更新日期:' "${geoCronLog}"
)

runRealityRegenerateTransactionRegression() (
    local root="${TMP_DIR}/reality-regenerate-transaction" profileFile aliasFile invalidState
    local failure backupCalls=0 reloadCalls=0 subscribeCalls=0 restoredCore= regenerateBackupPath=
    local templateCalls=0 configPath="${root}/" originalProfile validationSource
    validationSource=$(declare -f validateRealityTargetConfigAfterChange)
    local PADM_REALITY_STREAM_STATE_FILE="${root}/stream-state.json" PADM_REALITY_STREAM_CONF_FILE="${root}/stream.conf"
    local currentInstallProtocolType=,1, selectCustomInstallType=,20, coreInstallType
    mkdir -p "${root}"
    profileFile="${root}/07_VLESS_vision_reality_inbounds.json"
    aliasFile="${root}/02_dokodemodoor_inbounds_2053_default.json"
    coreTemplateConfigBackupCreate() {
        backupCalls=$((backupCalls + 1))
        checkLogBackupCreate "$1" "${profileFile}" "${aliasFile}"
        regenerateBackupPath=${!1}
    }
    xrayRunning() { return 0; }
    singBoxRunning() { return 0; }
    coreTemplateRestoreServiceState() { restoredCore="$*"; }
    xrayTemplateConfigDir() { printf '%s\n' "${root}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${root}"; }
    initRealityProfile() { realityTargetHost=target.example.com; realityTargetPort=443; realitySNI=sni.example.com; }
    initRealityKey() {
        [[ -z "${realityPrivateKey}" && -z "${realityPublicKey}" ]] || return 1
        templateCalls=$((templateCalls + 1))
        realityPrivateKey=new-private
        realityPublicKey=new-public
    }
    initRealityMldsa65() { realityMldsa65Seed=new-seed; realityMldsa65Verify=new-verify; }
    validateRealityTargetConfigAfterChange() { [[ "${failure}" != validate ]]; }
    reloadCore() { reloadCalls=$((reloadCalls + 1)); [[ "${failure}" != reload ]]; }
    subscribe() { subscribeCalls=$((subscribeCalls + 1)); [[ "${failure}" != subscribe ]]; }
    for coreInstallType in 1 2; do
        for failure in validate reload subscribe success; do
            printf '%s\n' '{"inbounds":[{"port":2443,"tls":{"reality":{"private_key":"old-private"}}},{"streamSettings":{"realitySettings":{"privateKey":"old-private"}}}],"routing":{"marker":"keep"}}' >"${profileFile}"
            originalProfile=$(<"${profileFile}")
            backupCalls=0 reloadCalls=0 subscribeCalls=0 restoredCore= regenerateBackupPath=
            if [[ "${failure}" == success ]]; then
                regenerateRealityProfile
            else
                regressionExpectStatus 1 regenerateRealityProfile
            fi
            [[ "${backupCalls}" == 1 && -n "${regenerateBackupPath}" && ! -e "${regenerateBackupPath}" ]]
            [[ "${reloadCalls}" == "$([[ "${failure}" == validate ]] && echo 0 || echo 1)" ]]
            [[ "${selectCustomInstallType}" == ,20, ]]
            if [[ "${failure}" == reload || "${failure}" == validate ]]; then
                [[ "$(<"${profileFile}")" == "${originalProfile}" ]]
                [[ "${subscribeCalls}" == 0 ]]
                if [[ "${coreInstallType}" == 1 ]]; then
                    [[ "${restoredCore}" == "xray true true" ]]
                else
                    [[ "${restoredCore}" == "sing-box true true" ]]
                fi
            else
                if [[ "${coreInstallType}" == 1 ]]; then
                    jq -e '.inbounds[1].streamSettings.realitySettings.privateKey == "new-private"' "${profileFile}" >/dev/null
                else
                    jq -e '.inbounds[0].tls.reality.private_key == "new-private"' "${profileFile}" >/dev/null
                fi
                jq -e '.routing.marker == "keep" and .inbounds[0].port == 2443' "${profileFile}" >/dev/null
                [[ "${subscribeCalls}" == 1 && -z "${restoredCore}" ]]
            fi
        done
    done
    # 再生身份保留分流监听、客户和传输参数；只有共用旧公钥的下行同步身份。
    coreInstallType=1
    currentInstallProtocolType=,2,
    failure=success
    rm "${profileFile}"
    profileFile="${root}/12_VLESS_XHTTP_inbounds.json"
    mkdir -p "${root}/auxiliary"
    printf '{"inbounds":[{"tls":{"reality":{"private_key":"auxiliary"}}}]}\n' >"${root}/auxiliary/07_VLESS_vision_reality_inbounds.json"
    local singBoxConfigPath="${root}/auxiliary/" auxiliaryBefore
    auxiliaryBefore=$(<"${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json")
    currentInstallProtocolType=,1,2,
    printf '%s\n' '{"enabled":true,"default_protocol":"xhttp","protocols":{"xhttp":{"public_port":443,"restore_port":9443,"internal_port":2444}}}' >"${PADM_REALITY_STREAM_STATE_FILE}"
    writeCoreDokodemoInbound "${aliasFile}" 2053 2444 tcp dokodemo-door-newPort-2053
    printf '%s\n' '{"inbounds":[{"listen":"127.0.0.1","port":2444,"settings":{"clients":[{"id":"keep-id"}],"decryption":"keep-encryption"},"streamSettings":{"realitySettings":{"publicKey":"old-public","serverNames":["old.example.com"],"shortIds":["keep-id"]},"xhttpSettings":{"host":"front.example.com","path":"/custom","mode":"packet-up","xmux":{"maxConcurrency":3},"extra":{"downloadSettings":{"realitySettings":{"publicKey":"old-public","serverName":"old.example.com"}}}}}}],"routing":{"rules":[{"outboundTag":"keep-route"}]}}' >"${profileFile}"
    local previousTransport
    previousTransport=$(jq -c '.inbounds[0].streamSettings.xhttpSettings | del(.extra.downloadSettings.realitySettings.publicKey, .extra.downloadSettings.realitySettings.serverName)' "${profileFile}")
    realityStreamXHTTPConfigFile() { printf '%s\n' "${profileFile}"; }
    reloadCore() {
        reloadCalls=$((reloadCalls + 1))
        jq -e '.inbounds[0].listen == "127.0.0.1" and .inbounds[0].port == 2444' "${profileFile}" >/dev/null
    }
    regenerateRealityProfile
    [[ "$(<"${singBoxConfigPath}07_VLESS_vision_reality_inbounds.json")" == "${auxiliaryBefore}" ]]
    jq -e '.inbounds[0].settings.port == 2444' "${aliasFile}" >/dev/null
    [[ "$(jq -c '.inbounds[0].streamSettings.xhttpSettings | del(.extra.downloadSettings.realitySettings.publicKey, .extra.downloadSettings.realitySettings.serverName)' "${profileFile}")" == "${previousTransport}" ]]
    jq -e '.inbounds[0] | .settings.clients[0].id == "keep-id" and .settings.decryption == "keep-encryption" and
        .streamSettings.realitySettings.shortIds == ["keep-id"] and
        .streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey == "new-public" and
        .streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.serverName == "sni.example.com"' "${profileFile}" >/dev/null
    updateRoutingJsonConfig "${profileFile}" '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey = "external-public"'
    regenerateRealityProfile
    jq -e '.inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey == "external-public" and .routing.rules[0].outboundTag == "keep-route"' "${profileFile}" >/dev/null
    updateRoutingJsonConfig "${profileFile}" '.inbounds[0].streamSettings.realitySettings.publicKey = "shared-public" |
        .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey = "shared-public" |
        .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.serverName = "independent.example.com"'
    regenerateRealityProfile
    jq -e '.inbounds[0].streamSettings.realitySettings.publicKey == "new-public" and
        .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.publicKey == "shared-public" and
        .inbounds[0].streamSettings.xhttpSettings.extra.downloadSettings.realitySettings.serverName == "independent.example.com"' "${profileFile}" >/dev/null
    (
        # 真实校验入口必须执行语义 check，merge 成功不能代替校验。
        eval "${validationSource}"
        local args= fixtureBinary="${root}/binary"
        printf '#!/bin/sh\nexit 0\n' >"${fixtureBinary}"
        chmod +x "${fixtureBinary}"
        realityXrayVisionConfigPath() { printf '%s/missing-vision\n' "${root}"; }
        realityXrayGrpcConfigPath() { printf '%s/missing-grpc\n' "${root}"; }
        realityXrayXhttpConfigPath() { printf '%s/missing-xhttp\n' "${root}"; }
        realitySingBoxVisionConfigPath() { printf '%s\n' "${profileFile}"; }
        realitySingBoxGrpcConfigPath() { printf '%s/missing-sb-grpc\n' "${root}"; }
        coreSingBoxBinaryPath() { printf '%s\n' "${fixtureBinary}"; }
        singBoxMergeConfigForValidation() { args="$*"; [[ "$3" != check ]]; }
        regressionExpectStatus 1 validateRealityTargetConfigAfterChange
        [[ "${args}" == "${fixtureBinary} "*' check' ]]
    )
    (
        # 状态读取失败不进入事务，不生成模板或恢复服务；旧配置和额外入口保持不变。
        local originalProfile=$(<"${profileFile}") originalAlias=$(<"${aliasFile}")
        for invalidState in '' '{' '{}' '{"enabled":true,"default_protocol":"xhttp","protocols":{}}' \
            '{"enabled":true,"default_protocol":"xhttp","protocols":{"xhttp":{"internal_port":0,"public_port":443}}}'; do
            printf '%s' "${invalidState}" >"${PADM_REALITY_STREAM_STATE_FILE}"
            templateCalls=0 subscribeCalls=0 reloadCalls=0 backupCalls=0 restoredCore=
            regressionExpectStatus 1 regenerateRealityProfile
            [[ "${templateCalls}:${subscribeCalls}:${reloadCalls}:${backupCalls}" == 0:0:0:0 &&
                -z "${restoredCore}" &&
                "$(<"${profileFile}")" == "${originalProfile}" && "$(<"${aliasFile}")" == "${originalAlias}" ]]
            local coexistPort=unchanged
            regressionExpectStatus 2 resolveRealityInstallCoexistPort coexistPort xhttp fixture
            [[ "${coexistPort}" == unchanged ]]
        done
    )
    printf '%s\n' '{"enabled":true,"default_protocol":"xhttp","protocols":{"xhttp":{"public_port":443,"restore_port":9443,"internal_port":2444}}}' >"${PADM_REALITY_STREAM_STATE_FILE}"
    (
        updateRoutingJsonConfig() { return 1; }
        local originalProfile originalAlias
        originalProfile=$(<"${profileFile}")
        originalAlias=$(<"${aliasFile}")
        subscribeCalls=0 reloadCalls=0
        regressionExpectStatus 1 regenerateRealityProfile
        [[ "$(<"${profileFile}")" == "${originalProfile}" && "$(<"${aliasFile}")" == "${originalAlias}" &&
            "${subscribeCalls}" == 0 && "${reloadCalls}" == 0 ]]
    )
)

runReloadCorePropagationRegression() (
    runRegressionStep reality-regenerate-transaction runRealityRegenerateTransactionRegression
    local root="${TMP_DIR}/reload-core-propagation"
    local alpnConfig="${root}/alpn.json"
    local vlessConfig="${root}/vless.json"
    local vlessState="${root}/vless-state.json"
    local fakeXray="${root}/xray"
    local refreshMarker="${root}/refresh"
    local subscribeMarker="${root}/subscribe"
    local reloadLog="${root}/reloads"
    local originalContent rc

    mkdir -p "${root}/nginx"
    errorCard() { return 0; }
    echoContent() { return 0; }
    menuLine() { return 0; }
    menuClose() { return 0; }
    cleanDirectoryContent() { return 0; }

    cat >"${alpnConfig}" <<'JSON'
{"inbounds":[{"streamSettings":{"tlsSettings":{"alpn":["http/1.1"]}}}]}
JSON
    traditionalTlsFallbackConfigFile() { printf '%s\n' "${alpnConfig}"; }
    padmCreateTempFileForTarget() {
        local -n targetRef=$1
        local targetFile=$2
        targetRef="${targetFile}.tmp"
        return 0
    }
    padmRemoveCleanupPath() { rm -f "$1"; }
    commitGeneratedJsonFile() {
        local tmpFile=$1
        local targetFile=$2
        mv "${tmpFile}" "${targetFile}"
    }
    reloadCore() {
        printf 'reload\n' >>"${reloadLog}"
        return 1
    }

    originalContent=$(<"${alpnConfig}")
    (
        local unavailable
        printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/xray-not-executable"
        chmod 0644 "${root}/xray-not-executable"
        for unavailable in "${root}/xray-missing" "${root}/xray-not-executable"; do
            PADM_XRAY_BINARY="${unavailable}"
            regressionExpectStatus 1 applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
            [[ "$(<"${alpnConfig}")" == "${originalContent}" ]]
            [[ ! -e "${alpnConfig}.alpn.bak" && ! -e "${alpnConfig}.tmp" && ! -e "${reloadLog}" ]]
        done
    ) || return 1
    printf '#!/usr/bin/env bash\nexit 0\n' >"${fakeXray}"
    chmod 0755 "${fakeXray}"
    local PADM_XRAY_BINARY="${fakeXray}" PADM_XRAY_CONF_DIR="${root}"
    regressionExpectStatus 1 applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
    [[ "$(<"${alpnConfig}")" == "${originalContent}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"
    (
        cp() {
            if [[ "$1" == "-p" && "$2" == "${alpnConfig}.alpn.bak" && "$3" == "${alpnConfig}.tmp" ]]; then
                return 1
            fi
            command cp "$@"
        }
        regressionExpectStatus 1 applyTraditionalTlsAlpn '["h2","http/1.1"]' >/dev/null 2>&1
        jq -e '.inbounds[0].streamSettings.tlsSettings.alpn == ["h2","http/1.1"]' "${alpnConfig}" >/dev/null
        [[ "$(<"${alpnConfig}.alpn.bak")" == "${originalContent}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${alpnConfig}"
    rm -f "${alpnConfig}.alpn.bak"

    cat >"${fakeXray}" <<'SH'
#!/usr/bin/env bash
case "$1" in
--version)
    printf 'Xray 25.9.5\n'
    ;;
vlessenc)
    printf '{"encryption":"mlkem768x25519plus.native.enc","decryption":"mlkem768x25519plus.native.dec"}\n'
    ;;
-test)
    exit 0
    ;;
esac
SH
    chmod +x "${fakeXray}"
    cat >"${vlessConfig}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"u","flow":"xtls-rprx-vision"}],"decryption":"none","fallbacks":[]}}]}
JSON
    originalContent=$(<"${vlessConfig}")
    coreInstallType=1
    PADM_XRAY_BINARY="${fakeXray}"
    PADM_XRAY_CONF_DIR="${root}"
    PADM_VLESS_REALITY_CONFIG_FILE="${vlessConfig}"
    PADM_VLESS_XHTTP_CONFIG_FILE="${root}/missing-xhttp.json"
    PADM_VLESS_ENCRYPTION_STATE_FILE="${vlessState}"
    readNginxSubscribe() {
        printf 'refresh\n' >"${refreshMarker}"
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    subscribe() { return 0; }

    rm -f "${refreshMarker}" "${vlessState}" "${reloadLog}"
    regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${refreshMarker}" ]]
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        cp() {
            if [[ "$1" == "-p" && "$2" == "${vlessConfig}" && "$3" == "${vlessConfig}.vlessenc.bak.tmp" ]]; then
                return 1
            fi
            command cp "$@"
        }
        reloadCore() { return 0; }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessState}.tmp" && "$2" == "${vlessState}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessState}.tmp" && "$4" == "${vlessState}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        reloadCore() { return 0; }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
        [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
        [[ ! -e "${vlessState}" ]]
        [[ ! -e "${vlessState}.tmp" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1

    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${refreshMarker}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    (
        mv() {
            if [[ "$1" == "${vlessConfig}.tmp" && "$2" == "${vlessConfig}" ]] ||
                [[ "$1" == "-f" && "$2" == "--" && "$3" == "${vlessConfig}.vlessenc" && "$4" == "${vlessConfig}" ]]; then
                return 1
            fi
            command mv "$@"
        }
        regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
        jq -e '.inbounds[0].settings.decryption == "mlkem768x25519plus.native.dec"' "${vlessConfig}" >/dev/null
        [[ "$(<"${vlessConfig}.vlessenc.bak")" == "${originalContent}" ]]
        [[ -e "${vlessState}" ]]
        [[ ! -e "${refreshMarker}" ]]
    ) || return 1
    printf '%s\n' "${originalContent}" >"${vlessConfig}"
    rm -f "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"

    reloadCore() { printf 'reload\n' >>"${reloadLog}"; return 0; }
    subscribe() {
        printf 'subscribe-unexpected\n' >"${subscribeMarker}"
        return 1
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-published\n' >"${subscribeMarker}"
        return 1
    }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    rm -f "${refreshMarker}" "${subscribeMarker}" "${reloadLog}" "${vlessState}" "${vlessConfig}.vlessenc.bak" "${vlessState}.bak" "${vlessState}.tmp"
    regressionExpectStatus 1 setVlessRealityEncryption enable >/dev/null 2>&1
    [[ "$(<"${vlessConfig}")" == "${originalContent}" ]]
    [[ ! -e "${vlessState}" ]]
    [[ ! -e "${vlessConfig}.vlessenc.bak" ]]
    [[ ! -e "${vlessState}.bak" ]]
    grep -qx 'refresh-published' "${subscribeMarker}"
    [[ "$(wc -l <"${reloadLog}" | tr -d ' ')" == "2" ]]

    reloadCore() { return 0; }
    refreshPublishedSubscriptions() { return 1; }
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${root}/nginx/"
    }
    regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1

    subscribePort=
    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${root}/nginx/"
    }
    showAccounts() { return 1; }
    regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1

    currentInstallProtocolType=,1,
    # 真实事务已在独立夹具验证；下面只检查调用方的选择与失败传播。
    coreTemplateConfigTransaction() { shift; "$@"; }
    initRealityProfile() { realityTargetHost=fixture.example.com; realityTargetPort=443; realitySNI=fixture.example.com; }
    initRealityKey() { realityPrivateKey=fixture-private; realityPublicKey=fixture-public; }
    initRealityMldsa65() { :; }
    xrayTemplateConfigDir() { printf '%s\n' "${root}"; }
    singBoxTemplateConfigDir() { printf '%s\n' "${root}"; }
    cp "${vlessConfig}" "${root}/07_VLESS_vision_reality_inbounds.json"
    updateRoutingJsonConfig() { :; }
    validateRealityTargetConfigAfterChange() { :; }
    reloadCore() { return 1; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 0
    }
    rm -f "${subscribeMarker}"
    regressionExpectStatus 1 regenerateRealityProfile >/dev/null 2>&1
    [[ ! -e "${subscribeMarker}" ]]

    reloadCore() { return 0; }
    subscribe() {
        printf 'subscribe\n' >"${subscribeMarker}"
        return 1
    }
    rm -f "${subscribeMarker}"
    regressionExpectStatus 1 regenerateRealityProfile >/dev/null 2>&1
    [[ -e "${subscribeMarker}" ]]
    (
        # 重新生成只选择当前 Reality 协议，不沿用或改写上次安装选择。
        local selectCustomInstallType=,20, currentInstallProtocolType selectedProtocol
        updateRoutingJsonConfig() { selectedProtocol+="$(protocolCapabilityIdByConfigFile "${1##*/}"),"; }
        printf '{}\n' >"${root}/08_VLESS_vision_gRPC_inbounds.json"
        printf '{}\n' >"${root}/12_VLESS_XHTTP_inbounds.json"
        reloadCore() { :; }
        subscribe() { :; }
        for currentInstallProtocolType in ,1, ,26, ,1,26,; do
            coreInstallType=2
            selectedProtocol=
            regenerateRealityProfile
            [[ "${selectCustomInstallType}" == ,20, ]]
            assertEquals "${currentInstallProtocolType#,}" "${selectedProtocol}" reality-regenerate-selection
        done
        for currentInstallProtocolType in ,1, ,2, ,26, ,1,2,26,; do
            coreInstallType=1
            selectedProtocol=
            regenerateRealityProfile
            [[ "${selectCustomInstallType}" == ,20, && "${selectedProtocol}" == "${currentInstallProtocolType#,}" ]]
        done
        currentInstallProtocolType=,3,
        selectedProtocol=
        regressionExpectStatus 1 regenerateRealityProfile
        [[ "${selectCustomInstallType}" == ,20, && -z "${selectedProtocol}" ]]
    )
)

runConfigTransactionRegression() (
    local tmpRoot
    tmpRoot=$(cd -- "${TMP_DIR}" && pwd -P) || return 1
    local targetFile="${tmpRoot}/transaction.json"
    local backupFile="${targetFile}.bak"
    local stagedFile
    local originalContent updatedContent
    local reloadCountFile="${tmpRoot}/transaction-reload-count"
    local refreshCountFile="${tmpRoot}/transaction-refresh-count"
    local validationLog="${tmpRoot}/transaction-validation.json" validateCount=0
    local validateMode=success
    local reloadMode=success
    local refreshMode=success
    local oldPath="${PATH}"
    local oldTmpDir="${TMPDIR:-}"
    local checkPortTmpRootRel="${TMP_DIR}/check-port-tmp"
    local checkPortTmpRoot
    local checkPortNginxDirRel="${TMP_DIR}/check-port-nginx"
    local checkPortNginxDir checkPortTarget
    local fakeBinDirRel="${TMP_DIR}/fake-bin"
    local fakeBinDir="${tmpRoot}/fake-bin"
    mkdir -p "${checkPortTmpRootRel}" "${checkPortNginxDirRel}" "${fakeBinDirRel}"
    checkPortTmpRoot="$(cd -- "${checkPortTmpRootRel}" && pwd -P)"
    checkPortNginxDir="$(cd -- "${checkPortNginxDirRel}" && pwd -P)/"
    checkPortTarget="${checkPortNginxDir}checkPortOpen.conf"
    TMPDIR="${checkPortTmpRoot}"

    transactionReloadMock() {
        printf '1\n' >>"${reloadCountFile}"
        [[ "${reloadMode}" == "success" ]]
    }

    transactionRefreshMock() {
        printf '1\n' >>"${refreshCountFile}"
        [[ "${refreshMode}" == "success" ]]
    }

    transactionValidateMock() {
        validateCount=$((validateCount + 1))
        printf '%s\n' "$(<"${targetFile}")" >"${validationLog}"
        [[ "${validateMode}" == "success" ]]
    }

    cat >"${targetFile}" <<'JSON'
{"mode":"old","port":443}
JSON
    originalContent=$(<"${targetFile}")
    (
        # 路径拒绝和备份失败都要立即清理暂存，不能进入校验、重载或订阅刷新。
        local requestedFile validateCalls="${tmpRoot}/transaction-early-validate"
        backupManagedFileToPath() { return 1; }
        transactionValidateMock() { printf 'validate\n' >>"${validateCalls}"; }
        for requestedFile in relative/config.json "${targetFile}"; do
            padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
            jq '.mode = "new"' "${targetFile}" >"${stagedFile}"
            regressionExpectStatus 1 configTransactionCommit "${requestedFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock
            [[ "$(<"${targetFile}")" == "${originalContent}" && ! -e "${stagedFile}" && ! -e "${backupFile}" ]]
            [[ ! -e "${validateCalls}" && ! -e "${reloadCountFile}" && ! -e "${refreshCountFile}" ]]
        done
    )
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new"' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ ! -e "${reloadCountFile}" ]]
    [[ ! -e "${refreshCountFile}" ]]
    # 回滚后不能再次校验旧文件，避免覆盖首次失败配置的诊断证据。
    [[ "${validateCount}" == 1 ]]
    jq -e '.mode == "new"' "${validationLog}" >/dev/null

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        [[ "$(<"${targetFile}")" != "${originalContent}" ]]
        jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
        [[ "$(<"${backupFile}")" == "${originalContent}" ]]
        [[ ! -e "${stagedFile}" ]]
        [[ ! -e "${reloadCountFile}" ]]
        [[ ! -e "${refreshCountFile}" ]]
        # 回滚失败留下的原始备份不能被下次参数修改覆盖。
        local failedContent previousValidateCount=${validateCount}
        failedContent=$(<"${targetFile}")
        padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
        jq '.mode = "another"' "${targetFile}" >"${stagedFile}"
        regressionExpectStatus 1 configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock || return 1
        [[ "$(<"${targetFile}")" == "${failedContent}" && "$(<"${backupFile}")" == "${originalContent}" &&
            ! -e "${stagedFile}" && "${validateCount}" == "${previousValidateCount}" &&
            ! -e "${reloadCountFile}" && ! -e "${refreshCountFile}" ]] || return 1
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local validateFailureLog="${tmpRoot}/transaction-validate-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=fail
    (
        menuLine() { printf '%s\n' "$*" >>"${validateFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "配置校验失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${validateFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    validateMode=success
    configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock
    updatedContent=$(<"${targetFile}")
    [[ "${updatedContent}" != "${originalContent}" ]]
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    originalContent=$(<"${targetFile}")
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    [[ "$(<"${targetFile}")" == "${originalContent}" ]]
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "2" ]]
    [[ ! -e "${refreshCountFile}" ]]

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    local reloadFailureLog="${tmpRoot}/transaction-reload-failure.log"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=fail
    refreshMode=success
    (
        menuLine() { printf '%s\n' "$*" >>"${reloadFailureLog}"; }
        echoContent() { :; }
        menuClose() { :; }
        cp() {
            local args=("$@")
            local targetPath="${args[$((${#args[@]} - 1))]}"
            if [[ "${targetPath}" == "${tmpRoot}"/.transaction.json.restore.* ]]; then
                return 1
            fi
            command cp "$@"
        }
        if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
            return 1
        fi
        grep -qx "核心重载失败，且回滚配置失败，请手动检查 ${targetFile} 和 ${backupFile}" "${reloadFailureLog}"
    ) || return 1

    printf '{"mode":"old","port":443}\n' >"${targetFile}"
    rm -f "${backupFile}" "${reloadCountFile}" "${refreshCountFile}"
    padmCreateTempFileForTarget stagedFile "${targetFile}" transaction || return 1
    jq '.mode = "new" | .port = 8443' "${targetFile}" >"${stagedFile}"
    reloadMode=success
    refreshMode=fail
    if configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" transactionValidateMock "事务校验失败" "已回滚事务" "事务成功" transactionRefreshMock transactionReloadMock >/dev/null 2>&1; then
        return 1
    fi
    jq -e '.mode == "new" and .port == 8443' "${targetFile}" >/dev/null
    [[ ! -e "${stagedFile}" ]]
    [[ ! -e "${backupFile}" ]]
    [[ "$(wc -l <"${reloadCountFile}" | tr -d ' ')" == "1" ]]
    [[ "$(wc -l <"${refreshCountFile}" | tr -d ' ')" == "1" ]]
    refreshMode=success

    (
        # 提交和校验中断只恢复文件，重载中断同时恢复旧核心；订阅中断保留已生效配置。
        local signalPhase signalRecovery signalName expectedRc caseRoot calls errors resultRc
        local targetFile backupFile stagedFile
        eval "$(declare -f commitGeneratedJsonFile | sed '1s/^commitGeneratedJsonFile/originalConfigSignalCommit/')"
        eval "$(declare -f restoreManagedFileFromBackup | sed '1s/^restoreManagedFileFromBackup/originalConfigSignalRestore/')"
        commitGeneratedJsonFile() {
            originalConfigSignalCommit "$@" || return 1
            [[ "${signalPhase}" != commit ]] || kill "-${signalName}" "${BASHPID}"
        }
        restoreManagedFileFromBackup() {
            [[ "${signalRecovery}" != file-fail ]] || return 1
            originalConfigSignalRestore "$@"
        }
        configSignalValidate() {
            [[ "${signalPhase}" != validate ]] || kill "-${signalName}" "${BASHPID}"
            return 0
        }
        configSignalReload() {
            local mode
            mode=$(jq -r '.mode' "${targetFile}") || return 1
            printf '%s\n' "${mode}" >>"${calls}"
            if [[ "${mode}" == new && "${signalPhase}" == reload ]]; then
                kill "-${signalName}" "${BASHPID}"
            fi
            [[ "${mode}" != old || "${signalRecovery}" != reload-fail ]]
        }
        configSignalRefresh() {
            [[ "${signalPhase}" != refresh ]] || kill "-${signalName}" "${BASHPID}"
            return 0
        }
        for signalName in INT TERM; do
            expectedRc=130
            [[ "${signalName}" != TERM ]] || expectedRc=143
            for signalPhase in commit validate reload refresh; do
                for signalRecovery in success file-fail reload-fail; do
                    [[ "${signalPhase}" != refresh || "${signalRecovery}" == success ]] || continue
                    [[ "${signalRecovery}" != reload-fail || "${signalPhase}" == reload ]] || continue
                    caseRoot="${tmpRoot}/config-signal-${signalName}-${signalPhase}-${signalRecovery}"
                    mkdir -p "${caseRoot}" || return 1
                    targetFile="${caseRoot}/config.json"
                    backupFile="${caseRoot}/config.bak"
                    stagedFile="${caseRoot}/staged.json"
                    calls="${caseRoot}/reload.log" errors="${caseRoot}/errors.log"
                    printf '{"mode":"old"}\n' >"${targetFile}"
                    printf '{"mode":"new"}\n' >"${stagedFile}"
                    : >"${calls}" "${errors}"
                    (
                        errorCard() { printf '%s\n' "$*" >>"${errors}"; }
                        configTransactionCommit "${targetFile}" "${stagedFile}" "${backupFile}" \
                            configSignalValidate "事务校验失败" "已回滚事务" "事务成功" \
                            configSignalRefresh configSignalReload
                    ) >/dev/null 2>&1 && resultRc=0 || resultRc=$?
                    [[ "${resultRc}" == "${expectedRc}" && ! -e "${stagedFile}" ]] || return 1
                    if [[ "${signalPhase}" == refresh ]]; then
                        jq -e '.mode == "new"' "${targetFile}" >/dev/null || return 1
                        [[ ! -e "${backupFile}" && "$(<"${calls}")" == new ]] || return 1
                    elif [[ "${signalRecovery}" == file-fail ]]; then
                        jq -e '.mode == "new"' "${targetFile}" >/dev/null || return 1
                        jq -e '.mode == "old"' "${backupFile}" >/dev/null || return 1
                        [[ "${signalPhase}" != reload || "$(<"${calls}")" == new ]] || return 1
                        [[ "${signalPhase}" == reload || ! -s "${calls}" ]] || return 1
                        grep -q '中断后回滚失败' "${errors}" || return 1
                    else
                        jq -e '.mode == "old"' "${targetFile}" >/dev/null || return 1
                        if [[ "${signalPhase}" == reload ]]; then
                            [[ "$(<"${calls}")" == $'new\nold' ]] || return 1
                        else
                            [[ ! -s "${calls}" ]] || return 1
                        fi
                        if [[ "${signalRecovery}" == reload-fail ]]; then
                            jq -e '.mode == "old"' "${backupFile}" >/dev/null || return 1
                            grep -q '旧核心重载失败' "${errors}" || return 1
                        else
                            [[ ! -e "${backupFile}" ]] || return 1
                        fi
                    fi
                done
            done
        done
    ) || return 1

    (
        # 协议只重载对应核心；失败时回滚自身配置，订阅刷新成功后才通知。
        local protocolFile="${tmpRoot}/protocol-parameter.json" calls="${tmpRoot}/protocol-parameter.log"
        local type operation protocolCore serviceStatus=0 protocolRefreshStatus=0 coreInstallType=1 singBoxConfigPath="${tmpRoot}/auxiliary/"
        local PADM_XHTTP_CONFIG_FILE="${protocolFile}" PADM_SKIP_CONTROLLER_REFRESH= PADM_CONTROL_SERVER=
        local -a args
        tuicConfigFile() { printf '%s\n' "${protocolFile}"; }
        hysteria2ConfigFile() { printf '%s\n' "${protocolFile}"; }
        coreSingBoxBinaryPath() { printf '%s\n' "${tmpRoot}/missing-sing-box"; }
        coreXrayBinaryPath() { printf '%s\n' "${tmpRoot}/missing-xray"; }
        reloadCore() { printf 'unexpected-reload\n' >>"${calls}"; return 99; }
        runServiceAction() { printf 'service:%s:%s\n' "$1" "$2" >>"${calls}"; return "${serviceStatus}"; }
        refreshProtocolSubscriptions() { printf 'refresh:%s\n' "$1" >>"${calls}"; return "${protocolRefreshStatus}"; }
        subscriptionNotifyControllerRefresh() { printf 'notify\n' >>"${calls}"; return 1; }
        for type in XHTTP Tuic Hysteria2; do
            protocolCore=sing-box
            case "${type}" in
            XHTTP) operation=setXHTTPMode; args=(stream-up); protocolCore=xray ;;
            Tuic) operation=setTuicRecommendedDefaults; args=() ;;
            Hysteria2) operation=setHysteria2BandwidthMode; args=(bbr) ;;
            esac
            originalContent='{"inbounds":[{"congestion_control":"bbr","up_mbps":100,"down_mbps":50,"streamSettings":{"xhttpSettings":{"mode":"auto"}}}]}'
            printf '%s\n' "${originalContent}" >"${protocolFile}"
            : >"${calls}"
            serviceStatus=0
            "${operation}" "${args[@]}"
            [[ "$(<"${calls}")" == "service:${protocolCore}:restart"$'\n'"refresh:${type}"$'\n'notify ]]
            [[ "$(<"${protocolFile}")" != "${originalContent}" ]]
            printf '%s\n' "${originalContent}" >"${protocolFile}"
            : >"${calls}"
            serviceStatus=1
            regressionExpectStatus 1 "${operation}" "${args[@]}" >/dev/null 2>&1
            [[ "$(<"${protocolFile}")" == "${originalContent}" ]]
            [[ "$(<"${calls}")" == "service:${protocolCore}:restart"$'\n'"service:${protocolCore}:restart" ]]
            : >"${calls}"
            serviceStatus=0
            protocolRefreshStatus=1
            regressionExpectStatus 1 "${operation}" "${args[@]}" >/dev/null 2>&1
            [[ "$(<"${protocolFile}")" != "${originalContent}" ]]
            [[ "$(<"${calls}")" == "service:${protocolCore}:restart"$'\n'"refresh:${type}" ]]
            protocolRefreshStatus=0
        done
        serviceStatus=0
        printf '{"inbounds":[{"up_mbps":72,"down_mbps":38}]}\n' >"${protocolFile}"
        setHysteria2BandwidthMode brutal <<< $'\n\n'
        jq -e '.inbounds[0] | .up_mbps == 72 and .down_mbps == 38' "${protocolFile}" >/dev/null
        : >"${calls}"
        PADM_SKIP_CONTROLLER_REFRESH=1 refreshTuicSubscriptions
        PADM_CONTROL_SERVER=1 refreshHysteria2Subscriptions
        PADM_SKIP_CONTROLLER_REFRESH=1 refreshXHTTPSubscriptions
        PADM_CONTROL_SERVER=1 refreshXHTTPSubscriptions
        [[ "$(<"${calls}")" == $'refresh:Tuic\nrefresh:Hysteria2\nrefresh:XHTTP\nrefresh:XHTTP' ]]
        printf '{' >"${protocolFile}"
        : >"${calls}"
        autoRead() { printf 'unexpected-input\n' >>"${calls}"; printf -v "$3" '%s' 100; }
        regressionExpectStatus 1 setHysteria2BandwidthMode brutal >/dev/null 2>&1
        [[ "$(<"${protocolFile}")" == '{' && ! -s "${calls}" ]]
    )

    local refreshFailureLog="${tmpRoot}/transaction-refresh-failure.log"
    local localSubscribeBase
    mkdir -p "${TMP_DIR}/subscribe_local/default" "${TMP_DIR}/subscribe_local/clashMeta" "${TMP_DIR}/subscribe_local/sing-box"
    PADM_SUBSCRIBE_LOCAL_DIR="${tmpRoot}/subscribe_local"
    localSubscribeBase=$(subscribeLocalBaseDir)
    readNginxSubscribe() {
        subscribePort=443
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    subscribe() {
        printf 'subscribe-unexpected:%s\n' "$*" >>"${refreshFailureLog}"
        return 1
    }
    refreshPublishedSubscriptions() {
        printf 'refresh-published\n' >>"${refreshFailureLog}"
        return 1
    }
    showAccounts() {
        printf 'showAccounts\n' >>"${refreshFailureLog}"
        return 1
    }
    errorCard() { return 0; }
    : >"${refreshFailureLog}"
    if refreshXHTTPSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'refresh-published' "${refreshFailureLog}"
    ! grep -q '^subscribe-unexpected:' "${refreshFailureLog}"

    : >"${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'refresh-published' "${refreshFailureLog}"

    readNginxSubscribe() {
        subscribePort=
        nginxConfigPath="${TMP_DIR}/nginx-refresh/"
    }
    : >"${refreshFailureLog}"
    if refreshTuicSubscriptions >/dev/null 2>&1; then
        return 1
    fi
    grep -qx 'showAccounts' "${refreshFailureLog}"

    (
        cleanDirectoryContent() {
            printf 'cleanDirectoryContent\n' >>"${refreshFailureLog}"
            return 1
        }
        showAccounts() {
            printf 'showAccounts\n' >>"${refreshFailureLog}"
            return 0
        }
        readNginxSubscribe() {
            subscribePort=
            nginxConfigPath="${TMP_DIR}/nginx-refresh/"
        }
        : >"${refreshFailureLog}"
        regressionExpectStatus 1 refreshVlessEncryptionSubscriptions >/dev/null 2>&1
        grep -qx 'cleanDirectoryContent' "${refreshFailureLog}"
        ! grep -q '^showAccounts$' "${refreshFailureLog}"
    ) || return 1
    (
        # 订阅配置读取失败不能转为本地重建或公网发布，也不能继续主控通知。
        readNginxSubscribe() { subscribePort=; return 1; }
        subscriptionNotifyControllerRefresh() { printf 'notify\n' >>"${refreshFailureLog}"; }
        local refreshFn
        for refreshFn in refreshXHTTPSubscriptions refreshHysteria2Subscriptions refreshTuicSubscriptions refreshVlessEncryptionSubscriptions; do
            : >"${refreshFailureLog}"
            regressionExpectStatus 1 "${refreshFn}"
            [[ ! -s "${refreshFailureLog}" ]]
        done
    )

    cat >"${fakeBinDir}/nginx" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "-t" ]]
printf 'check-port validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${fakeBinDir}/nginx"
    PATH="${fakeBinDir}:${PATH}"
    nginxConfigPath="${checkPortNginxDir}"
    printf 'old config\n' >"${checkPortTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${checkPortTarget}")" == "old config" ]]
    grep -qxF 'check-port validate fail' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    [[ ! -e "${checkPortTarget}.tmp" ]]

    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    (
        restoreManagedFileFromBackup() { return 1; }
        if writeCheckPortOpenNginxConfig 443 example.com '' 2>/dev/null; then
            return 1
        fi
        [[ "${CHECK_PORT_OPEN_NGINX_CONFIG_ERROR}" == *"旧配置恢复失败"* ]]
        [[ "$(<"${checkPortTarget}")" != "old config" ]]
        [[ "$(<"${checkPortTarget}.bak")" == "old config" ]]
        [[ ! -e "${checkPortTarget}.tmp" ]]
    ) || return 1
    printf 'old config\n' >"${checkPortTarget}"
    rm -f "${checkPortTarget}.bak"

    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    writeCheckPortOpenNginxConfig 443 example.com 'listen [::]:443;'
    grep -qxF 'check-port validate success' "${checkPortTmpRoot}/padm-check-port-open-nginx-test.log"
    grep -q 'server_name example.com;' "${checkPortTarget}"
    grep -q 'listen \[::\]:443;' "${checkPortTarget}"
    [[ ! -e "${checkPortTarget}.tmp" ]]
    [[ ! -e "${checkPortTarget}.bak" ]]
    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    unset PADM_FAKE_NGINX_VALIDATE_MODE
)

runEntryHelperConfigRegression() {
    local entryConfigPath="${TMP_DIR}/entry-helper-conf/"
    local entryFakeBin="${TMP_DIR}/entry-helper-fake-bin"
    local entryLogBase="${TMP_DIR}/entry-helper-logs/"
    local entryTmpRoot="${TMP_DIR}/entry-helper-tmp"
    local oldTmpDir="${TMPDIR:-}"
    local realityVisionFile="${entryConfigPath}07_VLESS_vision_reality_inbounds.json"
    local realityXhttpFile="${entryConfigPath}12_VLESS_XHTTP_inbounds.json"
    local oldPath="${PATH}"
    local protocolSelectionIncludesDef=
    local nginxTarget="${TMP_DIR}/entry-helper-nginx/sing_box_VMess_HTTPUpgrade.conf"
    local originalContent
    mkdir -p "${entryConfigPath}" "${entryLogBase}" "${entryFakeBin}" "${TMP_DIR}/entry-helper-nginx" "${entryTmpRoot}"
    cat >"${entryFakeBin}/nginx" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == "-v" ]]; then
    printf 'nginx version: nginx/1.24.0\n' >&2
    exit 0
fi
[[ "$1" == "-t" ]]
printf 'entry-helper validate %s\n' "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}"
[[ "${PADM_FAKE_NGINX_VALIDATE_MODE:-success}" == "success" ]]
SH
    chmod +x "${entryFakeBin}/nginx"
    PATH="${entryFakeBin}:${PATH}"
    TMPDIR="${entryTmpRoot}"
    protocolSelectionIncludesDef=$(declare -f protocolSelectionIncludes)
    protocolSelectionIncludesDef="${protocolSelectionIncludesDef/protocolSelectionIncludes/regressionOriginalProtocolSelectionIncludes}"
    eval "${protocolSelectionIncludesDef}"
    protocolSelectionIncludes() {
        regressionProtocolSelectionIncludesCompat "$@"
    }
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" true
    [[ "$(jq -r '.log.access' "${entryConfigPath}00_log.json")" == "${entryLogBase}access.log" ]]
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "debug" ]]
    writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
    jq -e '(.log.access | not)' "${entryConfigPath}00_log.json" >/dev/null
    [[ "$(jq -r '.log.error' "${entryConfigPath}00_log.json")" == "${entryLogBase}error.log" ]]
    [[ "$(jq -r '.log.loglevel' "${entryConfigPath}00_log.json")" == "warning" ]]

    (
        local logCasePath
        coreInstallType=1
        realityStatus=7
        xrayRunning() { return 1; }
        autoRead() { printf -v "$3" '1'; }
        for logCasePath in "${TMP_DIR}/entry-helper-access/conf/" "${TMP_DIR}/entry-helper space/conf/" \
            "${TMP_DIR}/parent-conf/xray/conf/"; do
            configPath="${logCasePath}"
            mkdir -p "${configPath}"
            writeXrayLogConfig "${configPath}00_log.json" "${configPath%conf/}" false
            cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
            checkLog >/dev/null 2>&1 || return 1
            jq -e '.log.access != null and .log.loglevel == "debug"' "${configPath}00_log.json" >/dev/null || return 1
            [[ "$(jq -r '.log.error' "${configPath}00_log.json")" == "${configPath%conf/}error.log" ]] || return 1
            jq -e '.inbounds[0].streamSettings.realitySettings.show == true' "${configPath}07_VLESS_vision_reality_inbounds.json" >/dev/null || return 1
            checkLog >/dev/null 2>&1 || return 1
            jq -e '(.log.access | not) and .log.loglevel == "warning"' "${configPath}00_log.json" >/dev/null || return 1
            jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${configPath}07_VLESS_vision_reality_inbounds.json" >/dev/null || return 1
            updateRoutingJsonConfig "${configPath}00_log.json" '.log.access = "none"'
            checkLog >/dev/null 2>&1 || return 1
            jq -e '.log.access != "none" and .log.loglevel == "debug"' "${configPath}00_log.json" >/dev/null || return 1
        done
    ) || return 1

    nginxConfigPath="${TMP_DIR}/entry-helper-nginx/"
    domain=example.com
    nginxStaticPath="${TMP_DIR}/static"
    currentPath=padm
    selectCustomInstallType=23
    printf 'old config\n' >"${nginxTarget}"
    export PADM_FAKE_NGINX_VALIDATE_MODE=fail
    if singBoxNginxConfig 23 443 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${nginxTarget}")" == "old config" ]]
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ -s "${entryTmpRoot}/padm-sing-box-vmess-httpupgrade-nginx-test.log" ]]
    export PADM_FAKE_NGINX_VALIDATE_MODE=success
    singBoxNginxConfig 23 443
    grep -q 'server_name example.com;' "${nginxTarget}"
    grep -q 'location /padm' "${nginxTarget}"
    ! grep -qx 'old config' "${nginxTarget}"
    [[ ! -e "${nginxTarget}.tmp" ]]
    [[ ! -e "${nginxTarget}.bak" ]]
    ! compgen -G "${TMP_DIR}/entry-helper-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null

    (
        local staleRoot="${TMP_DIR}/entry-helper-nginx-stale"
        local staleTarget="${staleRoot}/sing_box_VMess_HTTPUpgrade.conf"
        mkdir -p "${staleRoot}"
        printf 'stale backup\n' >"${staleTarget}.bak"
        nginxConfigPath="${staleRoot}/"
        export PADM_FAKE_NGINX_VALIDATE_MODE=fail
        if writeSingBoxVMessHTTPUpgradeNginxConfig <<'EOF' >/dev/null 2>&1
server {}
EOF
        then
            return 1
        fi
        [[ ! -e "${staleTarget}" ]]
        [[ "$(<"${staleTarget}.bak")" == "stale backup" ]]
        [[ ! -e "${staleTarget}.tmp" ]]
        ! compgen -G "${staleRoot}/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null
    )

    (
        local unsafeRoot="${TMP_DIR}/entry-helper-nginx-unsafe"
        local rc
        mkdir -p "${unsafeRoot}/relative-nginx"
        printf 'stale\n' >"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf"
        cd "${unsafeRoot}"
        nginxConfigPath="relative-nginx/"
        set +e
        writeSingBoxVMessHTTPUpgradeNginxConfig <<'EOF' >/dev/null 2>&1
server {}
EOF
        rc=$?
        set -e
        [[ "${rc}" == "1" ]]
        [[ "$(<"${unsafeRoot}/relative-nginx/sing_box_VMess_HTTPUpgrade.conf")" == "stale" ]]
        ! compgen -G "${unsafeRoot}/relative-nginx/.sing_box_VMess_HTTPUpgrade.conf.*" >/dev/null
    )

    cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
    updateRealityShowConfig "${realityVisionFile}" true
    jq -e '.inbounds[0].streamSettings.realitySettings.show == true' "${realityVisionFile}" >/dev/null
    originalContent=$(<"${realityVisionFile}")
    if updateRoutingJsonConfig "${realityVisionFile}" '.inbounds[0].streamSettings.realitySettings.show = [' 2>/dev/null; then
        return 1
    fi
    [[ "$(<"${realityVisionFile}")" == "${originalContent}" ]]
    [[ ! -e "${realityVisionFile}.tmp" ]]

    cat >"${realityXhttpFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":true}}}]}
JSON
    updateRealityShowConfig "${realityXhttpFile}" false
    jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityXhttpFile}" >/dev/null

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-write-error.log"
        local readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        updateRealityShowConfig() {
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 checkLog >/dev/null 2>&1
        [[ "${readCalls}" == "1" ]]
        grep -q 'Reality 日志联动配置写入失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-check-log-error.log"
        local reloadCalls=0 readCalls=0 rc
        : >"${errorLog}"
        coreInstallType=1
        configPath="${entryConfigPath}"
        realityStatus=7
        writeXrayLogConfig "${entryConfigPath}00_log.json" "${entryLogBase}" false
        cat >"${realityVisionFile}" <<'JSON'
{"inbounds":[{"streamSettings":{"realitySettings":{"show":false}}}]}
JSON
        autoRead() {
            readCalls=$((readCalls + 1))
            printf -v "$3" '1'
        }
        xrayRunning() { return 0; }
        runServiceAction() {
            [[ "$*" == 'xray restart' ]] || return 99
            reloadCalls=$((reloadCalls + 1))
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 checkLog >/dev/null 2>&1
        [[ "${readCalls}" == "1" ]]
        [[ "${reloadCalls}" == "2" ]]
        grep -q '已回滚日志配置修改' "${errorLog}"
        grep -q '恢复旧配置后核心重载仍失败' "${errorLog}"
        jq -e '(.log.access | not) and .log.error == "'"${entryLogBase}"'error.log" and .log.loglevel == "warning"' "${entryConfigPath}00_log.json" >/dev/null
        jq -e '.inbounds[0].streamSettings.realitySettings.show == false' "${realityVisionFile}" >/dev/null
        if regressionFindHasMatches "${entryTmpRoot}" -maxdepth 1 -type d -name 'padm-check-log-backup.*'; then
            return 1
        fi
        xrayRunning() { return 1; }
        reloadCalls=0
        checkLog >/dev/null 2>&1 || return 1
        [[ "${reloadCalls}" == 0 ]]
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-tls-issue-service.log"
        local errorLog="${TMP_DIR}/entry-helper-tls-issue-error.log"
        local rc allowFailure=false
        : >"${serviceLog}"
        : >"${errorLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        currentHost=tls-init.example.com
        lastInstallationConfig=true
        selectCoreType=2
        domain=
        handleNginx() {
            [[ "${sslType}" == letsencrypt && "${dnsAPIStatus}" == n && "${sslEmail}" == prepared@example.com ]] || return 1
            printf 'nginx:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        initTLSNginxConfig 1 >/dev/null 2>&1
        [[ ! -s "${serviceLog}" ]]
        local tlsDomain=${domain} dnsAPIType= dnsAPIStatus=n sslType=letsencrypt sslEmail=prepared@example.com
        acmeExecutable() { printf acmeIssueTool; }
        tlsAcmeLogFile() { printf '%s\n' "${TMP_DIR}/entry-helper-tls-issue-acme.log"; }
        acmeIssueTool() { printf 'issue\n' >>"${serviceLog}"; }
        sudo() { "$@"; }
        allowPort() {
            printf 'allow:%s\n' "$1" >>"${serviceLog}"
            [[ "${allowFailure}" != true ]]
        }
        regressionExpectStatus 1 acmeInstallSSL >/dev/null 2>&1
        [[ "$(<"${serviceLog}")" == $'allow:80\nnginx:stop:true' ]]
        ! grep -q '^issue$' "${serviceLog}"
        grep -q 'TLS 签发' "${errorLog}"
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
        : >"${serviceLog}"
        allowFailure=true
        regressionExpectStatus 1 acmeInstallSSL >/dev/null 2>&1
        [[ "$(<"${serviceLog}")" == allow:80 && "${SERVICE_QUEUE_ALLOW_FAILURE}" == previous ]]
    )

    (
        local serviceLog="${TMP_DIR}/entry-helper-port-service.log"
        local errorLog="${TMP_DIR}/entry-helper-port-error.log"
        local allowMarker="${TMP_DIR}/entry-helper-port-allow"
        local rc
        : >"${serviceLog}"
        : >"${errorLog}"
        rm -f "${allowMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=443
        domain=port.example.com
        handleXray() {
            printf 'xray:%s:%s\n' "$1" "${SERVICE_QUEUE_ALLOW_FAILURE:-}" >>"${serviceLog}"
            return 1
        }
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() {
            printf 'allow\n' >"${allowMarker}"
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        grep -qx 'xray:stop:true' "${serviceLog}"
        grep -q '无法复用当前 Reality 端口' "${errorLog}"
        [[ ! -e "${allowMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local errorLog="${TMP_DIR}/entry-helper-port-expression-error.log"
        local allowLog="${TMP_DIR}/entry-helper-port-expression-allow.log"
        local AUTO_PORT=1+2
        local rc
        : >"${errorLog}"
        : >"${allowLog}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '1+2'
        }
        allowPort() {
            printf '%s\n' "$1" >>"${allowLog}"
        }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 0; }
        checkPortOpen() { return 0; }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        grep -q '端口输入错误' "${errorLog}"
        [[ ! -s "${allowLog}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    (
        local checkPortMarker="${TMP_DIR}/entry-helper-port-nginx-cleanup-check"
        local errorLog="${TMP_DIR}/entry-helper-port-nginx-cleanup-error.log"
        local rc
        : >"${errorLog}"
        rm -f "${checkPortMarker}"
        SERVICE_QUEUE_ALLOW_FAILURE=previous
        btDomain=
        currentPort=
        customPort=
        xrayVLESSRealityPort=
        domain=port.example.com
        autoRead() {
            printf -v "$3" '443'
        }
        allowPort() { return 0; }
        checkDNSIP() { return 0; }
        removeNginxDefaultConf() { return 1; }
        checkPortOpen() {
            : >"${checkPortMarker}"
            return 0
        }
        errorCard() {
            printf '%s\n' "$*" >>"${errorLog}"
        }
        regressionExpectStatus 1 customPortFunction >/dev/null 2>&1
        [[ ! -e "${checkPortMarker}" ]]
        [[ "${SERVICE_QUEUE_ALLOW_FAILURE}" == "previous" ]]
    )

    PATH="${oldPath}"
    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    eval "${protocolSelectionIncludesDef}"
    unset PADM_FAKE_NGINX_VALIDATE_MODE
}

runSingBoxRealityKeyTransactionRegression() (
    local rootRel="${TMP_DIR}/singbox-reality-key-transaction"
    local root singBoxBinary keyFile
    local oldSingBoxBinary="${PADM_SINGBOX_BINARY:-}"
    local oldRealityKeyFile="${PADM_SINGBOX_REALITY_KEY_FILE:-}"
    local oldSelectCoreType="${selectCoreType:-}"
    local oldCoreInstallType="${coreInstallType:-}"
    local oldLastInstallationConfig="${lastInstallationConfig:-}"
    local oldCurrentRealityPublicKey="${currentRealityPublicKey:-}"
    local oldCurrentRealityPrivateKey="${currentRealityPrivateKey:-}"
    local oldRealityPrivateKey="${realityPrivateKey:-}"
    local oldRealityPublicKey="${realityPublicKey:-}"
    local rc

    mkdir -p "${rootRel}/sing-box" "${rootRel}/config"
    root=$(cd -- "${rootRel}" && pwd -P) || return 1
    singBoxBinary="${root}/sing-box/sing-box"
    keyFile="${root}/config/reality_key"
    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-generated\n'
printf 'PublicKey public-generated\n'
EOF
    chmod +x "${singBoxBinary}"
    printf 'publicKey:old-public\n' >"${keyFile}"

    PADM_SINGBOX_BINARY="${singBoxBinary}"
    PADM_SINGBOX_REALITY_KEY_FILE="${keyFile}"
    PADM_SINGBOX_CONFIG_DIR="${root}/config"
    selectCoreType=2
    coreInstallType=2
    lastInstallationConfig=
    currentRealityPublicKey=
    currentRealityPrivateKey=
    realityPrivateKey=
    realityPublicKey=

    eval "$(declare -f commitGeneratedFile | sed '1s/^commitGeneratedFile/originalCommitGeneratedFile/')"
    commitGeneratedFile() {
        if [[ "$2" == "${keyFile}" ]]; then
            return 1
        fi
        originalCommitGeneratedFile "$@"
    }

    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:old-public" ]]
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null

    commitGeneratedFile() {
        originalCommitGeneratedFile "$@"
    }
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-generated" ]]
    [[ "${realityPublicKey}" == "public-generated" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]
    ! compgen -G "${root}/config/.reality_key.reality.*" >/dev/null
    ! grep -qF 'statusCard "Reality Key" "privateKey:${realityPrivateKey}"' "${PROJECT_ROOT}/shell/core/protocol_runtime.sh"

    # 密钥已成功落盘后模板失败，也必须恢复旧密钥或删除首次安装的新文件。
    xrayRunning() { return 1; }
    singBoxRunning() { return 1; }
    realityKeyThenFail() {
        realityPrivateKey=
        realityPublicKey=
        initRealityKey >/dev/null || return 1
        [[ "$(<"${keyFile}")" == publicKey:public-generated ]] || return 2
        return 1
    }
    printf 'publicKey:old-public\n' >"${keyFile}"
    regressionExpectStatus 1 coreTemplateConfigTransaction sing-box realityKeyThenFail
    [[ "$(<"${keyFile}")" == "publicKey:old-public" ]]
    rm -f "${keyFile}"
    regressionExpectStatus 1 coreTemplateConfigTransaction sing-box realityKeyThenFail
    [[ ! -e "${keyFile}" ]]

    lastInstallationConfig=true
    currentRealityPrivateKey=private-reused
    currentRealityPublicKey=public-reused
    realityPrivateKey=
    realityPublicKey=
    initRealityKey >/dev/null
    [[ "${realityPrivateKey}" == "private-reused" ]]
    [[ "${realityPublicKey}" == "public-reused" ]]
    [[ "$(<"${keyFile}")" == "publicKey:public-reused" ]]

    lastInstallationConfig=
    currentRealityPrivateKey=
    currentRealityPublicKey=
    printf 'publicKey:public-generated\n' >"${keyFile}"

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    cat >"${singBoxBinary}" <<'EOF'
#!/usr/bin/env bash
printf 'PrivateKey private-only\n'
EOF
    chmod +x "${singBoxBinary}"
    realityPrivateKey=
    realityPublicKey=
    regressionExpectStatus 1 initRealityKey >/dev/null 2>&1
    [[ "$(<"${keyFile}")" == "publicKey:public-generated" ]]

    if [[ -n "${oldSingBoxBinary}" ]]; then
        PADM_SINGBOX_BINARY="${oldSingBoxBinary}"
    else
        unset PADM_SINGBOX_BINARY
    fi
    if [[ -n "${oldRealityKeyFile}" ]]; then
        PADM_SINGBOX_REALITY_KEY_FILE="${oldRealityKeyFile}"
    else
        unset PADM_SINGBOX_REALITY_KEY_FILE
    fi
    selectCoreType="${oldSelectCoreType}"
    coreInstallType="${oldCoreInstallType}"
    lastInstallationConfig="${oldLastInstallationConfig}"
    currentRealityPublicKey="${oldCurrentRealityPublicKey}"
    currentRealityPrivateKey="${oldCurrentRealityPrivateKey}"
    realityPrivateKey="${oldRealityPrivateKey}"
    realityPublicKey="${oldRealityPublicKey}"
)
