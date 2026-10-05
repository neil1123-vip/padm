#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-menu.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
COMPOSE_LOG="${TEST_ROOT}/compose.log"
DOWNLOAD_MARKER="${TEST_ROOT}/download.called"
CONTROL_LOG=
mkdir -p "${MOCK_BIN}" "${TEST_ROOT}/native" "${TEST_ROOT}/systemd"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    if [[ -n "${CONTROL_LOG}" && -f "${CONTROL_LOG}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
    fi
    printf 'docker-menu-regression-fail: %s\n' "$*" >&2
    exit 1
}

command -v script >/dev/null 2>&1 || fail 'util-linux script is required for real PTY checks'
command -v timeout >/dev/null 2>&1 || fail 'timeout is required for bounded PTY checks'
bash "${PROJECT_ROOT}/docker/tests/menu-signals.sh"

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
cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
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
ps) ;;
compose)
    if [[ "${2:-}" == version ]]; then
        printf 'v2.29.1\n'
        exit 0
    fi
    printf '%s\n' "$*" >>"${FAKE_COMPOSE_LOG:?}"
    case " $* " in
    *' logs '*)
        if [[ "${FAKE_LOG_STREAM:-0}" == 1 ]]; then
            trap 'exit 130' INT
            trap 'exit 143' TERM
            printf '%s\n' "${BASHPID}" >"${FAKE_LOG_PID:?}"
            : >"${FAKE_LOG_READY:?}"
            printf 'mock-log-ready\n'
            while true; do sleep 1; done
        fi
        ;;
    *' restart '*)
        [[ "${FAKE_RESTART_FAIL:-0}" != 1 ]] || exit 1
        ;;
    esac
    ;;
*) exit 1 ;;
esac
EOF
cat >"${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
: >"${FAKE_DOWNLOAD_MARKER:?}"
exit 1
EOF
cp "${MOCK_BIN}/curl" "${MOCK_BIN}/wget"
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
chmod 0755 "${MOCK_BIN}/"*

export PATH="${MOCK_BIN}:${PATH}" MSYS=winsymlinks:sys SHELL
SHELL=$(command -v bash)
export DOCKER_HOST=
export PADM_NATIVE_INSTALL_DIR="${TEST_ROOT}/native"
export PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd"
export PADM_DOCKER_LOCK_TIMEOUT=1
export FAKE_DOCKER_LOG="${DOCKER_LOG}" FAKE_COMPOSE_LOG="${COMPOSE_LOG}"
export FAKE_DOWNLOAD_MARKER="${DOWNLOAD_MARKER}" FAKE_LOG_READY="${TEST_ROOT}/logs.ready"
export FAKE_LOG_PID="${TEST_ROOT}/logs.pid"

runNonTty() {
    local expected=$1 name=$2 entry=$3 actual=0
    shift 3
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    bash -u "${entry}" "$@" </dev/null >"${CONTROL_LOG}" 2>&1 || actual=$?
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
}

waitForText() {
    local pattern=$1 file=$2 count=${3:-1} attempt
    for ((attempt = 0; attempt < 1800; attempt++)); do
        if [[ -f "${file}" ]] && [[ "$(grep -Fc "${pattern}" "${file}" || true)" -ge "${count}" ]]; then
            return 0
        fi
        sleep 0.05
    done
    return 1
}

assertNoLock() {
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] ||
        fail 'menu retained the deployment lock'
}

runPty() {
    local name=$1 driver=$2 input=$3 entry=$4 actual=0 feederStatus=0 command pipe feeder
    local expected=0
    shift 4
    CONTROL_LOG="${TEST_ROOT}/${name}.log"
    pipe="${TEST_ROOT}/${name}.input"
    mkfifo "${pipe}"
    printf -v command '%q ' bash -u "${entry}" "$@"
    if [[ "${driver}" == term ]]; then
        printf -v command 'printf "%%s\\n" "$$" >%q; exec %s' "${TEST_ROOT}/menu.pid" "${command}"
        expected=143
    fi
    (
        exec 3>"${pipe}"
        if [[ "${driver}" != plain ]]; then
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" || exit 1
            # 等待输入时现场检查，避免只验证退出后的清理。
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 2
        fi
        if [[ "${driver}" == setup ]]; then
            printf '2\n' >&3
            waitForText '核心 [1=Xray, 2=sing-box, 3=Xray+sing-box, 4=sing-box+Xray, 0=取消]' "${CONTROL_LOG}" || exit 11
            printf '0\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 12
            printf '0\n' >&3
        elif [[ "${driver}" == tls ]]; then
            printf '8\n' >&3
            waitForText 'Docker 证书管理' "${CONTROL_LOG}" || exit 13
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 14
            if [[ "${input}" == eof ]]; then
                printf '2\n\ncertificate.pem\n' >&3
                waitForText '私钥文件' "${CONTROL_LOG}" || exit 15
                printf '\004' >&3
            elif [[ "${input}" == renewal-eof ]]; then
                printf '6\n\nadmin@example.com\ndns_cf\n' >&3
                waitForText 'DNS 凭据文件' "${CONTROL_LOG}" || exit 17
                printf '\004' >&3
            else
                printf '%s' "${input}" >&3
            fi
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 16
            printf '0\n' >&3
        elif [[ "${driver}" == logs || "${driver}" == term ]]; then
            printf '6\n' >&3
            waitForText 'mock-log-ready' "${CONTROL_LOG}" || exit 3
            # 跟随日志期间也允许独立状态与定时采集争取部署锁。
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 4
            if [[ "${driver}" == term ]]; then
                kill -TERM "$(<"${TEST_ROOT}/menu.pid")" || exit 9
                for ((attempt = 0; attempt < 100; attempt++)); do
                    kill -0 "$(<"${TEST_ROOT}/menu.pid")" 2>/dev/null || exit 0
                    sleep 0.05
                done
                exit 10
            fi
            timeout 60 bash -u "${entry}" status >"${TEST_ROOT}/logs-concurrent-status.log" 2>&1 || exit 5
            printf '\003' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 2 || exit 6
            [[ ! -e "${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" ]] || exit 7
            printf '1\n' >&3
            waitForText 'Docker 管理菜单' "${CONTROL_LOG}" 3 || exit 8
            printf '0\n' >&3
        elif [[ "${driver}" != plain && "${input}" == $'\004' ]]; then
            printf '\004' >&3
        elif [[ "${driver}" != plain ]]; then
            local menuCount=1 line
            while IFS= read -r line || [[ -n "${line}" ]]; do
                printf '%s\n' "${line}" >&3
                menuCount=$((menuCount + 1))
                [[ "${line}" != 0 ]] || break
                waitForText 'Docker 管理菜单' "${CONTROL_LOG}" "${menuCount}" || exit 8
            done <<<"${input}"
        else
            printf '%s' "${input}" >&3
        fi
    ) &
    feeder=$!
    timeout 120 script -q -e -E never -f -c "${command}" "${CONTROL_LOG}" \
        <"${pipe}" >"${TEST_ROOT}/${name}.stdout" 2>&1 || actual=$?
    wait "${feeder}" || feederStatus=$?
    [[ "${feederStatus}" -eq 0 ]] || fail "${name}: PTY driver failed at checkpoint ${feederStatus}"
    [[ "${actual}" -eq "${expected}" ]] || fail "${name}: expected rc=${expected}, got rc=${actual}"
    assertNoLock
    if [[ "${driver}" == logs || "${driver}" == term ]]; then
        ! kill -0 "$(<"${FAKE_LOG_PID}")" 2>/dev/null || fail "${name}: log process survived the menu action"
    fi
}

assertMenu() {
    grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'PTY did not enter the menu'
}

assertHelpOnly() {
    grep -Fq '用法:' "${CONTROL_LOG}" || fail 'non-TTY invocation did not show usage'
    ! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'non-TTY invocation entered the menu'
    [[ ! -e "${DOWNLOAD_MARKER}" ]] || fail 'help invocation attempted a module download'
    [[ ! -s "${DOCKER_LOG}" ]] || fail 'help invocation touched Docker'
    [[ ! -e "${PADM_DOCKER_INSTALL_DIR}" ]] || fail 'help invocation initialized deployment state'
}

# 单文件入口没有模块；帮助必须在下载和安装之前返回。
ISOLATED="${TEST_ROOT}/isolated"
mkdir -p "${ISOLATED}"
cp "${PROJECT_ROOT}/install-docker.sh" "${ISOLATED}/install-docker.sh"
export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/isolated-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/isolated-bin"
runNonTty 0 isolated-no-args "${ISOLATED}/install-docker.sh"
assertHelpOnly
runNonTty 2 isolated-explicit-menu "${ISOLATED}/install-docker.sh" menu
assertHelpOnly

SOURCE_ROOT="${TEST_ROOT}/source"
mkdir -p "${SOURCE_ROOT}/shell/core" "${SOURCE_ROOT}/docker"
cp "${PROJECT_ROOT}/install-docker.sh" "${SOURCE_ROOT}/install-docker.sh"
cp -R "${PROJECT_ROOT}/docker/lib" "${SOURCE_ROOT}/docker/lib"
cp -R "${PROJECT_ROOT}/docker/contracts" "${SOURCE_ROOT}/docker/contracts"
cp "${PROJECT_ROOT}/shell/core/deployment_mode.sh" "${SOURCE_ROOT}/shell/core/deployment_mode.sh"
cp "${PROJECT_ROOT}/shell/core/stats_grpc.sh" "${SOURCE_ROOT}/shell/core/stats_grpc.sh"
TEST_REF=1111111111111111111111111111111111111111

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/non-tty-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/non-tty-bin"
runNonTty 0 non-tty-install "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}"
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail 'non-TTY install did not initialize the state'
! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail 'non-TTY install entered the menu'
assertNoLock

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/no-menu-state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/no-menu-bin"
runPty install-no-menu plain $'\004' "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}" --no-menu
[[ -f "${PADM_DOCKER_INSTALL_DIR}/mode" ]] || fail '--no-menu install did not initialize the state'
! grep -Fq 'Docker 管理菜单' "${CONTROL_LOG}" || fail '--no-menu install entered the menu'

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/state"
export PADM_DOCKER_BIN_DIR="${TEST_ROOT}/usr-local-bin"
runPty install-auto-menu menu $'0\n' "${PROJECT_ROOT}/install-docker.sh" \
    install --source "${SOURCE_ROOT}" --ref "${TEST_REF}"
assertMenu
grep -Fq 'configured=no' "${CONTROL_LOG}" || fail 'menu homepage did not run status'
CLI="${PADM_DOCKER_BIN_DIR}/padm-docker"
[[ -L "${CLI}" ]] || fail 'installed CLI link is missing'

: >"${DOCKER_LOG}"
runNonTty 0 installed-no-args "${CLI}"
grep -Fq '用法:' "${CONTROL_LOG}" || fail 'installed non-TTY no-args did not show help'
[[ ! -s "${DOCKER_LOG}" ]] || fail 'installed non-TTY no-args touched Docker'
runNonTty 2 installed-explicit-menu "${CLI}" menu
grep -Fq '用法:' "${CONTROL_LOG}" || fail 'installed non-TTY menu did not show help'
[[ ! -s "${DOCKER_LOG}" ]] || fail 'installed non-TTY menu touched Docker'
assertNoLock

runPty installed-no-args-menu menu $'1\n1\n0\n' "${CLI}"
assertMenu
[[ "$(grep -Fc 'configured=no' "${CONTROL_LOG}")" -ge 3 ]] || fail 'repeated status did not complete'

snapshotBefore=$(find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${PADM_DOCKER_INSTALL_DIR}/backups" -type f -print)
runPty first-config-cancel setup '' "${CLI}" menu
grep -Fq 'Docker 首次配置' "${CONTROL_LOG}" || fail 'first-config action did not enter the wizard'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'cancelled first-config action wrote a deployment'
snapshotAfter=$(find "${PADM_DOCKER_INSTALL_DIR}/config" "${PADM_DOCKER_INSTALL_DIR}/data" \
    "${PADM_DOCKER_INSTALL_DIR}/secrets" "${PADM_DOCKER_INSTALL_DIR}/backups" -type f -print)
[[ "${snapshotBefore}" == "${snapshotAfter}" ]] || fail 'cancelled first-config action changed persistent files'

runPty tls-unconfigured menu $'8\n0\n' "${CLI}" menu
grep -Fq '请先使用首次配置' "${CONTROL_LOG}" || fail 'unconfigured TLS action did not direct the user to first configuration'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'unconfigured TLS action wrote a deployment'

# 隔离业务命令，只用真实 PTY 检查生产证书向导的确认门禁与参数分发。
TLS_WIZARD_ROOT="${TEST_ROOT}/tls-wizard"
TLS_WIZARD_CLI="${TEST_ROOT}/tls-wizard-cli.sh"
TLS_WIZARD_ACTIONS="${TEST_ROOT}/tls-wizard.actions"
mkdir -p "${TLS_WIZARD_ROOT}/config"
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
printf '{}\n' >"${TLS_WIZARD_ROOT}/deployment.json"
printf 'PADM_OPS_IMAGE=fixture\n' >"${TLS_WIZARD_ROOT}/images.env"
export TLS_WIZARD_ROOT TLS_WIZARD_CLI TLS_WIZARD_ACTIONS PROJECT_ROOT
cat >"${TLS_WIZARD_CLI}" <<'EOF'
#!/usr/bin/env bash
set -u
source "${PROJECT_ROOT}/docker/lib/setup.sh"
dockerError() { printf '%s\n' "$*" >&2; }
dockerInstallRoot() { printf '%s\n' "${TLS_WIZARD_ROOT}"; }
dockerDomainIsValid() { [[ "$1" == ws.example.com || "$1" == other.example.com ]]; }
dockerEmailIsValid() { [[ "$1" == admin@example.com ]]; }
dockerConfigureSpecValidate() { return 0; }
dockerManagedSpecMatchesDeployment() { return 0; }
dockerResolveOpsImage() { printf 'fixture\n'; }
recordAction() {
    printf '%s' "$1" >>"${TLS_WIZARD_ACTIONS}"
    shift
    printf ' %s' "$@" >>"${TLS_WIZARD_ACTIONS}"
    printf '\n' >>"${TLS_WIZARD_ACTIONS}"
}
dockerTlsValidateCommand() { recordAction validate "$@"; }
dockerTlsInstallCommand() { recordAction install "$@"; }
dockerAcmeCommand() { recordAction acme "$@"; }
dockerRenewalCommand() { recordAction schedule "$@"; }
PADM_DOCKER_RC_STATE=15
PADM_DOCKER_RC_USAGE=2
case "${1:-}" in
status) exit 0 ;;
tls) [[ "${2:-}" == manage ]] || exit 2; dockerTlsManageCommand ;;
menu)
    source "${PROJECT_ROOT}/docker/lib/menu.sh"
    dockerMenuCli() { printf '%s\n' "${TLS_WIZARD_CLI}"; }
    dockerMenu
    ;;
esac
EOF
printf '{"tls":null}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
: >"${TLS_WIZARD_ACTIONS}"
runPty tls-no-domain menu $'8\n0\n' "${TLS_WIZARD_CLI}" menu
grep -Fq '当前部署没有 TLS 域名' "${CONTROL_LOG}" || fail 'TLS menu accepted a deployment without a TLS domain'
[[ ! -s "${TLS_WIZARD_ACTIONS}" ]] || fail 'missing TLS domain reached a business command'
printf '{"tls":{"domain":"ws.example.com"}}\n' >"${TLS_WIZARD_ROOT}/config/spec.json"
for tlsCase in cancel final-no eof validate install issue renew \
    renewal-status renewal-enable renewal-disable renewal-final-no renewal-eof; do
    : >"${TLS_WIZARD_ACTIONS}"
    expectedAction=
    case "${tlsCase}" in
    cancel) input=$'0\n' ;;
    final-no) input=$'3\n\nadmin@example.com\ndns_cf\ncredentials.env\nn\n' ;;
    eof) input=eof ;;
    validate) input=$'1\n\ny\n'; expectedAction='validate --domain ws.example.com' ;;
    install)
        input=$'2\nother.example.com\ncertificate.pem\nprivate-key.pem\ny\n'
        expectedAction='install --domain other.example.com --cert certificate.pem --key private-key.pem'
        ;;
    issue|renew)
        if [[ "${tlsCase}" == issue ]]; then choice=3; else choice=4; fi
        printf -v input '%s\n\nadmin@example.com\ndns_cf\ncredentials.env\ny\n' "${choice}"
        expectedAction="acme ${tlsCase} --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env"
        ;;
    renewal-status) input=$'5\n\ny\n'; expectedAction='schedule status' ;;
    renewal-enable)
        input=$'6\n\nadmin@example.com\ndns_cf\ncredentials.env\ny\n'
        expectedAction='schedule enable --domain ws.example.com --email admin@example.com --dns dns_cf --credentials credentials.env'
        ;;
    renewal-disable) input=$'7\n\ny\n'; expectedAction='schedule disable --domain ws.example.com' ;;
    renewal-final-no) input=$'6\n\nadmin@example.com\ndns_cf\ncredentials.env\nn\n' ;;
    renewal-eof) input=renewal-eof ;;
    esac
    runPty "tls-${tlsCase}" tls "${input}" "${TLS_WIZARD_CLI}" menu
    [[ "$(<"${TLS_WIZARD_ACTIONS}")" == "${expectedAction}" ]] ||
        fail "TLS ${tlsCase} bypassed confirmation or dispatched incorrect arguments"
done

# 最小已配置夹具只覆盖调度和命令分发，不宣称真实容器可用。
cat >"${PADM_DOCKER_INSTALL_DIR}/deployment.json" <<'EOF'
{
  "schema_version": 1,
  "mode": "docker",
  "padm_version": "test",
  "core": {"type": "xray"},
  "compose": {"project": "padm-docker", "profiles": ["core-xray"]}
}
EOF
cat >"${PADM_DOCKER_INSTALL_DIR}/images.env" <<EOF
PADM_XRAY_IMAGE=ghcr.io/example/padm-xray:test@sha256:$(printf '1%.0s' {1..64})
PADM_DOCKER_ROOT=${PADM_DOCKER_INSTALL_DIR}
EOF
printf '{"name":"padm-docker","services":{}}\n' >"${PADM_DOCKER_INSTALL_DIR}/compose.json"

: >"${COMPOSE_LOG}"
runPty repeated-status-restart menu $'1\n1\n5\n1\n0\n' "${CLI}" menu
[[ "$(grep -Ec ' ps$' "${COMPOSE_LOG}")" -ge 4 ]] || fail 'repeated configured status did not complete'
[[ "$(grep -Ec ' restart$' "${COMPOSE_LOG}")" -eq 1 ]] || fail 'restart was not dispatched exactly once'

: >"${COMPOSE_LOG}"
runPty up-down menu $'3\n4\n0\n' "${CLI}" menu
grep -Eq ' up -d --remove-orphans$' "${COMPOSE_LOG}" || fail 'menu up was not dispatched'
grep -Eq ' down --remove-orphans$' "${COMPOSE_LOG}" || fail 'menu down was not dispatched'

export FAKE_RESTART_FAIL=1
runPty invalid-and-failed menu $'invalid\n5\n1\n0\n' "${CLI}" menu
grep -Fq '无效' "${CONTROL_LOG}" || fail 'invalid choice was not reported'
grep -Fq 'Docker Compose 操作失败' "${CONTROL_LOG}" || fail 'operation failure was not reported'
[[ "$(grep -Fc 'Docker 管理菜单' "${CONTROL_LOG}")" -ge 4 ]] || fail 'failed operation did not remain in the menu'
unset FAKE_RESTART_FAIL

runPty menu-eof menu $'\004' "${CLI}" menu
assertMenu

: >"${COMPOSE_LOG}"
export FAKE_LOG_STREAM=1
runPty logs-interrupt logs '' "${CLI}" menu
grep -Eq ' logs --tail 100 --follow$' "${COMPOSE_LOG}" || fail 'menu logs did not forward bounded follow arguments'
[[ "$(grep -Ec ' ps$' "${COMPOSE_LOG}")" -ge 3 ]] || fail 'status did not work during and after interrupting logs'
grep -Fq 'configured=yes' "${TEST_ROOT}/logs-concurrent-status.log" ||
    fail 'status could not run while logs followed'
unset FAKE_LOG_STREAM

export FAKE_LOG_STREAM=1
runPty parent-term term '' "${CLI}" menu
unset FAKE_LOG_STREAM

printf 'docker-menu-regression-ok\n'
