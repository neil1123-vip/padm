#!/usr/bin/env bash

subscribeSectionTitle() {
    echoContent title "\n┌─ $1 ─────────────────────────────────────"
    [[ -n "${2:-}" ]] && menuLine "$2"
    menuClose
}

subscribeAccountTitle() {
    echoContent title "\n┌─ 订阅账号 ─────────────────────────────────────────"
    menuLine "账号：$1"
    menuClose
}

# 订阅账号展示
showAccounts() {
    readInstallType
    readInstallProtocolType
    readConfigHostPathUUID
    readSingBoxConfig

    echo
    progressCard "$1" "账号"

    initSubscribeLocalConfig
    showVlessTcpAccounts
    showVlessWsAccounts
    showTrojanGrpcAccounts
    showVmessWsAccounts
    showTrojanAccounts
    showVlessGrpcAccounts
    showHysteriaAccounts
    showVlessRealityAccounts
    showVlessRealityGrpcAccounts
    showTuicAccounts
    showNaiveAccounts
    showVmessHTTPUpgradeAccounts
    showVlessRealityXHTTPAccounts
    showAnyTlsAccounts
}
