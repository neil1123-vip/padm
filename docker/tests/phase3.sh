#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase3.XXXXXX")
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
        printf 'docker-phase3-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

fail() {
    printf 'docker-phase3-regression-fail: %s\n' "$*" >&2
    exit 1
}

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
-s) printf 'Linux\n' ;;
-m) printf 'x86_64\n' ;;
*) printf 'Linux\n' ;;
esac
EOF

cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-u" ]] && printf '0\n'
EOF

cat >"${MOCK_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--format=%a" ]]; then
    printf '600\n'
else
    exec /usr/bin/stat "$@"
fi
EOF

cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
mode=${FAKE_DOCKER_MODE:-ok}
printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
case "${1:-}" in
info)
    if [[ "${2:-}" == "--format" ]]; then
        case "${3:-}" in
        '{{.OSType}}') printf 'linux\n' ;;
        '{{.Architecture}}') printf 'x86_64\n' ;;
        '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
        *) exit 1 ;;
        esac
    fi
    ;;
context)
    printf 'unix:///var/run/docker.sock\n'
    ;;
pull) ;;
compose)
    if [[ "${2:-}" == "version" ]]; then
        printf 'v2.29.1\n'
        exit 0
    fi
    if [[ " ${*} " == *' up -d '* && "${mode}" == "fail-next-up" &&
        ! -e "${FAKE_DOCKER_FAIL_ONCE:?}" ]]; then
        : >"${FAKE_DOCKER_FAIL_ONCE}"
        exit 1
    fi
    if [[ " ${*} " == *' run --rm --no-deps xray '* && "${mode}" == "core-validate-fail" ]]; then
        exit 1
    fi
    ;;
ps)
    ;;
run)
    if [[ " ${*} " == *'ssl.cert_time_to_seconds'* ]]; then
        [[ "${mode}" != "tls-validity-fail" ]]
        exit $?
    fi
    if [[ " ${*} " == *' --entrypoint python3 '* ]]; then
        if [[ "${mode}" == "reality-dns-failure" ]]; then
            exit 2
        elif [[ "${mode}" == "reality-asn-risk" ]]; then
            printf '203.0.113.35\tAS13335\tCloudflare\n'
        elif [[ "${mode}" == "reality-unknown-risk" ]]; then
            printf '192.0.2.1\tunknown\tunknown\n'
        else
            printf '192.0.2.1\tAS64500\tExampleNet\n'
        fi
        exit 0
    fi
    if [[ " ${*} " == *' tls ping '* ]]; then
        if [[ " ${*} " == *' cloudflare.com:443 '* ]]; then
            if [[ "${mode}" == "reality-sni-risk" ]]; then
                printf 'Pinging with SNI\nHandshake succeeded\nTLS Version:\tTLS 1.3\n'
            else
                printf 'Pinging with SNI\nHandshake failure: certificate does not match SNI\n'
            fi
        else
            printf 'Pinging with SNI\nHandshake succeeded\nTLS Version:\tTLS 1.3\n'
        fi
        exit 0
    fi
    output=
    fullchain=
    keyfile=
    previous=
    for argument in "$@"; do
        if [[ "${previous}" == "--volume" && "${argument}" == *:/var/lib/padm/tls-output ]]; then
            output=${argument%:/var/lib/padm/tls-output}
        elif [[ "${previous}" == "--fullchain-file" ]]; then
            fullchain=${argument}
        elif [[ "${previous}" == "--key-file" ]]; then
            keyfile=${argument}
        fi
        previous=${argument}
    done
    if [[ -n "${output}" && -n "${fullchain}" && -n "${keyfile}" ]]; then
        printf 'fake-acme-certificate\n' >"${output}/${fullchain##*/}"
        printf 'fake-acme-private-key\n' >"${output}/${keyfile##*/}"
        chmod 0600 "${output}/${keyfile##*/}"
    fi
    [[ "${mode}" != "tls-validate-fail" ]]
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
    shift 2
    if [[ "${1:-}" == configure ]]; then
        set -- "$@" --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
            --control-bundle "${CONFIGURE_CONTROL}"
    fi
    : >"${CONTROL_LOG}"
    env \
        MSYS=winsymlinks:sys \
        PATH="${MOCK_BIN}:${PATH}" \
        DOCKER_HOST= \
        PADM_DOCKER_INSTALL_DIR="${DOCKER_ROOT}" \
        PADM_NATIVE_INSTALL_DIR="${NATIVE_ROOT}" \
        PADM_DOCKER_BIN_DIR="${CLI_DIR}" \
        PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd" \
        PADM_DOCKER_LOCK_TIMEOUT=2 \
        PADM_DOCKER_HEALTH_TIMEOUT=1 \
        PADM_DOCKER_SKIP_CHOWN=1 \
        FAKE_DOCKER_LOG="${DOCKER_LOG}" \
        FAKE_DOCKER_MODE="${FAKE_DOCKER_MODE:-ok}" \
        FAKE_DOCKER_FAIL_ONCE="${TEST_ROOT}/fail-once" \
        bash -u "${PROJECT_ROOT}/install-docker.sh" "$@" >"${CONTROL_LOG}" 2>&1 || actual=$?
    if [[ "${actual}" -ne "${expected}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
        fail "${name}: expected rc=${expected}, got rc=${actual}"
    fi
}

imageReference() {
    printf 'ghcr.io/example/padm-%s:test@sha256:%s' "$1" "${IMAGE_DIGEST}"
}

# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/tests/configure-fixture.sh"
dockerConfigureTestFixture

writeRealitySpec() {
    local target=$1 core=$2 accountName=$3 port=${4:-24443}
    jq -n \
        --arg core "${core}" \
        --arg name "${accountName}" \
        --arg digest "${IMAGE_DIGEST}" \
        --arg manifestSha "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
        --arg xray "$(imageReference xray)" \
        --arg singbox "$(imageReference sing-box)" \
        --arg nginx "$(imageReference nginx)" \
        --arg ops "${OPS_IMAGE}" \
        --arg net "$(imageReference net)" \
        --argjson port "${port}" '
      {
        schema_version: 1,
        release: {
          version: "3.1.8",
          manifest_sha256: $manifestSha,
          signature_identity: $identity
        },
        core: {
          type: $core,
          protocols: [{
            id: 1,
            server: "proxy.example.com",
            public_port: $port,
            address_families: ["ipv4", "ipv6"],
            name: $name,
            uuid: "11111111-1111-4111-8111-111111111111",
            reality: {
              server_name: "www.example.com",
              target_host: "www.example.com",
              target_port: 443,
              private_key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
              public_key: "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
              short_id: "6ba85179e30d4fc2"
            }
          }]
        },
        tls: null,
        subscription: {enabled: false, token: "0123456789abcdef"},
        images: {xray: $xray, "sing-box": $singbox, nginx: $nginx, ops: $ops, net: $net},
        host_integrations: []
      }
    ' >"${target}"
}

writeWebSocketSpec() {
    local target=$1
    jq -n \
        --arg digest "${IMAGE_DIGEST}" \
        --arg manifestSha "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" \
        --arg xray "$(imageReference xray)" \
        --arg singbox "$(imageReference sing-box)" \
        --arg nginx "$(imageReference nginx)" \
        --arg ops "${OPS_IMAGE}" \
        --arg net "$(imageReference net)" '
      {
        schema_version: 1,
        release: {
          version: "3.1.8",
          manifest_sha256: $manifestSha,
          signature_identity: $identity
        },
        core: {
          type: "xray",
          protocols: [{
            id: 21,
            server: "proxy.example.com",
            public_port: 24444,
            address_families: ["ipv4"],
            name: "main-ws",
            uuid: "22222222-2222-4222-8222-222222222222",
            websocket: {domain: "proxy.example.com", path: "websocket_path"}
          }]
        },
        tls: {domain: "proxy.example.com"},
        subscription: {enabled: true, token: "0123456789abcdef"},
        images: {xray: $xray, "sing-box": $singbox, nginx: $nginx, ops: $ops, net: $net},
        host_integrations: []
      }
    ' >"${target}"
}

REALITY_XRAY_SPEC="${TEST_ROOT}/xray.json"
REALITY_SINGBOX_SPEC="${TEST_ROOT}/sing-box.json"
REALITY_RELAY_SPEC="${TEST_ROOT}/reality-relay.json"
WS_SPEC="${TEST_ROOT}/ws.json"
MIXED_WS_SPEC="${TEST_ROOT}/mixed-ws.json"
UNSUPPORTED_SPEC="${TEST_ROOT}/unsupported.json"
ROLLBACK_SPEC="${TEST_ROOT}/rollback.json"
writeRealitySpec "${REALITY_XRAY_SPEC}" xray main-xray
writeRealitySpec "${REALITY_SINGBOX_SPEC}" sing-box main-sing-box
jq '.core.protocols[0].reality.target_host = "WWW.JAVA.COM"' "${REALITY_XRAY_SPEC}" >"${REALITY_RELAY_SPEC}"
writeWebSocketSpec "${WS_SPEC}"
jq --slurpfile reality "${REALITY_XRAY_SPEC}" '.core.protocols += $reality[0].core.protocols' \
    "${WS_SPEC}" >"${MIXED_WS_SPEC}"
jq '.core.protocols[0].id = 3' "${REALITY_XRAY_SPEC}" >"${UNSUPPORTED_SPEC}"
writeRealitySpec "${ROLLBACK_SPEC}" xray changed-after-failure 24444

SUBSCRIPTION_UNIT_ROOT="${TEST_ROOT}/subscription-unit"
mkdir -p "${SUBSCRIPTION_UNIT_ROOT}"
printf 'vless://unit-test\n' >"${SUBSCRIPTION_UNIT_ROOT}/0123456789abcdef"
PYTHONDONTWRITEBYTECODE=1 python3 - "${PROJECT_ROOT}/docker/images/ops/control_server.py" "${SUBSCRIPTION_UNIT_ROOT}" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("padm_control_server", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert module.read_subscription(sys.argv[2], "0123456789abcdef") == b"vless://unit-test\n"
assert module.TOKEN.fullmatch("0123456789abcdef")
assert not module.TOKEN.fullmatch("../escape")
PY

runControl 0 install install --source "${PROJECT_ROOT}"
runControl 0 unconfigured-status status
grep -qxF 'configured=no' "${CONTROL_LOG}" || fail 'fresh install did not report configured=no'

: >"${DOCKER_LOG}"
runControl 0 configure-xray configure --spec "${REALITY_XRAY_SPEC}"
jq -e '.core.type == "xray" and .core.protocol_ids == [1] and .compose.profiles == ["core-xray"]' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'Xray deployment state is wrong'
jq -e '.inbounds[0].streamSettings.security == "reality"' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || {
    jq '.inbounds[0]' "${DOCKER_ROOT}/config/xray/config.json" >&2 || true
    fail 'Xray Reality config is wrong'
}
jq -e '(.services | keys | sort) == ["acme", "xray"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'Xray Compose services are wrong'
grep -q ' run --rm --no-deps xray -test -confdir /etc/padm/xray' "${DOCKER_LOG}" ||
    fail 'Xray candidate was not validated in its image'

runControl 15 reject-reality-static-relay configure --spec "${REALITY_RELAY_SPEC}"
grep -qF '命中已知 CDN 中继风险域名' "${CONTROL_LOG}" || fail 'known relay Reality target was not rejected'
FAKE_DOCKER_MODE=reality-asn-risk runControl 15 reject-reality-as13335 configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '命中 Cloudflare AS13335' "${CONTROL_LOG}" || fail 'AS13335 Reality target was not rejected'
FAKE_DOCKER_MODE=reality-sni-risk runControl 15 reject-reality-cloudflare-sni configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '可响应 cloudflare.com SNI' "${CONTROL_LOG}" || fail 'Cloudflare SNI relay was not rejected'
FAKE_DOCKER_MODE=reality-unknown-risk runControl 15 reject-reality-unknown configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '风险检测不完整' "${CONTROL_LOG}" || fail 'unknown Reality target risk was not rejected'
FAKE_DOCKER_MODE=reality-dns-failure runControl 15 reject-reality-dns-failure configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '目标地址解析失败' "${CONTROL_LOG}" || fail 'partial DNS failure was not rejected'
jq -e '.core.type == "xray" and .core.protocol_ids == [1]' "${DOCKER_ROOT}/deployment.json" >/dev/null ||
    fail 'rejected Reality target changed the live deployment'

runControl 0 configure-sing-box configure --spec "${REALITY_SINGBOX_SPEC}"
jq -e '.core.type == "sing-box" and .core.protocol_ids == [1]' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'sing-box deployment state is wrong'
jq -e '.inbounds[0].type == "vless" and .inbounds[0].tls.reality.enabled == true' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail 'sing-box Reality config is wrong'
[[ ! -s "${DOCKER_ROOT}/config/xray/config.json" ]] || fail 'old Xray config survived core switch'

CERT_FILE="${TEST_ROOT}/proxy.example.com.crt"
KEY_FILE="${TEST_ROOT}/proxy.example.com.key"
printf 'fake-certificate\n' >"${CERT_FILE}"
printf 'fake-private-key\n' >"${KEY_FILE}"
chmod 0600 "${KEY_FILE}"
runControl 0 tls-install tls install --domain proxy.example.com --cert "${CERT_FILE}" \
    --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
[[ -f "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ]] || fail 'TLS certificate was not installed'

runControl 0 configure-websocket configure --spec "${WS_SPEC}"
jq -e '(.compose.profiles | sort) == ["core-xray", "nginx", "subscription"]' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'Nginx profiles are wrong'
grep -q 'proxy_pass http://xray:31297;' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Nginx did not proxy the WebSocket backend'
grep -q 'proxy_read_timeout 5d;' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Nginx WebSocket read timeout is missing'
! grep -q 'proxy_send_timeout' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Nginx WebSocket send timeout should use the default'
grep -q 'vless://22222222-2222-4222-8222-222222222222@proxy.example.com:24444' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" || fail 'subscription output is wrong'
jq -e '(.services | keys | sort) == ["acme", "nginx", "subscription", "xray"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'WebSocket Compose services are wrong'
jq -e '
  all(.services[]; .read_only == true and (.cap_drop | index("ALL")) != null and
    ((.cap_add // []) | length) == 0 and .labels["io.padm.mode"] == "docker") and
  all(.services[].volumes[]?; (.source | contains("docker.sock") | not))
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'generated Compose privilege boundary is wrong'

runControl 0 configure-mixed-subscription configure --spec "${MIXED_WS_SPEC}"
jq -e '(.core.protocol_ids | sort) == [1, 21] and
  (.compose.profiles | sort) == ["core-xray", "nginx", "subscription"]' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'mixed subscription deployment is wrong'
grep -q 'vless://11111111-1111-4111-8111-111111111111@proxy.example.com:24443.*security=reality' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
    fail 'mixed Xray deployment did not publish its Reality node'
grep -q 'vless://22222222-2222-4222-8222-222222222222@proxy.example.com:24444' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
    fail 'mixed Xray deployment lost its WebSocket node'

DEPLOYMENT_HASH=$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)
CONFIG_HASH=$(sha256sum "${DOCKER_ROOT}/config/xray/config.json" | cut -d ' ' -f 1)
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up runControl 14 failed-start-rolls-back configure --spec "${ROLLBACK_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'failed startup did not restore deployment.json'
[[ "$(sha256sum "${DOCKER_ROOT}/config/xray/config.json" | cut -d ' ' -f 1)" == "${CONFIG_HASH}" ]] ||
    fail 'failed startup did not restore core config'

FAKE_DOCKER_MODE=core-validate-fail runControl 15 failed-validation-keeps-live configure --spec "${ROLLBACK_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'failed validation changed live deployment'
runControl 15 unsupported-protocol configure --spec "${UNSUPPORTED_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'unsupported protocol changed live deployment'
for spec in "${REALITY_XRAY_SPEC}" "${REALITY_SINGBOX_SPEC}"; do
    jq '.subscription.enabled = true' "${spec}" >"${TEST_ROOT}/invalid-subscription.json"
    runControl 15 reject-standalone-reality-subscription configure --spec "${TEST_ROOT}/invalid-subscription.json"
done
jq '.tls = null' "${WS_SPEC}" >"${TEST_ROOT}/invalid-subscription.json"
runControl 15 reject-subscription-without-tls configure --spec "${TEST_ROOT}/invalid-subscription.json"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'rejected subscription topology changed live deployment'

CREDENTIALS="${TEST_ROOT}/dns.env"
printf 'CF_Token=test-token\n' >"${CREDENTIALS}"
chmod 0600 "${CREDENTIALS}"
: >"${DOCKER_LOG}"
runControl 0 acme-issue acme issue --domain proxy.example.com --email admin@example.com \
    --dns dns_cf --credentials "${CREDENTIALS}"
grep -q -- '--issue --dns dns_cf -d proxy.example.com' "${DOCKER_LOG}" || fail 'ACME issue was not run'
grep -q -- '--install-cert -d proxy.example.com' "${DOCKER_LOG}" || fail 'ACME install-cert was not run'
grep -qxF 'fake-acme-certificate' "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'ACME certificate was not committed'

runControl 0 restart-persistence status
grep -qxF 'configured=yes' "${CONTROL_LOG}" || fail 'configured status was not restored'
runControl 0 validate-persistence validate
grep -qxF 'Docker 部署配置校验通过' "${CONTROL_LOG}" || fail 'validate did not report success'
runControl 0 restart-up up

MATRIX_FILE="${PROJECT_ROOT}/docker/contracts/features.json"
REGISTRY_FILE="${TEST_ROOT}/protocol-registry.json"
bash -c 'source "$1"; protocolCapabilityRegistry' _ "${PROJECT_ROOT}/shell/core/protocols.sh" |
    jq -Rs 'split("\n") | map(select(length > 0) | split("|") | select(.[2] == "node") |
      {id: (.[0] | tonumber), cores: (.[5] | split(",")), transport: .[7], udp_support: .[14]})' \
        >"${REGISTRY_FILE}"

validateFeatureMatrix() {
    jq -e --slurpfile registry "${REGISTRY_FILE}" '
      def state: . == "supported" or . == "host-integrated" or . == "deferred" or . == "unsupported";
      def text: type == "string" and length > 0;
      def names($allowed): type == "array" and (unique | length) == length and
        all(.[]; . as $name | ($allowed | index($name)) != null);
      def metadata:
        (.status | state) and (.native_menu | text) and (.native_action | text) and (.reason | text) and
        (.profiles | names(["core-xray", "core-sing-box", "nginx", "acme", "subscription",
          "net-wireguard", "net-fail2ban", "net-transparent"])) and
        (.network_mode == "bridge" or .network_mode == "host" or .network_mode == "host-cli") and
        (.host_capabilities | names(["NET_ADMIN", "/dev/net/tun"])) and
        (if .network_mode != "host" then
          .host_capabilities == [] and all(.profiles[]; startswith("net-") | not)
        else true end) and
        (if .status == "host-integrated" then
          .network_mode == "host" and (.host_capabilities | index("NET_ADMIN")) != null and
          any(.profiles[]; startswith("net-"))
        else true end) and
        (if .status == "supported" then .network_mode == "host-cli" or (.profiles | length) > 0
        else true end);
      ["nginx", "tls-files", "acme-dns", "subscription", "acme-webroot", "acme-standalone",
        "fail2ban", "wireguard", "tun", "tproxy"] as $legacy |
      ["subscription-traffic", "interactive-menu", "routing-tools", "core-lifecycle",
        "core-upgrade-assessment", "script-update", "uninstall", "reality-target-management",
        "reality-parameter-management", "reality-coexistence"] as $host_cli |
      ["subscription-multiserver", "acme-standalone", "fail2ban", "wireguard", "tun", "tproxy",
        "internal-203-wireguard", "internal-204-tun", "internal-205-redirect-tproxy",
        "network-optimization"] as $host |
      ($legacy + $host_cli + $host + ["subscription-users", "site-static-redirect-alpn",
        "entry-port-management", "cdn-entry-management", "internal-201-socks-relay",
        "internal-202-http-relay", "internal-206-routing-rules", "internal-207-access-control",
        "geo-data", "vless-encryption"] | unique) as $required |
      . as $matrix |
      .schema_version == 1 and
      (.protocols | type == "array" and length > 0) and
      ([.protocols[] | {id, cores, transport, udp_support}] | sort_by(.id)) == ($registry[0] | sort_by(.id)) and
      all(.protocols[];
        metadata and .management_status == "deferred" and
        .network_mode == "bridge" and .host_capabilities == [] and
        if .status == "supported" then
          (.profiles | sort) == ([.cores[] | "core-\(.)"] +
            (if .id == 21 then ["nginx"] else [] end) | sort)
        else .profiles == [] end) and
      (.features | type == "object" and keys == ($legacy | sort)) and
      (.feature_matrix | type == "object" and length > 0) and
      ($required - (.feature_matrix | keys) | length) == 0 and
      all(.features | to_entries[];
        . as $entry | (($entry.value | state) and
          $matrix.feature_matrix[$entry.key].status == $entry.value)) and
      all(.feature_matrix | to_entries[];
        . as $entry | (.value | metadata) and
        .value.network_mode == (if ($host_cli | index($entry.key)) != null then "host-cli"
          elif ($host | index($entry.key)) != null then "host" else "bridge" end)) and
      (.host_integrations | type == "object" and keys == (["fail2ban", "tun", "tproxy", "wireguard"] | sort)) and
      all(.host_integrations | to_entries[];
        . as $entry |
        (.value | .status == "host-integrated" and .network_mode == "host" and
          .capabilities == ["NET_ADMIN"] and
          .devices == (if $entry.key == "tun" then ["/dev/net/tun"] else [] end)) and
        ($matrix.feature_matrix[$entry.key] |
          .status == $entry.value.status and .network_mode == $entry.value.network_mode and
          .profiles == [$entry.value.profile] and
          (.host_capabilities | sort) == ($entry.value.capabilities + $entry.value.devices | sort))) and
      all({
        nginx: ["nginx"], "tls-files": ["nginx", "acme"], "acme-dns": ["acme"],
        subscription: ["core-xray", "nginx", "subscription"],
        "subscription-traffic": ["core-xray", "core-sing-box"],
        "core-lifecycle": ["core-xray", "core-sing-box"], "script-update": [], uninstall: []
      } | to_entries[];
        . as $entry | ($matrix.feature_matrix[$entry.key].profiles | sort) == ($entry.value | sort)) and
      all({
        "internal-203-wireguard": "wireguard", "internal-204-tun": "tun",
        "internal-205-redirect-tproxy": "tproxy"
      } | to_entries[];
        . as $entry |
        ($matrix.feature_matrix[$entry.key] | {status, profiles, network_mode, host_capabilities}) ==
          ($matrix.feature_matrix[$entry.value] | {status, profiles, network_mode, host_capabilities})) and
      all(["interactive-menu", "reality-target-management", "reality-parameter-management",
        "reality-coexistence", "core-upgrade-assessment"][]; $matrix.feature_matrix[.].status == "deferred") and
      ([.protocols[] | select(.status == "supported") | .id] | sort) == [1, 21] and
      .feature_matrix.subscription.requires == {core: "xray", protocol_ids: [21], tls: true} and
      (.feature_matrix.subscription.profiles | sort) == ["core-xray", "nginx", "subscription"]
    ' "$1" >/dev/null 2>&1
}

validateFeatureMatrix "${MATRIX_FILE}" || fail 'Docker feature matrix drift or invalid metadata'
while IFS= read -r mutation; do
    jq "${mutation}" "${MATRIX_FILE}" >"${TEST_ROOT}/invalid-matrix.json"
    if validateFeatureMatrix "${TEST_ROOT}/invalid-matrix.json"; then
        fail "invalid feature matrix was accepted: ${mutation}"
    fi
done <<'EOF'
.features.subscription = "deferred"
.features = {}
.feature_matrix = {}
del(.feature_matrix["reality-target-management"])
.protocols[0].profiles = ["invalid-profile"]
.feature_matrix.nginx.profiles = ["net-wireguard"]
.feature_matrix.nginx.profiles = ["core-sing-box"]
.feature_matrix["subscription-traffic"].profiles = []
.feature_matrix.nginx.network_mode = "host"
.feature_matrix.wireguard.host_capabilities = ["SYS_ADMIN"]
.host_integrations.wireguard.capabilities = ["SYS_ADMIN"]
.feature_matrix["internal-203-wireguard"].profiles = ["net-fail2ban"]
.feature_matrix["internal-204-tun"].host_capabilities = ["NET_ADMIN"]
.protocols[3].transport = "quic"
.protocols[14].udp_support = "no"
.protocols[0].management_status = "supported"
.protocols[1].status = "supported" | .protocols[1].profiles = ["core-xray"]
.feature_matrix.subscription.requires.core = "sing-box"
.feature_matrix.subscription.requires.protocol_ids = [1]
.feature_matrix.subscription.requires.tls = false
.feature_matrix["core-upgrade-assessment"].status = "supported"
EOF

printf 'docker-phase3-regression-ok\n'
