#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase4.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
CONTROL_LOG="${TEST_ROOT}/control.log"
DOCKER_ROOT="${TEST_ROOT}/state"
NATIVE_ROOT="${TEST_ROOT}/native"
CLI_DIR="${TEST_ROOT}/bin-installed"
IMAGE_DIGEST=$(printf '1%.0s' {1..64})
OPS_IMAGE="ghcr.io/example/padm-ops:test@sha256:${IMAGE_DIGEST}"
mkdir -p "${MOCK_BIN}" "${NATIVE_ROOT}" "${TEST_ROOT}/systemd"
cleanup() {
    if [[ "${PADM_TEST_KEEP:-0}" == "1" ]]; then
        printf 'docker-phase4-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

fail() {
    printf 'docker-phase4-regression-fail: %s\n' "$*" >&2
    exit 1
}

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in -s) printf 'Linux\n' ;; -m) printf 'x86_64\n' ;; *) printf 'Linux\n' ;; esac
EOF
cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-u" ]] && printf '0\n'
EOF
cat >"${MOCK_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--format=%a" ]]; then printf '600\n'; else exec /usr/bin/stat "$@"; fi
EOF
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
case "${1:-}" in
info)
    case "${3:-}" in
    '{{.OSType}}') printf 'linux\n' ;;
    '{{.Architecture}}') printf 'x86_64\n' ;;
    '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
    esac
    ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
pull) ;;
compose)
    if [[ "${2:-}" == version ]]; then printf 'v2.29.1\n'; exit 0; fi
    if [[ " ${*} " == *' up -d '* && "${FAKE_DOCKER_MODE:-ok}" == fail-next-up &&
        ! -e "${FAKE_DOCKER_FAIL_ONCE:?}" ]]; then
        : >"${FAKE_DOCKER_FAIL_ONCE}"
        exit 1
    fi
    ;;
ps) ;;
run)
    if [[ " ${*} " == *'ssl.cert_time_to_seconds'* ]]; then
        [[ "${FAKE_DOCKER_MODE:-ok}" != tls-validity-fail ]]
        exit $?
    fi
    if [[ " ${*} " == *' --entrypoint python3 '* ]]; then
        printf '192.0.2.1\tAS64500\tExampleNet\n'
    elif [[ " ${*} " == *' tls ping '* ]]; then
        if [[ " ${*} " == *' cloudflare.com:443 '* ]]; then
            printf 'Pinging with SNI\nHandshake failure: certificate does not match SNI\n'
        else
            printf 'Pinging with SNI\nHandshake succeeded\nTLS Version:\tTLS 1.3\n'
        fi
    fi
    ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/uname" "${MOCK_BIN}/id" "${MOCK_BIN}/stat" "${MOCK_BIN}/docker"
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
chmod 0755 "${MOCK_BIN}/systemctl"
cp "${MOCK_BIN}/systemctl" "${MOCK_BIN}/nsenter"

runControl() {
    local expected=$1 name=$2 actual=0
    local -a command=(bash -u "${PROJECT_ROOT}/install-docker.sh")
    shift 2
    if [[ "${1:-}" == configure ]]; then
        set -- "$@" --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
            --control-bundle "${CONFIGURE_CONTROL}"
    elif [[ "${1:-}" == apply-staged ]]; then
        shift
        command=(bash -u -c '
          source "$1"
          dockerHostPreflight || exit 10
          dockerLockInstalledDeployment || exit $?
          dockerConfigureReleasePrepare "$2" "$3" "$4" || exit $?
          dockerConfigureApply "$5" "$6" "$7"
          status=$?
          dockerReleaseDeploymentLock
          dockerCleanupStagedBundle
          dockerManifestCleanup
          exit "${status}"
        ' test "${PROJECT_ROOT}/install-docker.sh"
            "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}")
    fi
    : >"${CONTROL_LOG}"
    env MSYS=winsymlinks:sys PATH="${MOCK_BIN}:${PATH}" DOCKER_HOST= \
        PADM_DOCKER_INSTALL_DIR="${DOCKER_ROOT}" PADM_NATIVE_INSTALL_DIR="${NATIVE_ROOT}" \
        PADM_DOCKER_BIN_DIR="${CLI_DIR}" PADM_DOCKER_LOCK_TIMEOUT=2 \
        PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd" \
        PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_SKIP_CHOWN=1 \
        FAKE_DOCKER_LOG="${DOCKER_LOG}" FAKE_DOCKER_MODE="${FAKE_DOCKER_MODE:-ok}" \
        FAKE_DOCKER_FAIL_ONCE="${TEST_ROOT}/fail-once" \
        "${command[@]}" "$@" >"${CONTROL_LOG}" 2>&1 || actual=$?
    if [[ "${actual}" -ne "${expected}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
        fail "${name}: expected rc=${expected}, got rc=${actual}"
    fi
}

imageReference() { printf 'ghcr.io/example/padm-%s:test@sha256:%s' "$1" "${IMAGE_DIGEST}"; }

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/tests/configure-fixture.sh"
dockerConfigureTestFixture

writeRealitySpec() {
    local target=$1 core=$2
    jq -n --arg core "${core}" --arg digest "${IMAGE_DIGEST}" \
        --arg manifestSha "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
        --arg xray "$(imageReference xray)" --arg singbox "$(imageReference sing-box)" \
        --arg nginx "$(imageReference nginx)" --arg ops "${OPS_IMAGE}" --arg net "$(imageReference net)" '
      {
        schema_version: 1,
        release: {version: "3.1.8", manifest_sha256: $manifestSha, signature_identity: $identity},
        core: {type: $core, protocols: [{
          id: 1, server: "proxy.example.com", public_port: 24443,
          address_families: ["ipv4", "ipv6"], name: "main",
          uuid: "11111111-1111-4111-8111-111111111111",
          reality: {server_name: "www.example.com", target_host: "www.example.com", target_port: 443,
            private_key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
            public_key: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
            short_id: "6ba85179e30d4fc2"}
        }]},
        tls: null,
        subscription: {enabled: false, token: "0123456789abcdef"},
        images: {xray: $xray, "sing-box": $singbox, nginx: $nginx, ops: $ops, net: $net},
        host_integrations: []
      }
    ' >"${target}"
}

writeWebSocketSpec() {
    local target=$1
    writeRealitySpec "${target}" xray
    jq '
      .core.protocols = [{id: 21, server: "proxy.example.com", public_port: 24444,
        address_families: ["ipv4"], name: "main-ws",
        uuid: "22222222-2222-4222-8222-222222222222",
        websocket: {domain: "proxy.example.com", path: "websocket_path"}}] |
      .tls = {domain: "proxy.example.com"}
    ' "${target}" >"${target}.tmp"
    mv -- "${target}.tmp" "${target}"
}

REALITY_XRAY="${TEST_ROOT}/reality-xray.json"
REALITY_SING="${TEST_ROOT}/reality-sing.json"
WIREGUARD_SPEC="${TEST_ROOT}/wireguard.json"
FAIL2BAN_SPEC="${TEST_ROOT}/fail2ban.json"
TUN_SPEC="${TEST_ROOT}/tun.json"
TPROXY_SPEC="${TEST_ROOT}/tproxy.json"
INVALID_SPEC="${TEST_ROOT}/invalid.json"
writeRealitySpec "${REALITY_XRAY}" xray
writeRealitySpec "${REALITY_SING}" sing-box
writeWebSocketSpec "${FAIL2BAN_SPEC}"
jq '.host_integrations = [{type: "wireguard", profile: "net-wireguard", firewall_rules: [],
  devices: ["wg-padm"], schedules: [], settings: {config_file: "wg-padm.conf", interface: "wg-padm"}}]' \
  "${REALITY_XRAY}" >"${WIREGUARD_SPEC}"
jq '.host_integrations = [{type: "fail2ban", profile: "net-fail2ban", firewall_rules: ["DOCKER-USER"],
  devices: [], schedules: [], settings: {log_file: "access.log", ports: [24444],
  max_retry: 6, find_time: 600, ban_time: 3600}}]' "${FAIL2BAN_SPEC}" >"${FAIL2BAN_SPEC}.tmp"
mv -- "${FAIL2BAN_SPEC}.tmp" "${FAIL2BAN_SPEC}"
jq '.host_integrations = [{type: "tun", profile: "net-transparent",
  firewall_rules: ["sing-box-auto-redirect"], devices: ["/dev/net/tun"], schedules: [],
  settings: {interface: "padm-tun", address: "198.18.0.1/30"}}]' "${REALITY_SING}" >"${TUN_SPEC}"
jq '.host_integrations = [{type: "tproxy", profile: "net-transparent",
  firewall_rules: ["padm-tproxy"], devices: [], schedules: [], settings: {port: 31298, mark: 129}}]' \
  "${REALITY_XRAY}" >"${TPROXY_SPEC}"
jq --slurpfile integration "${TPROXY_SPEC}" '.host_integrations = $integration[0].host_integrations' \
  "${FAIL2BAN_SPEC}" >"${INVALID_SPEC}"

runControl 0 install install --source "${PROJECT_ROOT}"
mkdir -p "${DOCKER_ROOT}/secrets/net/wireguard"
cat >"${DOCKER_ROOT}/secrets/net/wireguard/wg-padm.conf" <<'EOF'
[Interface]
PrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
Address = 10.23.0.1/24
ListenPort = 51820

[Peer]
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 10.23.0.2/32
EOF
chmod 0600 "${DOCKER_ROOT}/secrets/net/wireguard/wg-padm.conf"

: >"${DOCKER_LOG}"
for field in '.release.signature_identity = "untrusted"' '.images.xray |= sub("1$"; "2")'; do
    jq "${field}" "${WIREGUARD_SPEC}" >"${TEST_ROOT}/untrusted.json"
    runControl 16 untrusted-input configure --spec "${TEST_ROOT}/untrusted.json"
    [[ ! -e "${DOCKER_ROOT}/deployment.json" ]] || fail 'untrusted release inputs changed deployment'
done
runControl 0 wireguard configure --spec "${WIREGUARD_SPEC}"
cmp -s "${WIREGUARD_SPEC}" "${DOCKER_ROOT}/config/spec.json" || fail 'complete spec was not persisted'
if [[ "$(/usr/bin/uname -s)" == Linux ]]; then
    [[ "$(/usr/bin/stat --format=%a "${DOCKER_ROOT}/config/spec.json")" == 600 ]] ||
        fail 'complete spec permissions are not 0600'
fi
jq -e 'all(.services[].volumes[]?; .source != "${PADM_DOCKER_ROOT}/config" and
  .source != "${PADM_DOCKER_ROOT}/config/spec.json")' "${DOCKER_ROOT}/compose.json" >/dev/null ||
    fail 'complete spec is mounted into a container'
jq -e '
  (.compose.profiles | index("net-wireguard")) != null and
  any(.listeners[]; .service == "net-wireguard" and .public_port == 51820 and .transport == "udp") and
  .host_integrations[0].settings.interface == "wg-padm"
' "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'WireGuard deployment state is wrong'
jq -e '
  .services["net-wireguard"].network_mode == "host" and
  .services["net-wireguard"].cap_add == ["NET_ADMIN"] and
  ((.services.xray.cap_add // []) | length) == 0
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'WireGuard privilege boundary is wrong'
grep -q 'net-wireguard preflight wireguard' "${DOCKER_LOG}" || fail 'WireGuard preflight was not called'

CERT_FILE="${TEST_ROOT}/proxy.example.com.crt"
KEY_FILE="${TEST_ROOT}/proxy.example.com.key"
printf 'fake-certificate\n' >"${CERT_FILE}"
printf 'fake-private-key\n' >"${KEY_FILE}"
chmod 0600 "${KEY_FILE}"
runControl 0 tls-install tls install --domain proxy.example.com --cert "${CERT_FILE}" \
    --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
BEFORE_TLS_RECONFIGURE=$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)
FAKE_DOCKER_MODE=tls-validity-fail runControl 15 reject-expired-candidate configure --spec "${FAIL2BAN_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${BEFORE_TLS_RECONFIGURE}" ]] ||
    fail 'invalid certificate lifetime changed deployment'
: >"${DOCKER_LOG}"
runControl 0 fail2ban configure --spec "${FAIL2BAN_SPEC}"
grep -q 'access_log /var/log/nginx/access.log combined;' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Nginx real-source access log was not enabled'
grep -q 'DOCKER-USER' "${DOCKER_ROOT}/config/net/fail2ban/padm-docker-user.conf" ||
    fail 'Fail2ban action does not own DOCKER-USER'
grep -q -- '--ctorigdstport <port>' "${DOCKER_ROOT}/config/net/fail2ban/padm-docker-user.conf" ||
    fail 'Fail2ban does not match the original published port after Docker DNAT'
grep -q '^logtarget = STDOUT$' "${DOCKER_ROOT}/config/net/fail2ban/fail2ban.local" ||
    fail 'Fail2ban does not log to stdout on a read-only root'
jq -e '
  .services["net-fail2ban"].network_mode == "host" and
  .services["net-fail2ban"].cap_add == ["NET_ADMIN"] and
  ((.services.nginx.cap_add // []) | length) == 0
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'Fail2ban privilege boundary is wrong'
grep -q 'net-fail2ban preflight fail2ban 24444' "${DOCKER_LOG}" || fail 'Fail2ban preflight was not called'

jq '.core.protocols[0].public_port = 25444' "${FAIL2BAN_SPEC}" >"${TEST_ROOT}/fail2ban-edit.json"
runControl 15 reject-fail2ban-port-edit edit --spec "${TEST_ROOT}/fail2ban-edit.json" --preview
grep -qF '带 Fail2ban 的 WS 入口端口需联动封禁规则' "${CONTROL_LOG}" ||
    fail 'Fail2ban port edit did not expose its unsupported coordinated rule change'
cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'rejected Fail2ban port edit changed the managed spec'

FAIL2BAN_HASH=$(sha256sum "${DOCKER_ROOT}/config/net/fail2ban/padm.local" | cut -d ' ' -f 1)
DEPLOYMENT_HASH=$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)
SPEC_HASH=$(sha256sum "${DOCKER_ROOT}/config/spec.json" | cut -d ' ' -f 1)
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up runControl 14 rollback-net configure --spec "${TPROXY_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/config/net/fail2ban/padm.local" | cut -d ' ' -f 1)" == "${FAIL2BAN_HASH}" ]] ||
    fail 'failed deployment did not restore config/net'
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'failed deployment did not restore deployment state'
[[ "$(sha256sum "${DOCKER_ROOT}/config/spec.json" | cut -d ' ' -f 1)" == "${SPEC_HASH}" ]] ||
    fail 'failed deployment did not restore complete spec'

# 首配证书和 ACME 数据只暂存，健康检查失败时一起恢复。
STAGED_TLS="${DOCKER_ROOT}/.staged-tls"
STAGED_ACME="${DOCKER_ROOT}/.staged-acme"
mkdir -p "${STAGED_TLS}" "${STAGED_ACME}" "${DOCKER_ROOT}/data/acme"
printf 'old-acme-account\n' >"${DOCKER_ROOT}/data/acme/account"
cp -a "${DOCKER_ROOT}/secrets/tls/." "${STAGED_TLS}/"
printf 'new-certificate\n' >"${STAGED_TLS}/proxy.example.com.crt"
printf 'new-private-key\n' >"${STAGED_TLS}/proxy.example.com.key"
printf 'new-acme-account\n' >"${STAGED_ACME}/account"
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up runControl 14 rollback-staged apply-staged \
    "${FAIL2BAN_SPEC}" "${STAGED_TLS}" "${STAGED_ACME}"
grep -qxF fake-certificate "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'failed deployment committed candidate TLS'
grep -qxF old-acme-account "${DOCKER_ROOT}/data/acme/account" ||
    fail 'failed deployment committed candidate ACME data'
[[ "$(sha256sum "${DOCKER_ROOT}/config/spec.json" | cut -d ' ' -f 1)" == "${SPEC_HASH}" ]] ||
    fail 'failed staged deployment did not restore complete spec'
runControl 0 commit-staged apply-staged "${FAIL2BAN_SPEC}" "${STAGED_TLS}" "${STAGED_ACME}"
grep -qxF new-certificate "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'successful deployment did not commit candidate TLS'
grep -qxF new-acme-account "${DOCKER_ROOT}/data/acme/account" ||
    fail 'successful deployment did not commit candidate ACME data'

: >"${DOCKER_LOG}"
runControl 0 tun configure --spec "${TUN_SPEC}"
jq -e '
  .services["sing-box"].network_mode == "host" and .services["sing-box"].user == "0:0" and
  .services["sing-box"].cap_add == ["NET_ADMIN"] and
  .services["sing-box"].devices[0].source == "/dev/net/tun" and
  (.services | has("net-transparent") | not) and .services["net-tun-check"].restart == "no"
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'TUN service boundary is wrong'
jq -e 'any(.inbounds[]; .type == "tun" and .interface_name == "padm-tun" and .dns_mode == "disabled" and .auto_redirect == true)' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail 'sing-box TUN inbound is wrong'
grep -q 'net-tun-check preflight tun' "${DOCKER_LOG}" || fail 'TUN preflight was not called'

: >"${DOCKER_LOG}"
runControl 0 tproxy configure --spec "${TPROXY_SPEC}"
jq -e '
  .services.xray.network_mode == "host" and .services.xray.cap_add == ["NET_ADMIN"] and
  ((.services.xray.devices // []) | length) == 0 and
  .services["net-transparent"].network_mode == "host" and
  .services["net-transparent"].cap_add == ["NET_ADMIN"] and
  all(.services[]; (.privileged // false) == false and ((.cap_add // []) | index("SYS_ADMIN")) == null)
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'TProxy privilege boundary is wrong'
jq -e 'any(.inbounds[]; .protocol == "dokodemo-door" and .port == 31298 and .settings.followRedirect == true)' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'Xray TProxy inbound is wrong'
jq -e '
  ([.listeners[] | select(.public_port == 31298) | .transport] | sort) == ["tcp", "udp"] and
  .host_integrations[0].firewall_rules == ["padm-tproxy"]
' "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'TProxy ownership state is wrong'
grep -q 'net-transparent preflight tproxy 31298 129' "${DOCKER_LOG}" || fail 'TProxy preflight was not called'

LIVE_HASH=$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)
runControl 15 reject-nginx-tproxy configure --spec "${INVALID_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${LIVE_HASH}" ]] ||
    fail 'invalid transparent topology changed live state'

sh -n "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" || fail 'net entrypoint syntax is invalid'
grep -q 'padm-tproxy' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" || fail 'TProxy rule ownership is missing'
printf 'docker-phase4-regression-ok\n'
