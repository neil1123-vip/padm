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
    local answer inputFd nextInput output apply protocols
    unset AUTO_INSTALL AUTO_INSTALL_TYPE AUTO_INSTALL_SUMMARY_SHOWN AUTO_PROTOCOLS AUTO_REUSE_LAST
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

    AUTO_INSTALL=true
    AUTO_PROTOCOLS=999
    exec {inputFd}< <(printf '1\nnext-parent-action\n')
    regressionExpectStatus 1 selectCoreInstallProtocols xray <&"${inputFd}"
    [[ -z "${selectCustomInstallType}" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "1" ]]
    exec {inputFd}<&-
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
        readLastInstallationConfig <<<"${answer}"
        [[ -z "${lastInstallationConfig}" && "${cleaned}" == "1" ]]
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
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "1" ]]
    cleanStatus=1
    cleaned=0
    regressionExpectStatus 1 readLastInstallationConfig <<<"n"
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "1" ]]
    cleanStatus=0
    cleaned=0

    AUTO_INSTALL=true
    unset AUTO_REUSE_LAST
    readLastInstallationConfig </dev/null
    [[ "${lastInstallationConfig}" == "true" && "${cleaned}" == "0" ]]
    AUTO_REUSE_LAST=maybe
    exec {inputFd}< <(printf 'next-parent-action\n')
    regressionExpectStatus 1 readLastInstallationConfig <&"${inputFd}"
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "0" ]]
    read -r -u "${inputFd}" nextInput
    [[ "${nextInput}" == "next-parent-action" ]]
    exec {inputFd}<&-
    AUTO_REUSE_LAST=yes
    readLastInstallationConfig </dev/null
    [[ "${lastInstallationConfig}" == "true" ]]
    AUTO_REUSE_LAST=no
    readLastInstallationConfig </dev/null
    [[ -z "${lastInstallationConfig}" && "${cleaned}" == "1" ]]
    unset AUTO_INSTALL AUTO_REUSE_LAST

    # 结束标记防止旧 exit 0 把回归提前结束；递归旧入口返回不同状态便于识别。
    customXrayInstall() { return 99; }
    customSingBoxInstall() { return 99; }
    for apply in customXrayInstallApply customSingBoxInstallApply; do
        protocols="1，2"
        [[ "${apply}" != "customSingBoxInstallApply" ]] || protocols="1，31"
        output=$(
            configureRealityDomainMode() { printf 'configured:%s\n' "$1"; return 1; }
            applyStatus=0
            "${apply}" < <(printf '999\n%s\nnext-parent-action\n' "${protocols}") || applyStatus=$?
            printf 'apply-result:%s\n' "${applyStatus}"
        )
        grep -qxF "configured:,${protocols//，/,}," <<<"${output}"
        grep -qxF 'apply-result:1' <<<"${output}"
        output=$(
            configureRealityDomainMode() { return 0; }
            collectEntryProfile() { return 0; }
            protocolSelectionShowRiskNotes() { :; }
            installTools() { printf 'unexpected-install\n'; return 99; }
            cleaned=0
            applyStatus=0
            "${apply}" <<<"1" || applyStatus=$?
            printf 'apply-result:%s:cleaned=%s\n' "${applyStatus}" "${cleaned}"
        )
        grep -qxF 'apply-result:1:cleaned=0' <<<"${output}"
        ! grep -qxF 'unexpected-install' <<<"${output}"
    done

    # 历史读取不能覆盖本轮入口；失败必须在下载、停服务之前返回。
    (
        local entryReads=0
        readLastInstallationConfig() { realityEntryHost=old.example.com; }
        collectEntryProfile() {
            [[ "${realityEntryHost}" == old.example.com ]] || return 1
            realityEntryHost=new.example.com
            entryReads=$((entryReads + 1))
            return 1
        }
        installTools() { return 1; }
        configureRealityDomainMode() { return 0; }
        protocolSelectionShowRiskNotes() { :; }
        for apply in installXrayRealityApply installSingBoxRealityApply customXrayInstallApply customSingBoxInstallApply; do
            regressionExpectStatus 1 "${apply}" 1
            [[ "${realityEntryHost}" == new.example.com ]]
        done
        [[ "${entryReads}" == "4" ]]
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
