#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase1.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
CONTROL_LOG="${TEST_ROOT}/control.log"
DOCKER_CALL_LOG="${TEST_ROOT}/docker.log"
mkdir -p "${MOCK_BIN}"
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    printf 'docker-phase1-regression-fail: %s\n' "$*" >&2
    exit 1
}

cat >"${MOCK_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
-s) printf 'Linux\n' ;;
-m) printf '%s\n' "${FAKE_UNAME_ARCH:-x86_64}" ;;
*) printf 'Linux\n' ;;
esac
EOF

cat >"${MOCK_BIN}/id" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-u" ]] && printf '0\n'
EOF

cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
mode=${FAKE_DOCKER_MODE:-ok}
case "${1:-}" in
info)
    [[ "${mode}" != "daemon-fail" ]] || exit 1
    if [[ "${2:-}" == "--format" ]]; then
        case "${3:-}" in
        '{{.OSType}}') printf 'linux\n' ;;
        '{{.Architecture}}') printf '%s\n' "${FAKE_DAEMON_ARCH:-x86_64}" ;;
        '{{json .SecurityOptions}}')
            if [[ "${mode}" == "rootless" ]]; then
                printf '["name=rootless"]\n'
            else
                printf '["name=seccomp,profile=builtin"]\n'
            fi
            ;;
        *) exit 1 ;;
        esac
    fi
    ;;
context)
    [[ "${2:-}" == "inspect" ]] || exit 1
    printf '%s\n' "${FAKE_DOCKER_ENDPOINT:-unix:///var/run/docker.sock}"
    ;;
compose)
    if [[ "${2:-}" == "version" ]]; then
        printf '%s\n' "${FAKE_COMPOSE_VERSION:-v2.29.1}"
        exit 0
    fi
    printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
    [[ "${mode}" != "compose-fail" ]]
    ;;
ps)
    [[ "${mode}" != "active" ]] || printf 'container-id\n'
    ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/uname" "${MOCK_BIN}/id" "${MOCK_BIN}/docker"

export FAKE_DOCKER_LOG="${DOCKER_CALL_LOG}"

runControl() {
    local expected=$1 name=$2 dockerRoot=$3 nativeRoot=$4 binDir=$5
    local actual=0
    shift 5
    : >"${CONTROL_LOG}"
    env \
        MSYS=winsymlinks:sys \
        PATH="${MOCK_BIN}:${PATH}" \
        DOCKER_HOST= \
        PADM_DOCKER_INSTALL_DIR="${dockerRoot}" \
        PADM_NATIVE_INSTALL_DIR="${nativeRoot}" \
        PADM_DOCKER_BIN_DIR="${binDir}" \
        PADM_DOCKER_LOCK_TIMEOUT="${PADM_DOCKER_LOCK_TIMEOUT:-2}" \
        FAKE_DOCKER_LOG="${DOCKER_CALL_LOG}" \
        FAKE_DOCKER_MODE="${FAKE_DOCKER_MODE:-ok}" \
        FAKE_UNAME_ARCH="${FAKE_UNAME_ARCH:-x86_64}" \
        FAKE_DAEMON_ARCH="${FAKE_DAEMON_ARCH:-x86_64}" \
        FAKE_COMPOSE_VERSION="${FAKE_COMPOSE_VERSION:-v2.29.1}" \
        bash -u "${PROJECT_ROOT}/install-docker.sh" "$@" >"${CONTROL_LOG}" 2>&1 || actual=$?
    if [[ "${actual}" -ne "${expected}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
        fail "${name}: expected rc=${expected}, got rc=${actual}"
    fi
}

runEnginePromptCase() {
    local name=$1 input=$2 expected=$3 installStatus=$4
    local marker="${TEST_ROOT}/${name}.installed"
    local actual=0
    rm -f -- "${marker}"
    env \
        PHASE1_PROJECT_ROOT="${PROJECT_ROOT}" \
        PHASE1_INPUT="${input}" \
        PHASE1_EXPECTED="${expected}" \
        PHASE1_INSTALL_STATUS="${installStatus}" \
        PHASE1_INSTALL_MARKER="${marker}" \
        bash -u -c '
            set -u
            source "$PHASE1_PROJECT_ROOT/install-docker.sh"
            dockerEntryDockerAvailable() { return 1; }
            dockerEntryInstallDockerEngine() {
                : >"$PHASE1_INSTALL_MARKER"
                return "$PHASE1_INSTALL_STATUS"
            }
            actual=0
            if [[ "$PHASE1_INPUT" == __EOF__ ]]; then
                dockerEntryEnsureDockerForInstall </dev/null || actual=$?
            else
                dockerEntryEnsureDockerForInstall <<<"$PHASE1_INPUT" || actual=$?
            fi
            [[ "$actual" -eq "$PHASE1_EXPECTED" ]]
        ' || fail "${name}: unexpected Docker prompt result"
    if [[ "${input}" == 'y' ]]; then
        [[ -f "${marker}" ]] || fail "${name}: install hook was not called"
    else
        [[ ! -e "${marker}" ]] || fail "${name}: install hook was called unexpectedly"
    fi
}

runEnginePromptCase prompt-no n 10 0
runEnginePromptCase prompt-yes y 0 0
runEnginePromptCase prompt-eof __EOF__ 10 0
runEnginePromptCase prompt-install-fail y 10 1
env \
    PHASE1_PROJECT_ROOT="${PROJECT_ROOT}" \
    bash -u -c '
        set -u
        source "$PHASE1_PROJECT_ROOT/install-docker.sh"
        dockerEntryDockerAvailable() { return 0; }
        dockerEntryInstallDockerEngine() { return 99; }
        dockerEntryEnsureDockerForInstall </dev/null
    ' || fail 'existing Docker installation prompted or failed unexpectedly'
NATIVE_PROMPT_ROOT="${TEST_ROOT}/native-prompt"
mkdir -p "${NATIVE_PROMPT_ROOT}"
printf 'native\n' >"${NATIVE_PROMPT_ROOT}/mode"
env \
    PHASE1_PROJECT_ROOT="${PROJECT_ROOT}" \
    PADM_NATIVE_INSTALL_DIR="${NATIVE_PROMPT_ROOT}" \
    bash -u -c '
        set -u
        source "$PHASE1_PROJECT_ROOT/install-docker.sh"
        dockerEntryDockerAvailable() { return 1; }
        dockerEntryInstallDockerEngine() { return 99; }
        actual=0
        dockerEntryEnsureDockerForInstall <<<yes || actual=$?
        [[ "$actual" -eq 10 ]]
    ' || fail 'native installation conflict was not rejected before Docker bootstrap'

copyBundleFixture() {
    local target=$1
    mkdir -p "${target}/shell/core" "${target}/documents"
    cp "${PROJECT_ROOT}/install-docker.sh" "${target}/install-docker.sh"
    cp -R "${PROJECT_ROOT}/docker" "${target}/docker"
    cp "${PROJECT_ROOT}/shell/core/deployment_mode.sh" "${target}/shell/core/deployment_mode.sh"
    find "${PROJECT_ROOT}/documents" -maxdepth 1 -type f -name 'docker*.md' -exec cp {} "${target}/documents/" \;
}

DOCKER_ROOT="${TEST_ROOT}/state"
NATIVE_ROOT="${TEST_ROOT}/native"
CLI_DIR="${TEST_ROOT}/usr-local-bin"
mkdir -p "${NATIVE_ROOT}"
NO_COMPOSE_SOURCE="${TEST_ROOT}/no-compose-source"
copyBundleFixture "${NO_COMPOSE_SOURCE}"
rm -f -- "${NO_COMPOSE_SOURCE}/docker/compose.yaml"

runControl 0 install "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${NO_COMPOSE_SOURCE}"
[[ "$(<"${DOCKER_ROOT}/mode")" == "docker" ]] || fail 'mode marker was not initialized'
for directory in bundle config data secrets logs backups locks; do
    [[ -d "${DOCKER_ROOT}/${directory}" ]] || fail "missing state directory: ${directory}"
done
[[ -L "${DOCKER_ROOT}/bundle" ]] || fail 'bundle pointer is not a symbolic link'
[[ -L "${CLI_DIR}/padm-docker" ]] || fail 'padm-docker command link is missing'
[[ "$(readlink "${CLI_DIR}/padm-docker")" == "${DOCKER_ROOT}/bundle/install-docker.sh" ]] ||
    fail 'padm-docker command link has an unexpected target'
(
    cd "${DOCKER_ROOT}/bundle"
    sha256sum -c "./.padm-docker-bundle-manifest" >/dev/null
) || fail 'installed bundle manifest does not validate'

if [[ "$(/usr/bin/env uname -s 2>/dev/null || true)" == "Linux" ]]; then
    [[ "$(stat -c %a "${DOCKER_ROOT}")" == "750" ]] || fail 'state root mode is not 0750'
    [[ "$(stat -c %a "${DOCKER_ROOT}/secrets")" == "700" ]] || fail 'secrets mode is not 0700'
    [[ "$(stat -c %a "${DOCKER_ROOT}/mode")" == "640" ]] || fail 'mode file mode is not 0640'
fi

printf 'keep\n' >"${DOCKER_ROOT}/data/sentinel"
bundleBefore=$(readlink "${DOCKER_ROOT}/bundle")
runControl 0 repeat-install "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${NO_COMPOSE_SOURCE}"
[[ "$(readlink "${DOCKER_ROOT}/bundle")" == "${bundleBefore}" ]] || fail 'repeat install changed an identical bundle'
[[ "$(<"${DOCKER_ROOT}/data/sentinel")" == "keep" ]] || fail 'repeat install changed persistent data'

runControl 0 status-without-configuration "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" status
grep -q '^configured=no$' "${CONTROL_LOG}" || fail 'status did not expose missing configuration state'
for operation in up down restart logs; do
    runControl 14 "${operation}-without-compose" "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" "${operation}"
done

CONFLICT_NATIVE="${TEST_ROOT}/native-conflict"
CONFLICT_DOCKER="${TEST_ROOT}/docker-conflict"
mkdir -p "${CONFLICT_NATIVE}"
printf 'native\n' >"${CONFLICT_NATIVE}/mode"
runControl 11 native-conflict "${CONFLICT_DOCKER}" "${CONFLICT_NATIVE}" "${TEST_ROOT}/conflict-bin" install --source "${PROJECT_ROOT}"
[[ ! -e "${CONFLICT_DOCKER}" ]] || fail 'native conflict wrote Docker state'

RESIDUE_NATIVE="${TEST_ROOT}/native-residue"
RESIDUE_DOCKER="${TEST_ROOT}/docker-native-residue"
mkdir -p "${RESIDUE_NATIVE}"
printf 'unknown\n' >"${RESIDUE_NATIVE}/residue"
runControl 11 native-residue "${RESIDUE_DOCKER}" "${RESIDUE_NATIVE}" "${TEST_ROOT}/residue-bin" \
    install --source "${PROJECT_ROOT}"
[[ ! -e "${RESIDUE_DOCKER}" ]] || fail 'unknown native residue wrote Docker state'

AMBIGUOUS_ROOT="${TEST_ROOT}/ambiguous"
mkdir -p "${AMBIGUOUS_ROOT}"
printf 'unknown\n' >"${AMBIGUOUS_ROOT}/residue"
runControl 11 ambiguous-root "${AMBIGUOUS_ROOT}" "${NATIVE_ROOT}" "${TEST_ROOT}/ambiguous-bin" install --source "${PROJECT_ROOT}"
[[ "$(<"${AMBIGUOUS_ROOT}/residue")" == "unknown" ]] || fail 'ambiguous state was modified'

for failureMode in daemon-fail rootless; do
    export FAKE_DOCKER_MODE=${failureMode}
    failedRoot="${TEST_ROOT}/host-${failureMode}"
    runControl 10 "host-${failureMode}" "${failedRoot}" "${NATIVE_ROOT}" "${TEST_ROOT}/host-bin" install --source "${PROJECT_ROOT}"
    [[ ! -e "${failedRoot}" ]] || fail "${failureMode} preflight wrote state"
done
unset FAKE_DOCKER_MODE

export FAKE_DOCKER_MODE=active
runControl 11 unlabeled-active-containers "${TEST_ROOT}/active-without-state" "${NATIVE_ROOT}" \
    "${TEST_ROOT}/active-bin" install --source "${PROJECT_ROOT}"
[[ ! -e "${TEST_ROOT}/active-without-state" ]] || fail 'unlabeled active deployment wrote state'
runControl 15 status-unlabeled-active "${TEST_ROOT}/active-status-without-state" "${NATIVE_ROOT}" \
    "${TEST_ROOT}/active-status-bin" status
[[ ! -e "${TEST_ROOT}/active-status-without-state" ]] || fail 'status on an unlabeled active deployment wrote state'
unset FAKE_DOCKER_MODE

export FAKE_COMPOSE_VERSION=v1.29.2
runControl 10 compose-v1 "${TEST_ROOT}/compose-v1" "${NATIVE_ROOT}" "${TEST_ROOT}/compose-v1-bin" install --source "${PROJECT_ROOT}"
[[ ! -e "${TEST_ROOT}/compose-v1" ]] || fail 'Compose v1 preflight wrote state'
unset FAKE_COMPOSE_VERSION

export FAKE_UNAME_ARCH=riscv64
runControl 10 unsupported-arch "${TEST_ROOT}/bad-arch" "${NATIVE_ROOT}" "${TEST_ROOT}/bad-arch-bin" install --source "${PROJECT_ROOT}"
[[ ! -e "${TEST_ROOT}/bad-arch" ]] || fail 'unsupported architecture preflight wrote state'
unset FAKE_UNAME_ARCH

INVALID_REF_ROOT="${TEST_ROOT}/invalid-ref"
runControl 2 invalid-ref "${INVALID_REF_ROOT}" "${NATIVE_ROOT}" "${TEST_ROOT}/invalid-ref-bin" \
    install --source "${PROJECT_ROOT}" --ref not-a-commit
[[ ! -e "${INVALID_REF_ROOT}" ]] || fail 'invalid ref wrote state'

LOCK_ROOT="${TEST_ROOT}/locked"
mkdir -p "${LOCK_ROOT}/locks/deployment.lock"
printf '%s\n' "$$" >"${LOCK_ROOT}/locks/deployment.lock/pid"
PADM_DOCKER_LOCK_TIMEOUT=0 runControl 12 deployment-lock "${LOCK_ROOT}" "${NATIVE_ROOT}" "${TEST_ROOT}/lock-bin" install --source "${PROJECT_ROOT}"

BROKEN_SOURCE="${TEST_ROOT}/broken-source"
copyBundleFixture "${BROKEN_SOURCE}"
rm -f -- "${BROKEN_SOURCE}/docker/lib/lifecycle.sh"
runControl 13 broken-bundle "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${BROKEN_SOURCE}"
[[ "$(readlink "${DOCKER_ROOT}/bundle")" == "${bundleBefore}" ]] || fail 'failed bundle refresh changed the active bundle'
[[ "$(<"${DOCKER_ROOT}/data/sentinel")" == "keep" ]] || fail 'failed bundle refresh changed persistent data'

COMPOSE_SOURCE="${TEST_ROOT}/compose-source"
copyBundleFixture "${COMPOSE_SOURCE}"
printf 'services: {}\n' >"${COMPOSE_SOURCE}/docker/compose.yaml"
runControl 0 install-compose-fixture "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${COMPOSE_SOURCE}"
cat >"${DOCKER_ROOT}/deployment.json" <<'EOF'
{
  "schema_version": 1,
  "mode": "docker",
  "padm_version": "test",
  "compose": {"project": "padm-docker", "profiles": ["core-xray"]}
}
EOF
cat >"${DOCKER_ROOT}/images.env" <<EOF
PADM_XRAY_IMAGE=ghcr.io/example/padm-xray:test@sha256:$(printf '1%.0s' {1..64})
PADM_DOCKER_ROOT=${DOCKER_ROOT}
EOF
printf '{"name":"padm-docker","services":{}}\n' >"${DOCKER_ROOT}/compose.json"
: >"${DOCKER_CALL_LOG}"
runControl 0 compose-status "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" status
runControl 0 compose-up "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" up
runControl 0 compose-down "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" down
runControl 0 compose-restart "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" restart
runControl 0 compose-logs "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" logs --tail 5
grep -q ' ps$' "${DOCKER_CALL_LOG}" || fail 'status did not call Compose ps'
grep -q ' up -d --remove-orphans$' "${DOCKER_CALL_LOG}" || fail 'up did not remove Compose orphans'
grep -q ' down --remove-orphans$' "${DOCKER_CALL_LOG}" || fail 'down did not remove Compose orphans'
grep -q ' restart$' "${DOCKER_CALL_LOG}" || fail 'restart did not call Compose restart'
grep -q ' logs --tail 5$' "${DOCKER_CALL_LOG}" || fail 'logs arguments were not forwarded'

runControl 0 uninstall "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" uninstall
[[ ! -e "${CLI_DIR}/padm-docker" && ! -L "${CLI_DIR}/padm-docker" ]] || fail 'uninstall kept the CLI link'
[[ "$(<"${DOCKER_ROOT}/data/sentinel")" == "keep" ]] || fail 'uninstall removed persistent data'
[[ "$(<"${DOCKER_ROOT}/mode")" == "docker" ]] || fail 'uninstall removed the mode marker'
runControl 0 repeat-uninstall "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" uninstall

if grep -ERn 'docker[[:space:]]+build' \
    "${PROJECT_ROOT}/install-docker.sh" "${PROJECT_ROOT}/docker/lib" >/dev/null; then
    fail 'Docker control path contains a build command'
fi
grep -Fq 'docker-ce' "${PROJECT_ROOT}/install-docker.sh" || fail 'Docker installer lacks Docker CE packages'
grep -Fq 'docker-compose-plugin' "${PROJECT_ROOT}/install-docker.sh" ||
    fail 'Docker installer lacks the Compose v2 plugin'
grep -Fq '是否使用 Docker 官方软件源安装' "${PROJECT_ROOT}/install-docker.sh" ||
    fail 'Docker installer lacks the explicit confirmation prompt'
if grep -Fq 'get.docker.com' "${PROJECT_ROOT}/install-docker.sh"; then
    fail 'Docker installer uses the convenience script'
fi

printf 'docker-phase1-regression-ok\n'
