#!/usr/bin/env bash

runSubscriptionServiceRuntimeRecoveryRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/subscription-service-runtime-recovery"
    local actionLog="${root}/actions.log"
    local listenerReady=false

    mkdir -p "${root}/nginx" "${root}/static" "${root}/tls"
    : >"${actionLog}"
    nginxConfigPath="${root}/nginx/"
    nginxStaticPath="${root}/static"

    readNginxSubscribe() {
        subscribeConfigState=valid
        subscribeDomain=subscribe.example.com
        subscribePort=39778
    }
    nginxConfigFilePath() { printf '%s\n' "${nginxConfigPath}$1"; }
    resolveSubscribeServerName() { printf -v "$1" '%s' subscribe.example.com; }
    resolveSubscribePort() { printf -v "$1" '%s' 39778; }
    validateSubscribeTargetPort() { return 0; }
    prepareSubscribeTLSCertificate() { return 0; }
    tlsManagedDir() { printf '%s\n' "${root}/tls"; }
    tlsCertificatePairUsable() { return 0; }
    subscribePublicBaseDir() { printf '%s\n' "${root}/public"; }
    nginx() { [[ "$1" == "-v" || "$1" == "-t" ]]; }
    allowPort() { printf 'allow:%s\n' "$1" >>"${actionLog}"; }
    nginxRunning() { return 0; }
    subscriptionTcpPortHasListener() { [[ "${listenerReady}" == "true" ]]; }
    runSubscribeNginxAction() {
        [[ "$1" == "refresh" ]] || return 1
        listenerReady=true
        printf 'refresh\n' >>"${actionLog}"
    }
    probeSubscribeTLS() { [[ "${listenerReady}" == "true" ]]; }

    installSubscribeApply
    grep -qx 'allow:39778' "${actionLog}"
    grep -qx 'refresh' "${actionLog}"
    (
        local scenario wasRunning configWasApplied stopRc restoreRc nginxState pendingStart
        local rollbackLog="${root}/rollback.log" currentConfig="${root}/rollback.conf"
        local backupDir="${root}/rollback-backup"
        mkdir -p "${backupDir}"
        printf 'backup\n' >"${backupDir}/state"
        errorCard() { return 0; }
        nginxRunning() { [[ "${nginxState}" == true ]]; }
        padmForgetCleanupPath() { printf 'forget\n' >>"${rollbackLog}"; }
        runSubscribeNginxAction() {
            printf '%s\n' "$1" >>"${rollbackLog}"
            case "$1" in
            stop)
                [[ "${stopRc}" == 0 ]] || return "${stopRc}"
                nginxState=false
                pendingStart=false
                ;;
            start) nginxState=true; pendingStart=false ;;
            *) return 99 ;;
            esac
        }
        restoreCoreStartupServiceInstall() {
            printf 'restore\n' >>"${rollbackLog}"
            [[ "${pendingStart}" == false ]] || return 99
            [[ "${restoreRc}" == 0 ]] || return "${restoreRc}"
            printf 'old-config\n' >"${currentConfig}"
        }
        # 无进程不代表没有待启动任务；停止或恢复失败不能继续覆盖和启动。
        for scenario in stop-fail restore-fail running stopped unapplied-running unapplied-stopped; do
            wasRunning=false configWasApplied=true stopRc=0 restoreRc=0 nginxState=false pendingStart=true
            case "${scenario}" in
            stop-fail) stopRc=1; wasRunning=true ;;
            restore-fail) restoreRc=1; wasRunning=true ;;
            running) wasRunning=true ;;
            unapplied-running) configWasApplied=false; wasRunning=true; nginxState=true; pendingStart=false ;;
            unapplied-stopped) configWasApplied=false ;;
            esac
            : >"${rollbackLog}"
            printf 'new-config\n' >"${currentConfig}"
            if [[ "${scenario}" == *-fail ]]; then
                regressionExpectStatus 1 rollbackSubscribeNginxInstall "${backupDir}" "${wasRunning}" false failed "${configWasApplied}"
                [[ "$(<"${currentConfig}")" == new-config && -f "${backupDir}/state" ]]
                if [[ "${scenario}" == stop-fail ]]; then
                    [[ "$(<"${rollbackLog}")" == $'stop\nforget' && "${pendingStart}" == true ]]
                else
                    [[ "$(<"${rollbackLog}")" == $'stop\nrestore' && "${pendingStart}" == false ]]
                fi
                [[ "${nginxState}" == false ]]
            else
                rollbackSubscribeNginxInstall "${backupDir}" "${wasRunning}" false failed "${configWasApplied}"
                [[ "$(<"${currentConfig}")" == old-config && "${pendingStart}" == false ]]
                case "${scenario}" in
                running) [[ "$(<"${rollbackLog}")" == $'stop\nrestore\nstart' && "${nginxState}" == true ]] ;;
                unapplied-running) [[ "$(<"${rollbackLog}")" == restore && "${nginxState}" == true ]] ;;
                *) [[ "$(<"${rollbackLog}")" == $'stop\nrestore' && "${nginxState}" == false ]] ;;
                esac
            fi
        done
    )
    (
        # HTTP-01 必须检查 80 端口的归属，再临时停止并恢复受管 Nginx。
        listenerReady=true
        : >"${actionLog}"
        checkDNSIP() { return 0; }
        subscriptionTcpPortHasListener() { [[ "${1:-}" == 80 && "${listenerReady}" == true ]]; }
        subscriptionTcpPortListenersAreNginx() { [[ $# == 1 && "${1:-}" == 80 ]]; }
        nginxRunning() { [[ "${listenerReady}" == true ]]; }
        runSubscribeNginxAction() {
            printf 'nginx:%s\n' "$1" >>"${actionLog}"
            [[ "$1" == start ]] && listenerReady=true || listenerReady=false
            return 0
        }
        allowPort() { PADM_LAST_ALLOW_PORT_ADDED=true; printf 'allow:%s\n' "$1" >>"${actionLog}"; }
        denyPort() { printf 'deny:%s\n' "$1" >>"${actionLog}"; }
        installTLS() { [[ "$1" == 1 && "${listenerReady}" == false ]] || return 1; printf 'install\n' >>"${actionLog}"; }

        subscriptionInstallTLSHttp01 subscribe.example.com
        [[ "$(<"${actionLog}")" == $'nginx:stop\nallow:80\ninstall\ndeny:80\nnginx:start' ]]
        [[ "${listenerReady}" == true ]]
    )
)

assertCapturedSubscribeOutputs() {
    local user=$1
    local expectedDefault=$2
    local expectedServer=$3
    local expectedSNI=$4
    local expectedNetwork=$5
    local expectedType=$6

    grep -qxF "${expectedDefault}" "${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
    grep -qx "    server: ${expectedServer}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    if grep -q "^    servername:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    servername: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    elif grep -q "^    sni:" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"; then
        grep -qx "    sni: ${expectedSNI}" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${user}"
    fi
    jq -e --arg server "${expectedServer}" --arg sni "${expectedSNI}" --arg network "${expectedNetwork}" --arg type "${expectedType}" '
      .[0].type == $type and
      .[0].server == $server and
      .[0].tls.server_name == $sni and
      (if $network == "tcp" then (.[0].transport | not) else .[0].transport.type == $network end)
    ' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${user}" >/dev/null
}

assertDisplayedDefaultSubscribeLink() {
    local user=$1
    local title=$2
    local link
    IFS= read -r link <"${SUBSCRIBE_CAPTURE_DIR}/default/${user}"
    awk -v title="${title}" -v link="${link}" '
      index($0, title) { getline; found = ($0 == "green     " link "\\n"); exit }
      END { exit(found ? 0 : 1) }
    ' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"
}

runSubscribeLocalRollbackRegression() (
    local rootRel="${TMP_DIR}/subscribe-local-rollback"
    local root localDir publicDir errorLog callLog beforeSnapshot beforePublicSnapshot
    local oldLocalDir="${PADM_SUBSCRIBE_LOCAL_DIR:-}"
    local oldPublicDir="${PADM_SUBSCRIBE_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local oldSubscribeSalt="${subscribeSalt:-}"
    local renderCalls=0
    local showAccountsCalls=0
    local rc

    captureSubscribeLocalSnapshot() {
        find "${localDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }
    captureSubscribePublicSnapshot() {
        find "${publicDir}" -type f -printf '%P\t' -exec cat {} \; | sort
    }

    mkdir -p "${rootRel}"
    root=$(cd -- "${rootRel}" && pwd -P)
    localDir="${root}/subscribe_local"
    publicDir="${root}/subscribe_public"
    errorLog="${root}/error.log"
    callLog="${root}/calls.log"
    beforeSnapshot="${root}/before.txt"
    beforePublicSnapshot="${root}/before-public.txt"
    source "${PROJECT_ROOT}/shell/core/manage.sh"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localDir}"
    export PADM_SUBSCRIBE_DIR="${publicDir}"
    TMPDIR="${root}"
    REGRESSION_ERROR_CARD_LOG="${errorLog}"
    mkdir -p "${localDir}/default" "${localDir}/clashMeta" "${localDir}/sing-box"
    mkdir -p "${publicDir}/default" "${publicDir}/clashMeta" "${publicDir}/clashMetaProfiles" "${publicDir}/sing-box" "${publicDir}/sing-box_profiles"
    printf 'existing-salt\n' >"${localDir}/subscribeSalt"
    printf 'old default\n' >"${localDir}/default/existing"
    printf 'old clash\n' >"${localDir}/clashMeta/existing"
    printf '[{"tag":"old-local"}]\n' >"${localDir}/sing-box/existing"
    printf 'old public\n' >"${publicDir}/default/existing"
    subscribeSalt=existing-salt
    captureSubscribeLocalSnapshot >"${beforeSnapshot}"
    captureSubscribePublicSnapshot >"${beforePublicSnapshot}"

    readInstallProtocolType() { return 0; }
    readNginxSubscribe() { return 0; }
    installSubscribe() { return 0; }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        printf 'render\n' >>"${callLog}"
        return 0
    }

    : >"${errorLog}"
    : >"${callLog}"
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 1
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        return 0
    }
    coreInstallType=1
    regressionExpectStatus 1 subscribe false true >/dev/null 2>&1
    [[ "${showAccountsCalls}" == "0" ]]
    [[ "${renderCalls}" == "0" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅 Salt 初始化失败，已恢复旧订阅输出' "${errorLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'

    : >"${errorLog}"
    : >"${callLog}"
    renderCalls=0
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 0
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        printf 'new default\n' >"${localDir}/default/existing"
        printf 'new clash\n' >"${localDir}/clashMeta/existing"
        printf '[{"tag":"new-local"}]\n' >"${localDir}/sing-box/existing"
        return 1
    }
    regressionExpectStatus 1 subscribe false true >/dev/null 2>&1
    [[ "${showAccountsCalls}" == "1" ]]
    [[ "${renderCalls}" == "0" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    grep -q '订阅生成失败：重建本地订阅失败，已恢复旧订阅输出' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d -name 'padm-subscription-output-backup.*'

    : >"${errorLog}"
    : >"${callLog}"
    renderCalls=0
    showAccountsCalls=0
    resolveSubscribeSalt() {
        writeSubscribeSalt "$1" "new-salt"
        subscribeSalt="new-salt"
        return 0
    }
    showAccounts() {
        showAccountsCalls=$((showAccountsCalls + 1))
        printf 'showAccounts\n' >>"${callLog}"
        printf 'new default\n' >"${localDir}/default/existing"
        printf 'new clash\n' >"${localDir}/clashMeta/existing"
        printf '[{"tag":"new-local"}]\n' >"${localDir}/sing-box/existing"
        return 0
    }
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        printf 'render\n' >>"${callLog}"
        [[ "${PADM_SUBSCRIBE_DIR}" != "${publicDir}" ]] || return 1
        printf 'new public\n' >"${PADM_SUBSCRIBE_DIR}/default/existing"
        printf 'first account published\n' >"${PADM_SUBSCRIBE_DIR}/default/first-account"
        return 1
    }
    regressionExpectStatus 1 subscribe false true >/dev/null 2>&1
    [[ "${showAccountsCalls}" == "1" ]]
    [[ "${renderCalls}" == "1" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    [[ "$(<"${localDir}/subscribeSalt")" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    diff -u "${beforePublicSnapshot}" <(captureSubscribePublicSnapshot)
    [[ ! -e "${publicDir}/default/first-account" ]]
    grep -q '订阅生成失败：生成订阅输出失败，已恢复旧订阅输出' "${errorLog}"
    grep -qx 'showAccounts' "${callLog}"
    grep -qx 'render' "${callLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d \( -name 'padm-subscription-output-backup.*' -o -name 'padm-subscribe-publish.*' \)

    : >"${errorLog}"
    : >"${callLog}"
    renderCalls=0
    showAccountsCalls=0
    renderAllSubscribeUserOutputs() {
        renderCalls=$((renderCalls + 1))
        printf 'render\n' >>"${callLog}"
        printf 'new public\n' >"${PADM_SUBSCRIBE_DIR}/default/existing"
        return 0
    }
    syncInstallDirectoryTree() {
        return 1
    }
    regressionExpectStatus 1 subscribe false true >/dev/null 2>&1
    [[ "${showAccountsCalls}" == "1" ]]
    [[ "${renderCalls}" == "1" ]]
    [[ "${subscribeSalt}" == "existing-salt" ]]
    diff -u "${beforeSnapshot}" <(captureSubscribeLocalSnapshot)
    diff -u "${beforePublicSnapshot}" <(captureSubscribePublicSnapshot)
    grep -q '订阅生成失败：发布订阅输出失败，已恢复旧订阅输出' "${errorLog}"
    ! regressionFindHasMatches "${root}" -maxdepth 1 -type d \( -name 'padm-subscription-output-backup.*' -o -name 'padm-subscribe-publish.*' \)

    if [[ -n "${oldLocalDir}" ]]; then export PADM_SUBSCRIBE_LOCAL_DIR="${oldLocalDir}"; else unset PADM_SUBSCRIBE_LOCAL_DIR; fi
    if [[ -n "${oldPublicDir}" ]]; then export PADM_SUBSCRIBE_DIR="${oldPublicDir}"; else unset PADM_SUBSCRIBE_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
    if [[ -n "${oldSubscribeSalt}" ]]; then subscribeSalt="${oldSubscribeSalt}"; else unset subscribeSalt; fi
)

runSubscriptionGroupsBackupFailureRegression() (
    local root="${TMP_DIR}/subscription-groups-backup-failure"
    local groupsDir="${root}/subscribe_groups"
    local backupsDir="${groupsDir}/backups"
    local stateFile="${groupsDir}/groups.json"
    local oldGroupsDir="${PADM_SUBSCRIPTION_GROUPS_DIR:-}"
    local oldTmpDir="${TMPDIR:-}"
    local beforeSnapshot
    local backupModeLog="${root}/backup-mode.log"
    local chmodLog="${root}/chmod.log"
    local backupFile
    local rc

    source "${PROJECT_ROOT}/shell/subscription/groups.sh"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${groupsDir}"
    TMPDIR="${root}"
    mkdir -p "${groupsDir}"
    cat >"${stateFile}" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"默认订阅组","admin":{"id":"admin","name":"我的订阅","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"本机","role":"main","transport":"local","scheme":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON
    beforeSnapshot=$(<"${stateFile}")
    : >"${backupModeLog}"
    : >"${chmodLog}"
    eval "$(declare -f backupManagedFileToPath | sed '1s/^backupManagedFileToPath/originalBackupManagedFileToPath/')"
    backupManagedFileToPath() {
        printf '%s|%s|%s\n' "$1" "$2" "${3:-}" >>"${backupModeLog}"
        originalBackupManagedFileToPath "$@"
    }

    cp() {
        return 1
    }

    set +e
    backupFile=$(createSubscriptionGroupsBackup)
    rc=$?
    set -e
    unset -f cp
    [[ "${rc}" == "1" ]]
    [[ -z "${backupFile}" ]]
    [[ "$(<"${stateFile}")" == "${beforeSnapshot}" ]]
    if regressionFindHasMatches "${backupsDir}" -maxdepth 1 -type f -name 'groups-[0-9]*.json'; then
        return 1
    fi
    chmod() {
        printf '%s\n' "$*" >>"${chmodLog}"
        command chmod "$@"
    }
    backupFile=$(createSubscriptionGroupsBackup)
    [[ -f "${backupFile}" ]]
    grep -Fxq "${stateFile}|${backupFile}|600" "${backupModeLog}"
    grep -Fxq "700 ${backupsDir}" "${chmodLog}"
    command chmod 755 "${backupsDir}"
    command chmod 644 "${backupFile}"
    : >"${chmodLog}"
    subscriptionGroupsSecureStateFiles
    grep -Fxq "700 ${backupsDir}" "${chmodLog}"
    grep -Fxq "600 ${backupFile}" "${chmodLog}"

    if [[ -n "${oldGroupsDir}" ]]; then export PADM_SUBSCRIPTION_GROUPS_DIR="${oldGroupsDir}"; else unset PADM_SUBSCRIPTION_GROUPS_DIR; fi
    if [[ -n "${oldTmpDir}" ]]; then TMPDIR="${oldTmpDir}"; else unset TMPDIR; fi
)

runSubscriptionOutputProfileAndRealityRegression() {
    local SUBSCRIBE_CAPTURE_DIR="${SUBSCRIBE_CAPTURE_DIR}-${BASHPID:-$$}"
    local PADM_SUBSCRIBE_LOCAL_DIR="${SUBSCRIBE_CAPTURE_DIR}"
    rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
    export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
    export REGRESSION_ERROR_CARD_LOG="${TMP_DIR}/subscription-output-encryption-errors.log"
    : >"${REGRESSION_ERROR_CARD_LOG}"
local profileEmail profileId profilePassword profileName profileUuid
IFS=$'\037' read -r profileEmail profileId profilePassword _ profileName profileUuid <<<"$(subscriptionAccountProfile '{"email":"user-main","id":"uuid-main","password":"pass-main"}')"
[[ "${profileEmail}" == "user-main" && "${profileId}" == "uuid-main" && "${profilePassword}" == "pass-main" && "${profileName}" == "user-main" && "${profileUuid}" == "uuid-main" ]]
IFS=$'\037' read -r _ _ profilePassword _ profileName profileUuid <<<"$(subscriptionAccountProfile '{"name":"udp-user","password":"udp-pass"}')"
[[ "${profilePassword}" == "udp-pass" && "${profileName}" == "udp-user" && -z "${profileUuid}" ]]
IFS=$'\037' read -r _ _ profilePassword _ _ _ <<<"$(subscriptionAccountProfile '{"name":"udp-user","password":"pass with \"quotes\""}')"
[[ "${profilePassword}" == 'pass with "quotes"' ]] || return 1
local profileField profileValue
for profileField in email id password username name uuid; do
    for profileValue in '{}' '[]'; do
        regressionExpectFailure subscriptionAccountProfile \
            "$(jq -nc --arg field "${profileField}" --argjson value "${profileValue}" '{($field):$value}')" >/dev/null 2>&1 || return 1
    done
done
IFS=$'\037' read -r _ _ profilePassword _ _ _ <<<"$(subscriptionAccountProfile '{"name":"scalar-user","password":42}')"
[[ "${profilePassword}" == 42 ]] || return 1
coreInstallType=1
currentHost="tls.example.com"
realityEntryHost="node.example.com"
xrayVLESSRealitySNI="www.microsoft.com"
currentRealityPublicKey="pubkey"
currentRealityMldsa65Verify=""

local visionOutputConfigDir="${TMP_DIR}/vision-output-conf"
local visionOutputPreviousConfigPath="${configPath:-}"
mkdir -p "${visionOutputConfigDir}"
configPath="${visionOutputConfigDir}/"
cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'EOF'
{"inbounds":[{"port":443},{"settings":{"clients":[{"email":"fixture","id":"fixture"}],"decryption":"none"},"streamSettings":{"realitySettings":{"serverNames":["www.microsoft.com"],"publicKey":"pubkey","privateKey":"priv","target":"www.microsoft.com:443"}}}]}
EOF
printf '%s\n' '{"enabled":true,"encryption":"stale-encryption","decryption":"stale-decryption"}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
readInstallProtocolType
[[ -z "${currentRealityMldsa65Verify}" ]]
realityEntryHost="node.example.com"
xrayVLESSRealitySNI="www.microsoft.com"
currentRealityPublicKey="pubkey"
defaultBase64Code vlessReality 443 user-a-stale uuid-a "" ""
grep -qxF "vless://uuid-a@node.example.com:443?encryption=none&security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a-stale" "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-stale"
! grep -q '^    encryption:' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-stale"
jq -e '.[0] | has("encryption") | not' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-stale" >/dev/null
! grep -q 'pqv=null' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-stale" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'EOF'
{"inbounds":[{"port":443},{"settings":{"clients":[{"email":"fixture","id":"fixture"}],"decryption":"active-decryption"},"streamSettings":{"realitySettings":{"serverNames":["www.microsoft.com"],"publicKey":"pubkey","privateKey":"priv","target":"www.microsoft.com:443"}}}]}
EOF
printf '%s\n' '{"enabled":true,"encryption":"stale-encryption","decryption":"stale-decryption"}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
! defaultBase64Code vlessReality 443 user-a-mismatch uuid-a "" ""
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-mismatch" ]]
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-mismatch" ]]
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-mismatch" ]]
grep -q 'VLESS Encryption 配置与状态不一致' "${REGRESSION_ERROR_CARD_LOG}"

printf '%s\n' '{"enabled":true,"encryption":"active-encryption","decryption":"active-decryption"}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
readInstallProtocolType
realityEntryHost="node.example.com"
defaultBase64Code vlessReality 443 user-a-active uuid-a "" ""
grep -qxF "vless://uuid-a@node.example.com:443?encryption=active-encryption&security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=pubkey&sid=6ba85179e30d4fc2&flow=xtls-rprx-vision#user-a-active" "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-active"
grep -qx '    encryption: "active-encryption"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-active"
jq -e '.[0] | has("encryption") | not' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-active" >/dev/null
(
    cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'EOF'
{"inbounds":[{"port":443},{"settings":{"clients":[{"email":"fixture","id":"fixture"}],"decryption":"active-decryption"},"streamSettings":{"realitySettings":{"serverNames":["www.microsoft.com"],"publicKey":"pubkey","privateKey":"priv","target":"www.microsoft.com:443","mldsa65Seed":"seed-old","mldsa65Verify":"pqv-old"}}}]}
EOF
    readInstallProtocolType
    [[ "${currentRealityMldsa65Seed}" == "seed-old" && "${currentRealityMldsa65Verify}" == "pqv-old" ]]

    local singBoxVisionConfigDir="${TMP_DIR}/sing-box-vision-output-conf"
    mkdir -p "${singBoxVisionConfigDir}"
    cat >"${singBoxVisionConfigDir}/07_VLESS_vision_reality_inbounds.json" <<'EOF'
{"inbounds":[{"listen_port":1443,"users":[{"name":"sing-box-vision-wrapper","uuid":"uuid-wrapper"}],"tls":{"server_name":"www.microsoft.com","reality":{"handshake":{"server":"www.microsoft.com","server_port":443},"private_key":"sing-box-private"}}}]}
EOF
    coreInstallType=2
    configPath="${singBoxVisionConfigDir}/"
    readInstallProtocolType
    [[ -z "${currentRealityMldsa65Seed}" && -z "${currentRealityMldsa65Verify}" ]]
    currentRealityMldsa65Verify=stale-pqv
    singBoxVLESSRealityPublicKey=sing-box-public
    defaultBase64Code vlessReality 443 sing-box-vision-no-pqv uuid-vision "" ""
    regressionExpectStatus 1 grep -q 'pqv=' "${SUBSCRIBE_CAPTURE_DIR}/default/sing-box-vision-no-pqv"
    grep -qF '&pbk=sing-box-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/sing-box-vision-no-pqv"
    showVlessRealityAccounts
    grep -qF 'vless://uuid-wrapper@tls.example.com:1443?' "${SUBSCRIBE_CAPTURE_DIR}/default/sing-box-vision-wrapper"
    grep -qF '&sni=www.microsoft.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/sing-box-vision-wrapper"
    grep -qF '&pbk=sing-box-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/sing-box-vision-wrapper"
)
rm -f "${PADM_VLESS_ENCRYPTION_STATE_FILE}"
configPath="${visionOutputPreviousConfigPath}"

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
defaultBase64Code vlessReality 443 user-a-main uuid-a "" ""
expectedVisionLink=$(serializeVlessRealityVisionLink "uuid-a" "node.example.com" "443" "www.microsoft.com" "pubkey" "" "user-a-main")
assertCapturedSubscribeOutputs "user-a-main" "${expectedVisionLink}" "node.example.com" "www.microsoft.com" "tcp" "vless"
assertDisplayedDefaultSubscribeLink "user-a-main" "通用格式：VLESS Reality Vision"
jq -e '.[0].flow == "xtls-rprx-vision" and .[0].tls.reality.public_key == "pubkey"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-main" >/dev/null
! grep -q 'pqv' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-main" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentRealityMldsa65Verify="pqv"
defaultBase64Code vlessRealityGRPC 8443 user-a-grpc uuid-a "" ""
expectedGrpcLink=$(serializeVlessRealityGrpcLink "uuid-a" "node.example.com" "8443" "www.microsoft.com" "pubkey" "pqv" "user-a-grpc")
assertCapturedSubscribeOutputs "user-a-grpc" "${expectedGrpcLink}" "node.example.com" "www.microsoft.com" "grpc" "vless"
assertDisplayedDefaultSubscribeLink "user-a-grpc" "通用格式：VLESS Reality gRPC"
jq -e '.[0].transport.service_name == "grpc" and .[0].tls.reality.short_id == "6ba85179e30d4fc2"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-grpc" >/dev/null
grep -q 'pqv=pqv' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

(
    local protocol account
    singBoxSubscribeAppendFilter() { return 1; }
    for protocol in vlessReality vlessRealityGRPC; do
        account="reality-filter-failure-${protocol}"
        regressionExpectStatus 1 defaultBase64Code "${protocol}" 443 "${account}" uuid-a "" "" || return 1
        [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]] || return 1
    done
) || return 1

(
    local protocol variant account
    for protocol in vlessReality vlessRealityGRPC; do
        for variant in failed empty invalid; do
            account="reality-${protocol}-${variant}"
            case "${variant}" in
            failed) realityEntryHost() { printf '%s' node.example.com; return 1; } ;;
            empty) realityEntryHost() { :; } ;;
            invalid) realityEntryHost() { printf '%s' 'bad host'; } ;;
            esac
            regressionExpectStatus 1 defaultBase64Code "${protocol}" 443 "${account}" uuid-a "" "" || return 1
            [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" &&
                ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" &&
                ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]] || return 1
        done
        realityEntryHost() { printf '%s' 2001:db8::10; }
        account="reality-${protocol}-ipv6"
        defaultBase64Code "${protocol}" 443 "${account}" uuid-a "" "" || return 1
        grep -qF 'vless://uuid-a@[2001:db8::10]:443?' "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" || return 1
        grep -qx '    server: 2001:db8::10' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" || return 1
        jq -e '.[0].server == "2001:db8::10"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" >/dev/null || return 1
    done
) || return 1

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentRealityMldsa65Verify=""
local oldConfigPath="${configPath:-}"
configPath="${TMP_DIR}/xhttp-subscription-conf/"
mkdir -p "${configPath}"
xrayVLESSRealityXHTTPSNI="www.microsoft.com"
currentRealityXHTTPPublicKey="pubkey"
cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"port":443,"settings":{"decryption":"active-decryption"},"streamSettings":{"realitySettings":{"serverNames":["www.microsoft.com"],"publicKey":"pubkey","privateKey":"priv","target":"www.microsoft.com:443","mldsa65Seed":"seed-xhttp","mldsa65Verify":"pqv-xhttp"},"xhttpSettings":{"host":"front.example.com","path":"/custom-xhttp","mode":"packet-up"}}}]}
EOF
! defaultBase64Code vlessXHTTP 443 user-a-xhttp-missing-state uuid-a "cdn.example.com" "/ignored"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-missing-state" ]]
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp-missing-state" ]]

printf '%s\n' '{"enabled":true,"encryption":"active-encryption","decryption":"active-decryption"}' >"${PADM_VLESS_ENCRYPTION_STATE_FILE}"
readInstallProtocolType
[[ "${currentRealityMldsa65Seed}" == "seed-xhttp" && "${currentRealityMldsa65Verify}" == "pqv-xhttp" ]]
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
defaultBase64Code vlessXHTTP 443 user-a-xhttp-active uuid-a "cdn.example.com" "/ignored"
expectedXHTTPLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom-xhttp" "pubkey" "user-a-xhttp-active" active-encryption "front.example.com" "packet-up" "pqv-xhttp")
grep -qxF "${expectedXHTTPLink}" "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-active"
grep -q 'pqv=pqv-xhttp' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"
grep -qx '    encryption: "active-encryption"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp-active"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/user-a-xhttp-active" ]]
(
    local configPath="${TMP_DIR}/reality-pqv-isolation/"
    local singBoxConfigPath=
    mkdir -p "${configPath}"
    cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'EOF'
{"inbounds":[{"port":443},{"settings":{"clients":[]},"streamSettings":{"realitySettings":{"serverNames":["vision.example.com"],"publicKey":"vision-public","privateKey":"vision-private","target":"vision.example.com:443","mldsa65Seed":"vision-seed","mldsa65Verify":"vision-pqv"}}}]}
EOF
    cat >"${configPath}08_VLESS_vision_gRPC_inbounds.json" <<'EOF'
{"inbounds":[{"port":8443,"settings":{"clients":[{"email":"grpc-no-pqv","id":"uuid-grpc"}]},"streamSettings":{"realitySettings":{"serverNames":["grpc.example.com"],"publicKey":"grpc-public","privateKey":"grpc-private","target":"grpc.example.com:443","mldsa65Verify":""}}}]}
EOF
    cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"port":9443,"settings":{"clients":[]},"streamSettings":{"realitySettings":{"serverNames":["xhttp.example.com"],"publicKey":"xhttp-public","privateKey":"xhttp-private","target":"xhttp.example.com:443","mldsa65Seed":"xhttp-seed","mldsa65Verify":"xhttp-pqv"},"xhttpSettings":{"host":"xhttp.example.com","path":"/xhttp","mode":"auto"}}}]}
EOF
    readInstallProtocolType
    realityEntryHost="node.example.com"
    defaultBase64Code vlessReality 443 vision-own-pqv uuid-vision "" ""
    grep -qF '&pqv=vision-pqv&' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-own-pqv"
    grep -qF '&pbk=vision-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-own-pqv"

    currentRealityMldsa65Verify="stale-pqv"
    defaultBase64Code vlessXHTTP 9443 xhttp-own-pqv uuid-xhttp "node.example.com" "/ignored"
    grep -qF '&pqv=xhttp-pqv&' "${SUBSCRIBE_CAPTURE_DIR}/default/xhttp-own-pqv"
    showVlessRealityGrpcAccounts
    regressionExpectStatus 1 grep -q 'pqv=' "${SUBSCRIBE_CAPTURE_DIR}/default/grpc-no-pqv"
    grep -qF '&pbk=grpc-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/grpc-no-pqv"

    updateRoutingJsonConfig "${configPath}08_VLESS_vision_gRPC_inbounds.json" '.inbounds[0].streamSettings.realitySettings.mldsa65Verify = "grpc-pqv" | .inbounds[0].settings.clients[0].email = "grpc-own-pqv"'
    readInstallProtocolType
    showVlessRealityGrpcAccounts
    grep -qF '&pqv=grpc-pqv&' "${SUBSCRIBE_CAPTURE_DIR}/default/grpc-own-pqv"

    updateRoutingJsonConfig "${configPath}07_VLESS_vision_reality_inbounds.json" 'del(.inbounds[1].streamSettings.realitySettings.mldsa65Verify)'
    updateRoutingJsonConfig "${configPath}12_VLESS_XHTTP_inbounds.json" '.inbounds[0].streamSettings.realitySettings.mldsa65Verify = null'
    defaultBase64Code vlessReality 443 vision-no-pqv uuid-vision "" ""
    defaultBase64Code vlessXHTTP 9443 xhttp-no-pqv uuid-xhttp "node.example.com" "/ignored"
    regressionExpectStatus 1 grep -q 'pqv=' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-no-pqv" "${SUBSCRIBE_CAPTURE_DIR}/default/xhttp-no-pqv"

    printf '{invalid-json\n' >"${configPath}07_VLESS_vision_reality_inbounds.json"
    printf '{invalid-json\n' >"${configPath}12_VLESS_XHTTP_inbounds.json"
    regressionExpectStatus 1 defaultBase64Code vlessReality 443 vision-invalid-config uuid-vision "" ""
    regressionExpectStatus 1 defaultBase64Code vlessXHTTP 9443 xhttp-invalid-config uuid-xhttp "node.example.com" "/ignored"
    [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/vision-invalid-config" && ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/xhttp-invalid-config" ]]
)
rm -f "${PADM_VLESS_ENCRYPTION_STATE_FILE}"
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"

cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front.example.com","path":"/custom-xhttp","mode":"packet-up"}}}]}
EOF
currentRealityMldsa65Verify=""
defaultBase64Code vlessXHTTP 443 user-a-xhttp uuid-a "cdn.example.com" "/ignored"
expectedXHTTPLink=$(serializeVlessRealityXHTTPLink "uuid-a" "cdn.example.com" "443" "www.microsoft.com" "/custom-xhttp" "pubkey" "user-a-xhttp" none "front.example.com" "packet-up")
grep -qxF "${expectedXHTTPLink}" "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp"
assertDisplayedDefaultSubscribeLink "user-a-xhttp" "通用格式：VLESS Reality XHTTP Vision XMUX"
! grep -q 'flow=xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp"
grep -qx "    server: cdn.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "    servername: www.microsoft.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      path: /custom-xhttp" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      host: front.example.com" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
grep -qx "      mode: packet-up" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
! grep -q '^    encryption:' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
! grep -q 'flow: xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp"
! grep -q '&flow=xtls-rprx-vision' "${SUBSCRIBE_CAPTURE_DIR}/screen.log"

(
    local PADM_VLESS_REALITY_CONFIG_FILE="${TMP_DIR}/vision-subscription-override.json"
    local coreInstallType=1 currentInstallProtocolType=,1, xrayVLESSRealityVisionPort=443
    local singBoxConfigPath= currentPath=padm xrayVLESSRealitySNI=wrong.example.com
    local publicPort=
    cat >"${PADM_VLESS_REALITY_CONFIG_FILE}" <<'EOF'
{"inbounds":[{"port":9443},{"settings":{"clients":[{"email":"vision-override-reader","id":"uuid-override"}],"decryption":"none"},"streamSettings":{"realitySettings":{"serverNames":["override-sni.example.com"],"publicKey":"override-public","mldsa65Verify":"override-pqv"}}}]}
EOF
    realityStreamPublicPortForProtocol() { printf '%s' "${publicPort}"; }
    corePortSubscriptionPort() { printf '%s\n' "$2"; }
    showVlessRealityAccounts || return 1
    grep -qF 'vless://uuid-override@tls.example.com:9443?' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-override-reader" || return 1
    grep -qF '&sni=override-sni.example.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-override-reader" || return 1
    grep -qF '&pbk=override-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-override-reader" || return 1
    grep -qF '&pqv=override-pqv&' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-override-reader" || return 1
    jq -e '.[0].server_port == 9443 and .[0].tls.server_name == "override-sni.example.com" and .[0].tls.reality.public_key == "override-public"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/vision-override-reader" >/dev/null || return 1
    publicPort=10443
    updateRoutingJsonConfig "${PADM_VLESS_REALITY_CONFIG_FILE}" '.inbounds[1].settings.clients[0].email = "vision-override-stream"' || return 1
    showVlessRealityAccounts || return 1
    grep -qF '@tls.example.com:10443?' "${SUBSCRIBE_CAPTURE_DIR}/default/vision-override-stream" || return 1
    local badSNI account
    for badSNI in '"bad host"' '["bad.example.com"]'; do
        account=vision-override-invalid-sni
        updateRoutingJsonConfig "${PADM_VLESS_REALITY_CONFIG_FILE}" \
            '.inbounds[1].settings.clients[0].email = $email | .inbounds[1].streamSettings.realitySettings.serverNames[0] = $sni' \
            --arg email "${account}" --argjson sni "${badSNI}" || return 1
        regressionExpectStatus 1 showVlessRealityAccounts || return 1
        [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]] || return 1
    done
    PADM_VLESS_REALITY_CONFIG_FILE="${TMP_DIR}/missing-vision-override.json"
    local missingCapture="${TMP_DIR}/missing-vision-output"
    defaultBase64Code() { printf 'unexpected output\n' >>"${missingCapture}"; }
    regressionExpectStatus 1 showVlessRealityAccounts || return 1
    [[ ! -e "${missingCapture}" ]] || return 1
) || return 1

(
    local configPath="${TMP_DIR}/xhttp-subscription-no-slash"
    local PADM_XRAY_CONF_DIR="${configPath}" PADM_VLESS_XHTTP_CONFIG_FILE=
    local xhttpOverrideFile="${TMP_DIR}/xhttp-subscription-override.json"
    mkdir -p "${configPath}"
    cat >"${configPath}/12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"noslash.example.com","path":"/noslash","mode":"stream-up"}}}]}
EOF
    local variant
    for variant in no-slash directory-override; do
        [[ "${variant}" != directory-override ]] || configPath=
        defaultBase64Code vlessXHTTP 443 "user-a-xhttp-${variant}" uuid-a "cdn.example.com" "/ignored" || return 1
        grep -qF 'host=noslash.example.com' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-${variant}" || return 1
        grep -qF '&path=/noslash&mode=stream-up' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-${variant}" || return 1
    done

    cat >"${xhttpOverrideFile}" <<'EOF'
{"inbounds":[{"port":9443,"settings":{"clients":[{"email":"user-a-xhttp-override-reader","id":"uuid-override"}],"decryption":"none"},"streamSettings":{"realitySettings":{"serverNames":["override-sni.example.com"],"publicKey":"override-public","mldsa65Verify":"override-pqv"},"xhttpSettings":{"host":"override.example.com","path":"/override","mode":"packet-up"}}}]}
EOF
    cat >"${PADM_XRAY_CONF_DIR}/12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"wrong.example.com","path":"/wrong","mode":"auto"}}}]}
EOF
    PADM_VLESS_XHTTP_CONFIG_FILE="${xhttpOverrideFile}"
    defaultBase64Code vlessXHTTP 443 user-a-xhttp-override uuid-a "cdn.example.com" "/ignored" || return 1
    grep -qF 'host=override.example.com' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override" || return 1
    grep -qF '&path=/override&mode=packet-up' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override" || return 1
    grep -qF '&sni=override-sni.example.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override" || return 1
    grep -qF '&pbk=override-public&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override" || return 1
    grep -qF '&pqv=override-pqv&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override" || return 1
    grep -qx '    servername: override-sni.example.com' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp-override" || return 1
    grep -qx '      public-key: "override-public"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp-override" || return 1
    local currentInstallProtocolType=,2, xrayVLESSRealityXHTTPort=443 currentCDNAddress=cdn.example.com currentPath=padm
    realityStreamPublicPortForProtocol() { :; }
    corePortSubscriptionPort() { printf '%s\n' "$2"; }
    showVlessRealityXHTTPAccounts || return 1
    grep -qF 'vless://uuid-override@cdn.example.com:9443?' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override-reader" || return 1
    grep -qF '&sni=override-sni.example.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override-reader" || return 1
    grep -qF '&host=override.example.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-override-reader" || return 1
    currentCDNAddress=
    local account
    for variant in failed empty invalid; do
        account="xhttp-fallback-${variant}"
        updateRoutingJsonConfig "${xhttpOverrideFile}" '.inbounds[0].settings.clients[0].email = $email' --arg email "${account}" || return 1
        case "${variant}" in
        failed) realityEntryHost() { printf '%s' node.example.com; return 1; } ;;
        empty) realityEntryHost() { :; } ;;
        invalid) realityEntryHost() { printf '%s' 'bad host'; } ;;
        esac
        regressionExpectStatus 1 showVlessRealityXHTTPAccounts || return 1
        [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" &&
            ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]] || return 1
    done
    account=xhttp-fallback-ipv6
    updateRoutingJsonConfig "${xhttpOverrideFile}" '.inbounds[0].settings.clients[0].email = $email' --arg email "${account}" || return 1
    realityEntryHost() { printf '%s' 2001:db8::10; }
    showVlessRealityXHTTPAccounts || return 1
    grep -qF 'vless://uuid-override@[2001:db8::10]:9443?' "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" || return 1
    grep -qx '    server: 2001:db8::10' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" || return 1
) || return 1

(
    local configPath="${TMP_DIR}/xhttp-subscription-empty-host/"
    local configFile="${configPath}12_VLESS_XHTTP_inbounds.json" key value caseIndex=0 account
    mkdir -p "${configPath}"
    printf '%s\n' '{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"","path":"/empty-host","mode":"auto"}}}]}' >"${configFile}"
    defaultBase64Code vlessXHTTP 443 user-a-xhttp-empty-host uuid-a "cdn.example.com" "/ignored"
    grep -qF '&host=&fp=chrome' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-empty-host"
    grep -qx '      host: ""' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/user-a-xhttp-empty-host"
    [[ "$(xrayRealityXHTTPSetting host fallback.example.com)" == "" ]]
    printf '%s\n' '{"inbounds":[{"streamSettings":{"xhttpSettings":{"path":"/fallback"}}}]}' >"${configFile}"
    defaultBase64Code vlessXHTTP 443 user-a-xhttp-missing-host uuid-a "cdn.example.com" "/ignored"
    grep -qF '&host=www.microsoft.com&' "${SUBSCRIBE_CAPTURE_DIR}/default/user-a-xhttp-missing-host"
    [[ "$(xrayRealityXHTTPSetting mode auto)" == auto ]]
    for key in host path mode; do
        for value in null 123 false '[]' '{}'; do
            caseIndex=$((caseIndex + 1))
            account="user-a-xhttp-invalid-${key}-${caseIndex}"
            jq -n --arg key "${key}" --argjson value "${value}" '{inbounds:[{streamSettings:{xhttpSettings:
                ({host:"front.example.com",path:"/typed",mode:"auto"} | .[$key] = $value)}}]}' >"${configFile}"
            regressionExpectStatus 1 xrayRealityXHTTPSetting "${key}" fallback
            regressionExpectStatus 1 defaultBase64Code vlessXHTTP 443 "${account}" uuid-a "cdn.example.com" "/ignored"
            [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" ]]
        done
    done
    printf '%s\n' '{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front.example.com\ninvalid","path":"/typed","mode":"auto"}}}]}' >"${configFile}"
    regressionExpectStatus 1 xrayRealityXHTTPSetting host fallback
    printf '%s\n' '{"inbounds":[{"streamSettings":{"xhttpSettings":false}}]}' >"${configFile}"
    regressionExpectStatus 1 xrayRealityXHTTPSetting host fallback
    printf '%s\n' '{}' '{}' >"${configFile}"
    regressionExpectStatus 1 xrayRealityXHTTPSetting host fallback
    printf '{invalid-json\n' >"${configFile}"
    regressionExpectStatus 1 xrayRealityXHTTPSetting host fallback
)

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front.example.com","path":"/bad path","mode":"auto"}}}]}
EOF
! defaultBase64Code vlessXHTTP 443 user-bad-path uuid-a "cdn.example.com" "/ignored"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/user-bad-path" ]]

cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front host","path":"/valid","mode":"auto"}}}]}
EOF
! defaultBase64Code vlessXHTTP 443 user-bad-host uuid-a "cdn.example.com" "/ignored"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/user-bad-host" ]]

cat >"${configPath}12_VLESS_XHTTP_inbounds.json" <<'EOF'
{"inbounds":[{"streamSettings":{"xhttpSettings":{"host":"front.example.com","path":"/valid","mode":"future-mode"}}}]}
EOF
! defaultBase64Code vlessXHTTP 443 user-bad-mode uuid-a "cdn.example.com" "/ignored"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/user-bad-mode" ]]
(
    local configPath="${TMP_DIR}/reality-output-boundary/" coreInstallType=1 currentPath=padm
    local currentInstallProtocolType=,1,2,26, currentCDNAddress=node.example.com
    local xrayVLESSRealitySNI=sni.example.com xrayVLESSRealityXHTTPSNI=sni.example.com
    local currentRealityPublicKey=pubkey currentRealityXHTTPPublicKey=pubkey
    local xrayVLESSRealityXHTTPort=443 currentRealityMldsa65Verify=
    local singBoxVLESSRealityGRPCSNI= singBoxVLESSRealityPublicKey=
    local PADM_VLESS_REALITY_CONFIG_FILE= PADM_VLESS_XHTTP_CONFIG_FILE=
    local protocol configFile inboundIndex field value account grpcSNI grpcPublicKey grpcPQV index=0 failed=0
    realityStreamPublicPortForProtocol() { :; }
    corePortSubscriptionPort() { printf '%s\n' "$2"; }
    mkdir -p "${configPath}"
    for protocol in vision grpc xhttp; do
        inboundIndex=0
        case "${protocol}" in
        vision) configFile="${configPath}07_VLESS_vision_reality_inbounds.json"; inboundIndex=1 ;;
        grpc) configFile="${configPath}08_VLESS_vision_gRPC_inbounds.json" ;;
        xhttp) configFile="${configPath}12_VLESS_XHTTP_inbounds.json" ;;
        esac
        for field in publicKey mldsa65Verify sni; do
            for value in '42' 'false' '{}' '[]' '"bad\nfield"' '"bad\n"' '"bad&security=none"' '"bad:"'; do
                index=$((index + 1))
                account="reality-boundary-${protocol}-${index}"
                jq -n --argjson index "${inboundIndex}" --arg email "${account}" \
                    --arg field "${field}" --argjson value "${value}" '
                    {inbounds:[{port:443}]} |
                    .inbounds[$index].settings = {clients:[{email:$email,id:"uuid"}],decryption:"none"} |
                    .inbounds[$index].streamSettings = {
                        realitySettings:{serverNames:["sni.example.com"],publicKey:"pubkey",mldsa65Verify:""},
                        xhttpSettings:{host:"",path:"/path",mode:"auto"}} |
                    if $field == "sni" then .inbounds[$index].streamSettings.realitySettings.serverNames[0] = $value
                    else .inbounds[$index].streamSettings.realitySettings[$field] = $value end
                ' >"${configFile}" || return 1
                case "${protocol}" in
                vision) showVlessRealityAccountsFromConfig 1 "${configFile}" 443 >/dev/null 2>&1 ;;
                grpc)
                    grpcSNI=sni.example.com grpcPublicKey=pubkey grpcPQV=
                    case "${field}" in
                    sni) grpcSNI=$(jq -r . <<<"${value}") || return 1 ;;
                    publicKey) grpcPublicKey=$(jq -r . <<<"${value}") || return 1 ;;
                    mldsa65Verify) grpcPQV=$(jq -r . <<<"${value}") || return 1 ;;
                    esac
                    showVlessRealityGrpcAccountsFromConfig "${configFile}" 443 "${grpcSNI}" "${grpcPublicKey}" "${grpcPQV}" >/dev/null 2>&1
                    ;;
                xhttp) showVlessRealityXHTTPAccounts >/dev/null 2>&1 ;;
                esac
                if [[ $? -eq 0 || -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" ||
                    -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" || -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]]; then
                    printf 'assert-fail:reality-field:%s:%s:%s\n' "${protocol}" "${field}" "${value}" >&2
                    failed=1
                fi
            done
        done
    done
    updateRoutingJsonConfig "${configFile}" '.inbounds[0].streamSettings.realitySettings |= {serverNames:["sni.example.com"],publicKey:"42",mldsa65Verify:""} | .inbounds[0].settings.clients[0].email = "reality-string-key"' || return 1
    showVlessRealityXHTTPAccounts >/dev/null || return 1
    grep -qx '      public-key: "42"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/reality-string-key" || return 1
    (
        local coreInstallType=2 singBoxVLESSRealityVisionSNI singBoxVLESSRealityPublicKey=pubkey
        local configFile="${TMP_DIR}/singbox-vision-boundary.json" value account index=0
        for value in '42' '"sni.example.com\n"'; do
            index=$((index + 1))
            account="singbox-vision-sni-${index}"
            jq -n --arg email "${account}" --argjson sni "${value}" \
                '{inbounds:[{users:[{name:$email,uuid:"uuid"}],tls:{server_name:$sni}}]}' >"${configFile}" || return 1
            singBoxVLESSRealityVisionSNI=$(jq -r '.inbounds[0].tls.server_name' "${configFile}") || return 1
            if showVlessRealityAccountsFromConfig 2 "${configFile}" 443 >/dev/null 2>&1 ||
                [[ -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" || -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" ||
                    -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]]; then
                printf 'assert-fail:singbox-vision-sni:%s\n' "${value}" >&2
                failed=1
            fi
        done
        [[ "${failed}" -eq 0 ]]
    ) || failed=1
    configPath="${TMP_DIR}/missing-reality-output-config/"
    serializeVlessRealityVisionLink() { return 1; }
    serializeVlessRealityGrpcLink() { return 1; }
    serializeVlessRealityXHTTPLink() { return 1; }
    for protocol in vlessReality vlessRealityGRPC vlessXHTTP; do
        account="serializer-failure-${protocol}"
        if defaultBase64Code "${protocol}" 443 "${account}" uuid node.example.com /path >/dev/null 2>&1 ||
            [[ -e "${SUBSCRIBE_CAPTURE_DIR}/default/${account}" || -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/${account}" ||
                -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${account}" ]]; then
            printf 'assert-fail:reality-serializer:%s\n' "${protocol}" >&2
            failed=1
        fi
    done
    [[ "${failed}" -eq 0 ]]
) || return 1
configPath="${oldConfigPath}"
unset REGRESSION_ERROR_CARD_LOG
}

runSubscriptionOutputPublishAccountsAndRemoteHintRegression() {
    local SUBSCRIBE_CAPTURE_DIR="${SUBSCRIBE_CAPTURE_DIR}-${BASHPID:-$$}"
    local PADM_SUBSCRIBE_LOCAL_DIR="${SUBSCRIBE_CAPTURE_DIR}"
(
    local publishRoot="${TMP_DIR}/subscription-output-publish-accounts"
    local localBase="${publishRoot}/local"
    local mainCheckFile="${publishRoot}/main-check-count"
    local output
    mkdir -p "${localBase}/default"
    : >"${localBase}/default/local-keep"
    printf '0\n' >"${mainCheckFile}"

    subscriptionGroupsStateRead() {
        if [[ "$*" == "-r .id" ]]; then
            printf 'default\n'
            return 0
        fi
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            printf '%s\n' "$(( $(<"${mainCheckFile}") + 1 ))" >"${mainCheckFile}"
            return 0
        fi
        return 1
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            printf '%s\n' "$(( $(<"${mainCheckFile}") + 1 ))" >"${mainCheckFile}"
            return 0
        fi
        if [[ "$*" == *'--argjson enabledUsers '* && "$*" == *'.allows_main // false'* && "$*" == *'.has_remote // false'* && "$*" == *'@tsv'* ]]; then
            printf 'sub_team_a\ttrue\tfalse\nsub_team_b\ttrue\tfalse\n'
            return 0
        fi
        return 1
    }
    subscriptionActiveEnabledUsersJson() {
        printf '[{"id":"team-a","account":"sub_team_a","allowed_sources":["main"],"allows_main":true,"has_remote":false},{"id":"team-b","account":"sub_team_b","allowed_sources":["main"],"allows_main":true,"has_remote":false}]\n'
    }
    subscriptionSyncFindUserByAccountName() {
        return 99
    }

    output=$(subscriptionPublishAccounts "${localBase}")
    [[ "${output}" == $'local-keep\nsub_team_a\nsub_team_b' ]]
    [[ "$(<"${mainCheckFile}")" == "1" ]]
)

(
    local sourceLines
    local helperAccountFile="${TMP_DIR}/subscription-output-remote-hint-account.log"
    subscriptionRemoteScopeEnabled() { return 0; }
    subscriptionSyncFindUserByAccountName() {
        printf '%s\n' "$1" >"${helperAccountFile}"
        printf '{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"]}\n'
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'--argjson allowed ["edge"]'* && "$*" == *'.id as $sid | $allowed | index($sid)'* ]]; then
            printf 'edge\n'
            return 0
        fi
        return 1
    }
    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount sub_team_a)
    [[ "${sourceLines}" == "edge" ]]
    grep -qx 'sub_team_a' "${helperAccountFile}"

    subscriptionActiveGroupRead() {
        return 0
    }
    sourceLines=unexpected
    subscriptionRemoteSubscribeSourcesForAccount sub_team_a sourceLines
    [[ -z "${sourceLines}" ]]
)

(
    local renderRoot="${TMP_DIR}/subscription-render-remote-hint-batch"
    local localBase="${renderRoot}/local"
    local remoteChecksFile="${renderRoot}/remote-checks.log"
    local autoReadCalls=0
    local oldSubscribeSalt="${subscribeSalt:-}"
    local oldCurrentDefaultPort="${currentDefaultPort:-}"
    mkdir -p "${localBase}/default" "${renderRoot}"
    : >"${remoteChecksFile}"
    subscribeSalt=test-salt
    currentDefaultPort=443
    subscriptionRemoteScopeEnabled() { return 0; }

    subscriptionActiveGroupRead() {
        if [[ "$*" == *'any(.sources[]?; .id == "main" and ((.enabled // true) == true))'* ]]; then
            return 1
        fi
        if [[ "$*" == *'--argjson enabledUsers '* && "$*" == *'.has_remote // false'* && "$*" == *'@tsv'* ]]; then
            printf 'sub_team_a\tfalse\ttrue\n'
            return 0
        fi
        return 1
    }
    subscriptionActiveEnabledUsersJson() {
        printf '[{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"],"allows_main":false,"has_remote":true}]\n'
    }
    subscriptionPublishHasRemoteSources() {
        return 99
    }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf '%s\n' "$1" >>"${remoteChecksFile}"
        printf 'example.com:443:edge:https\n'
    }
    autoRead() {
        autoReadCalls=$((autoReadCalls + 1))
        printf -v "$3" 'y'
    }
    resolveSubscribePublicDomain() {
        printf 'example.com'
    }
    renderSubscribeUserOutputs() {
        [[ "$1" == "sub_team_a" && "$4" == "y" ]]
    }

    renderAllSubscribeUserOutputs "${localBase}" "" true "" true
    [[ "${autoReadCalls}" == "1" ]]
    [[ ! -s "${remoteChecksFile}" ]]

    if [[ -n "${oldSubscribeSalt}" ]]; then
        subscribeSalt="${oldSubscribeSalt}"
    else
        unset subscribeSalt
    fi
    if [[ -n "${oldCurrentDefaultPort}" ]]; then
        currentDefaultPort="${oldCurrentDefaultPort}"
    else
        unset currentDefaultPort
    fi
)

(
    local renderRoot="${TMP_DIR}/subscription-render-remote-hint-override"
    local localBase="${renderRoot}/local"
    local helperAccountsFile="${renderRoot}/helper-accounts.log"
    local unexpectedRemoteChecksFile="${renderRoot}/unexpected-remote-checks.log"
    local autoReadCalls=0
    local oldSubscribeSalt="${subscribeSalt:-}"
    local oldCurrentDefaultPort="${currentDefaultPort:-}"
    mkdir -p "${localBase}/default" "${renderRoot}"
    : >"${helperAccountsFile}"
    : >"${unexpectedRemoteChecksFile}"
    subscribeSalt=test-salt
    currentDefaultPort=443
    subscriptionRemoteScopeEnabled() { return 0; }

    subscriptionPublishHasRemoteSources() {
        printf '%s\n' "$1" >"${helperAccountsFile}"
        return 0
    }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf '%s\n' "$1" >>"${unexpectedRemoteChecksFile}"
        printf 'example.com:443:edge:https\n'
    }
    autoRead() {
        autoReadCalls=$((autoReadCalls + 1))
        printf -v "$3" 'y'
    }
    resolveSubscribePublicDomain() {
        printf 'example.com'
    }
    renderSubscribeUserOutputs() {
        [[ "$1" == "sub_team_a" && "$4" == "y" ]]
    }

    renderAllSubscribeUserOutputs "${localBase}" "" true "sub_team_a" true
    [[ "${autoReadCalls}" == "1" ]]
    grep -qx 'sub_team_a' "${helperAccountsFile}"
    [[ ! -s "${unexpectedRemoteChecksFile}" ]]

    if [[ -n "${oldSubscribeSalt}" ]]; then
        subscribeSalt="${oldSubscribeSalt}"
    else
        unset subscribeSalt
    fi
    if [[ -n "${oldCurrentDefaultPort}" ]]; then
        currentDefaultPort="${oldCurrentDefaultPort}"
    else
        unset currentDefaultPort
    fi
)
}

runSubscriptionOutputPartialRemoteSourcesRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/subscription-output-partial-remote-sources"
    local localBase="${root}/local"
    local publicBase="${root}/public"
    local email=sub_team_a
    local emailMd5
    local goodDefault
    local goodClashMeta
    local goodSingBox
    local syncSnapshots

    mkdir -p "${root}/tmp" "${localBase}" "${publicBase}"
    TMPDIR="${root}/tmp"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localBase}"
    export PADM_SUBSCRIBE_DIR="${publicBase}"
    subscribeSalt=test-salt
    emailMd5=$(printf '%s\n' "${email}${subscribeSalt}" | md5sum | awk '{print $1}')
    goodDefault=$(printf 'vless://good\n' | base64 -w 0)
    goodClashMeta=$'  - name: sub_team_a\n    server: good.example.com'
    goodSingBox='[{"tag":"sub_team_a","type":"vless","server":"good.example.com"}]'
    syncSnapshots=$(jq -cn \
        --arg default "${goodDefault}" \
        --arg clashMeta "${goodClashMeta}" \
        --argjson singBox "${goodSingBox}" \
        '{"edge-good":{"sub_team_a":{"default":$default,"clash_meta":$clashMeta,"sing_box":$singBox}},"edge-bad":{"sub_team_a":{"default":"","clash_meta":"bad","sing_box":[]}}}')

    subscriptionRemoteScopeEnabled() { return 0; }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf -v "$2" '%s' $'edge-good\nedge-bad'
    }
    subscriptionActiveGroupRead() {
        case "$*" in
        *'--arg id edge-good'*) printf '%s\n' '{"id":"edge-good","host":"good.example.com","port":443}' ;;
        *'--arg id edge-bad'*) printf '%s\n' '{"id":"edge-bad","host":"bad.example.com","port":443}' ;;
        *) return 1 ;;
        esac
    }

    stageRemoteSubscribe "${emailMd5}" "${email}" "${syncSnapshots}"
    grep -qx 'vless://good' "${publicBase}/default/${emailMd5}"
    grep -q 'sub_team_a_edge-good' "${publicBase}/clashMeta/${emailMd5}"
    ! grep -q 'edge-bad' "${publicBase}/default/${emailMd5}" "${publicBase}/clashMeta/${emailMd5}" "${localBase}/sing-box/${email}"
    jq -e 'length == 1 and .[0].tag == "sub_team_a_edge-good"' "${localBase}/sing-box/${email}" >/dev/null
)

runSubscriptionOutputRemoteOnlyAllFailedRestoreRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/subscription-output-remote-only-all-failed"
    local localBase="${root}/local"
    local publicBase="${root}/public"
    local email=sub_team_a
    local emailMd5

    mkdir -p \
        "${root}/tmp" \
        "${localBase}" \
        "${publicBase}/default" \
        "${publicBase}/clashMeta" \
        "${publicBase}/clashMetaProfiles" \
        "${publicBase}/sing-box_profiles" \
        "${publicBase}/sing-box"
    TMPDIR="${root}/tmp"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localBase}"
    export PADM_SUBSCRIBE_DIR="${publicBase}"
    export PADM_SUBSCRIBE_PREVIOUS_DIR="${publicBase}"
    subscribeSalt=test-salt
    emailMd5=$(printf '%s\n' "${email}${subscribeSalt}" | md5sum | awk '{print $1}')
    printf 'old-default\n' >"${publicBase}/default/${emailMd5}"
    printf 'old-clash\n' >"${publicBase}/clashMeta/${emailMd5}"
    printf 'old-clash-profile\n' >"${publicBase}/clashMetaProfiles/${emailMd5}"
    printf '[{"tag":"old-profile"}]\n' >"${publicBase}/sing-box_profiles/${emailMd5}"
    printf '{"outbounds":[{"tag":"old-sing-box"}]}\n' >"${publicBase}/sing-box/${emailMd5}"

    subscriptionRemoteScopeEnabled() { return 0; }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf -v "$2" '%s' $'edge-a\nedge-b'
    }
    subscriptionActiveGroupRead() {
        case "$*" in
        *'--arg id edge-a'*) printf '%s\n' '{"id":"edge-a","host":"a.example.com","port":443}' ;;
        *'--arg id edge-b'*) printf '%s\n' '{"id":"edge-b","host":"b.example.com","port":443}' ;;
        *) return 1 ;;
        esac
    }

    renderSubscribeUserOutputs "${email}" "${emailMd5}" example.com y true '{"edge-a":null,"edge-b":null}'
    [[ "$(<"${publicBase}/default/${emailMd5}")" == 'old-default' ]]
    [[ "$(<"${publicBase}/clashMeta/${emailMd5}")" == 'old-clash' ]]
    [[ "$(<"${publicBase}/clashMetaProfiles/${emailMd5}")" == 'old-clash-profile' ]]
    [[ "$(<"${publicBase}/sing-box_profiles/${emailMd5}")" == '[{"tag":"old-profile"}]' ]]
    [[ "$(<"${publicBase}/sing-box/${emailMd5}")" == '{"outbounds":[{"tag":"old-sing-box"}]}' ]]
)

runSubscriptionOutputMixedLocalRemoteAllFailedPreservesPreviousRegression() (
    set -euo pipefail
    local root="${TMP_DIR}/subscription-output-mixed-all-failed"
    local localBase="${root}/local"
    local publicBase="${root}/public"
    local email=sub_team_a
    local emailMd5

    mkdir -p \
        "${root}/tmp" \
        "${localBase}/default" \
        "${publicBase}/default" \
        "${publicBase}/clashMeta" \
        "${publicBase}/clashMetaProfiles" \
        "${publicBase}/sing-box_profiles" \
        "${publicBase}/sing-box"
    TMPDIR="${root}/tmp"
    export PADM_SUBSCRIBE_LOCAL_DIR="${localBase}"
    export PADM_SUBSCRIBE_DIR="${publicBase}"
    export PADM_SUBSCRIBE_PREVIOUS_DIR="${publicBase}"
    subscribeSalt=test-salt
    emailMd5=$(printf '%s\n' "${email}${subscribeSalt}" | md5sum | awk '{print $1}')
    printf 'new-local\n' >"${localBase}/default/${email}"
    printf 'old-combined-default\n' >"${publicBase}/default/${emailMd5}"
    printf 'old-combined-clash\n' >"${publicBase}/clashMeta/${emailMd5}"
    printf 'old-combined-clash-profile\n' >"${publicBase}/clashMetaProfiles/${emailMd5}"
    printf '[{"tag":"old-combined"}]\n' >"${publicBase}/sing-box_profiles/${emailMd5}"
    printf '{"outbounds":[{"tag":"old-combined"}]}\n' >"${publicBase}/sing-box/${emailMd5}"

    subscriptionRemoteScopeEnabled() { return 0; }
    subscriptionRemoteSubscribeSourcesForAccount() {
        printf -v "$2" '%s' $'edge-a\nedge-b'
    }
    subscriptionActiveGroupRead() {
        case "$*" in
        *'--arg id edge-a'*) printf '%s\n' '{"id":"edge-a","host":"a.example.com","port":443}' ;;
        *'--arg id edge-b'*) printf '%s\n' '{"id":"edge-b","host":"b.example.com","port":443}' ;;
        *) return 1 ;;
        esac
    }

    renderSubscribeUserOutputs "${email}" "${emailMd5}" example.com y true '{"edge-a":null,"edge-b":null}'
    [[ "$(<"${publicBase}/default/${emailMd5}")" == 'old-combined-default' ]]
    [[ "$(<"${publicBase}/clashMeta/${emailMd5}")" == 'old-combined-clash' ]]
    [[ "$(<"${publicBase}/clashMetaProfiles/${emailMd5}")" == 'old-combined-clash-profile' ]]
    [[ "$(<"${publicBase}/sing-box_profiles/${emailMd5}")" == '[{"tag":"old-combined"}]' ]]
    [[ "$(<"${publicBase}/sing-box/${emailMd5}")" == '{"outbounds":[{"tag":"old-combined"}]}' ]]
)

runSubscriptionOutputTlsVlessVmessTrojanRegression() {
    (
        # 各账号读取入口独立传播读取和输出失败，不改变调用方的 pipefail。
        set +o pipefail
        local configPath="${TMP_DIR}/tls-account-reader/"
        local singBoxConfigPath= currentDefaultPort=443 coreInstallType=1
        local currentInstallProtocolType=,27,21,22,24,25,2,
        local currentPath=padm currentCDNAddress=cdn.example.com
        local xrayVLESSRealityXHTTPort=443 reader configFile variant
        local capture="${TMP_DIR}/tls-account-reader.log"
        mkdir -p "${configPath}"
        subscribeSectionTitle() { :; }
        subscribeAccountTitle() { :; }
        realityStreamPublicPortForProtocol() { :; }
        corePortSubscriptionPort() { printf '%s\n' "$2"; }
        xrayRealityXHTTPSetting() { printf '%s\n' "$2"; }
        for reader in showVlessTcpAccounts showVlessWsAccounts showVmessWsAccounts showVlessGrpcAccounts showTrojanGrpcAccounts showVlessRealityXHTTPAccounts; do
            case "${reader}" in
            showVlessTcpAccounts) configFile=02_VLESS_TCP_inbounds.json ;;
            showVlessWsAccounts) configFile=03_VLESS_WS_inbounds.json ;;
            showVmessWsAccounts) configFile=05_VMess_WS_inbounds.json ;;
            showVlessGrpcAccounts) configFile=06_VLESS_GRPc_inbounds.json ;;
            showTrojanGrpcAccounts) configFile=04_trojan_GRPc_inbounds.json ;;
            showVlessRealityXHTTPAccounts) configFile=12_VLESS_XHTTP_inbounds.json ;;
            esac
            defaultBase64Code() { printf 'output\n' >>"${capture}"; }
            for variant in null '{}'; do
                jq -n --argjson clients "${variant}" '{inbounds:[{port:443,settings:{clients:$clients}}]}' >"${configPath}${configFile}"
                : >"${capture}"
                regressionExpectFailure "${reader}" >/dev/null 2>&1 || return 1
                [[ ! -s "${capture}" ]] || return 1
            done
            printf '{invalid\n' >"${configPath}${configFile}"
            regressionExpectFailure "${reader}" >/dev/null 2>&1 || return 1
            printf '{"inbounds":[{"port":443,"settings":{"clients":[]}}]}\n' >"${configPath}${configFile}"
            "${reader}" >/dev/null || return 1
            [[ ! -s "${capture}" ]] || return 1
            printf '{"inbounds":[{"port":443,"settings":{"clients":[{"email":"sub-reader","id":"uuid","password":"pass"}]}}]}\n' >"${configPath}${configFile}"
            defaultBase64Code() { printf 'failed-write\n' >>"${capture}"; return 1; }
            regressionExpectStatus 1 "${reader}" >/dev/null 2>&1 || return 1
            [[ "$(<"${capture}")" == failed-write ]] || return 1
            [[ "${SHELLOPTS}" != *pipefail* ]] || return 1
        done
    ) || return 1
    local SUBSCRIBE_CAPTURE_DIR="${SUBSCRIBE_CAPTURE_DIR}-${BASHPID:-$$}"
    local PADM_SUBSCRIBE_LOCAL_DIR="${SUBSCRIBE_CAPTURE_DIR}"
local quotedTlsUser='tls-"quoted-user'
rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
currentHost="tls.example.com"
! defaultBase64Code vlesstcp 443 "${quotedTlsUser}" uuid-quoted "" "" >/dev/null 2>&1
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/${quotedTlsUser}" ]]

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
defaultBase64Code vlesstcp 443 tls-user uuid-tls "" ""
assertCapturedSubscribeOutputs "tls-user" "vless://uuid-tls@[2001:db8::10]:443?encryption=none&security=tls&type=tcp&host=2001:db8::10&fp=chrome&headerType=none&sni=2001:db8::10&flow=xtls-rprx-vision#tls-user" "2001:db8::10" "2001:db8::10" "tcp" "vless"
assertDisplayedDefaultSubscribeLink "tls-user" "通用格式：VLESS TCP TLS Vision"
jq -e '.[0].flow == "xtls-rprx-vision" and (.[0].tls.reality | not)' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vlessws 443 tls-ws-user uuid-ws "2001:db8::20" "/ws-path"
assertCapturedSubscribeOutputs "tls-ws-user" "vless://uuid-ws@[2001:db8::20]:443?encryption=none&security=tls&type=ws&host=tls.example.com&sni=tls.example.com&fp=chrome&path=/ws-path#tls-ws-user" "2001:db8::20" "tls.example.com" "ws" "vless"
assertDisplayedDefaultSubscribeLink "tls-ws-user" "通用格式：VLESS WS TLS"
jq -e '.[0].transport.path == "/ws-path" and .[0].transport.headers.Host == "tls.example.com" and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-ws-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code vlessgrpc 443 tls-grpc-user uuid-grpc "2001:db8::20" ""
assertCapturedSubscribeOutputs "tls-grpc-user" "vless://uuid-grpc@[2001:db8::20]:443?encryption=none&security=tls&type=grpc&host=tls.example.com&path=svc-grpc&serviceName=svc-grpc&fp=chrome&alpn=h2&sni=tls.example.com#tls-grpc-user" "2001:db8::20" "tls.example.com" "grpc" "vless"
assertDisplayedDefaultSubscribeLink "tls-grpc-user" "通用格式：VLESS gRPC TLS"
jq -e '.[0].transport.service_name == "svc-grpc" and .[0].packet_encoding == "xudp"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-grpc-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessws 443 tls-vmess-user uuid-vmess "edge.example.com" "/vmess-ws"
vmessWsLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-vmess-user")
[[ "${vmessWsLink}" == vmess://* ]]
vmessWsJson=$(printf '%s' "${vmessWsLink#vmess://}" | base64 -d)
jq -e '.port == 443 and .ps == "tls-vmess-user" and .net == "ws" and .path == "/vmess-ws" and .add == "edge.example.com"' <<<"${vmessWsJson}" >/dev/null
grep -qxF "green     ${vmessWsJson}\\n" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"
assertCapturedSubscribeOutputs "tls-vmess-user" "${vmessWsLink}" "edge.example.com" "tls.example.com" "ws" "vmess"
assertDisplayedDefaultSubscribeLink "tls-vmess-user" "通用链接：VMess WS TLS"
jq -e '.[0].alter_id == 0 and .[0].transport.max_early_data == 2048 and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-vmess-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
defaultBase64Code trojan 443 tls-trojan-user "@:/?#[]" "" ""
assertCapturedSubscribeOutputs "tls-trojan-user" "trojan://%40%3A%2F%3F%23%5B%5D@[2001:db8::10]:443?peer=2001:db8::10&fp=chrome&sni=2001:db8::10&alpn=http/1.1#tls-trojan-user_Trojan" "2001:db8::10" "2001:db8::10" "tcp" "trojan"
assertDisplayedDefaultSubscribeLink "tls-trojan-user" "通用链接：Trojan TLS"
grep -qxF '    password: "@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-trojan-user"
jq -e '.[0].password == "@:/?#[]" and .[0].tls.alpn[0] == "http/1.1"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-trojan-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
currentPath="svc-"
defaultBase64Code trojangrpc 443 tls-trojan-grpc-user "grpc@:/?#[]" "2001:db8::20" ""
assertCapturedSubscribeOutputs "tls-trojan-grpc-user" "trojan://grpc%40%3A%2F%3F%23%5B%5D@[2001:db8::20]:443?encryption=none&peer=tls.example.com&security=tls&type=grpc&fp=chrome&sni=tls.example.com&alpn=h2&path=svc-trojangrpc&serviceName=svc-trojangrpc#tls-trojan-grpc-user" "2001:db8::20" "tls.example.com" "grpc" "trojan"
assertDisplayedDefaultSubscribeLink "tls-trojan-grpc-user" "通用链接：Trojan gRPC TLS"
grep -qxF '    password: "grpc@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-trojan-grpc-user"
jq -e '.[0].transport.service_name == "svc-trojangrpc" and (.[0].tls | has("insecure") | not) and .[0].multiplex.enabled == false' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-trojan-grpc-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
defaultBase64Code vmessHTTPUpgrade 443 tls-httpupgrade-user uuid-http "edge.example.com" "/upgrade"
httpUpgradeLink=$(sed -n '1p' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-httpupgrade-user")
[[ "${httpUpgradeLink}" == vmess://* ]]
[[ "${httpUpgradeLink}" != " "* ]]
httpUpgradeJson=$(printf '%s' "${httpUpgradeLink#vmess://}" | base64 -d)
jq -e '.port == 443 and .ps == "tls-httpupgrade-user" and .net == "httpupgrade" and .path == "/upgrade" and .add == "edge.example.com"' <<<"${httpUpgradeJson}" >/dev/null
grep -qxF "green     ${httpUpgradeJson}\\n" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"
assertCapturedSubscribeOutputs "tls-httpupgrade-user" "${httpUpgradeLink}" "edge.example.com" "tls.example.com" "httpupgrade" "vmess"
assertDisplayedDefaultSubscribeLink "tls-httpupgrade-user" "通用链接：VMess HTTPUpgrade TLS"
jq -e '.[0].security == "auto" and .[0].transport.path == "/upgrade" and .[0].packet_encoding == "packetaddr"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-httpupgrade-user" >/dev/null
unset REGRESSION_ECHO_LOG
}

runSubscriptionOutputAuxiliaryUdpRegression() (
    local root="${TMP_DIR}/subscription-output-auxiliary-udp"
    local uuid=11111111-1111-1111-1111-111111111111
    local desired='[{"id":"team-a","uuid":"11111111-1111-1111-1111-111111111111"}]'
    local mode subscriptions links
    local hysteria2PortHoppingStart= hysteria2PortHoppingEnd= hysteria2PortHopping=
    local tuicPortHoppingStart= tuicPortHoppingEnd= tuicPortHopping=
    local configPath="${root}/xray/" singBoxConfigPath="${root}/sing-box/"
    local PADM_REALITY_ENTRY_HOST_FILE="${root}/entry-host"
    local PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    source "${PROJECT_ROOT}/shell/subscription/output.sh"
    readInstallType() { :; }
    readPortHopping() { :; }
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    printf '192.0.2.10\n' >"${PADM_REALITY_ENTRY_HOST_FILE}"
    cat >"${configPath}07_VLESS_vision_reality_inbounds.json" <<'JSON'
{"inbounds":[{"port":443},{"settings":{"clients":[],"decryption":"none"},"streamSettings":{"realitySettings":{"serverNames":["www.example.com"],"target":"www.example.com:443","publicKey":"public-key","privateKey":"private-key"}}}]}
JSON
    ensureSubscriptionGroupsState
    subscriptionApplyUserGroupState "${desired}" '[]'
    for mode in reality tls singbox; do
        coreInstallType=1
        if [[ "${mode}" == tls ]]; then
            printf '%s\n' '{"inbounds":[{"port":443,"settings":{"clients":[]},"streamSettings":{"tlsSettings":{"certificates":[{"certificateFile":"/etc/padm/tls/main.example.com.crt"}]}}}]}' >"${configPath}28_trojan_TCP_direct_inbounds.json"
        elif [[ "${mode}" == singbox ]]; then
            coreInstallType=2
            configPath="${singBoxConfigPath}"
        fi
        printf '%s\n' '{"inbounds":[{"type":"hysteria2","listen_port":8443,"users":[],"up_mbps":100,"down_mbps":200,"tls":{"enabled":true,"server_name":"hy.example.com"}}]}' >"${singBoxConfigPath}06_hysteria2_inbounds.json"
        printf '%s\n' '{"inbounds":[{"type":"tuic","listen_port":9443,"users":[],"congestion_control":"bbr","tls":{"enabled":true,"server_name":"tuic.example.com"}}]}' >"${singBoxConfigPath}09_tuic_inbounds.json"
        subscriptionSyncAppendLocalUser team-a
        subscriptions=$(subscriptionControlRenderSubscribeAccounts "${desired}") || {
            printf 'assert-fail:auxiliary-udp-render:%s\n' "${mode}" >&2
            return 1
        }
        links=$(jq -r '.sub_team_a.default' <<<"${subscriptions}" | base64 -d)
        grep -qF "hysteria2://${uuid}@hy.example.com:8443?peer=hy.example.com&insecure=0&sni=hy.example.com&alpn=h3&upmbps=200&downmbps=100#" <<<"${links}"
        grep -qF "tuic://${uuid}:${uuid}@tuic.example.com:9443?congestion_control=bbr&alpn=h3&sni=tuic.example.com&udp_relay_mode=native&allow_insecure=0#" <<<"${links}"
        jq -e --arg uuid "${uuid}" '
          .sub_team_a as $account |
          ($account.clash_meta | contains("server: hy.example.com") and contains("sni: hy.example.com") and
            contains("server: tuic.example.com") and contains("sni: tuic.example.com")) and
          ([$account.sing_box[] | select(.type == "hysteria2" or .type == "tuic")] |
            length == 2 and all(.[]; .password == $uuid) and
            any(.[]; .type == "hysteria2" and .server == "hy.example.com" and .server_port == 8443 and .up_mbps == 200 and .down_mbps == 100 and .tls.server_name == "hy.example.com") and
            any(.[]; .type == "tuic" and .server == "tuic.example.com" and .server_port == 9443 and .tls.server_name == "tuic.example.com" and .uuid == $uuid))
        ' <<<"${subscriptions}" >/dev/null
        printf 'regression-ok:auxiliary-udp-output:%s\n' "${mode}"
    done
    (
        # 调用方未开启 pipefail 时，坏 users 和输出写入失败仍必须返回失败。
        set +o pipefail
        local functionName configFile userJson variant
        local capture="${root}/failed-output.log"
        currentInstallProtocolType=,3,31,
        singBoxHysteria2Port=8443
        singBoxTuicPort=9443
        for functionName in showHysteriaAccounts showTuicAccounts; do
            if [[ "${functionName}" == showHysteriaAccounts ]]; then
                configFile="${singBoxConfigPath}06_hysteria2_inbounds.json"
                userJson='{"name":"sub_hy","password":"pass"}'
            else
                configFile="${singBoxConfigPath}09_tuic_inbounds.json"
                userJson='{"name":"sub_tuic","uuid":"uuid","password":"pass"}'
            fi
            defaultBase64Code() { printf '%s\n' output >>"${capture}"; }
            for variant in null '{}'; do
                jq -n --argjson users "${variant}" \
                    '{inbounds:[{tls:{server_name:"udp.example.com"},users:$users}]}' >"${configFile}"
                : >"${capture}"
                regressionExpectStatus 1 "${functionName}" >/dev/null 2>&1 || return 1
                [[ ! -s "${capture}" ]] || return 1
            done
            jq -n '{inbounds:[{tls:{server_name:"udp.example.com"},users:[]}]}' >"${configFile}"
            "${functionName}" >/dev/null || return 1
            [[ ! -s "${capture}" ]] || return 1
            local password
            for password in $'bad\037password' $'bad\npassword' $'bad\rpassword'; do
                jq -n --argjson user "${userJson}" --arg password "${password}" \
                    '{inbounds:[{tls:{server_name:"udp.example.com"},users:[$user | .password = $password]}]}' >"${configFile}"
                : >"${capture}"
                regressionExpectStatus 1 "${functionName}" >/dev/null 2>&1 || return 1
                [[ ! -s "${capture}" ]] || return 1
            done
            local passwordJson
            for passwordJson in '{}' '[]'; do
                jq -n --argjson user "${userJson}" --argjson password "${passwordJson}" \
                    '{inbounds:[{tls:{server_name:"udp.example.com"},users:[$user | .password = $password]}]}' >"${configFile}"
                : >"${capture}"
                regressionExpectStatus 1 "${functionName}" >/dev/null 2>&1 || return 1
                [[ ! -s "${capture}" ]] || return 1
            done
            jq -n --argjson user "${userJson}" \
                '{inbounds:[{tls:{server_name:"udp.example.com"},users:[$user]}]}' >"${configFile}"
            defaultBase64Code() { printf '%s\n' failed-write >>"${capture}"; return 1; }
            regressionExpectStatus 1 "${functionName}" >/dev/null 2>&1 || return 1
            [[ "$(<"${capture}")" == failed-write ]] || return 1
        done
    ) || return 1
)

runSubscriptionOutputTlsAnyHysteriaTuicNaiveRegression() {
    runRegressionStep subscription-output-auxiliary-udp runSubscriptionOutputAuxiliaryUdpRegression
    local tlsBoundaryFailed=0
    (
        local configPath="${TMP_DIR}/tls-reader-tail-lf/" coreInstallType=2 singBoxConfigPath=
        local currentInstallProtocolType=,3,5,4,31, currentHost=tls.example.com
        local singBoxHysteria2Port=8443 singBoxTuicPort=9443 singBoxNaivePort=443 singBoxAnyTLSPort=443
        local hysteria2PortHoppingStart= hysteria2PortHoppingEnd= hysteria2PortHopping=
        local reader readerConfigFile status failed=0 capture="${TMP_DIR}/tls-reader-tail-lf-output"
        local -a readerArgs=()
        mkdir -p "${configPath}"
        readPortHopping() { :; }
        protocolConfigFile() { printf '%s\n' "${readerConfigFile}"; }
        defaultBase64Code() { printf 'unexpected\n' >>"${capture}"; }
        for reader in showTrojanAccountsFromConfig showHysteriaAccounts showTuicAccounts showNaiveAccounts showAnyTlsAccounts; do
            case "${reader}" in
            showTrojanAccountsFromConfig) readerConfigFile="${configPath}trojan.json" ;;
            showHysteriaAccounts) readerConfigFile="${configPath}hysteria.json" ;;
            showTuicAccounts) readerConfigFile="${configPath}tuic.json" ;;
            showNaiveAccounts) readerConfigFile="${configPath}10_naive_inbounds.json" ;;
            showAnyTlsAccounts) readerConfigFile="${configPath}13_anytls_inbounds.json" ;;
            esac
            readerArgs=()
            [[ "${reader}" != showTrojanAccountsFromConfig ]] || readerArgs=("${readerConfigFile}" 443)
            jq -n '{inbounds:[{tls:{server_name:"tls.example.com"},users:[{name:"tail-lf-user",uuid:"uuid",password:"pass"}]}]}' >"${readerConfigFile}" || return 1
            : >"${capture}"
            "${reader}" "${readerArgs[@]}" >/dev/null 2>&1; status=$?
            if [[ "${status}" -ne 0 || ! -s "${capture}" ]]; then
                printf 'assert-fail:tls-reader-baseline:%s\n' "${reader}" >&2
                failed=1
            fi
            jq -n '{inbounds:[{tls:{server_name:"tls.example.com\n"},users:[{name:"tail-lf-user",uuid:"uuid",password:"pass"}]}]}' >"${readerConfigFile}" || return 1
            : >"${capture}"
            "${reader}" "${readerArgs[@]}" >/dev/null 2>&1; status=$?
            if [[ "${status}" -eq 0 || -s "${capture}" ]]; then
                printf 'assert-fail:tls-reader-tail-lf:%s\n' "${reader}" >&2
                failed=1
            fi
        done
        [[ "${failed}" -eq 0 ]]
    ) || tlsBoundaryFailed=1
    local SUBSCRIBE_CAPTURE_DIR="${SUBSCRIBE_CAPTURE_DIR}-${BASHPID:-$$}"
    local PADM_SUBSCRIBE_LOCAL_DIR="${SUBSCRIBE_CAPTURE_DIR}"
subscribeOutputPortIsValid hysteria "20000-20002"
subscribeOutputPortIsValid tuic "30000-30002"
! subscribeOutputPortIsValid vlesstcp "20000-20002"
! subscribeOutputPortIsValid hysteria "20002-20000"
! subscribeOutputPortIsValid hysteria "0-20000"
! subscribeOutputPortIsValid anytls 65536

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
! defaultBase64Code vlesstcp 0 invalid-port-user invalid-port-id "" "" >/dev/null 2>&1
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/invalid-port-user" ]]
defaultBase64Code vlesstcp 08443 leading-zero-port-user uuid-leading-zero "" "" >/dev/null || return 1
grep -qF ':8443?' "${SUBSCRIBE_CAPTURE_DIR}/default/leading-zero-port-user" || return 1
grep -qx '    port: 8443' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/leading-zero-port-user" || return 1
jq -e '.[0].server_port == 8443' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/leading-zero-port-user" >/dev/null || return 1

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
export REGRESSION_ECHO_LOG="${SUBSCRIBE_CAPTURE_DIR}/screen.log"
currentHost="2001:db8::10"
singBoxAnyTLSPort=8443
defaultBase64Code anytls 443 tls-any-user "pass@:/?#[]" "" ""
assertCapturedSubscribeOutputs "tls-any-user" "anytls://pass%40%3A%2F%3F%23%5B%5D@[2001:db8::10]:8443?peer=2001:db8::10&insecure=0&sni=2001:db8::10#tls-any-user" "2001:db8::10" "2001:db8::10" "tcp" "anytls"
assertDisplayedDefaultSubscribeLink "tls-any-user" "通用链接：AnyTLS"
grep -qxF '    password: "pass@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-any-user"
jq -e '.[0].password == "pass@:/?#[]" and .[0].server_port == 8443' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-any-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
singBoxHysteria2Port=9443
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
hysteriaV2rayN=$(jq() { command jq "$@"; }; defaultBase64Code hysteria 8443 tls-hysteria-user "pass@:/?#[]" "" "")
assertCapturedSubscribeOutputs "tls-hysteria-user" "hysteria2://pass%40%3A%2F%3F%23%5B%5D@[2001:db8::10]:8443?peer=2001:db8::10&insecure=0&sni=2001:db8::10&alpn=h3&upmbps=100&downmbps=200#tls-hysteria-user" "2001:db8::10" "2001:db8::10" "tcp" "hysteria2" || return 1
assertDisplayedDefaultSubscribeLink "tls-hysteria-user" "通用链接：Hysteria2 TLS"
grep -qxF '    password: "pass@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-user"
jq -e '.server == "[2001:db8::10]:8443" and .auth == "pass@:/?#[]" and .tls.sni == "2001:db8::10" and .socks5.timeout == 300' <<<"${hysteriaV2rayN}" >/dev/null
jq -e '.[0].server_port == 8443 and .[0].password == "pass@:/?#[]" and .[0].up_mbps == 100 and .[0].down_mbps == 200 and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-hysteria-user" >/dev/null || return 1

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2BandwidthMode=bbr
hysteria2ClientUploadSpeed=
hysteria2ClientDownloadSpeed=
hysteria2ObfsType=salamander
hysteria2ObfsPassword='obfs@:/?#[]'
defaultBase64Code hysteria 9443 tls-hysteria-bbr-user pass-hysteria-bbr "" ""
grep -qxF "hysteria2://pass-hysteria-bbr@tls.example.com:9443?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3&obfs=salamander&obfs-password=obfs%40%3A%2F%3F%23%5B%5D#tls-hysteria-bbr-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-hysteria-bbr-user"
! grep -qE '^    (up|down):' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-bbr-user"
jq -e '.[0].type == "hysteria2" and (.[0].up_mbps | not) and (.[0].down_mbps | not) and .[0].obfs.type == "salamander" and .[0].obfs.password == "obfs@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-hysteria-bbr-user" >/dev/null

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2BandwidthMode=brutal
hysteria2ObfsType=gecko
hysteria2ObfsPassword='obfs@:/?#[]'
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria 9443 tls-hysteria-brutal-obfs-user pass-hysteria-brutal-obfs "" "" >/dev/null
grep -qxF '    up: "100 Mbps"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-brutal-obfs-user"
grep -qxF '    down: "200 Mbps"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-brutal-obfs-user"
grep -qxF '    obfs: "gecko"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-brutal-obfs-user"
grep -qxF '    obfs-password: "obfs@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-brutal-obfs-user"

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="tls.example.com"
singBoxHysteria2Port=9443
hysteria2BandwidthMode=brutal
hysteria2ObfsType=
hysteria2ObfsPassword=
hysteria2ClientUploadSpeed=100
hysteria2ClientDownloadSpeed=200
defaultBase64Code hysteria "20000-20002" tls-hysteria-hop-user pass-hysteria-hop "" "" >/dev/null
grep -qxF "hysteria2://pass-hysteria-hop@tls.example.com:20000-20002?peer=tls.example.com&insecure=0&sni=tls.example.com&alpn=h3&upmbps=100&downmbps=200#tls-hysteria-hop-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-hysteria-hop-user"
grep -qx "    ports: 20000-20002" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-hysteria-hop-user"
jq -e '.[0].server_ports == ["20000:20002"] and (.[0].server_port | not)' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-hysteria-hop-user" >/dev/null
[[ -f "${SUBSCRIBE_CAPTURE_DIR}/screen.log" ]] || return 1
if grep -q 'mport' "${SUBSCRIBE_CAPTURE_DIR}/default/tls-hysteria-hop-user" "${SUBSCRIBE_CAPTURE_DIR}/screen.log"; then
    return 1
fi

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
tuicAlgorithm="bbr"
singBoxTuicPort=8443
tuicV2rayN=$(jq() { command jq "$@"; }; defaultBase64Code tuic 9443 tls-tuic-user "uuid-tuic_pass@:/?#[]" "" "")
grep -qxF "tuic://uuid-tuic:pass%40%3A%2F%3F%23%5B%5D@[2001:db8::10]:9443?congestion_control=bbr&alpn=h3&sni=2001:db8::10&udp_relay_mode=native&allow_insecure=0#tls-tuic-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-tuic-user"
assertDisplayedDefaultSubscribeLink "tls-tuic-user" "通用链接：Tuic TLS"
jq -e '.relay.server == "[2001:db8::10]:9443" and .relay.ip == "2001:db8::10" and .relay.uuid == "uuid-tuic" and .relay.password == "pass@:/?#[]" and .relay.congestion_control == "bbr" and .local.server == "127.0.0.1:7798"' <<<"${tuicV2rayN}" >/dev/null
grep -qx "    server: 2001:db8::10" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qxF '    password: "pass@:/?#[]"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    udp-relay-mode: native" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    disable-sni: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    reduce-rtt: false" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
grep -qx "    sni: 2001:db8::10" "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-tuic-user"
jq -e '.[0].type == "tuic" and .[0].server == "2001:db8::10" and .[0].tls.server_name == "2001:db8::10"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-tuic-user" >/dev/null
jq -e '.[0].server_port == 9443 and .[0].uuid == "uuid-tuic" and .[0].password == "pass@:/?#[]" and .[0].congestion_control == "bbr" and .[0].udp_relay_mode == "native" and .[0].zero_rtt_handshake == false and .[0].tls.alpn[0] == "h3"' "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-tuic-user" >/dev/null || return 1

(
    # 标准订阅写入失败必须向上传播，不能继续生成 v2rayN 输出。
    local protocol credential outputTitle appendReached v2rayNReached
    appendStandardTLSSubscribeOutputs() { appendReached=true; return 1; }
    subscribeOutputTitle() { [[ "$1" != "${outputTitle}" ]] || v2rayNReached=true; }
    for protocol in hysteria tuic; do
        appendReached=false v2rayNReached=false
        credential="pass@:/?#[]" outputTitle="v2rayN：Hysteria2 TLS"
        [[ "${protocol}" != tuic ]] || { credential="uuid-tuic_pass@:/?#[]"; outputTitle="v2rayN：Tuic TLS"; }
        regressionExpectStatus 1 defaultBase64Code "${protocol}" 9443 "tls-${protocol}-failure-user" "${credential}" "" "" >/dev/null || return 1
        [[ "${appendReached}" == true && "${v2rayNReached}" == false ]] || return 1
    done
) || return 1

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
defaultBase64Code naive 443 tls-naive@user "pass@:/?#[]" "" ""
grep -qxF "naive+https://tls-naive%40user:pass%40%3A%2F%3F%23%5B%5D@[2001:db8::10]:443?padding=true#tls-naive@user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-naive@user"
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-naive@user" ]]
[[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-naive@user" ]]

rm -rf "${SUBSCRIBE_CAPTURE_DIR}"
currentHost="2001:db8::10"
defaultBase64Code shadowsocks 8388 tls-ss-user 'pass-"quoted' "" ""
defaultUserInfo=$(printf '%s' '2022-blake3-aes-128-gcm:pass-"quoted' | base64 -w 0)
grep -qxF "ss://${defaultUserInfo}@[2001:db8::10]:8388#tls-ss-user" "${SUBSCRIBE_CAPTURE_DIR}/default/tls-ss-user"
assertDisplayedDefaultSubscribeLink "tls-ss-user" "通用链接：Shadowsocks"
grep -qxF '    password: "pass-\"quoted"' "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-ss-user"
(
    base64() { return 1; }
    regressionExpectStatus 1 defaultBase64Code shadowsocks 8388 tls-ss-base64-failure pass "" "" >/dev/null 2>&1 ||
        { printf 'assert-fail:shadowsocks-base64-status\n' >&2; return 1; }
    [[ ! -e "${SUBSCRIBE_CAPTURE_DIR}/default/tls-ss-base64-failure" &&
        ! -e "${SUBSCRIBE_CAPTURE_DIR}/clashMeta/tls-ss-base64-failure" &&
        ! -e "${SUBSCRIBE_CAPTURE_DIR}/sing-box/tls-ss-base64-failure" ]] || return 1
) || tlsBoundaryFailed=1
unset REGRESSION_ECHO_LOG
[[ "${tlsBoundaryFailed}" -eq 0 ]] || return 1
}

runRemoteSubscribeSourcesAvoidReverseDecodeRegression() (
    local sourceLines
    local helperAccountFile="${TMP_DIR}/subscription-remote-sources-account.log"
    subscriptionRemoteScopeEnabled() { return 0; }

    subscriptionSyncAccountIdFromName() {
        return 97
    }
    subscriptionSyncFindUserByAccountName() {
        printf '%s\n' "$1" >"${helperAccountFile}"
        printf '{"id":"team-a","account":"sub_team_a","allowed_sources":["edge"]}\n'
    }
    subscriptionActiveEnabledUsersJson() {
        return 98
    }
    subscriptionActiveGroupRead() {
        if [[ "$*" == *'--argjson allowed ["edge"]'* && "$*" == *'.id as $sid | $allowed | index($sid)'* ]]; then
            printf 'example.com:443:edge:https\n'
            return 0
        fi
        return 1
    }

    sourceLines=$(subscriptionRemoteSubscribeSourcesForAccount sub_team_a)
    [[ "${sourceLines}" == "example.com:443:edge:https" ]]
    grep -qx 'sub_team_a' "${helperAccountFile}"
)

runSubscriptionSyncAppendLocalUserBatchRegression() (
    local root="${TMP_DIR}/subscription-sync-append-local-user-batch"
    local callLog="${root}/calls.log"
    local oldConfigPath="${configPath:-}"
    local oldSingBoxConfigPath="${singBoxConfigPath:-}"

    mkdir -p "${root}" "${root}/xray" "${root}/sing-box" "${root}/groups"
    coreInstallType=1
    configPath="${root}/xray/"
    singBoxConfigPath="${root}/sing-box/"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${root}/groups"
    ensureSubscriptionGroupsState
    subscriptionGroupsStateWrite '.user_groups += [{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"uuid":"11111111-1111-1111-1111-111111111111"}]'

    subscriptionSyncAppendProtocolBatch() {
        printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${callLog}"
        return 0
    }

    subscriptionSyncAppendLocalUser team-a

    [[ -f "${callLog}" ]] || return 1
    [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "2" ]] || return 1
    grep -qx "${root}/xray/	11111111-1111-1111-1111-111111111111	sub_team_a	xray" "${callLog}" || return 1
    grep -qx "${root}/sing-box/	11111111-1111-1111-1111-111111111111	sub_team_a	singbox" "${callLog}" || return 1

    : >"${callLog}"
    coreInstallType=2
    configPath="${singBoxConfigPath}"
    subscriptionSyncAppendLocalUser team-a
    [[ "$(wc -l <"${callLog}" | tr -d ' ')" == "1" ]] || return 1
    grep -qx "${root}/sing-box/	11111111-1111-1111-1111-111111111111	sub_team_a	singbox" "${callLog}" || return 1

    configPath="${oldConfigPath}"
    singBoxConfigPath="${oldSingBoxConfigPath}"
)

runSubscriptionSyncAppendProtocolUserPreservesClientsRegression() (
    local root="${TMP_DIR}/subscription-sync-append-preserves-clients"
    local targetFile="${root}/01_inbounds.json"
    local singBoxTargetFile="${root}/06_hysteria2_inbounds.json"

    mkdir -p "${root}/tmp"
    TMPDIR="${root}/tmp"
    cat >"${targetFile}" <<'JSON'
{"inbounds":[{"settings":{"clients":[{"id":"old-uuid","email":"sub_existing-VLESS_WS","level":7}]}}]}
JSON

    coreInstallType=1
    subscriptionSyncAppendProtocolUser 21 "${targetFile}" '.inbounds[0].settings.clients' new-uuid sub_new
    jq -e '
      (.inbounds[0].settings.clients | length) == 2 and
      .inbounds[0].settings.clients[0] == {id:"old-uuid",email:"sub_existing-VLESS_WS",level:7} and
      .inbounds[0].settings.clients[1].email == "sub_new-VLESS_WS"
    ' "${targetFile}" >/dev/null

    subscriptionSyncAppendProtocolUser 21 "${targetFile}" '.inbounds[0].settings.clients' another-uuid sub_new
    jq -e '(.inbounds[0].settings.clients | length) == 2' "${targetFile}" >/dev/null

    printf '%s\n' '{"inbounds":[{"settings":{"clients":[{"id":"old-uuid","email":"sub_existing-VLESS_WS"}]}}]}' >"${root}/auto-path.json"
    subscriptionSyncAppendProtocolUser 21 "${root}/auto-path.json" '' new-uuid sub_new
    jq -e '
      (.inbounds[0].settings.clients | length) == 2 and
      .inbounds[0].settings.clients[1].email == "sub_new-VLESS_WS"
    ' "${root}/auto-path.json" >/dev/null

    cat >"${singBoxTargetFile}" <<'JSON'
{"inbounds":[{"users":[{"password":"old-password","name":"sub_existing-singbox_hysteria2"}]}]}
JSON
    subscriptionSyncAppendProtocolUser 3 "${singBoxTargetFile}" '' new-password sub_new singbox
    jq -e '
      (.inbounds[0].users | length) == 2 and
      .inbounds[0].users[0].name == "sub_existing-singbox_hysteria2" and
      .inbounds[0].users[1].name == "sub_new-singbox_hysteria2"
    ' "${singBoxTargetFile}" >/dev/null

    local tuicFile="${root}/09_tuic_inbounds.json" beforeRepeat
    printf '%s\n' '{"inbounds":[{"users":[{"uuid":"old-uuid","password":"custom-password","name":"admin-singbox_tuic"}]}]}' >"${tuicFile}"
    subscriptionSyncAppendProtocolUser 31 "${tuicFile}" '' new-uuid sub_new singbox
    jq -e '
      .inbounds[0].users == [
        {uuid:"old-uuid",password:"custom-password",name:"admin-singbox_tuic"},
        {uuid:"new-uuid",password:"new-uuid",name:"sub_new-singbox_tuic"}
      ]
    ' "${tuicFile}" >/dev/null
    beforeRepeat=$(<"${tuicFile}")
    subscriptionSyncAppendProtocolUser 31 "${tuicFile}" '' new-uuid sub_new singbox
    [[ "$(<"${tuicFile}")" == "${beforeRepeat}" ]]
)

runSubscriptionSyncRemoveAccountFromFileRegression() (
    local root="${TMP_DIR}/subscription-sync-remove-account-file"
    local noMatchFile="${root}/no-match.json"
    local noMatchSnapshot="${root}/no-match.snapshot"
    local matchFile="${root}/match.json"
    local invalidFile="${root}/invalid.json"
    local invalidSnapshot="${root}/invalid.snapshot"

    mkdir -p "${root}"
    printf '%s\n' '{"inbounds":[{"settings":{"clients":[{"id":"keep-client","email":"sub_team_b-VLESS_WS"}]},"users":[{"name":"sub_team_c"}]}]}' >"${noMatchFile}"
    cp "${noMatchFile}" "${noMatchSnapshot}"
    subscriptionSyncRemoveAccountFromFile "${noMatchFile}" sub_team_a
    cmp -s "${noMatchFile}" "${noMatchSnapshot}"

    printf '%s\n' '{"inbounds":[{"settings":{"clients":[{"id":"remove-client","email":"sub_team_a-VLESS_WS"},{"id":"keep-client","email":"sub_team_b-VLESS_WS"}]},"users":[{"name":"sub_team_a"},{"name":"sub_team_c"}]}]}' >"${matchFile}"
    subscriptionSyncRemoveAccountFromFile "${matchFile}" sub_team_a
    jq -e '
      (.inbounds[0].settings.clients | map(.email) | . == ["sub_team_b-VLESS_WS"]) and
      (.inbounds[0].users | map(.name) | . == ["sub_team_c"])
    ' "${matchFile}" >/dev/null

    printf '%s\n' '{bad-json' >"${invalidFile}"
    cp "${invalidFile}" "${invalidSnapshot}"
    if subscriptionSyncRemoveAccountFromFile "${invalidFile}" sub_team_a; then
        return 1
    fi
    cmp -s "${invalidFile}" "${invalidSnapshot}"
)

runConfiguredAccountHelpersRegression() (
    local helperLog="${TMP_DIR}/configured-account-helpers.log"
    local currentManaged accounts
    subscriptionSyncConfiguredManagedUsers() {
        printf '%s\n' "$#" >"${helperLog}"
        printf '["sub_team_a-main","sub_team_b-main"]\n'
    }

    currentManaged=$(subscriptionSyncCurrentManagedUsers xray.json sing-box.json)
    jq -e '. == ["sub_team_a-main","sub_team_b-main"]' <<<"${currentManaged}" >/dev/null
    grep -qx '2' "${helperLog}" || return 1

    subscriptionSyncConfiguredAccountNamesJson() {
        printf '%s\n' "$#" >"${helperLog}"
        printf '["admin","ops","sub_team_a","sub_team_b"]\n'
    }
    trafficStatsAccountConfigFiles() {
        local -n resultRef=$1
        resultRef=("$3$2.json")
    }

    coreInstallType=1
    configPath="${TMP_DIR}/configured-account-xray/"
    singBoxConfigPath="${TMP_DIR}/configured-account-sing-box/"
    mkdir -p "${configPath}" "${singBoxConfigPath}"
    accounts=$(collectLocalTrafficAccounts)
    jq -e '. == ["admin","ops","sub_team_a","sub_team_b"]' <<<"${accounts}" >/dev/null
    grep -qx '2' "${helperLog}" || return 1

    subscriptionSyncCurrentManagedUsers() {
        return 97
    }
    subscriptionSyncConfiguredManagedCredentials() {
        printf '[{"account":"sub_team_a","uuids":["old-uuid"]}]\n'
    }
    local mismatches
    mismatches=$(subscriptionSyncCredentialMismatchAccounts '[{"id":"team-a","uuid":"new-uuid"}]')
    jq -e '. == ["sub_team_a"]' <<<"${mismatches}" >/dev/null
)

runTrafficAccountIdMapHelperRegression() (
    local trafficRoot="${TMP_DIR}/traffic-account-id-map-helper"
    local trafficSnapshot='{"ok":true,"items":[{"account":"sub_team_a","upload":1,"download":2},{"account":"sub_team_b","upload":3,"download":4}]}'

    mkdir -p "${trafficRoot}/groups"
    export PADM_SUBSCRIPTION_GROUPS_DIR="${trafficRoot}/groups"
    cat >"$(subscriptionGroupsFile)" <<'JSON'
{"version":2,"active_group":"default","groups":[{"id":"default","name":"Default","admin":{"id":"admin","name":"Admin","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":""},"sources":[{"id":"main","name":"Main","role":"main","scheme":"local","transport":"local","host":"127.0.0.1","port":0,"enabled":true,"sync_status":"local"}],"user_groups":[{"id":"team-a","name":"Team A","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"11111111-1111-1111-1111-111111111111"},{"id":"team-b","name":"Team B","enabled":true,"allowed_sources":["*"],"traffic_limit_gb":0,"token":"","uuid":"22222222-2222-2222-2222-222222222222"}],"sync":{"enabled":true,"interval_minutes":10,"last_run":"","last_status":"pending","failures":[],"quota_auto_apply":false},"traffic":{"global":{"upload":0,"download":0},"admin":{"upload":0,"download":0,"sources":{}},"user_groups":{},"sources":{}}}]}
JSON

    writeSubscriptionTrafficSnapshot "${trafficSnapshot}"
    jq -e '
      .traffic.user_groups["team-a"].sources.main.counters.sub_team_a.legacy.upload == 1 and
      .traffic.user_groups["team-a"].sources.main.counters.sub_team_a.legacy.download == 2 and
      .traffic.user_groups["team-b"].sources.main.counters.sub_team_b.legacy.upload == 3 and
      .traffic.user_groups["team-b"].sources.main.counters.sub_team_b.legacy.download == 4
    ' "$(subscriptionGroupsFile)" >/dev/null
)
