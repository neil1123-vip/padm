#!/usr/bin/env bash

passed=0
failed=0
warned=0

pass() {
    passed=$((passed + 1))
    printf '[PASS] %s\n' "$1"
}

fail() {
    failed=$((failed + 1))
    printf '[FAIL] %s\n' "$1"
}

warn() {
    warned=$((warned + 1))
    printf '[WARN] %s\n' "$1"
}

check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        pass "command exists: $1"
    else
        fail "command missing: $1"
    fi
}

check_file() {
    if [[ -f "$1" ]]; then
        pass "file exists: $1"
    else
        fail "file missing: $1"
    fi
}

check_optional_file() {
    if [[ -f "$1" ]]; then
        pass "file exists: $1"
    else
        warn "optional file missing: $1"
    fi
}

check_service_active() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl missing, skip service check: $1"
        return
    fi

    if systemctl is-active --quiet "$1"; then
        pass "service active: $1"
    else
        fail "service inactive: $1"
    fi
}

check_service_active_optional() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl missing, skip service check: $1"
        return
    fi

    if systemctl is-active --quiet "$1"; then
        pass "service active: $1"
    else
        warn "service inactive: $1"
    fi
}

check_service_enabled() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl missing, skip service enabled check: $1"
        return
    fi

    if systemctl is-enabled --quiet "$1"; then
        pass "service enabled: $1"
    else
        warn "service not enabled: $1"
    fi
}

check_no_pattern() {
    local path=$1
    local pattern=$2
    local label=$3

    if [[ ! -e "${path}" ]]; then
        warn "path missing, skip pattern check: ${path}"
        return
    fi

    : > /tmp/padm-validate-grep.log
    find "${path}" -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.list' -o -name '*.service' \) ! -path '*/shell/validate_install.sh' -exec grep -H -E "${pattern}" {} + >/tmp/padm-validate-grep.log 2>/dev/null || true
    if [[ -s /tmp/padm-validate-grep.log ]]; then
        fail "${label}: found forbidden pattern"
        cat /tmp/padm-validate-grep.log
    else
        pass "${label}: no forbidden pattern"
    fi
}

check_contains() {
    local file=$1
    local pattern=$2
    local label=$3

    if [[ ! -f "${file}" ]]; then
        fail "${label}: file missing ${file}"
        return
    fi

    if grep -E "${pattern}" "${file}" >/dev/null 2>&1; then
        pass "${label}"
    else
        fail "${label}: pattern missing in ${file}"
    fi
}

check_apt_update() {
    warn "skip apt update in validation; stateful online refresh is not part of read-only verification"
}

check_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        pass "nginx exists: $(nginx -v 2>&1)"
        if nginx -t >/tmp/padm-validate-nginx.log 2>&1; then
            pass "nginx config test succeeds"
        else
            fail "nginx config test failed"
            cat /tmp/padm-validate-nginx.log
        fi
        check_service_active nginx
        check_service_enabled nginx
    else
        warn "nginx missing, skip nginx checks"
    fi
}

check_xray() {
    if [[ -x /etc/padm/xray/xray ]]; then
        pass "xray binary executable"
        /etc/padm/xray/xray --version | head -n 1
        check_optional_file /etc/padm/xray/geoip.dat
        check_optional_file /etc/padm/xray/geosite.dat
        check_service_active xray.service
        check_service_enabled xray.service
    else
        warn "xray binary missing or not executable"
    fi
}

check_sing_box() {
    if [[ -x /etc/padm/sing-box/sing-box ]]; then
        pass "sing-box binary executable"
        /etc/padm/sing-box/sing-box version | head -n 1
        check_service_active_optional sing-box.service
        check_service_enabled sing-box.service
    else
        warn "sing-box binary missing or not executable"
    fi
}

check_warp() {
    if [[ -f /etc/apt/sources.list.d/cloudflare-client.list ]]; then
        check_contains /etc/apt/sources.list.d/cloudflare-client.list 'signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring\.gpg' 'cloudflare apt source uses signed-by'
        check_contains /etc/apt/sources.list.d/cloudflare-client.list 'https://pkg\.cloudflareclient\.com/' 'cloudflare apt source uses https'
        check_file /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    else
        warn "cloudflare apt source missing, skip WARP source check"
    fi

    if command -v warp-cli >/dev/null 2>&1; then
        pass "warp-cli exists"
        warp-cli --version || true
    else
        warn "warp-cli missing"
    fi
}

check_nginx_repo() {
    if [[ -f /etc/apt/sources.list.d/nginx.list ]]; then
        check_contains /etc/apt/sources.list.d/nginx.list 'signed-by=/usr/share/keyrings/nginx-archive-keyring\.gpg' 'nginx apt source uses signed-by'
        check_contains /etc/apt/sources.list.d/nginx.list 'https://nginx\.org/packages/' 'nginx apt source uses https'
        check_file /usr/share/keyrings/nginx-archive-keyring.gpg
    else
        warn "nginx apt source missing, skip nginx source check"
    fi
}

check_subscription_files() {
    check_optional_file /etc/padm/subscribe/default/subscribe.conf
    check_optional_file /etc/padm/subscribe/default/index.html
    check_optional_file /etc/padm/subscribe_groups/groups.json
    check_optional_file /etc/padm/subscribe_local/default/default.conf
}

check_domain() {
    local domain=$1
    local http_code=

    if dig +short A "${domain}" | grep -E '^[0-9.]+$' >/dev/null 2>&1 || dig +short AAAA "${domain}" | grep ':' >/dev/null 2>&1; then
        pass "domain resolves: ${domain}"
    else
        warn "domain does not resolve: ${domain}"
    fi

    http_code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "http://${domain}/" 2>/dev/null || true)
    if [[ "${http_code}" != "000" ]]; then
        pass "http reachable: ${domain} (${http_code})"
    else
        warn "http unreachable: ${domain}"
    fi

    http_code=$(curl -k -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "https://${domain}/" 2>/dev/null || true)
    if [[ "${http_code}" != "000" ]]; then
        pass "https reachable: ${domain} (${http_code})"
    else
        warn "https unreachable: ${domain}"
    fi

    if openssl s_client -servername "${domain}" -connect "${domain}:443" </dev/null 2>/tmp/padm-validate-tls.log | openssl x509 -noout -subject -issuer >/tmp/padm-validate-cert.log 2>/dev/null; then
        pass "tls certificate readable: ${domain}"
        cat /tmp/padm-validate-cert.log
    else
        warn "tls certificate unreadable: ${domain}"
        cat /tmp/padm-validate-tls.log
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
        fail "no supported core binary found"
    fi
    check_xray
    check_sing_box

    check_subscription_files
    check_no_pattern /etc/padm 'sshpass' 'repo should not contain temporary helpers'
    if [[ -n "${domain}" ]]; then
        if [[ "${online}" == "true" ]]; then
            check_command dig
            check_command openssl
            if command -v dig >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
                check_domain "${domain}"
            fi
        else
            warn "skip online domain checks for ${domain}; pass --online to enable DNS/HTTP/HTTPS/TLS probes"
        fi
    fi

    printf '\nSummary: PASS=%d WARN=%d FAIL=%d\n' "$passed" "$warned" "$failed"
    [[ "$failed" -eq 0 ]]
}

main "$@"
