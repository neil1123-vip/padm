#!/usr/bin/env bash

runRuntimeTempDirRegression() (
    local oldTmpDir="${TMPDIR:-}"
    local tmpRoot="${TMP_DIR}/runtime-tmp"
    local targetRoot="${TMP_DIR}/runtime-tempdir-target"
    local crontabPathMarker="${TMP_DIR}/runtime-crontab-path.txt"
    local jsonFile="${targetRoot}/state.json"
    local nestedJsonFile="${targetRoot}/missing/parent/state.json"
    local mkdirToolsLog="${TMP_DIR}/runtime-mkdir-tools.log"
    local mkdirStatus

    mkdir -p "${tmpRoot}" "${targetRoot}"
    TMPDIR="${tmpRoot}"

    : >"${mkdirToolsLog}"
    set +e
    (
        mkdir() {
            printf '%s\n' "$*" >>"${mkdirToolsLog}"
            [[ "$*" == "-p /etc/padm/xray/conf" ]] && return 1
            return 0
        }
        mkdirTools
    )
    mkdirStatus=$?
    set -e
    [[ "${mkdirStatus}" == "1" ]]
    grep -qx -- '-p /etc/padm/xray/conf' "${mkdirToolsLog}"
    grep -qx -- "-p ${tmpRoot}/padm-tls" "${mkdirToolsLog}"
    grep -qx -- '-p /usr/share/nginx/html/' "${mkdirToolsLog}"

    : >"${mkdirToolsLog}"
    (
        mkdir() {
            printf 'mkdir:%s\n' "$*" >>"${mkdirToolsLog}"
            return 0
        }
        chmod() {
            printf 'chmod:%s\n' "$*" >>"${mkdirToolsLog}"
            return 0
        }
        mkdirTools
    )
    grep -q -- 'chmod:700 .*subscribe_local' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .* /etc/padm/xray/conf' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .* /etc/padm/sing-box/conf' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/default' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/clashMeta' "${mkdirToolsLog}"
    grep -q -- 'chmod:700 .*subscribe_local/sing-box' "${mkdirToolsLog}"

    [[ "$(padmTmpFilePath padm-runtime-direct.log)" == "${tmpRoot}/padm-runtime-direct.log" ]]
    [[ "$(traditionalTlsAlpnTestLog)" == "${tmpRoot}/padm-alpn-xray-test.log" ]]
    [[ "$(xhttpConfigTestLog)" == "${tmpRoot}/padm-xhttp-test.log" ]]
    [[ "$(tuicConfigTestLog)" == "${tmpRoot}/padm-tuic-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-xray-test.log)" == "${tmpRoot}/padm-core-xray-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-xray-upgrade-test.log)" == "${tmpRoot}/padm-core-xray-upgrade-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-sing-box-test.log)" == "${tmpRoot}/padm-core-sing-box-test.log" ]]
    [[ "$(coreTmpFilePath padm-core-sing-box-upgrade-test.log)" == "${tmpRoot}/padm-core-sing-box-upgrade-test.log" ]]
    [[ "$(coreTmpFilePath padm-xray.init.XXXXXX)" == "${tmpRoot}/padm-xray.init.XXXXXX" ]]
    [[ "$(coreTmpFilePath padm-sing-box.service.XXXXXX)" == "${tmpRoot}/padm-sing-box.service.XXXXXX" ]]
    [[ "$(coreTmpFilePath padm-xray.service.XXXXXX)" == "${tmpRoot}/padm-xray.service.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-packages.XXXXXX)" == "${tmpRoot}/padm-packages.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-tls)" == "${tmpRoot}/padm-tls" ]]
    [[ "$(adapterTmpPath padm-tls)/acme.sh" == "${tmpRoot}/padm-tls/acme.sh" ]]
    [[ "$(adapterTmpPath padm-tls/acme.sh.download.XXXXXX)" == "${tmpRoot}/padm-tls/acme.sh.download.XXXXXX" ]]
    [[ "$(adapterNginxRepoTemplate)" == "${tmpRoot}/padm-nginx-repo.XXXXXX" ]]
    [[ "$(adapterNginxPinTemplate)" == "${tmpRoot}/padm-nginx-pin.XXXXXX" ]]
    [[ "$(adapterNginxYumRepoTemplate)" == "${tmpRoot}/padm-nginx-yum-repo.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-warp-repo.XXXXXX)" == "${tmpRoot}/padm-warp-repo.XXXXXX" ]]
    [[ "$(adapterTmpPath padm-warp-yum-repo.XXXXXX)" == "${tmpRoot}/padm-warp-yum-repo.XXXXXX" ]]
    [[ "$(accessControlXrayTestLog)" == "${tmpRoot}/padm-access-xray-test.log" ]]
    [[ "$(accessControlSingBoxTestLog)" == "${tmpRoot}/padm-access-sing-box-test.log" ]]
    [[ "$(aloneNginxTestLog)" == "${tmpRoot}/padm-alone-nginx-test.log" ]]
    [[ "$(realityStreamEnableBackupTemplate)" == "${tmpRoot}/padm-reality-stream.XXXXXX" ]]
    [[ "$(realityStreamDisableBackupTemplate)" == "${tmpRoot}/padm-reality-stream-disable.XXXXXX" ]]
    [[ "$(bbrSysctlLog)" == "${tmpRoot}/padm-bbr-sysctl.log" ]]
    [[ "$(bbrStateTempTemplate)" == "${tmpRoot}/padm-bbr-state.XXXXXX" ]]
    [[ "$(bbrSysctlTempTemplate)" == "${tmpRoot}/padm-bbr-sysctl.XXXXXX" ]]
    [[ "$(singBoxVMessHTTPUpgradeNginxTestLog)" == "${tmpRoot}/padm-sing-box-vmess-httpupgrade-nginx-test.log" ]]
    [[ "$(thirdPartyTcpScriptPath)" == "${tmpRoot}/padm-tcpx.sh" ]]
    [[ "$(realityScannerOutputPath 123)" == "${tmpRoot}/padm-realitlscanner-123.csv" ]]
    [[ "$(realityScannerOutputPath 123 sample-2)" == "${tmpRoot}/padm-realitlscanner-123-sample-2.csv" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-xray-test.log)" == "${tmpRoot}/padm-reality-target-xray-test.log" ]]
    [[ "$(realityTargetTmpPath padm-reality-target-sing-box-test.log)" == "${tmpRoot}/padm-reality-target-sing-box-test.log" ]]
    [[ "$(realityTargetTmpPath padm-reality-target.XXXXXX)" == "${tmpRoot}/padm-reality-target.XXXXXX" ]]

    printf '{"ok":true}\n' | writeGeneratedJsonFile "${jsonFile}" padm-runtime-json
    jq -e '.ok == true' "${jsonFile}" >/dev/null
    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-runtime-json.*'; then
        return 1
    fi
    printf '{"nested":true}\n' | writeGeneratedJsonFile "${nestedJsonFile}" padm-runtime-json
    jq -e '.nested == true' "${nestedJsonFile}" >/dev/null

    crontab() {
        printf '%s\n' "$1" >"${crontabPathMarker}"
        grep -qxF '15 1 * * * echo ok' "$1"
    }
    installUserCrontabContent $'\n15 1 * * * echo ok\n'
    [[ "$(<"${crontabPathMarker}")" == "${tmpRoot}"/padm-crontab.* ]]
    if regressionFindHasMatches "${tmpRoot}" -mindepth 1 -maxdepth 1 -name 'padm-crontab.*'; then
        return 1
    fi

    if [[ -n "${oldTmpDir}" ]]; then export TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runAutoReadUnsetAutoInstallRegression() (
    local value=
    unset AUTO_INSTALL AUTO_INSTALL_TYPE
    autoRead regression_unset_auto_install "请输入:" value <<<"manual-value"
    [[ "${value}" == "manual-value" ]]
)

runMenuReadChoiceRegression() (
    local value=previous
    set +e
    menuReadChoice regression_menu_eof "请选择:" value </dev/null
    local readStatus=$?
    set -e
    [[ "${readStatus}" -ne 0 ]]
    [[ -z "${value}" ]]

    value=previous
    set +e
    menuReadChoice regression_menu_empty "请选择:" value < <(printf '\n')
    readStatus=$?
    set -e
    [[ "${readStatus}" -ne 0 ]]
    [[ -z "${value}" ]]

    value=previous
    menuReadChoice regression_menu_allow_empty "请选择:" value true < <(printf '\n')
    [[ -z "${value}" ]]

    AUTO_INSTALL=true
    AUTO_INSTALL_TYPE=reality
    AUTO_INSTALL_SUMMARY_SHOWN=
    value=previous
    menuReadChoice install_type "请选择:" value </dev/null
    [[ "${value}" == "3" ]]
    unset AUTO_INSTALL AUTO_INSTALL_TYPE AUTO_INSTALL_SUMMARY_SHOWN

    (
        tuicAlgorithm=
        lastInstallationConfig=
        initTuicProtocol <<<""
        [[ "${tuicAlgorithm}" == "cubic" ]]
        tuicAlgorithm=
        regressionExpectStatus 1 initTuicProtocol </dev/null
        [[ -z "${tuicAlgorithm}" ]]
    )
    (
        realityEntryHost=entry.example.com
        realityTargetHost=
        AUTO_REALITY_TARGET=
        regressionExpectStatus 1 collectRealityProfile </dev/null
        [[ -z "${realityTargetHost}" ]]
    )
)

runInstallWorkflowRegression() (
    local renderedIds= errors=0 shown=0 cleaned=0 cleanStatus=0
    local answer inputFd nextInput output apply
    unset AUTO_INSTALL AUTO_INSTALL_TYPE AUTO_INSTALL_SUMMARY_SHOWN AUTO_PROTOCOLS AUTO_REUSE_LAST AUTO_DOMAIN AUTO_PORT
    echoContent() { :; }
    menuLine() { :; }
    menuMutedLine() { :; }
    menuSection() { :; }
    menuClose() { :; }
    statusCard() { :; }
    menuItem() { renderedIds+="$1"$'\n'; }
    protocolMenuDescription() { printf 'regression'; }
    errorCard() { errors=$((errors + 1)); }
    showAutoInstallSummary() { :; }
    showLastInstallationConfig() { shown=$((shown + 1)); }
    cleanLastInstallationConfig() { cleaned=$((cleaned + 1)); return "${cleanStatus}"; }

    (
        # 同一会话重新检测安装状态，不能沿用旧核心路径或 Reality 标记。
        # shellcheck source=/dev/null
        source "${PROJECT_ROOT}/shell/core/state.sh"
        local root="${TMP_DIR}/install-state-refresh"
        local coreInstallType= ctlPath=stale realityStatus=12 customPort=
        local configPath= singBoxConfigPath= frontingType=02_VLESS_TCP_inbounds
        local PADM_XRAY_BINARY="${root}/xray"
        local PADM_XRAY_CONF_DIR="${root}/reality"
        local PADM_SINGBOX_BINARY="${root}/sing-box"
        local PADM_SINGBOX_CONFIG_DIR="${root}/sing-box-config"
        mkdir -p "${PADM_XRAY_CONF_DIR}" "${root}/tls" "${PADM_SINGBOX_CONFIG_DIR}"
        cp /usr/bin/true "${PADM_XRAY_BINARY}"
        cp /usr/bin/true "${PADM_SINGBOX_BINARY}"
        printf '{}\n' >"${PADM_XRAY_CONF_DIR}/07_VLESS_vision_reality_inbounds.json"
        printf '{}\n' >"${PADM_XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json"
        readInstallType
        [[ "${coreInstallType}" == 1 && "${ctlPath}" == "${PADM_XRAY_BINARY}" && "${realityStatus}" == 12 ]]

        PADM_XRAY_CONF_DIR="${root}/tls"
        printf '{"inbounds":[{"port":8443}]}\n' >"${PADM_XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json"
        readInstallType
        [[ "${coreInstallType}" == 1 && -z "${realityStatus}" ]]
        readCustomPort
        [[ "${customPort}" == 8443 ]]
        printf '{"inbounds":[{"port":443}]}\n' >"${PADM_XRAY_CONF_DIR}/02_VLESS_TCP_inbounds.json"
        readCustomPort
        [[ -z "${customPort}" ]]

        PADM_XRAY_CONF_DIR="${root}/grpc"
        mkdir -p "${PADM_XRAY_CONF_DIR}"
        local storedClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"alice"},{"id":"22222222-2222-4222-8222-222222222222","email":"bob"}]'
        printf '{"inbounds":[{"settings":{"clients":%s}}]}\n' "${storedClients}" >"${PADM_XRAY_CONF_DIR}/08_VLESS_vision_gRPC_inbounds.json"
        readInstallType
        currentInstallProtocolType=",26,"
        frontingType=
        customPort=8443
        readCustomPort
        [[ -z "${customPort}" ]]
        readConfigHostPathUUID
        [[ "${currentUUID}" == 11111111-1111-4111-8111-111111111111 ]]
        [[ "$(jq -c . <<<"${currentClients}")" == "${storedClients}" ]]
        lastInstallationConfig=true
        local inputFd nextInput
        exec {inputFd}< <(printf 'next-parent-action\n')
        coreTemplateCollectInitialClients xray <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && "$(jq -c . <<<"${currentClients}")" == "${storedClients}" ]]
        exec {inputFd}<&-

        PADM_XRAY_CONF_DIR="${root}/missing-xray"
        printf '{}\n' >"${PADM_SINGBOX_CONFIG_DIR}/07_VLESS_vision_reality_inbounds.json"
        readInstallType
        [[ "${coreInstallType}" == 2 && "${ctlPath}" == "${PADM_SINGBOX_BINARY}" && -z "${realityStatus}" ]]

        PADM_SINGBOX_CONFIG_DIR="${root}/missing-sing-box"
        readInstallType
        [[ -z "${coreInstallType}${ctlPath}${configPath}${singBoxConfigPath}${realityStatus}" ]]
        customPort=8443
        readCustomPort
        [[ -z "${customPort}" ]]
    )

    # 纠错只读取当前安装输入，中文逗号与两位协议号都使用真实能力库校验。
    exec {inputFd}< <(printf '999\n1，2\nnext-parent-action\n')
    selectCoreInstallProtocols xray <&"${inputFd}"
    [[ "${selectCustomInstallType}" == ",1,2," && "${errors}" == "1" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-
    selectCoreInstallProtocols sing-box <<<"31"
    [[ "${selectCustomInstallType}" == ",31," ]]

    renderedIds=
    exec {inputFd}< <(printf 'next-parent-action\n')
    selectCoreInstallProtocols xray "1,21" <&"${inputFd}"
    [[ "${selectCustomInstallType}" == ",1,21," ]]
    [[ "${renderedIds}" == $'1\n21\n' ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-
    regressionExpectStatus 1 selectCoreInstallProtocols sing-box 2 </dev/null
    [[ -z "${selectCustomInstallType}" ]]

    selectCustomInstallType=previous
    regressionExpectStatus 1 selectCoreInstallProtocols xray </dev/null
    [[ -z "${selectCustomInstallType}" ]]
    selectCustomInstallType=previous
    regressionExpectStatus 1 selectCoreInstallProtocols xray < <(printf 'invalid')
    [[ -z "${selectCustomInstallType}" ]]
    exec {inputFd}< <(printf '\nnext-parent-action\n')
    regressionExpectStatus 1 selectCoreInstallProtocols xray <&"${inputFd}"
    [[ -z "${selectCustomInstallType}" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-

    AUTO_PROTOCOLS=999
    for AUTO_INSTALL in true 1 false; do
        exec {inputFd}< <(printf '1\nnext-parent-action\n')
        regressionExpectStatus 1 selectCoreInstallProtocols xray <&"${inputFd}"
        [[ -z "${selectCustomInstallType}" ]]
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == "1" ]]
        exec {inputFd}<&-
    done
    AUTO_PROTOCOLS="1，31"
    selectCoreInstallProtocols sing-box </dev/null
    [[ "${selectCustomInstallType}" == ",1,31," ]]
    unset AUTO_INSTALL AUTO_PROTOCOLS

    configPath=
    lastInstallationConfig=true
    exec {inputFd}< <(printf 'next-parent-action\n')
    readLastInstallationConfig <&"${inputFd}"
    [[ -z "${lastInstallationConfig}" && "${shown}" == "0" && "${cleaned}" == "0" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-

    configPath=/regression/installed/
    for answer in "" y Y yes YES true True 1; do
        lastInstallationConfig=previous
        readLastInstallationConfig <<<"${answer}"
        [[ "${lastInstallationConfig}" == "true" && "${cleaned}" == "0" ]]
    done
    for answer in n N no NO false False 0; do
        cleaned=0
        lastInstallationConfig=previous
        currentHost=old.example.com
        currentUUID=old-user
        currentClients='[{"id":"old-user"}]'
        customPort=8443
        readLastInstallationConfig <<<"${answer}"
        [[ -z "${lastInstallationConfig}${currentHost}${currentUUID}${currentClients}${customPort}" && "${cleaned}" == "0" ]]
        [[ "${PADM_INSTALL_RESET_HISTORY}" == true ]]
    done
    cleaned=0
    shown=0
    exec {inputFd}< <(printf 'maybe\n\nnext-parent-action\n')
    readLastInstallationConfig <&"${inputFd}"
    [[ "${lastInstallationConfig}" == "true" && "${cleaned}" == "0" && "${shown}" == "1" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-
    lastInstallationConfig=previous
    regressionExpectStatus 1 readLastInstallationConfig </dev/null
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    lastInstallationConfig=previous
    cleaned=0
    regressionExpectStatus 1 readLastInstallationConfig < <(printf 'n')
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    readLastInstallationConfig <<<"n"
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    cleanStatus=1
    cleaned=0
    readLastInstallationConfig <<<"n"
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    cleanStatus=0
    cleaned=0

    for AUTO_INSTALL in true 1 false; do
        unset AUTO_REUSE_LAST
        readLastInstallationConfig </dev/null
        [[ "${lastInstallationConfig}" == "true" && "${cleaned}" == "0" ]]
    done
    AUTO_REUSE_LAST=maybe
    for AUTO_INSTALL in true 1 false; do
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 readLastInstallationConfig <&"${inputFd}"
        [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == "next-parent-action" ]]
        exec {inputFd}<&-
    done
    AUTO_REUSE_LAST=yes
    readLastInstallationConfig </dev/null
    [[ "${lastInstallationConfig}" == "true" ]]
    AUTO_REUSE_LAST=no
    readLastInstallationConfig </dev/null
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    unset AUTO_INSTALL AUTO_REUSE_LAST

    (
        # 重新填写后取消两核安装，证书、订阅、服务和 ACME 文件必须原样保留。
        local root="${TMP_DIR}/install-reset-inputs" file before core protocols events=
        local PADM_INSTALL_RESET_HISTORY=false
        local PADM_REALITY_ENTRY_HOST_FILE="${root}/reality_entry_host"
        mkdir -p "${root}/tls" "${root}/subscribe" "${root}/services" "${root}/home/.acme.sh" "${root}/conf"
        for file in tls/example.crt tls/example.key subscribe/user services/xray.service home/.acme.sh/account.conf conf/inbound.json reality_entry_host; do
            printf 'old.example.com\n' >"${root}/${file}"
        done
        before=$(find "${root}" -type f -exec sha256sum {} + | LC_ALL=C sort)
        configPath="${root}/conf/"
        showLastInstallationConfig() {
            currentHost=old.example.com
            currentUUID=11111111-1111-4111-8111-111111111111
            currentClients='[{"id":"11111111-1111-4111-8111-111111111111"}]'
            currentPath=old-path
            customPort=8443
            realityPort=10001
            realityGrpcPort=10002
            xHTTPort=10003
            singBoxVLESSRealityVisionSNI=old-target.example.com
        }
        cleanLastInstallationConfig() { events+=$'cleanup\n'; return 1; }
        installTools() { events+=$'tools\n'; return 1; }
        coreTemplateConfigBackupCreate() { events+=$'backup\n'; return 1; }
        nginxRunning() { return 1; }
        for core in xray sing-box; do
            apply=customXrayInstall
            protocols=21
            [[ "${core}" != sing-box ]] || { protocols=3; apply=customSingBoxInstall; }
            regressionExpectStatus 1 "${apply}" "${protocols}" < <(printf 'n\n\n')
            [[ -z "${events}${currentHost}${currentUUID}${currentClients}${currentPath}${customPort}${realityPort}${realityGrpcPort}${xHTTPort}${singBoxVLESSRealityVisionSNI}" ]]
            [[ "${PADM_INSTALL_RESET_HISTORY}" == false && "${configPath}" == "${root}/conf/" ]]
            [[ "$(find "${root}" -type f -exec sha256sum {} + | LC_ALL=C sort)" == "${before}" ]]
        done

        # 重填不能从磁盘捡回旧入口；显式自动参数仍优先，管理路径仍可读取原入口。
        readLastInstallationConfig <<<"n"
        realityOnlyWithDomain=true
        unset AUTO_ENTRY_HOST AUTO_DOMAIN
        regressionExpectStatus 1 collectEntryProfile <<<""
        [[ -z "${realityEntryHost}" ]]
        AUTO_DOMAIN=new.example.com
        AUTO_UUID=22222222-2222-4222-8222-222222222222
        AUTO_USER=new-user
        AUTO_PORT=9443
        readLastInstallationConfig <<<"n"
        collectEntryProfile </dev/null
        coreTemplateCollectInitialClients xray </dev/null
        [[ "${realityEntryHost}" == new.example.com && "$(jq -r '.[0].id' <<<"${currentClients}")" == "${AUTO_UUID}" && "${AUTO_PORT}" == 9443 ]]
        currentClients=
        coreTemplateCollectInitialClients sing-box </dev/null
        [[ "$(jq -r '.[0].uuid' <<<"${currentClients}")" == "${AUTO_UUID}" ]]
        currentClients=
        coreTemplateCollectInitialClients sing-box true </dev/null
        [[ "$(jq -r '.[0].password' <<<"${currentClients}")" == "${AUTO_UUID}" ]]
        unset AUTO_DOMAIN AUTO_UUID AUTO_USER AUTO_PORT
        PADM_INSTALL_RESET_HISTORY=false
        collectEntryProfile </dev/null
        [[ "${realityEntryHost}" == old.example.com ]]
    )

    (
        # 协议和模式在事务外确认；取消不能触发原事务的备份、回滚或服务恢复。
        local core install input mode events= selectionErrors=0 inputFd nextInput xrayState=true singBoxState=true
        local PADM_CORE_TEMPLATE_TRANSACTION_ACTIVE=
        unset AUTO_INSTALL AUTO_PROTOCOLS AUTO_REALITY_DOMAIN
        coreSelectionErrorCard() { selectionErrors=$((selectionErrors + 1)); }
        protocolSelectionShowRiskNotes() { :; }
        coreTemplateConfigBackupCreate() {
            events+=$'backup\n'
            printf -v "$1" '%s' "${TMP_DIR}/install-selection-backup"
        }
        coreSwitchCleanupBackupCreate() { printf -v "$1" '%s' ""; }
        checkLogBackupRestore() { events+=$'rollback\n'; }
        padmRemoveCleanupPath() { :; }
        nginxRunning() { return 0; }
        xrayRunning() { [[ "${xrayState}" == true ]]; }
        singBoxRunning() { [[ "${singBoxState}" == true ]]; }
        handleXray() { events+="xray:$1"$'\n'; xrayState=false; [[ "$1" != start ]] || xrayState=true; }
        handleSingBox() { events+="sing-box:$1"$'\n'; singBoxState=false; [[ "$1" != start ]] || singBoxState=true; }
        handleNginx() { events+="nginx:$1"$'\n'; }
        padmRunPortAllowTransaction() { "$@"; }
        readLastInstallationConfig() { events+=$'read-last\n'; return 0; }
        collectEntryProfile() { events+=$'entry\n'; }
        coreTemplateCollectInitialClients() { events+=$'clients\n'; }
        installTools() { events+=$'tools\n'; return 1; }
        for core in xray sing-box; do
            install=customXrayInstall
            [[ "${core}" != sing-box ]] || install=customSingBoxInstall
            for input in "" $'\n' $'1\n' $'1\n2'; do
                events=
                regressionExpectStatus 1 "${install}" < <(printf '%s' "${input}")
                [[ -z "${events}" ]]
            done
            exec {inputFd}< <(printf '\nnext-parent-action\n')
            regressionExpectStatus 1 "${install}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ -z "${events}" && "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-

            # 纠错只读取当前字段；回车保留普通模式，后续 Apply 不再重复选择。
            for mode in "" 2; do
                events=
                selectionErrors=0
                exec {inputFd}< <(printf '999\n1\n9\n%s\nnext-parent-action\n' "${mode}")
                regressionExpectStatus 1 "${install}" <&"${inputFd}"
                read -r -u "${inputFd}" nextInput
                [[ "${selectCustomInstallType}" == ,1, && "${nextInput}" == next-parent-action && "${selectionErrors}" == 1 ]]
                [[ "${events}" == $'read-last\nentry\nclients\nbackup\ntools\n'"${core}:stop"$'\nrollback\n'"${core}:start"$'\n' ]]
                if [[ "${mode}" == 2 ]]; then
                    [[ "${realityOnlyWithDomain}" == true ]]
                else
                    [[ -z "${realityOnlyWithDomain}" ]]
                fi
                exec {inputFd}<&-
            done
        done
    )

    (
        # 双核心尚未清理时只验证安装目标，不能误读旧核心的运行状态。
        local checks= detections=0 state=false core
        local PADM_CHECK_GFW_SERVICE_ATTEMPTS=1 PADM_CHECK_GFW_SERVICE_INTERVAL=0
        readInstallType() { detections=$((detections + 1)); coreInstallType=1; }
        xrayRunning() { checks+=xray; [[ "${core}" == xray && "${state}" == true || "${core}" == sing-box ]]; }
        singBoxRunning() { checks+=sing-box; [[ "${core}" == sing-box && "${state}" == true || "${core}" == xray ]]; }
        for core in xray sing-box; do
            checks=
            state=false
            regressionExpectStatus 1 checkGFWStatue 1 "${core}"
            [[ "${checks}" == "${core}" && "${detections}" == 0 ]]
            checks=
            state=true
            checkGFWStatue 1 "${core}"
            [[ "${checks}" == "${core}" && "${detections}" == 0 ]]
        done
    )

    # 六个入口先确认历史和连接地址；取消不进入事务，重填标记只在本次安装可见。
    (
        local install input events= historyReads=0 inputFd nextInput
        local configPath=/regression/installed/ currentHost= btDomain= domain=
        local PADM_INSTALL_RESET_HISTORY=parent-value
        unset AUTO_INSTALL AUTO_PROTOCOLS AUTO_REUSE_LAST AUTO_DOMAIN AUTO_ENTRY_HOST
        AUTO_REALITY_DOMAIN=yes
        showLastInstallationConfig() {
            historyReads=$((historyReads + 1))
            currentHost=old.example.com
            realityEntryHost=old.example.com
        }
        nginxRunning() { events+=$'nginx\n'; return 0; }
        handleNginx() { events+=$'service\n'; }
        coreTemplateCollectInitialClients() { :; }
        readInstallTLSPort() { :; }
        coreSwitchConfigTransaction() { events+="transaction:${PADM_INSTALL_RESET_HISTORY}"$'\n'; return 17; }
        for install in installXrayReality installSingBoxReality customXrayInstall customSingBoxInstall xrayCoreInstall singBoxInstall; do
            for input in "" n $'n\n' $'n\n\n'; do
                events=
                historyReads=0
                regressionExpectStatus 1 "${install}" 1 domain < <(printf '%s' "${input}")
                [[ -z "${events}" && "${historyReads}" == 1 && "${PADM_INSTALL_RESET_HISTORY}" == parent-value ]]
            done
            AUTO_INSTALL=false
            AUTO_REUSE_LAST=no
            AUTO_ENTRY_HOST=new.example.com
            AUTO_DOMAIN=new.example.com
            events=
            historyReads=0
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 17 "${install}" 1 domain <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${events}" == $'transaction:true\n' && "${historyReads}" == 1 ]]
            [[ "${nextInput}" == next-parent-action && "${PADM_INSTALL_RESET_HISTORY}" == parent-value ]]
            if [[ "${selectCustomInstallType}" == ,1, ]]; then
                [[ "${realityEntryHost}" == new.example.com ]]
            else
                [[ "${domain}" == new.example.com ]]
            fi
            exec {inputFd}<&-
            unset AUTO_INSTALL AUTO_REUSE_LAST AUTO_ENTRY_HOST AUTO_DOMAIN
        done

        # 面板路径仍跳过全量和 Xray 域名页；sing-box 自定义 TLS 仍需确认域名。
        btDomain=panel.example.com
        unset AUTO_REALITY_DOMAIN
        local tlsReads=0
        readLastInstallationConfig() { return 0; }
        readInstallTLSDomain() { tlsReads=$((tlsReads + 1)); return 1; }
        for install in xrayCoreInstall singBoxInstall customXrayInstall; do
            regressionExpectStatus 17 "${install}" 21 </dev/null
            [[ "${tlsReads}" == 0 && "${PADM_INSTALL_RESET_HISTORY}" == parent-value ]]
        done
        events=
        regressionExpectStatus 1 customSingBoxInstall 3 </dev/null
        [[ "${tlsReads}" == 1 && -z "${events}" && "${PADM_INSTALL_RESET_HISTORY}" == parent-value ]]
    )

    (
        # 账号在六个入口的事务前确认；取消不动服务，模板阶段不再读取同一份输入。
        local install input inputFd nextInput events= currentUUID= currentClients= lastInstallationConfig=
        local configPath= btDomain= PADM_INSTALL_CLIENTS_PREPARED=parent-value
        local -a installs=(installXrayReality installSingBoxReality customXrayInstall customSingBoxInstall xrayCoreInstall singBoxInstall)
        unset AUTO_INSTALL AUTO_UUID AUTO_USER AUTO_REALITY_DOMAIN
        readLastInstallationConfig() { currentUUID=; currentClients=; lastInstallationConfig=; }
        configureRealityDomainMode() { :; }
        collectEntryProfile() { :; }
        readInstallTLSDomain() { :; }
        readInstallTLSPort() { :; }
        nginxRunning() { events+=$'nginx\n'; return 1; }
        coreSwitchConfigTransaction() {
            [[ "${PADM_INSTALL_CLIENTS_PREPARED}" == true ]]
            events+=$'transaction\n'
            shift
            "$@"
        }
        padmRunPortAllowTransaction() { "$@"; }
        collectTLSProfile() { tlsCertDomain=tls.example.com; }
        writeGeneratedJsonFile() { events+=$'write\n'; return 1; }
        addXrayOutbound() { events+=$'write\n'; return 1; }
        readSingBoxPortResult() { events+=$'write\n'; return 1; }
        installTools() {
            unset -f jq
            events+=$'tools\n'
            selectCustomInstallType=,27,
            if [[ "${install}" == *SingBox* || "${install}" == singBox* ]]; then
                initSingBoxConfigApply custom 1
            else
                initXrayConfigApply custom 1
            fi
        }
        for install in "${installs[@]}"; do
            jq() { return 127; }
            for input in "" $'11111111-1111-4111-8111-111111111111\n' $'11111111-1111-4111-8111-111111111111\ninvalid/name\n'; do
                events=
                regressionExpectStatus 1 "${install}" 28 < <(printf '%s' "${input}")
                [[ -z "${events}${currentClients}" && "${PADM_INSTALL_CLIENTS_PREPARED}" == parent-value ]]
            done
            events=
            exec {inputFd}< <(printf '11111111-1111-4111-8111-111111111111\nalice\nnext-parent-action\n')
            regressionExpectStatus 1 "${install}" 28 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && "${events}" == $'transaction\ntools\nwrite\n' ]]
            [[ "${PADM_INSTALL_CLIENTS_PREPARED}" == parent-value ]]
            [[ -z "${AUTO_UUID:-}${AUTO_USER:-}" ]]
            jq -e '.[0] | (.id // .uuid) == "11111111-1111-4111-8111-111111111111" and (.email // .name) == "alice"' <<<"${currentClients}" >/dev/null
            exec {inputFd}<&-
        done
    )

    (
        # 公共 TLS 端口先确认；取消或非法自动参数不能备份、下载或改动服务。
        local install input inputFd nextInput events= port= btDomain= domain=
        local currentHost= currentPort= customPort= lastInstallationConfig=
        local AUTO_PORT= AUTO_DOMAIN=tls.example.com
        readLastInstallationConfig() { lastInstallationConfig=; }
        coreTemplateCollectInitialClients() { :; }
        configureRealityDomainMode() { :; }
        protocolSelectionShowRiskNotes() { :; }
        nginxRunning() { return 1; }
        coreSwitchConfigTransaction() { events+=$'backup\n'; shift; "$@"; }
        padmRunPortAllowTransaction() { "$@"; }
        installTools() { events+=$'tools\n'; }
        installTLS() { events+=$'tls\n'; return 1; }
        installSingBox() { events+=$'download\n'; return 1; }
        handleNginx() { events+="nginx:$1"$'\n'; }
        handleXray() { events+="xray:$1"$'\n'; }
        allowPort() { events+="allow:$1"$'\n'; }
        checkDNSIP() { :; }
        removeNginxDefaultConf() { :; }
        checkPortOpen() { :; }
        for install in customXrayInstall xrayCoreInstall singBoxInstall; do
            btDomain= selectCoreType=1
            [[ "${install}" != singBoxInstall ]] || { btDomain=panel.example.com; selectCoreType=2; }
            for input in "" $'1+2\n'; do
                events=
                regressionExpectStatus 1 "${install}" 28 < <(printf '%s' "${input}")
                [[ -z "${events}${AUTO_PORT}" ]]
            done
            AUTO_PORT=1+2
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 "${install}" 28 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && -z "${events}" && "${AUTO_PORT}" == 1+2 ]]
            exec {inputFd}<&-
            AUTO_PORT=
            events=
            exec {inputFd}< <(printf '1+2\n8443\nnext-parent-action\n')
            regressionExpectStatus 1 "${install}" 28 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && "${port}" == 8443 && -z "${AUTO_PORT}" ]]
            [[ "${events}" == $'backup\ntools\nallow:8443\n'* ]]
            exec {inputFd}<&-
        done
    )

    (
        local events= expected input inputFd nextInput
        local currentHost= currentPort= customPort= domain= port=
        local lastInstallationConfig= btDomain= xrayVLESSRealityPort= selectCoreType=1
        progressCard() { :; }
        handleNginx() { events+="nginx:$1"$'\n'; }
        allowPort() { events+="allow:$1"$'\n'; }
        checkDNSIP() { events+="dns:$1"$'\n'; }
        removeNginxDefaultConf() { events+=$'clean\n'; }
        checkPortOpen() { events+="check:$1:$2"$'\n'; }

        # 取消、截断和非法输入不能停服务或继续检测，也不能吃掉上级菜单输入。
        for input in "" tls.example.com; do
            regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf '%s' "${input}")
            [[ -z "${events}" ]]
        done
        exec {inputFd}< <(printf '\nnext-parent-action\n')
        regressionExpectStatus 1 initTLSNginxConfig 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && -z "${events}" ]]
        exec {inputFd}<&-
        regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf 'tls.example.com\n')
        [[ -z "${events}" ]]
        regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf 'tls.example.com\n8443')
        [[ -z "${events}" ]]
        AUTO_DOMAIN=invalid/domain
        regressionExpectStatus 1 initTLSNginxConfig 1 </dev/null
        AUTO_DOMAIN=tls.example.com
        AUTO_PORT=1+2
        regressionExpectStatus 1 initTLSNginxConfig 1 </dev/null
        [[ -z "${events}" ]]
        unset AUTO_DOMAIN AUTO_PORT
        exec {inputFd}< <(printf 'invalid/domain\ntls.example.com\n1+2\n8443\nnext-parent-action\n')
        initTLSNginxConfig 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${domain}" == tls.example.com && "${port}" == 8443 && "${nextInput}" == next-parent-action ]]
        [[ "${events}" == $'allow:8443\ndns:tls.example.com\nclean\ncheck:8443:tls.example.com\nnginx:stop\n' ]]
        exec {inputFd}<&-
        events=
        regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf 'invalid/domain\n')
        [[ -z "${domain}" && -z "${events}" ]]
        regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf 'tls.example.com\n1+2\n')
        [[ -z "${port}" && -z "${events}" ]]

        # 不再先问是否复用，再分别问域名和端口是否复用。
        currentHost=old.example.com
        currentPort=443
        exec {inputFd}< <(printf '\n\nnext-parent-action\n')
        initTLSNginxConfig 1 <&"${inputFd}"
        [[ "${domain}" == old.example.com && "${port}" == 443 && "${events}" == $'nginx:stop\n' ]]
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action ]]
        exec {inputFd}<&-
        events=
        exec {inputFd}< <(printf 'invalid/domain\n\n1+2\n\nnext-parent-action\n')
        initTLSNginxConfig 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${domain}" == old.example.com && "${port}" == 443 &&
            "${nextInput}" == next-parent-action && "${events}" == $'nginx:stop\n' ]]
        exec {inputFd}<&-
        events=
        currentHost=invalid/domain
        AUTO_INSTALL=false
        AUTO_DOMAIN=
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 initTLSNginxConfig 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && -z "${domain}" && -z "${events}" ]]
        exec {inputFd}<&-
        unset AUTO_INSTALL AUTO_DOMAIN
        currentHost=old.example.com
        lastInstallationConfig=true
        initTLSNginxConfig 1 </dev/null
        [[ "${domain}" == old.example.com && "${port}" == 443 && "${events}" == $'nginx:stop\n' ]]
        events=
        currentPort=1+2
        regressionExpectStatus 1 initTLSNginxConfig 1 </dev/null
        [[ -z "${events}" ]]
        currentPort=443

        (
            # 坏历史字段原地修正，不清空用户，也不能在取消或纠错期间改服务。
            local currentHost=invalid/domain currentPort=1+2 domain= port= events=
            local currentClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"alice"}]'
            local beforeClients=${currentClients}
            exec {inputFd}< <(printf 'still/invalid\nfixed.example.com\n1+2\n8443\nnext-parent-action\n')
            initTLSNginxConfig 1 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && "${currentClients}" == "${beforeClients}" ]]
            [[ "${domain}" == fixed.example.com && "${port}" == 8443 ]]
            [[ "${events}" == $'allow:8443\ndns:fixed.example.com\nclean\ncheck:8443:fixed.example.com\nnginx:stop\n' ]]
            exec {inputFd}<&-
            events=
            exec {inputFd}< <(printf '\nnext-parent-action\n')
            regressionExpectStatus 1 initTLSNginxConfig 1 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && -z "${events}" && "${currentClients}" == "${beforeClients}" ]]
            exec {inputFd}<&-
            regressionExpectStatus 1 initTLSNginxConfig 1 < <(printf 'fixed.example.com\n')
            [[ -z "${events}" && "${currentClients}" == "${beforeClients}" ]]
            AUTO_DOMAIN=invalid/domain AUTO_PORT=1+2
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 initTLSNginxConfig 1 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && -z "${events}" ]]
            exec {inputFd}<&-
        )

        # 显式参数覆盖历史值；仅改域名也重新验证，成功后才停 Nginx。
        AUTO_DOMAIN=new.example.com
        AUTO_PORT=8443
        initTLSNginxConfig 1 </dev/null
        expected=$'allow:8443\ndns:new.example.com\nclean\ncheck:8443:new.example.com\nnginx:stop\n'
        [[ "${domain}" == new.example.com && "${port}" == 8443 && "${events}" == "${expected}" ]]
        events=
        unset AUTO_PORT
        initTLSNginxConfig 1 </dev/null
        expected=$'allow:443\ndns:new.example.com\nclean\ncheck:443:new.example.com\nnginx:stop\n'
        [[ "${port}" == 443 && "${events}" == "${expected}" ]]
        events=
        checkPortOpen() { events+="check:$1:$2"$'\n'; return 1; }
        regressionExpectStatus 1 initTLSNginxConfig 1 </dev/null
        [[ "${events}" == "${expected%nginx:stop$'\n'}" ]]
        unset AUTO_DOMAIN

        events=
        currentHost=
        currentPort=
        domain=panel.example.com
        btDomain=panel.example.com
        lastInstallationConfig=
        customPortFunction <<<""
        validPortNumber "${port}"
        [[ "${port}" -ge 10000 && "${port}" -le 30000 && "${events}" == "allow:${port}"$'\n' ]]
        events=
        btDomain=
        currentHost=${domain}
        customPort=8443
        lastInstallationConfig=true
        customPortFunction </dev/null
        [[ "${port}" == 8443 && -z "${events}" ]]
    )

    (
        # 四个 TLS 安装入口先确认域名；取消或参数错误不能创建备份或开始依赖安装。
        local apply events= currentHost= currentPort= customPort= btDomain= domain=
        local lastInstallationConfig= selectCoreType= selectCustomInstallType=,28, inputFd nextInput
        unset AUTO_INSTALL AUTO_DOMAIN AUTO_PORT
        readLastInstallationConfig() { :; }
        coreTemplateCollectInitialClients() { :; }
        configureRealityDomainMode() { :; }
        protocolSelectionShowRiskNotes() { :; }
        installTools() { events+="tools:${domain}"$'\n'; }
        installTLS() { events+=$'tls\n'; return 1; }
        coreSwitchConfigTransaction() { events+=$'backup\n'; shift; "$@"; }
        padmRunPortAllowTransaction() { "$@"; }
        nginxRunning() { return 1; }
        handleNginx() { events+="nginx:$1"$'\n'; }
        allowPort() { events+="allow:$1"$'\n'; }
        checkDNSIP() { :; }
        removeNginxDefaultConf() { :; }
        checkPortOpen() { :; }
        for apply in customXrayInstall customSingBoxInstall xrayCoreInstall singBoxInstall; do
            events=
            selectCoreType=2
            [[ "${apply}" != *Xray* && "${apply}" != xray* ]] || selectCoreType=1
            regressionExpectStatus 1 "${apply}" 28 </dev/null
            [[ -z "${events}" && -z "${domain}" ]]
            AUTO_DOMAIN=invalid/domain
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 "${apply}" 28 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action && -z "${events}" && -z "${domain}" ]]
            exec {inputFd}<&-
            unset AUTO_DOMAIN
            if [[ "${selectCoreType}" == 1 ]]; then
                exec {inputFd}< <(printf 'invalid/domain\ntls.example.com\n443\nnext-parent-action\n')
            else
                exec {inputFd}< <(printf 'invalid/domain\ntls.example.com\nnext-parent-action\n')
            fi
            regressionExpectStatus 1 "${apply}" 28 <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${domain}" == tls.example.com && "${nextInput}" == next-parent-action ]]
            [[ "${events}" == $'backup\ntools:tls.example.com\n'* && "${events}" == *$'nginx:stop\ntls\n' ]]
            exec {inputFd}<&-
        done
    )

    (
        local installCalls=0
        readLastInstallationConfig() { :; }
        readInstallTLSDomain() { domain=tls.example.com; }
        collectEntryProfile() { :; }
        configureRealityDomainMode() { :; }
        protocolSelectionShowRiskNotes() { :; }
        installTools() { installCalls=$((installCalls + 1)); return 1; }
        installXray() { printf 'unexpected-install\n'; }
        installSingBox() { printf 'unexpected-install\n'; }
        initTLSNginxConfig() { printf 'unexpected-install\n'; }
        customPortFunction() { printf 'unexpected-install\n'; }
        coreInstallServiceAction() { printf 'unexpected-install\n'; }
        for apply in installXrayRealityApply installSingBoxRealityApply customXrayInstallApply customSingBoxInstallApply xrayCoreInstallApply singBoxInstallApply; do
            output=$(
                installCalls=0
                selectCustomInstallType=,1,
                regressionExpectStatus 1 "${apply}" 1 || exit 1
                printf 'install-calls:%s\n' "${installCalls}"
            )
            grep -qxF 'install-calls:1' <<<"${output}"
            ! grep -qF 'unexpected-install' <<<"${output}" || exit 1
        done
    )

    (
        local serviceCalls=0 allowCalls=0
        local btDomain=panel.example.com domain=panel.example.com
        local currentHost= currentPort= customPort= lastInstallationConfig= xrayVLESSRealityPort=
        readLastInstallationConfig() { :; }
        configureRealityDomainMode() { :; }
        protocolSelectionShowRiskNotes() { :; }
        installTools() { :; }
        handleXray() { serviceCalls=$((serviceCalls + 1)); }
        allowPort() { allowCalls=$((allowCalls + 1)); }
        for apply in customXrayInstallApply xrayCoreInstallApply singBoxInstallApply; do
            selectCustomInstallType=,21,
            unset AUTO_PORT
            regressionExpectStatus 1 "${apply}" 21 </dev/null
            AUTO_PORT=1+2
            regressionExpectStatus 1 "${apply}" 21 </dev/null
            [[ "${serviceCalls}" == 0 && "${allowCalls}" == 0 ]]
        done
    )

    (
        local networkReads=0 invalidKey
        lastInstallationConfig=true
        hysteria2BandwidthMode=brutal
        hysteria2ClientDownloadSpeed=240
        hysteria2ClientUploadSpeed=90
        hysteria2ObfsType=salamander
        hysteria2ObfsPassword=stored-secret
        hysteria2Masquerade=https://masquerade.example.com
        getSingBoxCurrentVersion() { printf '1.14.0'; }
        autoRead() { networkReads=$((networkReads + 1)); return 1; }
        initHysteria2Network </dev/null
        [[ "${networkReads}" == "0" && "${hysteria2ClientDownloadSpeed}" == "240" && "${hysteria2ClientUploadSpeed}" == "90" ]]
        [[ "${hysteria2ObfsPassword}" == stored-secret && "${hysteria2Masquerade}" == https://masquerade.example.com ]]
        hysteria2ClientDownloadSpeed=invalid
        regressionExpectStatus 1 initHysteria2Network
        hysteria2BandwidthMode=bbr
        hysteria2ClientDownloadSpeed=
        hysteria2ClientUploadSpeed=
        initHysteria2Network
        getSingBoxCurrentVersion() { printf '1.10.0'; }
        regressionExpectStatus 1 initHysteria2Network
        getSingBoxCurrentVersion() { printf '1.14.0'; }

        # 复用其他协议时新增 Hysteria2，仍需采集新协议参数。
        hysteria2BandwidthMode=
        hysteria2ObfsType=
        hysteria2ObfsPassword=
        hysteria2Masquerade=
        autoRead() {
            networkReads=$((networkReads + 1))
            case "$1" in
            hysteria_bandwidth_mode) printf -v "$3" '%s' 2 ;;
            *) printf -v "$3" '%s' "" ;;
            esac
        }
        initHysteria2Network
        [[ "${networkReads}" == "3" && "${hysteria2BandwidthMode}" == bbr ]]

        hysteria2BandwidthMode=
        autoRead() { return 1; }
        regressionExpectStatus 1 initHysteria2Network </dev/null
        AUTO_INSTALL=true
        autoRead() {
            if [[ "$1" == "${invalidKey}" ]]; then
                printf -v "$3" '%s' invalid
            elif [[ "$1" == hysteria_bandwidth_mode ]]; then
                printf -v "$3" '%s' 1
            else
                printf -v "$3" '%s' 100
            fi
        }
        for invalidKey in hysteria_bandwidth_mode hysteria_download_speed hysteria_upload_speed; do
            hysteria2BandwidthMode=
            regressionExpectStatus 1 initHysteria2Network
        done
    )

    (
        # 重装编辑回车保留原值；非法字段原地纠正，不重新填写已确认的带宽和密码。
        local inputFd nextInput errors=0
        unset AUTO_INSTALL
        lastInstallationConfig=
        hysteria2BandwidthMode=brutal
        hysteria2ClientDownloadSpeed=240
        hysteria2ClientUploadSpeed=90
        hysteria2ObfsType=salamander
        hysteria2ObfsPassword=stored-secret
        hysteria2Masquerade=https://masquerade.example.com
        getSingBoxCurrentVersion() { printf '1.14.0'; }
        errorCard() { errors=$((errors + 1)); }
        exec {inputFd}< <(printf '\ninvalid\n\n\ninvalid\n\n\ninvalid\n\nnext-parent-action\n')
        initHysteria2Network <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${nextInput}" == next-parent-action && "${errors}" == 2 ]]
        [[ "${hysteria2BandwidthMode}" == brutal && "${hysteria2ClientDownloadSpeed}" == 240 && "${hysteria2ClientUploadSpeed}" == 90 ]]
        [[ "${hysteria2ObfsType}" == salamander && "${hysteria2ObfsPassword}" == stored-secret && "${hysteria2Masquerade}" == https://masquerade.example.com ]]
        exec {inputFd}< <(printf '2\noff\noff\nnext-parent-action\n')
        initHysteria2Network <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${nextInput}" == next-parent-action && "${hysteria2BandwidthMode}" == bbr &&
            -z "${hysteria2ClientDownloadSpeed}${hysteria2ClientUploadSpeed}${hysteria2ObfsType}${hysteria2ObfsPassword}${hysteria2Masquerade}" ]]
        hysteria2Masquerade=https://masquerade.example.com
        regressionExpectStatus 1 initHysteria2Network < <(printf '\n\ninvalid')
        [[ "${hysteria2Masquerade}" == https://masquerade.example.com ]]

        AUTO_INSTALL=true
        local invalidKey
        autoRead() {
            case "$1" in
            hysteria_bandwidth_mode) printf -v "$3" '%s' 2 ;;
            "${invalidKey}") printf -v "$3" '%s' invalid ;;
            *) printf -v "$3" '%s' "" ;;
            esac
        }
        for invalidKey in hysteria_obfs_type hysteria_masquerade; do
            hysteria2ObfsType=
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 initHysteria2Network <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${nextInput}" == next-parent-action ]]
        done
    )

    (
        # 一个选择同时完成算法保留或修改；错误编号不再静默降为 cubic。
        local inputFd nextInput errors=0 algorithm
        unset AUTO_INSTALL
        lastInstallationConfig=
        errorCard() { errors=$((errors + 1)); }
        for algorithm in cubic bbr new_reno; do
            tuicAlgorithm=${algorithm}
            exec {inputFd}< <(printf '\nnext-parent-action\n')
            initTuicProtocol <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${tuicAlgorithm}" == "${algorithm}" && "${nextInput}" == next-parent-action ]]
            regressionExpectStatus 1 initTuicProtocol < <(printf '2')
            [[ "${tuicAlgorithm}" == "${algorithm}" ]]
            lastInstallationConfig=true
            initTuicProtocol </dev/null
            [[ "${tuicAlgorithm}" == "${algorithm}" ]]
            lastInstallationConfig=
        done
        exec {inputFd}< <(printf '9\n2\nnext-parent-action\n')
        initTuicProtocol <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${tuicAlgorithm}" == bbr && "${nextInput}" == next-parent-action && "${errors}" == 1 ]]
        tuicAlgorithm=invalid
        lastInstallationConfig=true
        initTuicProtocol <<<"3"
        [[ "${tuicAlgorithm}" == new_reno && "${errors}" == 2 ]]
        AUTO_INSTALL=true
        tuicAlgorithm=invalid
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 initTuicProtocol <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${nextInput}" == next-parent-action && "${tuicAlgorithm}" == invalid ]]
    )

    (
        local tuicJson=
        lastInstallationConfig=true
        currentUUID=11111111-1111-4111-8111-111111111111
        currentClients='[{"uuid":"11111111-1111-4111-8111-111111111111","name":"regression"}]'
        selectCustomInstallType=",31,"
        singBoxTuicPort=
        tuicAlgorithm=bbr
        tuicAuthTimeout=8s
        tuicHeartbeat=20s
        tuicZeroRttHandshake=true
        collectTLSProfile() { tlsCertDomain=tls.example.com; }
        readSingBoxPortResult() { local -n ports=$1; ports=(443); }
        setSniffRouting() { return 0; }
        autoRead() { return 1; }
        writeGeneratedJsonFile() { tuicJson=$(cat); }
        initSingBoxConfigApply custom 1 true >/dev/null
        jq -e '.inbounds[0] | .congestion_control == "bbr" and .auth_timeout == "8s" and .heartbeat == "20s" and .zero_rtt_handshake == true' <<<"${tuicJson}" >/dev/null
        tuicAuthTimeout=
        tuicHeartbeat=
        tuicZeroRttHandshake=
        initSingBoxConfigApply custom 1 true >/dev/null
        jq -e '.inbounds[0] | .auth_timeout == "3s" and .heartbeat == "10s" and .zero_rtt_handshake == false' <<<"${tuicJson}" >/dev/null
    )

    (
        # 安装目标优先于旧核心；切换 Xray 不写 sing-box 密钥，选择也不泄漏到父菜单。
        local core targetType input inputFd nextInput calls="${TMP_DIR}/install-target-key-calls"
        local selectCoreType=parent-choice coreInstallType= targetCore=
        local currentRealityPrivateKey= currentRealityPublicKey= realityPrivateKey= realityPublicKey=
        local lastInstallationConfig= keyFile="${TMP_DIR}/install-target-reality-key"
        unset AUTO_INSTALL
        prepareCoreInstallInputs() {
            [[ "$1" == "${targetCore}" && "${selectCoreType}" == "${targetType}" &&
                "${coreInstallType}" != "${targetType}" ]]
        }
        coreSwitchConfigTransaction() { shift; "$@"; }
        padmRunPortAllowTransaction() { "$@"; }
        coreXrayBinaryPath() { printf xrayKeyTool; }
        coreSingBoxBinaryPath() { printf singBoxKeyTool; }
        realityKeyFile() { printf '%s\n' "${keyFile}"; }
        xrayKeyTool() {
            [[ "$*" == "x25519 -i manual-seed" ]] || return 1
            printf 'xray\n' >>"${calls}"
            printf 'PrivateKey: xray-private\nPassword (PublicKey): xray-public\n'
        }
        singBoxKeyTool() {
            [[ "$*" == "generate reality-keypair" ]] || return 1
            printf 'sing-box\n' >>"${calls}"
            printf 'PrivateKey: singbox-private\nPublicKey: singbox-public\n'
        }
        for core in xray sing-box; do
            targetCore=${core}
            targetType=1
            coreInstallType=2
            [[ "${core}" != sing-box ]] || { targetType=2; coreInstallType=1; }
            printf 'old-public\n' >"${keyFile}"
            : >"${calls}"
            realityPrivateKey=
            realityPublicKey=
            exec {inputFd}< <(printf 'manual-seed\nnext-parent-action\n')
            runCoreInstall "${core}" initRealityKey <&"${inputFd}"
            [[ "${selectCoreType}" == parent-choice && "${coreInstallType}" != "${targetType}" && "$(<"${calls}")" == "${core}" ]]
            if [[ "${core}" == xray ]]; then
                [[ "${realityPrivateKey}" == xray-private && "${realityPublicKey}" == xray-public && "$(<"${keyFile}")" == old-public ]]
            else
                read -r -u "${inputFd}" nextInput
                [[ "${nextInput}" == manual-seed && "$(<"${keyFile}")" == publicKey:singbox-public ]]
            fi
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${nextInput}" == next-parent-action ]]
        done
        selectCoreType=
        coreInstallType=2
        realityPrivateKey=
        realityPublicKey=
        : >"${calls}"
        initRealityKey </dev/null
        [[ "$(<"${calls}")" == sing-box && "$(<"${keyFile}")" == publicKey:singbox-public ]]

        # 管理入口直接调用模板，也必须忽略父菜单残留的选择。
        local template PADM_INSTALL_CLIENTS_PREPARED=false
        currentClients=
        collectTLSProfile() { :; }
        coreTemplateCollectInitialClients() {
            [[ "${selectCoreType}" == "${targetType}" ]] || return 1
            initRealityKey || return 1
            return 1
        }
        for template in initXrayConfigApply initSingBoxConfigApply; do
            selectCoreType=2
            targetType=1
            [[ "${template}" != initSingBoxConfigApply ]] || { selectCoreType=1; targetType=2; }
            local parentType=${selectCoreType}
            realityPrivateKey=
            realityPublicKey=
            : >"${calls}"
            regressionExpectStatus 1 "${template}" custom 1 true <<<"manual-seed"
            [[ "${selectCoreType}" == "${parentType}" && -s "${calls}" ]]
        done

        # EOF 或无换行的输入都不能生成密钥、写文件或保留截断的私钥。
        selectCoreType=1
        coreInstallType=2
        realityPrivateKey=
        realityPublicKey=
        : >"${calls}"
        for input in "" manual-seed; do
            regressionExpectStatus 1 initRealityKey < <(printf '%s' "${input}")
            [[ -z "${realityPrivateKey}${realityPublicKey}" && ! -s "${calls}" ]]
        done
        currentRealityPrivateKey=stored-private
        currentRealityPublicKey=stored-public
        regressionExpectStatus 1 initRealityKey </dev/null
        [[ -z "${realityPrivateKey}${realityPublicKey}" && ! -s "${calls}" ]]
    )

    (
        # 协议已删除时，重新读取不能留下本轮会话中的旧参数。
        singBoxConfigPath="${TMP_DIR}/install-without-tuic/"
        mkdir -p "${singBoxConfigPath}"
        tuicAlgorithm=bbr
        tuicAuthTimeout=8s
        tuicHeartbeat=20s
        tuicZeroRttHandshake=true
        readSingBoxConfig
        [[ -z "${tuicAlgorithm}${tuicAuthTimeout}${tuicHeartbeat}${tuicZeroRttHandshake}" ]]
    )

    (
        local core targetCore passwordMode nextInput inputFd result selectCustomInstallType=,28,
        local oldClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"old-user"}]'
        local testUuid=22222222-2222-4222-8222-222222222222
        local generationLog="${TMP_DIR}/install-initial-client-generation.log"
        generateRandomUuidValue() { printf 'generated\n' >>"${generationLog}"; printf '%s' "${testUuid}"; }
        for core in xray sing-box password; do
            targetCore=${core}
            passwordMode=false
            if [[ "${core}" == password ]]; then
                targetCore=sing-box
                passwordMode=true
            fi
            currentClients=${oldClients}
            currentUUID=11111111-1111-4111-8111-111111111111
            lastInstallationConfig=true
            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" </dev/null
            [[ "${currentClients}" == "${oldClients}" ]]
            lastInstallationConfig=
            exec {inputFd}< <(printf 'maybe\n\nnext-parent-action\n')
            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${currentClients}" == "${oldClients}" && "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-

            # 原地纠正当前字段；用户名纠错不能重读已经确认的 UUID。
            if [[ "${passwordMode}" == true ]]; then
                exec {inputFd}< <(printf 'n\narbitrary-secret\ninvalid/name\nsub_reserved\nalice\nnext-parent-action\n')
            else
                exec {inputFd}< <(printf 'n\nnot-a-uuid\n%s\ninvalid/name\nsub_reserved\nalice\nnext-parent-action\n' "${testUuid}")
            fi
            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action ]]
            if [[ "${core}" == xray ]]; then
                jq -e --arg uuid "${testUuid}" '.[0].id == $uuid and .[0].email == "alice"' <<<"${currentClients}" >/dev/null
            elif [[ "${passwordMode}" == true ]]; then
                jq -e '.[0].password == "arbitrary-secret" and .[0].name == "alice"' <<<"${currentClients}" >/dev/null
            else
                jq -e --arg uuid "${testUuid}" '.[0].uuid == $uuid and .[0].name == "alice"' <<<"${currentClients}" >/dev/null
            fi
            exec {inputFd}<&-

            currentClients=${oldClients}
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" </dev/null
            [[ "${currentClients}" == "${oldClients}" ]]
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" < <(printf 'n\n%s\ninvalid/name\n' "${testUuid}")
            [[ "${currentClients}" == "${oldClients}" ]]
            if [[ "${passwordMode}" != true ]]; then
                regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" < <(printf 'n\nnot-a-uuid\n')
                [[ "${currentClients}" == "${oldClients}" ]]
            fi

            currentClients='[]'
            currentUUID=
            : >"${generationLog}"
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" </dev/null
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" < <(printf '%s' "${testUuid}")
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" <<<"${testUuid}"
            regressionExpectStatus 1 coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" < <(printf '%s\nalice' "${testUuid}")
            [[ "${currentClients}" == '[]' && ! -s "${generationLog}" ]]

            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" < <(printf '\n\n')
            [[ "$(grep -c '^generated$' "${generationLog}")" == 1 ]]
            if [[ "${core}" == xray ]]; then
                jq -e --arg uuid "${testUuid}" '.[0].id == $uuid and .[0].email == "padm-22222222-VLESS_TCP/TLS_Vision"' <<<"${currentClients}" >/dev/null
            elif [[ "${passwordMode}" == true ]]; then
                jq -e --arg uuid "${testUuid}" '.[0].password == $uuid and .[0].name == "padm-22222222-singbox_hysteria2"' <<<"${currentClients}" >/dev/null
            else
                jq -e --arg uuid "${testUuid}" '.[0].uuid == $uuid and .[0].name == "padm-22222222-VLESS_TCP/TLS_Vision"' <<<"${currentClients}" >/dev/null
            fi
            currentClients='[]'
            AUTO_INSTALL=true
            : >"${generationLog}"
            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" </dev/null
            [[ "$(grep -c '^generated$' "${generationLog}")" == 1 ]]
            result=${currentClients}
            currentUUID=${testUuid}
            : >"${generationLog}"
            coreTemplateCollectInitialClients "${targetCore}" "${passwordMode}" </dev/null
            [[ "${currentClients}" == "${result}" && ! -s "${generationLog}" ]]
            unset AUTO_INSTALL
        done

        currentClients='[{"password":"stored-secret","name":"old-user"}]'
        currentUUID=
        lastInstallationConfig=true
        : >"${generationLog}"
        coreTemplateCollectInitialClients sing-box true </dev/null
        jq -e '.[0].password == "stored-secret" and .[0].name == "old-user"' <<<"${currentClients}" >/dev/null
        [[ ! -s "${generationLog}" ]]
        # 两核重装复用密码型用户，不依赖不存在的 UUID 字段。
        currentClients='[{"password":"alice-secret","name":"alice"},{"password":"bob-secret","name":"bob"}]'
        result=${currentClients}
        for core in xray sing-box; do
            coreTemplateCollectInitialClients "${core}" </dev/null
            [[ "${currentClients}" == "${result}" && ! -s "${generationLog}" ]]
        done
        selectCustomInstallType=,1,
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 coreTemplateCollectInitialClients sing-box <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && "${currentClients}" == "${result}" && ! -s "${generationLog}" ]]
        exec {inputFd}<&-
        # 首个 UUID 不能掩盖其余用户的不兼容凭据。
        currentUUID=11111111-1111-4111-8111-111111111111
        currentClients='[{"id":"11111111-1111-4111-8111-111111111111","email":"alice"},{"password":"bob-secret","name":"bob"}]'
        result=${currentClients}
        regressionExpectStatus 1 coreTemplateCollectInitialClients xray </dev/null
        [[ "${currentClients}" == "${result}" && ! -s "${generationLog}" ]]
        currentUUID=
        currentClients='[{"password":"11111111-1111-4111-8111-111111111111","name":"alice"},{"password":"22222222-2222-4222-8222-222222222222","name":"bob"}]'
        result=${currentClients}
        coreTemplateCollectInitialClients sing-box </dev/null
        [[ "${currentClients}" == "${result}" && ! -s "${generationLog}" ]]
        lastInstallationConfig=
        currentClients='[]'
        coreTemplateCollectInitialClients sing-box true < <(printf 'arbitrary-secret\nalice\n')
        jq -e '.[0].password == "arbitrary-secret" and .[0].name == "alice"' <<<"${currentClients}" >/dev/null
        currentClients='[]'
        AUTO_UUID=${testUuid}
        AUTO_USER=alice
        coreTemplateCollectInitialClients xray </dev/null
        jq -e --arg uuid "${testUuid}" '.[0].id == $uuid and .[0].email == "alice"' <<<"${currentClients}" >/dev/null
        result=${currentClients}
        AUTO_USER=sub_reserved
        regressionExpectStatus 1 coreTemplateCollectInitialClients xray <<<"n"
        [[ "${currentClients}" == "${result}" ]]
        AUTO_UUID=invalid
        AUTO_USER=alice
        exec {inputFd}< <(printf 'n\n%s\nnext-parent-action\n' "${testUuid}")
        regressionExpectStatus 1 coreTemplateCollectInitialClients xray <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == "${testUuid}" && "${currentClients}" == "${result}" ]]
        exec {inputFd}<&-
        AUTO_UUID=${testUuid}
        AUTO_USER=alice
        (
            jq() { return 1; }
            regressionExpectStatus 1 coreTemplateCollectInitialClients xray </dev/null
            [[ "${currentClients}" == "${result}" ]]
        )
        unset AUTO_UUID AUTO_USER
    )

    (
        local apply writeCalls=0
        currentUUID=
        currentClients='[]'
        lastInstallationConfig=
        collectTLSProfile() { tlsCertDomain=tls.example.com; }
        writeGeneratedJsonFile() { writeCalls=$((writeCalls + 1)); return 1; }
        for apply in initXrayConfigApply initSingBoxConfigApply; do
            regressionExpectStatus 1 "${apply}" custom 1 true </dev/null
            regressionExpectStatus 1 "${apply}" custom 1 true <<<"11111111-1111-4111-8111-111111111111"
        done
        [[ "${writeCalls}" == 0 && "${currentClients}" == '[]' ]]
    )

    (
        # 子安装取消后仍可操作主面板；自动安装保留原失败码且不读后续输入。
        local nextInput inputFd followupCalls=0 installCalls=0 coreInstallType=
        unset AUTO_INSTALL AUTO_PROTOCOLS AUTO_INSTALL_TYPE
        mkdirTools() { :; }
        aliasInstall() { :; }
        checkWgetShowProgress() { :; }
        getScriptVersion() { :; }
        showInstallStatus() { :; }
        customXrayInstall() { selectCoreInstallProtocols xray; }
        manageSubscription() { followupCalls=$((followupCalls + 1)); }
        menu < <(printf '1\n5\n1\n\n2\n')
        [[ "${followupCalls}" == 1 ]]
        installMenu() { installCalls=$((installCalls + 1)); return 17; }
        for AUTO_INSTALL in true 1 false; do
            installCalls=0
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 17 menu <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${installCalls}" == 1 && "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-
        done
        unset AUTO_INSTALL
    )

    (
        local route= value= nextInput inputFd invalid flag core alias coreInstallType=
        customXrayInstall() { route=xray; }
        customSingBoxInstall() { route=sing-box; }
        xrayCoreInstall() { route=traditional-xray; }
        singBoxInstall() { route=traditional-sing-box; }
        for core in xray sing-box; do
            parseInstallArgs --core "${core}" --protocols 1
            autoInstallValidateRequiredInputs
            autoRead install_type "请选择:" value </dev/null
            [[ "${value}" == 5 ]]
            exec {inputFd}< <(printf 'next-parent-action\n')
            installMenu <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            [[ "${route}" == "${core}" && "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-
            for alias in install full traditional 1; do
                parseInstallArgs --core "${core}" --install-type "${alias}"
                [[ -z "${AUTO_PROTOCOLS}" ]]
                autoInstallValidateRequiredInputs
                [[ "$(autoValueForKey install_type)" == 6 ]]
                exec {inputFd}< <(printf 'next-parent-action\n')
                installMenu <&"${inputFd}"
                read -r -u "${inputFd}" nextInput
                [[ "${route}" == "traditional-${core}" && "${nextInput}" == next-parent-action ]]
                exec {inputFd}<&-
            done
        done
        for flag in --install-type --core; do
            for invalid in typo 4 6; do
                parseInstallArgs "${flag}" "${invalid}"
                regressionExpectStatus 1 autoInstallValidateRequiredInputs
            done
        done
    )

    (
        local result= outputFile nextInput inputFd transport expected
        local allowLog= selectCustomInstallType=",5,"
        unset AUTO_INSTALL AUTO_PORT
        statusCard() { :; }
        showAutoInstallSummary() { :; }
        errorCard() { :; }
        corePortInputErrorCard() { :; }
        checkPort() { :; }
        allowPort() { allowLog+="${2:-tcp}:${1}"$'\n'; }
        allowPortTcpAndUdp() { allowLog+="tcp+udp:${1}"$'\n'; }

        # 已确认复用时不再询问；未确认时回车保留、显式输入替换，EOF 不开放端口。
        outputFile="${TMP_DIR}/runtime-singbox-port-result"
        lastInstallationConfig=true
        initSingBoxPort 9443 true tcp singbox_custom_port </dev/null >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" == "9443" && -z "${allowLog}" ]]
        exec {inputFd}< <(printf '1+2\n8443\nnext-parent-action\n')
        initSingBoxPort invalid true tcp singbox_custom_port <&"${inputFd}" >"${outputFile}"
        result=$(<"${outputFile}")
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${result}" == 8443 && "${nextInput}" == next-parent-action && "${allowLog}" == $'tcp:8443\n' ]]
        allowLog=
        regressionExpectStatus 1 initSingBoxPort invalid true tcp singbox_custom_port </dev/null
        [[ -z "${allowLog}" ]]
        AUTO_INSTALL=true
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 initSingBoxPort invalid true tcp singbox_custom_port <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${nextInput}" == next-parent-action && -z "${allowLog}" ]]
        unset AUTO_INSTALL
        lastInstallationConfig=
        exec {inputFd}< <(printf '\nnext-parent-action\n')
        initSingBoxPort 9443 true tcp singbox_custom_port <&"${inputFd}" >"${outputFile}"
        result=$(<"${outputFile}")
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${result}" == "9443" && "${nextInput}" == "next-parent-action" && -z "${allowLog}" ]]
        exec {inputFd}< <(printf '8443\nnext-parent-action\n')
        initSingBoxPort 9443 true tcp singbox_custom_port <&"${inputFd}" >"${outputFile}"
        result=$(<"${outputFile}")
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${result}" == "8443" && "${nextInput}" == next-parent-action && "${allowLog}" == $'tcp:8443\n' ]]
        allowLog=
        for result in 9443 ""; do
            regressionExpectStatus 1 initSingBoxPort "${result}" true tcp singbox_custom_port </dev/null
            regressionExpectStatus 1 initSingBoxPort "${result}" true tcp singbox_custom_port < <(printf '8443')
            [[ -z "${allowLog}" ]]
        done
        regressionExpectStatus 1 initSingBoxPort 9443 true tcp singbox_custom_port <<<"1+2"
        [[ -z "${allowLog}" ]]
        for result in "" 8443; do
            exec {inputFd}< <(printf '1+2\n%s\nnext-parent-action\n' "${result}")
            initSingBoxPort 9443 true tcp singbox_custom_port <&"${inputFd}" >"${outputFile}"
            expected=${result:-9443}
            result=$(<"${outputFile}")
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${result}" == "${expected}" && "${nextInput}" == next-parent-action ]]
            if [[ "${expected}" == 9443 ]]; then
                [[ -z "${allowLog}" ]]
            else
                [[ "${allowLog}" == $'tcp:8443\n' ]]
            fi
            allowLog=
        done
        initSingBoxPort "" true tcp singbox_custom_port <<<"" >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" =~ ^[0-9]+$ && "${result}" -ge 10000 && "${result}" -le 60000 &&
            "${allowLog}" == "tcp:${result}"$'\n' ]]
        allowLog=

        # 单选自动参数覆盖历史端口；固定端口和 Reality 共存内部端口优先。
        AUTO_INSTALL=true
        AUTO_PORT=1+2
        exec {inputFd}< <(printf 'next-parent-action\n')
        regressionExpectStatus 1 initSingBoxPort 9443 true tcp singbox_custom_port <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        exec {inputFd}<&-
        [[ "${nextInput}" == next-parent-action && -z "${allowLog}" ]]
        AUTO_PORT=8443
        lastInstallationConfig=true
        initSingBoxPort 9443 true tcp+udp singbox_custom_port </dev/null >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" == "8443" && "${allowLog}" == $'tcp+udp:8443\n' ]]
        allowLog=
        initSingBoxPort 9443 false tcp singbox_custom_port </dev/null >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" == "9443" && "${allowLog}" == $'tcp:9443\n' ]]
        allowLog=
        selectCustomInstallType=",1,"
        resolveRealityInstallCoexistPort() {
            printf -v "$1" '%s' 31300
            return 0
        }
        initSingBoxPort "" true tcp reality_subport 1 vision </dev/null >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" == "31300" && "${allowLog}" == $'tcp:31300\n' ]]
        allowLog=

        # 多选安装不能把同一个 --port 反复套给新入口，且历史入口仍可直接复用。
        selectCustomInstallType=",3,5,"
        lastInstallationConfig=true
        initSingBoxPort 9443 true tcp+udp singbox_custom_port </dev/null >"${outputFile}"
        result=$(<"${outputFile}")
        [[ "${result}" == "9443" && -z "${allowLog}" ]]
        lastInstallationConfig=
        (
            local autoPortSeen= autoReads=0
            autoRead() {
                autoReads=$((autoReads + 1))
                autoPortSeen=${AUTO_PORT:-}
                printf -v "$3" '%s' 15555
            }
            initSingBoxPort "" true tcp+udp singbox_custom_port </dev/null >"${outputFile}"
            result=$(<"${outputFile}")
            [[ "${result}" == "15555" && -z "${autoPortSeen}" && "${autoReads}" == 1 &&
                "${AUTO_PORT}" == "8443" && "${allowLog}" == $'tcp+udp:15555\n' ]]
        )
        unset AUTO_INSTALL AUTO_PORT selectCustomInstallType

        # 三种传输类型分别只开放匹配的协议。
        for transport in tcp udp tcp+udp; do
            allowLog=
            case "${transport}" in
            tcp) expected='tcp:15556' ;;
            udp) expected='udp:15556' ;;
            tcp+udp) expected='tcp+udp:15556' ;;
            esac
            initSingBoxPort "" true "${transport}" singbox_custom_port <<<"15556" >"${outputFile}"
            result=$(<"${outputFile}")
            [[ "${result}" == "15556" && "${allowLog}" == "${expected}"$'\n' ]]
        done
    )

    (
        local -a applies=(initXrayRealityPort initXrayXHTTPort initXrayRealityGrpcPort)
        local -a portVars=(realityPort xHTTPort realityGrpcPort)
        local -a protocolIds=(1 2 26)
        local -a transports=(tcp tcp+udp tcp)
        local index apply portVar answer inputFd nextInput expected checkCalls=0 allowLog=
        local realityPort= xHTTPort= realityGrpcPort= selectCustomInstallType=
        local xrayVLESSRealityPort=9443 xrayVLESSRealityXHTTPort=9443 xrayVLESSRealityGRPCPort=9443
        local lastInstallationConfig=
        unset AUTO_INSTALL AUTO_PORT
        statusCard() { :; }
        errorCard() { :; }
        showAutoInstallSummary() { :; }
        resolveRealityInstallCoexistPort() { return 1; }
        checkPort() { checkCalls=$((checkCalls + 1)); }
        allowPort() { allowLog+="tcp:${1}"$'\n'; }
        allowPortTcpAndUdp() { allowLog+="tcp+udp:${1}"$'\n'; }

        # 三个入口原地纠错；EOF 或截断不能检查、开放端口。
        for index in "${!applies[@]}"; do
            apply=${applies[index]}
            portVar=${portVars[index]}
            selectCustomInstallType=",${protocolIds[index]},"
            for answer in "" 8443; do
                printf -v "${portVar}" '%s' ""
                regressionExpectStatus 1 "${apply}" < <(printf '%s' "${answer}")
                [[ -z "${!portVar}" && "${checkCalls}" == 0 && -z "${allowLog}" ]]
            done
            printf -v "${portVar}" '%s' ""
            regressionExpectStatus 1 "${apply}" < <(printf '1+2\n')
            [[ -z "${!portVar}" && "${checkCalls}" == 0 && -z "${allowLog}" ]]
            for answer in "" 8443; do
                printf -v "${portVar}" '%s' ""
                checkCalls=0
                allowLog=
                exec {inputFd}< <(printf '1+2\n%s\nnext-parent-action\n' "${answer}")
                "${apply}" <&"${inputFd}"
                read -r -u "${inputFd}" nextInput
                exec {inputFd}<&-
                expected="${transports[index]}:${answer:-9443}"
                [[ "${!portVar}" == "${answer:-9443}" && "${checkCalls}" == 1 &&
                    "${allowLog}" == "${expected}"$'\n' && "${nextInput}" == next-parent-action ]]
            done

            # 单选显式端口优先于历史；自动参数不能落入后续交互。
            printf -v "${portVar}" '%s' ""
            checkCalls=0
            allowLog=
            AUTO_INSTALL=true
            AUTO_PORT=1+2
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 "${apply}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${nextInput}" == next-parent-action && "${checkCalls}" == 0 && -z "${allowLog}" ]]
            printf -v "${portVar}" '%s' ""
            AUTO_PORT=8443
            "${apply}" </dev/null
            [[ "${!portVar}" == 8443 && "${checkCalls}" == 1 &&
                "${allowLog}" == "${transports[index]}:8443"$'\n' ]]
            unset AUTO_INSTALL AUTO_PORT
            checkCalls=0
            allowLog=
        done

        # 坏历史端口可在当前字段补正；自动安装仍拒绝并保留原历史值。
        for index in "${!applies[@]}"; do
            apply=${applies[index]}
            portVar=${portVars[index]}
            selectCustomInstallType=",${protocolIds[index]},"
            xrayVLESSRealityPort=invalid
            xrayVLESSRealityXHTTPort=invalid
            xrayVLESSRealityGRPCPort=invalid
            lastInstallationConfig=true
            printf -v "${portVar}" '%s' ""
            exec {inputFd}< <(printf '1+2\n8443\nnext-parent-action\n')
            "${apply}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${!portVar}" == 8443 && "${nextInput}" == next-parent-action && "${checkCalls}" == 1 &&
                "${allowLog}" == "${transports[index]}:8443"$'\n' && "${xrayVLESSRealityPort}" == invalid ]]
            checkCalls=0
            allowLog=
            printf -v "${portVar}" '%s' ""
            regressionExpectStatus 1 "${apply}" </dev/null
            [[ -z "${!portVar}" && "${checkCalls}" == 0 && -z "${allowLog}" ]]
            AUTO_INSTALL=true
            exec {inputFd}< <(printf 'next-parent-action\n')
            regressionExpectStatus 1 "${apply}" <&"${inputFd}"
            read -r -u "${inputFd}" nextInput
            exec {inputFd}<&-
            [[ "${nextInput}" == next-parent-action && "${checkCalls}" == 0 && -z "${allowLog}" ]]
            unset AUTO_INSTALL
            printf -v "${portVar}" '%s' ""
        done
        lastInstallationConfig=

        # 多选使用各入口的内部端口默认值，不能套用公共 --port。
        AUTO_INSTALL=true
        AUTO_PORT=8443
        selectCustomInstallType=",1,2,26,"
        xrayVLESSRealityPort=
        xrayVLESSRealityXHTTPort=
        xrayVLESSRealityGRPCPort=
        for index in "${!applies[@]}"; do
            portVar=${portVars[index]}
            printf -v "${portVar}" '%s' ""
            checkCalls=0
            allowLog=
            "${applies[index]}" </dev/null
            [[ "${!portVar}" =~ ^[0-9]+$ && "${!portVar}" -ge 10000 && "${!portVar}" -le 30000 &&
                "${checkCalls}" == 1 && "${allowLog}" == "${transports[index]}:${!portVar}"$'\n' ]]
        done
    )

    (
        local events= answer output inputFd nextInput
        local nginxTestVersion=1.13.12 nginxAvailable=true
        local release=debian packageManager=apt upgrade=update removeType=remove rhelLike=false
        local selectCustomInstallType=",24,"
        padmAssertNativeInstallAllowed() { :; }
        progressCard() { :; }
        nginx() { printf 'nginx version: nginx/%s\n' "${nginxTestVersion}" >&2; }
        command() {
            if [[ "$*" == "-v nginx" ]]; then
                [[ "${nginxAvailable}" == true ]]
            else
                builtin command "$@"
            fi
        }
        beginPackageInstallTransaction() { events+=$'begin\n'; PADM_PACKAGE_TRANSACTION_STARTED=true; }
        endPackageInstallTransaction() { events+=$'end\n'; }
        waitAptProcess() { :; }
        initInstallProgress() { :; }
        adapterInstallLogPath() { printf '%s' "${TMP_DIR}/install-tools-preflight.log"; }
        runWithTimeout() { events+="timeout:$*"$'\n'; }
        runPackageCommandWithProgress() { events+=$'update\n'; }
        installBasePackages() { events+=$'base\n'; }
        installOptionalPackageTracked() { :; }
        installNginxTools() { events+=$'nginx-install\n'; }
        installAcmeTool() { events+=$'acme\n'; }

        # 结束标记能识别旧 exit 0；取消不能开始包事务或消费上级输入。
        for answer in n "" yes; do
            output=$(
                local status=0
                events=
                installTools 1 < <(printf '%s' "${answer}") || status=$?
                printf 'result:%s:%s\n' "${status}" "${events}"
            )
            grep -qxF 'result:1:' <<<"${output}"
        done
        events=
        exec {inputFd}< <(printf 'n\nnext-parent-action\n')
        regressionExpectStatus 1 installTools 1 <&"${inputFd}"
        read -r -u "${inputFd}" nextInput
        [[ "${nextInput}" == next-parent-action && -z "${events}" ]]
        exec {inputFd}<&-
        output=$(
            status=0
            installTools 1 <<<"" || status=$?
            printf 'result:%s:%s\n' "${status}" "${events}"
        )
        grep -qxF 'result:1:' <<<"${output}"
        for answer in y Y yes YES true 1; do
            events=
            installTools 1 <<<"${answer}"
            [[ "${events}" == $'begin\ntimeout:120 dpkg --configure -a\nupdate\nbase\ntimeout:300 remove nginx\nnginx-install\nacme\nend\n' ]]
        done
        events=
        selectCustomInstallType=",1,"
        installTools 1 </dev/null
        [[ "${events}" == $'begin\ntimeout:120 dpkg --configure -a\nupdate\nbase\nend\n' ]]
        events=
        selectCustomInstallType=",24,"
        nginxTestVersion=1.24.0
        installTools 1 </dev/null
        [[ "${events}" == $'begin\ntimeout:120 dpkg --configure -a\nupdate\nbase\nacme\nend\n' ]]
        events=
        nginxAvailable=false
        installTools 1 </dev/null
        [[ "${events}" == $'begin\ntimeout:120 dpkg --configure -a\nupdate\nbase\nnginx-install\nacme\nend\n' ]]
        installNginxTools() { return 1; }
        failPackageInstallTransaction() { printf 'failed:%s\n' "$1"; exit 1; }
        for nginxAvailable in true false; do
            nginxTestVersion=1.13.12
            output=$(
                (installTools 1 <<<y; printf 'unexpected-continue\n') || printf 'result:1\n'
            )
            [[ "${output}" == $'failed:Nginx安装失败\nresult:1' ]]
        done
    )

    (
        local core action expected status history
        local PADM_CORE_SWITCH_TRANSACTION_ACTIVE= geoStatus=0
        local statsCapability=supported reInstallXrayStatus=y reInstallSingBoxStatus=y
        lastInstallationConfig=
        readInstallType() { :; }
        progressCard() { :; }
        successCard() { :; }
        xrayInstalled() { return 0; }
        singBoxInstalled() { return 0; }
        singBoxV2rayApiCapability() { printf '%s' "${statsCapability}"; }
        singBoxConfigInstalled() { return 0; }
        coreXrayCurrentVersion() { printf 1.0.0; }
        getSingBoxCurrentVersion() { printf 1.0.0; }
        coreXrayInstallDir() { printf '%s' "${TMP_DIR}"; }
        ensureXrayGeoFiles() { printf 'geo\n'; return "${geoStatus}"; }
        coreLatestReleaseTag() { printf v1.0.1; }
        checkVersionNotEmpty() { [[ -n "$1" ]]; }
        installDownloadedXrayBinary() { printf 'upgrade\n'; }
        installDownloadedSingBoxBinary() { printf 'upgrade\n'; }
        for core in Xray SingBox; do
            action="install${core}"
            # EOF 和截断肯定输入不能准备 Geo、升级核心或继续配置。
            for answer in "" y yes; do
                output=$(
                    status=0
                    "${action}" 1 < <(printf '%s' "${answer}") || status=$?
                    printf 'result:%s\n' "${status}"
                )
                [[ "${output}" == result:1 ]]
            done
            for answer in "" n y Y yes YES true 1; do
                expected=
                [[ "${core}" == Xray ]] && expected+=$'geo\n'
                [[ "$(normalizeYesNo "${answer}")" == y ]] && expected+=$'upgrade\n'
                output=$(
                    "${action}" 1 <<<"${answer}" || exit 1
                    printf 'result:0\n'
                )
                [[ "${output}" == "${expected}result:0" ]]
            done
            lastInstallationConfig=true
            exec {inputFd}< <(printf 'next-parent-action\n')
            output=$("${action}" 1 <&"${inputFd}") || exit 1
            expected=
            [[ "${core}" != Xray ]] || expected=geo
            [[ "${output}" == "${expected}" ]]
            read -r -u "${inputFd}" nextInput
            [[ "${nextInput}" == next-parent-action ]]
            exec {inputFd}<&-
            # 完整重装跳过升级选择；即使重填参数或上次选择 y，也不改变版本。
            PADM_CORE_SWITCH_TRANSACTION_ACTIVE=true
            for history in "" true; do
                lastInstallationConfig=${history}
                exec {inputFd}< <(printf 'next-parent-action\n')
                output=$("${action}" 1 <&"${inputFd}") || exit 1
                [[ "${output}" == "${expected}" ]]
                read -r -u "${inputFd}" nextInput
                [[ "${nextInput}" == next-parent-action ]]
                exec {inputFd}<&-
            done
            PADM_CORE_SWITCH_TRANSACTION_ACTIVE= lastInstallationConfig=
        done
        PADM_CORE_SWITCH_TRANSACTION_ACTIVE=true
        statsCapability=unsupported
        [[ "$(installSingBox 1 </dev/null)" == upgrade ]]
        geoStatus=1
        output=$(installXray 1 </dev/null) && return 1
        [[ "${output}" == geo ]]
    )
)

runRuntimeAndRealityRegression() {
    local oldCurrentClients="${currentClients:-}"
    local xhttpClients
    local realityGrpcClients
    local visionClients

    visionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${visionLink}" == "vless://uuid-a@node.example.com:443?encryption=none&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    visionEncLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "pqv" "user-a" "mlkem768x25519plus.native.0rtt.test")
    [[ "${visionEncLink}" == "vless://uuid-a@node.example.com:443?encryption=mlkem768x25519plus.native.0rtt.test&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    visionLink=$(serializeVlessRealityVisionLink "uuid-a" "2001:db8::10" "443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${visionLink}" == "vless://uuid-a@[2001:db8::10]:443?encryption=none&security=reality&pqv=pqv&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a" ]]
    grpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "" "user-a")
    [[ "${grpcLink}" == "vless://uuid-a@node.example.com:8443?encryption=none&security=reality&type=grpc&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#user-a" ]]
    grpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "2001:db8::10" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a")
    [[ "${grpcLink}" == "vless://uuid-a@[2001:db8::10]:8443?encryption=none&security=reality&pqv=pqv&type=grpc&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&path=grpc&serviceName=grpc#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/xHTTP" "pubkey" "user-a")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=www.microsoft.com&fp=chrome&path=/xHTTP&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom" "pubkey" "user-a" none "front.example.com" "stream-one")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=front.example.com&fp=chrome&path=/custom&mode=stream-one&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom" "pubkey" "user-a" none "front.example.com" "stream-one" "pqv")
    [[ "${xhttpLink}" == "vless://uuid-a@cdn.example.com:443?encryption=none&security=reality&pqv=pqv&type=xhttp&sni=www.microsoft.com&host=front.example.com&fp=chrome&path=/custom&mode=stream-one&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    xhttpLink=$(serializeVlessRealityXHTTPLink "uuid-a" "2001:db8::10" "443" "www.microsoft.com" "/xHTTP" "pubkey" "user-a")
    [[ "${xhttpLink}" == "vless://uuid-a@[2001:db8::10]:443?encryption=none&security=reality&type=xhttp&sni=www.microsoft.com&host=www.microsoft.com&fp=chrome&path=/xHTTP&pbk=pubkey&sid=6ba85179e30d4fc2#user-a" ]]
    realityEntryHost=
    currentHost=
    domain=2001:db8::30
    [[ "$(realityEntryHost)" == "2001:db8::30" ]]
    currentClients='[{"id":"uuid-a","email":"user-a"}]'
    xhttpClients=$(initXrayClients 2)
    jq -e '.[0].email == "user-a-VLESS_Reality_XHTTP" and (.[0].flow | not)' <<<"${xhttpClients}" >/dev/null
    realityGrpcClients=$(initXrayClients 26)
    jq -e '.[0].email == "user-a-vless_reality_grpc" and (.[0].flow | not)' <<<"${realityGrpcClients}" >/dev/null
    visionClients=$(initXrayClients 27)
    jq -e '.[0].email == "user-a-VLESS_TCP/TLS_Vision" and .[0].flow == "xtls-rprx-vision"' <<<"${visionClients}" >/dev/null
    currentClients="${oldCurrentClients}"
    domain=tls.example.com
    currentHost=
    collectTLSProfile
    [[ "${tlsCertDomain}" == "tls.example.com" ]]
    [[ "${tlsSNI}" == "tls.example.com" ]]
    protocolMeta 1 security | grep -qx reality
    protocolMeta 1 transport | grep -qx tcp
    protocolMeta 1 needs_reality | grep -qx 1
    ! protocolSelectionNeedsCertificate 1
    protocolSelectionNeedsCertificate 3
    protocolMeta 3 needs_udp | grep -qx 1
    protocolCapabilityMeta 1 transport | grep -qx tcp
    protocolCapabilityMeta 1 security | grep -qx reality

    parseInstallArgs --install-type custom --core xray --protocols 1 --domain node.example.com --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --entry-host node.example.com --reuse-last no
    [[ "${AUTO_REALITY_TARGET}" == "www.microsoft.com:443" ]]
    [[ "${AUTO_REALITY_SERVER_NAME}" == "www.microsoft.com" ]]
    [[ "${AUTO_ENTRY_HOST}" == "node.example.com" ]]
    [[ "$(autoValueForKey reality_target)" == "www.microsoft.com:443" ]]
    [[ "$(autoValueForKey install_type)" == "5" ]]
    validateGitHubReleaseTag "v26.3.27"
    validateGitHubReleaseTag "202605082251"
    validateGitHubReleaseTag "release-2026.05.08"
    ! validateGitHubReleaseTag "../bad"
    ! validateGitHubReleaseTag "bad/tag"
    geoTmpDir="${TMP_DIR}/geo"
    mkdir -p "${geoTmpDir}"
    printf 'geoip' >"${geoTmpDir}/geoip.dat"
    printf 'geosite' >"${geoTmpDir}/geosite.dat"
    ensureXrayGeoFiles "${geoTmpDir}"
    [[ "$(<"${geoTmpDir}/geoip.dat")" == "geoip" ]]
    [[ "$(<"${geoTmpDir}/geosite.dat")" == "geosite" ]]
    printf 'v20260513' >"${geoTmpDir}/geo.version"
    [[ "$(xrayGeoDisplayVersion "${geoTmpDir}")" == "版本 v20260513" ]]
    rm -f "${geoTmpDir}/geo.version"
    [[ "$(xrayGeoDisplayVersion "${geoTmpDir}")" == 更新时间* || "$(xrayGeoDisplayVersion "${geoTmpDir}")" == "版本未知" ]]

    padmIsValidConnectAddress "example.org"
    padmIsValidConnectAddress "203.0.113.10"
    padmIsValidConnectAddress "2001:db8::1"
    ! padmIsValidConnectAddress "bad host"
    ! padmIsValidConnectAddress $'bad\nhost'
    ! padmIsValidConnectAddress "2001:::1"

    AUTO_REALITY_SERVER_NAME=
    parseRealityTargetInput "example.com"
    [[ "${realityTargetHost}" == "example.com" ]]
    [[ "${realityTargetPort}" == "443" ]]
    parseRealityTargetInput "example.org:8443"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    ! parseRealityTargetInput $'bad","extra":"x:443'
    ! parseRealityTargetInput "bad host:443"
    AUTO_REALITY_SERVER_NAME=$'bad"\nname'
    ! parseRealityTargetInput "example.net:443"
    AUTO_REALITY_SERVER_NAME=www.example.net
    parseRealityTargetInput "example.net:443"
    [[ "${realitySNI}" == "www.example.net" ]]
    AUTO_ENTRY_HOST=$'bad\nentry'
    ! collectEntryProfile
    AUTO_ENTRY_HOST=entry.example.com
    collectEntryProfile
    [[ "${realityEntryHost}" == "entry.example.com" ]]
    AUTO_ENTRY_HOST=
    AUTO_REALITY_SERVER_NAME=
    parseRealityTargetInput "example.org:8443"
    ! parseRealityTargetInput "bad.example.org:70000"
    [[ "${realityTargetHost}" == "example.org" ]]
    [[ "${realityTargetPort}" == "8443" ]]
    [[ "${realitySNI}" == "example.org" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "A" ]]
    showRealityTargetQuality "runtime.example.com:443"
    [[ "$(realityTargetResultCount)" -ge "1" ]]
    cachedLine=$(awk -F'\t' '$1 == "runtime.example.com:443" {print; found=1; exit} END {exit found ? 0 : 1}' "${PADM_REALITY_TARGET_RESULTS_FILE}")
    [[ "$(realityTargetResultField "${cachedLine}" 6)" == "192.0.2.1" ]]
    [[ "$(realityTargetResultField "${cachedLine}" 7)" == "AS64500" ]]
    [[ "$(realityTargetResultField "${cachedLine}" 8)" == "ExampleNet" ]]
    [[ "$(realityTargetResultField "${cachedLine}" 9)" == "same_asn" ]]
    [[ "$(printf '%s\n' "${cachedLine}" | awk -F'\t' '{print $10}')" == "A" ]]
    grep -qxF "tls ping -ip 192.0.2.1 runtime.example.com:443" "${REALITY_TLS_PING_ARGS_FILE}"
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 2048')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "B" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "C" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging with SNI\nTLS version: TLS 1.2\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "FAIL" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging without SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096\nPinging with SNI\nTLS version: TLS 1.3\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "C" ]]
    scoreLine=$(scoreRealityTargetFromTlsPing $'Pinging without SNI\nTLS Post-Quantum key exchange: X25519MLKEM768\nTLS version: TLS 1.3\nCertificate chain total length: 4096\nPinging with SNI\nTLS version: TLS 1.2\nCertificate chain total length: 4096')
    [[ "$(printf '%s\n' "${scoreLine}" | awk -F'\t' '{print $1}')" == "FAIL" ]]
}

runAutoInstallRealityRouteRegression() (
    local actions=
    local output=
    local oldCoreInstallType="${coreInstallType:-}"

    recordMenuAction() {
        actions+="$1"$'\n'
    }
    assertMenuAction() {
        grep -qxF "$1" <<<"${actions}"
    }

    parseInstallArgs --install-type reality --core xray --reality-target www.microsoft.com:443 --reality-server-name www.microsoft.com --reuse-last no
    AUTO_INSTALL_SUMMARY_SHOWN=
    selectInstallType=
    coreInstallType=

    uiStyle() { printf '%s' "$2"; }
    menuLine() { output+="$*"$'\n'; }
    menuMutedLine() { output+="$*"$'\n'; }
    menuSection() { :; }
    menuItem() { output+="$2 $3"$'\n'; }
    menuRecommendedItem() { output+="$2 $3"$'\n'; }
    menuDangerItem() { output+="$2 $3"$'\n'; }
    menuReturnItem() { output+="$2 $3"$'\n'; }
    statusCard() { recordMenuAction "statusCard:$1"; }
    successCard() { recordMenuAction "successCard:$1"; }
    runSubscriptionGroupSync() { recordMenuAction "runSubscriptionGroupSync:$*"; }
    errorCard() { recordMenuAction "errorCard:$1"; }
    showInstallStatus() { recordMenuAction showInstallStatus; }
    checkWgetShowProgress() { return 0; }
    mkdirTools() { recordMenuAction mkdirTools; return 0; }
    aliasInstall() { recordMenuAction aliasInstall; return 0; }
    getScriptVersion() { printf 'test\n'; }
    installXrayReality() { recordMenuAction installXrayReality; }
    installSingBoxReality() { recordMenuAction installSingBoxReality; }
    xrayCoreInstall() { recordMenuAction xrayCoreInstall; }
    singBoxInstall() { recordMenuAction singBoxInstall; }
    customXrayInstall() { recordMenuAction "customXrayInstall:$*"; }
    customSingBoxInstall() { recordMenuAction "customSingBoxInstall:$*"; }
    manageSubscription() { recordMenuAction manageSubscription; }
    protocolEntryMenu() { recordMenuAction protocolEntryMenu; }
    siteCertificateMenu() { recordMenuAction siteCertificateMenu; }
    routingAccessMenu() { recordMenuAction routingAccessMenu; }
    coreVersionManageMenu() { recordMenuAction coreVersionManageMenu; }
    systemScriptMenu() { recordMenuAction systemScriptMenu; }
    advancedDangerMenu() { recordMenuAction advancedDangerMenu; }

    menu

    assertMenuAction showInstallStatus
    assertMenuAction mkdirTools
    assertMenuAction aliasInstall
    assertMenuAction installXrayReality
    [[ "$(autoValueForKey main_menu)" == "1" ]]
    [[ "$(autoValueForKey install_type)" == "3" ]]
    [[ "$(autoValueForKey core)" == "1" ]]
    [[ "${selectInstallType}" == "3" ]]
    ! grep -qxF 'installSingBoxReality' <<<"${actions}"
    ! grep -qxF 'xrayCoreInstall' <<<"${actions}"
    ! grep -qxF 'singBoxInstall' <<<"${actions}"
    ! grep -q '^errorCard:' <<<"${actions}"
    coreInstallType="${oldCoreInstallType}"
)
