#!/usr/bin/env bash

passed=0
failed=0
warned=0

pass() {
    passed=$((passed + 1))
    printf '\033[32m[PASS]\033[0m %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf '\033[1;31m[FAIL]\033[0m %s\n' "$1"
}

warn() {
    warned=$((warned + 1))
    printf '\033[33m[WARN]\033[0m %s\n' "$1"
}

print_summary_card() {
    printf '\n\033[1;36m┌─ 验证摘要 ─────────────────────────────────────────\033[0m\n'
    printf '│ \033[32mPASS\033[0m：%d\n' "${passed}"
    printf '│ \033[33mWARN\033[0m：%d\n' "${warned}"
    printf '│ \033[1;31mFAIL\033[0m：%d\n' "${failed}"
    if [[ "${failed}" -eq 0 ]]; then
        if [[ "${warned}" -eq 0 ]]; then
            printf '│ 结论：\033[32m通过，可继续后续操作\033[0m\n'
        else
            printf '│ 结论：\033[33m无失败项，可继续；请按需查看 WARN\033[0m\n'
        fi
    else
        printf '│ 结论：\033[1;31m存在失败项，请先处理 FAIL 后再继续\033[0m\n'
    fi
    printf '\033[1;36m└──────────────────────────────────────────────────\033[0m\n'
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "命令存在：$1"
    else
        fail "命令缺失：$1"
    fi
}

check_file() {
    if [[ -f "$1" ]]; then
        pass "文件存在：$1"
    else
        fail "文件缺失：$1"
    fi
}

check_optional_file() {
    if [[ -f "$1" ]]; then
        pass "文件存在：$1"
    else
        warn "可选文件缺失：$1"
    fi
}

check_service_state() {
    local action=$1
    local service=$2
    local failureSeverity=${3:-fail}
    local missingMessage="systemctl 缺失，跳过服务状态检查：${service}"
    local successMessage="服务运行中：${service}"
    local failureMessage="服务未运行：${service}"

    if [[ "${action}" == "enabled" ]]; then
        missingMessage="systemctl 缺失，跳过服务开机自启检查：${service}"
        successMessage="服务已设置开机自启：${service}"
        failureMessage="服务未设置开机自启：${service}"
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        warn "${missingMessage}"
        return
    fi

    if systemctl is-${action} --quiet "${service}"; then
        pass "${successMessage}"
    else
        "${failureSeverity}" "${failureMessage}"
    fi
}

check_service_active() {
    check_service_state active "$1" fail
}

check_service_active_optional() {
    check_service_state active "$1" warn
}

check_service_enabled() {
    check_service_state enabled "$1" warn
}

check_no_pattern() {
    local path=$1
    local pattern=$2
    local label=$3

    if [[ ! -e "${path}" ]]; then
        warn "路径缺失，跳过模式检查：${path}"
        return
    fi

    : > /tmp/padm-validate-grep.log
    find "${path}" -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.list' -o -name '*.service' \) ! -path '*/shell/validate_install.sh' -exec grep -H -E "${pattern}" {} + >/tmp/padm-validate-grep.log 2>/dev/null || true
    if [[ -s /tmp/padm-validate-grep.log ]]; then
        fail "${label}：发现禁止模式"
        cat /tmp/padm-validate-grep.log
    else
        pass "${label}：未发现禁止模式"
    fi
}

check_contains() {
    local file=$1
    local pattern=$2
    local label=$3

    if [[ ! -f "${file}" ]]; then
        fail "${label}：文件缺失 ${file}"
        return
    fi

    if grep -E "${pattern}" "${file}" >/dev/null 2>&1; then
        pass "${label}"
    else
        fail "${label}：${file} 中缺少匹配内容"
    fi
}

check_fail2ban_jail_enabled() {
    local jailFile=$1
    local jailName=$2
    awk -v target="${jailName}" '
        /^\[/ {
            section=$0
            gsub(/^\[/, "", section)
            gsub(/\]$/, "", section)
            next
        }
        section == target && /^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$/ { found=1 }
        END { exit found ? 0 : 1 }
    ' "${jailFile}" >/dev/null 2>&1
}

check_fail2ban_jail_has_section() {
    local jailFile=$1
    local jailName=$2
    grep -Eq "^\\[${jailName//./\\.}\\]$" "${jailFile}" 2>/dev/null
}

check_apt_update() {
    warn "校验阶段跳过 apt update；只读验证不刷新在线状态"
}

check_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        pass "nginx 存在：$(nginx -v 2>&1)"
        if nginx -t >/tmp/padm-validate-nginx.log 2>&1; then
            pass "nginx 配置测试通过"
        else
            fail "nginx 配置测试失败"
            cat /tmp/padm-validate-nginx.log
        fi
        check_service_active nginx
        check_service_enabled nginx
    else
        warn "nginx 缺失，跳过 nginx 检查"
    fi
}

check_xray() {
    if [[ -x /etc/padm/xray/xray ]]; then
        pass "xray 二进制可执行"
        /etc/padm/xray/xray --version | head -n 1
        check_optional_file /etc/padm/xray/geoip.dat
        check_optional_file /etc/padm/xray/geosite.dat
        check_service_active xray.service
        check_service_enabled xray.service
    else
        warn "xray 二进制缺失或不可执行"
    fi
}

check_sing_box() {
    if [[ -x /etc/padm/sing-box/sing-box ]]; then
        pass "sing-box 二进制可执行"
        /etc/padm/sing-box/sing-box version | head -n 1
        check_service_active_optional sing-box.service
        check_service_enabled sing-box.service
    else
        warn "sing-box 二进制缺失或不可执行"
    fi
}

check_sing_box_compatibility_audit() {
    local statusFile warnFile summary

    if [[ ! -x /etc/padm/sing-box/sing-box ]]; then
        warn "未安装 sing-box，跳过兼容体检摘要"
        return
    fi
    if [[ ! -f /etc/padm/shell/core/bootstrap.sh ]]; then
        warn "缺少核心 bootstrap，跳过兼容体检摘要"
        return
    fi

    # 只读验收只输出摘要，不把历史兼容风险直接升级成 FAIL。
    (
        # shellcheck source=/dev/null
        source /etc/padm/shell/core/bootstrap.sh
        statusFile=$(singBoxCompatibilityAuditStatusFile)
        warnFile=$(singBoxCompatibilityAuditWarnFile)
        collectSingBoxCompatibilityFindings "${statusFile}" "$(singBoxCompatibilityAuditLog)" "${warnFile}"
        summary=$(summarizeSingBoxCompatibilityAudit "${statusFile}" "${warnFile}")
        if singBoxCompatibilityAuditHasFailures "${statusFile}"; then
            printf 'WARN:%s\n' "${summary}"
            printf 'LOG:%s\n' "$(singBoxCompatibilityAuditLog)"
        elif [[ -s "${warnFile}" ]]; then
            printf 'WARN:%s\n' "${summary}"
        else
            printf 'PASS:%s\n' "${summary}"
        fi
    ) >/tmp/padm-validate-sing-box-compat.log 2>&1 || true

    if grep -q '^PASS:' /tmp/padm-validate-sing-box-compat.log; then
        pass "sing-box 兼容体检通过"
    elif grep -q '^WARN:' /tmp/padm-validate-sing-box-compat.log; then
        warn "sing-box 兼容体检发现需关注项：$(sed -n 's/^WARN://p' /tmp/padm-validate-sing-box-compat.log | head -n 1)"
        if grep -q '^LOG:' /tmp/padm-validate-sing-box-compat.log; then
            warn "sing-box 兼容体检日志：$(sed -n 's/^LOG://p' /tmp/padm-validate-sing-box-compat.log | head -n 1)"
        fi
    else
        warn "sing-box 兼容体检摘要执行失败，已跳过"
        cat /tmp/padm-validate-sing-box-compat.log 2>/dev/null || true
    fi
}

check_xray_compatibility_audit() {
    local statusFile warnFile summary strictLog

    if [[ ! -x /etc/padm/xray/xray ]]; then
        warn "未安装 Xray，跳过兼容体检摘要"
        return
    fi
    if [[ ! -f /etc/padm/shell/core/bootstrap.sh ]]; then
        warn "缺少核心 bootstrap，跳过 Xray 兼容体检摘要"
        return
    fi

    (
        # shellcheck source=/dev/null
        source /etc/padm/shell/core/bootstrap.sh
        statusFile=$(xrayCompatibilityAuditStatusFile)
        warnFile=$(xrayCompatibilityAuditWarnFile)
        collectXrayCompatibilityFindings "${statusFile}" "$(xrayCompatibilityAuditLog)" "${warnFile}"
        summary=$(summarizeXrayCompatibilityAudit "${statusFile}" "${warnFile}")
        strictLog=$(coreXrayStrictConfigTestLog)
        if ! validateXrayConfigStrictWithBinary /etc/padm/xray/xray "${strictLog}"; then
            printf 'WARN:STRICT_FAIL %s\n' "${strictLog}"
        fi
        if xrayCompatibilityAuditHasFailures "${statusFile}"; then
            printf 'WARN:%s\n' "${summary}"
            printf 'LOG:%s\n' "$(xrayCompatibilityAuditLog)"
        elif [[ -s "${warnFile}" ]]; then
            printf 'WARN:%s\n' "${summary}"
        else
            printf 'PASS:%s\n' "${summary}"
        fi
    ) >/tmp/padm-validate-xray-compat.log 2>&1 || true

    if grep -q '^PASS:' /tmp/padm-validate-xray-compat.log; then
        pass "Xray 兼容体检通过"
    elif grep -q '^WARN:' /tmp/padm-validate-xray-compat.log; then
        warn "Xray 兼容体检发现需关注项：$(sed -n 's/^WARN://p' /tmp/padm-validate-xray-compat.log | head -n 1)"
        if grep -q '^LOG:' /tmp/padm-validate-xray-compat.log; then
            warn "Xray 兼容体检日志：$(sed -n 's/^LOG://p' /tmp/padm-validate-xray-compat.log | head -n 1)"
        fi
        if grep -q '^WARN:STRICT_FAIL ' /tmp/padm-validate-xray-compat.log; then
            warn "Xray 严格模式校验失败：$(sed -n 's/^WARN:STRICT_FAIL //p' /tmp/padm-validate-xray-compat.log | head -n 1)"
        fi
    else
        warn "Xray 兼容体检摘要执行失败，已跳过"
        cat /tmp/padm-validate-xray-compat.log 2>/dev/null || true
    fi
}

detect_package_family() {
    if [[ -f /etc/debian_version ]]; then
        printf 'apt'
    elif [[ -f /etc/redhat-release || -f /etc/centos-release ]]; then
        printf 'rpm'
    else
        printf 'unknown'
    fi
}

check_warp() {
    local packageFamily
    packageFamily=$(detect_package_family)
    if [[ "${packageFamily}" == "apt" ]]; then
        if [[ -f /etc/apt/sources.list.d/cloudflare-client.list ]]; then
            check_contains /etc/apt/sources.list.d/cloudflare-client.list 'signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring\.gpg' 'cloudflare apt 源使用 signed-by'
            check_contains /etc/apt/sources.list.d/cloudflare-client.list 'https://pkg\.cloudflareclient\.com/' 'cloudflare apt 源使用 https'
            check_file /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        else
            warn "可选 WARP apt 源缺失，跳过 WARP 源检查"
        fi
    elif [[ "${packageFamily}" == "rpm" ]]; then
        if [[ -f /etc/yum.repos.d/cloudflare-client.repo ]]; then
            check_contains /etc/yum.repos.d/cloudflare-client.repo 'pkg\.cloudflareclient\.com' 'cloudflare yum 源使用官方地址'
        else
            warn "可选 WARP yum 源缺失，跳过 WARP 源检查"
        fi
    else
        warn "未知发行版，跳过 WARP 源检查"
    fi

    if command -v warp-cli >/dev/null 2>&1; then
        pass "warp-cli 存在"
        warp-cli --version || true
    else
        warn "可选 WARP 未安装：warp-cli 缺失"
    fi
}

check_nginx_repo() {
    local packageFamily
    packageFamily=$(detect_package_family)
    if [[ "${packageFamily}" == "apt" ]]; then
        if [[ -f /etc/apt/sources.list.d/nginx.list ]]; then
            check_contains /etc/apt/sources.list.d/nginx.list 'signed-by=/usr/share/keyrings/nginx-archive-keyring\.gpg' 'nginx apt 源使用 signed-by'
            check_contains /etc/apt/sources.list.d/nginx.list 'https://nginx\.org/packages/' 'nginx apt 源使用 https'
            check_file /usr/share/keyrings/nginx-archive-keyring.gpg
        else
            warn "nginx apt 源缺失，跳过 nginx 源检查"
        fi
    elif [[ "${packageFamily}" == "rpm" ]]; then
        if [[ -f /etc/yum.repos.d/nginx.repo ]]; then
            check_contains /etc/yum.repos.d/nginx.repo 'nginx\.org/packages/' 'nginx yum 源使用官方地址'
        else
            warn "nginx yum 源缺失，跳过 nginx 源检查"
        fi
    else
        warn "未知发行版，跳过 nginx 源检查"
    fi
}

check_first_existing_file() {
    local label=$1
    local file

    shift
    for file in "$@"; do
        if [[ -f "${file}" ]]; then
            pass "${label}：${file}"
            return
        fi
    done
    warn "${label}缺失"
}

check_first_nonempty_dir() {
    local label=$1
    local dir

    shift
    for dir in "$@"; do
        if [[ -d "${dir}" ]] && find "${dir}" -type f -print -quit | grep -q .; then
            pass "${label}：${dir}"
            return
        fi
    done
    warn "${label}缺失"
}

check_subscription_files() {
    check_first_existing_file "订阅组配置存在" /etc/padm/subscribe_groups/groups.json
    check_first_nonempty_dir "默认订阅输出存在" /etc/padm/subscribe/default /etc/padm/subscribe_local/default
    check_first_nonempty_dir "sing-box 订阅输出存在" /etc/padm/subscribe/sing-box /etc/padm/subscribe_local/sing-box
}

check_fail2ban() {
    local jailFile=/etc/fail2ban/jail.d/padm.local
    local filterFile=/etc/fail2ban/filter.d/padm-control.conf
    local nginxScanFilterFile=/etc/fail2ban/filter.d/padm-nginx-scan-basic.conf
    local controlLog=/var/log/nginx/padm-control-access.log
    local nginxAccessLog=/var/log/nginx/access.log
    local enabledCount=0
    local controlEnabled=false
    local nginxScanSectionPresent=false
    local nginxScanEnabled=false
    local nginxScanRuntimeLog=

    if command -v fail2ban-client >/dev/null 2>&1; then
        pass "fail2ban 命令存在"
        if fail2ban-client -t >/tmp/padm-validate-fail2ban.log 2>&1; then
            pass "fail2ban 配置校验通过"
        else
            warn "fail2ban 配置校验未通过"
            cat /tmp/padm-validate-fail2ban.log
        fi
        check_service_active_optional fail2ban
        check_service_enabled fail2ban
    else
        warn "fail2ban 未安装，跳过防护校验"
        return
    fi

    if [[ -f "${jailFile}" ]]; then
        check_contains "${jailFile}" '^\[sshd\]' 'fail2ban jail 包含 sshd'
        check_contains "${jailFile}" '^\[padm-control\]' 'fail2ban jail 包含 padm-control'
        enabledCount=$(grep -Ec '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true[[:space:]]*$' "${jailFile}" 2>/dev/null || true)
        if [[ "${enabledCount}" =~ ^[0-9]+$ ]] && (( enabledCount > 0 )); then
            pass "fail2ban 已启用 ${enabledCount} 个 padm jail"
        else
            warn "fail2ban 当前未启用 padm jail"
        fi
        if check_fail2ban_jail_enabled "${jailFile}" padm-control; then
            controlEnabled=true
        fi
        if check_fail2ban_jail_has_section "${jailFile}" nginx-scan-basic; then
            nginxScanSectionPresent=true
            pass "fail2ban jail 包含 nginx-scan-basic"
            if check_fail2ban_jail_enabled "${jailFile}" nginx-scan-basic; then
                nginxScanEnabled=true
            fi
        else
            pass "nginx-scan-basic 当前未接入旧配置属可接受"
        fi
    else
        warn "fail2ban jail 文件缺失，可能当前处于 padm 防护停用状态"
    fi

    if [[ "${controlEnabled}" == "true" ]]; then
        if [[ -f "${filterFile}" ]]; then
            check_contains "${filterFile}" 's/control/' 'padm-control filter 匹配控制面路径'
        else
            warn "padm-control 已启用，但 filter 文件缺失"
        fi
        if [[ -e "${controlLog}" ]]; then
            pass "控制面专用访问日志存在：${controlLog}"
        else
            warn "padm-control 已启用，但控制面专用访问日志缺失：${controlLog}"
        fi
    elif [[ -f "${filterFile}" || -e "${controlLog}" ]]; then
        pass "padm-control 处于未启用状态，相关文件保留属可接受"
    fi

    if [[ "${nginxScanSectionPresent}" != "true" ]]; then
        pass "nginx-scan-basic 仍处于历史未接入状态"
    elif [[ "${nginxScanEnabled}" == "true" ]]; then
        if declare -F resolveSubscribeNginxAccessLogFile >/dev/null 2>&1; then
            nginxScanRuntimeLog=$(resolveSubscribeNginxAccessLogFile 2>/dev/null || true)
        fi
        if [[ -z "${nginxScanRuntimeLog}" ]]; then
            nginxScanRuntimeLog="${nginxAccessLog}"
        fi
        if [[ -f "${nginxScanFilterFile}" ]]; then
            check_contains "${nginxScanFilterFile}" 'wp-login\.php|\.env|phpmyadmin|actuator' 'nginx-scan-basic filter 匹配常见扫描路径'
        else
            warn "nginx-scan-basic 已启用，但 filter 文件缺失"
        fi
        if [[ -e "${nginxScanRuntimeLog}" ]]; then
            pass "Nginx 访问日志存在：${nginxScanRuntimeLog}"
        else
            warn "nginx-scan-basic 已启用，但访问日志缺失：${nginxScanRuntimeLog}"
        fi
    elif [[ -f "${nginxScanFilterFile}" ]]; then
        pass "nginx-scan-basic 处于默认关闭状态，扩展 filter 保留属可接受"
    else
        pass "nginx-scan-basic 默认关闭"
    fi
}

check_maintenance_summary() {
    if [[ -s /etc/padm/xray/geosite.dat && -s /etc/padm/xray/geoip.dat ]]; then
        pass "Xray Geo 文件齐全"
        if [[ -s /etc/padm/xray/geo.version ]]; then
            pass "Xray Geo 版本：$(tr -d '\r\n' </etc/padm/xray/geo.version)"
        else
            warn "Xray Geo 版本文件缺失：/etc/padm/xray/geo.version"
        fi
    else
        fail "Xray Geo 文件缺失"
    fi

    if find /etc/padm/tls -maxdepth 1 -type f -name '*.crt' -size +0c -print -quit 2>/dev/null | grep -q . &&
        find /etc/padm/tls -maxdepth 1 -type f -name '*.key' -size +0c -print -quit 2>/dev/null | grep -q .; then
        pass "TLS 证书文件存在"
    fi

    if [[ -f /etc/padm/tls/ssl_type ]]; then
        pass "TLS 类型记录存在"
    fi

    if [[ -f /etc/padm/install.sh ]]; then
        pass "padm 入口文件存在"
        if bash -n /etc/padm/install.sh >/dev/null 2>&1; then
            pass "padm 入口语法校验通过"
        else
            fail "padm 入口语法校验失败"
        fi
        if grep -q "ensureScriptModules" /etc/padm/install.sh; then
            pass "padm 入口包含 ensureScriptModules"
        else
            fail "padm 入口缺少 ensureScriptModules"
        fi
    else
        fail "padm 入口文件缺失"
    fi

    if crontab -l 2>/dev/null | grep -q "RenewTLS"; then
        pass "TLS 定时续签已配置"
    else
        warn "TLS 定时续签未配置"
    fi

    if crontab -l 2>/dev/null | grep -q "UpdateGeo"; then
        pass "Geo 自动更新已配置"
    else
        warn "Geo 自动更新未配置"
    fi
}

check_tcp_listen() {
    local port=$1

    if lsof -nP -i "tcp:${port}" 2>/dev/null | grep -q LISTEN; then
        return 0
    fi
    return 1
}

check_domain() {
    local domain=$1
    local http_code=

    if dig +short A "${domain}" | grep -E '^[0-9.]+$' >/dev/null 2>&1 || dig +short AAAA "${domain}" | grep ':' >/dev/null 2>&1; then
        pass "域名可解析：${domain}"
    else
        warn "域名不可解析：${domain}"
    fi

    http_code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "http://${domain}/" 2>/dev/null || true)
    if [[ "${http_code}" != "000" ]]; then
        pass "HTTP 可访问：${domain} (${http_code})"
    else
        warn "HTTP 不可访问：${domain}"
    fi

    if check_tcp_listen 443; then
        http_code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "https://${domain}/" 2>/dev/null || true)
        if [[ "${http_code}" != "000" ]]; then
            pass "HTTPS 可访问：${domain} (${http_code})"
        else
            warn "HTTPS 不可访问：${domain}"
        fi

        if openssl s_client -servername "${domain}" -connect "${domain}:443" </dev/null 2>/tmp/padm-validate-tls.log | openssl x509 -noout -subject -issuer >/tmp/padm-validate-cert.log 2>/dev/null; then
            pass "TLS 证书可读取：${domain}"
            cat /tmp/padm-validate-cert.log
        else
            warn "TLS 证书不可读取：${domain}"
            cat /tmp/padm-validate-tls.log
        fi
    else
        warn "本机未监听 443，跳过 HTTPS/TLS 检查；多端口 sing-box 场景可能正常"
    fi
}

main() {
    local online=false
    local domain=

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --online)
            online=true
            shift
            ;;
        *)
            domain=$1
            shift
            ;;
        esac
    done

    check_command curl
    check_command jq
    check_command lsof
    check_command systemctl
    check_nginx_repo
    check_warp

    local has_xray=false
    local has_sing_box=false
    if [[ -x /etc/padm/xray/xray ]]; then
        has_xray=true
    fi
    if [[ -x /etc/padm/sing-box/sing-box ]]; then
        has_sing_box=true
    fi
    if [[ "${has_xray}" == "false" && "${has_sing_box}" == "false" ]]; then
        fail "未找到支持的核心二进制"
    fi
    check_xray
    check_sing_box
    check_xray_compatibility_audit
    check_sing_box_compatibility_audit
    check_fail2ban

    check_subscription_files
    check_maintenance_summary
    check_no_pattern /etc/padm 'sshpass' '仓库不应包含临时辅助工具'
    if [[ -n "${domain}" ]]; then
        if [[ "${online}" == "true" ]]; then
            check_command dig
            check_command openssl
            if command -v dig >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
                check_domain "${domain}"
            fi
        else
            warn "跳过 ${domain} 的在线域名检查；传入 --online 可启用 DNS/HTTP/HTTPS/TLS 探测"
        fi
    fi

    printf '\n汇总：PASS=%d WARN=%d FAIL=%d\n' "$passed" "$warned" "$failed"
    print_summary_card
    [[ "$failed" -eq 0 ]]
}

main "$@"
