#!/usr/bin/env bash

if [[ "${PADM_DOCKER_LIFECYCLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_LIFECYCLE_LOADED=1

DOCKER_ASSESS_PROJECT=
DOCKER_ASSESS_CANDIDATE=
DOCKER_INSTALL_TRANSACTION_ACTIVE=0
DOCKER_INSTALL_PREVIOUS_BUNDLE_TARGET=
DOCKER_INSTALL_BUNDLE_TARGET=
DOCKER_INSTALL_CLI_PATH=
DOCKER_INSTALL_CLI_EXISTED=1
DOCKER_INSTALL_CLI_INODE=
DOCKER_INSTALL_CLI_TEMP_PATH=

dockerUsage() {
    cat >&2 <<'EOF'
用法:
  padm-docker                          # 交互终端进入菜单；非交互显示帮助
  padm-docker menu
  install-docker.sh install [--source <目录>] [--ref <commit|latest>] [--no-menu]
  padm-docker release [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker setup [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker edit [--spec <完整 JSON 文件>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --site-static <独立站点目录> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --site-template <notes|photos|docs> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --site-redirect <HTTP/HTTPS URL> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --site-default [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http01 <enable|disable> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5 <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-global [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay-port <端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay-sources|--http-relay-sources-add|--http-relay-sources-remove <来源 IP/CIDR CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tproxy-enable <端口> <标记> [--tproxy-family ipv4|ipv6|dual] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tproxy-settings <端口> <标记> [--tproxy-family ipv4|ipv6|dual] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tproxy-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tproxy-enable <端口> <标记> --tproxy-output-uid <UID> [--tproxy-family ipv4|ipv6|dual] [确认参数]
  padm-docker edit --tproxy-enable <端口> <标记> --tproxy-output-all [--tproxy-family ipv4|ipv6|dual] [确认参数]
  padm-docker edit --tproxy-settings <端口> <标记> [--tproxy-output-uid <UID>|--tproxy-output-all|--tproxy-output-off] [确认参数]
  padm-docker edit --redirect-enable <端口> [--redirect-family ipv4|ipv6|dual] [--redirect-output-uid <UID>|--redirect-output-all] [确认参数]
  padm-docker edit --redirect-settings <端口> [--redirect-family ipv4|ipv6|dual] [--redirect-output-uid <UID>|--redirect-output-all|--redirect-output-off] [确认参数]
  padm-docker edit --redirect-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tun-enable|--tun-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias <入口 ID> <公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias-remove <入口 ID> <公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias-replace <入口 ID> <旧公开端口> <新公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias-default <入口 ID> <已有额外端口|base> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-hopping <Hy2 入口 ID> <起始端口> <结束端口> <本机 IPv4> <本机 IPv6> [--preview|--confirm PADM-DOCKER-EDIT]
  padm-docker edit --port-hopping-clear [--preview|--confirm PADM-DOCKER-EDIT]
  padm-docker port-hopping <status|start|stop|share>
  padm-docker edit --cdn-entry <入口 ID> <IP或域名,...> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --cdn-entry-clear <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-preset <入口 ID> <daily|compatible|stream|single> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-xmux <入口 ID> <并发数或范围> <请求数或范围> <复用秒数或范围> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-xmux-clear <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-padding <入口 ID> <1-4096 的整数或正序范围> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-padding-clear <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-headers <入口 ID> <noGRPCHeader:true|false> <noSSEHeader:true|false> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-headers-clear <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-limits <入口 ID> <POST字节数> <间隔毫秒> <缓冲POST数> <流式秒数或范围> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --xhttp-limits-clear <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hy2-bandwidth <入口 ID> bbr [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hy2-bandwidth <入口 ID> brutal <服务端上行 Mbps> <服务端下行 Mbps> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tuic-congestion <入口 ID> <cubic|bbr|new_reno> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tuic-connection <入口 ID> <auth_timeout> <heartbeat> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tuic-zero-rtt <入口 ID> <true|false> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --tuic-defaults <入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-rules <IPv4/IPv6> <DNS 端口> <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-upstream <IPv4/IPv6> <端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-upstream <IPv4/IPv6> <端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts-replace <已有精确域名> <新字面 IPv4/IPv6> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts-add <新精确域名> <单个字面 IPv4/IPv6> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts-remove <已有精确域名> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-add <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-remove <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-replace <旧字面 IP/CIDR> <新字面 IP/CIDR> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-resolve|--block-ips-literal [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-bt [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-bt-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region <both|domain|ip> [--region-allow <域名规则 CSV>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-mode <both|domain|ip> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-allow-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-allow-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-allow-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --access-control-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6 <selective|global> [--ipv6-domains <域名规则 CSV>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-domains-remove <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-domains-replace <旧规则> <新规则> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-global [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-family <ipv4|ipv6> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --fail2ban-port <单个 WS 入口 ID> <新公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --alpn <入口 ID> <h2,http/1.1|http/1.1,h2|http/1.1> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker protocol list
  padm-docker protocol links [入口 ID]
  padm-docker protocol xhttp-status [入口 ID]
  padm-docker protocol hy2-status [入口 ID]
  padm-docker protocol tuic-status [入口 ID]
  padm-docker protocol stream-status
  padm-docker protocol alpn-status [入口 ID]
  padm-docker protocol routing-status
  padm-docker protocol tproxy-status
  padm-docker protocol redirect-status
  padm-docker protocol tun-status
  padm-docker protocol port-alias-status
  padm-docker protocol cdn-status [入口 ID]
  padm-docker account list [--json]
  padm-docker account create [--name <名称>] [--listeners <入口 ID,...>] [--disabled]
  padm-docker account edit <账号 ID> [--name <名称>] [--listeners <入口 ID,...>]
  padm-docker account copy <账号 ID> [--name <名称>] [--listeners <入口 ID,...>]
  padm-docker account enable <账号 ID>
  padm-docker account disable <账号 ID>
  padm-docker account delete <账号 ID> [--yes]
  padm-docker account rotate <账号 ID> [--yes]
   padm-docker subscription list [--json]
   padm-docker subscription create [--name <名称>] [--accounts <账号 ID,...>] [--listeners <入口 ID,...>] [--disabled]
   padm-docker subscription edit <分享组 ID> [--name <名称>] [--accounts <账号 ID,...>] [--listeners <入口 ID,...>]
   padm-docker subscription enable <分享组 ID>
   padm-docker subscription disable <分享组 ID>
   padm-docker subscription delete <分享组 ID> [--yes]
   padm-docker subscription rotate <分享组 ID> [--yes]
   padm-docker subscription content <分享组 ID>
   padm-docker subscription links <分享组 ID>
   padm-docker share <同上 subscription 命令>
  padm-docker control status [--json]
  padm-docker control init --address <WireGuard IPv4> --port <端口> --peer-address <对端 IPv4> [--yes]
  padm-docker control join --invite <私有邀请文件> --listener <入口 ID>... [--yes]
  padm-docker control sync --invite <私有邀请文件>
  padm-docker control source-check
  padm-docker control source-probe --address <WireGuard IPv4> --port <端口> --peer-address <对端 IPv4> --nonce <64 位 hex>
  padm-docker control log-rotate [--yes]
  padm-docker control log-schedule <enable|disable|status> [--yes]
  padm-docker control auto-log-rotate
  padm-docker control sync-schedule enable --invite <私有文件> [--yes]
  padm-docker control sync-schedule <disable|status> [--yes]
  padm-docker control auto-sync
  padm-docker business backup <绝对 JSON 路径>
  padm-docker business preview <备份 JSON 路径> --strategy <merge|replace>
  padm-docker business restore <备份 JSON 路径> --strategy <merge|replace> --yes
  padm-docker edit --reality-stream <Reality 入口 ID> <网站 TLS 入口 ID> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --reality-stream-host <Reality 入口 ID> <网站域名,域名> <宿主可达地址> <TLS 端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --reality-stream-loopback <Reality 入口 ID> <网站域名,域名> <127.0.0.1|::1> <TLS 端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --reality-stream off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker configure --spec <JSON 文件> [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker tls install --domain <域名> --cert <文件> --key <文件> [--ops-image <tag@digest>]
  padm-docker tls validate --domain <域名>
  padm-docker tls manage
  padm-docker acme <issue|renew> --domain <域名> --email <邮箱> <--dns <dns_*> --credentials <文件>|--standalone|--webroot> [--ops-image <tag@digest>]
  padm-docker acme schedule <enable|disable|status> [续期输入参数]
  padm-docker acme auto-renew
  padm-docker validate
  padm-docker status
  padm-docker traffic <show|collect>
  padm-docker traffic limit <账号 ID> <额度 GiB，0 不限额>
  padm-docker traffic reset <账号 ID>
  padm-docker fail2ban status
  padm-docker fail2ban unban <单个 IPv4/IPv6>
  padm-docker fail2ban enable <WS 端口,端口> <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban settings <WS 端口,端口> <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban disable [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban verify-source <WS 入口 ID> <外部客户端 IPv4/IPv6>
  padm-docker fail2ban control status
  padm-docker fail2ban control unban <单个 IPv4>
  padm-docker fail2ban control enable <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban control settings <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban control disable [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban ssh preflight [--json]
  padm-docker fail2ban ssh verify-source <本机 IPv4/IPv6> <SSH 端口> <外部客户端 IPv4/IPv6>
  padm-docker fail2ban ssh verify-unit <systemd service> <本机 IPv4/IPv6> <SSH 端口> <外部客户端 IPv4/IPv6>
  padm-docker fail2ban ssh status
  padm-docker fail2ban ssh unban <单个 IPv4/IPv6>
  padm-docker fail2ban ssh enable <systemd service> <本机 IPv4/IPv6> <SSH 端口> <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban ssh settings <systemd service> <本机 IPv4/IPv6> <SSH 端口> <失败阈值> <检测秒数> <封禁秒数> [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker fail2ban ssh disable [--preview | --confirm PADM-DOCKER-EDIT]
  padm-docker up
  padm-docker down
  padm-docker restart
  padm-docker logs [Compose logs 参数]
  padm-docker assess [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker geo <status|update [--version <固定 tag>]|auto-update>
  padm-docker geo schedule <enable|disable|status>
  padm-docker update [--manifest <URL|文件> --bundle <URL|文件> [--control-bundle <URL|文件>]]
  padm-docker rollback
  padm-docker uninstall [--remove-images] [--purge --confirm PADM-DOCKER-PURGE]
EOF
}

dockerTrafficScheduleCheck() {
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        return 0
    fi
    if command -v crontab >/dev/null 2>&1 && command -v pgrep >/dev/null 2>&1 &&
        { pgrep -x cron >/dev/null || pgrep -x crond >/dev/null; }; then
        return 0
    fi
    dockerError '自动流量采集需要正在运行的 systemd 或 cron，请先启用其中一项'
    return 1
}

dockerTrafficReadCrontab() {
    local content
    content=$(LC_ALL=C crontab -l 2>&1) || {
        case "${content}" in
        *'no crontab for'*|*"can't open 'root': No such file or directory"*) return 0 ;;
        *) dockerError "${content}"; return 1 ;;
        esac
    }
    printf '%s\n' "${content}"
}

dockerTrafficRuntimeCheck() {
    local cores=${1:-} core
    if [[ -z "${cores}" ]]; then
        cores=$(dockerTrafficCore) || return 1
    fi
    while IFS= read -r core; do
        case "${core}" in
        xray) ;;
        sing-box)
            dockerRequireCommand nsenter && dockerRequireCommand curl || return 1
            curl --version | grep -Eq '^Features:.*[[:space:]]HTTP2([[:space:]]|$)' || {
                dockerError 'sing-box 自动流量采集需要支持 HTTP/2 的宿主 curl'
                return 1
            }
            ;;
        *) dockerError "流量采集核心无效: ${core}"; return 1 ;;
        esac
    done <<<"${cores}"
    dockerTrafficScheduleCheck
}

dockerTrafficScheduleInstall() {
    dockerMaintenanceScheduleApply install traffic
}

dockerTrafficScheduleRemove() {
    dockerMaintenanceScheduleApply remove traffic
}

dockerRenewalScheduleRestore() {
    dockerMaintenanceScheduleRestore "$@" renewal
}

dockerRenewalScheduleInterrupted() {
    dockerMaintenanceScheduleInterrupted renewal
}

dockerRenewalScheduleCommit() {
    dockerMaintenanceScheduleCommit renewal
}

dockerRenewalScheduleApply() {
    dockerMaintenanceScheduleApply "$1" renewal
}

dockerRenewalScheduleInstall() {
    local root
    root=$(dockerInstallRoot) || return 1
    if [[ ! -e "${root}/secrets/renewal" && ! -L "${root}/secrets/renewal" ]]; then
        dockerRenewalScheduleRemove
        return $?
    fi
    dockerTrafficSafePath "${root}" "${root}/secrets/renewal" &&
        dockerRenewalRegistryValidate "${root}/secrets/renewal" || return 1
    if dockerRenewalEnabled "${root}/secrets/renewal"; then
        dockerRenewalScheduleApply install
    else
        [[ "$?" == 1 ]] || return 1
        dockerRenewalScheduleRemove
    fi
}

dockerRenewalScheduleRemove() {
    local unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system} content
    if [[ ! -e "${unitDir}/padm-docker-renewal.service" && ! -L "${unitDir}/padm-docker-renewal.service" &&
        ! -e "${unitDir}/padm-docker-renewal.timer" && ! -L "${unitDir}/padm-docker-renewal.timer" ]]; then
        command -v crontab >/dev/null 2>&1 || return 0
        content=$(dockerTrafficReadCrontab) || return 1
        [[ "${content}" == *'# padm-docker TLS 自动续期'* ]] || return 0
    fi
    dockerRenewalScheduleApply remove
}

dockerTrafficBeforeChange() {
    local root cores core
    root=$(dockerInstallRoot) || return 0
    [[ -f "${root}/deployment.json" ]] || return 0
    cores=$(dockerTrafficCore) || return 0
    while IFS= read -r core; do
        if [[ -f "${root}/config/${core}/users.base" ]]; then
            dockerTrafficSnapshot || dockerError '变更前采集失败，已保留历史流量；本次未采集的增量无法恢复'
            break
        fi
    done <<<"${cores}"
    return 0
}

dockerTrafficCommand() {
    local action=${1:-show} bytes
    [[ "$#" -eq 0 ]] || shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    case "${action}" in
    show|collect)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        if [[ "${action}" == show ]]; then dockerTrafficShow; else dockerTrafficCollect; fi
        ;;
    limit)
        [[ "$#" -eq 2 && "$2" =~ ^[0-9]+([.][0-9]{1,6})?$ ]] || return "${PADM_DOCKER_RC_USAGE}"
        bytes=$(jq -en --arg value "$2" '($value | tonumber) * 1073741824 | floor | select(. <= 9007199254740991)') ||
            return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficSetLimit "$1" "${bytes}"
        ;;
    reset)
        [[ "$#" -eq 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficReset "$1"
        ;;
    *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
    esac
}

dockerPrepareInstallSource() {
    local sourceRoot=$1 requestedRef=${2:-} bootstrapRef=${DOCKER_ENTRY_BOOTSTRAP_REF:-}
    DOCKER_ENTRY_BOOTSTRAP_REF=
    if [[ -z "${sourceRoot}" && -n "${requestedRef}" ]]; then
        if [[ "${requestedRef}" != "${bootstrapRef}" || -z "${DOCKER_ENTRY_FETCHED_REF:-}" ||
            ! -f "${DOCKER_ENTRY_SOURCE_DIR}/docker/lib/bootstrap.sh" ]]; then
            dockerEntryFetchBundle "${requestedRef}" || return 1
        fi
        sourceRoot=${DOCKER_ENTRY_SOURCE_DIR}
        requestedRef=${DOCKER_ENTRY_FETCHED_REF}
    fi
    [[ -n "${sourceRoot}" ]] || sourceRoot=${DOCKER_ENTRY_SOURCE_DIR}
    sourceRoot=$(cd -- "${sourceRoot}" 2>/dev/null && pwd -P) || return 1
    dockerBundleSourceIsComplete "${sourceRoot}" || return 1
    DOCKER_INSTALL_SOURCE_ROOT=${sourceRoot}
    DOCKER_INSTALL_SOURCE_REF=${requestedRef}
}

dockerInstallCommand() {
    local sourceRoot requestedRef root
    local previousBundleTarget= installedBundleTarget
    dockerEntryParseInstallArgs "$@" || return $?
    sourceRoot=${DOCKER_ENTRY_INSTALL_SOURCE}
    requestedRef=${DOCKER_ENTRY_INSTALL_REF}
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerAssertInstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerPrepareInstallSource "${sourceRoot}" "${requestedRef}" || {
        dockerError '无法准备 Docker 控制 bundle'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    dockerAcquireDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerAssertInstallAllowed || return "${PADM_DOCKER_RC_CONFLICT}"
    dockerInitializeStateRoot || {
        dockerError 'Docker 状态目录初始化失败'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/bundle" || -L "${root}/bundle" ]]; then
        previousBundleTarget=$(readlink "${root}/bundle" 2>/dev/null) &&
            dockerBundlePathForTarget "${previousBundleTarget}" >/dev/null || {
                dockerError '现有 Docker bundle 指针无法安全恢复，已取消安装'
                return "${PADM_DOCKER_RC_BUNDLE}"
            }
    fi
    DOCKER_INSTALL_TRANSACTION_ACTIVE=1
    DOCKER_INSTALL_PREVIOUS_BUNDLE_TARGET=${previousBundleTarget}
    DOCKER_INSTALL_BUNDLE_TARGET=
    DOCKER_INSTALL_CLI_PATH="${PADM_DOCKER_BIN_DIR:-/usr/local/bin}/padm-docker"
    DOCKER_INSTALL_CLI_EXISTED=0
    DOCKER_INSTALL_CLI_INODE=
    [[ ! -e "${DOCKER_INSTALL_CLI_PATH}" && ! -L "${DOCKER_INSTALL_CLI_PATH}" ]] ||
        DOCKER_INSTALL_CLI_EXISTED=1
    dockerInstallBundle "${DOCKER_INSTALL_SOURCE_ROOT}" "${DOCKER_INSTALL_SOURCE_REF}" || {
        dockerError 'Docker 控制 bundle 校验或切换失败'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    installedBundleTarget=$(readlink "${root}/bundle") || return "${PADM_DOCKER_RC_BUNDLE}"
    DOCKER_INSTALL_BUNDLE_TARGET=${installedBundleTarget}
    dockerInstallCli || {
        dockerError 'padm-docker 命令安装失败'
        dockerRestoreInstallTransaction || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    DOCKER_INSTALL_TRANSACTION_ACTIVE=0
    DOCKER_INSTALL_PREVIOUS_BUNDLE_TARGET=
    DOCKER_INSTALL_BUNDLE_TARGET=
    DOCKER_INSTALL_CLI_PATH=
    DOCKER_INSTALL_CLI_INODE=
    printf 'Docker 控制骨架已安装: %s\n' "${root}"
}

dockerRestoreInstallTransaction() {
    local root currentTarget expectedTarget previousTarget cliTarget
    local status=0
    [[ "${DOCKER_INSTALL_TRANSACTION_ACTIVE:-0}" == 1 ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerCleanupBundleLinkTemp || status=1
    dockerCleanupInstallCliTemp || status=1
    previousTarget=${DOCKER_INSTALL_PREVIOUS_BUNDLE_TARGET:-}
    expectedTarget=${DOCKER_INSTALL_BUNDLE_TARGET:-}
    currentTarget=$(readlink "${root}/bundle" 2>/dev/null || true)
    if [[ -e "${root}/bundle" || -L "${root}/bundle" ]] &&
        { [[ ! -L "${root}/bundle" ]] ||
            [[ "${currentTarget}" != "${previousTarget}" && "${currentTarget}" != "${expectedTarget}" ]]; }; then
        dockerError "本次 Docker bundle 指针已改变，未清理: ${root}/bundle"
        return 1
    fi
    if [[ -n "${previousTarget}" ]]; then
        dockerActivateBundle "${previousTarget}" || {
            dockerError "旧 Docker bundle 恢复失败，请检查: ${root}/bundle"
            return 1
        }
    elif [[ -n "${expectedTarget}" && -L "${root}/bundle" ]]; then
        [[ "${currentTarget}" == "${expectedTarget}" ]] || {
            dockerError "本次 Docker bundle 指针已改变，未清理: ${root}/bundle"
            return 1
        }
        rm -f -- "${root}/bundle" || {
            dockerError "本次 Docker bundle 指针清理失败，请检查: ${root}/bundle"
            return 1
        }
    elif [[ -e "${root}/bundle" || -L "${root}/bundle" ]]; then
        dockerError "本次 Docker bundle 指针已改变，未清理: ${root}/bundle"
        return 1
    fi
    cliTarget=${DOCKER_INSTALL_CLI_PATH:-}
    if [[ "${DOCKER_INSTALL_CLI_EXISTED:-1}" == 0 && -n "${DOCKER_INSTALL_CLI_INODE:-}" &&
        -L "${cliTarget}" &&
        "$(readlink "${cliTarget}" 2>/dev/null || true)" == "${root}/bundle/install-docker.sh" &&
        "$(stat --format=%d:%i -- "${cliTarget}" 2>/dev/null || true)" == "${DOCKER_INSTALL_CLI_INODE}" ]]; then
        dockerPathIsSafeAbsolute "${cliTarget}" && rm -f -- "${cliTarget}" || return 1
    fi
    DOCKER_INSTALL_TRANSACTION_ACTIVE=0
    DOCKER_INSTALL_PREVIOUS_BUNDLE_TARGET=
    DOCKER_INSTALL_BUNDLE_TARGET=
    DOCKER_INSTALL_CLI_PATH=
    DOCKER_INSTALL_CLI_INODE=
    DOCKER_INSTALL_CLI_TEMP_PATH=
    return "${status}"
}

dockerDeploymentState() {
    local state
    state=$(padmDockerDeploymentState) || return 1
    printf '%s\n' "${state}"
}

dockerRequireInstalledBundle() {
    local state marker root
    root=$(dockerInstallRoot) || return 1
    state=$(dockerDeploymentState) || return 1
    case "${state}" in
    installed | active) ;;
    absent)
        dockerError 'Docker 版 padm 尚未安装'
        return 1
        ;;
    *)
        dockerError 'Docker 版 padm 状态异常，已拒绝操作'
        return 1
        ;;
    esac
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    [[ "${marker}" == "docker" ]] || return 1
    dockerCurrentBundlePath >/dev/null || {
        dockerError '当前 Docker 控制 bundle 缺失或校验失败'
        return 1
    }
}

dockerComposeFile() {
    local root composeFile deploymentFile
    root=$(dockerInstallRoot) || return 1
    composeFile="${root}/compose.json"
    deploymentFile="${root}/deployment.json"
    [[ -f "${composeFile}" && ! -L "${composeFile}" ]] || return 1
    padmDockerDeploymentIdentityValid "${deploymentFile}" || return 1
    printf '%s\n' "${composeFile}"
}

dockerIPv6NetworkManage() {
    local action=${1:-cleanup} project=${2:-${PADM_DOCKER_PROJECT}} name ids state id
    [[ "${action}" == check || "${action}" == cleanup ]] &&
        [[ "${project}" == "${PADM_DOCKER_PROJECT}" || "${project}" =~ ^padm-docker-assess-[a-z0-9]{6}$ ]] ||
        return 1
    name="${project}-ipv6"
    ids=$(docker network ls -q --filter "name=^${name}$") || return 1
    [[ -n "${ids}" ]] || return 0
    [[ "${ids}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    state=$(docker network inspect "${ids}") || return 1
    if ! jq -e --arg name "${name}" --arg project "${project}" '
      length == 1 and (.[0] |
        .Name == $name and .Driver == "bridge" and .EnableIPv6 == true and
        .Labels["io.padm.mode"] == "docker" and .Labels["io.padm.project"] == $project and
        .Labels["io.padm.component"] == "routing-ipv6" and
        .Labels["com.docker.compose.project"] == $project and
        .Labels["com.docker.compose.network"] == "ipv6" and (.Containers | type == "object"))
    ' <<<"${state}" >/dev/null; then
        [[ "${action}" == cleanup ]] && return 0
        dockerError "IPv6 网络已存在但不属于本项目: ${name}"
        return 1
    fi
    [[ "${action}" == cleanup ]] || return 0
    # 不强制断开任何容器；未知归属或仍在使用的辅助网络保持不动。
    jq -e '.[0].Containers | length == 0' <<<"${state}" >/dev/null || return 0
    id=$(jq -er '.[0].Id' <<<"${state}") || return 1
    [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    docker network rm "${id}" >/dev/null
}

dockerComposeRun() {
    local root composeFile enabled controlEnabled sshEnabled argument composeFlags integrationFlags noDeps=0 recreate='' skipTimeout=0
    local specEnabled deployedEnabled specControlEnabled deployedControlEnabled specSshEnabled deployedSshEnabled
    local tproxyEnabled specTProxyEnabled deployedTProxyEnabled tproxyTouched=0 tproxyCore
    local -a services=()
    case "${1:-}" in up|restart|down|exec) ;; *) dockerComposeExecute "$@"; return $? ;; esac
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    case "${1:-}" in
    up|restart|exec)
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    composeFile=$(dockerComposeFile) || return "${PADM_DOCKER_RC_COMPOSE}"
    if jq -e 'any(.host_integrations[]?; .type == "tun")' "${root}/deployment.json" >/dev/null ||
        { [[ -f "${root}/config/spec.json" ]] &&
            jq -e 'any(.host_integrations[]?; .type == "tun")' "${root}/config/spec.json" >/dev/null; } ||
        [[ -e "${root}/data/net/transparent/tun.state" || -L "${root}/data/net/transparent/tun.state" ]]; then
        dockerTunComposeRun "$@"
        return $?
    fi
    composeFlags=$(jq -er -s '
      if length == 1 and (.[0] | type == "object" and (.services | type == "object")) then
        .[0].services |
        [has("net-fail2ban"), has("net-fail2ban-control"), has("net-fail2ban-ssh"),
         has("net-transparent")] | @tsv
      else error("编排文件结构无效") end
    ' "${composeFile}") || return "${PADM_DOCKER_RC_STATE}"
    IFS=$'\t' read -r enabled controlEnabled sshEnabled tproxyEnabled <<<"${composeFlags}"
    if [[ -f "${root}/config/spec.json" ]]; then
        integrationFlags=$(jq -er -s --slurpfile deployed "${root}/deployment.json" '
          if length == 1 and (.[0] | type == "object") and
              ($deployed | length == 1) and ($deployed[0] | type == "object") then
            def spec_enabled($kind): try any(.[0].host_integrations[]; .type == $kind) catch "error";
            def deployed_enabled($kind): try any($deployed[0].host_integrations[]; .type == $kind) catch "error";
            [spec_enabled("fail2ban"), deployed_enabled("fail2ban"),
             spec_enabled("fail2ban-control"), deployed_enabled("fail2ban-control"),
             spec_enabled("fail2ban-ssh"), deployed_enabled("fail2ban-ssh"),
             (spec_enabled("tproxy") or spec_enabled("redirect")),
             (deployed_enabled("tproxy") or deployed_enabled("redirect"))] | @tsv
          else error("Fail2ban 规格或部署结构无效") end
        ' "${root}/config/spec.json") || {
            dockerError 'Fail2ban 规格、部署与编排不一致，拒绝服务变更'
            return "${PADM_DOCKER_RC_STATE}"
        }
        IFS=$'\t' read -r specEnabled deployedEnabled specControlEnabled deployedControlEnabled \
            specSshEnabled deployedSshEnabled specTProxyEnabled deployedTProxyEnabled <<<"${integrationFlags}"
        [[ "${enabled}" == "${specEnabled}" && "${enabled}" == "${deployedEnabled}" ]] || {
            dockerError 'Fail2ban 规格、部署与编排不一致，拒绝服务变更'
            return "${PADM_DOCKER_RC_STATE}"
        }
        [[ "${controlEnabled}" == "${specControlEnabled}" &&
            "${controlEnabled}" == "${deployedControlEnabled}" ]] || {
            dockerError '控制 Fail2ban 规格、部署与编排不一致，拒绝服务变更'
            return "${PADM_DOCKER_RC_STATE}"
        }
        [[ "${sshEnabled}" == "${specSshEnabled}" &&
            "${sshEnabled}" == "${deployedSshEnabled}" ]] || {
            dockerError 'SSH Fail2ban 规格、部署与编排不一致，拒绝服务变更'
            return "${PADM_DOCKER_RC_STATE}"
        }
        [[ "${tproxyEnabled}" == "${specTProxyEnabled}" &&
            "${tproxyEnabled}" == "${deployedTProxyEnabled}" ]] || {
            dockerError 'TProxy 规格、部署与编排不一致，拒绝服务变更'
            return "${PADM_DOCKER_RC_STATE}"
        }
    elif [[ "${enabled}" == true || "${controlEnabled}" == true || "${sshEnabled}" == true ||
        "${tproxyEnabled}" == true ]]; then
        dockerError 'Fail2ban/TProxy 缺少受管规格，拒绝服务变更'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "${sshEnabled}" == true && "${controlEnabled}" == true ]]; then
        dockerError 'SSH 与控制面 INPUT 防护暂不支持共存，拒绝服务变更'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ "$1" == up || "$1" == restart || "$1" == down ]]; then
        if [[ "${tproxyEnabled}" == true && "$1" != down ]]; then
            local -a tproxyServices=()
            local tproxyNoDeps=0 tproxySkipTimeout=0
            tproxyCore=$(jq -er '.core.type' "${root}/config/spec.json") || return "${PADM_DOCKER_RC_STATE}"
            for argument in "${@:2}"; do
                if [[ "${tproxySkipTimeout}" == 1 ]]; then
                    [[ "${argument}" =~ ^[1-9][0-9]*$ ]] || return "${PADM_DOCKER_RC_USAGE}"
                    tproxySkipTimeout=0
                    continue
                fi
                case "${argument}" in
                --no-deps) tproxyNoDeps=1 ;;
                --wait-timeout) tproxySkipTimeout=1 ;;
                -d|--wait|--force-recreate) ;;
                *)
                    jq -e --arg service "${argument}" '.services | has($service)' \
                        "${composeFile}" >/dev/null || return "${PADM_DOCKER_RC_USAGE}"
                    tproxyServices+=("${argument}")
                    ;;
                esac
            done
            [[ "${tproxySkipTimeout}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            if [[ "${#tproxyServices[@]}" == 0 || " ${tproxyServices[*]} " == *' net-transparent '* ||
                " ${tproxyServices[*]} " == *" ${tproxyCore} "* ||
                "${tproxyNoDeps}" == 0 ]]; then
                tproxyTouched=1
            fi
        else
            tproxyTouched=1
        fi
        if [[ "${tproxyTouched}" == 1 ]]; then
            if [[ -f "${root}/config/spec.json" ]]; then
                dockerTProxyDisablePrepare "${root}/config/spec.json"
            else
                dockerTProxyDisablePrepare "${root}/deployment.json"
            fi || return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    if [[ "${enabled}" == true || "${controlEnabled}" == true || "${sshEnabled}" == true ]]; then
        case "${1:-}" in
        up|restart)
            for argument in "${@:2}"; do
                if [[ "${skipTimeout}" == 1 ]]; then
                    [[ "${argument}" =~ ^[1-9][0-9]*$ ]] || return "${PADM_DOCKER_RC_USAGE}"
                    skipTimeout=0
                    continue
                fi
                case "${argument}" in
                --no-deps) noDeps=1 ;;
                --force-recreate) recreate=recreate ;;
                --wait-timeout) skipTimeout=1 ;;
                -d|--wait) ;;
                *)
                    jq -e --arg service "${argument}" '.services | has($service)' \
                        "${composeFile}" >/dev/null || return "${PADM_DOCKER_RC_USAGE}"
                    services+=("${argument}")
                    ;;
                esac
            done
            [[ "${skipTimeout}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
            [[ "$1" != restart ]] || recreate=restart
            if [[ "${noDeps}" == 1 && "${#services[@]}" -gt 0 &&
                ( "${tproxyEnabled}" != true || "${tproxyTouched}" == 0 ) &&
                " ${services[*]} " != *' net-fail2ban '* && " ${services[*]} " != *' net-fail2ban-control '* &&
                " ${services[*]} " != *' net-fail2ban-ssh '* &&
                " ${services[*]} " != *' nginx '* && " ${services[*]} " != *' control '* &&
                " ${services[*]} " != *' net-wireguard '* ]]; then
                dockerComposeExecute "$@"
                return $?
            fi
            { [[ "${enabled}" != true ]] || dockerFail2banConfigurationCheck; } &&
                { [[ "${controlEnabled}" != true ]] || dockerControlFail2banConfigurationCheck; } &&
                { [[ "${sshEnabled}" != true ]] || dockerFail2banConfigurationCheck current ssh; } || {
                dockerError '当前 Fail2ban 编排不是受管新策略，请先通过 update 规范化后再启动'
                return "${PADM_DOCKER_RC_STATE}"
            }
            dockerFail2banSourceInputsCheck "${root}/config/spec.json" &&
                dockerFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerControlFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerSshFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerFail2banStartManagedVerified "${recreate}" || return "${PADM_DOCKER_RC_STATE}"
            if [[ "${tproxyEnabled}" == true ]]; then
                dockerComposeExecute up -d --wait \
                    --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" net-transparent ||
                    return "${PADM_DOCKER_RC_STATE}"
            fi
            [[ "${tproxyEnabled}" != true ]] || dockerTProxyContainer >/dev/null ||
                return "${PADM_DOCKER_RC_STATE}"
            return 0
            ;;
        down)
            dockerFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerControlFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerSshFail2banDisablePrepare "${root}/config/spec.json" ||
                return "${PADM_DOCKER_RC_STATE}"
            ;;
        exec)
            if [[ "${enabled}" == true && " $* " == *' nginx '* && " $* " == *' reload '* ]]; then
                dockerFail2banConfigurationCheck &&
                    dockerFail2banSourceInputsCheck "${root}/config/spec.json" &&
                    dockerFail2banDisablePrepare "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
            fi
            ;;
        esac
    elif [[ "$1" == up || "$1" == restart || "$1" == down ]]; then
        if [[ -f "${root}/config/spec.json" ]]; then
            dockerFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerControlFail2banDisablePrepare "${root}/config/spec.json" &&
                dockerSshFail2banDisablePrepare "${root}/config/spec.json" ||
                return "${PADM_DOCKER_RC_STATE}"
        else
            dockerFail2banDisablePrepare "${root}/deployment.json" &&
                dockerControlFail2banDisablePrepare "${root}/deployment.json" &&
                dockerSshFail2banDisablePrepare "${root}/deployment.json" ||
                return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    if [[ "${tproxyEnabled}" == true && "${tproxyTouched}" == 1 && "$1" == restart ]]; then
        local -a tproxyRestart=()
        for argument in "${@:2}"; do
            [[ "${argument}" == net-transparent ]] || tproxyRestart+=("${argument}")
        done
        # 已精确撤销并删除规则容器，restart 后须重新创建它而不是遗漏旧服务。
        if [[ "${#tproxyServices[@]}" != 1 || "${tproxyServices[0]}" != net-transparent ]]; then
            dockerComposeExecute restart "${tproxyRestart[@]}" || return $?
        fi
        dockerComposeExecute up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" \
            net-transparent || return $?
        dockerTProxyContainer >/dev/null || return "${PADM_DOCKER_RC_STATE}"
    else
        dockerComposeExecute "$@" || return $?
        if [[ "${tproxyEnabled}" == true && "${tproxyTouched}" == 1 && "$1" == up ]]; then
            dockerComposeExecute up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" \
                net-transparent || return $?
            dockerTProxyContainer >/dev/null || return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
}

dockerTunComposeRun() {
    local root argument status=0 skipTimeout=0 noDeps=0 touched=0
    local DOCKER_TUN_START_TOKEN=
    local -a services=() args=()
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerTunConfigurationCheck || return "${PADM_DOCKER_RC_STATE}"
    [[ "$1" != exec ]] || { dockerComposeExecute "$@"; return $?; }
    for argument in "${@:2}"; do
        if [[ "${skipTimeout}" == 1 ]]; then
            [[ "${argument}" =~ ^[1-9][0-9]*$ ]] || return "${PADM_DOCKER_RC_USAGE}"
            skipTimeout=0
            continue
        fi
        case "${argument}" in
        --no-deps) noDeps=1; args+=("${argument}") ;;
        --wait-timeout) skipTimeout=1 ;;
        -d|--wait|--force-recreate) args+=("${argument}") ;;
        *)
            jq -e --arg name "${argument}" '.services | has($name)' "${root}/compose.json" >/dev/null ||
                return "${PADM_DOCKER_RC_USAGE}"
            [[ "${argument}" != net-tun-check ]] || return "${PADM_DOCKER_RC_USAGE}"
            services+=("${argument}") args+=("${argument}")
            ;;
        esac
    done
    [[ "${skipTimeout}" == 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    if [[ "$1" == down || "${#services[@]}" == 0 || "${noDeps}" == 0 ||
        " ${services[*]} " == *' sing-box '* ]]; then
        touched=1
    fi
    [[ "${touched}" == 1 ]] || { dockerComposeExecute "$@"; return $?; }
    # 停止前审计完整归属；异常退出不借重启或恢复覆盖现场。
    dockerTunDisablePrepare "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    [[ "$1" != down ]] || { dockerComposeExecute "$@"; return $?; }
    dockerTunStartPrepare || return "${PADM_DOCKER_RC_STATE}"
    # 旧核心已被精确移除；restart 在这里创建新实例，再绑定本次启动意图。
    dockerComposeExecute up -d --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" \
        "${args[@]}" || status=$?
    if [[ "${status}" == 0 ]]; then
        dockerTunStartVerify || return "${PADM_DOCKER_RC_STATE}"
    else
        dockerTunStartAbort || {
            dockerError 'TUN 启动未完成且内核现场不能证明清净，保留状态待核对'
            return "${PADM_DOCKER_RC_STATE}"
        }
        return "${status}"
    fi
}

dockerFail2banStartManagedVerified() {
    local mf_root mf_spec mf_hash mf_plan mf_tuple mf_listener mf_family mf_source mf_services mf_index
    local mf_ws mf_control mf_ssh mf_current mf_phase=prepare mf_lockOwner=${BASHPID:-$$} mf_sshMode=
    local -a mf_starts=() mf_tuples=() mf_snapshots=() mf_recreate=() mf_jails=()
    case "${1:-}" in
    ''|restart) ;;
    recreate) mf_recreate=(--force-recreate); mf_sshMode=recreate ;;
    *) return 1 ;;
    esac
    [[ -n "${DOCKER_DEPLOYMENT_LOCK_DIR:-}" &&
        "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null || true)" == "${mf_lockOwner}" ]] || return 1
    mf_root=$(dockerInstallRoot) || return 1
    mf_spec="${mf_root}/config/spec.json"
    mf_ws=$(jq -r '.services | has("net-fail2ban")' "${mf_root}/compose.json") &&
        mf_control=$(jq -r '.services | has("net-fail2ban-control")' "${mf_root}/compose.json") &&
        mf_ssh=$(jq -r '.services | has("net-fail2ban-ssh")' "${mf_root}/compose.json") &&
        mf_hash=$(sha256sum -- "${mf_spec}") || return 1
    [[ "${mf_ws}" == true || "${mf_control}" == true || "${mf_ssh}" == true ]] || return 1
    [[ "${mf_ssh}" != true || "${mf_control}" != true ]] || return 1
    if [[ "${mf_ws}" == true ]]; then
        dockerFail2banSourceInputsCheck "${mf_spec}" &&
            mf_plan=$(dockerFail2banSourcePlan "${mf_spec}") &&
            [[ "$(jq 'length' <<<"${mf_plan}")" -gt 0 ]] &&
            dockerFail2banConfigurationCheck && dockerFail2banCleanCheck || return 1
        mapfile -t mf_tuples < <(jq -c '.[]' <<<"${mf_plan}")
        mf_jails+=(net-fail2ban)
    fi
    if [[ "${mf_control}" == true ]]; then
        dockerControlFail2banConfigurationCheck || return 1
        mf_jails+=(net-fail2ban-control)
    fi
    if [[ "${mf_ssh}" == true ]]; then
        dockerFail2banConfigurationCheck current ssh || return 1
    fi
    mf_services=$(jq -er --argjson ws "${mf_ws}" --argjson control "${mf_control}" \
        --slurpfile deployment "${mf_root}/deployment.json" '
      [.services | to_entries[] |
        select(.key != "net-fail2ban" and .key != "net-fail2ban-control" and .key != "net-fail2ban-ssh") |
        select((.value.profiles // [] | index("net-check")) == null) |
        select((.value.profiles // [] | length) == 0 or
          any(.value.profiles[]; . as $p | $deployment[0].compose.profiles | index($p))) |
        select((.value.depends_on // {} | has("net-fail2ban") or has("net-fail2ban-control") or
          has("net-fail2ban-ssh")) | not) |
        .key] |
      if length > 0 and (if $ws then index("nginx") != null else true end) and
        (if $control then index("control") != null and index("net-wireguard") != null else true end)
      then .[] else error("missing protection source services") end
    ' "${mf_root}/compose.json") || return 1
    mapfile -t mf_starts <<<"${mf_services}"
    # 所有 jail 均不进入普通启动列表；来源先就绪，SSH collector 与 jail 另行联合启动。
    if [[ "${1:-}" == restart ]]; then
        dockerComposeExecute restart --no-deps "${mf_starts[@]}" >/dev/null || return 1
    fi
    dockerComposeExecute up -d "${mf_recreate[@]}" --wait \
        --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" "${mf_starts[@]}" >/dev/null || return 1
    for mf_tuple in "${mf_tuples[@]}"; do
        mf_listener=$(jq -er '.listener_id' <<<"${mf_tuple}") &&
            mf_family=$(jq -er '.family' <<<"${mf_tuple}") &&
            mf_current=$(dockerFail2banSourceContainer "${mf_listener}" "${mf_family}") || return 1
        mf_snapshots+=("${mf_current}")
    done
    for mf_tuple in "${mf_tuples[@]}"; do
        mf_listener=$(jq -er '.listener_id' <<<"${mf_tuple}") &&
            mf_family=$(jq -er '.family' <<<"${mf_tuple}") || return 1
        mf_source="DOCKER_FAIL2BAN_SOURCE_${mf_family^^}"
        dockerFail2banSourceWitness "${mf_listener}" "${!mf_source}" >&2 || return 1
    done
    mf_phase=witnessed
    if [[ "${mf_control}" == true ]]; then
        dockerControlFail2banCleanCheck || return 1
        # 控制 nonce 最后取得；完成回调保留本次登记，启 jail 前再次核对全部来源。
        dockerControlSourceWitnessLocked dockerFail2banStartManagedCommit >&2
    else
        dockerFail2banStartManagedCommit
    fi
}

dockerFail2banStartManagedCommit() {
    [[ "${mf_phase:-}" == witnessed && -n "${mf_hash:-}" &&
        "$(cat "${DOCKER_DEPLOYMENT_LOCK_DIR}/pid" 2>/dev/null || true)" == "${mf_lockOwner}" ]] || return 1
    { [[ "${mf_ws}" != true ]] || { dockerFail2banConfigurationCheck && dockerFail2banCleanCheck; }; } &&
        { [[ "${mf_control}" != true ]] ||
            { dockerControlFail2banConfigurationCheck && dockerControlFail2banCleanCheck; }; } || return 1
    for ((mf_index = 0; mf_index < ${#mf_tuples[@]}; mf_index++)); do
        mf_listener=$(jq -er '.listener_id' <<<"${mf_tuples[mf_index]}") &&
            mf_family=$(jq -er '.family' <<<"${mf_tuples[mf_index]}") &&
            mf_current=$(dockerFail2banSourceContainer "${mf_listener}" "${mf_family}") &&
            [[ "${mf_current}" == "${mf_snapshots[mf_index]}" ]] || return 1
    done
    [[ "$(sha256sum -- "${mf_spec}")" == "${mf_hash}" ]] &&
        { [[ "${mf_control}" != true ]] || dockerControlSourceWitnessRecheck; } || return 1
    if [[ "${#mf_jails[@]}" -gt 0 ]]; then
        dockerComposeExecute up -d --no-deps --wait \
            --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" "${mf_jails[@]}" >/dev/null &&
            { [[ "${mf_ws}" != true ]] || dockerFail2banContainer >/dev/null; } &&
            { [[ "${mf_control}" != true ]] || dockerControlFail2banContainer >/dev/null; } || return 1
    fi
    [[ "${mf_ssh}" != true ]] || dockerSshFail2banStartVerified "${mf_sshMode}"
}

dockerPortHoppingTargetProjectCheck() {
    local root=$1 ids metadata
    local -a containers=() timed=()
    [[ "${ph_guarded:-false}" != true ]] || timed=(timeout -k 2 5)
    ids=$("${timed[@]}" docker ps -aq --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}") || return 1
    [[ -n "${ids}" ]] || return 0
    mapfile -t containers <<<"${ids}"
    [[ "${#containers[@]}" -eq 1 && "${containers[0]}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    metadata=$("${timed[@]}" docker container inspect "${containers[@]}") || return 1
    jq -e --arg root "${root}" --arg id "${containers[0]}" '
      length == 1 and (.[0] |
        (.Id | test("^[a-f0-9]{64}$") and startswith($id)) and
        (.Config.Labels as $l |
          $l["com.docker.compose.project"] == "padm-docker" and
          $l["com.docker.compose.service"] == "sing-box" and
          $l["com.docker.compose.oneoff"] == "False" and
          $l["com.docker.compose.project.working_dir"] == $root and
          $l["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
          $l["io.padm.mode"] == "docker" and $l["io.padm.project"] == "padm-docker" and
          $l["io.padm.component"] == "sing-box"))
    ' <<<"${metadata}" >/dev/null
}

dockerPortHoppingTargetStopOwned() {
    local root=$1 initial=$2 replacement=$3 ids metadata confirmed
    ids=$(docker ps -aq --filter "label=com.docker.compose.project=${PADM_DOCKER_PROJECT}" \
        --filter label=com.docker.compose.service=sing-box --filter label=com.docker.compose.oneoff=False) || return 1
    [[ -n "${ids}" ]] || return 0
    [[ "${ids}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
    metadata=$(docker container inspect "${ids}") || return 1
    jq -e --arg root "${root}" --arg id "${ids}" --arg replacement "${replacement}" \
        --argjson initial "${initial}" '
      length == 1 and (.[0] |
        (.Id | test("^[a-f0-9]{64}$") and startswith($id)) and .Image == $initial.image_id and
        (if $replacement == "true" then true else
          .Id == $initial.container_id and .State.StartedAt == $initial.started_at end) and
        (.Config.Labels as $l |
          $l["com.docker.compose.project"] == "padm-docker" and
          $l["com.docker.compose.service"] == "sing-box" and
          $l["com.docker.compose.oneoff"] == "False" and
          $l["com.docker.compose.project.working_dir"] == $root and
          $l["com.docker.compose.project.config_files"] == ($root + "/compose.json") and
          $l["io.padm.mode"] == "docker" and $l["io.padm.project"] == "padm-docker" and
          $l["io.padm.component"] == "sing-box"))
    ' <<<"${metadata}" >/dev/null || return 1
    confirmed=$(docker container inspect "${ids}") &&
        [[ "$(jq -Sc '.[0] | {Id,Image,Config,started_at:.State.StartedAt}' <<<"${confirmed}")" == \
            "$(jq -Sc '.[0] | {Id,Image,Config,started_at:.State.StartedAt}' <<<"${metadata}")" ]] || return 1
    dockerPortHoppingTargetStartLockCheck &&
        docker stop -t 10 "${ids}" >/dev/null &&
        dockerPortHoppingTargetStartLockCheck || return 1
    confirmed=$(docker container inspect "${ids}") || return 1
    jq -e --arg id "${ids}" 'length == 1 and (.[0] |
      (.Id | startswith($id)) and .State.Running == false and .State.Restarting == false and
      (.State.Status == "exited" or .State.Status == "dead"))' <<<"${confirmed}" >/dev/null
}

dockerPortHoppingTargetStartLockCheck() {
    local current
    current=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") &&
        [[ "${current}" == "${ph_lock}" ]] && return 0
    # 外层清理只核对 pid，锁身份漂移时必须阻止其删除替换锁。
    DOCKER_DEPLOYMENT_LOCK_DIR=
    dockerError "跳跃目标部署锁身份变化，保留事务证据: ${ph_stage}"
    return 1
}

dockerPortHoppingTargetStartFilesCheck() {
    local current output status=0
    local -a snapshots=()
    output=$(dockerPortHoppingTargetSnapshot start "${ph_owner}" "${ph_domain}" "" "${ph_lock}") ||
        status=$?
    [[ -z "${output}" ]] || mapfile -t snapshots <<<"${output}"
    if [[ "${#snapshots[@]}" == 0 || "${snapshots[0]}" != "${ph_lock}" ]]; then
        # 仅锁采样失败或身份漂移清标记；文件失败仍保留已核对的锁。
        DOCKER_DEPLOYMENT_LOCK_DIR=
        dockerError "跳跃目标部署锁身份变化，保留事务证据: ${ph_stage}"
        return 1
    fi
    [[ "${status}" == 0 && "${#snapshots[@]}" == 2 ]] || return 1
    current=${snapshots[1]}
    jq -e --arg mode "${ph_trafficMode}" --argjson files "${ph_files}" \
        --argjson live "${ph_live}" --argjson state "${ph_stateFile:-null}" '
      any(.[]; .[0] == "data/traffic" and .[3] != null and .[3] != false and
        ((.[3] | tostring) == $mode or .[3] == 16832)) and
      (map(select(.[0] != "data/traffic/state.json" and .[0] != "config/sing-box/config.json") |
        if .[0] == "data/traffic" then .[3] = 0 else . end) == $files) and
      ([.[] | select(.[0] == "config/sing-box/config.json")] == $live) and
      ($state == null or [.[] | select(.[0] == "data/traffic/state.json")] == $state)
    ' <<<"${current}" >/dev/null || return 1
    if [[ "${ph_verified}" == true ]]; then
        dockerTrafficSafePath "${ph_root}" "${ph_stage}/config.safe.expected" &&
            [[ -f "${ph_stage}/config.safe.expected" &&
                "$(sha256sum -- "${ph_stage}/config.safe.expected")" == "${ph_candidateHash}" ]] || return 1
    fi
    [[ "${ph_installed}" != true ]] ||
        cmp -s -- "${ph_root}/config/sing-box/config.json" "${ph_stage}/config.safe.expected"
}

dockerPortHoppingTargetStartInstall() {
    local current
    dockerPortHoppingTargetStartFilesCheck &&
        [[ "$(sha256sum -- "${ph_stage}/config.safe.expected")" == "${ph_candidateHash}" ]] || return 1
    cp -p -- "${ph_stage}/config.safe.expected" "${ph_stage}/config.next" || return 1
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] &&
        [[ "$(sha256sum -- "${ph_stage}/config.safe.expected")" == "${ph_candidateHash}" ]] &&
        cmp -s -- "${ph_stage}/config.next" "${ph_stage}/config.safe.expected" || return 1
    mv -f -- "${ph_stage}/config.next" "${ph_root}/config/sing-box/config.json" || return 1
    ph_installed=true
    cmp -s -- "${ph_root}/config/sing-box/config.json" "${ph_stage}/config.safe.expected" || return 1
    current=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "") &&
        ph_live=$(jq -c '[.[] | select(.[0] == "config/sing-box/config.json")]' <<<"${current}") || return 1
    dockerPortHoppingTargetStartFilesCheck
}

dockerPortHoppingTargetStartRecreate() {
    local witness current deadline identityFilter='.container_id != $initial.container_id'
    local healthTimeout=${PADM_DOCKER_HEALTH_TIMEOUT:-60}
    dockerPortHoppingTargetStartFilesCheck &&
        dockerPortHoppingTargetProjectCheck "${ph_root}" &&
        dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    # Compose 失败前可能已删旧 CID，恢复从此节点起必须核对当前服务归属。
    ph_runtime=true
    if [[ "${ph_restart:-false}" == true ]]; then
        [[ "${healthTimeout}" =~ ^[1-9][0-9]{0,2}$ ]] || return 1
        # 快照与安全配置已在同一事务形成；重启不再次采集，也不再重建核心。
        dockerLifecycleRestart >&2 || return 1
        identityFilter='.container_id == $initial.container_id'
        deadline=$(($(date +%s) + healthTimeout))
        while true; do
            dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
            current=$(timeout -k 2 5 docker container inspect \
                "$(jq -er '.container_id' <<<"${ph_initial}")") || return 1
            if jq -e 'length == 1 and .[0].State.Health.Status == "healthy"' \
                <<<"${current}" >/dev/null; then break; fi
            [[ "$(date +%s)" -lt "${deadline}" ]] || return 1
            sleep 0.1
        done
    else
        dockerComposeExecute up -d --force-recreate --no-deps --wait \
            --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" sing-box >&2 || return 1
    fi
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    witness=$(dockerPortHoppingTargetInspect start-after "${ph_listener}" "${ph_ipv4}" "${ph_ipv6}" "${ph_stage}") &&
        dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    jq -e --argjson initial "${ph_initial}" "
      ${identityFilter} and .started_at != \$initial.started_at and
      .image_id == \$initial.image_id and .listener_id == \$initial.listener_id and
      .target_port == \$initial.target_port and .ipv4 == \$initial.ipv4 and .ipv6 == \$initial.ipv6
    " <<<"${witness}" >/dev/null || return 1
    ph_witness=${witness}
}

dockerPortHoppingTargetStartPrepare() {
    local current state count
    ph_initial=$(dockerPortHoppingTargetInspect start-before "${ph_listener}" "${ph_ipv4}" "${ph_ipv6}" "${ph_stage}") &&
        dockerPortHoppingTargetProjectCheck "${ph_root}" &&
        dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    cp -p -- "${ph_root}/config/sing-box/config.json" "${ph_stage}/config.old.evidence" || return 1
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    ph_snapshot=true
    dockerTrafficSnapshot sing-box >&2 || return 1
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    current=$(dockerTrafficContainerState sing-box) &&
        jq -e --argjson initial "${ph_initial}" '
          .id == $initial.container_id and .started_at == $initial.started_at
        ' <<<"${current}" >/dev/null || return 1
    state=$(dockerTrafficReadState) &&
        printf '%s\n' "${state}" >"${ph_stage}/state.new.json" &&
        dockerTrafficRender sing-box "${ph_stage}/users.base.expected" "${state}" \
            >"${ph_stage}/config.safe.expected" || return 1
    current=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "") &&
        ph_stateFile=$(jq -c '[.[] | select(.[0] == "data/traffic/state.json")]' <<<"${current}") &&
        jq -es --slurpfile state "${ph_stage}/state.new.json" 'length == 1 and .[0] == $state[0]' \
            "${ph_root}/data/traffic/state.json" >/dev/null || return 1
    count=$(jq -er --arg listener "${ph_listener}" '
      [.inbounds[] | select(.tag == $listener and .type == "hysteria2") | .users[]] | length
    ' "${ph_stage}/config.safe.expected") &&
        [[ "${count}" -gt 0 ]] || return 1
    chmod 0640 "${ph_stage}/config.safe.expected" || return 1
    if [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" != 1 ]]; then
        chown 10001:10001 "${ph_stage}/config.safe.expected" || return 1
    fi
    ph_candidateHash=$(sha256sum -- "${ph_stage}/config.safe.expected") || return 1
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] || return 1
    dockerComposeExecute run --rm --no-deps --entrypoint /usr/local/bin/sing-box \
        --volume "${ph_stage}/config.safe.expected:/etc/padm/sing-box/config.json:ro" \
        sing-box check -c /etc/padm/sing-box/config.json >&2 || return 1
    [[ "$(sha256sum -- "${ph_stage}/config.safe.expected")" == "${ph_candidateHash}" ]] || return 1
    ph_verified=true
    dockerPortHoppingTargetStartFilesCheck && [[ "${ph_signal}" == 0 ]] &&
        dockerPortHoppingTargetStartInstall && [[ "${ph_signal}" == 0 ]] &&
        dockerPortHoppingTargetStartRecreate && [[ "${ph_signal}" == 0 ]]
}

dockerPortHoppingTargetBindingCheck() {
    local witness=$1 binding=$2 domain=$3 current container
    local ph_owner=${BASHPID:-$$} ph_lock ph_stage=${ph_stage:-}
    local -a timed=()
    [[ "${ph_guarded:-false}" != true ]] || timed=(timeout -k 2 5)
    ph_lock=$(jq -ec '.lock' <<<"${binding}") &&
        dockerPortHoppingTargetStartLockCheck &&
        current=$(dockerPortHoppingTargetFileSnapshot "${domain}" "$(jq -er '.started_at' <<<"${witness}")") &&
        jq -e --argjson binding "${binding}" '
          . as $rows |
          {files:map(select(.[0] != "data/traffic/state.json" and .[0] != "config/sing-box/config.json") |
            if .[0] == "data/traffic" then .[3] = 0 else . end),
           state:[.[] | select(.[0] == "data/traffic/state.json")],
           live:[.[] | select(.[0] == "config/sing-box/config.json")]} ==
            ($binding | {files,state,live}) and
          any($rows[]; .[0] == "data/traffic" and .[3] == 16832)
        ' <<<"${current}" >/dev/null &&
        dockerPortHoppingTargetProjectCheck "$(dockerInstallRoot)" &&
        container=$("${timed[@]}" docker container inspect "$(jq -er '.container_id' <<<"${witness}")") &&
        jq -e --argjson witness "${witness}" '
          length == 1 and (.[0] |
            .Id == $witness.container_id and .Image == $witness.image_id and
            .State.StartedAt == $witness.started_at and .RestartCount == $witness.restart_count and
            .State.Status == "running" and .State.Running == true and
            .State.Restarting == false and .State.Paused == false and .State.Dead == false and
            .State.Health.Status == "healthy")
        ' <<<"${container}" >/dev/null &&
        [[ "$(dockerPortHoppingTargetFileSnapshot "${domain}" \
            "$(jq -er '.started_at' <<<"${witness}")")" == "${current}" ]] &&
        dockerPortHoppingTargetStartLockCheck
}

dockerPortHoppingTargetStartManaged() {
    local ph_owner=${BASHPID:-$$} ph_root ph_stage= ph_lock ph_domain ph_files ph_live ph_raw ph_trafficMode
    local ph_listener=${1:-} ph_ipv4=${2:-} ph_ipv6=${3:-} ph_initial= ph_witness= ph_candidateHash=
    local ph_snapshot=false ph_verified=false ph_runtime=false ph_installed=false ph_stateFile= ph_signal=0 ph_status=1
    local ph_int ph_term ph_state ph_binding= ph_bound=${4:-}
    [[ "$#" -eq 3 || ( "$#" -eq 4 && "${ph_bound}" == bound ) ]] || return 1
    ph_lock=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") || {
        DOCKER_DEPLOYMENT_LOCK_DIR=
        return 1
    }
    ph_root=$(dockerInstallRoot) &&
        ph_domain=$(jq -er --arg listener "${ph_listener}" '
          [.core.protocols[] | select(.listener_id == $listener) | .hy2.domain] |
          if length == 1 then .[0] else error("目标入口不唯一") end
        ' "${ph_root}/config/spec.json") || { dockerPortHoppingTargetStartLockCheck; return 1; }
    ph_raw=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "") &&
        ph_trafficMode=$(jq -er '.[] | select(.[0] == "data/traffic") | .[3]' <<<"${ph_raw}") &&
        ph_files=$(jq -c '
          map(select(.[0] != "data/traffic/state.json" and .[0] != "config/sing-box/config.json") |
            if .[0] == "data/traffic" then .[3] = 0 else . end)
        ' <<<"${ph_raw}") &&
        ph_live=$(jq -c '[.[] | select(.[0] == "config/sing-box/config.json")]' <<<"${ph_raw}") ||
        { dockerPortHoppingTargetStartLockCheck; return 1; }
    ph_stage=$(mktemp -d "${ph_root}/.hopping-start.XXXXXX") ||
        { dockerPortHoppingTargetStartLockCheck; return 1; }
    dockerPortHoppingTargetStartLockCheck || return 1
    ph_int=$(trap -p INT)
    ph_term=$(trap -p TERM)
    trap 'ph_signal=130' INT
    trap 'ph_signal=143' TERM
    if dockerPortHoppingTargetStartPrepare; then ph_status=0; else ph_status=$?; fi
    # 恢复不继续原流程；已提交 state 从不回退，旧配置只作为证据。
    [[ "${ph_signal}" == 0 ]] || ph_status=${ph_signal}
    if [[ "${ph_status}" != 0 ]]; then
        trap '' INT TERM
        ph_signal=0
        if dockerPortHoppingTargetStartLockCheck && [[ "${ph_snapshot}" == true ]]; then
            ph_state=$(dockerTrafficReadState) || ph_state=
            if [[ -z "${ph_state}" || "${ph_state}" != "$(<"${ph_stage}/state.initial.json")" ||
                "${ph_runtime}" == true ]]; then
                if [[ "${ph_restart:-false}" != true && "${ph_verified}" == true ]] &&
                    dockerPortHoppingTargetStartInstall &&
                    dockerPortHoppingTargetStartRecreate; then
                    dockerError "跳跃目标启动未提交，已恢复安全候选并保留累计；证据: ${ph_stage}"
                elif dockerPortHoppingTargetStartLockCheck &&
                    dockerPortHoppingTargetStopOwned "${ph_root}" "${ph_initial}" "${ph_runtime}"; then
                    dockerError "跳跃目标启动失败，已停止受管核心并保留累计；证据: ${ph_stage}"
                else
                    dockerError "跳跃目标恢复或停止状态未确认，请检查证据: ${ph_stage}"
                fi
            fi
        fi
    else
        # 绑定沿用实际渲染和安装的版本，后置快照不得刷新为新基线。
        if [[ "${ph_bound}" == bound ]]; then
            dockerPortHoppingTargetStartFilesCheck &&
                ph_binding=$(jq -cn --argjson lock "${ph_lock}" --argjson files "${ph_files}" \
                    --argjson state "${ph_stateFile}" --argjson live "${ph_live}" \
                    '{lock:$lock,files:$files,state:$state,live:$live}') &&
                dockerPortHoppingTargetBindingCheck "${ph_witness}" "${ph_binding}" "${ph_domain}" ||
                ph_status=1
        fi
        [[ "${ph_status}" == 0 && "${ph_signal}" == 0 ]] && dockerPortHoppingTargetStartLockCheck &&
            dockerRemoveManagedTree "${ph_root}" "${ph_stage}" &&
            dockerPortHoppingTargetStartLockCheck && [[ "${ph_signal}" == 0 ]] &&
            { [[ "${ph_bound}" != bound ]] ||
                dockerPortHoppingTargetBindingCheck "${ph_witness}" "${ph_binding}" "${ph_domain}"; } &&
            [[ "${ph_signal}" == 0 ]] || ph_status=1
        if [[ "${ph_status}" == 0 && "${ph_bound}" == bound ]]; then
            ph_witness=$(jq -c --argjson binding "${ph_binding}" \
                '. + {startup_binding:$binding}' <<<"${ph_witness}") || ph_status=1
        elif [[ "${ph_status}" != 0 && "${ph_bound}" == bound ]]; then
            dockerError "启动版本绑定未提交，已启动核心不再次重建，累计不回退；证据目录可能已清理: ${ph_stage}"
        fi
    fi
    trap - INT TERM
    [[ -z "${ph_int}" ]] || eval "${ph_int}"
    [[ -z "${ph_term}" ]] || eval "${ph_term}"
    [[ "${ph_signal}" == 0 ]] || ph_status=${ph_signal}
    [[ "${ph_status}" == 0 ]] || return "${ph_status}"
    dockerPortHoppingTargetStartLockCheck || return 1
    printf '%s\n' "${ph_witness}"
}

dockerPortHoppingTargetPrepareActivation() {
    local ph_owner=${BASHPID:-$$} ph_root ph_lock ph_stage= ph_domain
    local listener=${1:-} start=${2:-} end=${3:-} ipv4=${4:-} ipv6=${5:-}
    local entry current files witness container started status=1 signal=0 intTrap termTrap
    local -a startupArgs=()
    local entryFilter='
      . as $s | [.core.protocols[] | select(.listener_id == $listener)] |
      if $s.schema_version == 3 and $s.core.type == "sing-box" and
        $s.core.secondary_type == null and ($s.core.protocols | length) == 1 and
        ($s.host_integrations | length) == 0 and length == 1 and .[0].id == 3 and
        (.[0].core // $s.core.type) == "sing-box" and
        (.[0].address_families | sort) == ["ipv4","ipv6"] and
        (.[0].public_port | type == "number" and floor == . and . >= 1 and . <= 65535)
      then {port:.[0].public_port,domain:.[0].hy2.domain,port_hopping:$s.port_hopping}
      else error("启用准备仅支持单个受管双族 Hy2 入口") end'
    local fixedFilter='
      map(select(.[0] != "data/traffic/state.json" and .[0] != "config/sing-box/config.json") |
        if .[0] == "data/traffic" then .[3] = 0 else . end)'
    [[ "$#" -eq 5 || ( "$#" -eq 6 && "$6" == bound ) ]] || return 1
    [[ "$#" -eq 5 ]] || startupArgs=(bound)
    [[ "${start}" =~ ^[1-9][0-9]{0,4}$ && "${end}" =~ ^[1-9][0-9]{0,4}$ &&
        "${start}" -le "${end}" && "${end}" -le 65535 ]] || return 1
    ph_lock=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") || {
        DOCKER_DEPLOYMENT_LOCK_DIR=
        return 1
    }
    ph_root=$(dockerInstallRoot) &&
        entry=$(jq -ec --arg listener "${listener}" "${entryFilter}" "${ph_root}/config/spec.json") &&
        jq -e --argjson start "${start}" --argjson end "${end}" '
          .port < $start or .port > $end' <<<"${entry}" >/dev/null &&
        ph_domain=$(jq -er '.domain' <<<"${entry}") || {
            dockerPortHoppingTargetStartLockCheck; return 1
        }
    jq -e --arg listener "${listener}" --argjson start "${start}" --argjson end "${end}" \
        --arg ipv4 "${ipv4}" --arg ipv6 "${ipv6}" '
      .port_hopping == null or .port_hopping ==
        {listener_id:$listener,range_start:$start,range_end:$end,ipv4:$ipv4,ipv6:$ipv6}
    ' <<<"${entry}" >/dev/null &&
        dockerPortHoppingAddressesValidate "${ipv4}" "${ipv6}" ||
        { dockerPortHoppingTargetStartLockCheck; return 1; }
    current=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "") &&
        jq -e '.[] | select(.[0] == "data/traffic") | .[1] != null' <<<"${current}" >/dev/null &&
        files=$(jq -c "${fixedFilter}" <<<"${current}") &&
        [[ "$(jq -ec --arg listener "${listener}" "${entryFilter}" "${ph_root}/config/spec.json")" == \
            "${entry}" ]] && dockerPortHoppingTargetStartLockCheck ||
        { dockerPortHoppingTargetStartLockCheck; return 1; }
    ph_stage=$(mktemp -d "${ph_root}/.hopping-prepare.XXXXXX") ||
        { dockerPortHoppingTargetStartLockCheck; return 1; }
    intTrap=$(trap -p INT)
    termTrap=$(trap -p TERM)
    trap 'signal=130' INT
    trap 'signal=143' TERM
    # 必须直接调用；命令替换会丢失当前持锁 Bash 身份。
    if dockerPortHoppingTargetStartLockCheck && [[ "${signal}" == 0 ]] &&
        dockerPortHoppingTargetStartManaged "${listener}" "${ipv4}" "${ipv6}" "${startupArgs[@]}" \
            >"${ph_stage}/started.json" &&
        [[ "${signal}" == 0 ]] && dockerPortHoppingTargetStartLockCheck &&
        witness=$(jq -ec --arg listener "${listener}" --arg ipv4 "${ipv4}" --arg ipv6 "${ipv6}" \
            --argjson entry "${entry}" '
          if .listener_id == $listener and .target_port == $entry.port and
          .ipv4 == $ipv4 and .ipv6 == $ipv6 and .protocol_id == 3 and .core == "sing-box" and
          (.container_id | test("^[a-f0-9]{64}$")) and
          (.image_id | test("^sha256:[a-f0-9]{64}$")) and .enabled_accounts > 0
          then . else error("启用准备目标代次不匹配") end
        ' "${ph_stage}/started.json") &&
        started=$(jq -er '.started_at' <<<"${witness}") &&
        dockerPortHoppingTargetProjectCheck "${ph_root}" &&
        container=$(docker container inspect "$(jq -er '.container_id' <<<"${witness}")") &&
        jq -e --argjson witness "${witness}" '
          length == 1 and (.[0] |
            .Id == $witness.container_id and .Image == $witness.image_id and
            .State.StartedAt == $witness.started_at and .RestartCount == $witness.restart_count and
            .State.Status == "running" and .State.Running == true and
            .State.Restarting == false and .State.Paused == false and .State.Dead == false and
            .State.Health.Status == "healthy")
        ' <<<"${container}" >/dev/null &&
        current=$(dockerPortHoppingTargetFileSnapshot "${ph_domain}" "${started}") &&
        jq -e '.[] | select(.[0] == "data/traffic") | .[3] == 16832' <<<"${current}" >/dev/null &&
        [[ "$(jq -c "${fixedFilter}" <<<"${current}")" == "${files}" && "${signal}" == 0 ]] &&
        dockerPortHoppingTargetStartLockCheck &&
        { [[ "${#startupArgs[@]}" == 0 ]] ||
            dockerPortHoppingTargetBindingCheck "${witness}" \
                "$(jq -ec '.startup_binding' <<<"${witness}")" "${ph_domain}"; } &&
        jq -c --argjson start "${start}" --argjson end "${end}" '
          . + {range_start:$start,range_end:$end}
        ' <<<"${witness}" >"${ph_stage}/prepared.json" &&
        [[ "${signal}" == 0 ]] && dockerPortHoppingTargetStartLockCheck; then
        witness=$(<"${ph_stage}/prepared.json")
        dockerRemoveManagedTree "${ph_root}" "${ph_stage}" &&
            dockerPortHoppingTargetStartLockCheck && [[ "${signal}" == 0 ]] &&
            { [[ "${#startupArgs[@]}" == 0 ]] ||
                dockerPortHoppingTargetBindingCheck "${witness}" \
                    "$(jq -ec '.startup_binding' <<<"${witness}")" "${ph_domain}"; } &&
            [[ "${signal}" == 0 ]] && status=0
    else status=$?; fi
    trap - INT TERM
    [[ -z "${intTrap}" ]] || eval "${intTrap}"
    [[ -z "${termTrap}" ]] || eval "${termTrap}"
    [[ "${signal}" == 0 ]] || status=${signal}
    if [[ "${status}" != 0 ]]; then
        dockerPortHoppingTargetStartLockCheck || :
        dockerError "跳跃启用准备未提交；累计不回退，证据目录可能已清理: ${ph_stage}"
        return "${status}"
    fi
    # 准备诊断不能作为后续 net 写规则的授权，也不证明端口范围当前空闲。
    printf '%s\n' "${witness}"
}

dockerPortHoppingProbeContainer() {
    local mode=$1 current child
    [[ -f "${ph_stage}/cid" && ! -L "${ph_stage}/cid" ]] || return 1
    child=$(<"${ph_stage}/cid")
    [[ "${child}" =~ ^[a-f0-9]{64}$ ]] || return 1
    current=$(docker container inspect "${child}") &&
        python3 "${ph_helper}" container "${ph_root}" "${child}" "${ph_image}" \
            "${ph_label}" "${ph_start}" "${ph_end}" "${ph_target}" "${ph_ipv4}" "${ph_ipv6}" \
            "${ph_host}" "${mode}" <<<"${current}"
}

dockerPortHoppingProbeCheck() {
    local current
    [[ "${ph_signal}" == 0 ]] &&
        dockerPortHoppingTargetBindingCheck "${ph_witness}" "${ph_binding}" "${ph_domain}" &&
        current=$(python3 "${ph_helper}" directory "${ph_root}") &&
        [[ "${current}" == "${ph_directory}" ]]
}

dockerPortHoppingProbeExchange() {
    local challenge nonce request digest ack current descriptor
    local -a command=(
        docker run --interactive --pull never --cidfile "${ph_stage}/cid"
        --label "io.padm.hopping-probe=${ph_label}" --network host --hostname "${ph_host}" --user 0:0
        --read-only --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges
        --no-healthcheck --restart no --log-driver none
        --tmpfs /tmp:rw,nosuid,nodev,size=16m,mode=1777
        --tmpfs /run:rw,nosuid,nodev,size=16m,mode=0755
        --mount "type=bind,source=${ph_root}/data/net,target=/var/lib/padm/net"
        "${ph_image}" port-hopping-probe "${ph_start}" "${ph_end}" "${ph_target}"
        "${ph_ipv4}" "${ph_ipv6}"
    )
    dockerPortHoppingProbeCheck || return 1
    # coproc 仅承载 Docker；持部署锁的准备函数始终在当前 Bash 直接调用。
    coproc PADM_HOPPING_TRANSPORT {
        exec timeout -k 2 65 "${command[@]}" 2>"${ph_stage}/child.log"
    }
    ph_transport=$!
    descriptor=${PADM_HOPPING_TRANSPORT[0]:-}
    [[ -n "${descriptor}" ]] || return 1
    exec {ph_read}<&"${descriptor}" || return 1
    exec {descriptor}<&-
    descriptor=${PADM_HOPPING_TRANSPORT[1]:-}
    [[ -n "${descriptor}" ]] || return 1
    exec {ph_write}>&"${descriptor}" || return 1
    exec {descriptor}>&-
    challenge=$(python3 "${ph_helper}" frame challenge <&"${ph_read}") &&
        nonce=$(jq -er '.nonce' <<<"${challenge}") &&
        [[ "$(jq -er '.host' <<<"${challenge}")" == "${ph_host}" ]] &&
        ph_projection=$(dockerPortHoppingProbeContainer live) &&
        ph_child=$(jq -er '.Id' <<<"${ph_projection}") &&
        dockerPortHoppingProbeCheck || return 1
    request=$(jq -cn --arg nonce "${nonce}" --argjson pid "${ph_owner}" \
        --arg lock "$(printf '%s' "${ph_lock}" | sha256sum | cut -d ' ' -f1)" \
        --arg startup "$(printf '%s' "${ph_binding}" | sha256sum | cut -d ' ' -f1)" \
        --arg child "${ph_child}" --arg image "${ph_image}" --argjson witness "${ph_witness}" '
      {v:1,nonce:$nonce,parent_pid:$pid,parent_lock_sha256:$lock,startup_sha256:$startup,
       child_id:$child,image_id:$image,target:($witness |
        {container_id,image_id,started_at,restart_count,listener_id,
         range_start,range_end,target_port,ipv4,ipv6})}
    ') &&
        digest=$(printf '%s' "${request}" | sha256sum | cut -d ' ' -f1) &&
        current=$(dockerPortHoppingProbeContainer live) &&
        [[ "${current}" == "${ph_projection}" ]] &&
        dockerPortHoppingProbeCheck &&
        printf '%s\n' "${request}" >&"${ph_write}" || return 1
    exec {ph_write}>&-
    ph_write=
    ack=$(python3 "${ph_helper}" frame ack "${nonce}" "${ph_child}" "${digest}" <&"${ph_read}") ||
        return 1
    exec {ph_read}<&-
    ph_read=
    if wait "${ph_transport}"; then ph_transport=; else ph_transport=; return 1; fi
    current=$(dockerPortHoppingProbeContainer any) &&
        [[ "${current}" == "${ph_projection}" ]] &&
        docker container inspect "${ph_child}" | jq -e 'length == 1 and (.[0].State |
          .Status == "exited" and .Running == false and .ExitCode == 0)' >/dev/null &&
        dockerPortHoppingProbeCheck || return 1
    ph_ack=${ack}
}

dockerPortHoppingProbeCleanup() {
    local current confirmed child status=0
    [[ -z "${ph_write}" ]] || { exec {ph_write}>&-; ph_write=; }
    [[ -z "${ph_read}" ]] || { exec {ph_read}<&-; ph_read=; }
    if [[ -f "${ph_stage}/cid" ]]; then
        if current=$(dockerPortHoppingProbeContainer any) &&
            { [[ -z "${ph_projection}" ]] || [[ "${current}" == "${ph_projection}" ]]; } &&
            confirmed=$(dockerPortHoppingProbeContainer any) &&
            [[ "${current}" == "${confirmed}" ]] &&
            child=$(jq -er '.Id' <<<"${current}"); then
            docker container stop --time 2 "${child}" >/dev/null &&
                confirmed=$(dockerPortHoppingProbeContainer any) &&
                [[ "${current}" == "${confirmed}" ]] &&
                docker container rm "${child}" >/dev/null || status=1
        else status=1; fi
    fi
    if [[ -n "${ph_transport}" ]]; then
        kill -TERM "${ph_transport}" 2>/dev/null || :
        # wait 只回收已保存的 transport；失败不作为只读握手成功。
        wait "${ph_transport}" 2>/dev/null || :
        ph_transport=
    fi
    return "${status}"
}

dockerPortHoppingTargetProbe() {
    local ph_owner=${BASHPID:-$$} ph_root ph_lock ph_stage= ph_domain ph_witness ph_binding
    local ph_start=${2:-} ph_end=${3:-} ph_ipv4=${4:-} ph_ipv6=${5:-} ph_target ph_image
    local ph_helper="${DOCKER_LIB_DIR}/port-hopping-probe.py" ph_directory ph_label ph_child=
    local ph_host= ph_projection= ph_read= ph_write= ph_transport= ph_ack= ph_signal=0
    local status=1 intTrap termTrap image
    [[ "$#" -eq 5 ]] || return 1
    ph_root=$(dockerInstallRoot) &&
        ph_lock=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") || {
            DOCKER_DEPLOYMENT_LOCK_DIR=; return 1;
        }
    ph_stage=$(mktemp -d "${ph_root}/.hopping-probe.XXXXXX") || return 1
    intTrap=$(trap -p INT)
    termTrap=$(trap -p TERM)
    trap 'ph_signal=130' INT
    trap 'ph_signal=143' TERM
    # 结果来自本轮直接调用；不接受保存 JSON、环境变量或旧 tuple 作为授权。
    if dockerPortHoppingTargetStartLockCheck &&
        dockerPortHoppingTargetPrepareActivation "$@" bound >"${ph_stage}/prepared.json" &&
        ph_witness=$(jq -ec '.' "${ph_stage}/prepared.json") &&
        ph_binding=$(jq -ec '.startup_binding' <<<"${ph_witness}") &&
        [[ "$(jq -ec '.lock' <<<"${ph_binding}")" == "${ph_lock}" ]] &&
        ph_domain=$(jq -er --arg listener "$1" '
          .core.protocols[] | select(.listener_id == $listener) | .hy2.domain
        ' "${ph_root}/config/spec.json") &&
        ph_target=$(jq -er '.target_port' <<<"${ph_witness}") &&
        ph_directory=$(python3 "${ph_helper}" directory "${ph_root}") &&
        image=$(jq -er '.images.net' "${ph_root}/config/spec.json") &&
        ph_image=$(docker image inspect "${image}" | jq -er '
          if length == 1 and (.[0].Id | test("^sha256:[a-f0-9]{64}$"))
          then .[0].Id else error("net 镜像身份无效") end') &&
        ph_label=$(python3 -c 'import os; print(os.urandom(32).hex())') &&
        ph_host=$(python3 -c 'import os; print(os.urandom(6).hex())') &&
        dockerPortHoppingProbeExchange; then status=0; else status=$?; fi
    [[ "${status}" != 130 && "${status}" != 143 ]] || ph_signal=${status}
    [[ "${ph_signal}" == 0 ]] || status=${ph_signal}
    trap '' INT TERM
    dockerPortHoppingProbeCleanup || status=1
    if [[ "${status}" == 0 ]]; then
        dockerPortHoppingProbeCheck &&
            dockerRemoveManagedTree "${ph_root}" "${ph_stage}" &&
            dockerPortHoppingProbeCheck || status=1
    fi
    trap - INT TERM
    [[ -z "${intTrap}" ]] || eval "${intTrap}"
    [[ -z "${termTrap}" ]] || eval "${termTrap}"
    [[ "${ph_signal}" == 0 ]] || status=${ph_signal}
    if [[ "${status}" != 0 ]]; then
        dockerPortHoppingTargetStartLockCheck || :
        dockerError "跳跃只读握手未完成；累计不回退，证据目录可能已清理: ${ph_stage}"
        return "${status}"
    fi
    # ACK 仅报告实时只读交接；不写 NAT 或跳跃 state，不授予后续写权限。
    jq -c --argjson ack "${ph_ack}" '. + {probe_ack:$ack}' <<<"${ph_witness}"
}

dockerPortHoppingGuardedContainer() {
    local mode=$1 current child
    [[ -f "${ph_stage}/cid" && ! -L "${ph_stage}/cid" ]] || return 1
    child=$(<"${ph_stage}/cid")
    [[ "${child}" =~ ^[a-f0-9]{64}$ ]] || return 1
    current=$(timeout -k 2 5 docker container inspect "${child}") &&
        python3 "${ph_helper}" "${ph_operation}-container" "${ph_root}" "${child}" "${ph_image}" \
            "${ph_label}" "${ph_start}" "${ph_end}" "${ph_target}" "${ph_ipv4}" "${ph_ipv6}" \
            "${ph_host}" "${mode}" <<<"${current}"
}

dockerPortHoppingGuardedSend() {
    local current
    current=$(dockerPortHoppingGuardedContainer live) &&
        [[ "${current}" == "${ph_projection}" ]] &&
        dockerPortHoppingProbeCheck &&
        [[ "${ph_signal}" == 0 ]] &&
        printf '%s\n' "$1" >&"${ph_write}"
}

dockerPortHoppingSupervisorControl() {
    [[ -n "${ph_control:-}" ]] || return 1
    python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" "$@" <&"${ph_control}"
}

dockerPortHoppingGuardedExchange() {
    local challenge nonce request digest current phase frame action descriptor duration=150 seq=1
    local supervisorPayload supervisorPhase
    local -a nonces=() command=(
        docker run --interactive --sig-proxy=false --pull never --cidfile "${ph_stage}/cid"
        --label "io.padm.hopping-${ph_operation}=${ph_label}" --network host --hostname "${ph_host}" --user 0:0
        --read-only --cap-drop ALL --cap-add NET_ADMIN --security-opt no-new-privileges
        --no-healthcheck --restart no --log-driver none
        --tmpfs /tmp:rw,nosuid,nodev,size=16m,mode=1777
        --tmpfs /run:rw,nosuid,nodev,size=16m,mode=0755
        --mount "type=bind,source=${ph_root}/data/net,target=/var/lib/padm/net"
        "${ph_image}" "port-hopping-${ph_operation}" "${ph_start}" "${ph_end}" "${ph_target}"
        "${ph_ipv4}" "${ph_ipv6}"
    )
    dockerPortHoppingProbeCheck || return 1
    [[ "${ph_operation}" != supervised ]] || duration=0
    # 有限模式限制客户端时长；持续模式按帧续期，关闭输入后由子端自行撤销。
    coproc PADM_HOPPING_TRANSPORT {
        exec timeout -k 2 "${duration}" "${command[@]}" 2>"${ph_stage}/child.log"
    }
    ph_transport=$!
    descriptor=${PADM_HOPPING_TRANSPORT[0]:-}
    [[ -n "${descriptor}" ]] || return 1
    exec {ph_read}<&"${descriptor}" || return 1
    exec {descriptor}<&-
    descriptor=${PADM_HOPPING_TRANSPORT[1]:-}
    [[ -n "${descriptor}" ]] || return 1
    exec {ph_write}>&"${descriptor}" || return 1
    exec {descriptor}>&-
    challenge=$(python3 "${ph_helper}" frame challenge <&"${ph_read}") &&
        nonce=$(jq -er '.nonce' <<<"${challenge}") &&
        [[ "$(jq -er '.host' <<<"${challenge}")" == "${ph_host}" ]] &&
        ph_projection=$(dockerPortHoppingGuardedContainer live) &&
        ph_child=$(jq -er '.Id' <<<"${ph_projection}") || return 1
    request=$(jq -cn --arg nonce "${nonce}" --argjson pid "${ph_owner}" \
        --arg lock "$(printf '%s' "${ph_lock}" | sha256sum | cut -d ' ' -f1)" \
        --arg startup "$(printf '%s' "${ph_binding}" | sha256sum | cut -d ' ' -f1)" \
        --arg child "${ph_child}" --arg image "${ph_image}" --argjson witness "${ph_witness}" '
      {v:1,nonce:$nonce,parent_pid:$pid,parent_lock_sha256:$lock,startup_sha256:$startup,
       child_id:$child,image_id:$image,target:($witness |
        {container_id,image_id,started_at,restart_count,listener_id,
         range_start,range_end,target_port,ipv4,ipv6})}
    ') &&
        digest=$(printf '%s' "${request}" | sha256sum | cut -d ' ' -f1) &&
        dockerPortHoppingGuardedSend "${request}" || return 1
    nonces=("${nonce}")
    for phase in ready written active; do
        frame=$(python3 "${ph_helper}" guarded-frame "${phase}" "${ph_child}" "${digest}" \
            "${nonces[@]}" <&"${ph_read}") &&
            nonce=$(jq -er '.nonce' <<<"${frame}") || return 1
        nonces+=("${nonce}")
        case "${phase}" in ready) action=write ;; written) action=finalize ;; active) action=close ;; esac
        [[ "${phase}" != active || "${ph_operation}" != supervised ]] || action=continue
        frame=$(jq -c --arg action "${action}" '.phase=$action' <<<"${frame}") &&
            dockerPortHoppingGuardedSend "${frame}" || return 1
    done
    if [[ "${ph_operation}" == supervised ]]; then
        while true; do
            frame=$(python3 "${ph_helper}" supervised-frame running "${ph_child}" "${digest}" \
                "${nonce}" "${seq}" <&"${ph_read}") &&
                nonce=$(jq -er '.nonce' <<<"${frame}") || return 1
            # 固定初始 nonce 与上一轮即可防止当前帧重放，不累计会话历史。
            for current in "${nonces[@]}"; do [[ "${nonce}" != "${current}" ]] || return 1; done
            if [[ -n "${ph_control:-}" && "${seq}" -ge 2 ]]; then
                current=$(dockerPortHoppingGuardedContainer live) &&
                    [[ "${current}" == "${ph_projection}" ]] &&
                    dockerPortHoppingProbeCheck &&
                    supervisorPayload=$(jq -cn --argjson target "${ph_witness}" \
                        --argjson running "${frame}" --argjson child "${ph_projection}" \
                        --argjson directory "${ph_directory}" --arg stage "${ph_stage}" \
                        '{target:$target,running:$running,child:$child,directory:$directory,stage:$stage}') ||
                    return 1
                supervisorPhase=running
                [[ "${seq}" != 2 ]] || supervisorPhase=ready
                dockerPortHoppingSupervisorControl gate "${supervisorPhase}" "${supervisorPayload}" ||
                    return 1
            fi
            action=$(jq -c '.phase="continue"' <<<"${frame}") &&
                dockerPortHoppingGuardedSend "${action}" || return 1
            if [[ -n "${ph_control:-}" && "${seq}" == 2 ]]; then
                # 第二轮已发送仍须复验原绑定；ready 和 started 使用同一份正文。
                current=$(dockerPortHoppingGuardedContainer live) &&
                    [[ "${current}" == "${ph_projection}" ]] &&
                    dockerPortHoppingProbeCheck &&
                    dockerPortHoppingSupervisorControl gate started "${supervisorPayload}" || return 1
            fi
            jq -cn --argjson target "${ph_witness}" --argjson running "${frame}" \
                    '{target:$target,running:$running}' >"${ph_stage}/supervised.next" &&
                chmod 0600 "${ph_stage}/supervised.next" &&
                mv -f -- "${ph_stage}/supervised.next" "${ph_stage}/supervised.json" || return 1
            seq=$((seq + 1))
        done
    fi
    exec {ph_write}>&-
    ph_write=
    ph_closed=$(python3 "${ph_helper}" guarded-frame closed "${ph_child}" "${digest}" \
        "${nonce}" <&"${ph_read}") || return 1
    exec {ph_read}<&-
    ph_read=
    if wait "${ph_transport}"; then ph_transport=; else return 1; fi
    current=$(dockerPortHoppingGuardedContainer any) &&
        [[ "${current}" == "${ph_projection}" ]] &&
        timeout -k 2 5 docker container inspect "${ph_child}" | jq -e '
          length == 1 and (.[0].State |
            .Status == "exited" and .Running == false and .ExitCode == 0)' >/dev/null &&
        dockerPortHoppingProbeCheck
}

dockerPortHoppingGuardedCleanup() {
    local current confirmed child state deadline status=0
    [[ -z "${ph_write}" ]] || { exec {ph_write}>&-; ph_write=; }
    # 持续子端可能正在发下一挑战；保留输出读端直到其按输入 EOF 撤销。
    [[ "${ph_operation}" == supervised || -z "${ph_read}" ]] ||
        { exec {ph_read}<&-; ph_read=; }
    if [[ -e "${ph_stage}/cid" || -L "${ph_stage}/cid" ]]; then
        deadline=$(($(date +%s) + 25))
        while true; do
            if ! current=$(dockerPortHoppingGuardedContainer any) ||
                { [[ -n "${ph_projection}" ]] && [[ "${current}" != "${ph_projection}" ]]; } ||
                ! child=$(jq -er '.Id' <<<"${current}") ||
                ! state=$(timeout -k 2 5 docker container inspect "${child}"); then
                status=1; break
            fi
            if jq -e 'length == 1 and (.[0].State |
                .Status == "exited" and .Running == false)' <<<"${state}" >/dev/null; then
                # 非零退出不能证明 finally 完成撤销，连同容器保留恢复证据。
                jq -e '.[0].State.ExitCode == 0' <<<"${state}" >/dev/null ||
                    { status=1; break; }
                confirmed=$(dockerPortHoppingGuardedContainer any) &&
                    [[ "${confirmed}" == "${current}" ]] &&
                    state=$(timeout -k 2 5 docker container inspect "${child}") &&
                    jq -e 'length == 1 and (.[0].State |
                      .Status == "exited" and .Running == false and .ExitCode == 0)' <<<"${state}" >/dev/null &&
                    timeout -k 2 10 docker container rm "${child}" >/dev/null || status=1
                break
            fi
            [[ "$(date +%s)" -lt "${deadline}" ]] || { status=1; break; }
            sleep 0.1
        done
    elif [[ -n "${ph_transport}" ]]; then
        # cidfile 尚未形成时不能证明没有启动子端，保留本轮证据。
        status=1
    fi
    [[ -z "${ph_read}" ]] || { exec {ph_read}<&-; ph_read=; }
    if [[ -n "${ph_transport}" ]]; then
        # 中断 wait 后仍保留本 Bash 作业；已退出的数字 PID 不能再发信号。
        if jobs -pr | grep -Fxq -- "${ph_transport}"; then
            kill -TERM "${ph_transport}" 2>/dev/null || :
        fi
        while ! wait "${ph_transport}" 2>/dev/null; do
            jobs -pr | grep -Fxq -- "${ph_transport}" || break
        done
        ph_transport=
    fi
    return "${status}"
}

dockerPortHoppingTargetGuarded() {
    local ph_control=
    dockerPortHoppingTargetTransaction guarded "$@"
}

dockerPortHoppingTargetSupervised() {
    local ph_control=
    dockerPortHoppingTargetTransaction supervised "$@"
}

dockerPortHoppingSupervisorStart() {
    local root
    [[ "$#" -eq 0 || "$#" -eq 5 ]] || return 1
    root=$(dockerInstallRoot) &&
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" start "${root}" \
            "${DOCKER_BUNDLE_SOURCE_ROOT}/install-docker.sh" "$@"
}

dockerPortHoppingSupervisorStatus() {
    local root
    [[ "$#" -eq 0 ]] || return 1
    root=$(dockerInstallRoot) &&
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" status "${root}"
}

dockerPortHoppingSupervisorStop() {
    local root
    [[ "$#" -eq 0 ]] || return 1
    root=$(dockerInstallRoot) &&
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" stop "${root}"
}

dockerPortHoppingSavedArguments() {
    local root spec expected
    root=$(dockerInstallRoot) || return 1
    spec="${root}/config/spec.json"
    dockerTrafficSafePath "${root}" "${spec}" &&
        [[ -f "${spec}" && -O "${spec}" ]] &&
        dockerPrivateFileIsRestricted "${spec}" &&
        dockerManagedSpecMatchesDeployment "${spec}" "${root}/deployment.json" "${root}/images.env" &&
        expected=$(dockerGenerateCompose "${spec}" /dev/stdout "${root}") &&
        jq -es --argjson expected "${expected}" 'length == 1 and .[0] == $expected' \
            "${root}/compose.json" >/dev/null &&
        jq -ec 'select(.port_hopping != null) | .port_hopping |
          [.listener_id, (.range_start|tostring), (.range_end|tostring), .ipv4, .ipv6]' "${spec}"
}

dockerPortHoppingCommand() {
    local action=${1:-status} root result saved spec uri
    [[ "$#" -le 1 ]] || return "${PADM_DOCKER_RC_USAGE}"
    case "${action}" in status|start|stop|share) ;; *) return "${PADM_DOCKER_RC_USAGE}" ;; esac
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    case "${action}" in
    start)
        dockerPortHoppingSavedArguments >/dev/null || {
            dockerError '缺少有效的受管端口跳跃配置，请先保存单个双族 Hy2 配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
        result=$(dockerPortHoppingSupervisorStart) || return $?
        printf '端口跳跃已启用。\n'
        ;;
    stop)
        result=$(dockerPortHoppingSupervisorStop) || return $?
        printf '端口跳跃已停止；保存配置保留。\n'
        ;;
    status)
        if [[ ! -e "${root}/data/net/.hopping-supervisor" &&
            ! -L "${root}/data/net/.hopping-supervisor" ]]; then
            dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
                dockerManagedSpecMatchesDeployment "${root}/config/spec.json" \
                    "${root}/deployment.json" "${root}/images.env" &&
                result=$(jq -c '{state:"stopped",saved:(.port_hopping // null)}' \
                    "${root}/config/spec.json") || return "${PADM_DOCKER_RC_STATE}"
            if [[ ! -e "${root}/data/net/.hopping-supervisor" &&
                ! -L "${root}/data/net/.hopping-supervisor" ]]; then
                [[ ! -e "${root}/data/net/port-hopping.state" &&
                    ! -L "${root}/data/net/port-hopping.state" ]] || {
                    dockerError '存在未经停止核验的跳跃规则状态，请保留证据排查'
                    return "${PADM_DOCKER_RC_STATE}"
                }
                printf '%s\n' "${result}"
                return 0
            fi
        fi
        result=$(dockerPortHoppingSupervisorStatus) || return $?
        jq -c '.payload.target | {state:"active",saved:{
          listener_id,range_start,range_end,ipv4,ipv6}}' <<<"${result}"
        ;;
    share)
        saved=$(dockerPortHoppingSavedArguments) || {
            dockerError '缺少有效的受管端口跳跃配置'
            return "${PADM_DOCKER_RC_STATE}"
        }
        result=$(dockerPortHoppingSupervisorStatus) || return $?
        spec="${root}/config/spec.json"
        result=$(jq -ec --argjson saved "${saved}" --argjson status "${result}" '
          $status.payload.target as $target |
          select([$target.listener_id, ($target.range_start|tostring),
            ($target.range_end|tostring), $target.ipv4, $target.ipv6] == $saved) |
          .port_hopping as $h |
          [.core.protocols[] | select(.id == 3 and .listener_id == $h.listener_id)] as $entries |
          select(($entries | length) == 1 and
            $entries[0].public_port == $target.target_port) |
          {core:{protocols:[($entries[0] |
            .public_port = "\($h.range_start)-\($h.range_end)")]},
           subscription:{enabled:true}}
        ' "${spec}") || {
            dockerError '活动跳跃范围与当前受管 Hy2 配置不一致，拒绝生成分享链接'
            return "${PADM_DOCKER_RC_STATE}"
        }
        uri=$(
            spec=$(mktemp "${TMPDIR:-/tmp}/padm-hopping-share.XXXXXX") || exit 1
            trap 'rm -f -- "${spec}"' EXIT
            printf '%s\n' "${result}" >"${spec}" &&
                dockerGenerateSubscription "${spec}" /dev/stdout
        ) &&
            [[ -n "${uri}" ]] || {
            dockerError '活动跳跃分享链接生成失败'
            return "${PADM_DOCKER_RC_STATE}"
        }
        printf '%s\n' "${uri}"
        ;;
    esac
}

dockerPortHoppingSupervisorStopIfActive() {
    local root
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/data/net/.hopping-supervisor" ||
        -L "${root}/data/net/.hopping-supervisor" ]]; then
        dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
        dockerPortHoppingSupervisorStop >/dev/null || {
            dockerError '跳跃监督会话未能通过原控制通道停止，已拒绝生命周期操作'
            return "${PADM_DOCKER_RC_LOCK}"
        }
        dockerPortHoppingSessionAbsent "${root}" || return "${PADM_DOCKER_RC_LOCK}"
    fi
    return 0
}

dockerPortHoppingTargetSupervisedOwned() {
    local ph_control=${1:-} owner=${BASHPID:-$$} original= current root status=1
    local released=false ownerSignal=0 intTrap termTrap pipeTrap payload ph_restart=false
    local ph_change= changeStatus=0
    local DOCKER_DEPLOYMENT_LOCK_DIR=
    [[ "$#" -ge 6 &&
        "${ph_control}" =~ ^[1-9][0-9]*$ && "${ph_control}" -ge 3 ]] || return 1
    shift
    local -a targets=("${@:1:5}") changeArguments=("${@:7}")
    case "${6:-}" in
    '') [[ "$#" -eq 5 ]] || return 1 ;;
    --restart) [[ "$#" -eq 6 ]] || return 1; ph_restart=true; ph_change=restart ;;
    --update) ph_change=update ;;
    --rollback) [[ "$#" -eq 6 ]] || return 1; ph_change=rollback ;;
    *) return 1 ;;
    esac
    python3 -B -c 'import fcntl,os,stat
if not stat.S_ISSOCK(os.fstat(0).st_mode) or fcntl.fcntl(0,fcntl.F_GETFL)&os.O_ACCMODE != os.O_RDWR:
    raise SystemExit("监督控制 fd 必须是双向 socket")' \
        <&"${ph_control}" || return 1
    intTrap=$(trap -p INT)
    termTrap=$(trap -p TERM)
    pipeTrap=$(trap -p PIPE)
    trap 'ownerSignal=130' INT
    trap 'ownerSignal=143' TERM
    trap '' PIPE
    # 不接收调用方的锁；完整原快照形成前失败时保留目录，不只按 pid 删除。
    # 专用参数只避开自身会话占用检查；控制 fd、原锁及 freshly bound 仍独立核验。
    if root=$(dockerInstallRoot) && dockerAcquireDeploymentLock --hopping-owner; then
        if original=$(dockerPortHoppingTargetLockSnapshot "${owner}"); then
            if [[ "${ownerSignal}" == 0 ]]; then
                if { [[ -z "${ph_change}" ]] ||
                    { payload=$(jq -cn --argjson pid "${owner}" --argjson lock "${original}" \
                        '{bash_pid:$pid,lock:$lock}') &&
                      dockerPortHoppingSupervisorControl gate "${ph_change}" "${payload}"; }; }; then
                    if [[ "${ownerSignal}" == 0 && ( "${ph_change}" == update || "${ph_change}" == rollback ) ]]; then
                        # 事务失败仍由原实现恢复；重新绑定当前业务后保留原失败状态。
                        trap 'dockerCommandInterrupted 130' INT
                        trap 'dockerCommandInterrupted 143' TERM
                        if [[ "${ph_change}" == update ]]; then
                            dockerUpdateCommand "${changeArguments[@]}" >&2 || changeStatus=$?
                        else
                            dockerRollbackCommand >&2 || changeStatus=$?
                        fi
                        trap 'ownerSignal=130' INT
                        trap 'ownerSignal=143' TERM
                        dockerCleanupBundleLinkTemp &&
                            dockerCleanupStagedBundle && dockerManifestCleanup &&
                            dockerEntryCleanup || ownerSignal=1
                        [[ "${DOCKER_CONFIG_SWITCHED:-0}" == 0 ]] || ownerSignal=1
                        current=$(dockerPortHoppingTargetLockSnapshot "${owner}") &&
                            [[ "${current}" == "${original}" && "${ownerSignal}" == 0 ]] &&
                            payload=$(jq -cn --argjson status "${changeStatus}" '{status:$status}') &&
                            dockerPortHoppingSupervisorControl gate changed "${payload}" || ownerSignal=1
                    fi
                    if [[ "${ownerSignal}" == 0 ]]; then
                        if dockerPortHoppingTargetTransaction supervised "${targets[@]}"; then
                            status=0
                        else
                            status=$?
                        fi
                    else
                        status=${ownerSignal}
                    fi
                fi
            fi
        fi
    else
        status=${PADM_DOCKER_RC_LOCK:-12}
    fi
    [[ "${ownerSignal}" == 0 ]] || status=${ownerSignal}
    if [[ -n "${original}" ]] &&
        current=$(dockerPortHoppingTargetLockSnapshot "${owner}") && [[ "${current}" == "${original}" ]]; then
        if dockerReleaseDeploymentLock &&
            [[ ! -e "${root}/locks/deployment.lock" && ! -L "${root}/locks/deployment.lock" ]]; then
            released=true
        fi
    else
        DOCKER_DEPLOYMENT_LOCK_DIR=
    fi
    [[ "${ownerSignal}" == 0 ]] || status=${ownerSignal}
    payload=$(jq -cn --argjson status "${status}" --argjson released "${released}" \
        '{status:$status,lock_released:$released}') &&
        dockerPortHoppingSupervisorControl notify finished "${payload}" || :
    trap - INT TERM PIPE
    [[ -z "${intTrap}" ]] || eval "${intTrap}"
    [[ -z "${termTrap}" ]] || eval "${termTrap}"
    [[ -z "${pipeTrap}" ]] || eval "${pipeTrap}"
    [[ "${ownerSignal}" == 0 ]] || status=${ownerSignal}
    return "${status}"
}

dockerPortHoppingTargetTransaction() {
    local ph_operation=${1:-}
    shift || return 1
    local ph_owner=${BASHPID:-$$} ph_root ph_lock ph_stage= ph_domain ph_witness ph_binding
    local ph_start=${2:-} ph_end=${3:-} ph_ipv4=${4:-} ph_ipv6=${5:-} ph_target ph_image
    local ph_helper="${DOCKER_LIB_DIR}/port-hopping-probe.py" ph_directory ph_label ph_child=
    local ph_host= ph_projection= ph_read= ph_write= ph_transport= ph_closed= ph_signal=0
    local status=1 intTrap termTrap pipeTrap image ph_guarded=true cleanupStatus=0 savedSignal payload
    local ph_control=${ph_control:-}
    local ph_restart=${ph_restart:-false}
    if [[ "${FUNCNAME[1]:-}" != dockerPortHoppingTargetSupervisedOwned ]]; then
        ph_control=; ph_restart=false
    fi
    [[ "$#" -eq 5 && ( "${ph_operation}" == guarded || "${ph_operation}" == supervised ) ]] || return 1
    [[ -z "${ph_control}" || "${ownerSignal:-0}" == 0 ]] || return "${ownerSignal}"
    ph_root=$(dockerInstallRoot) &&
        ph_lock=$(dockerPortHoppingTargetLockSnapshot "${ph_owner}") || {
            DOCKER_DEPLOYMENT_LOCK_DIR=; return 1;
        }
    ph_stage=$(mktemp -d "${ph_root}/.hopping-guarded.XXXXXX") || return 1
    intTrap=$(trap -p INT)
    termTrap=$(trap -p TERM)
    pipeTrap=$(trap -p PIPE)
    trap 'ph_signal=130' INT
    trap 'ph_signal=143' TERM
    # EPIPE 必须返回失败并进入撤销，不能让 SIGPIPE 直接终止持锁父端。
    trap '' PIPE
    [[ -z "${ph_control}" || "${ownerSignal:-0}" == 0 ]] || ph_signal=${ownerSignal}
    # 每道写门只用当前持锁 Bash 的新准备结果，原绑定全程不能刷新。
    if [[ "${ph_signal}" == 0 ]] && dockerPortHoppingTargetStartLockCheck &&
        dockerPortHoppingTargetPrepareActivation "$@" bound >"${ph_stage}/prepared.json" &&
        ph_witness=$(jq -ec '.' "${ph_stage}/prepared.json") &&
        ph_binding=$(jq -ec '.startup_binding' <<<"${ph_witness}") &&
        [[ "$(jq -ec '.lock' <<<"${ph_binding}")" == "${ph_lock}" ]] &&
        ph_domain=$(jq -er --arg listener "$1" '
          .core.protocols[] | select(.listener_id == $listener) | .hy2.domain
        ' "${ph_root}/config/spec.json") &&
        ph_target=$(jq -er '.target_port' <<<"${ph_witness}") &&
        ph_directory=$(python3 "${ph_helper}" directory "${ph_root}") &&
        image=$(jq -er '.images.net' "${ph_root}/config/spec.json") &&
        ph_image=$(timeout -k 2 5 docker image inspect "${image}" | jq -er '
          if length == 1 and (.[0].Id | test("^sha256:[a-f0-9]{64}$"))
          then .[0].Id else error("net 镜像身份无效") end') &&
        ph_label=$(python3 -c 'import os; print(os.urandom(32).hex())') &&
        ph_host=$(python3 -c 'import os; print(os.urandom(6).hex())') &&
        dockerPortHoppingGuardedExchange; then status=0; else status=$?; fi
    [[ "${status}" != 130 && "${status}" != 143 ]] || ph_signal=${status}
    [[ "${ph_signal}" == 0 ]] || status=${ph_signal}
    if dockerPortHoppingGuardedCleanup; then cleanupStatus=0; else cleanupStatus=$?; status=1; fi
    if [[ -n "${ph_control}" && "${cleanupStatus}" == 0 && "${ph_signal}" == 143 &&
        -n "${ph_child}" && -n "${ph_projection}" ]]; then
        savedSignal=${ph_signal}
        ph_signal=0
        # 仅独立监督的正常 TERM 可确认净撤销；漂移或未知退出保留原证据。
        if dockerPortHoppingProbeCheck &&
            [[ ! -e "${ph_root}/data/net/port-hopping.state" &&
                ! -L "${ph_root}/data/net/port-hopping.state" ]] &&
            dockerRemoveManagedTree "${ph_root}" "${ph_stage}" &&
            dockerPortHoppingProbeCheck &&
            [[ ! -e "${ph_root}/data/net/port-hopping.state" &&
                ! -L "${ph_root}/data/net/port-hopping.state" && "${ph_signal}" == 0 ]] &&
            payload=$(jq -cn --argjson target "${ph_witness}" --arg child "${ph_child}" \
                --arg stage "${ph_stage}" '{target:$target,child_id:$child,stage:$stage}'); then
            if dockerPortHoppingSupervisorControl notify cleaned "${payload}"; then
                status=${savedSignal}
            else
                status=1
            fi
        else status=1; fi
        [[ "${ph_signal}" != 0 ]] || ph_signal=${savedSignal}
    fi
    if [[ "${status}" == 0 ]]; then
        dockerPortHoppingProbeCheck &&
            dockerRemoveManagedTree "${ph_root}" "${ph_stage}" &&
            dockerPortHoppingProbeCheck || status=1
    fi
    trap - INT TERM PIPE
    [[ -z "${intTrap}" ]] || eval "${intTrap}"
    [[ -z "${termTrap}" ]] || eval "${termTrap}"
    [[ -z "${pipeTrap}" ]] || eval "${pipeTrap}"
    [[ "${ph_signal}" == 0 ]] || status=${ph_signal}
    if [[ "${status}" != 0 ]]; then
        dockerPortHoppingTargetStartLockCheck || :
        dockerError "跳跃写事务未完成；规则撤销未确证时保留证据与容器: ${ph_stage}"
        return "${status}"
    fi
    jq -c --argjson closed "${ph_closed}" '. + {guarded_closed:$closed}' <<<"${ph_witness}"
}

dockerComposeExecute() {
    local composeFile composeDir root profile
    local -a commandArgs=() extraArgs=()
    composeFile=$(dockerComposeFile) || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    case "${1:-}" in
    up|restart) dockerControlRecoveryCheck current || return "${PADM_DOCKER_RC_STATE}" ;;
    esac
    case "${1:-}" in
    up|restart|run|exec)
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    case "${1:-}" in
    up|down|restart|run|exec)
        if jq -e '.networks.ipv6 != null' "${composeFile}" >/dev/null; then
            dockerIPv6NetworkManage check || return "${PADM_DOCKER_RC_COMPOSE}"
        fi
        ;;
    esac
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" ]] || {
        dockerError 'images.env 缺失或不安全'
        return "${PADM_DOCKER_RC_STATE}"
    }
    composeDir=$(dirname -- "${composeFile}")
    # 已验证的镜像和挂载根只从受管 env-file 读取，不接受宿主导出变量覆盖。
    commandArgs=(env -u PADM_DOCKER_ROOT -u PADM_NET_ROOT \
        -u PADM_XRAY_IMAGE -u PADM_SINGBOX_IMAGE -u PADM_NGINX_IMAGE \
        -u PADM_OPS_IMAGE -u PADM_NET_IMAGE docker compose --project-name "${PADM_DOCKER_PROJECT}"
        --project-directory "${composeDir}" --env-file "${root}/images.env"
        --file "${composeFile}")
    while IFS= read -r profile; do
        [[ -n "${profile}" ]] || continue
        commandArgs+=(--profile "${profile}")
    done < <(jq -r '.compose.profiles[]' "${root}/deployment.json")
    case "${1:-}" in
    up|down) extraArgs+=(--remove-orphans) ;;
    logs)
        # 日志只读且可能持续跟随，不能长期阻塞管理命令或流量采集。
        dockerReleaseDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
        ;;
    esac
    # 管理动作不接收交互输入，避免 Compose 吞掉调用方循环中的下一项。
    if [[ -n "${DOCKER_COMPOSE_TIMEOUT:-}" ]]; then
        [[ "${DOCKER_COMPOSE_TIMEOUT}" =~ ^[1-9][0-9]?$ &&
            "${DOCKER_COMPOSE_TIMEOUT}" -le 30 ]] || {
            dockerError 'Docker Compose 操作超时参数无效'
            return "${PADM_DOCKER_RC_USAGE}"
        }
        commandArgs=(timeout --foreground -k 2 "${DOCKER_COMPOSE_TIMEOUT}" "${commandArgs[@]}")
    fi
    "${commandArgs[@]}" "$@" "${extraArgs[@]}" </dev/null || {
        dockerError 'Docker Compose 操作失败'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    if [[ "${1:-}" == down ]] && jq -e '.networks.ipv6 != null' "${composeFile}" >/dev/null; then
        dockerIPv6NetworkManage cleanup || return "${PADM_DOCKER_RC_COMPOSE}"
    fi
}

dockerLockInstalledDeployment() {
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${FUNCNAME[2]:-}" == dockerPortHoppingTargetSupervisedOwned &&
        ( "${FUNCNAME[1]:-}" == dockerUpdateCommand && "${ph_change:-}" == update ||
          "${FUNCNAME[1]:-}" == dockerRollbackCommand && "${ph_change:-}" == rollback ) ]]; then
        # 仅原监督 owner 的直接调用复用本 Bash 的锁，环境标记不能绕开普通取锁。
        [[ "$(dockerPortHoppingTargetLockSnapshot "${owner}")" == "${original}" ]] ||
            return "${PADM_DOCKER_RC_LOCK}"
        return 0
    fi
    dockerAcquireDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
}

dockerPortHoppingSupervisorChangeBundleCheck() {
    local bundlePath=$1 spec=${2:-}
    [[ "${FUNCNAME[2]:-}" == dockerPortHoppingTargetSupervisedOwned ]] || return 0
    # shortcut: 活动会话仅跨相同监督实现升级，协议版本协商接入后再放宽。
    cmp -s -- "${DOCKER_LIB_DIR}/lifecycle.sh" "${bundlePath}/docker/lib/lifecycle.sh" &&
        cmp -s -- "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" \
            "${bundlePath}/docker/lib/port-hopping-supervisor.py" || {
        dockerError '目标控制 bundle 与当前跳跃监督实现不兼容，未切换部署'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    [[ -z "${spec}" ]] || jq -e --arg listener "${targets[0]}" \
        --slurpfile current "$(dockerInstallRoot)/config/spec.json" '
      .schema_version == 3 and .core.type == "sing-box" and .core.secondary_type == null and
      (.core.protocols | length) == 1 and
      .host_integrations == [] and
      .port_hopping == $current[0].port_hopping and
      ([.core.protocols[] | select(.listener_id == $listener and .id == 3)] | length) == 1 and
      ([.core.protocols[] | select(.listener_id == $listener) |
        {public_port,address_families,domain:.hy2.domain}] ==
       [$current[0].core.protocols[] | select(.listener_id == $listener) |
        {public_port,address_families,domain:.hy2.domain}])
    ' "${spec}" >/dev/null
}

dockerPortHoppingSupervisorChangeCheck() {
    [[ "${FUNCNAME[2]:-}" == dockerPortHoppingTargetSupervisedOwned ]] || return 0
    [[ "${ownerSignal}" == 0 &&
        "$(dockerPortHoppingTargetLockSnapshot "${owner}")" == "${original}" ]]
}

dockerStatusCommand() {
    local state bundlePath ref root siteMode=unknown result
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${state}" == "absent" ]]; then
        printf 'state=absent\n'
        return 0
    fi
    [[ "${state}" != "ambiguous" ]] || {
        dockerError 'state=ambiguous'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/data/net/.hopping-supervisor" ||
        -L "${root}/data/net/.hopping-supervisor" ]]; then
        dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
        result=$(dockerPortHoppingSupervisorStatus) || return $?
        jq -er '.payload.target | "state=installed\nconfigured=yes\nport_hopping=active\nlistener=\(.listener_id)\nrange=\(.range_start)-\(.range_end)"' <<<"${result}"
        return $?
    fi
    dockerLockInstalledDeployment || return $?
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
    ref=$(<"${bundlePath}/${PADM_DOCKER_BUNDLE_REF}")
    printf 'state=%s\nbundle_ref=%s\n' "${state}" "${ref}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if ! dockerComposeFile >/dev/null; then
        printf 'configured=no\n'
        return 0
    fi
    printf 'configured=yes\nrelease=%s\nprofiles=%s\n' \
        "$(jq -r '.padm_version' "${root}/deployment.json")" \
        "$(jq -r '.compose.profiles | join(",")' "${root}/deployment.json")"
    if dockerTrafficSafePath "${root}" "${root}/config/spec.json" &&
        dockerConfigureSpecValidate "${root}/config/spec.json" >/dev/null 2>&1; then
        siteMode=$(jq -r '.site.mode // "legacy"' "${root}/config/spec.json") || return "${PADM_DOCKER_RC_STATE}"
    fi
    printf 'site_mode=%s\n' "${siteMode}"
    dockerComposeRun ps
}

dockerLifecycleCommand() {
    local operation=$1 root
    # 来源输入仅在本次调用栈共享，不留跨事务的成功标记。
    # shellcheck disable=SC2034
    local DOCKER_FAIL2BAN_SOURCE_IPV4='' DOCKER_FAIL2BAN_SOURCE_IPV6=''
    shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${operation}" == restart &&
        ( -e "${root}/data/net/.hopping-supervisor" || -L "${root}/data/net/.hopping-supervisor" ) ]]; then
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" restart "${root}" || {
            dockerError '跳跃监督重启未确认；已保留会话证据，拒绝普通重启'
            return "${PADM_DOCKER_RC_LOCK}"
        }
        return 0
    fi
    if [[ "${operation}" == down ]]; then
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerPortHoppingSupervisorStopIfActive || return $?
    fi
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    case "${operation}" in
    up|restart)
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        dockerControlSyncScheduleSpecCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        dockerFail2banSourceInputsPrepare "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    case "${operation}" in
    up)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficScheduleInstall && dockerRenewalScheduleInstall &&
            dockerGeoScheduleInstall && dockerControlLogScheduleInstall &&
            dockerControlSyncScheduleInstall && dockerComposeRun up -d
        ;;
    down)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
        dockerControlLogScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
        dockerControlSyncScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
        dockerTrafficBeforeChange
        dockerComposeRun down && dockerTrafficScheduleRemove
        ;;
    restart)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficBeforeChange
        dockerLifecycleRestart
        ;;
    logs) dockerComposeRun logs "$@" ;;
    esac
}

dockerLifecycleRestart() {
    local root
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerControlSyncScheduleSpecCheck "${root}/config/spec.json" &&
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" &&
        dockerFail2banSourceInputsPrepare "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
    dockerTrafficScheduleInstall && dockerRenewalScheduleInstall &&
        dockerGeoScheduleInstall && dockerControlLogScheduleInstall &&
        dockerControlSyncScheduleInstall && dockerComposeRun restart
}

dockerPullManifestImages() {
    local name reference
    for name in "${PADM_DOCKER_MANIFEST_IMAGE_NAMES[@]}"; do
        reference=$(dockerManifestImageReference "${name}") || return 1
        docker pull "${reference}" || {
            dockerError "镜像拉取失败: ${reference}"
            return 1
        }
    done
}

dockerReleaseCommand() {
    local manifest= bundle= controlBundle=
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" ||
        return "${PADM_DOCKER_RC_MANIFEST}"
    # 仅校验候选控制脚本，不切换当前 bundle；标准输出只保留可信 JSON。
    dockerStageReleaseBundle >&2 || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages >&2 || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerManifestConfigurationInputs || return "${PADM_DOCKER_RC_MANIFEST}"
}

dockerAssessCleanup() {
    local project=${DOCKER_ASSESS_PROJECT:-} candidate=${DOCKER_ASSESS_CANDIDATE:-} ids id failed=0
    [[ -n "${project}" ]] || return 0
    [[ "${project}" =~ ^padm-docker-assess-[a-z0-9]{6}$ && -n "${candidate}" ]] || return 1
    # 只移除本次随机评估项目的 oneoff，不按生产 project 清理。
    ids=$(docker ps -aq --filter "label=com.docker.compose.project=${project}" \
        --filter "label=com.docker.compose.project.working_dir=${candidate}" \
        --filter label=com.docker.compose.oneoff=True) || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
        docker rm -f "${id}" >/dev/null || failed=1
    done <<<"${ids}"
    ids=$(docker network ls -q --filter "label=com.docker.compose.project=${project}" \
        --filter label=com.docker.compose.network=default) || return 1
    while IFS= read -r id; do
        [[ -n "${id}" ]] || continue
        [[ "${id}" =~ ^[a-f0-9]{12,64}$ ]] || return 1
        docker network rm "${id}" >/dev/null || failed=1
    done <<<"${ids}"
    if [[ -f "${candidate}/compose.json" && ! -L "${candidate}/compose.json" ]] &&
        jq -e '.networks.ipv6 != null' "${candidate}/compose.json" >/dev/null; then
        dockerIPv6NetworkManage cleanup "${project}" || failed=1
    fi
    [[ "${failed}" == 0 ]] || { dockerError "评估资源清理失败: ${project}"; return 1; }
    DOCKER_ASSESS_PROJECT=
    DOCKER_ASSESS_CANDIDATE=
}

dockerAssessCandidate() (
    local candidate=$1 core file version status="${1}/assessment.status"
    local log="${1}/assessment.log" warnings="${1}/assessment.warnings" found defaultHttp=false
    local probe="${1}/config/xray/.assessment-strict-probe.json"
    local strictLog="${1}/assessment.strict.log" strictStatus=0
    [[ -z "$(find "${candidate}" -type l -print -quit)" ]] || {
        dockerError '评估候选不能包含符号链接'
        return 1
    }
    # 编排必须由受管规格无损重建，防止自定义挂载将试跑写入生产目录。
    dockerGenerateCompose "${candidate}/config/spec.json" "${candidate}/compose.assessment.json" &&
        jq -en --arg project "${DOCKER_ASSESS_PROJECT}" \
            --slurpfile expected "${candidate}/compose.assessment.json" \
            --slurpfile actual "${candidate}/compose.json" '
          def comparable:
            if .name == $project then .name = "padm-docker" else . end |
            if .networks.default.name == $project then
              .networks.default.name = "padm-docker" |
              .networks.default.labels["io.padm.project"] = "padm-docker"
            else . end |
            if .networks.ipv6.name == ($project + "-ipv6") then
              .networks.ipv6.name = "padm-docker-ipv6" |
              .networks.ipv6.labels["io.padm.project"] = "padm-docker"
            else . end |
            .services |= with_entries(.value.labels |= del(."io.padm.release"));
          ($actual | length) == 1 and ($expected[0] | comparable) == ($actual[0] | comparable)
        ' >/dev/null || {
        dockerError '现有编排与受管规格不一致，拒绝运行升级评估'
        return 1
    }
    jq --arg project "${DOCKER_ASSESS_PROJECT}" '
      .name = $project | .networks.default.name = $project |
      .networks.default.labels["io.padm.project"] = $project |
      if .networks.ipv6 != null then
        .networks.ipv6.name = ($project + "-ipv6") |
        .networks.ipv6.labels["io.padm.project"] = $project
      else . end
    ' "${candidate}/compose.json" >"${candidate}/compose.assessment-isolated.json" &&
        mv -- "${candidate}/compose.assessment-isolated.json" "${candidate}/compose.json" || return 1
    # 只加载菜单版扫描函数，不调用原生下载、安装、迁移或服务操作。
    # shellcheck source=/dev/null
    source "${DOCKER_BUNDLE_SOURCE_ROOT}/shell/core/cores.sh" || return 1
    : >"${status}" && : >"${log}" && : >"${warnings}" || return 1
    printf '候选发布: %s\n' "$(jq -er '.padm_version' "${candidate}/deployment.json")"
    while IFS= read -r core; do
        case "${core}" in
        xray)
            version=$(dockerCandidateCompose "${candidate}" run --rm --no-deps xray version) || return 1
            [[ "${version}" == Xray\ * ]] || { dockerError '无法读取候选 Xray 版本'; return 1; }
            ;;
        sing-box)
            version=$(dockerCandidateCompose "${candidate}" run --rm --no-deps sing-box version) || return 1
            [[ "${version}" == sing-box\ version\ * ]] || { dockerError '无法读取候选 sing-box 版本'; return 1; }
            defaultHttp=$(jq -s 'any(.[]; (.route.default_http_client? // "") != "")' \
                "${candidate}/config/sing-box/"*.json) || return 1
            grep -Eq '(^|[^[:alnum:]_])with_v2ray_api([^[:alnum:]_]|$)' <<<"${version}" || {
                dockerError '候选 sing-box 缺少流量统计所需的 v2ray API 能力'
                return 1
            }
            ;;
        *) return 1 ;;
        esac
        printf '核心 %s: %s\n' "${core}" "${version%%$'\n'*}"
        found=0
        for file in "${candidate}/config/${core}/"*.json; do
            [[ -f "${file}" && ! -L "${file}" ]] || continue
            found=1
            case "${core}" in
            xray) xrayCompatibilityAuditScanJsonFile "${file}" "${status}" "${log}" "${warnings}" || return 1 ;;
            sing-box) singBoxCompatibilityAuditScanJsonFile "${file}" "${status}" "${log}" "${warnings}" "${defaultHttp}" || return 1 ;;
            esac
        done
        [[ "${found}" == 1 ]] || { dockerError "候选 ${core} JSON 配置缺失"; return 1; }
    done < <(jq -r '[.core.type, .core.secondary_type] | .[] | select(. != null)' "${candidate}/config/spec.json")
    cat -- "${log}" || return 1
    if coreCompatibilityAuditHasFailures "${status}"; then
        dockerError '升级风险扫描失败，现有部署未修改'
        return 1
    fi
    if [[ -s "${warnings}" ]]; then
        printf '升级风险扫描: 需关注上述警告\n'
    else
        printf '升级风险扫描: 未发现已知风险\n'
    fi
    dockerBundleSupportsSpec "${DOCKER_STAGED_BUNDLE_PATH}" "${candidate}/config/spec.json" &&
        dockerValidateCandidate "${candidate}/config/spec.json" "${candidate}" || return 1
    printf 'Compose 校验: 通过\n核心配置试跑: 通过\n'
    if jq -e '[.core.type, .core.secondary_type] | index("xray") != null' \
        "${candidate}/config/spec.json" >/dev/null; then
        dockerCandidateCompose "${candidate}" run --rm --no-deps -e XRAY_JSON_STRICT=true \
            xray -test -confdir /etc/padm/xray >/dev/null || {
            dockerError 'Xray 候选严格校验失败'
            return 1
        }
        # 普通模式能读取、严格模式明确拒绝未知字段，才证明核心启用了严格解析。
        jq '.padm_assessment_unknown_field = true' "${candidate}/config/xray/config.json" \
            >"${probe}" && chmod 0640 "${probe}" || return 1
        [[ "${PADM_DOCKER_SKIP_CHOWN:-0}" == 1 ]] ||
            chown "0:${PADM_DOCKER_CONTAINER_GID}" "${probe}" || return 1
        if ! dockerCandidateCompose "${candidate}" run --rm --no-deps xray \
            -test -config /etc/padm/xray/.assessment-strict-probe.json >"${strictLog}" 2>&1; then
            dockerError 'Xray 严格解析能力探针的普通模式失败'
            return 1
        fi
        dockerCandidateCompose "${candidate}" run --rm --no-deps -e XRAY_JSON_STRICT=true \
            xray -test -config /etc/padm/xray/.assessment-strict-probe.json \
            >"${strictLog}" 2>&1 || strictStatus=$?
        rm -f -- "${probe}" || return 1
        if [[ "${strictStatus}" == 0 ]]; then
            printf 'Xray 严格校验: 未启用；候选核心未拒绝未知字段，仅普通配置试跑通过。\n'
        elif grep -Fq 'unknown field "padm_assessment_unknown_field"' "${strictLog}"; then
            printf 'Xray 严格校验: 通过\n'
        else
            dockerError 'Xray 严格解析能力探针失败，不能确认严格校验'
            return 1
        fi
    fi
    printf 'TLS 校验: %s\n订阅校验: %s\n宿主集成校验: %s\n' \
        "$(jq -r 'if .tls != null then "通过" else "未启用" end' "${candidate}/config/spec.json")" \
        "$(jq -r 'if .subscription.enabled == true then "通过" else "未启用" end' "${candidate}/config/spec.json")" \
        "$(jq -r 'if (.host_integrations | length) > 0 or .reality_stream.host_website != null then "通过" else "未启用" end' "${candidate}/config/spec.json")"
)

dockerAssessCommand() {
    local manifest= bundle= controlBundle= root status=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest|--bundle|--control-bundle)
            [[ "$#" -ge 2 && -n "$2" && "$2" != --* ]] || return "${PADM_DOCKER_RC_USAGE}"
            case "$1" in
            --manifest) manifest=$2 ;;
            --bundle) bundle=$2 ;;
            --control-bundle) controlBundle=$2 ;;
            esac
            shift 2
            ;;
        *) dockerUsage; return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] || {
        dockerError '完整升级评估需要受管规格，请先通过 edit --spec 导入原始规格'
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerControlSyncScheduleSpecCheck "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle && dockerRenewalBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" &&
        dockerGeoBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" &&
        dockerControlLogScheduleBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" &&
        dockerControlSyncScheduleBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" ||
        return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
    # 评估只操作私有副本，不采集流量、不备份、不切换、不启停生产服务。
    if dockerCreateUpdateCandidate; then
        DOCKER_ASSESS_CANDIDATE=${DOCKER_CONFIG_CANDIDATE}
        DOCKER_ASSESS_PROJECT=${DOCKER_CONFIG_CANDIDATE##*.}
        DOCKER_ASSESS_PROJECT="padm-docker-assess-${DOCKER_ASSESS_PROJECT,,}"
        dockerAssessCandidate "${DOCKER_CONFIG_CANDIDATE}" || status=${PADM_DOCKER_RC_STATE}
    else
        status=${PADM_DOCKER_RC_STATE}
    fi
    if [[ "${status}" -ne 0 ]]; then
        dockerError '核心升级评估未通过，现有部署未修改'
    fi
    dockerAssessCleanup || status=${PADM_DOCKER_RC_STATE}
    dockerCleanupConfigurationCandidate || status=${PADM_DOCKER_RC_STATE}
    [[ "${status}" -ne 0 ]] || printf '核心升级评估完成，现有部署未修改；客户端连通仍需独立验收。\n'
    return "${status}"
}

dockerUpdateCommand() {
    local manifest= bundle= controlBundle= candidate backup root sshPresent sshInput
    local -a updateArguments=("$@")
    # 升级失败恢复仍须重新挑战，只复用本次预期来源。
    # shellcheck disable=SC2034
    local DOCKER_FAIL2BAN_SOURCE_IPV4='' DOCKER_FAIL2BAN_SOURCE_IPV6=''
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --manifest)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            manifest=$2
            shift 2
            ;;
        --bundle)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            bundle=$2
            shift 2
            ;;
        --control-bundle)
            [[ "$#" -ge 2 && -n "$2" ]] || return "${PADM_DOCKER_RC_USAGE}"
            controlBundle=$2
            shift 2
            ;;
        *)
            dockerUsage
            return "${PADM_DOCKER_RC_USAGE}"
            ;;
        esac
    done
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${FUNCNAME[1]:-}" != dockerPortHoppingTargetSupervisedOwned &&
        ( -e "${root}/data/net/.hopping-supervisor" || -L "${root}/data/net/.hopping-supervisor" ) ]]; then
        dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" update "${root}" "${updateArguments[@]}"
        return $?
    fi
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    sshInput="${root}/deployment.json"
    [[ ! -e "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] ||
        sshInput="${root}/config/spec.json"
    sshPresent=$(jq -r 'any(.host_integrations[]; .type == "fail2ban-ssh")' \
        "${sshInput}") || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${sshPresent}" == true ]]; then
        dockerError 'SSH 防护启用期间暂不支持版本更新，请先通过 SSH 防护入口停用'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerControlSyncScheduleSpecCheck "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" ||
        return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle || {
        dockerError '无法准备 release 控制 bundle，现有部署未切换'
        return "${PADM_DOCKER_RC_BUNDLE}"
    }
    dockerRenewalBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerGeoBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerControlLogScheduleBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerControlSyncScheduleBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPortHoppingSupervisorChangeBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" ||
        return "${PADM_DOCKER_RC_BUNDLE}"
    dockerPullManifestImages || return "${PADM_DOCKER_RC_COMPOSE}"
    dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
    dockerTrafficBeforeChange
    dockerCreateUpdateCandidate || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    candidate=${DOCKER_CONFIG_CANDIDATE}
    dockerValidateUpdateCandidate "${candidate}" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerFail2banSourceInputsPrepare "${candidate}/config/spec.json" "${root}/config/spec.json" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerControlAccessLogEnsure "${root}" "${candidate}/config/spec.json" || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    dockerBackupConfiguration update || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    dockerPortHoppingSupervisorChangeCheck || return "${PADM_DOCKER_RC_STATE}"
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerActivateStagedBundle ||
        ! dockerPortHoppingSupervisorChangeCheck ||
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall ||
        ! dockerRenewalScheduleInstall ||
        ! dockerGeoScheduleInstall ||
        ! dockerControlLogScheduleInstall ||
        ! dockerControlSyncScheduleInstall ||
        ! dockerPortHoppingSupervisorChangeCheck; then
        dockerError '控制脚本切换、启动或健康检查失败，正在恢复旧配置和控制脚本'
        if ! dockerRestoreConfiguration; then
            dockerError "旧版本恢复失败，请检查备份: ${backup}"
        fi
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    DOCKER_CONFIG_SWITCHED=0
    DOCKER_CONFIG_STREAM_TRANSITION=0
    DOCKER_CONFIG_STREAM_HOST_TRANSITION=0
    dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
    printf 'Docker 镜像和控制脚本更新已提交，回滚快照: %s\n' "${backup}"
}

dockerConfigurationBackupAllowed() {
    case "$1" in
    deployment.json|deployment.previous.json|images.env|compose.json|config/xray|config/sing-box|config/nginx|config/net|config/control|config/spec.json|config/share-groups.json|data/traffic/state.json|data/subscription|data/static|secrets/tls|data/acme) return 0 ;;
    *) return 1 ;;
    esac
}

dockerValidateConfigurationBackup() {
    local backup=$1 root relative entry bundlePath expectedCompose
    root=$(dockerInstallRoot) || return 1
    dockerManagedPathIsSafe "${root}" "${backup}" || return 1
    [[ "${backup}" == "${root%/}/backups/"* && -d "${backup}" && ! -L "${backup}" && -O "${backup}" ]] || return 1
    [[ -f "${backup}/present" && ! -L "${backup}/present" && -O "${backup}/present" ]] || return 1
    # 挑战根不属于配置快照，恢复不得发布旧 token 或替换在线目录。
    [[ ! -e "${backup}/data/acme-webroot" && ! -L "${backup}/data/acme-webroot" ]] || return 1
    [[ -z "$(find "${backup}" -type l -print -quit 2>/dev/null)" ]] || return 1
    if [[ -e "${backup}/bundle.target" ]]; then
        [[ -f "${backup}/bundle.target" && -O "${backup}/bundle.target" ]] || return 1
        dockerBundlePathForTarget "$(<"${backup}/bundle.target")" >/dev/null || return 1
    fi
    while IFS= read -r relative; do
        dockerConfigurationBackupAllowed "${relative}" || return 1
        [[ -n "${relative}" && -e "${backup}/${relative}" && ! -L "${backup}/${relative}" &&
            -O "${backup}/${relative}" ]] || return 1
    done <"${backup}/present"
    [[ -z "$(sort "${backup}/present" | uniq -d)" ]] || return 1
    while IFS= read -r entry; do
        [[ "${entry}" == "${backup}/present" || "${entry}" == "${backup}/bundle.target" ||
            "${entry}" == "${backup}/deployment.json" ||
            "${entry}" == "${backup}/deployment.previous.json" || "${entry}" == "${backup}/images.env" ||
            "${entry}" == "${backup}/compose.json" || "${entry}" == "${backup}/config" ||
            "${entry}" == "${backup}/data" || "${entry}" == "${backup}/secrets" ||
            "${entry}" == "${backup}/secrets/tls" || "${entry}" == "${backup}/secrets/tls/"* ||
            "${entry}" == "${backup}/config/"* ||
            "${entry}" == "${backup}/data/"* ]] || return 1
        [[ -O "${entry}" ]] || return 1
    done < <(find "${backup}" -mindepth 1 -print)
    grep -qxF deployment.json "${backup}/present" || return 1
    grep -qxF compose.json "${backup}/present" || return 1
    grep -qxF images.env "${backup}/present" || return 1
    dockerDeploymentFileValidate "${backup}/deployment.json" || return 1
    # 本机调度登记不在业务快照中，但启用时仍须约束将要恢复的控制 bundle。
    dockerControlLogScheduleValidate "${root}" || return 1
    dockerControlSyncScheduleValidate "${root}" || return 1
    if [[ -f "${root}/secrets/control-sync/request.json" ]]; then
        [[ -f "${backup}/config/spec.json" ]] &&
            dockerControlSyncScheduleSpecCheck "${backup}/config/spec.json" || return 1
    fi
    if [[ -f "${root}/secrets/control-sync/request.json" ]] ||
        { [[ -f "${root}/data/control-log/schedule.json" ]] &&
        jq -e '.enabled == true' "${root}/data/control-log/schedule.json" >/dev/null; }; then
        if [[ -f "${backup}/bundle.target" ]]; then
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") || return 1
        else
            bundlePath=$(dockerCurrentBundlePath) || return 1
        fi
        dockerControlLogScheduleBundleCheck "${bundlePath}" || return 1
        dockerControlSyncScheduleBundleCheck "${bundlePath}" || return 1
    fi
    if [[ -e "${backup}/config/share-groups.json" ]]; then
        grep -qxF config/share-groups.json "${backup}/present" &&
            dockerSubscriptionStateValidate "${backup}/config/share-groups.json" || return 1
    fi
    if [[ -e "${backup}/data/traffic/state.json" ]]; then
        [[ "${backup##*/}" == business.* ]] &&
            grep -qxF data/traffic/state.json "${backup}/present" &&
            jq -e "${DOCKER_TRAFFIC_STATE_JQ}" "${backup}/data/traffic/state.json" >/dev/null || return 1
    fi
    if [[ -e "${backup}/config/spec.json" || -L "${backup}/config/spec.json" ]]; then
        grep -qxF config/spec.json "${backup}/present" || return 1
        dockerManagedSpecMatchesDeployment "${backup}/config/spec.json" \
            "${backup}/deployment.json" "${backup}/images.env" || return 1
        if [[ -f "${backup}/bundle.target" ]]; then
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") || return 1
        else
            bundlePath=$(dockerCurrentBundlePath) || return 1
        fi
        dockerBundleSupportsSpec "${bundlePath}" "${backup}/config/spec.json" || return 1
        if jq -e '((.relay.http.address_families // []) | index("ipv6")) != null' \
            "${backup}/config/spec.json" >/dev/null; then
            # 恢复旧 IPv4 bridge 会折叠 IPv6 来源，须在停服前核对受管网络。
            expectedCompose=$(dockerGenerateCompose "${backup}/config/spec.json" /dev/stdout "${backup}") || return 1
            jq -en --slurpfile compose "${backup}/compose.json" --argjson expected "${expectedCompose}" '
              ($compose | length) == 1 and
              $compose[0].networks.ipv6 == $expected.networks.ipv6 and
              $compose[0].services.xray.networks == $expected.services.xray.networks and
              $compose[0].services.xray.network_mode == null
            ' >/dev/null || {
                dockerError 'IPv6 HTTP 中继恢复编排缺少受管来源网络，尚未停止或修改服务'
                return 1
            }
        fi
        dockerGeoBundleCheck "${bundlePath}" "${backup}" || return 1
        dockerControlStateCheck "${backup}" || return 1
        if jq -e 'has("site")' "${backup}/config/spec.json" >/dev/null; then
            grep -qxF data/static "${backup}/present" &&
                dockerSiteStateValidate "${backup}/config/spec.json" "${backup}" || return 1
        fi
        if jq -e 'has("control")' "${backup}/config/spec.json" >/dev/null; then
            grep -qxF config/control "${backup}/present" || return 1
        fi
    elif [[ -e "${backup}/config/control/state.json" ]]; then
        return 1
    fi
    if [[ -e "${backup}/data/static" || -L "${backup}/data/static" ]]; then
        grep -qxF data/static "${backup}/present" &&
            dockerSiteTreeValidate "${backup}/data/static" || return 1
    fi
}

dockerLatestUpdateBackup() {
    local root backup= candidate
    root=$(dockerInstallRoot) || return 1
    while IFS= read -r candidate; do
        [[ -d "${candidate}" && ! -L "${candidate}" && -O "${candidate}" ]] || continue
        dockerValidateConfigurationBackup "${candidate}" || continue
        if [[ -z "${backup}" ]] || [[ "$(stat -c %Y "${candidate}" 2>/dev/null || printf 0)" -gt \
            "$(stat -c %Y "${backup}" 2>/dev/null || printf 0)" ]]; then
            backup=${candidate}
        fi
    done < <(find "${root}/backups" -mindepth 1 -maxdepth 1 -type d -name 'update.*' -print 2>/dev/null)
    [[ -n "${backup}" ]] || return 1
    printf '%s\n' "${backup}"
}

dockerTrafficRollbackCheck() {
    local backup=$1 root version
    jq -e '[.core.type, .core.secondary_type] | index("sing-box") != null' "${backup}/deployment.json" >/dev/null ||
        return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -f "${root}/data/traffic/state.json" || -f "${root}/config/sing-box/users.base" ||
        -f "${backup}/config/sing-box/users.base" ]]; then
        version=$(dockerCandidateCompose "${backup}" run --rm --no-deps sing-box version) || return 1
        grep -Eq '(^|[^[:alnum:]_])with_v2ray_api([^[:alnum:]_]|$)' <<<"${version}" || {
            dockerError '回滚目标 sing-box 不支持用户统计，无法保留当前采集与额度管理；现有部署未停止'
            return 1
        }
    fi
}

dockerRollbackCommand() {
    local backup currentBackup bundlePath root sshPresent sshInput sshBackupInput
    # 回滚与失败恢复共享输入，现场证明每次重新取得。
    # shellcheck disable=SC2034
    local DOCKER_FAIL2BAN_SOURCE_IPV4='' DOCKER_FAIL2BAN_SOURCE_IPV6=''
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${FUNCNAME[1]:-}" != dockerPortHoppingTargetSupervisedOwned &&
        ( -e "${root}/data/net/.hopping-supervisor" || -L "${root}/data/net/.hopping-supervisor" ) ]]; then
        dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
        python3 -B "${DOCKER_LIB_DIR}/port-hopping-supervisor.py" rollback "${root}"
        return $?
    fi
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，无法回滚'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    backup=$(dockerLatestUpdateBackup) || {
        dockerError '没有可用的更新回滚快照'
        return "${PADM_DOCKER_RC_STATE}"
    }
    if [[ "${FUNCNAME[1]:-}" == dockerPortHoppingTargetSupervisedOwned ]]; then
        if [[ -e "${backup}/bundle.target" || -L "${backup}/bundle.target" ]]; then
            [[ -f "${backup}/bundle.target" && ! -L "${backup}/bundle.target" &&
                -O "${backup}/bundle.target" ]] || return "${PADM_DOCKER_RC_BUNDLE}"
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") ||
                return "${PADM_DOCKER_RC_BUNDLE}"
        else
            bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
        fi
        dockerPortHoppingSupervisorChangeBundleCheck "${bundlePath}" "${backup}/config/spec.json" ||
            return "${PADM_DOCKER_RC_BUNDLE}"
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    sshInput="${root}/deployment.json" sshBackupInput="${backup}/deployment.json"
    [[ ! -e "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] ||
        sshInput="${root}/config/spec.json"
    [[ ! -e "${backup}/config/spec.json" && ! -L "${backup}/config/spec.json" ]] ||
        sshBackupInput="${backup}/config/spec.json"
    sshPresent=$(jq -rn --slurpfile current "${sshInput}" --slurpfile backup "${sshBackupInput}" \
        'any($current[0].host_integrations[]; .type == "fail2ban-ssh") or
         any($backup[0].host_integrations[]; .type == "fail2ban-ssh")') ||
        return "${PADM_DOCKER_RC_STATE}"
    if [[ "${sshPresent}" == true ]]; then
        dockerError 'SSH 防护相关版本回滚尚未接入联合清理，未修改当前部署'
        return "${PADM_DOCKER_RC_STATE}"
    fi
    if [[ -f "${root}/config/spec.json" ]] &&
        jq -e '.tls.http01 == true' "${root}/config/spec.json" >/dev/null; then
        dockerAcmeWebrootTransitionValidate "${backup}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerControlSyncRollbackCheck "${backup}" || return "${PADM_DOCKER_RC_STATE}"
    dockerRealityStreamDeploymentCheck "${backup}/config/spec.json" "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficSafePath "${root}" "${root}/secrets/renewal" &&
        dockerRenewalRegistryValidate "${root}/secrets/renewal" || return "${PADM_DOCKER_RC_STATE}"
    if dockerRenewalEnabled "${root}/secrets/renewal"; then
        if [[ -e "${backup}/bundle.target" || -L "${backup}/bundle.target" ]]; then
            [[ -f "${backup}/bundle.target" && ! -L "${backup}/bundle.target" &&
                -O "${backup}/bundle.target" ]] || return "${PADM_DOCKER_RC_BUNDLE}"
            bundlePath=$(dockerBundlePathForTarget "$(<"${backup}/bundle.target")") || return "${PADM_DOCKER_RC_BUNDLE}"
        else
            bundlePath=$(dockerCurrentBundlePath) || return "${PADM_DOCKER_RC_BUNDLE}"
        fi
        dockerRenewalBundleCheck "${bundlePath}" || return "${PADM_DOCKER_RC_BUNDLE}"
    else
        [[ "$?" == 1 ]] || return "${PADM_DOCKER_RC_STATE}"
    fi
    dockerTrafficRollbackCheck "${backup}" || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck "$(jq -r '.core.type, (.core.secondary_type // empty)' "${backup}/deployment.json")" ||
        return "${PADM_DOCKER_RC_HOST}"
    dockerFail2banSourceInputsPrepare "${backup}/config/spec.json" "${root}/config/spec.json" ||
        return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficBeforeChange
    dockerBackupConfiguration rollback || return "${PADM_DOCKER_RC_STATE}"
    currentBackup=${DOCKER_CONFIG_BACKUP}
    dockerPortHoppingSupervisorChangeCheck || return "${PADM_DOCKER_RC_STATE}"
    DOCKER_CONFIG_BACKUP=${backup}
    DOCKER_CONFIG_SWITCHED=1
    if dockerRestoreConfiguration && dockerTrafficScheduleInstall &&
        dockerPortHoppingSupervisorChangeCheck; then
        DOCKER_CONFIG_BACKUP=${currentBackup}
        dockerCleanupConfigurationCandidate || return "${PADM_DOCKER_RC_STATE}"
        printf 'Docker 已回滚到: %s\n' "${backup}"
        return 0
    fi
    dockerError '回滚失败，正在尝试恢复当前版本'
    DOCKER_CONFIG_BACKUP=${currentBackup}
    DOCKER_CONFIG_SWITCHED=1
    dockerRestoreConfiguration && dockerTrafficScheduleInstall ||
        dockerError "当前版本或采集调度恢复失败，请检查备份: ${currentBackup}"
    dockerCleanupConfigurationCandidate || true
    return "${PADM_DOCKER_RC_COMPOSE}"
}

dockerRemoveRecordedImages() {
    local root name key reference expectedDigest actualDigest
    local -A keys=(
        [xray]=PADM_XRAY_IMAGE [sing-box]=PADM_SINGBOX_IMAGE [nginx]=PADM_NGINX_IMAGE
        [ops]=PADM_OPS_IMAGE [net]=PADM_NET_IMAGE
    )
    root=$(dockerInstallRoot) || return 1
    dockerDeploymentFileValidate "${root}/deployment.json" || return 1
    [[ -f "${root}/images.env" && ! -L "${root}/images.env" && -O "${root}/images.env" ]] || return 1
    for name in "${PADM_DOCKER_MANIFEST_IMAGE_NAMES[@]}"; do
        key=${keys[${name}]}
        reference=$(sed -n "s/^${key}=//p" "${root}/images.env") || return 1
        [[ "$(printf '%s\n' "${reference}" | wc -l | tr -d '[:space:]')" == "1" ]] || return 1
        [[ "${reference}" =~ ^[a-z0-9][a-z0-9._/-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$ ]] || return 1
        expectedDigest=$(jq -er --arg name "${name}" '.images[$name].index_digest' "${root}/deployment.json") || return 1
        actualDigest=${reference##*@}
        [[ "${actualDigest}" == "${expectedDigest}" ]] || return 1
        docker image rm "${reference}" || return 1
    done
}

dockerPurgeStateRoot() {
    local root marker parent resolved
    root=$(dockerInstallRoot) || return 1
    dockerPathIsSafeAbsolute "${root}" || return 1
    [[ -d "${root}" && ! -L "${root}" && -O "${root}" ]] || return 1
    parent=$(cd -- "$(dirname -- "${root}")" 2>/dev/null && pwd -P) || return 1
    resolved="${parent}/$(basename -- "${root}")"
    [[ "${resolved}" == "${root}" ]] || return 1
    marker=$(padmDeploymentModeAtRoot "${root}") || return 1
    [[ "${marker}" == docker && -f "${root}/mode" && ! -L "${root}/mode" && -O "${root}/mode" ]] || return 1
    rm -rf -- "${root}"
}

dockerUninstallCommand() {
    local state removeImages=0 purge=0 confirm= backup root
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        --remove-images) removeImages=1; shift ;;
        --purge) purge=1; shift ;;
        --confirm)
            [[ "$#" -ge 2 ]] || return "${PADM_DOCKER_RC_USAGE}"
            confirm=$2
            shift 2
            ;;
        *) return "${PADM_DOCKER_RC_USAGE}" ;;
        esac
    done
    if ((purge)); then
        [[ "${confirm}" == 'PADM-DOCKER-PURGE' ]] || {
            dockerError 'purge 必须使用 --confirm PADM-DOCKER-PURGE'
            return "${PADM_DOCKER_RC_USAGE}"
        }
    elif [[ -n "${confirm}" ]]; then
        return "${PADM_DOCKER_RC_USAGE}"
    fi
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    state=$(dockerDeploymentState) || return "${PADM_DOCKER_RC_STATE}"
    if [[ "${state}" == "absent" ]]; then
        printf 'Docker 版 padm 未安装，无需卸载\n'
        return 0
    fi
    dockerPortHoppingSupervisorStopIfActive || return $?
    dockerLockInstalledDeployment || return $?
    dockerTrafficBeforeChange
    if ((purge)); then
        dockerBackupConfiguration uninstall || return "${PADM_DOCKER_RC_STATE}"
        backup=${DOCKER_CONFIG_BACKUP}
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerGeoScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerControlLogScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerControlSyncScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/compose.json" || -e "${root}/deployment.json" || -e "${root}/images.env" ]]; then
        dockerComposeFile >/dev/null || {
            dockerError 'Docker Compose 状态不完整，已拒绝卸载'
            return "${PADM_DOCKER_RC_STATE}"
        }
        dockerComposeRun down || return $?
    else
        dockerTProxyDisablePrepare <(printf '{"host_integrations":[]}') ||
            return "${PADM_DOCKER_RC_STATE}"
        if [[ -e "${root}/data/net/ssh-collector" || -L "${root}/data/net/ssh-collector" ]]; then
            dockerSshFail2banDisablePrepare <(printf '{"host_integrations":[]}') ||
                return "${PADM_DOCKER_RC_STATE}"
        fi
    fi
    dockerTrafficScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerRemoveCli || return "${PADM_DOCKER_RC_STATE}"
    if ((removeImages)); then
        dockerRemoveRecordedImages || return "${PADM_DOCKER_RC_COMPOSE}"
    fi
    if ((purge)); then
        dockerPurgeStateRoot || {
            dockerError "purge 失败；卸载备份仍保留: ${backup}"
            return "${PADM_DOCKER_RC_STATE}"
        }
        printf 'Docker 状态、控制 bundle、配置和数据已清理\n'
    elif ((removeImages)); then
        printf 'Docker 控制命令及记录的镜像已卸载；状态、配置、数据和备份均已保留\n'
    else
        printf 'Docker 控制命令已卸载；状态、配置、数据、备份和镜像均已保留\n'
    fi
}

dockerCommandInterrupted() {
    local status=$1
    dockerAcmeChallengeRestore || true
    dockerAssessCleanup || true
    dockerMaintenanceScheduleInterrupted traffic || true
    dockerControlLogScheduleInterrupted || true
    dockerControlSyncScheduleInterrupted || true
    dockerGeoScheduleInterrupted || true
    dockerGeoInterrupted || true
    dockerRenewalScheduleInterrupted || true
    if declare -F dockerRenewalInterrupted >/dev/null 2>&1; then
        dockerRenewalInterrupted || true
    fi
    if declare -F dockerConfigurationInterrupted >/dev/null 2>&1; then
        dockerConfigurationInterrupted || true
    fi
    dockerRestoreInstallTransaction || true
    dockerSetupCleanup || true
    dockerCleanupStateInitialization || true
    dockerCleanupBundleLinkTemp || true
    dockerReleaseDeploymentLock || true
    dockerCleanupStagedBundle || true
    dockerManifestCleanup || true
    dockerEntryCleanup || true
    exit "${status}"
}

dockerMain() {
    local command=${1:-menu} status
    [[ "$#" -gt 0 ]] && shift
    # 菜单不持有部署锁，各操作由独立 CLI 进程完成清理。
    if [[ "${command}" == menu ]]; then
        dockerMenu "$@"
        return $?
    fi
    trap 'dockerCommandInterrupted 130' INT
    trap 'dockerCommandInterrupted 143' TERM
    case "${command}" in
    install) dockerInstallCommand "$@" ;;
    release) dockerReleaseCommand "$@" ;;
    setup) dockerSetupCommand "$@" ;;
    edit) dockerEditCommand "$@" ;;
    protocol) dockerProtocolCommand "$@" ;;
    account) dockerAccountCommand "$@" ;;
    subscription | share) dockerSubscriptionCommand "$@" ;;
    business) dockerBusinessCommand "$@" ;;
    control) dockerControlCommand "$@" ;;
    configure) dockerConfigureCommand "$@" ;;
    tls)
        case "${1:-}" in
        install) shift; dockerTlsInstallCommand "$@" ;;
        validate) shift; dockerTlsValidateCommand "$@" ;;
        manage) shift; dockerTlsManageCommand "$@" ;;
        *) status=${PADM_DOCKER_RC_USAGE} ;;
        esac
        ;;
    acme)
        case "${1:-}" in
        schedule) shift; dockerRenewalCommand "$@" ;;
        auto-renew) shift; dockerRenewalCommand run "$@" ;;
        *) dockerAcmeCommand "$@" ;;
        esac
        ;;
    validate) dockerValidateInstalledCommand "$@" ;;
    status) dockerStatusCommand "$@" ;;
    traffic) dockerTrafficCommand "$@" ;;
    port-hopping) dockerPortHoppingCommand "$@" ;;
    fail2ban) dockerFail2banCommand "$@" ;;
    up | down | restart | logs) dockerLifecycleCommand "${command}" "$@" ;;
    assess) dockerAssessCommand "$@" ;;
    geo) dockerGeoCommand "$@" ;;
    update) dockerUpdateCommand "$@" ;;
    rollback) dockerRollbackCommand "$@" ;;
    uninstall) dockerUninstallCommand "$@" ;;
    help | --help | -h)
        dockerUsage
        status=0
        ;;
    *)
        dockerUsage
        status=${PADM_DOCKER_RC_USAGE}
        ;;
    esac
    status=${status:-$?}
    dockerAcmeChallengeRestore || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerMaintenanceScheduleInterrupted traffic || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerControlLogScheduleInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerControlSyncScheduleInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerGeoScheduleInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerGeoInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerRenewalScheduleInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    if declare -F dockerRenewalInterrupted >/dev/null 2>&1; then
        dockerRenewalInterrupted || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    fi
    if [[ "${DOCKER_TLS_SWITCHED:-0}" == 1 ]]; then
        dockerRestoreTlsFiles || dockerError "TLS 事务恢复失败，请检查备份: ${DOCKER_TLS_BACKUP:-}"
        [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    fi
    dockerCleanupTlsCandidate || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerSetupCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    dockerCleanupStateInitialization || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_STATE}
    if [[ "${command}" == install && "${status}" -ne 0 ]]; then
        dockerRestoreInstallTransaction || true
    fi
    dockerCleanupBundleLinkTemp || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    dockerReleaseDeploymentLock || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_LOCK}
    dockerCleanupStagedBundle || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    dockerManifestCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_MANIFEST}
    if [[ "${command}" != install || "${status}" -ne 0 || "${DOCKER_MENU_AFTER_INSTALL:-0}" -ne 1 ]]; then
        dockerEntryCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    fi
    trap - INT TERM
    return "${status}"
}
