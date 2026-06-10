#!/usr/bin/env bash

# VMess+WS+TLS 分流
vmessWSRouting() {
    echoContent title "\n┌─ VMess WS TLS 分流 ────────────────────────────────"
    menuLine "请按 README 中的分流说明配置域名或规则"
    menuItem 1 "添加出站" "添加 VMess WS TLS 出站分流"
    menuDangerItem 2 "卸载" "移除 VMess WS TLS 分流"
    menuReturnItem 3 "返回分流工具" "回到上一级分流菜单"
    menuClose
    autoRead vmess_ws_routing_menu "请选择:" selectType

    case ${selectType} in
    1)
        setVMessWSRoutingOutbounds
        ;;
    2)
        removeVMessWSRouting
        ;;
    3)
        routingToolsMenu
        ;;
    *)
        errorCard "选择错误，请重新选择"
        vmessWSRouting
        ;;
    esac
}


# 设置 VMess WS TLS 出站
setVMessWSRoutingOutbounds() {
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
        removeXrayOutbound VMess-out || return 1
        addXrayOutbound "VMess-out" || return 1
        addXrayRouting VMess-out outboundTag "${domainList}" || return 1
        reloadCore || return 1
        successCard "添加分流成功"
        exit 0
    fi
    errorCard "地址不可为空"
    return 1
}

# 移除 VMess WS TLS 分流
removeVMessWSRouting() {

    removeXrayOutbound VMess-out || return 1
    unInstallRouting VMess-out outboundTag || return 1

    reloadCore || return 1
    successCard "卸载成功"
}
