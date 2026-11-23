#!/usr/bin/env bash

# 分流工具

routingToolsMenu() {
    local selectType
    while true; do
        echoContent title "\n┌─ 分流工具 ─────────────────────────────────────────"
        menuItem 1 "WARP 出站" "通过 Cloudflare WARP 转发流量"
        menuItem 2 "IPv6 出站" "按域名或全局使用 IPv6 直连"
        menuItem 3 "Socks5 中继" "配置中继出站或入站监听"
        menuItem 4 "DNS 覆盖" "为指定域名选择 DNS 服务器"
        menuItem 5 "DNS/hosts 覆盖" "将指定域名解析到固定 IP"
        menuReturnItem 0 "返回路由与访问控制"
        menuClose

        selectType=
        menuReadChoice routing_tools_menu "请选择:" selectType interactive || return 0
        case "${selectType}" in
        1) warpRoutingMenu || true; continue ;;
        2) ipv6Routing 1 || true; continue ;;
        3) socks5Routing || true; continue ;;
        4) dnsRouting 1 || true; continue ;;
        5) sniRouting 1 || true; continue ;;
        0) return 0 ;;
        *) coreSelectionErrorCard "选择错误" ;;
        esac
    done
}
