#!/usr/bin/env bash

# BT 下载管理

btTools() {

    readInstallType

    if [[ -z "${configPath}" ]]; then

        coreNotInstalledErrorCard

        return 1

    fi
    local btStatus=
    while true; do
        echoContent title "\n┌─ BT 下载管理 ──────────────────────────────────────"

    menuLine "通过核心协议嗅探识别 bittorrent 后阻断"

    menuLine "只能覆盖可识别流量；加密、混淆或部分 uTP 场景可能绕过"

    menuLine "Xray：协议规则 + 入站 sniffing；sing-box：sniff action + protocol 规则"

    echo

    showBTBlockStatus

    menuItem 1 "启用 BT 阻断" "阻断已识别的 bittorrent 流量"

    menuItem 2 "关闭 BT 阻断" "移除 BT 协议阻断规则"

    menuItem 3 "查看当前状态" "显示 Xray / sing-box 规则状态"

    menuReturnItem 4 "返回路由与访问控制" "回到上级菜单"

    menuClose

    btStatus=
    autoRead bt_menu "请选择:" btStatus || return 0

    if [[ "${btStatus}" == "1" ]]; then

        routingConfigApplyTransaction "启用 BT 阻断失败" true false installBTBlock || return 1

        successCard "已启用 BT 阻断"
        return $?

    elif [[ "${btStatus}" == "2" ]]; then

        routingConfigApplyTransaction "关闭 BT 阻断失败" true false uninstallBTBlock || return 1

        successCard "已关闭 BT 阻断"
        return $?

    elif [[ "${btStatus}" == "3" ]]; then

        showBTBlockStatus

        return $?

    elif [[ "${btStatus}" == "4" ]]; then

        return 0

    else

        coreSelectionErrorCard "选择错误"

    fi
    done
}



showBTBlockStatus() {

    local hasStatus=false



    if [[ "${coreInstallType}" == "1" ]]; then

        hasStatus=true

        if hasXrayBTBlockRule; then

            menuLine "Xray-core：已启用 BT 阻断"

        else

            menuLine "Xray-core：未启用 BT 阻断"

        fi

    fi



    if [[ -n "${singBoxConfigPath}" ]]; then

        hasStatus=true

        if hasSingBoxBTBlockRule; then

            menuLine "sing-box：已启用 BT 阻断"

        else

            menuLine "sing-box：未启用 BT 阻断"

        fi

    fi



    if [[ "${hasStatus}" == "false" ]]; then

        menuLine "当前未检测到可管理的 Xray 或 sing-box 配置"

    fi

}



hasXrayBTBlockRule() {

    [[ -f "${configPath}09_routing.json" ]] && jq -e '.routing.rules[]? | select(.outboundTag == "blackhole_out" and (.protocol // [] | index("bittorrent")))' "${configPath}09_routing.json" >/dev/null 2>&1

}



hasSingBoxBTBlockRule() {

    [[ -f "${singBoxConfigPath}bt_block_route.json" ]] && jq -e '.route.rules[]? | select((.action == "reject" or .outbound == "block") and (.protocol // [] | index("bittorrent")))' "${singBoxConfigPath}bt_block_route.json" >/dev/null 2>&1

}



installBTBlock() {

    if [[ "${coreInstallType}" == "1" ]]; then

        addXrayBTBlockRule || return 1

        installSniffing || return 1

        removeXrayOutbound blackhole_out || return 1

        addXrayOutbound blackhole_out || return 1

    fi



    if [[ -n "${singBoxConfigPath}" ]]; then

        addSingBoxBTBlockRule || return 1

    fi

}



uninstallBTBlock() {

    if [[ "${coreInstallType}" == "1" ]]; then

        unInstallRouting blackhole_out outboundTag bittorrent || return 1

    fi



    if [[ -n "${singBoxConfigPath}" ]]; then

        removeSingBoxConfig bt_block_route || return 1

    fi

}



addXrayBTBlockRule() {

    if [[ ! -f "${configPath}09_routing.json" ]]; then

        writeRoutingJsonConfig "${configPath}09_routing.json" <<EOF || return 1

{

  "routing": {

    "domainStrategy": "IPOnDemand",

    "rules": []

  }

}

EOF

    fi



    unInstallRouting blackhole_out outboundTag bittorrent || return 1

    updateRoutingJsonConfig "${configPath}09_routing.json" '.routing.rules += [{"type":"field","outboundTag":"blackhole_out","protocol":["bittorrent"]}]' || return 1

}



addSingBoxBTBlockRule() {

    writeRoutingJsonConfig "${singBoxConfigPath}bt_block_route.json" <<EOF || return 1

{

  "route": {

    "rules": [

      {

        "action": "sniff",

        "timeout": "1s"

      },

      {

        "protocol": [

          "bittorrent"

        ],

        "action": "reject"

      }

    ]

  }

}

EOF

}
