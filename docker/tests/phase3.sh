#!/usr/bin/env bash
set -euo pipefail

export FAKE_PHASE3_HOST_SYSTEM FAKE_PHASE3_HOST_STAT
FAKE_PHASE3_HOST_SYSTEM=$(uname -s)
FAKE_PHASE3_HOST_STAT=$(command -v stat)
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
TEST_SKIP_CHOWN=1
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux && "$(id -u)" == 0 ]]; then
    TEST_SKIP_CHOWN=0
fi
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
    exec "${FAKE_PHASE3_HOST_STAT}" "$@"
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
    if [[ " ${*} " == *' up -d '* && ! -e "${FAKE_DOCKER_FAIL_ONCE:?}" &&
        ( "${mode}" == "fail-next-up" ||
            ( "${mode}" == "fail-next-sing-box-up" && " ${*} " == *' --profile core-sing-box '* ) ) ]]; then
        : >"${FAKE_DOCKER_FAIL_ONCE}"
        exit 1
    fi
    if [[ " ${*} " == *' run --rm --no-deps xray '* && "${mode}" == "core-validate-fail" ]]; then
        exit 1
    fi
    if [[ " ${*} " == *' run --rm --no-deps sing-box '* && "${mode}" == "sing-box-validate-fail" ]]; then
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
    if [[ " ${*} " == *' --entrypoint python3 '* && " ${*} " != *'/opt/acme/acme.sh'* ]]; then
        if [[ " ${*} " == *'302e020100300506032b656e04220420'* ]]; then
            previous=
            for argument in "$@"; do
                if [[ "${previous}" == -c ]]; then
                    exec python3 -c "${argument}"
                fi
                previous=${argument}
            done
            exit 1
        elif [[ "${mode}" == "reality-dns-failure" ]]; then
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
    if [[ "${CONTROL_USE_DEFAULT_ASSETS:-0}" != 1 &&
        ( "${1:-}" == configure || "${1:-}" == edit ) ]]; then
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
        PADM_DOCKER_SKIP_CHOWN="${TEST_SKIP_CHOWN}" \
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
              private_key: "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
              public_key: "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo",
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
jq '.core.protocols[0].id = 31' "${REALITY_XRAY_SPEC}" >"${UNSUPPORTED_SPEC}"
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
jq -e '.schema_version == 1' "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
    fail 'configuring a legacy spec silently rewrote its format'
jq -e '.inbounds[0].tag == "vless-reality"' "${DOCKER_ROOT}/config/xray/config.json" >/dev/null ||
    fail 'legacy Reality tag changed'
jq -e '(.services | keys | sort) == ["acme", "xray"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'Xray Compose services are wrong'
grep -q ' run --rm --no-deps xray -test -confdir /etc/padm/xray' "${DOCKER_LOG}" ||
    fail 'Xray candidate was not validated in its image'
cp -- "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/edit-original-xray.json"
jq '.core.protocols[0].reality.public_key = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"' \
    "${TEST_ROOT}/edit-original-xray.json" >"${DOCKER_ROOT}/config/spec.json"
runControl 15 edit-reject-current-wrong-key edit --preview
grep -qF 'Reality 公私钥不匹配' "${CONTROL_LOG}" ||
    fail 'editing an existing mismatched public key did not reach the key derivation guard'
cp -- "${TEST_ROOT}/edit-original-xray.json" "${DOCKER_ROOT}/config/spec.json"

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
runControl 0 edit-sing-box-preview edit --preview

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
jq -e '.services.nginx.ports == ["0.0.0.0:24444:8443/tcp"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'legacy WebSocket TLS port changed'
jq -e 'any(.inbounds[]; .tag == "vless-ws" and .port == 31297)' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'legacy WebSocket identity or backend changed'
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

# 编辑回归复用真实生成器和原有事务模拟，只比较生效配置，不把备份算作状态变化。
editLiveHash() {
    {
        sha256sum "${DOCKER_ROOT}/deployment.json" "${DOCKER_ROOT}/compose.json" \
            "${DOCKER_ROOT}/images.env"
        find "${DOCKER_ROOT}/config" "${DOCKER_ROOT}/data/subscription" \
            "${DOCKER_ROOT}/data/traffic" "${DOCKER_ROOT}/secrets/tls" \
            -type f -print0 | sort -z | xargs -0 sha256sum
    } | sha256sum | cut -d ' ' -f 1
}
assertEditCleanup() {
    [[ -z "$(find "${DOCKER_ROOT}" -maxdepth 1 -type d \
        \( -name '.candidate.*' -o -name '.edit.*' \) -print -quit)" ]] ||
        fail 'edit left a configuration candidate or draft directory'
}
runEditPty() {
    local command fifo="${TEST_ROOT}/edit-pty.input" completed="${TEST_ROOT}/edit-pty.done"
    local input=${1:-$'1\n1\n25446\n8\nn\n'} expected=${2:-0}
    local feeder actual=0 feederStatus=0
    rm -f -- "${fifo}" "${completed}"
    mkfifo "${fifo}"
    printf -v command '%q ' bash -u "${PROJECT_ROOT}/install-docker.sh" edit \
        --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
        --control-bundle "${CONFIGURE_CONTROL}"
    printf -v command '%s; status=$?; printf "%%s\\n" "$status" >%q; exit "$status"' "${command}" "${completed}"
    (
        exec 3>"${fifo}"
        printf '%s' "${input}" >&3
        # 等命令结束再关闭输入，避免 script 丢弃已排队的交互行。
        for ((attempt = 0; attempt < 2400; attempt++)); do
            [[ ! -f "${completed}" ]] || exit 0
            sleep 0.05
        done
        exit 1
    ) &
    feeder=$!
    env MSYS=winsymlinks:sys PATH="${MOCK_BIN}:${PATH}" DOCKER_HOST= \
        PADM_DOCKER_INSTALL_DIR="${DOCKER_ROOT}" PADM_NATIVE_INSTALL_DIR="${NATIVE_ROOT}" \
        PADM_DOCKER_BIN_DIR="${CLI_DIR}" PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd" \
        PADM_DOCKER_LOCK_TIMEOUT=2 PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_SKIP_CHOWN="${TEST_SKIP_CHOWN}" \
        FAKE_DOCKER_LOG="${DOCKER_LOG}" FAKE_DOCKER_MODE=ok \
        FAKE_DOCKER_FAIL_ONCE="${TEST_ROOT}/fail-once" \
        timeout 120 script -q -e -E never -f -c "${command}" "${CONTROL_LOG}" \
            <"${fifo}" >"${TEST_ROOT}/edit-pty.stdout" 2>&1 || actual=$?
    wait "${feeder}" || feederStatus=$?
    [[ "${actual}" -eq "${expected}" && "${feederStatus}" -eq 0 ]] ||
        fail "interactive edit PTY expected rc=${expected}, got rc=${actual}"
}

EDIT_SPEC="${TEST_ROOT}/edit.json"
jq '
  .schema_version = 2 |
  .core.protocols |= map(
    .listener_id = (if .id == 1 then "vless-reality" else "vless-ws" end) |
    if .id == 21 then .websocket += {backend_port: 31297, tls_port: 8443} else . end) |
  .core.protocols[1].public_port = 25443
' "${MIXED_WS_SPEC}" >"${EDIT_SPEC}"
# 旧控制包只能接收 v1，新控制包声明兼容三个受管规格版本。
OLD_SCHEMA_BUNDLE="${TEST_ROOT}/old-schema-bundle"
NEW_SCHEMA_BUNDLE="${TEST_ROOT}/new-schema-bundle"
mkdir -p "${OLD_SCHEMA_BUNDLE}/docker/contracts" "${NEW_SCHEMA_BUNDLE}/docker/contracts"
jq -n '{properties:{schema_version:{const:1}}}' \
    >"${OLD_SCHEMA_BUNDLE}/docker/contracts/configure.schema.json"
cp -- "${PROJECT_ROOT}/docker/contracts/configure.schema.json" \
    "${NEW_SCHEMA_BUNDLE}/docker/contracts/configure.schema.json"
for bundle in "${OLD_SCHEMA_BUNDLE}" "${NEW_SCHEMA_BUNDLE}"; do
    cp -- "${PROJECT_ROOT}/docker/contracts/features.json" "${bundle}/docker/contracts/features.json"
done
jq '.schema_version = 3 | .core.secondary_type = null |
    .core.protocols |= map(.core = "xray")' "${EDIT_SPEC}" >"${TEST_ROOT}/edit-v3.json"
bash -euo pipefail -c '
    source "$1/docker/lib/bootstrap.sh"
    source "$1/docker/lib/bundle.sh"
    dockerBundleSupportsSpec "$2" "$4"
    dockerBundleSupportsSpec "$3" "$4"
    dockerBundleSupportsSpec "$3" "$5"
    dockerBundleSupportsSpec "$3" "$6"
    if dockerBundleSupportsSpec "$2" "$5"; then
        exit 1
    fi
    ! dockerBundleSupportsSpec "$3" <(jq "del(.schema_version)" "$5")
    ! dockerBundleSupportsSpec "$3" <(jq ".,." "$5")
' _ "${PROJECT_ROOT}" "${OLD_SCHEMA_BUNDLE}" "${NEW_SCHEMA_BUNDLE}" \
    "${MIXED_WS_SPEC}" "${EDIT_SPEC}" "${TEST_ROOT}/edit-v3.json" ||
    fail 'control bundle format gate lost legacy compatibility or accepted v2 in a const-v1 bundle'
mkdir -p "${DOCKER_ROOT}/data/traffic"
printf '%s\n' '{"schema_version":1,"accounts":{"11111111-1111-4111-8111-111111111111":{"name":"main-xray","upload":7,"download":11,"limit_bytes":0,"baseline":{}}}}' \
    >"${DOCKER_ROOT}/data/traffic/state.json"
chmod 0600 "${DOCKER_ROOT}/data/traffic/state.json"
EDIT_LIVE_HASH=$(editLiveHash)
NGINX_HASH=$(sha256sum "${DOCKER_ROOT}/config/nginx/default.conf" | cut -d ' ' -f 1)
TRAFFIC_HASH=$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)
: >"${DOCKER_LOG}"
runControl 0 edit-preview edit --spec "${EDIT_SPEC}" --preview
[[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'edit preview changed live configuration'
! grep -Eq ' (up|down|restart|exec) ' "${DOCKER_LOG}" || fail 'edit preview changed services or collected traffic'
while IFS= read -r secret; do
    ! grep -Fq -- "${secret}" "${CONTROL_LOG}" || fail 'edit preview exposed a credential or WebSocket path'
done < <(jq -r '[.subscription.token, .core.protocols[] |
    if type == "object" then .uuid, .websocket.path, .reality.private_key,
      .reality.public_key, .reality.short_id else . end] |
    .[] | select(type == "string" and length > 0)' "${EDIT_SPEC}")
assertEditCleanup
export FAKE_EDIT_REAL_CURL
FAKE_EDIT_REAL_CURL=$(command -v curl)
export FAKE_EDIT_ASSET_MANIFEST="${CONFIGURE_MANIFEST}" FAKE_EDIT_ASSET_BUNDLE="${CONFIGURE_BUNDLE}"
export FAKE_EDIT_ASSET_CONTROL="${CONFIGURE_CONTROL}" FAKE_EDIT_ASSET_LOG="${TEST_ROOT}/edit-default-assets.log"
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
target= url= previous=
for argument in "$@"; do
    [[ "${previous}" != -o ]] || target=${argument}
    [[ "${argument}" != https://* ]] || url=${argument}
    previous=${argument}
done
case "${url}" in
https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.json)
    sourceFile=${FAKE_EDIT_ASSET_MANIFEST:?} ;;
https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.sigstore.json)
    sourceFile=${FAKE_EDIT_ASSET_BUNDLE:?} ;;
https://example.invalid/control.tar.gz)
    sourceFile=${FAKE_EDIT_ASSET_CONTROL:?} ;;
*) exec "${FAKE_EDIT_REAL_CURL:?}" "$@" ;;
esac
[[ -n "${target}" ]] || exit 1
printf '%s\n' "${url}" >>"${FAKE_EDIT_ASSET_LOG:?}"
cp -- "${sourceFile}" "${target}"
EOF
chmod 0755 "${MOCK_BIN}/curl"
CONTROL_USE_DEFAULT_ASSETS=1 runControl 0 edit-default-current-release edit --preview
rm -- "${MOCK_BIN}/curl"
[[ "$(wc -l <"${FAKE_EDIT_ASSET_LOG}")" -eq 3 ]] ||
    fail 'default edit did not download exactly three current-release assets'
for url in \
    https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.json \
    https://github.com/neil1123-vip/padm/releases/download/v3.1.8/release-manifest.sigstore.json \
    https://example.invalid/control.tar.gz; do
    grep -qxF "${url}" "${FAKE_EDIT_ASSET_LOG}" || fail 'default edit did not pin the deployed release assets'
done
! grep -q latest "${FAKE_EDIT_ASSET_LOG}" || fail 'default edit requested latest release assets'
[[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'default edit preview changed live configuration'
unset FAKE_EDIT_REAL_CURL FAKE_EDIT_ASSET_MANIFEST FAKE_EDIT_ASSET_BUNDLE FAKE_EDIT_ASSET_CONTROL FAKE_EDIT_ASSET_LOG
assertEditCleanup
runControl 2 edit-needs-explicit-mode edit --spec "${EDIT_SPEC}"
runControl 2 edit-reject-invalid-confirmation edit --spec "${EDIT_SPEC}" --confirm no
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    : >"${DOCKER_LOG}"
    runEditPty
    grep -qF 'core.protocols.1.public_port' "${CONTROL_LOG}" ||
        fail 'interactive edit did not preview the entered Reality port change'
    [[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'cancelled interactive edit changed live configuration'
    ! grep -Eq ' (up|down|restart|exec) ' "${DOCKER_LOG}" ||
        fail 'cancelled interactive edit changed services or collected traffic'
    assertEditCleanup
    EDIT_LIVE_HASH=$(editLiveHash)
    runEditPty $'1\n1\nabc\n' 15
    [[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'invalid interactive edit changed live configuration'
    assertEditCleanup
    mv -- "${DOCKER_ROOT}/secrets" "${TEST_ROOT}/saved-secrets"
    ln -s "${TEST_ROOT}/saved-secrets" "${DOCKER_ROOT}/secrets"
    SECRETS_HASH=$(find "${TEST_ROOT}/saved-secrets" -type f -print0 | sort -z |
        xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)
    runControl 15 edit-reject-symlinked-secrets edit --spec "${EDIT_SPEC}" --preview
    [[ "$(find "${TEST_ROOT}/saved-secrets" -type f -print0 | sort -z |
        xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)" == "${SECRETS_HASH}" ]] ||
        fail 'edit changed TLS files through a secrets ancestor symlink'
    rm -- "${DOCKER_ROOT}/secrets"
    mv -- "${TEST_ROOT}/saved-secrets" "${DOCKER_ROOT}/secrets"
    [[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'rejected secrets symlink edit changed live configuration'
    assertEditCleanup
fi
for directory in config/sing-box config/net; do
    printf 'unmanaged-input\n' >"${DOCKER_ROOT}/${directory}/edit-unknown"
    UNKNOWN_LIVE_HASH=$(editLiveHash)
    runControl 15 edit-reject-unknown-input edit --spec "${EDIT_SPEC}" --preview
    [[ "$(editLiveHash)" == "${UNKNOWN_LIVE_HASH}" ]] || fail 'edit discarded an unknown inactive configuration file'
    rm -- "${DOCKER_ROOT}/${directory}/edit-unknown"
done
cp -- "${DOCKER_ROOT}/images.env" "${TEST_ROOT}/edit-images.env"
sed 's|^PADM_DOCKER_ROOT=.*|PADM_DOCKER_ROOT=/tmp/padm-docker-other|' \
    "${TEST_ROOT}/edit-images.env" >"${DOCKER_ROOT}/images.env"
UNKNOWN_LIVE_HASH=$(editLiveHash)
runControl 15 edit-reject-altered-mount-root edit --spec "${EDIT_SPEC}" --preview
[[ "$(editLiveHash)" == "${UNKNOWN_LIVE_HASH}" ]] || fail 'edit discarded the altered image environment input'
cp -- "${TEST_ROOT}/edit-images.env" "${DOCKER_ROOT}/images.env"
cp -- "${DOCKER_ROOT}/config/xray/config.json" "${TEST_ROOT}/edit-before-quota.json"
cp -- "${DOCKER_ROOT}/data/traffic/state.json" "${TEST_ROOT}/edit-before-quota-state.json"
USERS_BASE_HASH=$(sha256sum "${DOCKER_ROOT}/config/xray/users.base" | cut -d ' ' -f 1)
jq '.accounts["11111111-1111-4111-8111-111111111111"].limit_bytes = 1' \
    "${TEST_ROOT}/edit-before-quota-state.json" >"${DOCKER_ROOT}/data/traffic/state.json"
bash -u -c '
    source "$1/docker/lib/bootstrap.sh"
    source "$1/docker/lib/traffic.sh"
    dockerTrafficRender xray "$2" "$(<"$3")"
' _ "${PROJECT_ROOT}" "${DOCKER_ROOT}/config/xray/users.base" \
    "${DOCKER_ROOT}/data/traffic/state.json" >"${DOCKER_ROOT}/config/xray/config.json"
jq -e '[.inbounds[].settings.clients[]? |
    select(.id == "11111111-1111-4111-8111-111111111111")] | length == 0' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'quota fixture did not disable its exceeded account'
QUOTA_LIVE_HASH=$(editLiveHash)
runControl 0 edit-preview-over-quota edit --spec "${EDIT_SPEC}" --preview
[[ "$(editLiveHash)" == "${QUOTA_LIVE_HASH}" &&
    "$(sha256sum "${DOCKER_ROOT}/config/xray/users.base" | cut -d ' ' -f 1)" == "${USERS_BASE_HASH}" ]] ||
    fail 'edit preview lost an over-quota account or changed quota state'
cp -- "${TEST_ROOT}/edit-before-quota.json" "${DOCKER_ROOT}/config/xray/config.json"
cp -- "${TEST_ROOT}/edit-before-quota-state.json" "${DOCKER_ROOT}/data/traffic/state.json"
for mutation in 'del(.core.protocols[0].uuid)' '.schema_version = 3' '.unexpected = true'; do
    jq "${mutation}" "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
    runControl 15 edit-reject-invalid-spec edit --spec "${TEST_ROOT}/edit-invalid.json" --preview
done
for mutation in \
    'del(.core.protocols[0].listener_id)' \
    '.core.protocols[0].uuid = "33333333-3333-4333-8333-333333333333"' \
    '.subscription.token = "fedcba9876543210"' \
    '.core.protocols[0].listener_id = "entry-renamed"' \
    '.core.protocols[0].websocket.backend_port = 31298' \
    '.core.protocols[0].websocket.tls_port = 8444'; do
    jq "${mutation}" "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
    runControl 15 edit-reject-fixed-field-change edit --spec "${TEST_ROOT}/edit-invalid.json" --preview
done
cat "${EDIT_SPEC}" "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
runControl 15 edit-reject-multiple-json edit --spec "${TEST_ROOT}/edit-invalid.json" --preview
jq '.release.manifest_sha256 = ("f" * 64)' "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
runControl 16 edit-reject-untrusted-release edit --spec "${TEST_ROOT}/edit-invalid.json" --preview
jq '.core.protocols[1].reality.public_key = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"' \
    "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
runControl 15 edit-reject-wrong-reality-key edit --spec "${TEST_ROOT}/edit-invalid.json" --preview
FAKE_DOCKER_MODE=core-validate-fail runControl 15 edit-reject-invalid-candidate edit --spec "${EDIT_SPEC}" --preview
[[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'rejected edit changed live configuration'
assertEditCleanup

runControl 0 edit-confirm-port edit --spec "${EDIT_SPEC}" --confirm PADM-DOCKER-EDIT
jq -e --slurpfile original "${EDIT_SPEC}" '
  . == ($original[0] | .schema_version = 3 | .core.secondary_type = null |
    .core.protocols |= map(.core = "xray"))' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail 'edit changed unselected complete spec fields'
jq -e 'any(.inbounds[]; .port == 25443 and .streamSettings.security == "reality")' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'edit did not commit the Reality port'
[[ "$(sha256sum "${DOCKER_ROOT}/config/nginx/default.conf" | cut -d ' ' -f 1)" == "${NGINX_HASH}" ]] ||
    fail 'editing the Reality port changed WebSocket Nginx config'
[[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)" == "${TRAFFIC_HASH}" ]] ||
    fail 'edit lost cumulative traffic or quota state'
grep -q 'vless://22222222-2222-4222-8222-222222222222@proxy.example.com:24444' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" || fail 'edit lost the WebSocket subscription node'
grep -q 'vless://11111111-1111-4111-8111-111111111111@proxy.example.com:25443' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" || fail 'edit did not update the Reality subscription port'
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    [[ "$("${FAKE_PHASE3_HOST_STAT}" -c %a "${DOCKER_ROOT}/config/spec.json")" == 600 &&
        "$("${FAKE_PHASE3_HOST_STAT}" -c %a "${DOCKER_ROOT}/config/xray/users.base")" == 640 &&
        "$("${FAKE_PHASE3_HOST_STAT}" -c %a "${DOCKER_ROOT}/config/nginx/default.conf")" == 640 ]] ||
        fail 'edit did not retain private spec and runtime configuration permissions'
    if [[ "${TEST_SKIP_CHOWN}" == 0 ]]; then
        [[ "$("${FAKE_PHASE3_HOST_STAT}" -c %u:%g "${DOCKER_ROOT}/config/spec.json")" == 0:0 &&
            "$("${FAKE_PHASE3_HOST_STAT}" -c %u:%g "${DOCKER_ROOT}/config/xray/users.base")" == 0:10001 &&
            "$("${FAKE_PHASE3_HOST_STAT}" -c %u:%g "${DOCKER_ROOT}/config/nginx/default.conf")" == 0:10001 ]] ||
            fail 'edit did not retain root-only spec and runtime container-group ownership'
    fi
fi
EDIT_LIVE_HASH=$(editLiveHash)
jq '.core.protocols[1].public_port = 25444' "${EDIT_SPEC}" >"${TEST_ROOT}/edit-invalid.json"
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up runControl 14 edit-failed-start-rolls-back \
    edit --spec "${TEST_ROOT}/edit-invalid.json" --confirm PADM-DOCKER-EDIT
[[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'failed edit did not restore spec, core, TLS, Nginx and subscription'
assertEditCleanup

EDIT_IMPORT_SPEC="${TEST_ROOT}/edit-import-v3.json"
cp -- "${DOCKER_ROOT}/config/spec.json" "${EDIT_IMPORT_SPEC}"
rm -- "${DOCKER_ROOT}/config/spec.json"
EDIT_LIVE_HASH=$(editLiveHash)
runControl 15 edit-legacy-needs-original-spec edit --preview
runControl 15 edit-legacy-reject-invented-spec edit --spec "${MIXED_WS_SPEC}" --preview
runControl 0 edit-legacy-preview edit --spec "${EDIT_IMPORT_SPEC}" --preview
[[ ! -e "${DOCKER_ROOT}/config/spec.json" && "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] ||
    fail 'legacy preview committed its imported spec'
cp -- "${DOCKER_ROOT}/config/xray/users.base" "${TEST_ROOT}/edit-users.base"
for mutation in \
    '.inbounds[0].settings.clients += [{id:"33333333-3333-4333-8333-333333333333",email:"extra-account"}]' \
    '.routing.rules += [{type:"field",domain:["custom.example.com"],outboundTag:"direct"}]'; do
    jq "${mutation}" "${TEST_ROOT}/edit-users.base" >"${DOCKER_ROOT}/config/xray/users.base"
    EDIT_LIVE_HASH=$(editLiveHash)
    runControl 15 edit-reject-unmanaged-core-input edit --spec "${EDIT_IMPORT_SPEC}" --preview
    [[ "$(editLiveHash)" == "${EDIT_LIVE_HASH}" ]] || fail 'rejected edit discarded custom accounts or routing'
done
cp -- "${TEST_ROOT}/edit-users.base" "${DOCKER_ROOT}/config/xray/users.base"
runControl 0 edit-legacy-confirm-import edit --spec "${EDIT_IMPORT_SPEC}" --confirm PADM-DOCKER-EDIT
jq -e --slurpfile original "${EDIT_SPEC}" '
  . == ($original[0] | .schema_version = 3 | .core.secondary_type = null |
    .core.protocols |= map(.core = "xray"))' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail 'legacy import did not retain the complete original spec'
assertEditCleanup

# 真实终端分别提交复制与删除；多实例下数字协议 ID 不能误选其他入口。
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    runEditPty $'9\n21\n\n28444\n8\ny\n'
    jq -e '(.core.protocols | length) == 3 and
      any(.core.protocols[]; .listener_id == "entry-1" and .id == 21 and .public_port == 28444 and
        .websocket.backend_port == 31298 and .websocket.tls_port == 8444)' \
        "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
        fail 'interactive WebSocket clone did not allocate a stable identity and independent internal ports'
    jq -e 'any(.listeners[]; .listener_id == "entry-1" and
      .public_port == 28444 and .container_port == 8444)' "${DOCKER_ROOT}/deployment.json" >/dev/null ||
        fail 'interactive clone was not committed to the deployment listeners'
    PTY_CLONE_HASH=$(editLiveHash)
    runEditPty $'1\n21\n' 15
    [[ "$(editLiveHash)" == "${PTY_CLONE_HASH}" ]] ||
        fail 'ambiguous numeric protocol selection changed a multi-entry deployment'
    assertEditCleanup
    runEditPty $'10\nentry-1\n8\ny\n'
    jq -e --slurpfile original "${EDIT_SPEC}" '
      . == ($original[0] | .schema_version = 3 | .core.secondary_type = null |
        .core.protocols |= map(.core = "xray"))' \
        "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
        fail 'interactive entry deletion did not retain the original complete spec'
    jq -e '[.listeners[].listener_id] | sort == ["vless-reality", "vless-ws"]' \
        "${DOCKER_ROOT}/deployment.json" >/dev/null ||
        fail 'interactive entry deletion left a stale deployment listener'
    assertEditCleanup
fi

# 多入口复用既有凭据；身份、核心端口与 TLS 端口必须由完整规格明确记录。
MULTI_SPEC="${TEST_ROOT}/multi-v2.json"
jq '
  .core.protocols += [
    (.core.protocols[] | select(.id == 1) |
      .listener_id = "entry-extra-reality" | .name = "extra-reality" | .public_port = 26443),
    (.core.protocols[] | select(.id == 21) |
      .listener_id = "entry-extra-ws" | .name = "extra-ws" | .public_port = 26444 |
      .websocket.path = "second_ws_path" | .websocket.backend_port = 31300 |
      .websocket.tls_port = 8543)
  ]
' "${EDIT_SPEC}" >"${MULTI_SPEC}"
MULTI_LIVE_HASH=$(editLiveHash)
runControl 0 edit-multi-preview edit --spec "${MULTI_SPEC}" --preview
[[ "$(editLiveHash)" == "${MULTI_LIVE_HASH}" ]] || fail 'multi-entry preview changed live configuration'
assertEditCleanup
runControl 0 edit-add-multiple-entries edit --spec "${MULTI_SPEC}" --confirm PADM-DOCKER-EDIT
jq -e '
  .core.protocol_ids == [1, 21] and
  ([.listeners[] | .listener_id] | sort) ==
    ["entry-extra-reality", "entry-extra-ws", "vless-reality", "vless-ws"] and
  any(.listeners[]; .listener_id == "entry-extra-ws" and .service == "nginx" and
    .public_port == 26444 and .container_port == 8543) and
  any(.listeners[]; .listener_id == "vless-ws" and .public_port == 24444 and .container_port == 8443)
' "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'multi-entry deployment lost stable listener identities'
jq -e '
  [.inbounds[] | select(.protocol == "vless") | {tag, port}] | sort_by(.tag) ==
    ([{tag:"entry-extra-reality",port:26443},{tag:"entry-extra-ws",port:31300},
      {tag:"vless-reality",port:25443},{tag:"vless-ws",port:31297}] | sort_by(.tag))
' "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'multi-entry Xray tags or backend ports are wrong'
for backend in 31297 31300; do
    grep -q "proxy_pass http://xray:${backend};" "${DOCKER_ROOT}/config/nginx/default.conf" ||
        fail "multi-entry Nginx lost backend ${backend}"
done
for port in 8443 8543; do
    grep -Eq "listen ${port} .*ssl;" "${DOCKER_ROOT}/config/nginx/default.conf" ||
        fail "multi-entry Nginx lost TLS listener ${port}"
done
[[ "$(grep -c '^[[:space:]]*server {' "${DOCKER_ROOT}/config/nginx/default.conf")" -eq 3 ]] ||
    fail 'multiple WebSocket entries did not retain separate TLS servers and one health server'
jq -e '.services.nginx.ports | sort ==
  ["0.0.0.0:24444:8443/tcp", "0.0.0.0:26444:8543/tcp"]' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'multi-entry Compose TLS mappings are wrong'
[[ "$(wc -l <"${DOCKER_ROOT}/data/subscription/0123456789abcdef")" -eq 4 ]] ||
    fail 'multi-entry subscription did not contain every entry'
for port in 24444 25443 26443 26444; do
    grep -q "@proxy.example.com:${port}" "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
        fail "multi-entry subscription lost public port ${port}"
done
MULTI_TAGS=$(jq -c '[.inbounds[] | select(.protocol == "vless") | {tag,port}] | sort_by(.tag)' \
    "${DOCKER_ROOT}/config/xray/config.json")
MULTI_LISTENERS=$(jq -c '.listeners | sort_by(.listener_id)' "${DOCKER_ROOT}/deployment.json")
jq '.core.protocols |= reverse' "${MULTI_SPEC}" >"${TEST_ROOT}/multi-reordered.json"
runControl 0 edit-reorder-stable-identity edit --spec "${TEST_ROOT}/multi-reordered.json" --confirm PADM-DOCKER-EDIT
[[ "$(jq -c '[.inbounds[] | select(.protocol == "vless") | {tag,port}] | sort_by(.tag)' \
    "${DOCKER_ROOT}/config/xray/config.json")" == "${MULTI_TAGS}" &&
    "$(jq -c '.listeners | sort_by(.listener_id)' "${DOCKER_ROOT}/deployment.json")" == "${MULTI_LISTENERS}" ]] ||
    fail 'reordering protocol entries renumbered listener identities or ports'
MULTI_LIVE_HASH=$(editLiveHash)
for mutation in \
    '(.core.protocols[] | select(.listener_id == "entry-extra-reality") | .listener_id) = "entry-renamed"' \
    '(.core.protocols[] | select(.listener_id == "entry-extra-ws") | .listener_id) = "entry-renamed-ws" |
      (.core.protocols[] | select(.listener_id == "entry-renamed-ws") | .websocket.backend_port) = 31400' \
    '(.core.protocols[] | select(.listener_id == "entry-extra-ws") | .listener_id) = "entry-renamed-ws" |
      (.core.protocols[] | select(.listener_id == "entry-renamed-ws") | .websocket.tls_port) = 8643'; do
    jq "${mutation}" "${MULTI_SPEC}" >"${TEST_ROOT}/multi-invalid.json"
    runControl 15 edit-reject-identity-replacement edit --spec "${TEST_ROOT}/multi-invalid.json" --preview
    [[ "$(editLiveHash)" == "${MULTI_LIVE_HASH}" ]] ||
        fail 'same-credential identity replacement changed live configuration'
    assertEditCleanup
done
for mutation in \
    '.core.protocols[0].listener_id = .core.protocols[1].listener_id' \
    '.core.protocols[0].listener_id = "vless-reality"' \
    '.core.protocols[0].public_port = .core.protocols[1].public_port' \
    '.core.protocols[3].websocket.backend_port = .core.protocols[0].websocket.backend_port' \
    '.core.protocols[1].public_port = .core.protocols[0].websocket.backend_port' \
    '.core.protocols[3].websocket.tls_port = .core.protocols[0].websocket.tls_port' \
    '.core.protocols[0].websocket.tls_port = 8080' \
    '.core.protocols[1].public_port = 10085' \
    '.core.protocols[0].websocket.backend_port = 10085' \
    '.core.protocols |= [range(17) as $n | .[1] |
      .listener_id = ("entry-limit-" + ($n | tostring)) | .public_port = (27000 + $n)] |
      .tls = null | .subscription.enabled = false' \
    '.core.type = "sing-box"'; do
    jq "${mutation}" "${MULTI_SPEC}" >"${TEST_ROOT}/multi-invalid.json"
    runControl 15 reject-multi-entry-conflict configure --spec "${TEST_ROOT}/multi-invalid.json"
    [[ "$(editLiveHash)" == "${MULTI_LIVE_HASH}" ]] || fail 'rejected multi-entry spec changed live configuration'
    assertEditCleanup
done
jq '.core.protocols += [(.core.protocols[] | select(.listener_id == "entry-extra-reality") |
  .listener_id = "entry-bad-clone" | .public_port = 28443 |
  .uuid = "33333333-3333-4333-8333-333333333333")]' "${MULTI_SPEC}" >"${TEST_ROOT}/multi-invalid.json"
runControl 15 edit-reject-new-entry-credentials edit --spec "${TEST_ROOT}/multi-invalid.json" --preview
[[ "$(editLiveHash)" == "${MULTI_LIVE_HASH}" ]] || fail 'rejected entry credentials changed live configuration'
runControl 0 edit-remove-multiple-entries edit --spec "${EDIT_SPEC}" --confirm PADM-DOCKER-EDIT
jq '
  .core.protocols |= map(select(.id == 1)) |
  .tls = null | .subscription.enabled = false
' "${EDIT_SPEC}" >"${TEST_ROOT}/reality-only-v2.json"
TLS_HASH=$(find "${DOCKER_ROOT}/secrets/tls" -type f -print0 | sort -z |
    xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)
REMOVE_WS_LOG_START=$(wc -l <"${DOCKER_LOG}")
runControl 0 edit-remove-last-websocket edit --spec "${TEST_ROOT}/reality-only-v2.json" --confirm PADM-DOCKER-EDIT
tail -n "+$((REMOVE_WS_LOG_START + 1))" "${DOCKER_LOG}" | grep -q -- ' up -d .*--remove-orphans' ||
    fail 'removing the last WebSocket did not clean up orphaned project services'
jq -e '.schema_version == 3 and .core.secondary_type == null and .tls == null and .subscription.enabled == false and
  .subscription.token == "0123456789abcdef" and .core.protocols[0].listener_id == "vless-reality"' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail 'removing the last WebSocket lost retained spec inputs'
[[ "$(find "${DOCKER_ROOT}/secrets/tls" -type f -print0 | sort -z |
    xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)" == "${TLS_HASH}" ]] ||
    fail 'removing the last WebSocket deleted retained TLS files'
jq '.core.type = "sing-box" | .core.protocols |= map(select(.id == 1)) |
  .tls = null | .subscription.enabled = false' "${MULTI_SPEC}" >"${TEST_ROOT}/multi-sing-box.json"
runControl 0 configure-multi-sing-box configure --spec "${TEST_ROOT}/multi-sing-box.json"
jq -e '[.inbounds[] | select(.type == "vless") | {tag,listen_port}] | sort_by(.tag) ==
  ([{tag:"entry-extra-reality",listen_port:26443},{tag:"vless-reality",listen_port:25443}] | sort_by(.tag))' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail 'multi-entry sing-box Reality listeners are wrong'
jq '.core.protocols[0].public_port = 10087' "${TEST_ROOT}/multi-sing-box.json" \
    >"${TEST_ROOT}/multi-invalid.json"
runControl 15 reject-sing-box-stats-port configure --spec "${TEST_ROOT}/multi-invalid.json"
jq '.core.protocols |= [range(16) as $n | .[1] |
  .listener_id = ("entry-limit-" + ($n | tostring)) | .public_port = (27000 + $n)] |
  .tls = null | .subscription.enabled = false' "${MULTI_SPEC}" >"${TEST_ROOT}/multi-limit.json"
runControl 0 configure-sixteen-entries configure --spec "${TEST_ROOT}/multi-limit.json"
jq -e '[.inbounds[] | select(.protocol == "vless")] | length == 16' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'maximum supported entry count was not rendered'
jq -e '(.listeners | length) == 16 and ([.listeners[].listener_id] | unique | length) == 16' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'maximum entry count lost stable listener identities'
runControl 0 configure-multi-xray configure --spec "${MULTI_SPEC}"
runControl 0 edit-multi-baseline-preview edit --preview
assertEditCleanup

if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    runEditPty $'9\nvless-reality\n2\n27443\n8\ny\n'
    jq -e '.core.secondary_type == "sing-box" and
      any(.core.protocols[]; .listener_id == "entry-1" and .core == "sing-box" and .public_port == 27443)' \
        "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail 'interactive clone did not enable the secondary core'
    runEditPty $'10\nentry-1\n8\ny\n'
    jq -e '.core.secondary_type == null' "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
        fail 'interactive deletion did not disable the last secondary listener'
    jq -e '.services | has("sing-box") | not' "${DOCKER_ROOT}/compose.json" >/dev/null ||
        fail 'interactive deletion left the secondary service'
    SINGLE_CORE_LIVE_HASH=$(editLiveHash)
    runEditPty $'9\nvless-ws\n2\n' 15
    [[ "$(editLiveHash)" == "${SINGLE_CORE_LIVE_HASH}" ]] || fail 'unsupported WS core changed live state'
    runEditPty $'10\nvless-reality\n10\nentry-extra-reality\n10\nvless-ws\n10\nentry-extra-ws\n' 15
    [[ "$(editLiveHash)" == "${SINGLE_CORE_LIVE_HASH}" ]] || fail 'deleting the last primary listener changed live state'
    assertEditCleanup
    runControl 0 configure-multi-xray configure --spec "${MULTI_SPEC}"
fi

# 主副核心共享部署事务和订阅；内部端口只在各自容器命名空间冲突。
DUAL_SPEC="${TEST_ROOT}/dual-v3.json"
jq '
  .schema_version = 3 | .core.secondary_type = "sing-box" |
  .core.protocols |= map(.core = "xray") |
  .core.protocols += [
    (.core.protocols[] | select(.listener_id == "vless-reality") |
      .core = "sing-box" | .listener_id = "entry-sing-box" |
      .name = "sing-box-reality" | .public_port = 31297)
  ]
' "${MULTI_SPEC}" >"${DUAL_SPEC}"
: >"${DOCKER_LOG}"
runControl 0 configure-dual-core configure --spec "${DUAL_SPEC}"
jq -e '.schema_version == 1 and .formats.config == 1 and
  .core.type == "xray" and .core.secondary_type == "sing-box" and .core.protocol_ids == [1,21] and
  (.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"] and
  any(.listeners[]; .listener_id == "entry-sing-box" and .service == "sing-box" and
    .public_port == 31297 and .container_port == 31297)' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'dual-core deployment contract is wrong'
jq -e '([.inbounds[] | select(.protocol == "vless")] | length) == 4 and
  all(.inbounds[] | select(.protocol == "vless"); .tag != "entry-sing-box")' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail 'Xray config contains a sing-box entry'
jq -e '[.inbounds[] | select(.type == "vless") | {tag,listen_port}] ==
  [{tag:"entry-sing-box",listen_port:31297}]' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail 'sing-box config lost its owned entry'
jq -e '(.services | keys | sort) == ["acme","nginx","sing-box","subscription","xray"] and
  .services["sing-box"].ports ==
    ["0.0.0.0:31297:31297/tcp","[::]:31297:31297/tcp"] and
  (.services.nginx.ports | length) > 0' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'dual-core Compose services or mappings are wrong'
grep -q ' run --rm --no-deps xray -test ' "${DOCKER_LOG}" ||
    fail 'dual-core Xray candidate was not validated'
grep -q ' run --rm --no-deps sing-box check ' "${DOCKER_LOG}" ||
    fail 'dual-core sing-box candidate was not validated'
[[ "$(wc -l <"${DOCKER_ROOT}/data/subscription/0123456789abcdef")" -eq 5 ]] ||
    fail 'dual-core subscription did not publish all entries'
grep -q '@proxy.example.com:31297.*security=reality' \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
    fail 'dual-core subscription lost the secondary-core Reality entry'
DUAL_SUBSCRIPTION_HASH=$(sha256sum "${DOCKER_ROOT}/data/subscription/0123456789abcdef" | cut -d ' ' -f 1)
jq '.core.type = "sing-box" | .core.secondary_type = "xray"' \
    "${DUAL_SPEC}" >"${TEST_ROOT}/dual-sing-box-primary.json"
runControl 0 configure-sing-box-primary-websocket-secondary configure \
    --spec "${TEST_ROOT}/dual-sing-box-primary.json"
jq -e '.core.type == "sing-box" and .core.secondary_type == "xray" and
  (.compose.profiles | sort) == ["core-sing-box","core-xray","nginx","subscription"]' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail 'swapping primary and secondary lost dual-core profiles'
jq -e '.services.nginx.depends_on.xray.condition == "service_healthy" and
  (.services.xray.ports | length) == 4' "${DOCKER_ROOT}/compose.json" >/dev/null ||
    fail 'WebSocket proxy did not retain its secondary Xray dependency'
[[ "$(sha256sum "${DOCKER_ROOT}/data/subscription/0123456789abcdef" | cut -d ' ' -f 1)" == \
    "${DUAL_SUBSCRIPTION_HASH}" ]] || fail 'swapping primary and secondary changed subscription nodes'
runControl 0 configure-restore-xray-primary configure --spec "${DUAL_SPEC}"
runControl 0 edit-dual-core-preview edit --preview
assertEditCleanup
cp -- "${DOCKER_ROOT}/deployment.json" "${TEST_ROOT}/dual-deployment.json"
for mutation in \
    '.compose.profiles |= map(select(. != "nginx"))' \
    '.compose.profiles |= map(select(. != "subscription"))' \
    '.compose.profiles += ["net-wireguard"]'; do
    jq "${mutation}" "${TEST_ROOT}/dual-deployment.json" >"${DOCKER_ROOT}/deployment.json"
    runControl 15 edit-reject-mismatched-profiles edit --preview
    assertEditCleanup
done
cp -- "${TEST_ROOT}/dual-deployment.json" "${DOCKER_ROOT}/deployment.json"
DUAL_LIVE_HASH=$(editLiveHash)
for mutation in \
    'del(.core.protocols[0].core)' \
    '.core.secondary_type = null' \
    '.core.secondary_type = "xray"' \
    '.core.protocols |= map(select(.core == "xray"))' \
    '.core.protocols |= map(select(.core == "sing-box")) | .tls = null | .subscription.enabled = false' \
    '(.core.protocols[] | select(.id == 21) | .core) = "sing-box"' \
    '.core.protocols[-1].public_port = .core.protocols[1].public_port' \
    '.core.protocols[-1].public_port = 10087' \
    '.host_integrations = [{type:"wireguard",profile:"net-wireguard",
      firewall_rules:[],devices:["wg-padm"],schedules:[],
      settings:{config_file:"wg-padm.conf",interface:"wg-padm"}}]'; do
    jq "${mutation}" "${DUAL_SPEC}" >"${TEST_ROOT}/dual-invalid.json"
    runControl 15 reject-dual-core-conflict configure --spec "${TEST_ROOT}/dual-invalid.json"
    [[ "$(editLiveHash)" == "${DUAL_LIVE_HASH}" ]] || fail 'invalid dual-core request changed live state'
    assertEditCleanup
done
jq '(.core.protocols[] | select(.listener_id == "vless-reality") | .core) = "sing-box"' \
    "${DUAL_SPEC}" >"${TEST_ROOT}/dual-invalid.json"
runControl 15 edit-reject-existing-entry-core-change edit --spec "${TEST_ROOT}/dual-invalid.json" --preview
[[ "$(editLiveHash)" == "${DUAL_LIVE_HASH}" ]] || fail 'entry ownership rewrite changed live configuration'
for mode in core-validate-fail sing-box-validate-fail; do
    FAKE_DOCKER_MODE="${mode}" runControl 15 reject-invalid-dual-core-candidate \
        configure --spec "${DUAL_SPEC}"
    [[ "$(editLiveHash)" == "${DUAL_LIVE_HASH}" ]] || fail 'one invalid core changed the other live core'
done
jq '.core.protocols[-1].public_port = 32443' "${DUAL_SPEC}" >"${TEST_ROOT}/dual-changed.json"
for mode in fail-next-up fail-next-sing-box-up; do
    rm -f -- "${TEST_ROOT}/fail-once"
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${mode}" runControl 14 dual-core-start-failure-restores-both \
        configure --spec "${TEST_ROOT}/dual-changed.json"
    [[ "$(editLiveHash)" == "${DUAL_LIVE_HASH}" ]] ||
        fail 'dual-core startup failure did not restore both configs, TLS, subscription and traffic'
    grep ' up -d ' "${DOCKER_LOG}" | grep ' --profile core-xray ' |
        grep -q ' --profile core-sing-box ' ||
        fail 'dual-core recovery did not restart both core profiles'
    assertEditCleanup
done
REMOVE_SECONDARY_LOG_START=$(wc -l <"${DOCKER_LOG}")
jq '.core.secondary_type = null | .core.protocols |= map(select(.core == "xray"))' \
    "${DUAL_SPEC}" >"${TEST_ROOT}/dual-primary-only.json"
runControl 0 edit-disable-secondary-core edit --spec "${TEST_ROOT}/dual-primary-only.json" --confirm PADM-DOCKER-EDIT
tail -n "+$((REMOVE_SECONDARY_LOG_START + 1))" "${DOCKER_LOG}" | grep -q -- ' up -d .*--remove-orphans' ||
    fail 'disabling the secondary core did not remove orphaned services'
[[ ! -s "${DOCKER_ROOT}/config/sing-box/config.json" ]] ||
    fail 'secondary-core configuration survived disabling it'
jq -e '.core.secondary_type == null and (.compose.profiles | index("core-sing-box")) == null and
  all(.listeners[]; .service != "sing-box")' "${DOCKER_ROOT}/deployment.json" >/dev/null ||
    fail 'disabled secondary core survived deployment state'
[[ "$(wc -l <"${DOCKER_ROOT}/data/subscription/0123456789abcdef")" -eq 4 ]] ||
    fail 'secondary-core removal retained a stale subscription node'
assertEditCleanup

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
      ([.protocols[] | select(.status == "supported") | .id] | sort) == [1, 2, 3, 4, 5, 21, 26, 28, 30, 31] and
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
(.protocols[] | select(.id == 29)) |= (.status = "supported" | .profiles = ["core-sing-box"])
.feature_matrix.subscription.requires.core = "sing-box"
.feature_matrix.subscription.requires.protocol_ids = [1]
.feature_matrix.subscription.requires.tls = false
.feature_matrix["core-upgrade-assessment"].status = "supported"
EOF

printf 'docker-phase3-regression-ok\n'
