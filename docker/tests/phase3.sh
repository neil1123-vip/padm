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
mkdir -p "${MOCK_BIN}" "${NATIVE_ROOT}"
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

runControl() {
    local expected=$1 name=$2 actual=0
    shift 2
    : >"${CONTROL_LOG}"
    env \
        MSYS=winsymlinks:sys \
        PATH="${MOCK_BIN}:${PATH}" \
        DOCKER_HOST= \
        PADM_DOCKER_INSTALL_DIR="${DOCKER_ROOT}" \
        PADM_NATIVE_INSTALL_DIR="${NATIVE_ROOT}" \
        PADM_DOCKER_BIN_DIR="${CLI_DIR}" \
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

writeRealitySpec() {
    local target=$1 core=$2 accountName=$3 port=${4:-24443}
    jq -n \
        --arg core "${core}" \
        --arg name "${accountName}" \
        --arg digest "${IMAGE_DIGEST}" \
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
          manifest_sha256: $digest,
          signature_identity: "test-workflow"
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
        images: {xray: $xray, "sing-box": $singbox, nginx: $nginx, ops: $ops, net: $net}
      }
    ' >"${target}"
}

writeWebSocketSpec() {
    local target=$1
    jq -n \
        --arg digest "${IMAGE_DIGEST}" \
        --arg xray "$(imageReference xray)" \
        --arg singbox "$(imageReference sing-box)" \
        --arg nginx "$(imageReference nginx)" \
        --arg ops "${OPS_IMAGE}" \
        --arg net "$(imageReference net)" '
      {
        schema_version: 1,
        release: {
          version: "3.1.8",
          manifest_sha256: $digest,
          signature_identity: "test-workflow"
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
        images: {xray: $xray, "sing-box": $singbox, nginx: $nginx, ops: $ops, net: $net}
      }
    ' >"${target}"
}

REALITY_XRAY_SPEC="${TEST_ROOT}/xray.json"
REALITY_SINGBOX_SPEC="${TEST_ROOT}/sing-box.json"
WS_SPEC="${TEST_ROOT}/ws.json"
UNSUPPORTED_SPEC="${TEST_ROOT}/unsupported.json"
ROLLBACK_SPEC="${TEST_ROOT}/rollback.json"
writeRealitySpec "${REALITY_XRAY_SPEC}" xray main-xray
writeRealitySpec "${REALITY_SINGBOX_SPEC}" sing-box main-sing-box
writeWebSocketSpec "${WS_SPEC}"
jq '.core.protocols[0].id = 3' "${REALITY_XRAY_SPEC}" >"${UNSUPPORTED_SPEC}"
writeRealitySpec "${ROLLBACK_SPEC}" xray changed-after-failure 24444

SUBSCRIPTION_UNIT_ROOT="${TEST_ROOT}/subscription-unit"
mkdir -p "${SUBSCRIPTION_UNIT_ROOT}"
printf 'vless://unit-test\n' >"${SUBSCRIPTION_UNIT_ROOT}/0123456789abcdef"
python3 - "${PROJECT_ROOT}/docker/images/ops/control_server.py" "${SUBSCRIPTION_UNIT_ROOT}" <<'PY'
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
grep -q 'vless://22222222-2222-4222-8222-222222222222@proxy.example.com:24444' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" || fail 'subscription output is wrong'
jq -e '(.services | keys | sort) == ["acme", "nginx", "subscription", "xray"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'WebSocket Compose services are wrong'
jq -e '
  all(.services[]; .read_only == true and (.cap_drop | index("ALL")) != null and
    ((.cap_add // []) | length) == 0 and .labels["io.padm.mode"] == "docker") and
  all(.services[].volumes[]?; (.source | contains("docker.sock") | not))
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'generated Compose privilege boundary is wrong'

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

registryIds=$(bash -c 'source "$1"; protocolCapabilityRegistry' _ \
    "${PROJECT_ROOT}/shell/core/protocols.sh" | awk -F '|' '$3 == "node" { print $1 }' | sort -n | paste -sd, -)
matrixIds=$(jq -r '.protocols[].id' "${PROJECT_ROOT}/docker/contracts/features.json" | sort -n | paste -sd, -)
[[ "${registryIds}" == "${matrixIds}" ]] || fail 'Docker feature matrix drifted from protocol registry'

printf 'docker-phase3-regression-ok\n'
