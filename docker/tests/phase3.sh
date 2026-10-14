#!/usr/bin/env bash
set -euo pipefail

PHASE3_SCOPE=${PADM_DOCKER_PHASE3_SCOPE:-full}
case "${PHASE3_SCOPE}" in
full|edit|entries) ;;
*) printf 'docker-phase3-regression-fail: unknown scope %s\n' "${PHASE3_SCOPE}" >&2; exit 1 ;;
esac

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

if [[ "${FAKE_PHASE3_HOST_SYSTEM}" != Linux ]]; then
cat >"${MOCK_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--format=%a" ]]; then
    printf '600\n'
else
    exec "${FAKE_PHASE3_HOST_STAT}" "$@"
fi
EOF
chmod 0755 "${MOCK_BIN}/stat"
fi

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
    if [[ " ${*} " == *' generate rand --base64 16 '* ]]; then
        [[ "${mode}" != ss-generate-fail ]] || exit 1
        value=$(python3 -c 'import base64,secrets; print(base64.b64encode(secrets.token_bytes(16)).decode())') || exit 1
        printf '%s\n' "${value}" >>"${FAKE_DOCKER_LOG}.ss-generated"
        chmod 0600 "${FAKE_DOCKER_LOG}.ss-generated"
        printf '%s\n' "${value}"
        exit 0
    fi
    if [[ "${mode}" == acme-issue-fail && " ${*} " == *' --issue '* ]]; then
        exit 1
    fi
    if [[ "${mode}" == acme-install-fail && " ${*} " == *' --install-cert '* ]]; then
        exit 1
    fi
    if [[ " ${*} " == *'ssl.cert_time_to_seconds'* ]]; then
        [[ "${mode}" != "tls-validity-fail" ]]
        exit $?
    fi
    if [[ " ${*} " == *'DNS CNAME probe requires nslookup'* ]]; then
        exit 0
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
chmod 0755 "${MOCK_BIN}/uname" "${MOCK_BIN}/id" "${MOCK_BIN}/docker"
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
chmod 0755 "${MOCK_BIN}/systemctl"
cp "${MOCK_BIN}/systemctl" "${MOCK_BIN}/nsenter"

runControl() {
    local expected=$1 name=$2 actual=0
    shift 2
    if [[ "${CONTROL_USE_DEFAULT_ASSETS:-0}" != 1 &&
        ( "${1:-}" == configure || "${1:-}" == edit || "${1:-}" == reinstall ) ]]; then
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

# 完整集合只在 edit 验收公共迁移自检，独立 entries 仍保留原覆盖。
if [[ "${PADM_DOCKER_CONTRACTS_SHARED_CHECKS:-0}" != 1 || "${PHASE3_SCOPE}" != entries ]]; then
(
    # 真实迁移与草稿校验保留，只隔离宿主门禁并在后续事务开始前停止。
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/normalized-reuse"
    source "${PROJECT_ROOT}/install-docker.sh"
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config"
    cp -- "${REALITY_XRAY_SPEC}" "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    originalMigrate=$(declare -f dockerConfigureSpecMigrate)
    eval "${originalMigrate/dockerConfigureSpecMigrate/phase3OriginalMigrate}"
    dockerConfigureSpecMigrate() {
        printf '%s\n' "$2" >>"${TEST_ROOT}/reuse-migrations"
        phase3OriginalMigrate "$@"
    }
    dockerHostPreflight() { :; }
    dockerLockInstalledDeployment() { :; }
    dockerComposeFile() { :; }
    dockerEditBaselineValidate() { :; }
    dockerAcmeWebrootTransitionValidate() {
        [[ "$(stat -c %a "$1")" == 600 &&
            "$(stat -c %a "${1%/*}/original.json")" == 600 &&
            "$(stat -c %a "${1%/*}")" == 700 ]] || fail '复用草稿放宽私密输入权限'
        printf 'validated\n' >>"${TEST_ROOT}/reuse-validated"
        return 1
    }
    cp() {
        if [[ "${reuseCase}" == copy-fail && "${2##*/}" == normalized.json &&
            "${3##*/}" == draft.json ]]; then return 17; fi
        command cp "$@"
    }
    for reuseCase in normal external invalid-external copy-fail; do
        : >"${TEST_ROOT}/reuse-migrations"
        : >"${TEST_ROOT}/reuse-validated"
        arguments=(--preview)
        expectedMigrations=1 expectedValidated=1
        case "${reuseCase}" in
        external) arguments+=(--spec "${REALITY_XRAY_SPEC}"); expectedMigrations=2 ;;
        invalid-external)
            arguments+=(--spec "${UNSUPPORTED_SPEC}")
            expectedMigrations=2 expectedValidated=0 ;;
        copy-fail) expectedValidated=0 ;;
        esac
        actual=0
        dockerEditCommand "${arguments[@]}" >"${TEST_ROOT}/reuse.log" 2>&1 || actual=$?
        [[ "${actual}" == "${PADM_DOCKER_RC_STATE}" &&
            "$(wc -l <"${TEST_ROOT}/reuse-migrations")" == "${expectedMigrations}" &&
            "$(wc -l <"${TEST_ROOT}/reuse-validated")" == "${expectedValidated}" ]] ||
            fail "normalized 复用、外部输入迁移或复制失败边界错误: ${reuseCase}"
        dockerSetupCleanup || fail '复用草稿未清理'
    done
)
fi

if [[ "${PHASE3_SCOPE}" != entries ]]; then
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
fi

runControl 0 install install --source "${PROJECT_ROOT}"
if [[ "${PHASE3_SCOPE}" != entries ]]; then
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
grep -qF '命中已知 CDN 风险名单' "${CONTROL_LOG}" || fail 'known relay Reality target was not rejected'
FAKE_DOCKER_MODE=reality-asn-risk runControl 15 reject-reality-as13335 configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '(cloudflare_relay)' "${CONTROL_LOG}" || fail 'AS13335 Reality target was not rejected'
FAKE_DOCKER_MODE=reality-sni-risk runControl 15 reject-reality-cloudflare-sni configure --spec "${REALITY_XRAY_SPEC}"
grep -qF '(cloudflare_relay)' "${CONTROL_LOG}" || fail 'Cloudflare SNI relay was not rejected'
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
fi

CERT_FILE="${TEST_ROOT}/proxy.example.com.crt"
KEY_FILE="${TEST_ROOT}/proxy.example.com.key"
printf 'fake-certificate\n' >"${CERT_FILE}"
printf 'fake-private-key\n' >"${KEY_FILE}"
chmod 0600 "${KEY_FILE}"
runControl 0 tls-install tls install --domain proxy.example.com --cert "${CERT_FILE}" \
    --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
[[ -f "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ]] || fail 'TLS certificate was not installed'

if [[ "${PHASE3_SCOPE}" != entries ]]; then
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
fi

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
        \( -name '.candidate.*' -o -name '.edit.*' -o -name '.reinstall.*' \) -print -quit)" ]] ||
        fail 'edit left a configuration candidate or draft directory'
}
runEditPty() {
    local command fifo="${TEST_ROOT}/edit-pty.input" completed="${TEST_ROOT}/edit-pty.done"
    local input=${1:-$'1\n1\n25446\n8\nn\n'} expected=${2:-0}
    local feeder actual=0 feederStatus=0
    rm -f -- "${fifo}" "${completed}"
    mkfifo "${fifo}"
    printf -v command '%q ' bash -u "${PROJECT_ROOT}/install-docker.sh" "${PHASE3_PTY_COMMAND:-edit}" "${@:3}" \
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
if [[ "${PHASE3_SCOPE}" != entries ]]; then
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

# 已受管的 Geo 是独立维护输入，编辑协议不能丢失文件或切回镜像路径。
mkdir -p "${DOCKER_ROOT}/config/xray/geo"
printf 'geoip-fixture\n' >"${DOCKER_ROOT}/config/xray/geo/geoip.dat"
printf 'geosite-fixture\n' >"${DOCKER_ROOT}/config/xray/geo/geosite.dat"
jq -n --arg geoip "$(sha256sum "${DOCKER_ROOT}/config/xray/geo/geoip.dat" | cut -d ' ' -f1)" \
    --arg geosite "$(sha256sum "${DOCKER_ROOT}/config/xray/geo/geosite.dat" | cut -d ' ' -f1)" \
    '{schema_version:1,version:"202610070140",enabled:false,
      sha256:{"geoip.dat":$geoip,"geosite.dat":$geosite}}' >"${DOCKER_ROOT}/config/xray/geo/state.json"
GEO_HASH=$(sha256sum "${DOCKER_ROOT}/config/xray/geo/"*)
jq '.services.xray.environment.XRAY_LOCATION_ASSET = "/etc/padm/xray/geo"' \
    "${DOCKER_ROOT}/compose.json" >"${TEST_ROOT}/geo-compose.json"
cp -- "${TEST_ROOT}/geo-compose.json" "${DOCKER_ROOT}/compose.json"
runControl 0 edit-confirm-port edit --spec "${EDIT_SPEC}" --confirm PADM-DOCKER-EDIT
[[ "$(sha256sum "${DOCKER_ROOT}/config/xray/geo/"*)" == "${GEO_HASH}" ]] || fail 'edit lost managed Geo data'
jq -e '.services.xray.environment.XRAY_LOCATION_ASSET == "/etc/padm/xray/geo"' \
    "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'edit changed managed Geo asset path'
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
        "$("${FAKE_PHASE3_HOST_STAT}" -c %a "${DOCKER_ROOT}/config/xray/users.base")" == 600 &&
        "$("${FAKE_PHASE3_HOST_STAT}" -c %a "${DOCKER_ROOT}/config/nginx/default.conf")" == 640 ]] ||
        fail 'edit did not retain private spec and runtime configuration permissions'
    if [[ "${TEST_SKIP_CHOWN}" == 0 ]]; then
        [[ "$("${FAKE_PHASE3_HOST_STAT}" -c %u:%g "${DOCKER_ROOT}/config/spec.json")" == 0:0 &&
            "$("${FAKE_PHASE3_HOST_STAT}" -c %u:%g "${DOCKER_ROOT}/config/xray/users.base")" == 0:0 &&
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
fi

if [[ "${PHASE3_SCOPE}" == entries ]]; then
    # 独立生成切点前的受管状态，保留非零流量和 Geo，避免弱化后续恢复断言。
    jq '.schema_version = 3 | .core.secondary_type = null |
        .core.protocols |= map(.core = "xray")' "${EDIT_SPEC}" >"${TEST_ROOT}/edit-v3.json"
    runControl 0 configure-entry-baseline configure --spec "${TEST_ROOT}/edit-v3.json"
    mkdir -p "${DOCKER_ROOT}/data/traffic" "${DOCKER_ROOT}/config/xray/geo"
    printf '%s\n' '{"schema_version":1,"accounts":{"11111111-1111-4111-8111-111111111111":{"name":"main-xray","upload":7,"download":11,"limit_bytes":0,"baseline":{}}}}' \
        >"${DOCKER_ROOT}/data/traffic/state.json"
    chmod 0600 "${DOCKER_ROOT}/data/traffic/state.json"
    printf 'geoip-fixture\n' >"${DOCKER_ROOT}/config/xray/geo/geoip.dat"
    printf 'geosite-fixture\n' >"${DOCKER_ROOT}/config/xray/geo/geosite.dat"
    jq -n --arg geoip "$(sha256sum "${DOCKER_ROOT}/config/xray/geo/geoip.dat" | cut -d ' ' -f1)" \
        --arg geosite "$(sha256sum "${DOCKER_ROOT}/config/xray/geo/geosite.dat" | cut -d ' ' -f1)" \
        '{schema_version:1,version:"202610070140",enabled:false,
          sha256:{"geoip.dat":$geoip,"geosite.dat":$geosite}}' >"${DOCKER_ROOT}/config/xray/geo/state.json"
    jq '.services.xray.environment.XRAY_LOCATION_ASSET = "/etc/padm/xray/geo"' \
        "${DOCKER_ROOT}/compose.json" >"${TEST_ROOT}/geo-compose.json"
    cp -- "${TEST_ROOT}/geo-compose.json" "${DOCKER_ROOT}/compose.json"
fi

if [[ "${PHASE3_SCOPE}" != edit ]]; then
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
grep -q -- '--issue --dns dns_cf --keylength ec-256 -d proxy.example.com' "${DOCKER_LOG}" || fail 'ECC ACME issue was not run'
grep -q -- '--install-cert -d proxy.example.com --ecc' "${DOCKER_LOG}" || fail 'ECC ACME install-cert was not run'
grep -qxF 'fake-acme-certificate' "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'ACME certificate was not committed'

# 新增、删除和保身份重建复用 entries 的真实候选事务，不重复核心与协议矩阵。
protocolEdit() {
    local expected=$1 name=$2 before
    shift 2
    before=$(editLiveHash)
    : >"${DOCKER_LOG}"
    runControl "${expected}" "${name}" edit "$@"
    assertEditCleanup
    if [[ "${expected}" != 0 || " $* " == *' --preview '* ]]; then
        [[ "$(editLiveHash)" == "${before}" ]] || fail "${name}: 拒绝、预览或失败恢复改变在线状态"
    fi
    if [[ " $* " == *' --preview '* ]]; then
        ! grep -Eq ' (up|down|restart|exec) ' "${DOCKER_LOG}" ||
            fail "${name}: 预览改变服务或采集流量"
    fi
}
PROTOCOL_BASE="${TEST_ROOT}/protocol-base.json"
jq '.schema_version=3 | .core.secondary_type=null | .core.protocols |= map(.core="xray") |
  .accounts=[{id:"33333333-3333-4333-8333-333333333333",name:"business",enabled:true,
    uuid:"44444444-4444-4444-8444-444444444444",password:"Business.Password1",
    shadowsocks_password:null,listeners:["vless-reality","vless-ws"]}]' \
    "${EDIT_SPEC}" >"${PROTOCOL_BASE}"
runControl 0 protocol-management-baseline configure --spec "${PROTOCOL_BASE}"
PROTOCOL_TRAFFIC_HASH=$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)
# 旧格式先迁移私密草稿；预览和取消保留线上格式，确认才写入 v3。
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version=$version | del(.accounts,.core.secondary_type) |
      .core.protocols |= map(del(.core) |
        if $version==1 then del(.listener_id,.websocket.backend_port,.websocket.tls_port) else . end)' \
        "${PROTOCOL_BASE}" >"${TEST_ROOT}/protocol-legacy.json"
    runControl 0 "protocol-v${version}-baseline" configure --spec "${TEST_ROOT}/protocol-legacy.json"
    protocolEdit 0 "protocol-v${version}-preview" --protocol-add vless-reality 2 28443 --preview
    if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
        legacyHash=$(editLiveHash)
        runEditPty $'n\n' 0 --protocol-add vless-reality 2 28443
        [[ "$(editLiveHash)" == "${legacyHash}" ]] || fail "v${version} 取消迁移改变在线格式"
        assertEditCleanup
    fi
    protocolEdit 0 "protocol-v${version}-commit" --protocol-add vless-reality 2 28443 --confirm PADM-DOCKER-EDIT
    jq -e '.schema_version==3 and .core.secondary_type==null and
      any(.core.protocols[]; .listener_id=="entry-1" and .id==2) and
      any(.core.protocols[]; .listener_id=="vless-ws" and .core=="xray" and
        .websocket.backend_port==31297 and .websocket.tls_port==8443)' \
        "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail "v${version} 增量未迁移固定入口身份"
done
runControl 0 protocol-restore-v3-baseline configure --spec "${PROTOCOL_BASE}"
protocolEdit 2 protocol-add-usage --protocol-add vless-reality 2 0 --preview
protocolEdit 2 protocol-core-needs-add --protocol-rebuild vless-reality --protocol-core sing-box --preview
protocolEdit 2 protocol-core-invalid --protocol-add vless-reality 2 28443 --protocol-core invalid --preview
protocolEdit 2 protocol-actions-exclusive --protocol-add vless-reality 2 28443 \
    --protocol-remove vless-ws --preview
protocolEdit 15 protocol-add-core-boundary --protocol-add vless-ws 31 28443 --preview
protocolEdit 0 protocol-add-preview --protocol-add vless-reality 2 28443 --preview
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    PROTOCOL_CANCEL_HASH=$(editLiveHash)
    : >"${DOCKER_LOG}"
    runEditPty $'n\n' 0 --protocol-add vless-reality 2 28443
    [[ "$(editLiveHash)" == "${PROTOCOL_CANCEL_HASH}" ]] || fail '取消新增协议改变在线状态'
    ! grep -Eq ' (up|down|restart|exec) ' "${DOCKER_LOG}" || fail '取消新增协议改变服务或采集流量'
    assertEditCleanup
fi
protocolEdit 0 protocol-add-reality --protocol-add vless-reality 2 28443 --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" '
  (.core.protocols[] | select(.listener_id == "vless-reality")) as $source |
  (.core.protocols | length) == 3 and
  (.core.protocols | map(select(.listener_id != "entry-1"))) == $before[0].core.protocols and
  (. | del(.core.protocols)) == ($before[0] | del(.core.protocols)) and
  any(.core.protocols[]; .listener_id == "entry-1" and .id == 2 and .core == $source.core and
    .uuid == $source.uuid and .server == $source.server and .name == $source.name and
    .address_families == $source.address_families and .reality == $source.reality and
    .public_port == 28443 and
    .xhttp == {path:"/entry-1xhttp",host:$source.reality.server_name,mode:"auto"})
' "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
    fail '新增 Reality 传输改变既有身份、账号关联、TLS、发布或模板参数'
jq -e 'any(.inbounds[]; .tag=="entry-1" and .port==28443 and .streamSettings.network=="xhttp")' \
    "${DOCKER_ROOT}/config/xray/config.json" >/dev/null || fail '新增协议未进入实际核心配置'
grep -q '@proxy.example.com:28443.*type=xhttp' "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
    fail '新增协议未进入既有订阅'
cp -- "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/protocol-added.json"
# 普通规格导入仍不能新增不同 TLS 协议，专项豁免也不能借外部规格改其它字段。
jq '.core.protocols += [(.core.protocols[] | select(.listener_id=="vless-ws") |
  del(.websocket) | .id=28 | .listener_id="entry-foreign" | .public_port=29443 |
  .trojan={domain:"proxy.example.com"})]' "${TEST_ROOT}/protocol-added.json" \
    >"${TEST_ROOT}/protocol-foreign.json"
protocolEdit 15 protocol-import-not-authorized --spec "${TEST_ROOT}/protocol-foreign.json" --preview
protocolEdit 2 protocol-add-cannot-import --protocol-add vless-reality 26 29443 \
    --spec "${TEST_ROOT}/protocol-foreign.json" --preview
protocolEdit 0 protocol-rebuild-preview --protocol-rebuild entry-1 --preview
PROTOCOL_REBUILD_HASH=$(editLiveHash)
protocolEdit 0 protocol-rebuild-identity --protocol-rebuild entry-1 --confirm PADM-DOCKER-EDIT
[[ "$(editLiveHash)" == "${PROTOCOL_REBUILD_HASH}" ]] || fail '保身份重建改变规格、凭据或业务文件'
grep -q ' run --rm --no-deps xray -test ' "${DOCKER_LOG}" &&
    grep -q -- ' up -d .*--force-recreate' "${DOCKER_LOG}" || fail '重建未重新验证并重建核心'
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up protocolEdit 14 protocol-rebuild-failure \
    --protocol-rebuild entry-1 --confirm PADM-DOCKER-EDIT
protocolEdit 0 protocol-remove-preview --protocol-remove entry-1 --preview
protocolEdit 0 protocol-remove-reality --protocol-remove entry-1 --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" '.==$before[0]' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '直接删除派生入口没有恢复原完整规格'
protocolEdit 0 protocol-remove-account-link --protocol-remove vless-ws --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" '
  .accounts == ($before[0].accounts | map(.listeners=["vless-reality"])) and
  .subscription.token==$before[0].subscription.token and .tls==null and
  .subscription.enabled==false and (.core.protocols | length)==1
' "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '删除入口未精确裁剪账号关联或保留订阅身份'
protocolEdit 15 protocol-remove-last-account-link --protocol-remove vless-reality --preview
[[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)" == \
    "${PROTOCOL_TRAFFIC_HASH}" ]] || fail '协议增删或重建改变累计流量与额度'

PROTOCOL_TLS="${TEST_ROOT}/protocol-tls.json"
jq '.core.type="sing-box" | .core.secondary_type=null |
  .core.protocols=[(.core.protocols[] | select(.listener_id=="vless-reality") |
    del(.reality) | .id=3 | .core="sing-box" | .listener_id="entry-hy2" |
    .server="node.example.com" |
    .hy2={domain:"proxy.example.com",bandwidth_mode:"bbr",up_mbps:100,down_mbps:50,
      obfs:null,masquerade:""})] |
  .accounts |= map(.listeners=["entry-hy2"]) | .subscription.enabled=false' \
    "${PROTOCOL_BASE}" >"${PROTOCOL_TLS}"
runControl 0 protocol-tls-management-baseline configure --spec "${PROTOCOL_TLS}"
(
    source "${PROJECT_ROOT}/install-docker.sh"
    generated="${TEST_ROOT}/protocol-generated.json"
    dockerEditEntryAdd "${PROTOCOL_TLS}" entry-hy2 5 sing-box 29445 protocol "${generated}" &&
        dockerConfigureSpecValidate "${generated}" || fail 'Naive 派生草稿无效'
    jq -e '.core.protocols[-1].id==5 and
      .core.protocols[-1].server=="proxy.example.com" and
      .core.protocols[-1].naive.domain=="proxy.example.com"' "${generated}" >/dev/null ||
        fail 'Naive 新增没有使用已有 TLS 域名作为服务器'
    dockerEditEntryAdd "${PROTOCOL_BASE}" vless-ws 23 xray 29446 protocol "${generated}" &&
        dockerConfigureSpecValidate "${generated}" || fail 'HTTPUpgrade 派生草稿无效'
    jq -e '.core.protocols[-1].httpupgrade=={domain:"proxy.example.com",path:"entry-1path",
      backend_port:31306,tls_port:8444}' "${generated}" >/dev/null ||
        fail '不同 Nginx 协议新增没有分配独立内部端口'
    jq '.core.protocols |= map(if .id==21 then
      del(.websocket) | .id=27 | .listener_id="entry-fallback" | .fallback_tls={domain:"proxy.example.com",
        http_port:31300,http2_port:31302} else . end) |
      .accounts |= map(.listeners |= map(if .=="vless-ws" then "entry-fallback" else . end)) |
      .subscription.enabled=false' "${PROTOCOL_BASE}" >"${TEST_ROOT}/protocol-fallback.json"
    dockerEditEntryAdd "${TEST_ROOT}/protocol-fallback.json" entry-fallback 27 xray 29448 copy "${generated}" &&
        dockerConfigureSpecValidate "${generated}" &&
        dockerEditCompatibilityValidate "${TEST_ROOT}/protocol-fallback.json" "${generated}" ||
        fail 'fallback 复制草稿或普通兼容门禁无效'
    jq -e '.core.protocols[-1].fallback_tls==
      (.core.protocols[] | select(.listener_id=="entry-fallback") | .fallback_tls)' \
        "${generated}" >/dev/null || fail '复制 fallback 没有保留共享后端'
    dockerEditEntryAdd "${TEST_ROOT}/protocol-fallback.json" entry-fallback 29 xray 29449 protocol \
        "${generated}" && dockerConfigureSpecValidate "${generated}" ||
        fail '新增不同 fallback 协议的草稿无效'
    jq -e '[.core.protocols[] | select(.id==27 or .id==29) |
      .fallback_tls.http_port,.fallback_tls.http2_port] | length==4 and (unique | length)==4' \
        "${generated}" >/dev/null || fail '不同 fallback 协议新增没有避开两条内部监听'
    jq '.tls=null' "${PROTOCOL_TLS}" >"${TEST_ROOT}/protocol-no-tls.json"
    jq '.host_integrations=[{type:"wireguard",settings:{}}]' "${PROTOCOL_TLS}" \
        >"${TEST_ROOT}/protocol-host.json"
    for entryCase in no-tls unsupported-core xray-shadowsocks host-secondary; do
        spec="${PROTOCOL_TLS}" core=sing-box target=31
        case "${entryCase}" in
        no-tls) spec="${TEST_ROOT}/protocol-no-tls.json" ;;
        unsupported-core) core=xray target=31 ;;
        xray-shadowsocks) core=xray target=30 ;;
        host-secondary) spec="${TEST_ROOT}/protocol-host.json" core=xray target=28 ;;
        esac
        if dockerEditEntryAdd "${spec}" entry-hy2 "${target}" "${core}" 29447 protocol \
            "${generated}" >"${TEST_ROOT}/protocol-helper.log" 2>&1; then
            fail "新增协议突破支持边界: ${entryCase}"
        fi
    done
) || fail '协议新增模板或核心/TLS 支持边界错误'
protocolEdit 0 protocol-add-tuic-preview --protocol-add entry-hy2 31 29443 --preview
protocolEdit 0 protocol-add-tuic --protocol-add entry-hy2 31 29443 --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_TLS}" '
  .core.protocols[0] as $source |
  (. | del(.core.protocols))==($before[0] | del(.core.protocols)) and
  (.core.protocols | map(select(.listener_id!="entry-1")))==$before[0].core.protocols and
  any(.core.protocols[]; .listener_id=="entry-1" and .id==31 and .core=="sing-box" and
    .server==$source.server and .uuid==$source.uuid and .address_families==$source.address_families and
    .public_port==29443 and .tuic=={domain:"proxy.example.com",congestion_control:"cubic",
      auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false})
' "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '已有 TLS 新增 TUIC 未保持原部署身份'
jq -e 'any(.inbounds[]; .tag=="entry-1" and .type=="tuic" and .listen_port==29443)' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail '新增 TUIC 未进入实际核心配置'
protocolEdit 0 protocol-remove-tuic --protocol-remove entry-1 --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_TLS}" '.==$before[0]' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail 'TUIC 删除没有保留已有 TLS 和账号'
[[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)" == \
    "${PROTOCOL_TRAFFIC_HASH}" ]] || fail 'TLS 协议增删改变累计流量与额度'

# 已有受管 TLS 可显式新增副核心，保留主核心、原入口、证书、账号关联和累计。
runControl 0 protocol-dual-tls-baseline configure --spec "${PROTOCOL_BASE}"
PROTOCOL_TLS_HASH=$(find "${DOCKER_ROOT}/secrets/tls" -type f -print0 | sort -z |
    xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)
protocolEdit 0 protocol-dual-tls-preview --protocol-add vless-ws 31 30443 \
    --protocol-core sing-box --preview
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-sing-box-up protocolEdit 14 protocol-dual-tls-failure \
    --protocol-add vless-ws 31 30443 --protocol-core sing-box --confirm PADM-DOCKER-EDIT
protocolEdit 0 protocol-dual-tls-commit --protocol-add vless-ws 31 30443 \
    --protocol-core sing-box --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" '
  (.core.protocols | map(select(.listener_id!="entry-1")))==$before[0].core.protocols and
  (. | del(.core.protocols,.core.secondary_type))==
    ($before[0] | del(.core.protocols,.core.secondary_type)) and
  .core.type=="xray" and .core.secondary_type=="sing-box" and
  any(.core.protocols[]; .listener_id=="entry-1" and .id==31 and .core=="sing-box" and
    .uuid=="22222222-2222-4222-8222-222222222222" and .public_port==30443 and
    .tuic.domain=="proxy.example.com")
' "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '跨核心 TLS 增量改变主核心或既有业务身份'
jq -e 'any(.inbounds[]; .tag=="entry-1" and .type=="tuic" and .listen_port==30443)' \
    "${DOCKER_ROOT}/config/sing-box/config.json" >/dev/null || fail '跨核心新增没有生成 TUIC 配置'
[[ "$(find "${DOCKER_ROOT}/secrets/tls" -type f -print0 | sort -z |
    xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)" == "${PROTOCOL_TLS_HASH}" ]] ||
    fail '跨核心新增改写既有证书'
(
    source "${PROJECT_ROOT}/install-docker.sh"
    dockerEditEntryAdd "${PROTOCOL_BASE}" vless-ws 3 sing-box 30444 protocol \
        "${TEST_ROOT}/protocol-dual-hy2.json" &&
        dockerConfigureSpecValidate "${TEST_ROOT}/protocol-dual-hy2.json" ||
        fail '已有 Xray TLS 不能生成 Hy2 副核心草稿'
) || fail '跨核心 TLS 模板失败'
protocolEdit 0 protocol-dual-tls-remove --protocol-remove entry-1 --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" '.==$before[0]' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '移除新增副核心未恢复原规格'

# 无 TLS 的 Shadowsocks 增量只生成两把独立 16 字节密钥，复制和重用保持原密钥。
jq '.core.protocols |= map(select(.id==1)) | .tls=null | .subscription.enabled=false |
  .accounts |= map(.listeners=["vless-reality"])' "${PROTOCOL_BASE}" \
    >"${TEST_ROOT}/protocol-ss-base.json"
runControl 0 protocol-ss-baseline configure --spec "${TEST_ROOT}/protocol-ss-base.json"
protocolEdit 15 protocol-without-tls-rejected --protocol-add vless-reality 31 31443 \
    --protocol-core sing-box --preview
assertSsPrivate() {
    local secret
    while IFS= read -r secret; do
        ! grep -Fq -- "${secret}" "${CONTROL_LOG}" "${DOCKER_LOG}" ||
            fail 'Shadowsocks 密钥出现在预览、业务输出或外部 argv'
    done <"${DOCKER_LOG}.ss-generated"
}
FAKE_DOCKER_MODE=ss-generate-fail protocolEdit 15 protocol-ss-generation-failure \
    --protocol-add vless-reality 30 31443 --protocol-core sing-box --confirm PADM-DOCKER-EDIT
protocolEdit 0 protocol-ss-preview --protocol-add vless-reality 30 31443 --protocol-core sing-box --preview
assertSsPrivate
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-sing-box-up protocolEdit 14 protocol-ss-start-failure \
    --protocol-add vless-reality 30 31443 --protocol-core sing-box --confirm PADM-DOCKER-EDIT
assertSsPrivate
protocolEdit 0 protocol-ss-commit --protocol-add vless-reality 30 31443 \
    --protocol-core sing-box --confirm PADM-DOCKER-EDIT
assertSsPrivate
python3 - "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/protocol-ss-base.json" \
    "${DOCKER_ROOT}/config/sing-box/config.json" <<'PY'
import base64
import json
from pathlib import Path
import sys

spec, original, config = (json.loads(Path(path).read_text()) for path in sys.argv[1:])
entry = next(entry for entry in spec["core"]["protocols"] if entry["id"] == 30)
passwords = [entry["shadowsocks"][key] for key in ("server_password", "user_password")]
assert passwords[0] != passwords[1]
for password in passwords:
    decoded = base64.b64decode(password, validate=True)
    assert len(decoded) == 16 and base64.b64encode(decoded).decode() == password
assert spec["core"]["type"] == "xray" and spec["core"]["secondary_type"] == "sing-box"
assert [entry for entry in spec["core"]["protocols"] if entry["id"] != 30] == original["core"]["protocols"]
for key in ("accounts", "subscription", "release", "tls"):
    assert spec[key] == original[key], key
runtime = next(inbound for inbound in config["inbounds"] if inbound["type"] == "shadowsocks")
assert runtime["password"] == passwords[0] and runtime["users"][0]["password"] == passwords[1]
PY
cp -- "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/protocol-ss-installed.json"
ssGenerations=$(wc -l <"${DOCKER_LOG}.ss-generated")
protocolEdit 0 protocol-ss-same-protocol --protocol-add entry-1 30 31444 --confirm PADM-DOCKER-EDIT
[[ "$(wc -l <"${DOCKER_LOG}.ss-generated")" == "${ssGenerations}" ]] ||
    fail '同协议新增重新生成 Shadowsocks 密钥'
jq -e --slurpfile before "${TEST_ROOT}/protocol-ss-installed.json" '
  (.core.protocols | map(select(.listener_id!="entry-2")))==$before[0].core.protocols and
  (.core.protocols[] | select(.listener_id=="entry-2") | .shadowsocks)==
    ($before[0].core.protocols[] | select(.listener_id=="entry-1") | .shadowsocks)
' "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '同协议新增改变已有 Shadowsocks 密钥'
(
    source "${PROJECT_ROOT}/install-docker.sh"
    dockerEditEntryAdd "${TEST_ROOT}/protocol-ss-installed.json" entry-1 30 sing-box 31445 copy \
        "${TEST_ROOT}/protocol-ss-copy.json" &&
        dockerConfigureSpecValidate "${TEST_ROOT}/protocol-ss-copy.json" &&
        dockerEditCompatibilityValidate "${TEST_ROOT}/protocol-ss-installed.json" \
            "${TEST_ROOT}/protocol-ss-copy.json" || fail 'Shadowsocks 复制草稿或兼容门禁失败'
    jq -e '.core.protocols[-1].shadowsocks==
      (.core.protocols[] | select(.listener_id=="entry-1") | .shadowsocks)' \
        "${TEST_ROOT}/protocol-ss-copy.json" >/dev/null || fail 'Shadowsocks 复制改写已有密钥'
    dockerEditEntryAdd "${TEST_ROOT}/protocol-ss-installed.json" vless-reality 30 sing-box 31446 protocol \
        "${TEST_ROOT}/protocol-ss-reused.json" &&
        dockerConfigureSpecValidate "${TEST_ROOT}/protocol-ss-reused.json" ||
        fail '同 UUID 的其它源入口不能复用 Shadowsocks 身份'
    jq -e '.core.protocols[-1].shadowsocks==
      (.core.protocols[] | select(.listener_id=="entry-1") | .shadowsocks)' \
        "${TEST_ROOT}/protocol-ss-reused.json" >/dev/null || fail '同 UUID 来源新增改写原 Shadowsocks 密钥'
) || fail 'Shadowsocks 复制身份失败'
[[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)" == \
    "${PROTOCOL_TRAFFIC_HASH}" ]] || fail '旧版迁移、跨核心或 Shadowsocks 增量改变累计与额度'

# 首个 TLS 协议只追加本次入口和域名；四种来源复用已有证书事务。
FIRST_TLS_REALITY="${TEST_ROOT}/protocol-ss-base.json"
FIRST_TLS_SS="${TEST_ROOT}/protocol-ss-installed.json"
mkdir -p "${DOCKER_ROOT}/data/acme/unrelated"
printf 'keep-acme-account\n' >"${DOCKER_ROOT}/data/acme/unrelated/account.conf"
chmod 0600 "${DOCKER_ROOT}/data/acme/unrelated/account.conf"
FIRST_TLS_UNRELATED_HASH=$(sha256sum "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" \
    "${DOCKER_ROOT}/secrets/tls/proxy.example.com.key" \
    "${DOCKER_ROOT}/data/acme/unrelated/account.conf" | sha256sum | cut -d ' ' -f 1)
firstTlsEdit() {
    local expected=$1 name=$2 acmeHash
    shift 2
    acmeHash=$(find "${DOCKER_ROOT}/data/acme" -type f -print0 | sort -z |
        xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)
    protocolEdit "${expected}" "${name}" "$@"
    if [[ "${expected}" != 0 || " $* " == *' --preview '* ]]; then
        [[ "$(find "${DOCKER_ROOT}/data/acme" -type f -print0 | sort -z |
            xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1)" == "${acmeHash}" ]] ||
            fail "${name}: 预览或失败改写 ACME 账号"
    fi
    [[ "$(sha256sum "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" \
        "${DOCKER_ROOT}/secrets/tls/proxy.example.com.key" \
        "${DOCKER_ROOT}/data/acme/unrelated/account.conf" | sha256sum | cut -d ' ' -f 1)" == \
        "${FIRST_TLS_UNRELATED_HASH}" ]] || fail "${name}: 改写其它证书或 ACME 账号"
}
assertFirstTlsSpec() {
    local before=$1 source=$2 domain=$3 protocol=$4 core=$5 port=$6 secondary=$7
    jq -e --slurpfile before "${before}" --arg source "${source}" --arg domain "${domain}" \
        --arg core "${core}" --arg secondary "${secondary}" --argjson protocol "${protocol}" \
        --argjson port "${port}" '
      (.core.protocols[-1]) as $new |
      ($before[0].core.protocols[] | select(.listener_id==$source)) as $source |
      .tls=={domain:$domain} and
      .core.secondary_type==(if $secondary=="" then null else $secondary end) and
      (.core.protocols[0:-1])==$before[0].core.protocols and
      (. | del(.tls,.core.protocols,.core.secondary_type))==
        ($before[0] | del(.tls,.core.protocols,.core.secondary_type)) and
      $new.id==$protocol and $new.core==$core and $new.public_port==$port and
      $new.uuid==$source.uuid and $new.name==$source.name and $new.server==$source.server and
      $new.address_families==$source.address_families and
      ($new.websocket.domain // $new.trojan.domain // $new.tuic.domain)==$domain
    ' "${DOCKER_ROOT}/config/spec.json" >/dev/null || fail '首个 TLS 增量改变其它规格或账号授权'
}
runControl 0 protocol-first-tls-baseline configure --spec "${FIRST_TLS_REALITY}"
firstTlsEdit 15 protocol-first-tls-input-missing --protocol-add vless-reality 21 32443 --preview
firstTlsEdit 15 protocol-first-tls-source-missing --protocol-add vless-reality 21 32443 \
    --tls-domain proxy.example.com --preview
firstTlsEdit 15 protocol-first-tls-domain-missing --protocol-add vless-reality 21 32443 \
    --tls-existing --preview
firstTlsEdit 2 protocol-first-tls-source-exclusive --protocol-add vless-reality 21 32443 \
    --tls-domain proxy.example.com --tls-existing --tls-import "${CERT_FILE}" "${KEY_FILE}" --preview
firstTlsEdit 2 protocol-first-tls-domain-duplicate --protocol-add vless-reality 21 32443 \
    --tls-domain proxy.example.com --tls-domain other.example.com --tls-existing --preview
firstTlsEdit 2 protocol-first-tls-needs-add --protocol-rebuild vless-reality \
    --tls-domain proxy.example.com --tls-existing --preview
firstTlsEdit 2 protocol-first-tls-target-reality --protocol-add vless-reality 2 32443 \
    --tls-domain proxy.example.com --tls-existing --preview
firstTlsEdit 2 protocol-first-tls-domain-invalid --protocol-add vless-reality 21 32443 \
    --tls-domain bad/domain --tls-existing --preview
firstTlsEdit 15 protocol-first-tls-existing-missing --protocol-add vless-reality 21 32443 \
    --tls-domain missing.example.com --tls-existing --preview
firstTlsEdit 15 protocol-first-tls-import-missing --protocol-add vless-reality 21 32443 \
    --tls-domain first-import.example.com --tls-import "${TEST_ROOT}/missing.crt" "${KEY_FILE}" --preview
FAKE_DOCKER_MODE=tls-validate-fail firstTlsEdit 15 protocol-first-tls-invalid-certificate \
    --protocol-add vless-reality 21 32443 --tls-domain proxy.example.com --tls-existing --preview
firstTlsEdit 0 protocol-first-tls-existing-preview --protocol-add vless-reality 21 32443 \
    --tls-domain proxy.example.com --tls-existing --preview
grep -qF '候选配置校验通过，预览未提交。' "${CONTROL_LOG}" ||
    fail '已有证书预览没有完成候选校验'
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    firstTlsCancelHash=$(editLiveHash)
    for input in $'0\n' $'proxy.example.com\n0\n' $'proxy.example.com\n1\nn\n' \
        $'proxy.example.com\n\004'; do
        : >"${DOCKER_LOG}"
        runEditPty "${input}" 0 --protocol-add vless-reality 21 32443
        [[ "$(editLiveHash)" == "${firstTlsCancelHash}" ]] || fail '首个 TLS 交互取消或 EOF 改写线上'
        ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
            fail '首个 TLS 交互取消或 EOF 改动服务或申请证书'
        assertEditCleanup
    done
fi
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up firstTlsEdit 14 protocol-first-tls-up-failure \
    --protocol-add vless-reality 21 32443 --tls-domain proxy.example.com \
    --tls-existing --confirm PADM-DOCKER-EDIT
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    : >"${DOCKER_LOG}"
    runEditPty $'proxy.example.com\n1\ny\n' 0 --protocol-add vless-reality 21 32443
    assertEditCleanup
else
    firstTlsEdit 0 protocol-first-tls-existing-commit --protocol-add vless-reality 21 32443 \
        --tls-domain proxy.example.com --tls-existing --confirm PADM-DOCKER-EDIT
fi
assertFirstTlsSpec "${FIRST_TLS_REALITY}" vless-reality proxy.example.com 21 xray 32443 ''
grep -q 'proxy_pass http://xray:31297;' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Reality 新增首个 WS 没有生成实际 Nginx 后端'
firstTlsEdit 2 protocol-first-tls-already-managed --protocol-add vless-reality 28 32444 \
    --tls-domain other.example.com --tls-import "${CERT_FILE}" "${KEY_FILE}" --preview

runControl 0 protocol-first-tls-import-baseline configure --spec "${FIRST_TLS_REALITY}"
firstTlsEdit 0 protocol-first-tls-import-preview --protocol-add vless-reality 28 32444 \
    --tls-domain first-import.example.com --tls-import "${CERT_FILE}" "${KEY_FILE}" --preview
grep -qF '候选配置校验通过，预览未提交。' "${CONTROL_LOG}" ||
    fail '导入证书预览没有完成候选校验'
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    : >"${DOCKER_LOG}"
    printf -v input 'first-import.example.com\n2\n%s\n%s\ny\n' "${CERT_FILE}" "${KEY_FILE}"
    runEditPty "${input}" 0 --protocol-add vless-reality 28 32444
    assertEditCleanup
else
    firstTlsEdit 0 protocol-first-tls-import-commit --protocol-add vless-reality 28 32444 \
        --tls-domain first-import.example.com --tls-import "${CERT_FILE}" "${KEY_FILE}" --confirm PADM-DOCKER-EDIT
fi
assertFirstTlsSpec "${FIRST_TLS_REALITY}" vless-reality first-import.example.com 28 xray 32444 ''
cmp -s "${CERT_FILE}" "${DOCKER_ROOT}/secrets/tls/first-import.example.com.crt" &&
    cmp -s "${KEY_FILE}" "${DOCKER_ROOT}/secrets/tls/first-import.example.com.key" ||
    fail '导入首个 TLS 证书未提交原始输入'

runControl 0 protocol-first-tls-dns-baseline configure --spec "${FIRST_TLS_SS}"
firstTlsEdit 15 protocol-first-tls-dns-credentials-missing --protocol-add entry-1 31 32445 \
    --tls-domain first-dns.example.com --tls-dns admin@example.com dns_cf "${TEST_ROOT}/missing.env" --preview
firstTlsEdit 2 protocol-first-tls-dns-provider-invalid --protocol-add entry-1 31 32445 \
    --tls-domain first-dns.example.com --tls-dns admin@example.com invalid "${CREDENTIALS}" --preview
for source in dns standalone; do
    tlsArgs=(--tls-dns admin@example.com dns_cf "${CREDENTIALS}")
    [[ "${source}" != standalone ]] || tlsArgs=(--tls-standalone admin@example.com)
    firstTlsEdit 0 "protocol-first-tls-${source}-preview" --protocol-add entry-1 31 32445 \
        --tls-domain first-dns.example.com "${tlsArgs[@]}" --preview
    grep -qF '预览未申请证书或提交' "${CONTROL_LOG}" ||
        fail 'ACME 预览未明确保留计划验收范围'
    ! grep -Eq ' --issue | --install-cert |--publish 0.0.0.0:80:' "${DOCKER_LOG}" ||
        fail 'ACME 预览调用 CA 或占用挑战端口'
done
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    firstTlsCancelHash=$(editLiveHash)
    for input in $'n\n' $'\004'; do
        : >"${DOCKER_LOG}"
        runEditPty "${input}" 0 --protocol-add entry-1 31 32445 --tls-domain first-dns.example.com \
            --tls-dns admin@example.com dns_cf "${CREDENTIALS}"
        [[ "$(editLiveHash)" == "${firstTlsCancelHash}" ]] || fail 'ACME 确认取消或 EOF 改写线上'
        ! grep -Eq ' --issue | --install-cert | (up|down|restart|exec) ' "${DOCKER_LOG}" ||
            fail 'ACME 确认取消或 EOF 仍申请或变更服务'
        assertEditCleanup
    done
fi
for acmeFailure in acme-issue-fail acme-install-fail; do
    FAKE_DOCKER_MODE="${acmeFailure}" firstTlsEdit 15 "protocol-first-tls-${acmeFailure}" \
        --protocol-add entry-1 31 32445 --tls-domain first-dns.example.com \
        --tls-dns admin@example.com dns_cf "${CREDENTIALS}" --confirm PADM-DOCKER-EDIT
done
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    : >"${DOCKER_LOG}"
    printf -v input 'first-dns.example.com\n3\nadmin@example.com\ndns_cf\n%s\ny\n' "${CREDENTIALS}"
    runEditPty "${input}" 0 --protocol-add entry-1 31 32445
    [[ "$(grep -Fc '确认申请证书并在完整候选验证后提交？[y/N]' "${CONTROL_LOG}")" == 1 ]] ||
        fail 'DNS 首个 TLS 没有仅确认一次'
    assertEditCleanup
else
    firstTlsEdit 0 protocol-first-tls-dns-commit --protocol-add entry-1 31 32445 \
        --tls-domain first-dns.example.com --tls-dns admin@example.com dns_cf "${CREDENTIALS}" \
        --confirm PADM-DOCKER-EDIT
fi
assertFirstTlsSpec "${FIRST_TLS_SS}" entry-1 first-dns.example.com 31 sing-box 32445 sing-box
grep -q -- '--issue --dns dns_cf --keylength ec-256 -d first-dns.example.com' "${DOCKER_LOG}" &&
    grep -qxF 'fake-acme-certificate' "${DOCKER_ROOT}/secrets/tls/first-dns.example.com.crt" ||
    fail 'SS 新增 sing-box TLS 未实际申请或提交证书'
assertSsPrivate
runControl 0 protocol-first-tls-standalone-baseline configure --spec "${FIRST_TLS_SS}"
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    : >"${DOCKER_LOG}"
    runEditPty $'first-http.example.com\n4\nadmin@example.com\ny\n' 0 \
        --protocol-add entry-1 21 32446 --protocol-core xray
    [[ "$(grep -Fc '确认申请证书并在完整候选验证后提交？[y/N]' "${CONTROL_LOG}")" == 1 ]] ||
        fail 'standalone 首个 TLS 没有仅确认一次'
    assertEditCleanup
else
    firstTlsEdit 0 protocol-first-tls-standalone-commit --protocol-add entry-1 21 32446 \
        --protocol-core xray --tls-domain first-http.example.com --tls-standalone admin@example.com \
        --confirm PADM-DOCKER-EDIT
fi
assertFirstTlsSpec "${FIRST_TLS_SS}" entry-1 first-http.example.com 21 xray 32446 sing-box
grep -q -- '--issue --standalone --httpport 8080 --keylength ec-256 -d first-http.example.com' "${DOCKER_LOG}" &&
    grep -q -- '--publish 0.0.0.0:80:8080' "${DOCKER_LOG}" ||
    fail '跨核心首个 TLS 未复用 standalone 挑战'
assertSsPrivate

(
    export PADM_DOCKER_INSTALL_DIR="${DOCKER_ROOT}"
    source "${PROJECT_ROOT}/install-docker.sh"
    entryAction=add entryListener=vless-reality entryProtocol=21 entryCore=xray entryPort=32443
    entryTlsDomain=proxy.example.com
    generated="${TEST_ROOT}/protocol-first-tls-expected.json"
    dockerEditEntryAdd "${FIRST_TLS_REALITY}" "${entryListener}" "${entryProtocol}" "${entryCore}" \
        "${entryPort}" protocol "${generated}" '' "${entryTlsDomain}" &&
        dockerConfigureSpecValidate "${generated}" &&
        dockerEditCompatibilityValidate "${FIRST_TLS_REALITY}" "${generated}" ||
        fail '首个 TLS 完整 expected 门禁拒绝合法草稿'
    cp -- "${generated}" "${TEST_ROOT}/protocol-first-tls-foreign.json"
    for mutation in '.tls.domain="other.example.com" | .core.protocols[-1].websocket.domain="other.example.com"' \
        '.accounts[0].name="foreign"' '.core.protocols[0].public_port+=1' \
        '.subscription.enabled=true' '.tls.http01=true'; do
        jq "${mutation}" "${generated}" >"${TEST_ROOT}/protocol-first-tls-drift.json"
        if dockerEditCompatibilityValidate "${FIRST_TLS_REALITY}" "${TEST_ROOT}/protocol-first-tls-drift.json" \
            >"${TEST_ROOT}/protocol-helper.log" 2>&1; then
            fail '首个 TLS 专项放行额外域名、账号、入口或订阅漂移'
        fi
    done
    recoveryCandidate=$(mktemp -d "${DOCKER_ROOT}/.edit.recovery.XXXXXX")
    chmod 0700 "${recoveryCandidate}"
    printf '[]\n' >"${recoveryCandidate}/challenge.json"
    chmod 0600 "${recoveryCandidate}/challenge.json"
    DOCKER_SETUP_CANDIDATE="${recoveryCandidate}"
    DOCKER_ACME_RECOVERY="${recoveryCandidate}/challenge.json"
    DOCKER_ACME_CONTAINER=fixture-challenge
    if dockerSetupCleanup >"${TEST_ROOT}/protocol-helper.log" 2>&1; then
        fail '活动 ACME 恢复状态仍删除配置草稿'
    fi
    [[ -f "${recoveryCandidate}/challenge.json" ]] || fail '临时清理删除 ACME 恢复证据'
    DOCKER_ACME_RECOVERY= DOCKER_ACME_CONTAINER= DOCKER_ACME_WEBROOT= DOCKER_ACME_STOPPED=()
    dockerSetupCleanup && [[ ! -e "${recoveryCandidate}" ]] || fail 'ACME 恢复完成后仍遗留草稿'
) || fail '首个 TLS 门禁或 ACME 恢复证据保护失败'
runControl 0 protocol-first-tls-foreign-baseline configure --spec "${FIRST_TLS_REALITY}"
firstTlsEdit 15 protocol-first-tls-import-not-authorized \
    --spec "${TEST_ROOT}/protocol-first-tls-foreign.json" --preview
[[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" | cut -d ' ' -f 1)" == \
    "${PROTOCOL_TRAFFIC_HASH}" ]] || fail '首个 TLS 增量改变累计流量或额度'

# 重装复用完整候选事务，只用一次跨核心、协议和账号替换验证编辑边界与恢复。
REINSTALL_SPEC="${TEST_ROOT}/reinstall-private.json"
jq '.core.protocols[0] |= (.public_port=33443 | .name="reinstalled-hy2" |
    .uuid="55555555-5555-4555-8555-555555555555") |
  .accounts[0] |= (.name="reinstalled-business" |
    .uuid="66666666-6666-4666-8666-666666666666")' \
    "${PROTOCOL_TLS}" >"${REINSTALL_SPEC}"
chmod 0600 "${REINSTALL_SPEC}"
printf '%s\n' '{"schema_version":1,"groups":[{"id":"share-aaaaaaaaaaaaaaaa","name":"old-share","enabled":false,"token":"old-share-token-aaaaaaaa","account_ids":["11111111-1111-4111-8111-111111111111"],"listener_ids":["vless-reality"]}]}' \
    >"${DOCKER_ROOT}/config/share-groups.json"
chmod 0600 "${DOCKER_ROOT}/config/share-groups.json"
printf 'unrelated-business-data\n' >"${DOCKER_ROOT}/data/reinstall-preserved"
reinstallPreservedHash() {
    find "${DOCKER_ROOT}/data/traffic" "${DOCKER_ROOT}/data/acme" "${DOCKER_ROOT}/secrets/tls" \
        "${DOCKER_ROOT}/config/xray/geo" \
        "${DOCKER_ROOT}/data/reinstall-preserved" -type f -print0 |
        sort -z | xargs -0 sha256sum | sha256sum | cut -d ' ' -f 1
}
reinstallControl() {
    local expected=$1 name=$2 before preserved
    shift 2
    before=$(editLiveHash)
    preserved=$(reinstallPreservedHash)
    : >"${DOCKER_LOG}"
    runControl "${expected}" "${name}" reinstall "$@"
    assertEditCleanup
    [[ "$(reinstallPreservedHash)" == "${preserved}" ]] ||
        fail "${name}: 重装改变累计、证书、ACME 或其它业务数据"
    if [[ "${expected}" != 0 || " $* " == *' --preview '* ]]; then
        [[ "$(editLiveHash)" == "${before}" ]] || fail "${name}: 重装预览、拒绝或失败恢复改变线上"
    fi
    if [[ "${expected}" != 0 && "${expected}" != 14 || " $* " == *' --preview '* ]]; then
        ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
            fail "${name}: 重装预览或拒绝提前改动服务、账本或证书"
    fi
}
reinstallControl 2 reinstall-needs-mode --spec "${REINSTALL_SPEC}"
reinstallControl 2 reinstall-reject-confirmation --spec "${REINSTALL_SPEC}" --confirm no
reinstallControl 2 reinstall-no-spec-preview --preview
reinstallControl 2 reinstall-no-spec-confirm --confirm PADM-DOCKER-REINSTALL
(
    source "${PROJECT_ROOT}/install-docker.sh"
    guardRoot="${TEST_ROOT}/reinstall-wizard-guard"
    mkdir -p "${guardRoot}/config"
    dockerInstallRoot() { printf '%s\n' "${guardRoot}"; }
    dockerComposeFile() { printf '%s\n' "${DOCKER_ROOT}/compose.json"; }
    cp -- "${FIRST_TLS_REALITY}" "${guardRoot}/config/spec.json"
    chmod 0600 "${guardRoot}/config/spec.json"
    dockerSetupReinstallAllowed || fail '重装向导拒绝普通受管规格'
    for mutation in '.host_integrations=[{type:"wireguard"}]' '.reality_stream={}' \
        '.port_hopping={}' '.control={}' '.control_sync={}'; do
        jq "${mutation}" "${FIRST_TLS_REALITY}" >"${guardRoot}/config/spec.json"
        ! dockerSetupReinstallAllowed >"${TEST_ROOT}/reinstall-guard.log" 2>&1 ||
            fail '重装向导未保留特殊宿主角色的支持边界'
    done
) || fail '重装向导支持边界检查失败'
protocolEdit 15 edit-still-rejects-complete-replacement --spec "${REINSTALL_SPEC}" --preview
reinstallControl 0 reinstall-complete-preview --spec "${REINSTALL_SPEC}" --preview
grep -qF '候选配置校验通过，预览未提交。' "${CONTROL_LOG}" ||
    fail '重装预览没有完成完整候选校验'
for version in 1 2; do
    jq --argjson version "${version}" '.schema_version=$version | del(.accounts,.core.secondary_type) |
      .core.protocols |= map(del(.core) |
        if $version==1 then del(.listener_id,.websocket.backend_port,.websocket.tls_port) else . end)' \
        "${PROTOCOL_BASE}" >"${TEST_ROOT}/reinstall-legacy.json"
    chmod 0600 "${TEST_ROOT}/reinstall-legacy.json"
    reinstallControl 0 "reinstall-v${version}-preview" --spec "${TEST_ROOT}/reinstall-legacy.json" --preview
done
jq 'del(.core.protocols[0].uuid)' "${REINSTALL_SPEC}" >"${TEST_ROOT}/reinstall-invalid.json"
chmod 0600 "${TEST_ROOT}/reinstall-invalid.json"
reinstallControl 15 reinstall-reject-invalid-spec --spec "${TEST_ROOT}/reinstall-invalid.json" --preview
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    chmod 0644 "${REINSTALL_SPEC}"
    reinstallControl 15 reinstall-reject-public-spec --spec "${REINSTALL_SPEC}" --preview
    chmod 0600 "${REINSTALL_SPEC}"
    if [[ "${TEST_SKIP_CHOWN}" == 0 ]]; then
        chown 65534:65534 "${REINSTALL_SPEC}"
        reinstallControl 15 reinstall-reject-foreign-spec --spec "${REINSTALL_SPEC}" --preview
        chown 0:0 "${REINSTALL_SPEC}"
    fi
fi
cp -- "${CONFIGURE_BUNDLE}" "${TEST_ROOT}/reinstall-valid.sigstore.json"
jq '.signature="invalid"' "${TEST_ROOT}/reinstall-valid.sigstore.json" >"${CONFIGURE_BUNDLE}"
reinstallControl 16 reinstall-reject-untrusted-release --spec "${REINSTALL_SPEC}" --preview
cp -- "${TEST_ROOT}/reinstall-valid.sigstore.json" "${CONFIGURE_BUNDLE}"
cp -- "${DOCKER_ROOT}/config/xray/users.base" "${TEST_ROOT}/reinstall-users.base"
jq '.routing.rules += [{type:"field",domain:["unmanaged.example.com"],outboundTag:"direct"}]' \
    "${TEST_ROOT}/reinstall-users.base" >"${DOCKER_ROOT}/config/xray/users.base"
reinstallControl 15 reinstall-reject-baseline-drift --spec "${REINSTALL_SPEC}" --preview
cp -- "${TEST_ROOT}/reinstall-users.base" "${DOCKER_ROOT}/config/xray/users.base"
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    reinstallCancelHash=$(editLiveHash)
    reinstallDataHash=$(reinstallPreservedHash)
    for input in $'n\n' $'\004'; do
        : >"${DOCKER_LOG}"
        PHASE3_PTY_COMMAND=reinstall runEditPty "${input}" 0 --spec "${REINSTALL_SPEC}"
        [[ "$(editLiveHash)" == "${reinstallCancelHash}" &&
            "$(reinstallPreservedHash)" == "${reinstallDataHash}" ]] ||
            fail '重装最终确认取消或 EOF 改变线上或业务数据'
        ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
            fail '重装最终确认前改动服务、账本或证书'
        assertEditCleanup
    done
    : >"${DOCKER_LOG}"
    PHASE3_PTY_COMMAND=reinstall runEditPty $'0\n' 0
    [[ "$(editLiveHash)" == "${reinstallCancelHash}" &&
        "$(reinstallPreservedHash)" == "${reinstallDataHash}" ]] ||
        fail '重新选择核心的向导取消改变线上'
    ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
        fail '重新选择核心的向导取消仍改动服务、账本或证书'
    assertEditCleanup
fi
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up reinstallControl 14 reinstall-up-failure-restores-complete-state \
    --spec "${REINSTALL_SPEC}" --confirm PADM-DOCKER-REINSTALL
reinstallControl 0 reinstall-complete-commit --spec "${REINSTALL_SPEC}" --confirm PADM-DOCKER-REINSTALL
jq -e --slurpfile expected "${REINSTALL_SPEC}" '.==$expected[0]' \
    "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
    fail '重装没有完整提交所选核心、协议和账号'
jq -e '.groups == []' "${DOCKER_ROOT}/config/share-groups.json" >/dev/null ||
    fail '完整规格重装保留了旧分享授权'
jq -e '.core.type=="sing-box" and .core.secondary_type==null and .core.protocol_ids==[3] and
  .compose.profiles==["core-sing-box"] and
  all(.listeners[]; .service=="sing-box" and .public_port==33443)' \
    "${DOCKER_ROOT}/deployment.json" >/dev/null || fail '重装部署仍包含旧核心或入口'
[[ ! -s "${DOCKER_ROOT}/config/xray/config.json" ]] || fail '重装保留了旧 Xray 生效配置'
runControl 0 reinstall-sharing protocol links entry-hy2
grep -qF 'hysteria2://55555555-5555-4555-8555-555555555555@node.example.com:33443?' "${CONTROL_LOG}" &&
    ! grep -qF 'vless://' "${CONTROL_LOG}" || fail '重装分享与新协议、凭据或端口不一致'

# 域名迁移只改 TLS 关联字段；小表保留固定连接地址及 Reality、SS 的完整身份。
TLS_MIGRATE_DOMAIN=migrated.example.com
TLS_MIGRATE_CERT="${TEST_ROOT}/migrated.crt"
TLS_MIGRATE_KEY="${TEST_ROOT}/migrated.key"
printf 'fake-migrated-certificate\n' >"${TLS_MIGRATE_CERT}"
printf 'fake-migrated-private-key\n' >"${TLS_MIGRATE_KEY}"
chmod 0600 "${TLS_MIGRATE_KEY}"
(
    source "${PROJECT_ROOT}/install-docker.sh"
    generated="${TEST_ROOT}/tls-migrate-helper.json"
    changed="${TEST_ROOT}/tls-migrate-helper-changed.json"
    tlsMigrateDomain=${TLS_MIGRATE_DOMAIN}
    for template in '21 websocket xray' '23 httpupgrade xray' '24 grpc_tls xray' \
        '3 hy2 sing-box' '4 anytls sing-box' '5 naive sing-box' \
        '27 fallback_tls xray' '28 trojan xray' '31 tuic sing-box'; do
        read -r protocol field core <<<"${template}"
        dockerEditEntryAdd "${PROTOCOL_BASE}" vless-ws "${protocol}" "${core}" 34443 protocol "${generated}" ||
            fail "TLS 迁移模板无法生成: ${field}"
        jq --slurpfile ss "${FIRST_TLS_SS}" '
          .core.protocols = [
            (.core.protocols[-1] | .server="proxy.example.com"),
            (.core.protocols[-1] | .listener_id="fixed-address" | .server="fixed.example.com"),
            (.core.protocols[] | select(.id==1)),
            ($ss[0].core.protocols[] | select(.id==30))]' \
            "${generated}" >"${TEST_ROOT}/tls-migrate-helper-input.json"
        dockerEditTlsDomainChange "${TEST_ROOT}/tls-migrate-helper-input.json" "${tlsMigrateDomain}" "${changed}" ||
            fail "TLS 迁移字段被拒绝: ${field}"
        jq -e --arg field "${field}" --arg domain "${tlsMigrateDomain}" \
            --slurpfile before "${TEST_ROOT}/tls-migrate-helper-input.json" '
          . == ($before[0] | .tls.domain=$domain |
            .core.protocols[0][$field].domain=$domain | .core.protocols[0].server=$domain |
            .core.protocols[1][$field].domain=$domain)' "${changed}" >/dev/null ||
            fail "TLS 迁移改写其它字段或漏改连接域名: ${field}"
    done
    dockerEditTlsDomainChange "${PROTOCOL_BASE}" "${tlsMigrateDomain}" "${changed}" &&
        dockerEditCompatibilityValidate "${PROTOCOL_BASE}" "${changed}" ||
        fail 'TLS 域名迁移 expected 拒绝合法草稿'
    for mutation in '.accounts[0].name="foreign"' '.subscription.token="fedcba9876543210"' \
        '.core.protocols[0].uuid="77777777-7777-4777-8777-777777777777"' \
        '.core.protocols[1].reality.server_name="other.example.com"' '.tls.http01=true'; do
        jq "${mutation}" "${changed}" >"${TEST_ROOT}/tls-migrate-helper-drift.json"
        ! dockerEditCompatibilityValidate "${PROTOCOL_BASE}" "${TEST_ROOT}/tls-migrate-helper-drift.json" \
            >"${TEST_ROOT}/tls-migrate-helper.log" 2>&1 || fail 'TLS 迁移 expected 放行额外漂移'
    done
    for mutation in '.tls=null' '.host_integrations=[{type:"wireguard"}]' \
        '.reality_stream={}' '.port_hopping={}' '.control={}' '.control_sync={}'; do
        jq "${mutation}" "${PROTOCOL_BASE}" >"${TEST_ROOT}/tls-migrate-helper-input.json"
        ! dockerEditTlsDomainChange "${TEST_ROOT}/tls-migrate-helper-input.json" "${tlsMigrateDomain}" "${changed}" \
            >"${TEST_ROOT}/tls-migrate-helper.log" 2>&1 || fail 'TLS 迁移突破原 TLS 或特殊角色边界'
    done
) || fail 'TLS 域名迁移字段、冻结或支持边界错误'
runControl 0 tls-migrate-baseline configure --spec "${PROTOCOL_BASE}"
runControl 0 tls-migrate-existing-certificate tls install --domain "${TLS_MIGRATE_DOMAIN}" \
    --cert "${CERT_FILE}" --key "${KEY_FILE}" --ops-image "${OPS_IMAGE}"
TLS_MIGRATE_PRESERVED_HASH=$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" \
    "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" "${DOCKER_ROOT}/secrets/tls/proxy.example.com.key" \
    "${DOCKER_ROOT}/data/acme/unrelated/account.conf" "${DOCKER_ROOT}/data/reinstall-preserved" |
    sha256sum | cut -d ' ' -f 1)
tlsMigrateEdit() {
    local expected=$1 name=$2
    shift 2
    firstTlsEdit "${expected}" "${name}" --tls-migrate "${TLS_MIGRATE_DOMAIN}" "$@"
    [[ "$(sha256sum "${DOCKER_ROOT}/data/traffic/state.json" \
        "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" "${DOCKER_ROOT}/secrets/tls/proxy.example.com.key" \
        "${DOCKER_ROOT}/data/acme/unrelated/account.conf" "${DOCKER_ROOT}/data/reinstall-preserved" |
        sha256sum | cut -d ' ' -f 1)" == "${TLS_MIGRATE_PRESERVED_HASH}" ]] ||
        fail "${name}: TLS 迁移改变累计、旧证书或其它数据"
}
tlsMigrateEdit 2 tls-migrate-needs-source --preview
tlsMigrateEdit 2 tls-migrate-reject-spec --tls-existing --spec "${PROTOCOL_BASE}" --preview
tlsMigrateEdit 2 tls-migrate-reject-other-action --tls-existing --protocol-rebuild vless-ws --preview
tlsMigrateEdit 2 tls-migrate-reject-conflicting-sources --tls-existing --tls-import "${CERT_FILE}" "${KEY_FILE}" --preview
protocolEdit 15 tls-migrate-reject-same-domain --tls-migrate proxy.example.com --tls-existing --preview
protocolEdit 2 tls-migrate-reject-bad-domain --tls-migrate invalid_domain --tls-existing --preview
tlsMigrateEdit 0 tls-migrate-existing-preview --tls-existing --preview
grep -qF '候选配置校验通过，预览未提交。' "${CONTROL_LOG}" || fail 'TLS 迁移预览未验证完整候选'
FAKE_DOCKER_MODE=tls-validate-fail tlsMigrateEdit 15 tls-migrate-reject-invalid-certificate \
    --tls-import "${TLS_MIGRATE_CERT}" "${TLS_MIGRATE_KEY}" --preview
cp -- "${CONFIGURE_BUNDLE}" "${TEST_ROOT}/tls-migrate-valid.sigstore.json"
jq '.signature="invalid"' "${TEST_ROOT}/tls-migrate-valid.sigstore.json" >"${CONFIGURE_BUNDLE}"
tlsMigrateEdit 16 tls-migrate-reject-untrusted-release --tls-existing --preview
cp -- "${TEST_ROOT}/tls-migrate-valid.sigstore.json" "${CONFIGURE_BUNDLE}"
cp -- "${DOCKER_ROOT}/config/xray/users.base" "${TEST_ROOT}/tls-migrate-users.base"
jq '.routing.rules += [{type:"field",domain:["unmanaged.example.com"],outboundTag:"direct"}]' \
    "${TEST_ROOT}/tls-migrate-users.base" >"${DOCKER_ROOT}/config/xray/users.base"
tlsMigrateEdit 15 tls-migrate-reject-baseline-drift --tls-existing --preview
cp -- "${TEST_ROOT}/tls-migrate-users.base" "${DOCKER_ROOT}/config/xray/users.base"
for source in dns standalone; do
    tlsArgs=(--tls-dns admin@example.com dns_cf "${CREDENTIALS}")
    [[ "${source}" != standalone ]] || tlsArgs=(--tls-standalone admin@example.com)
    tlsMigrateEdit 0 "tls-migrate-${source}-preview" "${tlsArgs[@]}" --preview
    grep -qF '预览未申请证书或提交' "${CONTROL_LOG}" &&
        ! grep -Eq ' --issue | --install-cert |--publish 0.0.0.0:80:' "${DOCKER_LOG}" ||
        fail 'TLS 域名迁移 ACME 预览申请证书或占用挑战端口'
done
if [[ "${FAKE_PHASE3_HOST_SYSTEM}" == Linux ]]; then
    tlsMigrateCancelHash=$(editLiveHash)
    for input in $'n\n' $'\004'; do
        : >"${DOCKER_LOG}"
        runEditPty "${input}" 0 --tls-migrate "${TLS_MIGRATE_DOMAIN}" --tls-existing
        [[ "$(editLiveHash)" == "${tlsMigrateCancelHash}" ]] || fail 'TLS 迁移取消或 EOF 改变线上'
        ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
            fail 'TLS 迁移最终确认前改变服务、账本或证书'
        assertEditCleanup
    done
    : >"${DOCKER_LOG}"
    runEditPty $'n\n' 0 --tls-migrate "${TLS_MIGRATE_DOMAIN}" \
        --tls-dns admin@example.com dns_cf "${CREDENTIALS}"
    [[ "$(editLiveHash)" == "${tlsMigrateCancelHash}" ]] || fail 'TLS 迁移 ACME 取消改变线上'
    ! grep -Eq ' (up|down|restart|exec) | --issue | --install-cert ' "${DOCKER_LOG}" ||
        fail 'TLS 迁移 ACME 取消仍申请证书或改动服务'
    assertEditCleanup
fi
FAKE_DOCKER_MODE=acme-issue-fail tlsMigrateEdit 15 tls-migrate-acme-failure \
    --tls-dns admin@example.com dns_cf "${CREDENTIALS}" --confirm PADM-DOCKER-EDIT
rm -f -- "${TEST_ROOT}/fail-once"
FAKE_DOCKER_MODE=fail-next-up tlsMigrateEdit 14 tls-migrate-up-failure \
    --tls-import "${TLS_MIGRATE_CERT}" "${TLS_MIGRATE_KEY}" --confirm PADM-DOCKER-EDIT
tlsMigrateEdit 0 tls-migrate-import-commit --tls-import "${TLS_MIGRATE_CERT}" "${TLS_MIGRATE_KEY}" \
    --confirm PADM-DOCKER-EDIT
jq -e --slurpfile before "${PROTOCOL_BASE}" --arg domain "${TLS_MIGRATE_DOMAIN}" '
  . == ($before[0] | .tls.domain=$domain | .core.protocols[0].server=$domain |
    .core.protocols[0].websocket.domain=$domain)' "${DOCKER_ROOT}/config/spec.json" >/dev/null ||
    fail 'TLS 迁移改变账号、token、Reality 或未选中规格'
cmp -s "${TLS_MIGRATE_CERT}" "${DOCKER_ROOT}/secrets/tls/${TLS_MIGRATE_DOMAIN}.crt" &&
    cmp -s "${TLS_MIGRATE_KEY}" "${DOCKER_ROOT}/secrets/tls/${TLS_MIGRATE_DOMAIN}.key" ||
    fail 'TLS 迁移未提交新证书原始内容'
grep -qF "server_name ${TLS_MIGRATE_DOMAIN};" "${DOCKER_ROOT}/config/nginx/default.conf" &&
    grep -qF "/etc/padm/secrets/tls/${TLS_MIGRATE_DOMAIN}.crt" "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'TLS 迁移 Nginx SNI 或证书挂载仍指向旧域名'
grep -q "vless://22222222-2222-4222-8222-222222222222@${TLS_MIGRATE_DOMAIN}:24444.*sni=${TLS_MIGRATE_DOMAIN}" \
    "${DOCKER_ROOT}/data/subscription/0123456789abcdef" &&
    grep -qF 'vless://11111111-1111-4111-8111-111111111111@proxy.example.com:25443' \
        "${DOCKER_ROOT}/data/subscription/0123456789abcdef" ||
    fail 'TLS 迁移分享没有更新 TLS 域名/SNI 或改变 Reality 连接地址'

runControl 0 restart-persistence status
grep -qxF 'configured=yes' "${CONTROL_LOG}" || fail 'configured status was not restored'
runControl 0 validate-persistence validate
grep -qxF 'Docker 部署配置校验通过' "${CONTROL_LOG}" || fail 'validate did not report success'
runControl 0 restart-up up
fi

if [[ "${PHASE3_SCOPE}" != entries ]]; then
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
        (.profiles | names(["core-xray", "core-sing-box", "nginx", "nginx-stream", "acme", "subscription",
          "net-wireguard", "net-fail2ban", "net-fail2ban-control", "net-fail2ban-ssh", "net-transparent"])) and
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
        "fail2ban", "wireguard", "tun", "tproxy", "redirect"] as $legacy |
      ["subscription-traffic", "interactive-menu", "routing-tools", "core-lifecycle",
        "core-upgrade-assessment", "geo-data", "script-update", "uninstall", "reality-target-management",
        "reality-parameter-management", "reality-coexistence"] as $host_cli |
      ["subscription-multiserver", "fail2ban", "wireguard", "tun", "tproxy", "redirect",
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
            (if (.id >= 21 and .id <= 25) or .id == 27 or .id == 29 then ["nginx"] else [] end) | sort)
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
      (.host_integrations | type == "object" and
        keys == (["fail2ban", "fail2ban-control", "fail2ban-ssh", "tun", "tproxy", "redirect", "wireguard"] | sort)) and
      all(.host_integrations | to_entries[];
        . as $entry |
        (.value | .status == "host-integrated" and .network_mode == "host" and
          .capabilities == ["NET_ADMIN"] and
          .devices == (if $entry.key == "tun" then ["/dev/net/tun"] else [] end)) and
        ($matrix.feature_matrix[if $entry.key == "fail2ban-control" or $entry.key == "fail2ban-ssh"
          then "fail2ban" else $entry.key end] |
          .status == $entry.value.status and .network_mode == $entry.value.network_mode and
          .profiles == (if $entry.key == "fail2ban" or $entry.key == "fail2ban-control" or $entry.key == "fail2ban-ssh"
            then ["net-fail2ban", "net-fail2ban-control", "net-fail2ban-ssh"] else [$entry.value.profile] end) and
          (.host_capabilities | sort) == ($entry.value.capabilities + $entry.value.devices | sort))) and
      (.host_integrations["fail2ban-control"] |
        .profile == "net-fail2ban-control" and .address_families == ["ipv4"] and
        .services == ["control", "net-wireguard", "net-fail2ban-control"]) and
      (.host_integrations["fail2ban-ssh"] |
        .profile == "net-fail2ban-ssh" and .address_families == ["ipv4","ipv6"] and
        .services == ["net-fail2ban-ssh"]) and
      all({
        nginx: ["nginx"], "tls-files": ["nginx", "acme"], "acme-dns": ["acme"],
        subscription: ["core-xray", "nginx", "subscription"],
        "subscription-traffic": ["core-xray", "core-sing-box"],
        "core-lifecycle": ["core-xray", "core-sing-box"],
        "core-upgrade-assessment": ["core-xray", "core-sing-box"], "geo-data": ["core-xray"],
        "script-update": [], uninstall: []
      } | to_entries[];
        . as $entry | ($matrix.feature_matrix[$entry.key].profiles | sort) == ($entry.value | sort)) and
      all({
        "internal-203-wireguard": "wireguard", "internal-204-tun": "tun",
        "internal-205-redirect-tproxy": "tproxy"
      } | to_entries[];
        . as $entry |
        ($matrix.feature_matrix[$entry.key] | {status, profiles, network_mode, host_capabilities}) ==
          ($matrix.feature_matrix[$entry.value] | {status, profiles, network_mode, host_capabilities})) and
      all(["interactive-menu", "reality-coexistence"][]; $matrix.feature_matrix[.].status == "deferred") and
      $matrix.feature_matrix["core-upgrade-assessment"].status == "supported" and
      $matrix.feature_matrix["geo-data"].status == "supported" and
      $matrix.feature_matrix["reality-target-management"].status == "supported" and
      $matrix.feature_matrix["reality-parameter-management"].status == "supported" and
      ([.protocols[] | select(.status == "supported") | .id] | sort) == [1, 2, 3, 4, 5, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31] and
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
.feature_matrix["acme-standalone"].network_mode = "host"
.feature_matrix.wireguard.host_capabilities = ["SYS_ADMIN"]
.host_integrations.wireguard.capabilities = ["SYS_ADMIN"]
.host_integrations["fail2ban-control"].profile = "net-fail2ban"
.host_integrations["fail2ban-control"].address_families = ["ipv4","ipv6"]
del(.host_integrations["fail2ban-ssh"])
.host_integrations["fail2ban-ssh"].profile = "net-fail2ban-control"
.host_integrations["fail2ban-ssh"].services = ["control","net-fail2ban-ssh"]
.host_integrations["fail2ban-ssh"].address_families = ["ipv4","ipv6","dual"]
.host_integrations["fail2ban-ssh"].capabilities = ["NET_ADMIN","SYS_PTRACE"]
del(.host_integrations.redirect)
.feature_matrix.redirect.network_mode = "bridge"
.feature_matrix.fail2ban.profiles += ["net-fail2ban-ssh-unmanaged"]
.feature_matrix["internal-203-wireguard"].profiles = ["net-fail2ban"]
.feature_matrix["internal-204-tun"].host_capabilities = ["NET_ADMIN"]
.protocols[3].transport = "quic"
.protocols[14].udp_support = "no"
.protocols[0].management_status = "supported"
(.protocols[] | select(.id == 29)) |= (.status = "supported" | .profiles = ["core-sing-box"])
.feature_matrix.subscription.requires.core = "sing-box"
.feature_matrix.subscription.requires.protocol_ids = [1]
.feature_matrix.subscription.requires.tls = false
.feature_matrix["core-upgrade-assessment"].status = "deferred"
.feature_matrix["core-upgrade-assessment"].profiles = []
.feature_matrix["geo-data"].status = "deferred"
.feature_matrix["geo-data"].profiles = []
.feature_matrix["reality-parameter-management"].status = "deferred"
.feature_matrix["reality-target-management"].status = "deferred"
EOF
fi

printf 'docker-phase3-regression-ok\n'
