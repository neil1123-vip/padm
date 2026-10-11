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

showLocalProtocolLinks() (
    local linkRoot= accountFile accountName link
    local shown=false protocolLinkOutputQuiet=true
    # 使用私密临时目录复用生成器，查看不覆盖本机订阅缓存或公网产物。
    padmCreateTmpRootPath linkRoot padm-protocol-links.XXXXXX -d || return 1
    export PADM_SUBSCRIBE_LOCAL_DIR="${linkRoot}/subscribe_local"
    export PADM_SUBSCRIBE_DIR="${linkRoot}/subscribe"
    if ! showAccounts >/dev/null; then
        errorCard "协议链接生成失败" "请检查当前本机协议配置后重试"
        return 1
    fi
    protocolLinkOutputQuiet=false
    for accountFile in "${PADM_SUBSCRIBE_LOCAL_DIR}"/default/*; do
        [[ -s "${accountFile}" ]] || continue
        accountName=${accountFile##*/}
        [[ "${accountName}" != sub_* ]] || continue
        subscribeAccountTitle "${accountName}"
        while IFS= read -r link || [[ -n "${link}" ]]; do
            [[ -n "${link}" ]] || continue
            subscribeOutputTitle "${link%%:*} 协议链接"
            showProtocolShareLink "${link}"
            shown=true
        done <"${accountFile}"
    done
    if [[ "${shown}" != true ]]; then
        statusCard "当前没有可用的本机自用协议链接" "请先安装协议；分享订阅请到订阅与用户查看"
    fi
)
