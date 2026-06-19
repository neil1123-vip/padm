#!/usr/bin/env bash

# 分流工具

routingToolsMenu() {

    echoContent title "\n┌─ 分流工具 ─────────────────────────────────────────"

    menuLine "按域名或规则把服务端出站流量改走指定出口"

    menuLine "WARP、Socks5 全局模式会删除其他出站规则，启用前请确认用途"

    menuItem 1 "WARP 出站" "Cloudflare WARP WireGuard 出站，依赖第三方注册工具"

    menuItem 2 "IPv6 出站" "按域名或全局走 IPv6 direct 出站"

    menuItem 3 "Socks5 中继" "接入外部 Socks5 或给其他机器提供 Socks5 入站"

    menuItem 4 "DNS 覆盖" "为指定域名改用指定 DNS 解析"

    menuItem 5 "DNS/hosts 覆盖" "把指定域名解析到指定后端 IP"

    menuReturnItem 6 "返回路由与访问控制" "回到上级菜单"

    menuClose

    autoRead routing_tools_menu "请选择:" selectType

    case ${selectType} in

    1)

        warpRoutingMenu

        ;;

    2)

        ipv6Routing 1

        ;;

    3)

        socks5Routing

        ;;

    4)

        dnsRouting 1

        ;;

    5)

        if [[ -n "${singBoxConfigPath}" ]]; then

            errorCard "此功能不支持Hysteria2、Tuic"

        fi

        sniRouting 1

        ;;

    6)

        routingAccessMenu

        ;;

    *)

        coreSelectionErrorCard "选择错误"

        routingToolsMenu

        ;;

    esac

}
