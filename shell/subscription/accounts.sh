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
subscriptionAccountDisplayFunction() {
    protocolCapabilityMeta "$1" account_display
}

showAccounts() {
    local step=${1:-}
    local protocolId displayFn
    readInstallType || return 1
    readInstallProtocolType || return 1
    readConfigHostPathUUID || return 1
    readSingBoxConfig || return 1

    echo
    progressCard "${step}" "账号"

    initSubscribeLocalConfig || return 1
    while IFS='|' read -r protocolId _; do
        currentProtocolHas "${protocolId}" || continue
        displayFn=$(subscriptionAccountDisplayFunction "${protocolId}") || {
            errorCard "订阅输出生成失败" "协议 ${protocolId} 缺少账号输出映射"
            return 1
        }
        "${displayFn}" || return 1
    done < <(protocolCapabilityRegistry | awk -F'|' '$3 == "node" { print }')
}
