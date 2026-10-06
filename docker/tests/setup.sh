#!/usr/bin/env bash
set -euo pipefail

for tool in script timeout mkfifo find; do
    command -v "${tool}" >/dev/null 2>&1 || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
find . -maxdepth 0 -printf '' 2>/dev/null ||
    { printf 'docker-setup-regression requires find with -printf\n' >&2; exit 1; }
export FAKE_SETUP_HOST_SYSTEM FAKE_SETUP_HOST_STAT
FAKE_SETUP_HOST_SYSTEM=$(uname -s)
FAKE_SETUP_HOST_STAT=$(command -v stat)
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-setup.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
SOURCE_ROOT="${TEST_ROOT}/source"
BASE_ROOT="${TEST_ROOT}/base"
MANIFEST="${TEST_ROOT}/release-manifest.json"
SIGNATURE="${TEST_ROOT}/release-manifest.sigstore.json"
CONTROL="${TEST_ROOT}/control.tar.gz"
EVENTS="${TEST_ROOT}/events"
VERIFY_LOG="${TEST_ROOT}/verify.log"
ARGV_LOG="${TEST_ROOT}/argv.log"
CONTROL_LOG=
mkdir -p "${MOCK_BIN}" "${TEST_ROOT}/native" "${TEST_ROOT}/systemd"
cleanup() {
    if [[ "${PADM_TEST_KEEP:-0}" == 1 ]]; then
        printf 'docker-setup-test-root: %s\n' "${TEST_ROOT}" >&2
    else
        rm -rf -- "${TEST_ROOT}"
    fi
}
trap cleanup EXIT

fail() {
    [[ -z "${CONTROL_LOG}" || ! -f "${CONTROL_LOG}" ]] || sed 's/^/  /' "${CONTROL_LOG}" >&2
    printf 'docker-setup-regression-fail: %s\n' "$*" >&2
    exit 1
}

# 直接执行生产中的派生脚本，固定 RFC 7748 向量不依赖假 Docker 输出。
PYTHON=
for pythonCandidate in python3 python; do
    if command -v "${pythonCandidate}" >/dev/null 2>&1 &&
        "${pythonCandidate}" -c 'import sys; sys.exit(0 if sys.version_info.major == 3 else 1)' >/dev/null 2>&1; then
        PYTHON=${pythonCandidate}
        break
    fi
done
if [[ -n "${PYTHON}" ]] && command -v openssl >/dev/null 2>&1; then
    DERIVE_SCRIPT="${TEST_ROOT}/derive-public.py"
    awk '
        /^import base64$/ { active=1 }
        active && /^[[:space:]]*\047/ { exit }
        active { print }
    ' "${PROJECT_ROOT}/docker/lib/setup.sh" >"${DERIVE_SCRIPT}"
    grep -Fq 'private_key = base64.b64decode' "${DERIVE_SCRIPT}" ||
        fail 'could not extract the production X25519 derivation script'
    vectorPrivate=$("${PYTHON}" -c 'import base64; print(base64.urlsafe_b64encode(bytes.fromhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")).decode().rstrip("="))')
    vectorPublic=$("${PYTHON}" -c 'import base64; print(base64.urlsafe_b64encode(bytes.fromhex("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")).decode().rstrip("="))')
    derivedPublic=$(printf '%s\n' "${vectorPrivate}" | "${PYTHON}" "${DERIVE_SCRIPT}") ||
        fail 'production X25519 derivation failed the RFC 7748 vector'
    [[ "${derivedPublic}" == "${vectorPublic}" ]] || fail 'production X25519 derivation returned the wrong public key'
    if printf 'not-valid-base64!\n' | "${PYTHON}" "${DERIVE_SCRIPT}" >"${TEST_ROOT}/bad-derived.stdout" 2>"${TEST_ROOT}/bad-derived.stderr"; then
        fail 'production X25519 derivation accepted malformed base64'
    fi
    [[ ! -s "${TEST_ROOT}/bad-derived.stdout" ]] || fail 'malformed private key emitted a derived public key'
else
    if [[ "${CI:-}" == true && "${FAKE_SETUP_HOST_SYSTEM}" == Linux ]]; then
        fail 'Linux CI requires Python 3 and OpenSSL for the production X25519 check'
    fi
    printf 'docker-setup-derivation-skip: Python 3 or OpenSSL is unavailable\n' >&2
fi

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
-m) printf 'x86_64\n' ;;
*) printf 'Linux\n' ;;
esac
EOF
cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == -u ]] && printf '0\n'
EOF
cat >"${MOCK_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
# MSYS2 的权限显示受 Windows ACL 影响；Linux 仍检查真实权限。
if [[ "${1:-}" == --format=%a && "${FAKE_SETUP_HOST_SYSTEM}" != Linux ]]; then
    printf '600\n'
else
    exec "${FAKE_SETUP_HOST_STAT}" "$@"
fi
EOF
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
mode=${FAKE_SETUP_MODE:-ok}
printf 'docker' >>"${FAKE_SETUP_ARGV_LOG:?}"
printf ' %q' "$@" >>"${FAKE_SETUP_ARGV_LOG}"
printf '\n' >>"${FAKE_SETUP_ARGV_LOG}"
case "${1:-}" in
info)
    if [[ "${2:-}" == --format ]]; then
        case "${3:-}" in
        '{{.OSType}}') printf 'linux\n' ;;
        '{{.Architecture}}') printf 'x86_64\n' ;;
        '{{json .SecurityOptions}}') printf '["name=seccomp,profile=builtin"]\n' ;;
        *) exit 1 ;;
        esac
    fi
    ;;
context) printf 'unix:///var/run/docker.sock\n' ;;
ps)
    if [[ "${mode}" == port-conflict && " $* " == *' publish='* ]]; then printf 'other-project\n'; fi
    ;;
pull) printf 'pull %s\n' "$2" >>"${FAKE_SETUP_EVENTS:?}" ;;
compose)
    if [[ "${2:-}" == version ]]; then printf 'v2.29.1\n'; exit 0; fi
    printf 'compose %s\n' "$*" >>"${FAKE_SETUP_EVENTS:?}"
    if [[ "${mode}" == health-fail && " $* " == *' up -d '* ]]; then exit 1; fi
    if [[ "${mode}" == tls-fail && " $* " == *' tls-check '* ]]; then exit 1; fi
    if [[ " $* " == *' sing-box version '* ]]; then printf 'sing-box version 1.14.0\nTags: with_v2ray_api\n'; fi
    ;;
run)
    printf 'run %s\n' "$*" >>"${FAKE_SETUP_EVENTS:?}"
    if [[ " $* " == *' uuid '* ]]; then
        [[ "${mode}" != keygen-fail ]] || exit 1
        if [[ "${mode}" == interrupt-int || "${mode}" == interrupt-term ]]; then
            printf 'generation-ready\n'
            printf '%s\n' "${BASHPID}" >"${FAKE_SETUP_CHILD_PID:?}"
            # 模拟耗时容器工具，信号必须清理整个调用而非只删临时目录。
            trap 'exit 143' TERM
            trap 'exit 130' INT
            while true; do sleep 1; done
        fi
        printf '11111111-1111-4111-8111-111111111111\n'
    elif [[ " $* " == *' x25519 '* ]]; then
        [[ "${mode}" != keygen-fail ]] || exit 1
        printf 'PrivateKey: %s\nPassword (PublicKey): %s\n' \
            AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
    elif [[ " $* " == *' rand -hex '* ]]; then
        [[ "${mode}" != token-fail ]] || exit 1
        bytes=${!#}
        [[ "${bytes}" =~ ^[0-9]+$ ]] || exit 1
        printf '%*s\n' "$((bytes * 2))" '' | tr ' ' a
    elif [[ " $* " == *' --entrypoint python3 '* && " $* " != *'/opt/acme/acme.sh'* ]]; then
        if [[ " $* " == *'private_key = base64.b64decode'* ]]; then
            IFS= read -r privateKey || exit 1
            [[ "${privateKey}" == AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA ]] || exit 1
            printf 'derived-stdin\n' >>"${FAKE_SETUP_EVENTS}"
            if [[ "${mode}" == derived-fail ]]; then
                printf 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC\n'
            else
                printf 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\n'
            fi
        else
            printf '192.0.2.1\tAS64500\tExampleNet\n'
        fi
    elif [[ " $* " == *' tls ping '* ]]; then
        if [[ " $* " == *' cloudflare.com:443 '* ]]; then
            printf 'Pinging with SNI\nHandshake failure: certificate does not match SNI\n'
        else
            printf 'Pinging with SNI\nHandshake succeeded\nTLS Version:\tTLS 1.3\n'
        fi
    elif [[ " $* " == *' tls-check '* ]]; then
        [[ "${mode}" != tls-fail ]] || exit 1
    elif [[ " $* " == *'/opt/acme/acme.sh'* ]]; then
        [[ "${mode}" != acme-fail ]] || exit 1
        output= account= domain= previous=
        for argument in "$@"; do
            if [[ "${previous}" == --volume && "${argument}" == *:/var/lib/padm/tls-output ]]; then
                output=${argument%:/var/lib/padm/tls-output}
            elif [[ "${previous}" == --volume && "${argument}" == *:/var/lib/padm/acme ]]; then
                account=${argument%:/var/lib/padm/acme}
            elif [[ "${previous}" == -d ]]; then
                domain=${argument}
            fi
            previous=${argument}
        done
        [[ -n "${account}" ]] && printf 'candidate-acme-account\n' >"${account}/account.conf"
        if [[ " $* " == *' --install-cert '* ]]; then
            printf 'fake-acme-cert\n' >"${output}/${domain}.crt"
            printf 'fake-acme-key\n' >"${output}/${domain}.key"
            chmod 0600 "${output}/${domain}.key"
        fi
    fi
    ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_SETUP_VERIFY_LOG:?}"
[[ "$#" -eq 8 && "$1" == verify-blob && "$2" == --bundle &&
    "$4" == --certificate-identity-regexp &&
    "$5" == '^https://github\.com/neil1123-vip/padm/\.github/workflows/create_release\.yml@refs/heads/main$' &&
    "$6" == --certificate-oidc-issuer && "$7" == https://token.actions.githubusercontent.com ]] || exit 1
[[ "${FAKE_SETUP_MODE:-ok}" != signature-fail ]] || exit 1
jq -e --arg sha "$(sha256sum "$8" | cut -d ' ' -f 1)" '
    .manifest_sha256 == $sha and
    .identity == "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main"
' "$3" >/dev/null
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
    printf 'curl 8.0.0\nFeatures: HTTP2 HTTPS\n'
    exit 0
fi
printf 'download %s\n' "$*" >>"${FAKE_SETUP_EVENTS:?}"
exit 1
EOF
cat >"${MOCK_BIN}/wget" <<'EOF'
#!/usr/bin/env bash
printf 'download %s\n' "$*" >>"${FAKE_SETUP_EVENTS:?}"
exit 1
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
cp "${MOCK_BIN}/systemctl" "${MOCK_BIN}/nsenter"
chmod 0755 "${MOCK_BIN}/"*

REAL_JQ=$(command -v jq)
export FAKE_SETUP_REAL_JQ="${REAL_JQ}"
cat >"${MOCK_BIN}/jq" <<'EOF'
#!/usr/bin/env bash
printf 'jq' >>"${FAKE_SETUP_ARGV_LOG:?}"
printf ' %q' "$@" >>"${FAKE_SETUP_ARGV_LOG}"
printf '\n' >>"${FAKE_SETUP_ARGV_LOG}"
exec "${FAKE_SETUP_REAL_JQ:?}" "$@"
EOF
chmod 0755 "${MOCK_BIN}/jq"

export PATH="${MOCK_BIN}:${PATH}" MSYS=winsymlinks:sys DOCKER_HOST='' SHELL
SHELL=$(command -v bash)
export PADM_NATIVE_INSTALL_DIR="${TEST_ROOT}/native"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
export PADM_DOCKER_LOCK_TIMEOUT=1 PADM_DOCKER_HEALTH_TIMEOUT=1 PADM_DOCKER_SKIP_CHOWN=1
export FAKE_SETUP_EVENTS="${EVENTS}" FAKE_SETUP_VERIFY_LOG="${VERIFY_LOG}"
export FAKE_SETUP_ARGV_LOG="${ARGV_LOG}" FAKE_SETUP_CHILD_PID="${TEST_ROOT}/child.pid"

# 输出变量恰好叫 answer 时也必须传回调用者；确认与订阅共用该路径。
(
    source "${PROJECT_ROOT}/docker/lib/setup.sh"
    answer=
    dockerSetupRead answer '' n <<<y
    [[ "${answer}" == y ]]
    dockerSetupRead answer '' n <<<''
    [[ "${answer}" == n ]]
) || fail 'prompt helper shadowed the answer output variable'

for relative in \
    install-docker.sh docker/lib/bootstrap.sh docker/lib/bundle.sh docker/lib/manifest.sh \
    docker/lib/services.sh docker/lib/traffic.sh docker/lib/renewal.sh docker/lib/lifecycle.sh docker/lib/menu.sh docker/lib/setup.sh \
    docker/contracts/configure.schema.json docker/contracts/deployment.schema.json \
    docker/contracts/features.json shell/core/deployment_mode.sh shell/core/stats_grpc.sh; do
    mkdir -p "${SOURCE_ROOT}/$(dirname -- "${relative}")"
    cp "${PROJECT_ROOT}/${relative}" "${SOURCE_ROOT}/${relative}"
done
tar -czf "${CONTROL}" -C "${SOURCE_ROOT}" install-docker.sh docker shell
jq -n --arg sha "$(sha256sum "${CONTROL}" | cut -d ' ' -f 1)" '
    def image($name): {
        reference: ("ghcr.io/example/padm-" + $name + ":3.2.0@sha256:" + ("2" * 64)),
        index_digest: ("sha256:" + ("2" * 64)),
        platforms: {"linux/amd64": ("sha256:" + ("4" * 64)), "linux/arm64": ("sha256:" + ("5" * 64))}
    };
    {schema_version: 1, release: {version: "3.2.0", commit: ("a" * 40), created_at: "2026-10-05T00:00:00Z"},
     control: {bundle_url: "https://example.invalid/control.tar.gz", sha256: $sha, min_version: "3.2.0"},
     images: {xray: image("xray"), "sing-box": image("sing-box"), nginx: image("nginx"), ops: image("ops"), net: image("net")},
     upstream: {alpine: "3", xray: "1", sing_box: "1", nginx: "1", acme_sh: "1"},
     formats: {compose: 1, config: 1, data: 1},
     compatibility: {host: ["linux", "rootful-docker", "compose-v2"], architectures: ["amd64", "arm64"], profiles: ["core-xray","core-sing-box"], features_version: 1},
     migrations: []}
' >"${MANIFEST}"
jq -n --arg sha "$(sha256sum "${MANIFEST}" | cut -d ' ' -f 1)" '
    {manifest_sha256:$sha,identity:"https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main"}
' >"${SIGNATURE}"
ASSET_ARGS=(--manifest "${MANIFEST}" --bundle "${SIGNATURE}" --control-bundle "${CONTROL}")
export PADM_DOCKER_INSTALL_DIR="${BASE_ROOT}" PADM_DOCKER_BIN_DIR="${TEST_ROOT}/base-bin"
CONTROL_LOG="${TEST_ROOT}/install.log"
bash -u "${PROJECT_ROOT}/install-docker.sh" install --no-menu --source "${SOURCE_ROOT}" \
    --ref ffffffffffffffffffffffffffffffffffffffff >"${CONTROL_LOG}" 2>&1 || fail 'fixture install failed'

newState() {
    local name=$1
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-${name}"
    export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-${name}"
    cp -R "${BASE_ROOT}" "${PADM_DOCKER_INSTALL_DIR}"
    mkdir "${PADM_DOCKER_BIN_DIR}"
    ln -s "${PADM_DOCKER_INSTALL_DIR}/bundle/install-docker.sh" "${PADM_DOCKER_BIN_DIR}/padm-docker"
    CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
    : >"${EVENTS}"; : >"${VERIFY_LOG}"; : >"${ARGV_LOG}"
}

snapshot() {
    local path
    find "${PADM_DOCKER_INSTALL_DIR}" -printf '%P %y %l\n' | LC_ALL=C sort
    while IFS= read -r path; do sha256sum "${path}"; done \
        < <(find "${PADM_DOCKER_INSTALL_DIR}" -type f -print | LC_ALL=C sort)
}

assertClean() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || fail 'setup retained deployment lock'
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}" -maxdepth 2 -type d \
        \( -name '.setup.*' -o -name '.edit.*' -o -name '.protocol.*' -o \
            -name '.candidate.*' -o -name '.manifest.*' -o -name '.stage.*' \) -print -quit)" ]] ||
        fail 'setup retained a candidate directory'
}

assertUnconfigured() {
    local file
    assertClean
    for file in deployment.json compose.json images.env config/spec.json; do
        [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/${file}" ]] || fail "failed setup retained ${file}"
    done
    [[ -z "$(find "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" -type f -print -quit 2>/dev/null || true)" ]] ||
        fail 'failed setup retained TLS material'
}

assertNoSecrets() {
    local secret
    for secret in AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
        hy2-obfs-private-1234; do
        ! grep -Fq "${secret}" "${CONTROL_LOG}" || fail 'setup printed a secret'
        ! grep -Fq "${secret}" "${ARGV_LOG}" || fail 'setup passed a secret through process arguments'
    done
}

runPty() {
    local expected=$1 name=$2 input=$3 actual=0 feederStatus=0 command fifo feeder completed
    local interruptMode=0
    shift 3
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    fifo="${TEST_ROOT}/${name}.input"
    completed="${TEST_ROOT}/${name}.done"
    mkfifo "${fifo}"
    printf -v command '%q ' bash -u "${CLI}" "$@"
    if [[ "${FAKE_SETUP_MODE:-}" == interrupt-int || "${FAKE_SETUP_MODE:-}" == interrupt-term ]]; then
        interruptMode=1
        rm -f -- "${FAKE_SETUP_CHILD_PID}"
        printf -v command 'printf "%%s\\n" "$$" >%q; exec %s' "${TEST_ROOT}/${name}.pid" "${command}"
    else
        printf -v command '%s; status=$?; printf "%%s\\n" "$status" >%q; exit "$status"' "${command}" "${completed}"
    fi
    (
        exec 3>"${fifo}"
        if [[ "${input}" == $'1\n1\n\004' ]]; then
            printf '1\n1\n' >&3
            for ((attempt = 0; attempt < 1200; attempt++)); do
                if [[ -f "${CONTROL_LOG}" ]] && grep -Fq '服务器域名或 IP' "${CONTROL_LOG}"; then
                    printf '\004' >&3
                    break
                fi
                sleep 0.05
            done
        else
            printf '%s' "${input}" >&3
        fi
        if [[ "${interruptMode}" == 1 ]]; then
            for ((attempt = 0; attempt < 2400; attempt++)); do
                [[ ! -f "${FAKE_SETUP_CHILD_PID}" ]] || break
                sleep 0.05
            done
            [[ -f "${FAKE_SETUP_CHILD_PID}" ]] || exit 2
            if [[ "${FAKE_SETUP_MODE}" == interrupt-int ]]; then
                printf '\003' >&3
            else
                kill -TERM -- "-$(<"${TEST_ROOT}/${name}.pid")" || exit 3
            fi
            for ((attempt = 0; attempt < 600; attempt++)); do
                kill -0 "$(<"${TEST_ROOT}/${name}.pid")" 2>/dev/null || exit 0
                sleep 0.05
            done
            exit 4
        fi
        # 保持 PTY 输入打开到命令结束，避免 script 在 EOF 时丢弃排队输入。
        for ((attempt = 0; attempt < 3600; attempt++)); do
            [[ ! -f "${completed}" ]] || exit 0
            sleep 0.05
        done
        exit 1
    ) &
    feeder=$!
    timeout 240 script -q -e -E never -f -c "${command}" "${CONTROL_LOG}" \
        <"${fifo}" >"${TEST_ROOT}/${name}.stdout" 2>&1 || actual=$?
    wait "${feeder}" || feederStatus=$?
    [[ "${feederStatus}" -eq 0 ]] || fail "${name}: PTY command did not finish"
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
    assertClean
    assertNoSecrets
    if [[ "${interruptMode}" == 1 ]]; then
        ! kill -0 "$(<"${FAKE_SETUP_CHILD_PID}")" 2>/dev/null ||
            fail 'setup left the interrupted credential generator running'
    fi
}

REALITY_INPUT=$'1\n1\nproxy.example.com\n1\n24443\ntarget.example.com\n443\ntarget.example.com\ny\n'
SINGBOX_INPUT=$'2\n1\nproxy.example.com\n1\n24443\ntarget.example.com\n443\ntarget.example.com\ny\n'
for cancellation in first eof partial final empty; do
    newState "cancel-${cancellation}"
    before=$(snapshot)
    case "${cancellation}" in
    first) input=$'0\n' ;;
    eof) input=$'\004' ;;
    partial) input=$'1\n1\n\004' ;;
    final) input=${REALITY_INPUT%$'y\n'}$'n\n' ;;
    empty) input=${REALITY_INPUT%$'y\n'}$'\n' ;;
    esac
    runPty 0 "cancel-${cancellation}" "${input}" setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" ]] || fail "${cancellation}: cancellation changed state"
    [[ ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] || fail "${cancellation}: cancellation reached privileged work"
done

for signal in int term; do
    newState "interrupt-${signal}"
    export FAKE_SETUP_MODE="interrupt-${signal}"
    if [[ "${signal}" == int ]]; then expected=130; else expected=143; fi
    runPty "${expected}" "interrupt-${signal}" "${REALITY_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
    unset FAKE_SETUP_MODE
done

newState non-tty
before=$(snapshot)
CONTROL_LOG="${TEST_ROOT}/non-tty.log"
actual=0
bash -u "${CLI}" setup "${ASSET_ARGS[@]}" </dev/null >"${CONTROL_LOG}" 2>&1 || actual=$?
[[ "${actual}" -eq 2 && "$(snapshot)" == "${before}" && ! -s "${EVENTS}" ]] ||
    fail 'non-TTY setup did not reject without side effects'

for failure in signature-fail keygen-fail derived-fail token-fail port-conflict health-fail; do
    newState "${failure}"
    export FAKE_SETUP_MODE="${failure}"
    case "${failure}" in
    signature-fail) expected=16 ;;
    keygen-fail|derived-fail|token-fail) expected=15 ;;
    port-conflict) expected=11 ;;
    health-fail) expected=14 ;;
    esac
    runPty "${expected}" "${failure}" "${REALITY_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
    if [[ "${failure}" == signature-fail ]]; then
        [[ ! -s "${EVENTS}" ]] || fail 'bad signature reached key generation or image pulls'
    fi
    unset FAKE_SETUP_MODE
done

newState missing-cosign
NO_COSIGN_BIN="${TEST_ROOT}/no-cosign-bin"
mkdir "${NO_COSIGN_BIN}"
for tool in bash uname id docker curl wget jq sha256sum tar readlink dirname basename \
    mkdir chmod find sort cp awk cut mktemp rm rmdir cat date stat sleep cmp wc head uniq tr sed env \
    script timeout grep stty ps mkfifo; do
    ln -s "$(command -v "${tool}")" "${NO_COSIGN_BIN}/${tool}"
done
PATH="${NO_COSIGN_BIN}" runPty 16 missing-cosign "${REALITY_INPUT}" setup "${ASSET_ARGS[@]}"
assertUnconfigured
[[ ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] || fail 'missing cosign reached generation or image pulls'
grep -Fq cosign "${CONTROL_LOG}" || fail 'missing verifier did not report the required tool'

newState xray-success
runPty 0 xray-success "${REALITY_INPUT}" setup "${ASSET_ARGS[@]}"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
[[ -f "${SPEC}" && ! -L "${SPEC}" ]] || fail 'setup did not preserve full configuration spec'
jq -e --arg sha "$(sha256sum "${MANIFEST}" | cut -d ' ' -f 1)" '
    .schema_version == 3 and .release.version == "3.2.0" and .release.manifest_sha256 == $sha and
    .core.type == "xray" and .core.secondary_type == null and (.core.protocols | length) == 1 and
    .core.protocols[0].core == "xray" and .core.protocols[0].id == 1 and
    .core.protocols[0].uuid == "11111111-1111-4111-8111-111111111111" and
    (.core.protocols[0].reality.private_key | length) == 43 and
    (.core.protocols[0].reality.public_key | length) == 43 and
    (.core.protocols[0].reality.short_id | length) == 16
' "${SPEC}" >/dev/null || fail 'preserved spec omitted verified metadata or generated Reality credentials'
jq -e 'all(.services[].volumes[]?; (.source != "${PADM_DOCKER_ROOT}/config") and (.source | endswith("/config/spec.json") | not))' \
    "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null || fail 'configuration spec was exposed to containers'
if [[ "${FAKE_SETUP_HOST_SYSTEM}" == Linux ]]; then
    [[ "$("${FAKE_SETUP_HOST_STAT}" -c %a "${SPEC}")" == 600 ]] || fail 'spec permissions were not 0600'
fi
[[ "$(grep -c '^pull ' "${EVENTS}")" -eq 5 ]] || fail 'setup did not use the five verified image references'
! grep -Fq AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "${CONTROL_LOG}" || fail 'setup printed the private key'

# 既有部署不能通过向导覆盖，CLI 的自报发布字段同样不能绕过验签门禁。
before=$(snapshot)
runPty 11 existing-deployment $'0\n' setup "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'existing deployment was overwritten by setup'
for field in release images; do
    if [[ "${field}" == release ]]; then
        jq '.release.manifest_sha256 = ("b" * 64)' "${SPEC}" >"${TEST_ROOT}/tampered.json"
    else
        jq '.images.xray |= sub("@sha256:[0-9a-f]+$"; "@sha256:" + ("3" * 64))' "${SPEC}" >"${TEST_ROOT}/tampered.json"
    fi
    chmod 0600 "${TEST_ROOT}/tampered.json"
    CONTROL_LOG="${TEST_ROOT}/tampered-${field}.log"
    actual=0
    bash -u "${CLI}" configure --spec "${TEST_ROOT}/tampered.json" "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 16 && "$(snapshot)" == "${before}" ]] || fail "tampered ${field} bypassed CLI trust boundary"
done

newState singbox-success
runPty 0 singbox-success "${SINGBOX_INPUT}" setup "${ASSET_ARGS[@]}"
jq -e '.schema_version == 3 and .core.type == "sing-box" and .core.secondary_type == null and
    .core.protocols[0].core == "sing-box" and .core.protocols[0].id == 1' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail 'sing-box first configuration did not succeed'

# 新传输仍在确认后生成凭据；首配不借 TLS 或订阅发布开启其它服务。
for transportCase in xray-xhttp xray-grpc singbox-grpc; do
    newState "${transportCase}"
    case "${transportCase}" in
    xray-xhttp) core=xray; protocol=2; input=${REALITY_INPUT/$'1\n1\n'/$'1\n4\n'} ;;
    xray-grpc) core=xray; protocol=26; input=${REALITY_INPUT/$'1\n1\n'/$'1\n5\n'} ;;
    singbox-grpc) core=sing-box; protocol=26; input=${SINGBOX_INPUT/$'2\n1\n'/$'2\n5\n'} ;;
    esac
    before=$(snapshot)
    runPty 0 "${transportCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${transportCase}: cancellation generated credentials or changed deployment"
    runPty 0 "${transportCase}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --arg core "${core}" --argjson protocol "${protocol}" '
      .core.type == $core and .core.secondary_type == null and .tls == null and
      (.subscription.enabled | not) and (.core.protocols | length) == 1 and
      (.core.protocols[0] | .id == $protocol and .core == $core and
        (.reality.private_key | length) == 43 and
        if $protocol == 2 then
          .listener_id == "entry-reality-xhttp" and
          .xhttp.host == .reality.server_name and .xhttp.mode == "auto" and
          (.xhttp.path | test("^/[a-f0-9]{32}$")) and (.grpc == null)
        else .listener_id == "entry-reality-grpc" and
          .grpc == {service_name: "grpc"} and (.xhttp == null) end)
    ' "${SPEC}" >/dev/null || fail "${transportCase}: generated transport or credentials were incorrect"
    CONTROL_LOG="${TEST_ROOT}/${transportCase}-list.log"
    bash -u "${CLI}" protocol list >"${CONTROL_LOG}" 2>&1 || fail "${transportCase}: protocol list failed"
    if [[ "${protocol}" == 2 ]]; then label='Reality XHTTP'; else label='Reality gRPC'; fi
    grep -Fq "${label}" "${CONTROL_LOG}" || fail "${transportCase}: protocol list used the wrong name"
    assertClean
    assertNoSecrets
done

# 双核心共用账号与 Reality 密钥，但入口身份和公开端口必须独立。
DUAL_XRAY_INPUT=$'3\n1\nproxy.example.com\n1\n24443\ntarget.example.com\n443\ntarget.example.com\n24445\ny\n'
DUAL_SINGBOX_INPUT=$'4\n1\nproxy.example.com\n1\n24443\ntarget.example.com\n443\ntarget.example.com\n24445\ny\n'
for dualCase in dual-xray dual-singbox dual-xray-xhttp dual-xray-grpc dual-singbox-grpc; do
    newState "${dualCase}"
    protocol=1; listener=vless-reality
    case "${dualCase}" in
    dual-xray*) input=${DUAL_XRAY_INPUT}; primary=xray; secondary=sing-box ;;
    dual-singbox*) input=${DUAL_SINGBOX_INPUT}; primary=sing-box; secondary=xray ;;
    esac
    case "${dualCase}" in
    dual-xray-xhttp)
        input=${input/$'3\n1\n'/$'3\n4\n'}; protocol=2; listener=entry-reality-xhttp
        ;;
    dual-xray-grpc)
        input=${input/$'3\n1\n'/$'3\n5\n'}; protocol=26; listener=entry-reality-grpc
        ;;
    dual-singbox-grpc)
        input=${input/$'4\n1\n'/$'4\n5\n'}; protocol=26; listener=entry-reality-grpc
        ;;
    esac
    runPty 0 "${dualCase}" "${input}" setup "${ASSET_ARGS[@]}"
    jq -e --arg primary "${primary}" --arg secondary "${secondary}" \
        --argjson protocol "${protocol}" --arg listener "${listener}" '
        .schema_version == 3 and .core.type == $primary and .core.secondary_type == $secondary and
        (.core.protocols | length) == 2 and
        [.core.protocols[].listener_id] == [$listener, "entry-secondary-reality"] and
        [.core.protocols[].public_port] == [24443,24445] and
        [.core.protocols[].core] == [$primary,$secondary] and
        .core.protocols[0].id == $protocol and .core.protocols[1].id == 1 and
        .core.protocols[1].xhttp == null and .core.protocols[1].grpc == null and
        .core.protocols[0].uuid == .core.protocols[1].uuid and
        .core.protocols[0].reality == .core.protocols[1].reality and
        (.core.protocols[0] |
          if $protocol == 2 then .xhttp.host == .reality.server_name and .xhttp.mode == "auto" and
            (.xhttp.path | test("^/[a-f0-9]{32}$")) and .grpc == null
          elif $protocol == 26 then .grpc == {service_name: "grpc"} and .xhttp == null
          else .xhttp == null and .grpc == null end)
    ' "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null ||
        fail "${dualCase}: setup lost core ownership, independent listeners or shared credentials"
    jq -e '.services | has("xray") and has("sing-box")' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${dualCase}: setup did not install both core services"
done

newState dual-port-conflict
before=$(snapshot)
runPty 11 dual-port-conflict "${DUAL_XRAY_INPUT/24445/24443}" setup "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
    fail 'dual-core conflicting ports reached confirmation, signature verification or generation'

printf 'fake-cert\n' >"${TEST_ROOT}/cert.pem"
printf 'fake-key\n' >"${TEST_ROOT}/key.pem"
chmod 0600 "${TEST_ROOT}/key.pem"
printf -v HY2_INPUT '2\n6\nproxy.example.com\n1\nhy2.example.com\n24449\n\n\n\nn\n\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_HY2_INPUT '4\n6\nproxy.example.com\n3\ntarget.example.com\n443\ntarget.example.com\n24445\nhy2.example.com\n24449\nbrutal\n120\n60\ny\nhttps://www.example.com/health\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for hy2Case in hy2-default dual-hy2; do
    newState "${hy2Case}"
    if [[ "${hy2Case}" == hy2-default ]]; then input=${HY2_INPUT}; else input=${DUAL_HY2_INPUT}; fi
    before=$(snapshot)
    runPty 0 "${hy2Case}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${hy2Case}: cancellation reached credentials, TLS or deployment writes"
    runPty 0 "${hy2Case}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --arg mode "${hy2Case}" '
      .schema_version == 3 and .core.type == "sing-box" and
      .tls.domain == "hy2.example.com" and (.subscription.enabled | not) and
      (.core.protocols[0] | .id == 3 and .core == "sing-box" and
        .listener_id == "entry-hysteria2" and .public_port == 24449 and
        .uuid == "11111111-1111-4111-8111-111111111111" and
        .reality == null and .hy2.domain == "hy2.example.com" and
        if $mode == "hy2-default" then
          .hy2 == {domain: "hy2.example.com", bandwidth_mode: "bbr",
            up_mbps: 100, down_mbps: 50, obfs: null, masquerade: ""}
        else .hy2.bandwidth_mode == "brutal" and .hy2.up_mbps == 120 and
          .hy2.down_mbps == 60 and .hy2.obfs.type == "salamander" and
          (.hy2.obfs.password | test("^[a-f0-9]{32}$")) and
          .hy2.masquerade == "https://www.example.com/health" end) and
      if $mode == "hy2-default" then
        .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == "xray" and (.core.protocols | length) == 2 and
        (.core.protocols[1] | .id == 1 and .core == "xray" and .public_port == 24445 and
          .listener_id == "entry-secondary-reality" and
          (.reality.private_key | length) == 43) and
        .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${hy2Case}: setup lost TLS, Hysteria2 parameters or the secondary Reality"
    [[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/hy2.example.com.crt" &&
        -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/hy2.example.com.key" ]] ||
        fail "${hy2Case}: setup did not commit Hysteria2 TLS"
    if [[ "${hy2Case}" == hy2-default ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" ||
            fail 'Hysteria2-only setup generated unused Reality keys'
    fi
    CONTROL_LOG="${TEST_ROOT}/${hy2Case}-list.log"
    bash -u "${CLI}" protocol list >"${CONTROL_LOG}" 2>&1 || fail "${hy2Case}: protocol list failed"
    grep -Fq Hysteria2 "${CONTROL_LOG}" || fail "${hy2Case}: protocol list mislabeled Hysteria2"
    assertNoSecrets
done

# 复用首配部署验证参数菜单、复制和取消，账号与 TLS 身份始终保持不变。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-hy2-default"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-hy2-default"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/hy2-original.json"
before=$(snapshot)
runPty 0 hy2-edit-cancel $'13\n3\n4\n2\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'cancelling a Hysteria2 password edit changed deployment'
runPty 0 hy2-edit $'13\n3\n1\nbrutal\n13\n3\n2\n180\n13\n3\n3\n90\n13\n3\n4\n2\nhy2-obfs-private-1234\n13\n3\n5\nhttps://www.example.com/proxy\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/hy2-original.json" '
  .core.protocols[0] as $p | $before[0].core.protocols[0] as $old |
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  ($p | del(.hy2)) == ($old | del(.hy2)) and
  ($p.hy2 | del(.obfs.password)) ==
    {domain: "hy2.example.com", bandwidth_mode: "brutal", up_mbps: 180, down_mbps: 90,
     obfs: {type: "salamander"}, masquerade: "https://www.example.com/proxy"}
' "${SPEC}" >/dev/null || fail 'Hysteria2 parameter editing changed identity or did not update all selected values'
[[ "$(jq -r '.core.protocols[0].hy2.obfs.password' "${SPEC}")" == hy2-obfs-private-1234 ]] ||
    fail 'Hysteria2 password editing did not preserve the private input'
runPty 0 hy2-copy $'9\n3\n2\n24450\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $first | .core.protocols[1] as $copy |
  $copy.listener_id == "entry-1" and $copy.public_port == 24450 and
  ($copy | del(.listener_id, .public_port)) == ($first | del(.listener_id, .public_port))
' "${SPEC}" >/dev/null || fail 'Hysteria2 copy did not preserve account, obfuscation, parameters and core'
runPty 0 hy2-clear $'13\nentry-1\n4\n1\n13\nentry-1\n5\noff\n13\nentry-1\n1\nbbr\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[1].hy2 | .bandwidth_mode == "bbr" and .obfs == null and .masquerade == ""' \
    "${SPEC}" >/dev/null || fail 'Hysteria2 clearing of obfuscation or masquerade failed'
before=$(snapshot)
runPty 15 hy2-copy-xray $'9\n3\n1\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'copying Hysteria2 to Xray changed deployment'
runPty 15 hy2-invalid-speed $'13\nentry-1\n2\n1000001\n8\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'out-of-range Hysteria2 bandwidth changed deployment'
for rejectedEdit in uuid domain core listener new-account; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.hy2.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24451 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/hy2-rejected.json"
    chmod 0600 "${TEST_ROOT}/hy2-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/hy2-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/hy2-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: Hysteria2 edit bypassed the identity boundary"
    assertClean
    assertNoSecrets
done

# 同一 TLS 的 WS 与 Hysteria2 删除顺序不得误删证书关系或继续发布订阅。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-dual-hy2"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-dual-hy2"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq '.core.protocols += [
  (.core.protocols[1] | .core = "sing-box" | .listener_id = "entry-sing-reality" | .public_port = 24446),
  {id: 21, core: "xray", listener_id: "vless-ws", server: "proxy.example.com", public_port: 24444,
   address_families: ["ipv4"], name: "main-ws", uuid: .core.protocols[0].uuid,
   websocket: {domain: .tls.domain, path: "abcdefghws", backend_port: 31297, tls_port: 8443}}] |
  .subscription.enabled = true' "${SPEC}" >"${TEST_ROOT}/hy2-with-ws.json"
chmod 0600 "${TEST_ROOT}/hy2-with-ws.json"
runPty 0 hy2-ws-configure '' configure --spec "${TEST_ROOT}/hy2-with-ws.json" "${ASSET_ARGS[@]}"
runPty 0 hy2-delete-ws $'10\nvless-ws\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "hy2.example.com" and (.subscription.enabled | not) and
  any(.core.protocols[]; .id == 3) and all(.core.protocols[]; .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting the last WS removed Hysteria2 TLS or kept HTTPS publication enabled'
runPty 0 hy2-delete-last-tls $'10\nentry-hysteria2\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls == null and (.subscription.enabled | not) and
  all(.core.protocols[]; .id != 3 and .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting the last TLS protocol retained its deployment TLS reference'

printf -v WS_INPUT '1\n2\nproxy.example.com\n1\nws.example.com\n24444\n2\n%s\n%s\ny\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for tlsCase in tls-fail ws-success; do
    newState "${tlsCase}"
    if [[ "${tlsCase}" == tls-fail ]]; then
        export FAKE_SETUP_MODE=tls-fail
        runPty 15 "${tlsCase}" "${WS_INPUT}" setup "${ASSET_ARGS[@]}"
        assertUnconfigured
        unset FAKE_SETUP_MODE
    else
        runPty 0 "${tlsCase}" "${WS_INPUT}" setup "${ASSET_ARGS[@]}"
        jq -e '.core.protocols[0].id == 21 and .tls.domain == "ws.example.com" and .subscription.enabled and
            (.subscription.token | length) >= 32 and (.core.protocols[0].websocket.path | length) >= 16' \
            "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null || fail 'WS setup omitted TLS/subscription/path fields'
        [[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.crt" &&
            -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.key" ]] ||
            fail 'WS setup did not commit imported TLS material'
    fi
done

newState dual-ws-reality
printf -v DUAL_WS_INPUT '3\n2\nproxy.example.com\n1\ntarget.example.com\n443\ntarget.example.com\n24445\nws.example.com\n24444\n2\n%s\n%s\ny\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
runPty 0 dual-ws-reality "${DUAL_WS_INPUT}" setup "${ASSET_ARGS[@]}"
jq -e '.schema_version == 3 and .core.type == "xray" and .core.secondary_type == "sing-box" and
    ([.core.protocols[].id] | sort) == [1,21] and
    any(.core.protocols[]; .id == 21 and .core == "xray") and
    any(.core.protocols[]; .id == 1 and .core == "sing-box" and
        (.reality.private_key | length) == 43 and (.reality.public_key | length) == 43) and
    .core.protocols[0].uuid == .core.protocols[1].uuid and .subscription.enabled' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null ||
    fail 'WS-only primary did not generate the secondary Reality credentials or core ownership'

newState both-managed
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme"
printf 'existing-selected-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.crt"
printf 'existing-selected-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.key"
printf 'existing-other-certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.crt"
printf 'existing-other-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/other.example.com.key"
printf 'existing-acme-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/existing-account.conf"
chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/"*.key
existingMaterials=$(find "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme" \
    -type f -exec sha256sum {} + | LC_ALL=C sort)
BOTH_INPUT=$'1\n3\nproxy.example.com\n3\n24443\ntarget.example.com\n443\ntarget.example.com\nws.example.com\n24444\n1\ny\ny\n'
runPty 0 both-managed "${BOTH_INPUT}" setup "${ASSET_ARGS[@]}"
jq -e '.core.type == "xray" and ([.core.protocols[].id] | sort) == [1,21] and
    all(.core.protocols[]; .address_families == ["ipv4","ipv6"]) and
    .core.protocols[0].uuid == .core.protocols[1].uuid and .subscription.enabled' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null ||
    fail 'combined Reality and WS setup omitted the selected protocols, shared account or address families'
[[ "$(find "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme" \
    -type f -exec sha256sum {} + | LC_ALL=C sort)" == "${existingMaterials}" ]] ||
    fail 'managed TLS setup replaced existing certificate or ACME account files'

printf 'DNS_TOKEN=fake\n' >"${TEST_ROOT}/dns.env"
chmod 0600 "${TEST_ROOT}/dns.env"
printf -v DNS_INPUT '1\n2\nproxy.example.com\n1\nws.example.com\n24444\n3\nadmin@example.com\ndns_cf\n%s\ny\ny\n' \
    "${TEST_ROOT}/dns.env"
for dnsCase in acme-fail dns-success; do
    newState "${dnsCase}"
    if [[ "${dnsCase}" == acme-fail ]]; then
        export FAKE_SETUP_MODE=acme-fail
        runPty 15 "${dnsCase}" "${DNS_INPUT}" setup "${ASSET_ARGS[@]}"
        assertUnconfigured
        [[ ! -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" ]] ||
            fail 'failed DNS-01 retained candidate ACME account'
        unset FAKE_SETUP_MODE
    else
        runPty 0 "${dnsCase}" "${DNS_INPUT}" setup "${ASSET_ARGS[@]}"
        [[ -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" &&
            -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/ws.example.com.crt" ]] ||
            fail 'DNS-01 setup did not commit certificate and ACME account together'
    fi
done

# 安装新传输只派生已有 Reality 凭据，原入口和内部身份不得被替换。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-xray-success"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-xray-success"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
: >"${EVENTS}"; : >"${VERIFY_LOG}"; : >"${ARGV_LOG}"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
SOURCE_SPEC="${TEST_ROOT}/derive-source.json"
cp -- "${SPEC}" "${SOURCE_SPEC}"
runPty 0 derive-xhttp $'11\nvless-reality\n2\n1\n24446\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${SOURCE_SPEC}" '
  .core.protocols[0] == $before[0].core.protocols[0] and
  (.core.protocols[1] | .id == 2 and .listener_id == "entry-1" and .core == "xray" and
    .public_port == 24446 and .uuid == $before[0].core.protocols[0].uuid and
    .reality == $before[0].core.protocols[0].reality and
    .xhttp == {path: "/entry-1xhttp", host: "target.example.com", mode: "auto"})
' "${SPEC}" >/dev/null || fail 'Reality XHTTP derivation changed source identity or transport defaults'
runPty 0 edit-xhttp $'12\nentry-1\n1\n/new-xhttp\n12\nentry-1\n2\ncdn.example.com\n12\nentry-1\n3\npacket-up\n5\nentry-1\n3\nnext.example.com\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[1] | .id == 2 and .reality.server_name == "next.example.com" and
    .xhttp == {path: "/new-xhttp", host: "cdn.example.com", mode: "packet-up"}' "${SPEC}" >/dev/null ||
    fail 'existing XHTTP transport or Reality parameter editing failed'
runPty 0 derive-grpc $'11\nentry-1\n26\n2\n24447\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.secondary_type == "sing-box" and
  (.core.protocols[2] | .id == 26 and .listener_id == "entry-2" and .core == "sing-box" and
    .grpc == {service_name: "grpc"} and .xhttp == null) and
  .core.protocols[2].uuid == .core.protocols[1].uuid and
  .core.protocols[2].reality == .core.protocols[1].reality' "${SPEC}" >/dev/null ||
    fail 'Reality gRPC derivation did not preserve credentials across cores'
runPty 0 edit-grpc $'12\nentry-2\ncustom-grpc\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[2].grpc.service_name == "custom-grpc"' "${SPEC}" >/dev/null ||
    fail 'existing gRPC service editing failed'
before=$(snapshot)
runPty 15 copy-xhttp-singbox $'9\nentry-1\n2\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'copying XHTTP to sing-box changed state'
for rejectedEdit in existing-id new-credential invalid-transport; do
    case "${rejectedEdit}" in
    existing-id) filter='.core.protocols[1] |= (.id = 26 | del(.xhttp) | .grpc = {service_name: "grpc"})' ;;
    new-credential) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24448 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    invalid-transport) filter='.core.protocols[1].xhttp.mode = "invalid-mode"' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/rejected-edit.json"
    chmod 0600 "${TEST_ROOT}/rejected-edit.json"
    CONTROL_LOG="${TEST_ROOT}/rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/rejected-edit.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: rejected edit changed state or bypassed identity/transport validation"
    assertClean
done

printf 'docker-setup-regression-ok\n'
