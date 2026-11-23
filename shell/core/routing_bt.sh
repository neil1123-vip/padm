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

    menuLine "核心通过协议嗅探识别 BitTorrent 流量"

    menuLine "加密、混淆及部分 uTP 流量可能无法识别"

    echo

    showBTBlockStatus

    menuItem 1 "启用 BT 阻断" "拦截识别出的 BitTorrent 流量"

    menuItem 2 "关闭 BT 阻断" "移除 BT 阻断规则"

    menuItem 3 "查看状态" "检查 Xray 与 sing-box 的阻断规则"

    menuReturnItem 0 "返回路由与访问控制"

    menuClose

    btStatus=
    menuReadChoice bt_menu "请选择:" btStatus interactive || return 0

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

    elif [[ "${btStatus}" == "0" ]]; then

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

        menuLine "未检测到可管理的 Xray 或 sing-box 配置"

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
