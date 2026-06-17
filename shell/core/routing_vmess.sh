#!/usr/bin/env bash

# 设置 VMess WS TLS 出站
setVMessWSRoutingOutbounds() {
    local outboundTag="vmess-out"
    local legacyOutboundTag="VMess-out"

    autoRead vmess_ws_address "请输入VMess+WS+TLS的地址:" setVMessWSTLSAddress
    echoContent title "\n┌─ VMess WS TLS 分流规则 ────────────────────────────"
    menuLine "录入示例：netflix,openai"
    menuClose
    autoRead vmess_ws_domains "请按照上面示例录入域名:" domainList

    if [[ -z ${domainList} ]]; then
        errorCard "域名不可为空"
        return 1
    fi

    if [[ -n "${setVMessWSTLSAddress}" ]]; then
        echo
        autoRead vmess_ws_port "请输入VMess+WS+TLS的端口:" setVMessWSTLSPort
        echo
        if ! validPortNumber "${setVMessWSTLSPort}"; then
            errorCard "端口不合法"
            return 1
        fi

        autoRead vmess_ws_uuid "请输入VMess+WS+TLS的UUID:" setVMessWSTLSUUID
        echo
        if [[ -z "${setVMessWSTLSUUID}" ]]; then
            errorCard "UUID不可为空"
            return 1
        fi

        autoRead vmess_ws_path "请输入VMess+WS+TLS的Path路径:" setVMessWSTLSPath
        echo
        if [[ -z "${setVMessWSTLSPath}" ]]; then
            errorCard "路径不可为空"
            return 1
        elif [[ "${setVMessWSTLSPath}" != */* ]]; then
            setVMessWSTLSPath="/${setVMessWSTLSPath}"
        fi
        unInstallRouting "${legacyOutboundTag}" outboundTag || return 1
        removeXrayOutbound "${legacyOutboundTag}" || return 1
        removeXrayOutbound "${outboundTag}" || return 1
        addXrayOutbound "${outboundTag}" || return 1
        addXrayRouting "${outboundTag}" outboundTag "${domainList}" || return 1
        reloadCore || return 1
        successCard "添加分流成功"
        exit 0
    fi
    errorCard "地址不可为空"
    return 1
}

# 移除 VMess WS TLS 分流
removeVMessWSRouting() {
    local outboundTag="vmess-out"
    local legacyOutboundTag="VMess-out"

    unInstallRouting "${legacyOutboundTag}" outboundTag || return 1
    unInstallRouting "${outboundTag}" outboundTag || return 1
    removeXrayOutbound "${legacyOutboundTag}" || return 1
    removeXrayOutbound "${outboundTag}" || return 1

    reloadCore || return 1
    successCard "卸载成功"
}
