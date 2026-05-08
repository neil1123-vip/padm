#!/usr/bin/env bash

vlessEncryptionStateFile() {
    echo "${PADM_VLESS_ENCRYPTION_STATE_FILE:-/etc/padm/xray/vless_encryption.json}"
}

xrayVersionAtLeast() {
    local current=$1
    local required=$2
    current=${current#v}
    required=${required#v}
    [[ "$(printf '%s\n%s\n' "${required}" "${current}" | sort -V | head -n 1)" == "${required}" ]]
}

extractVlessEncField() {
    local field=$1
    sed -n 's/.*"'"${field}"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1
}

vlessEncryptionStateSummary() {
    local stateFile
    local xrayVersion="未安装"
    local encryptionPrefix="none"
    stateFile=$(vlessEncryptionStateFile)
    if [[ -x /etc/padm/xray/xray ]]; then
        xrayVersion=$(/etc/padm/xray/xray --version | awk 'NR==1 {print $2}')
    fi
    if [[ -f "${stateFile}" ]]; then
        encryptionPrefix=$(jq -r '.encryption // "none" | split(".")[:3] | join(".")' "${stateFile}" 2>/dev/null)
        [[ -z "${encryptionPrefix}" || "${encryptionPrefix}" == "null" ]] && encryptionPrefix=none
        menuLine "当前状态：已启用；Xray=${xrayVersion}；encryption=${encryptionPrefix}..."
    else
        menuLine "当前状态：未启用；Xray=${xrayVersion}；encryption=none"
    fi
}

refreshVlessEncryptionSubscriptions() {
    readNginxSubscribe
    if [[ -n "${subscribePort}" || -f "${nginxConfigPath}subscribe.conf" ]]; then
        subscribe renew >/dev/null
        echoContent green " ---> 已刷新 default 公网订阅；Clash/Mihomo/sing-box 订阅未写入实验 encryption 字段"
    else
        cleanDirectoryContent /etc/padm/subscribe_local/default
        cleanDirectoryContent /etc/padm/subscribe_local/clashMeta
        cleanDirectoryContent /etc/padm/subscribe_local/sing-box
        showAccounts >/dev/null
        echoContent green " ---> 已刷新本地 default 订阅；Clash/Mihomo/sing-box 订阅未写入实验 encryption 字段"
    fi
}

setVlessRealityEncryption() {
    local mode=$1
    local configFile=/etc/padm/xray/conf/07_VLESS_vision_reality_inbounds.json
    local stateFile
    local backupFile
    local xrayVersion
    local vlessEncOutput
    local encryption
    local decryption
    local stateBackupFile
    stateFile=$(vlessEncryptionStateFile)

    if [[ "${coreInstallType}" != "1" ]]; then
        echoContent red " ---> 此实验功能仅支持 Xray-core"
        return 1
    fi
    if [[ ! -x /etc/padm/xray/xray || ! -f "${configFile}" ]]; then
        echoContent red " ---> 未检测到 Xray Reality Vision 配置，请先安装 Xray Reality Vision"
        return 1
    fi

    backupFile="${configFile}.vlessenc.bak"
    stateBackupFile="${stateFile}.bak"
    cp "${configFile}" "${backupFile}"
    if [[ -f "${stateFile}" ]]; then
        cp "${stateFile}" "${stateBackupFile}"
    else
        rm -f "${stateBackupFile}"
    fi

    if [[ "${mode}" == "enable" ]]; then
        xrayVersion=$(/etc/padm/xray/xray --version | awk 'NR==1 {print $2}')
        if ! xrayVersionAtLeast "${xrayVersion}" "25.9.5"; then
            echoContent red " ---> 当前 Xray-core ${xrayVersion} 不支持 vlessenc，请先升级到 v25.9.5 或更高版本"
            rm -f "${backupFile}"
            return 1
        fi
        if ! /etc/padm/xray/xray vlessenc >/tmp/padm-vlessenc.out 2>/tmp/padm-vlessenc.err; then
            echoContent red " ---> xray vlessenc 执行失败，请先确认当前 Xray-core 支持该命令"
            rm -f "${backupFile}" /tmp/padm-vlessenc.out /tmp/padm-vlessenc.err
            return 1
        fi
        vlessEncOutput=$(cat /tmp/padm-vlessenc.out)
        encryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField encryption)
        decryption=$(printf '%s\n' "${vlessEncOutput}" | extractVlessEncField decryption)
        rm -f /tmp/padm-vlessenc.out /tmp/padm-vlessenc.err
        if [[ -z "${encryption}" || -z "${decryption}" ]]; then
            echoContent red " ---> 无法解析 xray vlessenc 输出，已取消启用"
            rm -f "${backupFile}"
            return 1
        fi
        if ! jq --arg decryption "${decryption}" 'del(.inbounds[1].settings.fallbacks) | .inbounds[1].settings.decryption = $decryption' "${configFile}" >"${configFile}.tmp"; then
            echoContent red " ---> 写入 Xray 配置失败，已取消启用"
            mv "${backupFile}" "${configFile}"
            rm -f "${configFile}.tmp" "${stateBackupFile}"
            return 1
        fi
        mv "${configFile}.tmp" "${configFile}"
        mkdir -p "$(dirname "${stateFile}")"
        if ! jq -n --arg encryption "${encryption}" --arg decryption "${decryption}" '{enabled:true,encryption:$encryption,decryption:$decryption}' >"${stateFile}"; then
            echoContent red " ---> 写入 VLESS Encryption 状态失败，已取消启用"
            mv "${backupFile}" "${configFile}"
            [[ -f "${stateBackupFile}" ]] && mv "${stateBackupFile}" "${stateFile}"
            return 1
        fi
        chmod 600 "${stateFile}" 2>/dev/null || true
    else
        if ! jq '.inbounds[1].settings.decryption = "none" | del(.inbounds[1].settings.fallbacks)' "${configFile}" >"${configFile}.tmp"; then
            echoContent red " ---> 写入 Xray 配置失败，已取消关闭"
            mv "${backupFile}" "${configFile}"
            rm -f "${configFile}.tmp" "${stateBackupFile}"
            return 1
        fi
        mv "${configFile}.tmp" "${configFile}"
        rm -f "${stateFile}"
    fi

    if ! /etc/padm/xray/xray -test -confdir /etc/padm/xray/conf >/tmp/padm-xray-test.log 2>&1; then
        mv "${backupFile}" "${configFile}"
        if [[ -f "${stateBackupFile}" ]]; then
            mv "${stateBackupFile}" "${stateFile}"
        elif [[ "${mode}" == "enable" ]]; then
            rm -f "${stateFile}"
        fi
        echoContent red " ---> Xray 配置校验失败，已回滚本次修改"
        echoContent yellow " ---> 可查看 /tmp/padm-xray-test.log 排查原因"
        return 1
    fi
    rm -f "${backupFile}" "${stateBackupFile}"
    reloadCore
    refreshVlessEncryptionSubscriptions
    return 0
}

manageVlessEncryptionExperiment() {
    readInstallType
    readInstallProtocolType
    echoContent skyBlue "\n┌─ VLESS Encryption 实验功能 ─────────────────────────"
    menuLine "仅支持 Xray-core + VLESS Reality Vision"
    menuLine "启用后可能只有部分客户端可用；Clash/Mihomo/sing-box 订阅不保证兼容"
    menuLine "默认推荐仍是 Reality Vision，不建议新手启用"
    vlessEncryptionStateSummary
    menuDangerItem 1 "启用实验开关" "生成 vlessenc 并修改 Xray Reality Vision 配置"
    menuItem 2 "关闭实验开关" "恢复 decryption=none 并删除实验订阅参数"
    menuItem 3 "返回主菜单" "回到 padm 管理面板"
    echoContent skyBlue "└──────────────────────────────────────────────────"
    autoRead vless_encryption_menu "请选择:" selectVlessEncryptionMenu
    case ${selectVlessEncryptionMenu} in
    1)
        echoContent red " ---> VLESS Encryption 是实验功能，可能只有部分客户端可用"
        echoContent yellow " ---> 启用后 default VLESS 链接会携带新的 encryption 参数；Clash/Mihomo/sing-box 订阅不保证兼容"
        autoRead vless_encryption_confirm "确认承担兼容性风险并启用[y/n]?" confirmVlessEncryption
        if [[ "${confirmVlessEncryption}" == "y" ]]; then
            setVlessRealityEncryption enable && echoContent green " ---> VLESS Encryption 实验开关已启用"
        else
            echoContent yellow " ---> 已取消"
        fi
        ;;
    2)
        setVlessRealityEncryption disable && echoContent green " ---> VLESS Encryption 实验开关已关闭"
        ;;
    3)
        menu
        ;;
    *)
        echoContent red ' ---> 选择错误，重新选择'
        manageVlessEncryptionExperiment
        ;;
    esac
}

# 检查是否安装宝塔
checkBTPanel() {
    if [[ -n $(pgrep -f "BT-Panel") ]]; then
        # 读取域名
        if [[ -d '/www/server/panel/vhost/cert/' && -n $(find /www/server/panel/vhost/cert/*/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取宝塔配置\n"

                find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /www/server/panel/vhost/cert/*/fullchain.pem | awk -F "[/]" '{print $7}' | awk '{print NR""":"$0}' | grep -e "^${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    checkBTPanel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/padm/tls/${btDomain}.crt" && ! -f "/etc/padm/tls/${btDomain}.key" ]]; then
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/fullchain.pem" "/etc/padm/tls/${btDomain}.crt"
                        ln -s "/www/server/panel/vhost/cert/${btDomain}/privkey.pem" "/etc/padm/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/www/wwwroot/${btDomain}/html/"

                    mkdir -p "/www/wwwroot/${btDomain}/html/"

                    if [[ -f "/www/wwwroot/${btDomain}/.user.ini" ]]; then
                        chattr -i "/www/wwwroot/${btDomain}/.user.ini"
                    fi
                    nginxConfigPath="/www/server/panel/vhost/nginx/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                checkBTPanel
            fi
        fi
    fi
}

check1Panel() {
    if [[ -n $(pgrep -f "1panel") ]]; then
        # 读取域名
        if [[ -d '/opt/1panel/apps/openresty/openresty/www/sites/' && -n $(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem) ]]; then
            if [[ -z "${currentHost}" ]]; then
                echoContent skyBlue "\n读取1Panel配置\n"

                find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}'

                read -r -p "请输入编号选择:" selectBTDomain
            else
                selectBTDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${currentHost}" | cut -d ":" -f 1)
            fi

            if [[ -n "${selectBTDomain}" ]]; then
                btDomain=$(find /opt/1panel/apps/openresty/openresty/www/sites/*/ssl/fullchain.pem | awk -F "[/]" '{print $9}' | awk '{print NR""":"$0}' | grep "${selectBTDomain}:" | cut -d ":" -f 2)

                if [[ -z "${btDomain}" ]]; then
                    echoContent red " ---> 选择错误，请重新选择"
                    check1Panel
                else
                    domain=${btDomain}
                    if [[ ! -f "/etc/padm/tls/${btDomain}.crt" && ! -f "/etc/padm/tls/${btDomain}.key" ]]; then
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/fullchain.pem" "/etc/padm/tls/${btDomain}.crt"
                        ln -s "/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/ssl/privkey.pem" "/etc/padm/tls/${btDomain}.key"
                    fi

                    nginxStaticPath="/opt/1panel/apps/openresty/openresty/www/sites/${btDomain}/index/"
                fi
            else
                echoContent red " ---> 选择错误，请重新选择"
                check1Panel
            fi
        fi
    fi
}


# 卸载 sing-box
unInstallSingBox() {
    local type=$1
    if [[ -n "${singBoxConfigPath}" ]]; then
        if grep -q 'tuic' </etc/padm/sing-box/conf/config.json && [[ "${type}" == "tuic" ]]; then
            rm "${singBoxConfigPath}09_tuic_inbounds.json"
            echoContent green " ---> 删除sing-box tuic配置成功"
        fi

        if grep -q 'hysteria2' </etc/padm/sing-box/conf/config.json && [[ "${type}" == "hysteria2" ]]; then
            rm "${singBoxConfigPath}06_hysteria2_inbounds.json"
            echoContent green " ---> 删除sing-box hysteria2配置成功"
        fi
        rm "${singBoxConfigPath}config.json"
    fi

    readInstallType

    if [[ -n "${singBoxConfigPath}" ]]; then
        echoContent yellow " ---> 检测到有其他配置，保留sing-box核心"
        serviceQueueRestart sing-box
        serviceQueueApply
    else
        handleSingBox stop
        rm /etc/systemd/system/sing-box.service
        rm -rf /etc/padm/sing-box/*
        echoContent green " ---> sing-box 卸载完成"
    fi
}


# 清理旧残留
cleanUp() {
    if [[ "$1" == "xrayDel" ]]; then
        handleXray stop
        rm -rf /etc/padm/xray/*
    elif [[ "$1" == "singBoxDel" ]]; then
        handleSingBox stop
        rm -rf /etc/padm/sing-box/conf/config.json >/dev/null 2>&1
        cleanDirectoryContent /etc/padm/sing-box/conf/config
    fi
}

# 更新传统 TLS fallback 静态站点
updateNginxBlog() {
    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 0
    fi

    echoContent skyBlue "\n进度 $1/${totalProgress} : 更换传统 TLS fallback 静态站点"

    if ! currentProtocolHas 0 || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 由于环境依赖，请先安装Xray-core的VLESS_TCP_TLS_Vision"
        exit 0
    fi
    echoContent red "=============================================================="
    echoContent yellow "# 该功能仅用于传统 TLS fallback：未命中代理协议时展示本机静态页面"
    echoContent yellow "# VLESS Reality Vision/XHTTP/gRPC 不依赖此静态站点，Reality 伪装由外部 target/SNI 完成"
    echoContent yellow "# 如需自定义，请手动复制模版文件到 ${nginxStaticPath} \n"
    echoContent yellow "1.现代引导页"
    echoContent yellow "2.游戏工作室"
    echoContent yellow "3.个人笔记"
    echoContent yellow "4.商务服务"
    echoContent yellow "5.媒体工具"
    echoContent yellow "6.互动节奏页"
    echoContent yellow "7.制造企业"
    echoContent yellow "8.作品集展示"
    echoContent yellow "9.本地404页面"
    echoContent yellow "10.服务状态页"
    echoContent yellow "11.文档索引"
    echoContent yellow "12.产品简介"
    echoContent yellow "13.研究实验室"
    echoContent yellow "14.社区主页"
    echoContent yellow "15.旅行札记"
    echoContent yellow "16.食谱收藏"
    echoContent yellow "17.图片日志"
    echoContent yellow "18.学习中心"
    echoContent yellow "19.活动页面"
    echoContent yellow "20.团队介绍"
    echoContent yellow "21.302重定向网站"
    echoContent red "=============================================================="
    read -r -p "请选择:" selectInstallNginxBlogType

    if [[ "${selectInstallNginxBlogType}" == "21" ]]; then
        if [[ "${coreInstallType}" == "2" ]]; then
            echoContent red "\n ---> 此功能仅支持Xray-core内核，请等待后续更新"
            exit 0
        fi
        echoContent red "\n=============================================================="
        echoContent yellow "重定向的优先级更高，配置302之后如果更改传统 TLS fallback 静态站点，根路由下静态站点将不起作用"
        echoContent yellow "如想要静态站点实现作用需删除302重定向配置\n"
        echoContent yellow "1.添加"
        echoContent yellow "2.删除"
        echoContent red "=============================================================="
        read -r -p "请选择:" redirectStatus

        if [[ "${redirectStatus}" == "1" ]]; then
            backupNginxConfig backup
            read -r -p "请输入要重定向的域名,例如 https://www.baidu.com:" redirectDomain
            removeNginx302
            addNginx302 "${redirectDomain}"
            serviceQueueRestart nginx
            serviceQueueApply
            if [[ -z $(pgrep -f "nginx") ]]; then
                backupNginxConfig restoreBackup
                serviceQueueStart nginx
                serviceQueueApply
                exit 0
            fi
            checkNginx302
            exit 0
        fi
        if [[ "${redirectStatus}" == "2" ]]; then
            removeNginx302
            echoContent green " ---> 移除302重定向成功"
            exit 0
        fi
    fi
    if [[ "${selectInstallNginxBlogType}" =~ ^([1-9]|1[0-9]|20)$ ]]; then
        installNginxStaticTemplate "${selectInstallNginxBlogType}"
        echoContent green " ---> 更换传统 TLS fallback 静态站点成功"
    else
        echoContent red " ---> 选择错误，请重新选择"
        updateNginxBlog
    fi
}


# 入口端口管理
addCorePort() {

    if [[ "${coreInstallType}" == "2" ]]; then
        echoContent red "\n ---> 此功能仅支持Xray-core内核"
        exit 0
    fi

    echoContent skyBlue "\n┌─ 入口端口管理 ─────────────────────────────────────"
    menuLine "支持批量添加；不影响默认端口使用"
    menuLine "查看账号时只展示默认端口账号；端口列表用英文逗号分隔"
    menuLine "如已安装 Hysteria2，会同时安装 Hysteria2 新端口"
    menuLine "示例：2053,2083,2087"
    menuItem 1 "查看已添加端口" "列出当前额外端口"
    menuItem 2 "添加端口" "批量添加新入口端口"
    menuItem 3 "删除端口" "移除已添加端口"
    menuClose
    read -r -p "请选择:" selectNewPortType
    if [[ "${selectNewPortType}" == "1" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        exit 0
    elif [[ "${selectNewPortType}" == "2" ]]; then
        read -r -p "请输入端口号:" newPort
        read -r -p "请输入默认的端口号，同时会更改订阅端口以及节点端口，[回车]默认443:" defaultPort

        if [[ -n "${defaultPort}" ]]; then
            rm -rf "$(find ${configPath}* | grep "default")"
        fi

        if [[ -n "${newPort}" ]]; then

            while read -r port; do
                rm -rf "$(find ${configPath}* | grep "${port}")"

                local fileName=
                local hysteriaFileName=
                if [[ -n "${defaultPort}" && "${port}" == "${defaultPort}" ]]; then
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}_default.json"
                else
                    fileName="${configPath}02_dokodemodoor_inbounds_${port}.json"
                fi

                if [[ -n ${hysteriaPort} ]]; then
                    hysteriaFileName="${configPath}02_dokodemodoor_inbounds_hysteria_${port}.json"
                fi

                # 开放端口
                allowPort "${port}"
                allowPort "${port}" "udp"

                local settingsPort=443
                if [[ -n "${customPort}" ]]; then
                    settingsPort=${customPort}
                fi

                if [[ -n ${hysteriaFileName} ]]; then
                    cat <<EOF >"${hysteriaFileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${hysteriaPort},
		"network": "udp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-hysteria-${port}"
	}
  ]
}
EOF
                fi
                cat <<EOF >"${fileName}"
{
  "inbounds": [
	{
	  "listen": "0.0.0.0",
	  "port": ${port},
	  "protocol": "dokodemo-door",
	  "settings": {
		"address": "127.0.0.1",
		"port": ${settingsPort},
		"network": "tcp",
		"followRedirect": false
	  },
	  "tag": "dokodemo-door-newPort-${port}"
	}
  ]
}
EOF
            done < <(echo "${newPort}" | tr ',' '\n')

            echoContent green " ---> 添加完毕"
            reloadCore
            addCorePort
        fi
    elif [[ "${selectNewPortType}" == "3" ]]; then
        find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}'
        read -r -p "请输入要删除的端口编号:" portIndex
        local dokoConfig
        dokoConfig=$(find ${configPath} -name "*dokodemodoor*" | grep -v "hysteria" | awk -F "[c][o][n][f][/]" '{print $2}' | awk -F "[_]" '{print $4}' | awk -F "[.]" '{print ""NR""":"$1}' | grep "${portIndex}:")
        if [[ -n "${dokoConfig}" ]]; then
            rm "${configPath}02_dokodemodoor_inbounds_$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}').json"
            local hysteriaDokodemodoorFilePath=

            hysteriaDokodemodoorFilePath="${configPath}02_dokodemodoor_inbounds_hysteria_$(echo "${dokoConfig}" | awk -F "[:]" '{print $2}').json"
            if [[ -f "${hysteriaDokodemodoorFilePath}" ]]; then
                rm "${hysteriaDokodemodoorFilePath}"
            fi

            reloadCore
            addCorePort
        else
            echoContent yellow "\n ---> 编号输入错误，请重新选择"
            addCorePort
        fi
    fi
}


# 卸载脚本
unInstall() {
    read -r -p "是否确认卸载安装内容？[y/n]:" unInstallStatus
    if [[ "${unInstallStatus}" != "y" ]]; then
        echoContent green " ---> 放弃卸载"
        menu
        exit 0
    fi
    # checkBTPanel
    echoContent yellow " ---> 脚本不会删除acme相关配置，删除请手动执行 [rm -rf /root/.acme.sh]"
    handleNginx stop
    if [[ -z $(pgrep -f "nginx") ]]; then
        echoContent green " ---> 停止Nginx成功"
    fi
    if [[ "${release}" == "alpine" ]]; then
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rc-update del xray default
            rm -rf /etc/init.d/xray
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rc-update del sing-box default
            rm -rf /etc/init.d/sing-box
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
    else
        if [[ "${coreInstallType}" == "1" ]]; then
            handleXray stop
            rm -rf /etc/systemd/system/xray.service
            echoContent green " ---> 删除Xray开机自启完成"
        fi
        if [[ "${coreInstallType}" == "2" || -n "${singBoxConfigPath}" ]]; then
            handleSingBox stop
            rm -rf /etc/systemd/system/sing-box.service
            echoContent green " ---> 删除sing-box开机自启完成"
        fi
    fi

    rm -rf /etc/padm
    rm -rf ${nginxConfigPath}alone.conf
    rm -rf ${nginxConfigPath}checkPortOpen.conf >/dev/null 2>&1
    rm -rf "${nginxConfigPath}sing_box_VMess_HTTPUpgrade.conf" >/dev/null 2>&1
    rm -rf ${nginxConfigPath}checkPortOpen.conf >/dev/null 2>&1

    unInstallSubscribe

    if [[ -d "${nginxStaticPath}" && -f "${nginxStaticPath}/check" ]]; then
        rm -rf "${nginxStaticPath}"
        echoContent green " ---> 删除伪装网站完成"
    fi

    rm -rf /usr/bin/padm
    rm -rf /usr/sbin/padm
    echoContent green " ---> 卸载快捷方式完成"
    echoContent green " ---> 卸载管理脚本完成"
}


# CDN节点管理
manageCDN() {
    echoContent skyBlue "\n进度 $1/1 : CDN节点管理"
    local setCDNDomain=

    if currentProtocolHasAny 1 2 3 5 11; then
        echoContent red "=============================================================="
        echoContent yellow "# 注意事项"
        echoContent yellow "CDN节点优先配合 VLESS Reality XHTTP 使用；传统 WS/gRPC/HTTPUpgrade 仅在兼容旧客户端时考虑"
        echoContent yellow "不了解 Cloudflare 优选 IP/CNAME 时建议保持默认，错误配置会导致客户端无法连接"

        echoContent yellow "1.CNAME www.digitalocean.com"
        echoContent yellow "2.CNAME who.int"
        echoContent yellow "3.CNAME blog.hostmonit.com"
        echoContent yellow "4.CNAME www.visa.com.hk"
        echoContent yellow "5.手动输入[可输入多个，比如: 1.1.1.1,1.1.2.2,cloudflare.com 逗号分隔]"
        echoContent yellow "6.移除CDN节点"
        echoContent red "=============================================================="
        read -r -p "请选择:" selectCDNType
        case ${selectCDNType} in
        1)
            setCDNDomain="www.digitalocean.com"
            ;;
        2)
            setCDNDomain="who.int"
            ;;
        3)
            setCDNDomain="blog.hostmonit.com"
            ;;
        4)
            setCDNDomain="www.visa.com.hk"
            ;;
        5)
            read -r -p "请输入想要自定义CDN IP或者域名:" setCDNDomain
            ;;
        6)
            echo >/etc/padm/cdn
            echoContent green " ---> 移除成功"
            exit 0
            ;;
        esac

        if [[ -n "${setCDNDomain}" ]]; then
            echo >/etc/padm/cdn
            echo "${setCDNDomain}" >"/etc/padm/cdn"
            echoContent green " ---> 修改CDN成功"
            subscribe false false
        else
            echoContent red " ---> 不可以为空，请重新输入"
            manageCDN 1
        fi
    else
        echoContent yellow "CDN节点优先配合 VLESS Reality XHTTP 使用；传统 WS/gRPC/HTTPUpgrade 仅在兼容旧客户端时考虑"
        echoContent red " ---> 未检测到可以使用的协议，仅支持ws、grpc、HTTPUpgrade相关的协议"
    fi
}

# clashMeta配置文件
clashMetaConfig() {
    local url=$1
    local id=$2
    cat <<EOF >"/etc/padm/subscribe/clashMetaProfiles/${id}"
log-level: debug
mode: rule
ipv6: true
mixed-port: 7890
allow-lan: true
bind-address: "*"
lan-allowed-ips:
  - 0.0.0.0/0
  - ::/0
find-process-mode: strict
external-controller: 0.0.0.0:9090

geox-url:
  geoip: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat"
  geosite: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat"
  mmdb: "https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.metadb"
geo-auto-update: true
geo-update-interval: 24

external-controller-cors:
  allow-private-network: true

global-client-fingerprint: chrome

profile:
  store-selected: true
  store-fake-ip: true

sniffer:
  enable: true
  override-destination: false
  sniff:
    QUIC:
      ports: [ 443 ]
    TLS:
      ports: [ 443 ]
    HTTP:
      ports: [80]


dns:
  enable: true
  prefer-h3: false
  listen: 0.0.0.0:1053
  ipv6: true
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - 'dns.google'
    - "localhost.ptlogin2.qq.com"
  use-hosts: true
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
    - 1.1.1.1
    - 8.8.8.8
  proxy-server-nameserver:
    - https://223.5.5.5/dns-query
    - https://1.12.12.12/dns-query
  nameserver-policy:
    "geosite:cn,private":
      - https://doh.pub/dns-query
      - https://dns.alidns.com/dns-query

proxy-providers:
  ${subscribeSalt}_provider:
    type: http
    path: ./${subscribeSalt}_provider.yaml
    url: ${url}
    interval: 3600
    proxy: DIRECT
    health-check:
      enable: true
      url: https://cp.cloudflare.com/generate_204
      interval: 300

proxy-groups:
  - name: 手动切换
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies: null
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 36000
    tolerance: 50
    use:
      - ${subscribeSalt}_provider
    proxies: null

  - name: 全球代理
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: 流媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: DNS_Proxy
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 自动选择
      - 手动切换
      - DIRECT

  - name: Telegram
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Google
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT
  - name: YouTube
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
  - name: Netflix
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Spotify
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
      - DIRECT
  - name: HBO
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: Bing
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择


  - name: OpenAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: ClaudeAI
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择

  - name: Disney
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 流媒体
      - 手动切换
      - 自动选择
  - name: GitHub
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - 手动切换
      - 自动选择
      - DIRECT

  - name: 国内媒体
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
  - name: 本地直连
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 自动选择
  - name: 漏网之鱼
    type: select
    use:
      - ${subscribeSalt}_provider
    proxies:
      - DIRECT
      - 手动切换
      - 自动选择
rule-providers:
  lan:
    type: http
    behavior: classical
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Lan/Lan.yaml
    path: ./Rules/lan.yaml
  reject:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400
  proxy:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400
  gfw:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/gfw.txt
    path: ./ruleset/gfw.yaml
    interval: 86400
  greatfire:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/greatfire.txt
    path: ./ruleset/greatfire.yaml
    interval: 86400
  tld-not-cn:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/tld-not-cn.txt
    path: ./ruleset/tld-not-cn.yaml
    interval: 86400
  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400
  applications:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/applications.txt
    path: ./ruleset/applications.yaml
    interval: 86400
  Disney:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Disney/Disney.yaml
    path: ./ruleset/disney.yaml
    interval: 86400
  Netflix:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Netflix/Netflix.yaml
    path: ./ruleset/netflix.yaml
    interval: 86400
  YouTube:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/YouTube/YouTube.yaml
    path: ./ruleset/youtube.yaml
    interval: 86400
  HBO:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/HBO/HBO.yaml
    path: ./ruleset/hbo.yaml
    interval: 86400
  OpenAI:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/OpenAI/OpenAI.yaml
    path: ./ruleset/openai.yaml
    interval: 86400
  ClaudeAI:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Claude/Claude.yaml
    path: ./ruleset/claudeai.yaml
    interval: 86400
  Bing:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Bing/Bing.yaml
    path: ./ruleset/bing.yaml
    interval: 86400
  Google:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Google/Google.yaml
    path: ./ruleset/google.yaml
    interval: 86400
  GitHub:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/GitHub/GitHub.yaml
    path: ./ruleset/github.yaml
    interval: 86400
  Spotify:
    type: http
    behavior: classical
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/Spotify/Spotify.yaml
    path: ./ruleset/spotify.yaml
    interval: 86400
  ChinaMaxDomain:
    type: http
    behavior: domain
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_Domain.yaml
    path: ./Rules/ChinaMaxDomain.yaml
  ChinaMaxIPNoIPv6:
    type: http
    behavior: ipcidr
    interval: 86400
    url: https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Clash/ChinaMax/ChinaMax_IP_No_IPv6.yaml
    path: ./Rules/ChinaMaxIPNoIPv6.yaml
rules:
  - RULE-SET,YouTube,YouTube,no-resolve
  - RULE-SET,Google,Google,no-resolve
  - RULE-SET,GitHub,GitHub
  - RULE-SET,telegramcidr,Telegram,no-resolve
  - RULE-SET,Spotify,Spotify,no-resolve
  - RULE-SET,Netflix,Netflix
  - RULE-SET,HBO,HBO
  - RULE-SET,Bing,Bing
  - RULE-SET,OpenAI,OpenAI
  - RULE-SET,ClaudeAI,ClaudeAI
  - RULE-SET,Disney,Disney
  - RULE-SET,proxy,全球代理
  - RULE-SET,gfw,全球代理
  - RULE-SET,applications,本地直连
  - RULE-SET,ChinaMaxDomain,本地直连
  - RULE-SET,ChinaMaxIPNoIPv6,本地直连,no-resolve
  - RULE-SET,lan,本地直连,no-resolve
  - GEOIP,CN,本地直连
  - MATCH,漏网之鱼
EOF

}

# 订阅
subscribe() {
    readInstallProtocolType
    installSubscribe

    readNginxSubscribe
    local renewSalt=$1
    local showStatus=$2
    if [[ "${coreInstallType}" == "1" || "${coreInstallType}" == "2" ]]; then

        echoContent skyBlue "-------------------------备注---------------------------------"
        echoContent yellow "# 查看订阅会重新生成本地账号的订阅"
        echoContent red "# 需要手动输入md5加密的salt值，如果不了解使用随机即可"
        echoContent yellow "# 不影响已添加的远程订阅的内容\n"

        if [[ -f "/etc/padm/subscribe_local/subscribeSalt" && -n $(cat "/etc/padm/subscribe_local/subscribeSalt") ]]; then
            if [[ -z "${renewSalt}" ]]; then
                read -r -p "读取到上次安装设置的Salt [$(cat /etc/padm/subscribe_local/subscribeSalt)]，是否使用？[y/n]:" historySaltStatus
                if [[ "${historySaltStatus}" == "y" ]]; then
                    subscribeSalt=$(cat /etc/padm/subscribe_local/subscribeSalt)
                else
                    read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
                fi
            else
                subscribeSalt=$(cat /etc/padm/subscribe_local/subscribeSalt)
            fi
        else
            read -r -p "请输入salt值, [回车]使用随机:" subscribeSalt
            showStatus=
        fi

        if [[ -z "${subscribeSalt}" ]]; then
            subscribeSalt=$(initRandomSalt)
        fi
        echoContent yellow "\n ---> Salt: ${subscribeSalt}"

        echo "${subscribeSalt}" >/etc/padm/subscribe_local/subscribeSalt

        cleanDirectoryContent /etc/padm/subscribe/default
        cleanDirectoryContent /etc/padm/subscribe/clashMeta
        cleanDirectoryContent /etc/padm/subscribe/clashMetaProfiles
        cleanDirectoryContent /etc/padm/subscribe/sing-box
        cleanDirectoryContent /etc/padm/subscribe/sing-box_profiles
        cleanDirectoryContent /etc/padm/subscribe_local/default
        cleanDirectoryContent /etc/padm/subscribe_local/clashMeta
        cleanDirectoryContent /etc/padm/subscribe_local/sing-box
        showAccounts >/dev/null
        if [[ -n $(ls /etc/padm/subscribe_local/default/) ]]; then
            if [[ -n "$(listRemoteSubscribeSources)" ]]; then
                if [[ -z "${renewSalt}" ]]; then
                    read -r -p "读取到其他订阅，是否更新？[y/n]" updateOtherSubscribeStatus
                else
                    updateOtherSubscribeStatus=y
                fi
            fi
            local subscribePortLocal="${subscribePort}"
            find /etc/padm/subscribe_local/default/* | while read -r email; do
                email=$(echo "${email}" | awk -F "[d][e][f][a][u][l][t][/]" '{print $2}')

                local emailMd5=
                emailMd5=$(echo -n "${email}${subscribeSalt}"$'\n' | md5sum | awk '{print $1}')

                cat "/etc/padm/subscribe_local/default/${email}" >>"/etc/padm/subscribe/default/${emailMd5}"
                if [[ "${updateOtherSubscribeStatus}" == "y" ]]; then
                    updateRemoteSubscribe "${emailMd5}" "${email}"
                fi
                local base64Result
                base64Result=$(base64 -w 0 "/etc/padm/subscribe/default/${emailMd5}")
                echo "${base64Result}" >"/etc/padm/subscribe/default/${emailMd5}"
                echoContent yellow "--------------------------------------------------------------"
                local currentDomain=${currentHost}

                if [[ -n "${currentDefaultPort}" && "${currentDefaultPort}" != "443" ]]; then
                    currentDomain="${currentHost}:${currentDefaultPort}"
                fi
                if [[ -n "${subscribePortLocal}" ]]; then
                    if [[ "${subscribeType}" == "http" ]]; then
                        currentDomain="$(getPublicIP):${subscribePort}"
                    else
                        currentDomain="${currentHost}:${subscribePort}"
                    fi
                fi
                if [[ -z "${showStatus}" ]]; then
                    echoContent skyBlue "\n----------默认订阅----------\n"
                    echoContent green "email:${email}\n"
                    echoContent yellow "url:${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/default/${emailMd5}\n"
                    if [[ "${release}" != "alpine" ]]; then
                        echo "${subscribeType}://${currentDomain}/s/default/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                    fi
                fi

                # clashMeta
                if [[ -f "/etc/padm/subscribe_local/clashMeta/${email}" ]]; then

                    cat "/etc/padm/subscribe_local/clashMeta/${email}" >>"/etc/padm/subscribe/clashMeta/${emailMd5}"

                    sed -i '1i\proxies:' "/etc/padm/subscribe/clashMeta/${emailMd5}"

                    local clashProxyUrl="${subscribeType}://${currentDomain}/s/clashMeta/${emailMd5}"
                    clashMetaConfig "${clashProxyUrl}" "${emailMd5}"
                    if [[ -z "${showStatus}" ]]; then
                        echoContent skyBlue "\n----------clashMeta订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/clashMetaProfiles/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi
                    fi

                fi
                # sing-box
                if [[ -f "/etc/padm/subscribe_local/sing-box/${email}" ]]; then
                    cp "/etc/padm/subscribe_local/sing-box/${email}" "/etc/padm/subscribe/sing-box_profiles/${emailMd5}"

                    [[ -z "${showStatus}" ]] && echoContent skyBlue " ---> 下载 sing-box 通用配置文件"
                    local localSingBoxTemplate="${SCRIPT_DIR:-/etc/padm}/documents/sing-box.json"
                    if [[ -f "${localSingBoxTemplate}" ]]; then
                        cp "${localSingBoxTemplate}" "/etc/padm/subscribe/sing-box/${emailMd5}"
                    else
                        downloadFile -O "/etc/padm/subscribe/sing-box/${emailMd5}" "https://raw.githubusercontent.com/neil1123-vip/padm/master/documents/sing-box.json"
                    fi

                    local singBoxOutboundTags
                    singBoxOutboundTags=$(jq -c '. | map(.tag)' "/etc/padm/subscribe_local/sing-box/${email}")
                    jq --argjson tags "${singBoxOutboundTags}" '.outbounds |= map(if has("outbounds") then .outbounds += $tags else . end)' "/etc/padm/subscribe/sing-box/${emailMd5}" >"/etc/padm/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/padm/subscribe/sing-box/${emailMd5}_tmp" "/etc/padm/subscribe/sing-box/${emailMd5}"
                    jq --slurpfile localOutbounds "/etc/padm/subscribe_local/sing-box/${email}" '.outbounds += $localOutbounds[0]' "/etc/padm/subscribe/sing-box/${emailMd5}" >"/etc/padm/subscribe/sing-box/${emailMd5}_tmp" && mv "/etc/padm/subscribe/sing-box/${emailMd5}_tmp" "/etc/padm/subscribe/sing-box/${emailMd5}"

                    if [[ -z "${showStatus}" ]]; then
                        echoContent skyBlue "\n----------sing-box订阅----------\n"
                        echoContent yellow "url:${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        echoContent yellow "在线二维码:https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}\n"
                        if [[ "${release}" != "alpine" ]]; then
                            echo "${subscribeType}://${currentDomain}/s/sing-box/${emailMd5}" | qrencode -s 10 -m 1 -t UTF8
                        fi
                    fi

                fi

                if [[ -z "${showStatus}" ]]; then
                    echoContent skyBlue "--------------------------------------------------------------"
                else
                    echoContent green " ---> email:${email}，订阅已更新，请使用客户端重新拉取"
                fi

            done
        fi
    else
        echoContent red " ---> 未安装传统 TLS fallback 静态站点，无法使用订阅服务"
    fi
}


# 随机salt
initRandomSalt() {
    local chars="abcdefghijklmnopqrtuxyz"
    local initCustomPath=
    for i in {1..10}; do
        echo "${i}" >/dev/null
        initCustomPath+="${chars:RANDOM%${#chars}:1}"
    done
    echo "${initCustomPath}"
}

# 切换alpn
switchAlpn() {
    echoContent skyBlue "\n功能 1/${totalProgress} : 切换alpn"
    if [[ -z ${currentAlpn} ]]; then
        echoContent red " ---> 无法读取alpn，请检查是否安装"
        exit 0
    fi

    echoContent red "\n=============================================================="
    echoContent green "当前alpn首位为:${currentAlpn}"
    echoContent yellow "  1.当http/1.1首位时，trojan可用，gRPC部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  2.当h2首位时，gRPC可用，trojan部分客户端可用【客户端支持手动选择alpn的可用】"
    echoContent yellow "  3.如客户端不支持手动更换alpn，建议使用此功能更改服务端alpn顺序，来使用相应的协议"
    echoContent red "=============================================================="

    if [[ "${currentAlpn}" == "http/1.1" ]]; then
        echoContent yellow "1.切换alpn h2 首位"
    elif [[ "${currentAlpn}" == "h2" ]]; then
        echoContent yellow "1.切换alpn http/1.1 首位"
    else
        echoContent red '不符合'
    fi

    echoContent red "=============================================================="

    read -r -p "请选择:" selectSwitchAlpnType
    if [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "http/1.1" ]]; then

        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn = [\"h2\",\"http/1.1\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json

    elif [[ "${selectSwitchAlpnType}" == "1" && "${currentAlpn}" == "h2" ]]; then
        local frontingTypeJSON
        frontingTypeJSON=$(jq -r ".inbounds[0].streamSettings.tlsSettings.alpn =[\"http/1.1\",\"h2\"]" ${configPath}${frontingType}.json)
        echo "${frontingTypeJSON}" | jq . >${configPath}${frontingType}.json
    else
        echoContent red " ---> 选择错误"
        exit 0
    fi
    reloadCore
}


# reality管理
regenerateRealityProfile() {
    if [[ "${coreInstallType}" == "1" ]]; then
        selectCustomInstallType=",7,"
        initXrayConfig custom 1 true
    elif [[ "${coreInstallType}" == "2" ]]; then
        if currentProtocolHas 7; then
            selectCustomInstallType=",7,"
        fi
        if currentProtocolHas 8; then
            selectCustomInstallType="${selectCustomInstallType},8,"
        fi
        initSingBoxConfig custom 1 true
    fi

    reloadCore
    subscribe false
}

manageReality() {
    readInstallProtocolType
    readConfigHostPathUUID
    readCustomPort
    readSingBoxConfig

    if ! currentProtocolHasAny 7 8 12 || [[ -z "${coreInstallType}" ]]; then
        echoContent red "\n ---> 请先安装 Reality 协议。新人路径：主菜单 1.安装管理 -> 3.无域名 Reality 安装，或 1.安装管理 -> 2.自定义安装中选择 Reality 编号"
        exit 0
    fi

    echoContent skyBlue "\n┌─ REALITY 管理 ─────────────────────────────────────"
    menuItem 1 "重新生成 Reality 参数" "更新 key、shortId 等 Reality 参数"
    menuItem 2 "配置 443 共存分流" "同机真实网站与 Reality 共用公网 443"
    menuItem 3 "查看当前分流状态" "检查 state、Nginx stream 与后端监听"
    menuItem 4 "关闭 443 共存分流" "恢复 Reality 原入口端口并清理分流配置"
    menuLine "Reality 不需要本机伪装站点；443 共存分流仅用于同机真实网站"
    menuLine "分流时只填写真实网站域名，其他 SNI 默认转给 Reality"
    menuClose
    read -r -p "请选择:" selectRealityManageType

    case "${selectRealityManageType}" in
    1)
        regenerateRealityProfile
        ;;
    2)
        configureRealityStreamSplit
        ;;
    3)
        showRealityStreamSplitStatus
        ;;
    4)
        disableRealityStreamSplit
        ;;
    *)
        echoContent red " ---> 选择错误"
        ;;
    esac
}


# hysteria管理
manageHysteria() {
    echoContent skyBlue "\n┌─ Hysteria2 管理 ───────────────────────────────────"
    local hysteria2Status=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/06_hysteria2_inbounds.json" ]]; then
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络场景"
        menuItem 1 "重新安装" "重建 Hysteria2 入站配置"
        menuItem 2 "卸载" "移除 Hysteria2 入站配置"
        menuItem 3 "端口跳跃管理" "配置 UDP 端口跳跃转发"
        hysteria2Status=true
    else
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络场景"
        menuItem 1 "安装" "新增 Hysteria2 入站配置"
    fi

    menuClose
    read -r -p "请选择:" installHysteria2Status
    if [[ "${installHysteria2Status}" == "1" ]]; then
        singBoxHysteria2Install
    elif [[ "${installHysteria2Status}" == "2" && "${hysteria2Status}" == "true" ]]; then
        unInstallSingBox hysteria2
    elif [[ "${installHysteria2Status}" == "3" && "${hysteria2Status}" == "true" ]]; then
        portHoppingMenu hysteria2
    fi
}


# tuic管理
manageTuic() {
    echoContent skyBlue "\n┌─ Tuic 管理 ────────────────────────────────────────"
    local tuicStatus=
    if [[ -n "${singBoxConfigPath}" ]] && [[ -f "/etc/padm/sing-box/conf/config/09_tuic_inbounds.json" ]]; then
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络或 QUIC/HTTP3 客户端场景"
        menuLine "不作为新人默认推荐"
        menuItem 1 "重新安装" "重建 Tuic 入站配置"
        menuItem 2 "卸载" "移除 Tuic 入站配置"
        menuItem 3 "端口跳跃管理" "配置 UDP 端口跳跃转发"
        tuicStatus=true
    else
        menuLine "依赖 sing-box 内核；适合 UDP、移动网络或 QUIC/HTTP3 客户端场景"
        menuLine "不作为新人默认推荐"
        menuItem 1 "安装" "新增 Tuic 入站配置"
    fi

    menuClose
    read -r -p "请选择:" installTuicStatus
    if [[ "${installTuicStatus}" == "1" ]]; then
        singBoxTuicInstall
    elif [[ "${installTuicStatus}" == "2" && "${tuicStatus}" == "true" ]]; then
        unInstallSingBox tuic
    elif [[ "${installTuicStatus}" == "3" && "${tuicStatus}" == "true" ]]; then
        portHoppingMenu tuic
    fi
}

# 操作Hysteria
handleHysteria() {
    # shellcheck disable=SC2010
    if find /bin /usr/bin | grep -q systemctl && ls /etc/systemd/system/ | grep -q hysteria.service; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "start" ]]; then
            systemctl start hysteria.service
        elif [[ -n $(pgrep -f "hysteria/hysteria") ]] && [[ "$1" == "stop" ]]; then
            systemctl stop hysteria.service
        fi
    fi
    sleep 0.8

    if [[ "$1" == "start" ]]; then
        if [[ -n $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> Hysteria启动成功"
        else
            echoContent red "Hysteria启动失败"
            echoContent red "请手动执行【/etc/padm/hysteria/hysteria --log-level debug -c /etc/padm/hysteria/conf/config.json server】，查看错误日志"
            exit 0
        fi
    elif [[ "$1" == "stop" ]]; then
        if [[ -z $(pgrep -f "hysteria/hysteria") ]]; then
            echoContent green " ---> Hysteria关闭成功"
        else
            echoContent red "Hysteria关闭失败"
            echoContent red "请手动执行【ps -ef|grep -v grep|grep hysteria|awk '{print \$2}'|xargs kill -9】"
            exit 0
        fi
    fi
}

