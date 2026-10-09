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
  padm-docker edit --site-redirect <HTTP/HTTPS URL> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --site-default [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http01 <enable|disable> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5 <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --socks5-global [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --http-relay-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias <入口 ID> <公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias-remove <入口 ID> <公开端口> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --port-alias-default <入口 ID> <已有额外端口|base> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-rules <IPv4/IPv6> <DNS 端口> <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --dns-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --hosts-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --direct-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-domains-add <域名规则 CSV> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-ips-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-bt [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --block-bt-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region <both|domain|ip> [--region-allow <域名规则 CSV>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --region-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6 <selective|global> [--ipv6-domains <域名规则 CSV>] [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --ipv6-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp <root 私有 JSON 文件> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --warp-off [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker edit --alpn <入口 ID> <h2,http/1.1|http/1.1,h2|http/1.1> [--preview|--confirm PADM-DOCKER-EDIT] [发布资产参数]
  padm-docker protocol list
  padm-docker protocol links [入口 ID]
  padm-docker protocol stream-status
  padm-docker protocol alpn-status [入口 ID]
  padm-docker protocol routing-status
  padm-docker protocol port-alias-status
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

dockerTrafficCronRemove() {
    local content
    command -v crontab >/dev/null 2>&1 || return 0
    content=$(dockerTrafficReadCrontab) || return 1
    if [[ "${content}" == *'# padm-docker-traffic'* ]]; then
        printf '%s\n' "${content}" | sed '/# padm-docker-traffic$/d' | crontab - || return 1
    fi
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
    local root cli bashPath unitDir temp cronText
    dockerTrafficScheduleCheck || return 1
    root=$(dockerInstallRoot) || return 1
    cli="${PADM_DOCKER_BIN_DIR:-/usr/local/bin}/padm-docker"
    bashPath=$(command -v bash) || return 1
    # 定时任务配置不能接受换行、shell 表达式或 systemd 占位符。
    [[ "${root}" =~ ^/[A-Za-z0-9._/-]+$ && "${cli}" =~ ^/[A-Za-z0-9._/-]+$ &&
        "${bashPath}" =~ ^/[A-Za-z0-9._/-]+$ ]] || return 1
    if command -v systemctl >/dev/null 2>&1 && systemctl show-environment >/dev/null 2>&1; then
        unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system}
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" ]] || return 1
        for temp in "${unitDir}/padm-docker-traffic.service" "${unitDir}/padm-docker-traffic.timer"; do
            [[ ! -L "${temp}" ]] || return 1
            if [[ -e "${temp}" ]]; then
                [[ -f "${temp}" && -O "${temp}" ]] &&
                    grep -qxF '# padm-docker 流量采集' "${temp}" || return 1
            fi
        done
        temp=$(mktemp "${root}/locks/traffic-unit.XXXXXX") || return 1
        cat >"${temp}" <<EOF
# padm-docker 流量采集
[Unit]
Description=padm Docker traffic accounting
After=docker.service
[Service]
Type=oneshot
Environment=PADM_DOCKER_INSTALL_DIR=${root}
ExecStart=${bashPath} ${cli} traffic collect
TimeoutStartSec=90
EOF
        install -m 0644 "${temp}" "${unitDir}/padm-docker-traffic.service" || { rm -f -- "${temp}"; return 1; }
        cat >"${temp}" <<'EOF'
# padm-docker 流量采集
[Unit]
Description=Collect padm Docker traffic every minute
[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s
Persistent=true
[Install]
WantedBy=timers.target
EOF
        install -m 0644 "${temp}" "${unitDir}/padm-docker-traffic.timer" || { rm -f -- "${temp}"; return 1; }
        rm -f -- "${temp}"
        systemctl daemon-reload && systemctl enable --now padm-docker-traffic.timer && dockerTrafficCronRemove
    else
        cronText=$(dockerTrafficReadCrontab) || return 1
        {
            printf '%s\n' "${cronText}" | sed '/# padm-docker-traffic$/d'
            printf '* * * * * PADM_DOCKER_INSTALL_DIR=%s %s %s traffic collect # padm-docker-traffic\n' "${root}" "${bashPath}" "${cli}"
        } | crontab -
    fi
}

dockerTrafficScheduleRemove() {
    local unitDir file changed=0
    unitDir=${PADM_DOCKER_SYSTEMD_DIR:-/etc/systemd/system}
    for file in "${unitDir}/padm-docker-traffic.timer" "${unitDir}/padm-docker-traffic.service"; do
        [[ -e "${file}" || -L "${file}" ]] || continue
        [[ -d "${unitDir}" && ! -L "${unitDir}" && -O "${unitDir}" &&
            -f "${file}" && ! -L "${file}" && -O "${file}" ]] || return 1
        grep -qxF '# padm-docker 流量采集' "${file}" || return 1
        if [[ "${file}" == *.timer ]]; then systemctl disable --now "${file##*/}" || return 1;
        else systemctl stop "${file##*/}" || return 1; fi
        rm -f -- "${file}" || return 1
        changed=1
    done
    [[ "${changed}" == 0 ]] || systemctl daemon-reload || return 1
    dockerTrafficCronRemove
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
    commandArgs=(docker compose --project-name "${PADM_DOCKER_PROJECT}"
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
    dockerAcquireDeploymentLock || return "${PADM_DOCKER_RC_LOCK}"
    dockerRequireInstalledBundle || return "${PADM_DOCKER_RC_STATE}"
}

dockerStatusCommand() {
    local state bundlePath ref root siteMode=unknown
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
    shift
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    case "${operation}" in
    up|restart)
        root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
        dockerRealityStreamDeploymentCheck "${root}/config/spec.json" ||
            return "${PADM_DOCKER_RC_STATE}"
        ;;
    esac
    case "${operation}" in
    up)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficScheduleInstall && dockerRenewalScheduleInstall &&
            dockerGeoScheduleInstall && dockerComposeRun up -d
        ;;
    down)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
        dockerTrafficBeforeChange
        dockerComposeRun down && dockerTrafficScheduleRemove
        ;;
    restart)
        [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
        dockerTrafficRuntimeCheck || return "${PADM_DOCKER_RC_HOST}"
        dockerTrafficBeforeChange
        dockerTrafficScheduleInstall && dockerRenewalScheduleInstall &&
            dockerGeoScheduleInstall && dockerComposeRun restart
        ;;
    logs) dockerComposeRun logs "$@" ;;
    esac
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
    dockerRealityStreamDeploymentCheck "${root}/config/spec.json" || return "${PADM_DOCKER_RC_STATE}"
    dockerManifestPrepare "${manifest}" "${bundle}" "${controlBundle}" || return "${PADM_DOCKER_RC_MANIFEST}"
    dockerStageReleaseBundle && dockerRenewalBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" &&
        dockerGeoBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" ||
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
    local manifest= bundle= controlBundle= candidate backup root
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
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，请先执行 configure'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
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
    dockerBackupConfiguration update || {
        dockerCleanupConfigurationCandidate || true
        return "${PADM_DOCKER_RC_STATE}"
    }
    backup=${DOCKER_CONFIG_BACKUP}
    if ! dockerInstallCandidate "${candidate}" "${backup}" ||
        ! dockerEnsureRuntimeDataPermissions ||
        ! dockerActivateStagedBundle ||
        ! dockerComposeRun up -d --force-recreate --wait --wait-timeout "${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ||
        ! dockerTrafficScheduleInstall ||
        ! dockerRenewalScheduleInstall ||
        ! dockerGeoScheduleInstall; then
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
    local backup=$1 root relative entry bundlePath
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
    local backup currentBackup bundlePath root
    [[ "$#" -eq 0 ]] || return "${PADM_DOCKER_RC_USAGE}"
    dockerHostPreflight || return "${PADM_DOCKER_RC_HOST}"
    dockerLockInstalledDeployment || return $?
    dockerComposeFile >/dev/null || {
        dockerError 'Docker 服务尚未配置，无法回滚'
        return "${PADM_DOCKER_RC_COMPOSE}"
    }
    backup=$(dockerLatestUpdateBackup) || {
        dockerError '没有可用的更新回滚快照'
        return "${PADM_DOCKER_RC_STATE}"
    }
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
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
    fi
    dockerTrafficRollbackCheck "${backup}" || return "${PADM_DOCKER_RC_STATE}"
    dockerTrafficRuntimeCheck "$(jq -r '.core.type, (.core.secondary_type // empty)' "${backup}/deployment.json")" ||
        return "${PADM_DOCKER_RC_HOST}"
    dockerTrafficBeforeChange
    dockerBackupConfiguration rollback || return "${PADM_DOCKER_RC_STATE}"
    currentBackup=${DOCKER_CONFIG_BACKUP}
    DOCKER_CONFIG_BACKUP=${backup}
    DOCKER_CONFIG_SWITCHED=1
    if dockerRestoreConfiguration && dockerTrafficScheduleInstall; then
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
    dockerLockInstalledDeployment || return $?
    dockerTrafficBeforeChange
    if ((purge)); then
        dockerBackupConfiguration uninstall || return "${PADM_DOCKER_RC_STATE}"
        backup=${DOCKER_CONFIG_BACKUP}
    fi
    root=$(dockerInstallRoot) || return "${PADM_DOCKER_RC_STATE}"
    dockerGeoScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    dockerRenewalScheduleRemove || return "${PADM_DOCKER_RC_STATE}"
    if [[ -e "${root}/compose.json" || -e "${root}/deployment.json" || -e "${root}/images.env" ]]; then
        dockerComposeFile >/dev/null || {
            dockerError 'Docker Compose 状态不完整，已拒绝卸载'
            return "${PADM_DOCKER_RC_STATE}"
        }
        dockerComposeRun down || return $?
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
    else
        printf 'Docker 控制命令已卸载；状态、配置、数据、备份和镜像均已保留\n'
    fi
}

dockerCommandInterrupted() {
    local status=$1
    dockerAcmeChallengeRestore || true
    dockerAssessCleanup || true
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
    dockerReleaseDeploymentLock || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_LOCK}
    dockerCleanupStagedBundle || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    dockerManifestCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_MANIFEST}
    if [[ "${command}" != install || "${status}" -ne 0 || "${DOCKER_MENU_AFTER_INSTALL:-0}" -ne 1 ]]; then
        dockerEntryCleanup || [[ "${status}" -ne 0 ]] || status=${PADM_DOCKER_RC_BUNDLE}
    fi
    trap - INT TERM
    return "${status}"
}
