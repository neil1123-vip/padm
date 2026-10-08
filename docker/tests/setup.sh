#!/usr/bin/env bash
set -euo pipefail

SECTION=${1-all}
[[ "$#" -le 1 ]] || { printf 'usage: %s [all|core|encrypted|transports|tls]\n' "${BASH_SOURCE[0]}" >&2; exit 2; }
case "${SECTION}" in
all|core|encrypted|transports|tls) ;;
*) printf 'unknown setup section: %s\n' "${SECTION}" >&2; exit 2 ;;
esac

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
    elif [[ " $* " == *' generate rand --base64 16 '* ]]; then
        [[ " $* " == *'padm-sing-box:'* ]] || exit 1
        # 两次工具调用分别返回独立的 16 字节密钥；失败不能留下半份首配。
        keyCount=$(grep -c ' generate rand --base64 16$' "${FAKE_SETUP_EVENTS}")
        if (( keyCount % 2 == 1 )); then
            [[ "${mode}" != ss-server-key-fail ]] || exit 1
            if [[ "${mode}" == ss-malformed-key ]]; then
                printf 'MDEyMzQ1Njc4OWFiY2RlZh==\n'
            else
                printf 'MDEyMzQ1Njc4OWFiY2RlZg==\n'
            fi
        else
            [[ "${mode}" != ss-user-key-fail ]] || exit 1
            printf 'ZmVkY2JhOTg3NjU0MzIxMA==\n'
        fi
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
            if [[ "${mode}" == candidates ]]; then
                printf 'TLS Post-Quantum key exchange: X25519MLKEM768\nCertificate chain has length: 4400\n'
            fi
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
    docker/lib/services.sh docker/lib/traffic.sh docker/lib/renewal.sh docker/lib/schedule.sh docker/lib/geo.sh docker/lib/control-sync.sh docker/lib/lifecycle.sh docker/lib/menu.sh docker/lib/setup.sh docker/lib/accounts.sh docker/lib/subscriptions.sh docker/lib/business.sh docker/lib/reality-targets.sh \
    docker/contracts/configure.schema.json docker/contracts/deployment.schema.json \
    docker/contracts/features.json shell/core/deployment_mode.sh shell/core/stats_grpc.sh shell/core/runtime.sh shell/core/reality_targets.sh shell/core/cores.sh; do
    mkdir -p "${SOURCE_ROOT}/$(dirname -- "${relative}")"
    cp "${PROJECT_ROOT}/${relative}" "${SOURCE_ROOT}/${relative}"
done
cat >>"${SOURCE_ROOT}/shell/core/reality_targets.sh" <<'EOF'
lookupRealityTargetLocation() { printf 'Fixture Location\n'; }
currentRealityNetworkProfile() { printf '192.0.2.10\tAS64500\tExampleNet\n'; }
EOF
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
    find "${PADM_DOCKER_INSTALL_DIR}" -printf '%P %y %l\n' | LC_ALL=C sort
    find "${PADM_DOCKER_INSTALL_DIR}" -type f -print0 | LC_ALL=C sort -z |
        xargs -0 -r sha256sum --
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
    local -a secrets=(
        -e AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
        -e aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        -e hy2-obfs-private-1234 -e MDEyMzQ1Njc4OWFiY2RlZg== -e ZmVkY2JhOTg3NjU0MzIxMA==
        -e MDEyMzQ1Njc4OWFiY2RlZh==
    )
    ! grep -Fq "${secrets[@]}" "${CONTROL_LOG}" || fail 'setup printed a secret'
    ! grep -Fq "${secrets[@]}" "${ARGV_LOG}" || fail 'setup passed a secret through process arguments'
}

runPty() {
    local expected=$1 name=$2 input=$3 actual=0 feederStatus=0 command fifo feeder inputFd
    local interruptMode=0
    shift 3
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    fifo="${TEST_ROOT}/${name}.input"
    mkfifo "${fifo}"
    # 父进程保持写端打开，输入发送后不产生 EOF，也不再轮询命令完成。
    exec {inputFd}<>"${fifo}"
    printf -v command '%q ' bash -u "${CLI}" "$@"
    if [[ "${FAKE_SETUP_MODE:-}" == interrupt-int || "${FAKE_SETUP_MODE:-}" == interrupt-term ]]; then
        interruptMode=1
        rm -f -- "${FAKE_SETUP_CHILD_PID}"
        printf -v command 'printf "%%s\\n" "$$" >%q; exec %s' "${TEST_ROOT}/${name}.pid" "${command}"
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
    ) &
    feeder=$!
    timeout 240 script -q -e -E never -f -c "${command}" "${CONTROL_LOG}" \
        <"${fifo}" >"${TEST_ROOT}/${name}.stdout" 2>&1 || actual=$?
    exec {inputFd}>&-
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

REALITY_INPUT=$'1\n1\nproxy.example.com\n1\n24443\n2\ntarget.example.com:443\ntarget.example.com\ny\n'
SINGBOX_INPUT=$'2\n1\nproxy.example.com\n1\n24443\n2\ntarget.example.com:443\ntarget.example.com\ny\n'
printf 'fake-cert\n' >"${TEST_ROOT}/cert.pem"
printf 'fake-key\n' >"${TEST_ROOT}/key.pem"
chmod 0600 "${TEST_ROOT}/key.pem"

if [[ "${SECTION}" == all || "${SECTION}" == core ]]; then
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

for candidateCase in success return eof final-no no-a signature-fail; do
    newState "candidates-${candidateCase}"
    export FAKE_SETUP_MODE=candidates
    input=$'1\n1\nproxy.example.com\n1\n24443\n\n'
    expected=0
    case "${candidateCase}" in
    success) input+=$'1\n\ny\n' ;;
    return) input+=$'r\n' ;;
    eof) input+=$'\004' ;;
    final-no) input+=$'1\n\nn\n' ;;
    no-a) FAKE_SETUP_MODE=ok; input+=$'r\n' ;;
    signature-fail) FAKE_SETUP_MODE=signature-fail; expected=16 ;;
    esac
    runPty "${expected}" "candidates-${candidateCase}" "${input}" setup "${ASSET_ARGS[@]}"
    if [[ "${candidateCase}" == success ]]; then
        jq -e '.core.protocols[0].reality |
          .target_host != "" and .target_port == 443 and .server_name == .target_host' \
            "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null ||
            fail '候选首配未使用所选目标和默认 SNI'
        [[ "$(grep -c '^pull ' "${EVENTS}")" == 5 ]] || fail '候选首配重复准备发布镜像'
    else
        assertUnconfigured
        ! grep -Eq '^compose | uuid | x25519 | rand -hex ' "${EVENTS}" ||
            fail '候选取消或失败提前生成账号、写入或启动部署'
    fi
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/data/reality-targets" ]] ||
        fail '首配候选选择发布了临时目标库'
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail '首配候选交互占用了部署锁'
    if [[ "${candidateCase}" == signature-fail ]]; then
        [[ ! -s "${EVENTS}" ]] || fail '候选探测绕过发布验签'
    elif [[ "${candidateCase}" == no-a ]]; then
        grep -Fq '总数：0' "${CONTROL_LOG}" || fail '候选菜单包含未实测 A 级目标'
    fi
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
DUAL_XRAY_INPUT=$'3\n1\nproxy.example.com\n1\n24443\n2\ntarget.example.com:443\ntarget.example.com\n24445\ny\n'
DUAL_SINGBOX_INPUT=$'4\n1\nproxy.example.com\n1\n24443\n2\ntarget.example.com:443\ntarget.example.com\n24445\ny\n'
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
fi

if [[ "${SECTION}" == all || "${SECTION}" == encrypted ]]; then
# Shadowsocks 首配不读取 TLS 或订阅参数，仅在确认后生成两份独立密码。
SS_INPUT=$'2\n9\nproxy.example.com\n3\n24459\ny\n'
DUAL_SS_INPUT=$'4\n9\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\n24459\ny\n'
for ssCase in ss-default dual-ss; do
    newState "${ssCase}"
    if [[ "${ssCase}" == ss-default ]]; then input=${SS_INPUT}; single=true; else input=${DUAL_SS_INPUT}; single=false; fi
    before=$(snapshot)
    runPty 0 "${ssCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${ssCase}: cancellation reached key generation or deployment writes"
    runPty 0 "${ssCase}" "${input}" setup "${ASSET_ARGS[@]}"
    [[ "$(grep -c ' generate rand --base64 16$' "${EVENTS}")" -eq 2 ]] ||
        fail "${ssCase}: setup did not generate two independent passwords"
    ! grep -Eq 'TLS 域名|证书 \[|启用 HTTPS 订阅|拥塞模式|Salamander' "${CONTROL_LOG}" ||
        fail "${ssCase}: setup collected unrelated TLS or Hysteria2 inputs"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --argjson single "${single}" '
      .schema_version == 3 and .core.type == "sing-box" and .tls == null and
      (.subscription.enabled | not) and .host_integrations == [] and
      (.core.protocols[0] | .id == 30 and .core == "sing-box" and
        .listener_id == "entry-shadowsocks" and .name == "main-shadowsocks" and
        .server == "proxy.example.com" and .public_port == 24459 and
        .address_families == ["ipv4","ipv6"] and
        .uuid == "11111111-1111-4111-8111-111111111111" and
        .reality == null and .shadowsocks.method == "2022-blake3-aes-128-gcm" and
        (.shadowsocks.server_password | test("^[A-Za-z0-9+/]{21}[AQgw]==$")) and
        (.shadowsocks.user_password | test("^[A-Za-z0-9+/]{21}[AQgw]==$")) and
        .shadowsocks.server_password != .shadowsocks.user_password) and
      if $single then .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == "xray" and (.core.protocols | length) == 2 and
        (.core.protocols[1] | .id == 1 and .core == "xray" and .public_port == 24445 and
          .listener_id == "entry-secondary-reality" and (.reality.private_key | length) == 43) and
        .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${ssCase}: setup lost Shadowsocks credentials or core ownership"
    [[ "$(jq -r '.core.protocols[0].shadowsocks.server_password' "${SPEC}")" == MDEyMzQ1Njc4OWFiY2RlZg== &&
        "$(jq -r '.core.protocols[0].shadowsocks.user_password' "${SPEC}")" == ZmVkY2JhOTg3NjU0MzIxMA== ]] ||
        fail "${ssCase}: setup changed generated password bytes"
    jq -e --slurpfile spec "${SPEC}" '
      $spec[0].core.protocols[0] as $p | [.inbounds[] | select(.type == "shadowsocks")] |
      length == 1 and all(.[];
        .method == $p.shadowsocks.method and .password == $p.shadowsocks.server_password and
        .users == [{name: $p.uuid, password: $p.shadowsocks.user_password}] and
        .network == null and .tls == null)
    ' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null ||
        fail "${ssCase}: runtime lost the password, statistics identity or TCP/UDP default"
    jq -e '.services["sing-box"].ports | sort ==
      ["0.0.0.0:24459:24459/tcp", "0.0.0.0:24459:24459/udp",
       "[::]:24459:24459/tcp", "[::]:24459:24459/udp"]' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${ssCase}: setup did not publish TCP and UDP for both address families"
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" ||
            fail 'Shadowsocks-only setup generated unused Reality keys'
        ! grep -Fq 'Reality 目标' "${CONTROL_LOG}" || fail 'Shadowsocks-only setup collected a Reality target'
    fi
    CONTROL_LOG="${TEST_ROOT}/${ssCase}-list.log"
    bash -u "${CLI}" protocol list >"${CONTROL_LOG}" 2>&1 || fail "${ssCase}: protocol list failed"
    grep -Fq Shadowsocks "${CONTROL_LOG}" || fail "${ssCase}: protocol list mislabeled Shadowsocks"
    assertNoSecrets
done
for ssFailure in ss-server-key-fail ss-user-key-fail ss-malformed-key; do
    newState "${ssFailure}"
    export FAKE_SETUP_MODE="${ssFailure}"
    runPty 15 "${ssFailure}" "${SS_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
    unset FAKE_SETUP_MODE
done
newState ss-dual-port-conflict
before=$(snapshot)
runPty 11 ss-dual-port-conflict "${DUAL_SS_INPUT/24459/24445}" setup "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
    fail 'Shadowsocks dual-core port conflict reached generation or deployment writes'

# 通用编辑、复制和删除不重写 Shadowsocks 方法、密码、统计身份或核心。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-ss-default"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-ss-default"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/ss-original.json"
before=$(snapshot)
runPty 0 ss-edit-cancel $'1\n30\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'cancelling a Shadowsocks edit changed deployment'
runPty 0 ss-edit $'1\n30\n24460\n2\n30\nnext.example.com\n3\n30\n2\n4\n30\nnext-shadowsocks\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/ss-original.json" '
  .tls == null and .subscription == $before[0].subscription and
  (.core.protocols[0] | del(.public_port, .server, .address_families, .name)) ==
    ($before[0].core.protocols[0] | del(.public_port, .server, .address_families, .name)) and
  (.core.protocols[0] | .public_port == 24460 and .server == "next.example.com" and
    .address_families == ["ipv6"] and .name == "next-shadowsocks")
' "${SPEC}" >/dev/null || fail 'Shadowsocks editing changed identity or did not apply selected values'
runPty 0 ss-copy $'9\n30\n2\n24461\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $first | .core.protocols[1] as $copy |
  $copy.listener_id == "entry-1" and $copy.public_port == 24461 and
  ($copy | del(.listener_id, .public_port)) == ($first | del(.listener_id, .public_port))
' "${SPEC}" >/dev/null || fail 'Shadowsocks copy lost passwords, account or core'
before=$(snapshot)
runPty 15 ss-copy-xray $'9\nentry-shadowsocks\n1\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'copying Shadowsocks to Xray changed deployment'
for rejectedEdit in uuid method server-password user-password core listener new-account new-naive; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    method) filter='.core.protocols[0].shadowsocks.method = "2022-blake3-aes-256-gcm"' ;;
    server-password) filter='.core.protocols[0].shadowsocks.server_password = ("A" * 22 + "==")' ;;
    user-password) filter='.core.protocols[0].shadowsocks.user_password = ("A" * 22 + "==")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24462 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-naive) filter='.tls = {domain: "naive.example.com"} |
        .core.protocols += [.core.protocols[0] | .listener_id = "entry-3" | .public_port = 24462 |
          .id = 5 | .server = "naive.example.com" | .naive = {domain: "naive.example.com"} | del(.shadowsocks)]' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/ss-rejected.json"
    chmod 0600 "${TEST_ROOT}/ss-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/ss-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/ss-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: Shadowsocks edit bypassed the identity boundary"
    assertClean
    assertNoSecrets
done
runPty 0 ss-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls == null and (.core.protocols | length) == 1 and
  .core.protocols[0].listener_id == "entry-shadowsocks"' "${SPEC}" >/dev/null ||
    fail 'deleting a Shadowsocks copy changed the original entry or TLS state'
before=$(snapshot)
runPty 15 ss-delete-last-primary $'10\nentry-shadowsocks\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'deleting the final primary Shadowsocks entry changed deployment'

printf -v HY2_INPUT '2\n6\nproxy.example.com\n1\nhy2.example.com\n24449\n\n\n\nn\n\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_HY2_INPUT '4\n6\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nhy2.example.com\n24449\nbrutal\n120\n60\ny\nhttps://www.example.com/health\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v ANYTLS_INPUT '2\n7\nproxy.example.com\n3\nanytls.example.com\n24451\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_ANYTLS_INPUT '4\n7\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nanytls.example.com\n24451\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v NAIVE_INPUT '2\n8\nnaive.example.com\n3\n\n24455\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_NAIVE_INPUT '4\n8\nnaive.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nnaive.example.com\n24455\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for tlsProtocolCase in anytls-default dual-anytls naive-default dual-naive; do
    newState "${tlsProtocolCase}"
    case "${tlsProtocolCase}" in
    anytls-default) input=${ANYTLS_INPUT}; single=true ;;
    dual-anytls) input=${DUAL_ANYTLS_INPUT}; single=false ;;
    naive-default) input=${NAIVE_INPUT}; single=true ;;
    dual-naive) input=${DUAL_NAIVE_INPUT}; single=false ;;
    esac
    if [[ "${tlsProtocolCase}" == *naive* ]]; then
        protocol=5; protocolType=naive; label=NaiveProxy; domain=naive.example.com; port=24455
    else
        protocol=4; protocolType=anytls; label=AnyTLS; domain=anytls.example.com; port=24451
    fi
    before=$(snapshot)
    runPty 0 "${tlsProtocolCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${tlsProtocolCase}: cancellation reached credentials, TLS or deployment writes"
    runPty 0 "${tlsProtocolCase}" "${input}" setup "${ASSET_ARGS[@]}"
    ! grep -Fq '11111111-1111-4111-8111-111111111111' "${ARGV_LOG}" "${CONTROL_LOG}" ||
        fail "${tlsProtocolCase}: the generated password appeared in arguments or output"
    ! grep -Eq '拥塞模式|上行带宽|下行带宽|Salamander|伪装 HTTPS|启用 HTTPS 订阅' "${CONTROL_LOG}" ||
        fail "${tlsProtocolCase}: setup collected unrelated Hysteria2 or publication parameters"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --argjson single "${single}" --argjson protocol "${protocol}" \
        --arg type "${protocolType}" --arg domain "${domain}" --argjson port "${port}" '
      .schema_version == 3 and .core.type == "sing-box" and
      .tls.domain == $domain and (.subscription.enabled | not) and
      .host_integrations == [] and
      (.core.protocols[0] | .id == $protocol and .core == "sing-box" and
        .listener_id == ("entry-" + $type) and .name == ("main-" + $type) and .public_port == $port and
        .address_families == ["ipv4","ipv6"] and
        .uuid == "11111111-1111-4111-8111-111111111111" and .reality == null and
        .hy2 == null and .[$type] == {domain: $domain} and
        if $protocol == 5 then .server == $domain and .anytls == null else .naive == null end) and
      if $single then
        .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == "xray" and (.core.protocols | length) == 2 and
        (.core.protocols[1] | .id == 1 and .core == "xray" and .public_port == 24445 and
          .listener_id == "entry-secondary-reality" and
          (.reality.private_key | length) == 43) and
        .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${tlsProtocolCase}: setup lost TLS parameters, shared account or secondary Reality"
    [[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${domain}.crt" &&
        -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/${domain}.key" ]] ||
        fail "${tlsProtocolCase}: setup did not commit TLS"
    jq -e --arg type "${protocolType}" --arg domain "${domain}" '
      .inbounds[] | select(.type == $type) |
      .users == [(if $type == "naive" then {username: "11111111-1111-4111-8111-111111111111"}
        else {name: "11111111-1111-4111-8111-111111111111"} end) +
        {password: "11111111-1111-4111-8111-111111111111"}] and
      .tls.enabled and .tls.server_name == $domain and
      if $type == "naive" then .network == "tcp" else true end' \
        "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null ||
        fail "${tlsProtocolCase}: runtime did not reuse the UUID for the password and account"
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" ||
            fail "${tlsProtocolCase}: TLS-only setup generated unused Reality keys"
        ! grep -Fq 'Reality 目标' "${CONTROL_LOG}" || fail "${tlsProtocolCase}: setup collected an unused Reality target"
    fi
    CONTROL_LOG="${TEST_ROOT}/${tlsProtocolCase}-list.log"
    bash -u "${CLI}" protocol list >"${CONTROL_LOG}" 2>&1 || fail "${tlsProtocolCase}: protocol list failed"
    grep -Fq "${label}" "${CONTROL_LOG}" || fail "${tlsProtocolCase}: protocol list used the wrong name"
    assertNoSecrets
done

for tlsProtocol in anytls naive; do
    newState "${tlsProtocol}-tls-fail"
    if [[ "${tlsProtocol}" == naive ]]; then input=${NAIVE_INPUT}; else input=${ANYTLS_INPUT}; fi
    export FAKE_SETUP_MODE=tls-fail
    runPty 15 "${tlsProtocol}-tls-fail" "${input}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
    unset FAKE_SETUP_MODE
done

for rejectedSetup in naive-domain naive-port; do
    newState "${rejectedSetup}"
    before=$(snapshot)
    if [[ "${rejectedSetup}" == naive-domain ]]; then
        input=$'2\n8\nproxy.example.com\n1\nnaive.example.com\n'; expected=2
    else
        input=${DUAL_NAIVE_INPUT/24455/24445}; expected=11
    fi
    runPty "${expected}" "${rejectedSetup}" "${input}" setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${rejectedSetup}: rejection reached verification, credentials or deployment writes"
    ! grep -Fq '确认首次配置' "${CONTROL_LOG}" || fail "${rejectedSetup}: rejection reached confirmation"
done

# NaiveProxy 复用通用编辑与同核复制；原生 URI 的服务器不能与冻结的证书域名分离。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-naive-default"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-naive-default"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/naive-original.json"
before=$(snapshot)
runPty 0 naive-edit-cancel $'1\n5\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'cancelling a NaiveProxy edit changed deployment'
runPty 0 naive-edit $'1\n5\n24456\n2\n5\n\n3\n5\n2\n4\n5\nnext-naive\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/naive-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | del(.public_port, .address_families, .name)) ==
    ($before[0].core.protocols[0] | del(.public_port, .address_families, .name)) and
  (.core.protocols[0] | .public_port == 24456 and .address_families == ["ipv6"] and .name == "next-naive")
' "${SPEC}" >/dev/null || fail 'NaiveProxy editing changed identity or did not apply selected values'
runPty 0 naive-copy $'9\n5\n2\n24457\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $first | .core.protocols[1] as $copy |
  $copy.listener_id == "entry-1" and $copy.public_port == 24457 and
  ($copy | del(.listener_id, .public_port)) == ($first | del(.listener_id, .public_port))
' "${SPEC}" >/dev/null || fail 'NaiveProxy copy did not preserve the shared account, TLS and core'
before=$(snapshot)
runPty 15 naive-copy-xray $'9\nentry-naive\n1\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'copying NaiveProxy to Xray changed deployment'
runPty 15 naive-edit-server $'2\nentry-naive\nnext.example.com\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'changing NaiveProxy server away from its TLS domain changed deployment'
! grep -Fq '配置差异' "${CONTROL_LOG}" || fail 'NaiveProxy server mismatch reached confirmation preview'
for rejectedEdit in uuid domain core listener server new-account new-anytls new-shadowsocks; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" |
        .core.protocols |= map(.server = "next.example.com" | .naive.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    server) filter='.core.protocols[0].server = "next.example.com"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24458 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-anytls) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24458 | .id = 4 | .anytls = {domain: .naive.domain} | del(.naive)]' ;;
    new-shadowsocks) filter='.core.protocols += [$ss[0].core.protocols[0] |
        .listener_id = "entry-3" | .public_port = 24463]' ;;
    esac
    jq --slurpfile ss "${TEST_ROOT}/ss-original.json" "${filter}" "${SPEC}" >"${TEST_ROOT}/naive-rejected.json"
    chmod 0600 "${TEST_ROOT}/naive-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/naive-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/naive-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: NaiveProxy edit bypassed the identity boundary"
    assertClean
    assertNoSecrets
done
runPty 0 naive-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "naive.example.com" and (.core.protocols | length) == 1 and
  .core.protocols[0].listener_id == "entry-naive"' "${SPEC}" >/dev/null ||
    fail 'deleting a NaiveProxy copy removed the remaining TLS reference'

# AnyTLS 复用通用字段编辑与同核复制，凭据、域名、核心和入口身份不能被重写。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-anytls-default"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-anytls-default"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/anytls-original.json"
before=$(snapshot)
runPty 0 anytls-edit-cancel $'1\n4\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'cancelling an AnyTLS edit changed deployment'
runPty 0 anytls-edit $'1\n4\n24452\n2\n4\nnext.example.com\n3\n4\n2\n4\n4\nnext-anytls\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/anytls-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | del(.public_port, .server, .address_families, .name)) ==
    ($before[0].core.protocols[0] | del(.public_port, .server, .address_families, .name)) and
  (.core.protocols[0] | .public_port == 24452 and .server == "next.example.com" and
    .address_families == ["ipv6"] and .name == "next-anytls")
' "${SPEC}" >/dev/null || fail 'AnyTLS generic editing changed identity or did not apply selected values'
runPty 0 anytls-copy $'9\n4\n2\n24453\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $first | .core.protocols[1] as $copy |
  $copy.listener_id == "entry-1" and $copy.public_port == 24453 and
  ($copy | del(.listener_id, .public_port)) == ($first | del(.listener_id, .public_port))
' "${SPEC}" >/dev/null || fail 'AnyTLS copy did not preserve the shared account, TLS and core'
before=$(snapshot)
runPty 15 anytls-copy-xray $'9\nentry-anytls\n1\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'copying AnyTLS to Xray changed deployment'
for rejectedEdit in uuid domain core listener new-account new-hy2 new-naive; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.anytls.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24454 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-hy2) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24454 | .id = 3 | .hy2 = {domain: .anytls.domain,
          bandwidth_mode: "bbr", up_mbps: 100, down_mbps: 50, obfs: null, masquerade: ""} | del(.anytls)]' ;;
    new-naive) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24458 | .id = 5 | .server = .anytls.domain |
        .naive = {domain: .anytls.domain} | del(.anytls)]' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/anytls-rejected.json"
    chmod 0600 "${TEST_ROOT}/anytls-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/anytls-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/anytls-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: AnyTLS edit bypassed the identity boundary"
    assertClean
    assertNoSecrets
done

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
for rejectedEdit in uuid domain core listener new-account new-anytls new-naive; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.hy2.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24451 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-anytls) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24451 | .id = 4 | .anytls = {domain: .hy2.domain} | del(.hy2)]' ;;
    new-naive) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
        .public_port = 24458 | .id = 5 | .server = .hy2.domain |
        .naive = {domain: .hy2.domain} | del(.hy2)]' ;;
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

# TLS 入口删除不得误删仍需证书的入口；最后保留 Shadowsocks 时仍清除无用 TLS 关系。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-dual-hy2"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-dual-hy2"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq --slurpfile ss "${TEST_ROOT}/ss-original.json" '.core.protocols += [
  $ss[0].core.protocols[0],
  (.core.protocols[1] | .core = "sing-box" | .listener_id = "entry-sing-reality" | .public_port = 24446),
  {id: 4, core: "sing-box", listener_id: "entry-anytls", server: "proxy.example.com", public_port: 24451,
   address_families: ["ipv4","ipv6"], name: "main-anytls", uuid: .core.protocols[0].uuid,
   anytls: {domain: .tls.domain}},
  {id: 5, core: "sing-box", listener_id: "entry-naive", server: .tls.domain, public_port: 24455,
   address_families: ["ipv4","ipv6"], name: "main-naive", uuid: .core.protocols[0].uuid,
   naive: {domain: .tls.domain}},
  {id: 21, core: "xray", listener_id: "vless-ws", server: "proxy.example.com", public_port: 24444,
   address_families: ["ipv4"], name: "main-ws", uuid: .core.protocols[0].uuid,
   websocket: {domain: .tls.domain, path: "abcdefghws", backend_port: 31297, tls_port: 8443}}] |
  .subscription.enabled = true' "${SPEC}" >"${TEST_ROOT}/hy2-with-ws.json"
chmod 0600 "${TEST_ROOT}/hy2-with-ws.json"
runPty 0 hy2-ws-configure '' configure --spec "${TEST_ROOT}/hy2-with-ws.json" "${ASSET_ARGS[@]}"
runPty 0 hy2-delete-ws $'10\nvless-ws\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "hy2.example.com" and (.subscription.enabled | not) and
  any(.core.protocols[]; .id == 3) and any(.core.protocols[]; .id == 4) and any(.core.protocols[]; .id == 5) and
  all(.core.protocols[]; .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting the last WS removed remaining TLS protocols or kept HTTPS publication enabled'
runPty 0 hy2-delete-retain-anytls $'10\nentry-hysteria2\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "hy2.example.com" and (.subscription.enabled | not) and
  any(.core.protocols[]; .id == 4) and any(.core.protocols[]; .id == 5) and
  all(.core.protocols[]; .id != 3 and .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting Hysteria2 removed remaining AnyTLS/NaiveProxy TLS references'
runPty 0 anytls-delete-retain-naive $'10\nentry-anytls\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "hy2.example.com" and (.subscription.enabled | not) and
  any(.core.protocols[]; .id == 5) and all(.core.protocols[]; .id != 3 and .id != 4 and .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting AnyTLS removed the remaining NaiveProxy TLS reference'
runPty 0 naive-delete-last-tls $'10\nentry-naive\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls == null and (.subscription.enabled | not) and
  any(.core.protocols[]; .id == 30) and
  all(.core.protocols[]; .id != 3 and .id != 4 and .id != 5 and .id != 21)' "${SPEC}" >/dev/null ||
    fail 'deleting the last TLS protocol removed Shadowsocks or retained its TLS reference'
fi

if [[ "${SECTION}" == all || "${SECTION}" == transports ]]; then
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
printf -v DUAL_WS_INPUT '3\n2\nproxy.example.com\n1\n2\ntarget.example.com:443\ntarget.example.com\n24445\nws.example.com\n24444\n2\n%s\n%s\ny\ny\n' \
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
BOTH_INPUT=$'1\n3\nproxy.example.com\n3\n24443\n2\ntarget.example.com:443\ntarget.example.com\nws.example.com\n24444\n1\ny\ny\n'
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

# NaiveProxy 的已有受管证书与 DNS-01 仍使用首配的候选事务。
for naiveTlsCase in managed dns-success dns-fail; do
    newState "naive-${naiveTlsCase}"
    if [[ "${naiveTlsCase}" == managed ]]; then
        mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
        cp -- "${TEST_ROOT}/cert.pem" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/naive.example.com.crt"
        cp -- "${TEST_ROOT}/key.pem" "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/naive.example.com.key"
        chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/naive.example.com.key"
        input=$'2\n8\nnaive.example.com\n1\n\n24455\n1\ny\n'
    else
        printf -v input '2\n8\nnaive.example.com\n1\n\n24455\n3\nadmin@example.com\ndns_cf\n%s\ny\n' \
            "${TEST_ROOT}/dns.env"
    fi
    if [[ "${naiveTlsCase}" == dns-fail ]]; then
        export FAKE_SETUP_MODE=acme-fail
        runPty 15 "naive-${naiveTlsCase}" "${input}" setup "${ASSET_ARGS[@]}"
        assertUnconfigured
        [[ ! -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" ]] ||
            fail 'failed NaiveProxy DNS-01 retained candidate ACME state'
        unset FAKE_SETUP_MODE
    else
        runPty 0 "naive-${naiveTlsCase}" "${input}" setup "${ASSET_ARGS[@]}"
        [[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/naive.example.com.crt" &&
            -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/naive.example.com.key" ]] ||
            fail "${naiveTlsCase}: NaiveProxy TLS was not committed"
        jq -e '.tls.domain == "naive.example.com" and
          .core.protocols[0].server == .core.protocols[0].naive.domain' \
            "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >/dev/null ||
            fail "${naiveTlsCase}: NaiveProxy TLS lost the same-domain contract"
        [[ "${naiveTlsCase}" != dns-success ||
            -f "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf" ]] ||
            fail 'NaiveProxy DNS-01 did not commit its ACME account'
    fi
done
fi

if [[ "${SECTION}" == all || "${SECTION}" == core ]]; then
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
fi

if [[ "${SECTION}" == all || "${SECTION}" == encrypted ]]; then
# TUIC 复用首配与编辑事务；取消、凭据冻结和 TLS 消费者删除均检查受管状态。
printf -v TUIC_INPUT '2\n10\nproxy.example.com\n3\ntuic.example.com\n24465\n\n\n\nn\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_TUIC_INPUT '4\n10\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\ntuic.example.com\n24465\nbbr\n8s\n20s\ny\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for tuicCase in tuic-default dual-tuic; do
    newState "${tuicCase}"
    if [[ "${tuicCase}" == tuic-default ]]; then input=${TUIC_INPUT}; single=true
    else input=${DUAL_TUIC_INPUT}; single=false; fi
    before=$(snapshot)
    runPty 0 "${tuicCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${tuicCase}: 取消首配提前生成账号或写入部署"
    runPty 0 "${tuicCase}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --argjson single "${single}" '
      .schema_version == 3 and .core.type == "sing-box" and
      .tls.domain == "tuic.example.com" and .subscription.enabled == false and
      (.core.protocols[0] | .id == 31 and .core == "sing-box" and
        .listener_id == "entry-tuic" and .public_port == 24465 and
        .uuid == "11111111-1111-4111-8111-111111111111" and .reality == null and
        .tuic == (if $single then {domain:"tuic.example.com",congestion_control:"cubic",
          auth_timeout:"3s",heartbeat:"10s",zero_rtt_handshake:false}
        else {domain:"tuic.example.com",congestion_control:"bbr",
          auth_timeout:"8s",heartbeat:"20s",zero_rtt_handshake:true} end)) and
      if $single then .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == "xray" and (.core.protocols | length) == 2 and
        .core.protocols[1].id == 1 and .core.protocols[1].public_port == 24445 and
        .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${tuicCase}: TUIC 首配参数或双核心身份错误"
    jq -e --slurpfile spec "${SPEC}" '
      $spec[0].core.protocols[0] as $p |
      .inbounds[] | select(.type == "tuic") |
      .users == [{name:$p.uuid,uuid:$p.uuid,password:$p.uuid}] and .tls.alpn == ["h3"] and
      .congestion_control == $p.tuic.congestion_control and .auth_timeout == $p.tuic.auth_timeout and
      .heartbeat == $p.tuic.heartbeat and .zero_rtt_handshake == $p.tuic.zero_rtt_handshake
    ' "${PADM_DOCKER_INSTALL_DIR}/config/sing-box/config.json" >/dev/null ||
        fail "${tuicCase}: TUIC 生成参数或流量身份错误"
    jq -e '.services["sing-box"].ports ==
      ["0.0.0.0:24465:24465/udp","[::]:24465:24465/udp"]' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null || fail 'TUIC 非 UDP 双栈发布'
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail 'TUIC 单核生成了无用 Reality 密钥'
    fi
    assertClean
    assertNoSecrets
done

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-tuic-default"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-tuic-default"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/tuic-original.json"
before=$(snapshot)
runPty 0 tuic-edit-cancel $'14\n31\n1\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'TUIC 参数取消改变部署'
runPty 0 tuic-edit $'14\n31\n1\nnew_reno\n14\n31\n2\n5s\n14\n31\n3\n12s\n14\n31\n4\ny\n1\n31\n24466\n2\n31\nnext.example.com\n3\n31\n2\n4\n31\nnext-tuic\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/tuic-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | .uuid == $before[0].core.protocols[0].uuid and
    .listener_id == "entry-tuic" and .public_port == 24466 and .server == "next.example.com" and
    .address_families == ["ipv6"] and .name == "next-tuic" and
    .tuic == {domain:"tuic.example.com",congestion_control:"new_reno",
      auth_timeout:"5s",heartbeat:"12s",zero_rtt_handshake:true})
' "${SPEC}" >/dev/null || fail 'TUIC 参数/通用编辑未更新或改写身份'
runPty 0 tuic-copy $'9\n31\n2\n24467\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $source | .core.protocols[1] as $copy |
  $copy.listener_id == "entry-1" and $copy.public_port == 24467 and
  ($copy | del(.listener_id,.public_port)) == ($source | del(.listener_id,.public_port))
' "${SPEC}" >/dev/null || fail 'TUIC 同核复制改变账号或参数'
before=$(snapshot)
runPty 15 tuic-copy-xray $'9\nentry-tuic\n1\n' edit "${ASSET_ARGS[@]}"
runPty 15 tuic-invalid-duration $'14\nentry-tuic\n2\n0s\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'TUIC 非法编辑或跨核复制改变部署'
for rejectedEdit in uuid domain core listener new-account new-anytls; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.tuic.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "xray" | .core.secondary_type = "xray"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
      .public_port = 24468 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-anytls) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
      .public_port = 24468 | .id = 4 | .anytls = {domain:.tuic.domain} | del(.tuic)]' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/tuic-rejected.json"
    chmod 0600 "${TEST_ROOT}/tuic-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/tuic-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/tuic-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: TUIC 编辑绕过身份边界"
    assertClean
done
runPty 0 tuic-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "tuic.example.com" and (.core.protocols | length) == 1' "${SPEC}" >/dev/null ||
    fail '删除 TUIC 副本移除了仍需 TLS 的入口'

# 混合入口删除仍保留 TUIC 证书关系；最后删除 TUIC 后只撤销规格引用。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-dual-tuic"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-dual-tuic"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq --slurpfile ss "${TEST_ROOT}/ss-original.json" '
  .core.protocols += [$ss[0].core.protocols[0], {
    id:21,core:"xray",listener_id:"vless-ws",server:"proxy.example.com",public_port:24444,
    address_families:["ipv4"],name:"main-ws",uuid:.core.protocols[0].uuid,
    websocket:{domain:.tls.domain,path:"abcdefghws",backend_port:31297,tls_port:8443}}] |
  .subscription.enabled = true
' "${SPEC}" >"${TEST_ROOT}/tuic-with-ws.json"
chmod 0600 "${TEST_ROOT}/tuic-with-ws.json"
runPty 0 tuic-ws-configure '' configure --spec "${TEST_ROOT}/tuic-with-ws.json" "${ASSET_ARGS[@]}"
runPty 0 tuic-delete-ws $'10\nvless-ws\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "tuic.example.com" and .subscription.enabled == false and
  any(.core.protocols[]; .id == 31)' "${SPEC}" >/dev/null ||
    fail '删除 WS 丢失了 TUIC TLS 关系'
runPty 0 tuic-delete-last-tls $'10\nentry-tuic\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls == null and .subscription.enabled == false and
  any(.core.protocols[]; .id == 30) and all(.core.protocols[]; .id != 31)' "${SPEC}" >/dev/null ||
    fail '删除最后 TUIC TLS 消费者未清理规格引用'
[[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/tuic.example.com.key" ]] ||
    fail '删除 TUIC 错误删除了受管证书'
for tuicFailure in tls-fail health-fail; do
    newState "tuic-${tuicFailure}"
    export FAKE_SETUP_MODE="${tuicFailure}"
    if [[ "${tuicFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
    runPty "${expected}" "tuic-${tuicFailure}" "${TUIC_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
done
export FAKE_SETUP_MODE=ok
fi

if [[ "${SECTION}" == all || "${SECTION}" == transports ]]; then
# Trojan direct 在两核心共用 UUID/password，复制和删除沿用受管编辑事务。
printf -v TROJAN_INPUT '1\n11\nproxy.example.com\n3\ntrojan.example.com\n24476\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v SING_TROJAN_INPUT '2\n11\nproxy.example.com\n3\ntrojan.example.com\n24476\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_TROJAN_INPUT '3\n11\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\ntrojan.example.com\n24476\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_SING_TROJAN_INPUT '4\n11\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\ntrojan.example.com\n24476\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for trojanCase in trojan-xray trojan-sing dual-trojan-xray dual-trojan-sing; do
    newState "${trojanCase}"
    case "${trojanCase}" in
    trojan-xray) input=${TROJAN_INPUT}; core=xray; single=true ;;
    trojan-sing) input=${SING_TROJAN_INPUT}; core=sing-box; single=true ;;
    dual-trojan-xray) input=${DUAL_TROJAN_INPUT}; core=xray; single=false ;;
    dual-trojan-sing) input=${DUAL_SING_TROJAN_INPUT}; core=sing-box; single=false ;;
    esac
    before=$(snapshot)
    runPty 0 "${trojanCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${trojanCase}: 取消首配提前生成凭据或写入部署"
    runPty 0 "${trojanCase}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --arg core "${core}" --argjson single "${single}" '
      .schema_version == 3 and .core.type == $core and .tls.domain == "trojan.example.com" and
      .subscription.enabled == false and
      (.core.protocols[0] | .id == 28 and .core == $core and .listener_id == "entry-trojan" and
        .public_port == 24476 and .address_families == ["ipv4","ipv6"] and
        .name == "main-trojan" and .server == "proxy.example.com" and
        .uuid == "11111111-1111-4111-8111-111111111111" and .reality == null and
        .trojan == {domain:"trojan.example.com"}) and
      if $single then .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == (if $core == "xray" then "sing-box" else "xray" end) and
        (.core.protocols | length) == 2 and .core.protocols[1].id == 1 and
        .core.protocols[1].public_port == 24445 and .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${trojanCase}: Trojan 首配丢失核心归属或共享凭据"
    jq -e --arg core "${core}" --slurpfile spec "${SPEC}" '
      $spec[0].core.protocols[0] as $p |
      if $core == "xray" then
        any(.inbounds[]; .protocol == "trojan" and .settings.clients == [{email:$p.uuid,password:$p.uuid}] and
          .streamSettings.security == "tls" and .streamSettings.tlsSettings.alpn == ["http/1.1"])
      else any(.inbounds[]; .type == "trojan" and .users == [{name:$p.uuid,password:$p.uuid}] and
        .tls.enabled and .tls.alpn == ["http/1.1"]) end
    ' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null ||
        fail "${trojanCase}: Trojan 认证或统计身份错误"
    jq -e --arg core "${core}" '.services[$core].ports ==
      ["0.0.0.0:24476:24476/tcp","[::]:24476:24476/tcp"] and
      (.services | has("nginx") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${trojanCase}: Trojan direct 非 TCP 双栈或启动 Nginx"
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail 'Trojan 单核生成了无用 Reality 密钥'
    fi
    assertClean
    assertNoSecrets
done

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-trojan-xray"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-trojan-xray"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/trojan-original.json"
before=$(snapshot)
runPty 0 trojan-edit-cancel $'1\n28\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'Trojan 取消编辑改变部署'
runPty 0 trojan-edit $'1\n28\n24477\n2\n28\nnext.example.com\n3\n28\n2\n4\n28\nnext-trojan\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/trojan-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | .uuid == $before[0].core.protocols[0].uuid and
    .listener_id == "entry-trojan" and .public_port == 24477 and .server == "next.example.com" and
    .address_families == ["ipv6"] and .name == "next-trojan" and
    .trojan == {domain:"trojan.example.com"})
' "${SPEC}" >/dev/null || fail 'Trojan 通用编辑改写了 TLS 或账号身份'
runPty 0 trojan-copy-xray $'9\n28\n1\n24478\n8\ny\n' edit "${ASSET_ARGS[@]}"
runPty 0 trojan-copy-sing $'9\nentry-trojan\n2\n24479\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $source | .core.secondary_type == "sing-box" and
  (.core.protocols | length) == 3 and
  all(.core.protocols[1:][]; .uuid == $source.uuid and .trojan == $source.trojan and
    .server == $source.server and .name == $source.name and .address_families == $source.address_families) and
  (.core.protocols[1] | .core == "xray" and .listener_id == "entry-1" and .public_port == 24478) and
  (.core.protocols[2] | .core == "sing-box" and .listener_id == "entry-2" and .public_port == 24479)
' "${SPEC}" >/dev/null || fail 'Trojan 同核/跨核复制改变原始身份或 TLS'
before=$(snapshot)
for rejectedEdit in uuid domain core listener new-account new-anytls; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.trojan.domain = "next.example.com")' ;;
    core) filter='.core.protocols[0].core = "sing-box"' ;;
    listener) filter='.core.protocols[0].listener_id = "entry-renamed"' ;;
    new-account) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
      .public_port = 24480 | .uuid = "22222222-2222-4222-8222-222222222222"]' ;;
    new-anytls) filter='.core.protocols += [.core.protocols[0] | .listener_id = "entry-3" |
      .core = "sing-box" | .public_port = 24480 | .id = 4 | .anytls = {domain:.trojan.domain} | del(.trojan)]' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/trojan-rejected.json"
    chmod 0600 "${TEST_ROOT}/trojan-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/trojan-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/trojan-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: Trojan 编辑绕过身份边界"
    assertClean
done
runPty 0 trojan-delete-secondary $'10\nentry-2\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.secondary_type == null and .tls.domain == "trojan.example.com" and
  (.core.protocols | length) == 2' "${SPEC}" >/dev/null || fail '删除 Trojan 副核心丢失 TLS'
runPty 0 trojan-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "trojan.example.com" and (.core.protocols | length) == 1' "${SPEC}" >/dev/null ||
    fail '删除 Trojan 副本撤销仍需 TLS 的入口'

# 混合 WS 删除不影响 direct TLS；最后消费者删除仅撤销规格引用。
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-dual-trojan-xray"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-dual-trojan-xray"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq '.core.protocols += [
  (.core.protocols[1] | .core = "xray" | .listener_id = "entry-primary-reality" | .public_port = 24481), {
  id:21,core:"xray",listener_id:"vless-ws",server:"proxy.example.com",public_port:24444,
  address_families:["ipv4"],name:"main-ws",uuid:.core.protocols[0].uuid,
  websocket:{domain:.tls.domain,path:"abcdefghws",backend_port:31297,tls_port:8443}}] |
  .subscription.enabled = true' "${SPEC}" >"${TEST_ROOT}/trojan-with-ws.json"
chmod 0600 "${TEST_ROOT}/trojan-with-ws.json"
runPty 0 trojan-ws-configure '' configure --spec "${TEST_ROOT}/trojan-with-ws.json" "${ASSET_ARGS[@]}"
runPty 0 trojan-delete-ws $'10\nvless-ws\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "trojan.example.com" and .subscription.enabled == false and
  any(.core.protocols[]; .id == 28)' "${SPEC}" >/dev/null || fail '删除 WS 丢失 Trojan TLS'
runPty 0 trojan-delete-last-tls $'10\nentry-trojan\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls == null and .subscription.enabled == false and .core.type == "xray" and
  .core.secondary_type == "sing-box" and (.core.protocols | length) == 2 and
  all(.core.protocols[]; .id == 1)' \
    "${SPEC}" >/dev/null || fail '删除最后 Trojan TLS 消费者未清理规格引用或核心归属'
[[ -f "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/trojan.example.com.key" ]] ||
    fail '删除 Trojan 错误删除受管证书'
for trojanFailure in tls-fail health-fail; do
    newState "trojan-${trojanFailure}"
    export FAKE_SETUP_MODE="${trojanFailure}"
    if [[ "${trojanFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
    runPty "${expected}" "trojan-${trojanFailure}" "${TROJAN_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
done
export FAKE_SETUP_MODE=ok

# VMess WS TLS 复用现有 WS 事务，aid 固定为零，单入口不开放 HTTPS 发布。
printf -v VMESS_INPUT '1\n12\nproxy.example.com\n3\nvmess.example.com\n24481\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
printf -v DUAL_VMESS_INPUT '3\n12\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nvmess.example.com\n24481\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for vmessCase in vmess-single vmess-dual; do
    newState "${vmessCase}"
    input=${VMESS_INPUT}; single=true
    if [[ "${vmessCase}" == vmess-dual ]]; then input=${DUAL_VMESS_INPUT}; single=false; fi
    before=$(snapshot)
    runPty 0 "${vmessCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${vmessCase}: 取消首配提前生成凭据或写入部署"
    runPty 0 "${vmessCase}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --argjson single "${single}" '
      .schema_version == 3 and .core.type == "xray" and .tls.domain == "vmess.example.com" and
      .subscription.enabled == false and
      (.core.protocols[0] | .id == 22 and .core == "xray" and .public_port == 24481 and
        .address_families == ["ipv4","ipv6"] and .server == "proxy.example.com" and
        .uuid == "11111111-1111-4111-8111-111111111111" and
        (.websocket | .domain == "vmess.example.com" and .backend_port == 31297 and .tls_port == 8443)) and
      if $single then .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == "sing-box" and (.core.protocols | length) == 2 and
        .core.protocols[1].id == 1 and .core.protocols[1].public_port == 24445 end
    ' "${SPEC}" >/dev/null || fail "${vmessCase}: VMess 首配规格错误"
    jq -e --slurpfile spec "${SPEC}" '$spec[0].core.protocols[0] as $p |
      any(.inbounds[]; .protocol == "vmess" and .tag == $p.listener_id and
        .settings.clients == [{id:$p.uuid,email:$p.uuid,alterId:0}] and
        .port == $p.websocket.backend_port and .streamSettings == {
          network:"ws",security:"none",wsSettings:{path:("/"+$p.websocket.path+"ws")}})' \
        "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" >/dev/null ||
        fail "${vmessCase}: VMess 认证、aid 或 WS 配置错误"
    jq -e '.services.xray.ports == [] and .services.nginx.ports ==
      ["0.0.0.0:24481:8443/tcp","[::]:24481:8443/tcp"] and
      (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${vmessCase}: VMess Nginx 双栈或发布拓扑错误"
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail 'VMess 单核生成无用 Reality 密钥'
    fi
done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-vmess-single"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-vmess-single"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
VMESS_LISTENER=$(jq -r '.core.protocols[0].listener_id' "${SPEC}")
cp -- "${SPEC}" "${TEST_ROOT}/vmess-original.json"
before=$(snapshot)
runPty 0 vmess-edit-cancel $'1\n22\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'VMess 取消编辑改变部署'
runPty 0 vmess-edit $'1\n22\n24482\n2\n22\nnext.example.com\n3\n22\n2\n4\n22\nnext-vmess\n6\n22\nnewvmesspath\n8\ny\n' \
    edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/vmess-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | .uuid == $before[0].core.protocols[0].uuid and
    .listener_id == $before[0].core.protocols[0].listener_id and
    .public_port == 24482 and .server == "next.example.com" and
    .address_families == ["ipv6"] and .name == "next-vmess" and
    .websocket == {domain:"vmess.example.com",path:"newvmesspath",backend_port:31297,tls_port:8443})' \
    "${SPEC}" >/dev/null || fail 'VMess 编辑改写 TLS 或账号/内部端口身份'
runPty 0 vmess-copy-xray $'9\n22\n1\n24483\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $source | (.core.protocols | length) == 2 and
  (.core.protocols[1] | .id == 22 and .core == "xray" and .listener_id == "entry-1" and
    .public_port == 24483 and .uuid == $source.uuid and .name == $source.name and
    .websocket == {domain:"vmess.example.com",path:"newvmesspath",backend_port:31298,tls_port:8444})' \
    "${SPEC}" >/dev/null || fail 'VMess 复制丢失身份或内部端口隔离'
before=$(snapshot)
printf -v input '9\n%s\n2\n24484\n' "${VMESS_LISTENER}"
runPty 15 vmess-copy-sing "${input}" edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'VMess 错误复制到 sing-box'
for rejectedEdit in uuid domain backend tls-port core aid; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.websocket.domain = "next.example.com")' ;;
    backend) filter='.core.protocols[0].websocket.backend_port = 31300' ;;
    tls-port) filter='.core.protocols[0].websocket.tls_port = 8445' ;;
    core) filter='.core.protocols[0].core = "sing-box" | .core.secondary_type = "sing-box"' ;;
    aid) filter='.core.protocols[0].alterId = 1' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/vmess-rejected.json"
    chmod 0600 "${TEST_ROOT}/vmess-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/vmess-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/vmess-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: VMess 编辑绕过身份冻结"
    assertClean
done
runPty 0 vmess-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "vmess.example.com" and (.core.protocols | length) == 1' \
    "${SPEC}" >/dev/null || fail 'VMess 删除副本撤销 TLS'
runPty 15 vmess-enable-publish $'7\ny\n8\n' edit "${ASSET_ARGS[@]}"
for vmessFailure in tls-fail health-fail; do
    newState "vmess-${vmessFailure}"
    export FAKE_SETUP_MODE="${vmessFailure}"
    if [[ "${vmessFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
    runPty "${expected}" "vmess-${vmessFailure}" "${VMESS_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
done
export FAKE_SETUP_MODE=ok

# HTTPUpgrade 与 WS 共用受管 TLS，但入口路径及两核后端保持独立。
printf -v HTTPUPGRADE_INPUT '1\n13\nproxy.example.com\n3\nhttpupgrade.example.com\n24485\n2\n%s\n%s\ny\n' \
    "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
for httpupgradeCase in httpupgrade-xray httpupgrade-sing dual-httpupgrade-xray dual-httpupgrade-sing; do
    core=xray; coreChoice=1; single=true
    case "${httpupgradeCase}" in
    httpupgrade-sing) core=sing-box; coreChoice=2 ;;
    dual-httpupgrade-xray) coreChoice=3; single=false ;;
    dual-httpupgrade-sing) core=sing-box; coreChoice=4; single=false ;;
    esac
    if [[ "${single}" == true ]]; then
        printf -v input '%s\n13\nproxy.example.com\n3\nhttpupgrade.example.com\n24485\n2\n%s\n%s\ny\n' \
            "${coreChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
    else
        printf -v input '%s\n13\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nhttpupgrade.example.com\n24485\n2\n%s\n%s\ny\n' \
            "${coreChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
    fi
    newState "${httpupgradeCase}"
    before=$(snapshot)
    runPty 0 "${httpupgradeCase}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
        fail "${httpupgradeCase}: 取消首配提前生成凭据或写入部署"
    runPty 0 "${httpupgradeCase}" "${input}" setup "${ASSET_ARGS[@]}"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    jq -e --arg core "${core}" --argjson single "${single}" '
      .schema_version == 3 and .core.type == $core and .tls.domain == "httpupgrade.example.com" and
      .subscription.enabled == false and
      (.core.protocols[0] | .id == 23 and .core == $core and .listener_id == "entry-vmess-httpupgrade" and
        .name == "main-vmess-httpupgrade" and .public_port == 24485 and
        .address_families == ["ipv4","ipv6"] and .server == "proxy.example.com" and
        .uuid == "11111111-1111-4111-8111-111111111111" and
        (.httpupgrade | .domain == "httpupgrade.example.com" and .backend_port == 31306 and .tls_port == 8443)) and
      if $single then .core.secondary_type == null and (.core.protocols | length) == 1
      else .core.secondary_type == (if $core == "xray" then "sing-box" else "xray" end) and
        (.core.protocols | length) == 2 and .core.protocols[1].id == 1 and
        .core.protocols[1].public_port == 24445 and .core.protocols[0].uuid == .core.protocols[1].uuid end
    ' "${SPEC}" >/dev/null || fail "${httpupgradeCase}: HTTPUpgrade 首配规格错误"
    jq -e --arg core "${core}" --slurpfile spec "${SPEC}" '
      $spec[0].core.protocols[0] as $p |
      if $core == "xray" then any(.inbounds[]; .tag == $p.listener_id and .protocol == "vmess" and
        .settings.clients == [{id:$p.uuid,email:$p.uuid,alterId:0}] and .port == $p.httpupgrade.backend_port and
        .streamSettings == {network:"httpupgrade",security:"none",
          httpupgradeSettings:{path:("/"+$p.httpupgrade.path),host:$p.httpupgrade.domain}})
      else any(.inbounds[]; .tag == $p.listener_id and .type == "vmess" and
        .users == [{uuid:$p.uuid,name:$p.uuid,alterId:0}] and .listen_port == $p.httpupgrade.backend_port and
        .transport == {type:"httpupgrade",path:("/"+$p.httpupgrade.path),host:$p.httpupgrade.domain}) end
    ' "${PADM_DOCKER_INSTALL_DIR}/config/${core}/config.json" >/dev/null ||
        fail "${httpupgradeCase}: HTTPUpgrade 认证、host 或路径错误"
    jq -e --arg core "${core}" '.services[$core].ports == [] and
      .services.nginx.ports == ["0.0.0.0:24485:8443/tcp","[::]:24485:8443/tcp"] and
      (.services.nginx.depends_on | keys) == [$core] and (.services | has("subscription") | not)' \
        "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
        fail "${httpupgradeCase}: HTTPUpgrade Nginx 双栈或 upstream 依赖错误"
    if [[ "${single}" == true ]]; then
        ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail 'HTTPUpgrade 单核生成无用 Reality 密钥'
    fi
    assertClean
    assertNoSecrets
done
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-httpupgrade-xray"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-httpupgrade-xray"
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
cp -- "${SPEC}" "${TEST_ROOT}/httpupgrade-original.json"
before=$(snapshot)
runPty 0 httpupgrade-edit-cancel $'1\n23\n0\n' edit "${ASSET_ARGS[@]}"
[[ "$(snapshot)" == "${before}" ]] || fail 'HTTPUpgrade 取消编辑改变部署'
runPty 0 httpupgrade-edit $'1\n23\n24486\n2\n23\nnext.example.com\n3\n23\n2\n4\n23\nnext-httpupgrade\n6\n23\nnewupgradepath\n8\ny\n' \
    edit "${ASSET_ARGS[@]}"
jq -e --slurpfile before "${TEST_ROOT}/httpupgrade-original.json" '
  .tls == $before[0].tls and .subscription == $before[0].subscription and
  (.core.protocols[0] | .uuid == $before[0].core.protocols[0].uuid and .listener_id == "entry-vmess-httpupgrade" and
    .public_port == 24486 and .server == "next.example.com" and .address_families == ["ipv6"] and
    .name == "next-httpupgrade" and
    .httpupgrade == {domain:"httpupgrade.example.com",path:"newupgradepath",backend_port:31306,tls_port:8443})' \
    "${SPEC}" >/dev/null || fail 'HTTPUpgrade 编辑改写 TLS 或账号/内部端口身份'
runPty 0 httpupgrade-copy-xray $'9\n23\n1\n24487\n8\ny\n' edit "${ASSET_ARGS[@]}"
runPty 0 httpupgrade-copy-sing $'9\nentry-vmess-httpupgrade\n2\n24488\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.protocols[0] as $source | .core.secondary_type == "sing-box" and
  (.core.protocols | length) == 3 and
  all(.core.protocols[1:][]; .id == 23 and .uuid == $source.uuid and
    .httpupgrade.domain == $source.httpupgrade.domain and .httpupgrade.path == $source.httpupgrade.path and
    .name == $source.name and .server == $source.server and .address_families == $source.address_families) and
  (.core.protocols[1] | .core == "xray" and .listener_id == "entry-1" and .public_port == 24487 and
    .httpupgrade.backend_port == 31307 and .httpupgrade.tls_port == 8444) and
  (.core.protocols[2] | .core == "sing-box" and .listener_id == "entry-2" and .public_port == 24488 and
    .httpupgrade.backend_port == 31306 and .httpupgrade.tls_port == 8445)' \
    "${SPEC}" >/dev/null || fail 'HTTPUpgrade 同核/跨核复制丢失身份或端口隔离'
before=$(snapshot)
for rejectedEdit in uuid domain backend tls-port core aid id; do
    case "${rejectedEdit}" in
    uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
    domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.httpupgrade.domain = "next.example.com")' ;;
    backend) filter='.core.protocols[0].httpupgrade.backend_port = 31308' ;;
    tls-port) filter='.core.protocols[0].httpupgrade.tls_port = 8446' ;;
    core) filter='.core.protocols[0].core = "sing-box"' ;;
    aid) filter='.core.protocols[0].alterId = 1' ;;
    id) filter='.core.protocols[0] |= (.id = 22 | .websocket = .httpupgrade | del(.httpupgrade))' ;;
    esac
    jq "${filter}" "${SPEC}" >"${TEST_ROOT}/httpupgrade-rejected.json"
    chmod 0600 "${TEST_ROOT}/httpupgrade-rejected.json"
    CONTROL_LOG="${TEST_ROOT}/httpupgrade-rejected-${rejectedEdit}.log"
    actual=0
    bash -u "${CLI}" edit --spec "${TEST_ROOT}/httpupgrade-rejected.json" --preview "${ASSET_ARGS[@]}" \
        >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] ||
        fail "${rejectedEdit}: HTTPUpgrade 编辑绕过身份冻结"
    assertClean
done
runPty 0 httpupgrade-delete-secondary $'10\nentry-2\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.core.secondary_type == null and .tls.domain == "httpupgrade.example.com" and
  (.core.protocols | length) == 2' "${SPEC}" >/dev/null || fail '删除 HTTPUpgrade 副核心丢失 TLS'
runPty 0 httpupgrade-delete-copy $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
jq -e '.tls.domain == "httpupgrade.example.com" and (.core.protocols | length) == 1' \
    "${SPEC}" >/dev/null || fail 'HTTPUpgrade 删除副本撤销 TLS'
runPty 15 httpupgrade-enable-publish $'7\ny\n8\n' edit "${ASSET_ARGS[@]}"
for httpupgradeFailure in tls-fail health-fail; do
    newState "httpupgrade-${httpupgradeFailure}"
    export FAKE_SETUP_MODE="${httpupgradeFailure}"
    if [[ "${httpupgradeFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
    runPty "${expected}" "httpupgrade-${httpupgradeFailure}" "${HTTPUPGRADE_INPUT}" setup "${ASSET_ARGS[@]}"
    assertUnconfigured
done
export FAKE_SETUP_MODE=ok
fi

if [[ "${SECTION}" == all || "${SECTION}" == tls ]]; then
# 两类 Xray gRPC TLS 复用首配事务，不生成无用 Reality 凭据。
for grpcProtocol in 24 25; do
    grpcChoice=14; backend=31301; scheme=vless; listener=entry-vless-grpc-tls
    [[ "${grpcProtocol}" != 25 ]] || { grpcChoice=15; backend=31304; scheme=trojan; listener=entry-trojan-grpc-tls; }
    printf -v grpcInput '1\n%s\nproxy.example.com\n3\ngrpc.example.com\n24491\n2\n%s\n%s\ny\n' \
        "${grpcChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
    for grpcTopology in single dual; do
        newState "grpc-tls-${grpcProtocol}-${grpcTopology}"
        input=${grpcInput}; single=true
        if [[ "${grpcTopology}" == dual ]]; then
            single=false
            printf -v input '3\n%s\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\ngrpc.example.com\n24491\n2\n%s\n%s\ny\n' \
                "${grpcChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
        fi
        before=$(snapshot)
        runPty 0 "grpc-tls-${grpcProtocol}-${grpcTopology}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
        [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
            fail "${grpcProtocol}/${grpcTopology}: 取消 gRPC TLS 首配改变状态或生成秘密"
        runPty 0 "grpc-tls-${grpcProtocol}-${grpcTopology}" "${input}" setup "${ASSET_ARGS[@]}"
        SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        jq -e --argjson protocol "${grpcProtocol}" --argjson backend "${backend}" \
            --arg listener "${listener}" --arg scheme "${scheme}" --argjson single "${single}" '
          .schema_version == 3 and .core.type == "xray" and .tls.domain == "grpc.example.com" and
          .subscription.enabled == false and
          (.core.protocols[0] | .id == $protocol and .core == "xray" and .listener_id == $listener and
            .name == "main-"+$scheme+"-grpc-tls" and .server == "proxy.example.com" and .public_port == 24491 and
            .address_families == ["ipv4","ipv6"] and .uuid == "11111111-1111-4111-8111-111111111111" and
            (.grpc_tls | .domain == "grpc.example.com" and .backend_port == $backend and .tls_port == 8443 and
              (.service_name | test("^[a-f0-9]{16}$")))) and
          if $single then .core.secondary_type == null and (.core.protocols | length) == 1
          else .core.secondary_type == "sing-box" and (.core.protocols | length) == 2 and
            .core.protocols[1].id == 1 and .core.protocols[1].public_port == 24445 and
            .core.protocols[0].uuid == .core.protocols[1].uuid end
        ' "${SPEC}" >/dev/null || fail "${grpcProtocol}/${grpcTopology}: gRPC TLS 首配规格错误"
        jq -e --arg scheme "${scheme}" --slurpfile spec "${SPEC}" '
          $spec[0].core.protocols[0] as $p |
          any(.inbounds[]; .tag == $p.listener_id and .protocol == $scheme and .port == $p.grpc_tls.backend_port and
            .settings == (if $scheme == "vless" then {decryption:"none",clients:[{id:$p.uuid,email:$p.uuid}]}
              else {clients:[{password:$p.uuid,email:$p.uuid}]} end) and .streamSettings == {
              network:"grpc",security:"none",grpcSettings:{serviceName:$p.grpc_tls.service_name}})' \
            "${PADM_DOCKER_INSTALL_DIR}/config/xray/config.json" >/dev/null ||
            fail "${grpcProtocol}/${grpcTopology}: gRPC TLS 认证或 serviceName 错误"
        jq -e '.services.xray.ports == [] and .services.nginx.ports ==
          ["0.0.0.0:24491:8443/tcp","[::]:24491:8443/tcp"] and
          .services.nginx.depends_on == {xray:{condition:"service_healthy"}} and
          (.services | has("subscription") | not)' "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
            fail "${grpcProtocol}/${grpcTopology}: gRPC TLS 双栈或 Nginx 依赖错误"
        if [[ "${single}" == true ]]; then
            ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail '单核 gRPC TLS 生成无用 Reality 密钥'
        fi
        assertClean
        assertNoSecrets
    done
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-grpc-tls-${grpcProtocol}-single"
    export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-grpc-tls-${grpcProtocol}-single"
    CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    cp -- "${SPEC}" "${TEST_ROOT}/grpc-tls-original.json"
    before=$(snapshot)
    printf -v input '1\n%s\n0\n' "${grpcProtocol}"
    runPty 0 "grpc-tls-${grpcProtocol}-edit-cancel" "${input}" edit "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" ]] || fail "${grpcProtocol}: 取消 gRPC TLS 编辑改变部署"
    printf -v input '1\n%s\n24492\n2\n%s\nnext.example.com\n3\n%s\n2\n4\n%s\nnext-grpc\n12\n%s\ncustom_grpc-1\n8\ny\n' \
        "${grpcProtocol}" "${grpcProtocol}" "${grpcProtocol}" "${grpcProtocol}" "${grpcProtocol}"
    runPty 0 "grpc-tls-${grpcProtocol}-edit" "${input}" edit "${ASSET_ARGS[@]}"
    jq -e --argjson backend "${backend}" --slurpfile before "${TEST_ROOT}/grpc-tls-original.json" '
      .tls == $before[0].tls and .subscription == $before[0].subscription and
      (.core.protocols[0] | .uuid == $before[0].core.protocols[0].uuid and
        .listener_id == $before[0].core.protocols[0].listener_id and .public_port == 24492 and
        .server == "next.example.com" and .address_families == ["ipv6"] and .name == "next-grpc" and
        .grpc_tls == {domain:"grpc.example.com",service_name:"custom_grpc-1",backend_port:$backend,tls_port:8443})' \
        "${SPEC}" >/dev/null || fail "${grpcProtocol}: gRPC TLS 编辑改写固定身份或未编辑服务名"
    printf -v input '9\n%s\n1\n24493\n8\ny\n' "${grpcProtocol}"
    runPty 0 "grpc-tls-${grpcProtocol}-copy" "${input}" edit "${ASSET_ARGS[@]}"
    jq -e --argjson backend "${backend}" '.core.protocols[0] as $p |
      (.core.protocols | length) == 2 and .core.secondary_type == null and
      (.core.protocols[1] | .id == $p.id and .core == "xray" and .listener_id == "entry-1" and .public_port == 24493 and
        .uuid == $p.uuid and .name == $p.name and .grpc_tls ==
        ($p.grpc_tls + {backend_port:($backend+1),tls_port:8444}))' "${SPEC}" >/dev/null ||
        fail "${grpcProtocol}: gRPC TLS 复制丢失身份或内部端口隔离"
    before=$(snapshot)
    printf -v input '9\n%s\n2\n24494\n' "${listener}"
    runPty 15 "grpc-tls-${grpcProtocol}-copy-sing" "${input}" edit "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" ]] || fail "${grpcProtocol}: gRPC TLS 被复制到 sing-box"
    for rejectedEdit in uuid domain backend tls-port core id new-protocol; do
        case "${rejectedEdit}" in
        uuid) filter='.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' ;;
        domain) filter='.tls.domain = "next.example.com" | .core.protocols |= map(.grpc_tls.domain = "next.example.com")' ;;
        backend) filter='.core.protocols[0].grpc_tls.backend_port = 31309' ;;
        tls-port) filter='.core.protocols[0].grpc_tls.tls_port = 8445' ;;
        core) filter='.core.protocols[0].core = "sing-box" | .core.secondary_type = "sing-box"' ;;
        id) filter='.core.protocols[0].id = (if .core.protocols[0].id == 24 then 25 else 24 end)' ;;
        new-protocol) filter='.core.protocols += [.core.protocols[0] |
          .id = (if .id == 24 then 25 else 24 end) | .listener_id = "entry-new-other" | .public_port = 24495 |
          .grpc_tls.backend_port = 31309 | .grpc_tls.tls_port = 8445]' ;;
        esac
        jq "${filter}" "${SPEC}" >"${TEST_ROOT}/grpc-tls-rejected.json"
        chmod 0600 "${TEST_ROOT}/grpc-tls-rejected.json"
        CONTROL_LOG="${TEST_ROOT}/grpc-tls-${grpcProtocol}-${rejectedEdit}.log"
        actual=0
        bash -u "${CLI}" edit --spec "${TEST_ROOT}/grpc-tls-rejected.json" --preview "${ASSET_ARGS[@]}" \
            >"${CONTROL_LOG}" 2>&1 || actual=$?
        [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] ||
            fail "${grpcProtocol}/${rejectedEdit}: gRPC TLS 编辑绕过身份冻结"
        assertClean
    done
    runPty 0 "grpc-tls-${grpcProtocol}-delete-copy" $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
    jq -e '.tls.domain == "grpc.example.com" and (.core.protocols | length) == 1' "${SPEC}" >/dev/null ||
        fail "${grpcProtocol}: 删除 gRPC TLS 副本撤销证书引用"
    runPty 15 "grpc-tls-${grpcProtocol}-enable-publish" $'7\ny\n8\n' edit "${ASSET_ARGS[@]}"
    for grpcFailure in tls-fail health-fail; do
        newState "grpc-tls-${grpcProtocol}-${grpcFailure}"
        export FAKE_SETUP_MODE="${grpcFailure}"
        if [[ "${grpcFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
        runPty "${expected}" "grpc-tls-${grpcProtocol}-${grpcFailure}" "${grpcInput}" setup "${ASSET_ARGS[@]}"
        assertUnconfigured
    done
    export FAKE_SETUP_MODE=ok
done
# 传统 TLS 首配仍走同一候选事务，fallback 后端不承担 TLS。
for fallbackProtocol in 27 29; do
    fallbackChoice=16; listener=entry-vless-tls-vision
    [[ "${fallbackProtocol}" != 29 ]] || { fallbackChoice=17; listener=entry-trojan-tls-fallback; }
    printf -v fallbackInput '1\n%s\nproxy.example.com\n3\nfallback.example.com\n24501\n2\n%s\n%s\ny\n' \
        "${fallbackChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
    for fallbackTopology in single dual; do
        newState "fallback-${fallbackProtocol}-${fallbackTopology}"
        input=${fallbackInput}; single=true
        if [[ "${fallbackTopology}" == dual ]]; then
            single=false
            printf -v input '3\n%s\nproxy.example.com\n3\n2\ntarget.example.com:443\ntarget.example.com\n24445\nfallback.example.com\n24501\n2\n%s\n%s\ny\n' \
                "${fallbackChoice}" "${TEST_ROOT}/cert.pem" "${TEST_ROOT}/key.pem"
        fi
        before=$(snapshot)
        runPty 0 "fallback-${fallbackProtocol}-${fallbackTopology}-cancel" "${input%$'y\n'}"$'n\n' setup "${ASSET_ARGS[@]}"
        [[ "$(snapshot)" == "${before}" && ! -s "${EVENTS}" && ! -s "${VERIFY_LOG}" ]] ||
            fail "${fallbackProtocol}/${fallbackTopology}: 取消传统 TLS 首配改变状态"
        runPty 0 "fallback-${fallbackProtocol}-${fallbackTopology}" "${input}" setup "${ASSET_ARGS[@]}"
        SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
        jq -e --argjson protocol "${fallbackProtocol}" --arg listener "${listener}" --argjson single "${single}" '
          .schema_version == 3 and .core.type == "xray" and .tls.domain == "fallback.example.com" and
          .subscription.enabled == false and
          (.core.protocols[0] | .id == $protocol and .core == "xray" and .listener_id == $listener and
            .server == "proxy.example.com" and .public_port == 24501 and
            .address_families == ["ipv4","ipv6"] and .uuid == "11111111-1111-4111-8111-111111111111" and
            .fallback_tls == {domain:"fallback.example.com",http_port:31300,http2_port:31302}) and
          if $single then .core.secondary_type == null and (.core.protocols | length) == 1
          else .core.secondary_type == "sing-box" and (.core.protocols | length) == 2 and
            .core.protocols[1].id == 1 and .core.protocols[1].public_port == 24445 and
            .core.protocols[0].uuid == .core.protocols[1].uuid end
        ' "${SPEC}" >/dev/null || fail "${fallbackProtocol}/${fallbackTopology}: 传统 TLS 首配规格错误"
        jq -e '.services.xray.ports == ["0.0.0.0:24501:24501/tcp","[::]:24501:24501/tcp"] and
          (.services.xray.depends_on // {}) == {} and (.services.nginx.depends_on // {}) == {} and
          .services.nginx.ports == [] and
          any(.services.xray.volumes[]; .target == "/etc/padm/secrets/tls" and .read_only) and
          all(.services.nginx.volumes[]; .target != "/etc/padm/secrets/tls")' \
            "${PADM_DOCKER_INSTALL_DIR}/compose.json" >/dev/null ||
            fail "${fallbackProtocol}/${fallbackTopology}: TLS 终止或 fallback 依赖错误"
        if [[ "${single}" == true ]]; then
            ! grep -Eq ' x25519( |$)|derived-stdin' "${EVENTS}" || fail '单核传统 TLS 生成无用 Reality 密钥'
        fi
        assertClean
        assertNoSecrets
    done
    export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state-fallback-${fallbackProtocol}-single"
    export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/bin-fallback-${fallbackProtocol}-single"
    CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
    SPEC="${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
    cp -- "${SPEC}" "${TEST_ROOT}/fallback-original.json"
    before=$(snapshot)
    printf -v input '1\n%s\n0\n' "${fallbackProtocol}"
    runPty 0 "fallback-${fallbackProtocol}-edit-cancel" "${input}" edit "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" ]] || fail "${fallbackProtocol}: 取消编辑改变部署"
    printf -v input '1\n%s\n24502\n2\n%s\nnext.example.com\n3\n%s\n2\n4\n%s\nnext-fallback\n9\n%s\n1\n24503\n8\ny\n' \
        "${fallbackProtocol}" "${fallbackProtocol}" "${fallbackProtocol}" "${fallbackProtocol}" "${fallbackProtocol}"
    runPty 0 "fallback-${fallbackProtocol}-edit-copy" "${input}" edit "${ASSET_ARGS[@]}"
    jq -e --slurpfile before "${TEST_ROOT}/fallback-original.json" '
      .core.secondary_type == null and .tls == $before[0].tls and (.core.protocols | length) == 2 and
      (.core.protocols[0] | .public_port == 24502 and .server == "next.example.com" and
        .address_families == ["ipv6"] and .name == "next-fallback" and
        .uuid == $before[0].core.protocols[0].uuid and .fallback_tls == $before[0].core.protocols[0].fallback_tls) and
      (.core.protocols[1] | .listener_id == "entry-1" and .public_port == 24503 and
        .uuid == $before[0].core.protocols[0].uuid and .fallback_tls == $before[0].core.protocols[0].fallback_tls)
    ' "${SPEC}" >/dev/null || fail "${fallbackProtocol}: 编辑复制丢失身份或共享后端"
    before=$(snapshot)
    printf -v input '9\n%s\n2\n24504\n' "${listener}"
    runPty 15 "fallback-${fallbackProtocol}-copy-sing" "${input}" edit "${ASSET_ARGS[@]}"
    [[ "$(snapshot)" == "${before}" ]] || fail "${fallbackProtocol}: 复制接受 sing-box"
    for filter in \
        '.core.protocols[0].uuid = "22222222-2222-4222-8222-222222222222"' \
        '.tls.domain = "next.example.com" | .core.protocols |= map(.fallback_tls.domain = "next.example.com")' \
        '.core.protocols[0].fallback_tls.http_port = 31308' \
        '.core.protocols[0].fallback_tls.http2_port = 31309'; do
        jq "${filter}" "${SPEC}" >"${TEST_ROOT}/fallback-rejected.json"
        chmod 0600 "${TEST_ROOT}/fallback-rejected.json"
        CONTROL_LOG="${TEST_ROOT}/fallback-${fallbackProtocol}-rejected.log"
        actual=0
        bash -u "${CLI}" edit --spec "${TEST_ROOT}/fallback-rejected.json" --preview "${ASSET_ARGS[@]}" \
            >"${CONTROL_LOG}" 2>&1 || actual=$?
        [[ "${actual}" == 15 && "$(snapshot)" == "${before}" ]] || fail "${fallbackProtocol}: 编辑绕过固定身份"
        assertClean
    done
    runPty 0 "fallback-${fallbackProtocol}-delete-copy" $'10\nentry-1\n8\ny\n' edit "${ASSET_ARGS[@]}"
    jq -e '.tls.domain == "fallback.example.com" and (.core.protocols | length) == 1' "${SPEC}" >/dev/null ||
        fail "${fallbackProtocol}: 删除副本撤销 TLS"
    runPty 15 "fallback-${fallbackProtocol}-enable-publish" $'7\ny\n8\n' edit "${ASSET_ARGS[@]}"
    for fallbackFailure in tls-fail health-fail; do
        newState "fallback-${fallbackProtocol}-${fallbackFailure}"
        export FAKE_SETUP_MODE="${fallbackFailure}"
        if [[ "${fallbackFailure}" == tls-fail ]]; then expected=15; else expected=14; fi
        runPty "${expected}" "fallback-${fallbackProtocol}-${fallbackFailure}" "${fallbackInput}" setup "${ASSET_ARGS[@]}"
        assertUnconfigured
    done
    export FAKE_SETUP_MODE=ok
done
fi
printf 'docker-setup-regression-ok\n'
