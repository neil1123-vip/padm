#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase1.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
CONTROL_LOG="${TEST_ROOT}/control.log"
DOCKER_CALL_LOG="${TEST_ROOT}/docker.log"
mkdir -p "${MOCK_BIN}" "${TEST_ROOT}/systemd"
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
    [[ "${mode}" != "compose-slow" ]] || exec sleep 30
    [[ "${mode}" != "compose-fail" ]]
    ;;
ps)
    if [[ "$*" != 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ]]; then
        [[ "${mode}" != "active" ]] || printf 'container-id\n'
    fi
    ;;
*) exit 1 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/uname" "${MOCK_BIN}/id" "${MOCK_BIN}/docker"
printf '#!/usr/bin/env bash\nexit 0\n' >"${MOCK_BIN}/systemctl"
chmod 0755 "${MOCK_BIN}/systemctl"

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
        PADM_DOCKER_SYSTEMD_DIR="${TEST_ROOT}/systemd" \
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

# 参数错误必须在引擎探测或安装确认前退出，合法参数仍进入原流程。
runEngineArgumentCase() {
    local expected=$1 name=$2 marker="${TEST_ROOT}/engine-args.log"
    shift 2
    : >"${marker}"
    (
        command() {
            if [[ "$*" == '-v docker' ]]; then
                printf 'probe\n' >>"${PHASE1_ENGINE_ARGS_LOG}"
                return 1
            fi
            builtin command "$@"
        }
        export -f command
        export PHASE1_ENGINE_ARGS_LOG="${marker}"
        runControl "${expected}" "${name}" "${TEST_ROOT}/engine-args-state" \
            "${TEST_ROOT}/engine-args-native" "${TEST_ROOT}/engine-args-bin" \
            install "$@" </dev/null
    )
    if [[ "${expected}" -ne 10 ]]; then
        [[ ! -s "${marker}" ]] || fail "${name}: invalid arguments reached Docker bootstrap"
    else
        [[ -s "${marker}" ]] || fail "${name}: valid arguments skipped Docker bootstrap"
    fi
}
runEngineArgumentCase 10 engine-args-valid --no-menu --source "${PROJECT_ROOT}"
runEngineArgumentCase 10 engine-args-valid-ref --ref ffffffffffffffffffffffffffffffffffffffff
runEngineArgumentCase 10 engine-args-local-digest --source "${PROJECT_ROOT}" --ref "sha256:$(printf 'a%.0s' {1..64})"
runEngineArgumentCase 2 engine-args-remote-digest --ref "sha256:$(printf 'a%.0s' {1..64})"
runEngineArgumentCase 2 engine-args-invalid-ref --ref typo
runEngineArgumentCase 2 engine-args-missing-ref --ref
runEngineArgumentCase 2 engine-args-missing-source --source
runEngineArgumentCase 2 engine-args-unknown --unknown
runEngineArgumentCase 2 engine-args-source-latest --source "${PROJECT_ROOT}" --ref latest
runEngineArgumentCase 13 engine-args-missing-directory --source "${TEST_ROOT}/missing-source"
mkdir -- "${TEST_ROOT}/empty-source"
runEngineArgumentCase 13 engine-args-empty-directory --source "${TEST_ROOT}/empty-source"

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
    cp "${PROJECT_ROOT}/shell/core/stats_grpc.sh" "${target}/shell/core/stats_grpc.sh"
    cp "${PROJECT_ROOT}/shell/core/"{runtime.sh,reality_targets.sh,cores.sh} "${target}/shell/core/"
    find "${PROJECT_ROOT}/documents" -maxdepth 1 -type f -name 'docker*.md' -exec cp {} "${target}/documents/" \;
}

DOCKER_ROOT="${TEST_ROOT}/state"
NATIVE_ROOT="${TEST_ROOT}/native"
CLI_DIR="${TEST_ROOT}/usr-local-bin"
mkdir -p "${NATIVE_ROOT}"
NO_COMPOSE_SOURCE="${TEST_ROOT}/no-compose-source"
copyBundleFixture "${NO_COMPOSE_SOURCE}"
rm -f -- "${NO_COMPOSE_SOURCE}/docker/compose.yaml"

# 单文件入口应尊重完整本地源，不下载 latest 或其它模块。
STANDALONE_ROOT="${TEST_ROOT}/standalone"
FETCH_LOG="${TEST_ROOT}/standalone-fetch.log"
mkdir -p "${STANDALONE_ROOT}"
cp -- "${PROJECT_ROOT}/install-docker.sh" "${STANDALONE_ROOT}/install-docker.sh"
(
    curl() { printf '%s\n' "$*" >>"${PHASE1_FETCH_LOG}"; return 99; }
    wget() { curl "$@"; }
    export -f curl wget
    export PHASE1_FETCH_LOG="${FETCH_LOG}"
    PROJECT_ROOT="${STANDALONE_ROOT}" runControl 0 standalone-local-source \
        "${TEST_ROOT}/standalone-state" "${NATIVE_ROOT}" "${TEST_ROOT}/standalone-bin" \
        install --no-menu --source "${NO_COMPOSE_SOURCE}"
    [[ ! -s "${FETCH_LOG}" ]] || fail 'standalone local source attempted a download'
    PROJECT_ROOT="${STANDALONE_ROOT}" runControl 2 standalone-source-latest \
        "${TEST_ROOT}/standalone-invalid" "${NATIVE_ROOT}" "${TEST_ROOT}/standalone-invalid-bin" \
        install --source "${NO_COMPOSE_SOURCE}" --ref latest
    [[ ! -s "${FETCH_LOG}" && ! -e "${TEST_ROOT}/standalone-invalid" ]] ||
        fail 'invalid standalone source/ref performed installation work'
)

# 指定 SHA 只取一次匹配归档，不访问 latest 元数据。
FETCH_ARCHIVE="${TEST_ROOT}/standalone-source.tar.gz"
FETCH_REF=ffffffffffffffffffffffffffffffffffffffff
tar -czf "${FETCH_ARCHIVE}" -C "${TEST_ROOT}" no-compose-source
(
    curl() {
        local url=${!#} target=
        printf '%s\n' "${url}" >>"${PHASE1_FETCH_LOG}"
        [[ "${url}" == "https://github.com/neil1123-vip/padm/archive/${PHASE1_FETCH_REF}.tar.gz" ]] || return 99
        while [[ "$#" -gt 0 ]]; do
            if [[ "$1" == -o ]]; then target=$2; break; fi
            shift
        done
        [[ -n "${target}" ]] && command cp -- "${PHASE1_FETCH_ARCHIVE}" "${target}"
    }
    wget() { return 99; }
    export -f curl wget
    export PHASE1_FETCH_LOG="${FETCH_LOG}" PHASE1_FETCH_ARCHIVE="${FETCH_ARCHIVE}" PHASE1_FETCH_REF="${FETCH_REF}"
    PROJECT_ROOT="${STANDALONE_ROOT}" runControl 0 standalone-fixed-ref \
        "${TEST_ROOT}/standalone-ref-state" "${NATIVE_ROOT}" "${TEST_ROOT}/standalone-ref-bin" \
        install --no-menu --ref "${FETCH_REF}"
    [[ "$(wc -l <"${FETCH_LOG}")" -eq 1 ]] || fail 'standalone fixed ref downloaded more than once'
    [[ "$(<"${TEST_ROOT}/standalone-ref-state/bundle/.padm-docker-bundle-ref")" == "${FETCH_REF}" ]] ||
        fail 'standalone fixed ref did not preserve the requested version'
)

# 加载控制模块前中断下载或解包，也必须清理本次临时源。
for signal in INT TERM; do
    signalStatus=130
    [[ "${signal}" != TERM ]] || signalStatus=143
    for stage in download extract; do
        interruptedTemp="${TEST_ROOT}/standalone-${stage}-${signal}-tmp"
        interruptedState="${TEST_ROOT}/standalone-${stage}-${signal}-state"
        mkdir -- "${interruptedTemp}"
        (
            curl() {
                local target=
                if [[ "${PHASE1_FETCH_STAGE}" == download ]]; then
                    kill -"${PHASE1_FETCH_SIGNAL}" "${BASHPID:-$$}"
                fi
                while [[ "$#" -gt 0 ]]; do
                    if [[ "$1" == -o ]]; then target=$2; break; fi
                    shift
                done
                [[ -n "${target}" ]] && command cp -- "${PHASE1_FETCH_ARCHIVE}" "${target}"
            }
            tar() {
                if [[ "${PHASE1_FETCH_STAGE}" == extract && "${1:-}" == -xzf ]]; then
                    kill -"${PHASE1_FETCH_SIGNAL}" "${BASHPID:-$$}"
                fi
                command tar "$@"
            }
            wget() { return 99; }
            export -f curl wget tar
            export TMPDIR="${interruptedTemp}" PHASE1_FETCH_ARCHIVE="${FETCH_ARCHIVE}"
            export PHASE1_FETCH_SIGNAL="${signal}" PHASE1_FETCH_STAGE="${stage}"
            PROJECT_ROOT="${STANDALONE_ROOT}" runControl "${signalStatus}" \
                "standalone-${stage}-${signal}" "${interruptedState}" "${NATIVE_ROOT}" \
                "${TEST_ROOT}/standalone-${stage}-${signal}-bin" install --no-menu --ref "${FETCH_REF}"
        )
        [[ ! -e "${interruptedState}" &&
            -z "$(find "${interruptedTemp}" -mindepth 1 -print -quit)" ]] ||
            fail "standalone-${stage}-${signal}: interruption kept bootstrap source"
    done
done

# 预加载只供本次安装使用，同进程的后续 latest 必须重新解析。
(
    source "${PROJECT_ROOT}/install-docker.sh"
    DOCKER_ENTRY_SOURCE_DIR=${NO_COMPOSE_SOURCE}
    DOCKER_ENTRY_FETCHED_REF=${FETCH_REF}
    DOCKER_ENTRY_BOOTSTRAP_REF=latest
    fetches=0
    dockerEntryFetchBundle() {
        [[ "$1" == latest ]] || return 1
        fetches=$((fetches + 1))
        DOCKER_ENTRY_FETCHED_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    }
    dockerPrepareInstallSource "" latest || fail 'prefetched install source was rejected'
    [[ "${fetches}" -eq 0 && -z "${DOCKER_ENTRY_BOOTSTRAP_REF}" &&
        "${DOCKER_INSTALL_SOURCE_REF}" == "${FETCH_REF}" ]] || fail 'bootstrap ref was not consumed once'
    dockerPrepareInstallSource "" latest || fail 'subsequent latest source was rejected'
    [[ "${fetches}" -eq 1 && "${DOCKER_INSTALL_SOURCE_REF}" != "${FETCH_REF}" ]] ||
        fail 'subsequent latest reused the bootstrap ref'
)

runControl 0 install "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${NO_COMPOSE_SOURCE}"
[[ "$(<"${DOCKER_ROOT}/mode")" == "docker" ]] || fail 'mode marker was not initialized'
for directory in bundle config data secrets logs backups locks; do
    [[ -d "${DOCKER_ROOT}/${directory}" ]] || fail "missing state directory: ${directory}"
done
[[ -L "${DOCKER_ROOT}/bundle" ]] || fail 'bundle pointer is not a symbolic link'
[[ -f "${DOCKER_ROOT}/bundle/shell/core/stats_grpc.sh" ]] || fail 'bundle lacks the shared stats decoder'
[[ -f "${DOCKER_ROOT}/bundle/shell/core/reality_targets.sh" &&
    -f "${DOCKER_ROOT}/bundle/shell/core/runtime.sh" ]] || fail 'bundle lacks the shared Reality target module'
[[ -L "${CLI_DIR}/padm-docker" ]] || fail 'padm-docker command link is missing'
[[ "$(readlink "${CLI_DIR}/padm-docker")" == "${DOCKER_ROOT}/bundle/install-docker.sh" ]] ||
    fail 'padm-docker command link has an unexpected target'
(
    cd "${DOCKER_ROOT}/bundle"
    sha256sum -c "./.padm-docker-bundle-manifest" >/dev/null
) || fail 'installed bundle manifest does not validate'

(
    source "${PROJECT_ROOT}/docker/lib/bundle.sh"
    validationRoot="${TEST_ROOT}/bundle-validation"
    mkdir -- "${validationRoot}"
    cp -R "${DOCKER_ROOT}/bundle/." "${validationRoot}/"
    manifest="${validationRoot}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    printf 'hash fixture\n' >"${validationRoot}/docker/-hash-fixture"
    dockerWriteBundleManifest "${validationRoot}" || fail 'batch manifest generation failed'
    referenceManifest="${TEST_ROOT}/bundle-manifest-reference"
    : >"${referenceManifest}"
    while IFS= read -r relativePath; do
        sha256sum "${validationRoot}/${relativePath}" |
            awk -v path="${relativePath}" '{print $1 "  " path}' >>"${referenceManifest}"
    done < <({ dockerBundlePayloadPaths "${validationRoot}"; printf '%s\n' "${PADM_DOCKER_BUNDLE_REF}"; } | LC_ALL=C sort -u)
    cmp -s "${referenceManifest}" "${manifest}" || fail 'batch manifest differs from per-file hashes'
    : >"${referenceManifest}"
    while IFS= read -r relativePath; do
        sha256sum "${validationRoot}/${relativePath}" |
            awk -v path="${relativePath}" '{print $1 "  " path}' >>"${referenceManifest}"
    done < <(dockerBundlePayloadPaths "${validationRoot}")
    expectedDigest="sha256:$(sha256sum "${referenceManifest}" | cut -d ' ' -f 1)"
    [[ "$(dockerBundleSourceDigest "${validationRoot}")" == "${expectedDigest}" ]] ||
        fail 'batch source digest differs from per-file hashes'
    cp -- "${manifest}" "${TEST_ROOT}/bundle-manifest"
    dockerValidateBundle "${validationRoot}" || fail 'valid bundle was rejected'
    (
        export TMPDIR="${TEST_ROOT}/bundle-hash-tmp"
        mkdir -- "${TMPDIR}"
        sha256sum() { printf 'partial hash output\n'; return 17; }
        if dockerWriteBundleManifest "${validationRoot}"; then
            fail 'partial hash failure was accepted'
        fi
        [[ ! -e "${manifest}" ]] || fail 'partial manifest was retained'
        if dockerBundleSourceDigest "${validationRoot}"; then
            fail 'partial source hash failure was accepted'
        fi
        [[ -z "$(find "${TMPDIR}" -mindepth 1 -print -quit)" ]] ||
            fail 'hash failure leaked temporary files'
    ) || fail 'batch hash failure cleanup failed'
    cp -- "${TEST_ROOT}/bundle-manifest" "${manifest}"
    manifestText=$(<"${manifest}")
    printf '%s' "${manifestText//  /$'\t\t'}" >"${manifest}"
    dockerValidateBundle "${validationRoot}" ||
        fail 'tab-separated manifest without a final newline was rejected'
    cp -- "${TEST_ROOT}/bundle-manifest" "${manifest}"
    printf 'changed\n' >>"${validationRoot}/install-docker.sh"
    if dockerValidateBundle "${validationRoot}"; then
        fail 'bundle with changed contents was accepted'
    fi
    rm -f -- "${validationRoot}/install-docker.sh"
    if dockerValidateBundle "${validationRoot}"; then
        fail 'bundle with a missing file was accepted'
    fi
    cp -- "${DOCKER_ROOT}/bundle/install-docker.sh" "${validationRoot}/install-docker.sh"
    head -n 1 "${TEST_ROOT}/bundle-manifest" >>"${manifest}"
    if dockerValidateBundle "${validationRoot}"; then
        fail 'bundle with a duplicate manifest entry was accepted'
    fi
    cp -- "${TEST_ROOT}/bundle-manifest" "${manifest}"
    printf 'invalid manifest entry\n' >>"${manifest}"
    if dockerValidateBundle "${validationRoot}"; then
        fail 'bundle with an invalid manifest entry was accepted'
    fi
    cp -- "${TEST_ROOT}/bundle-manifest" "${manifest}"
    printf '%064d  ../outside\n' 0 >>"${manifest}"
    if dockerValidateBundle "${validationRoot}"; then
        fail 'bundle with an unsafe manifest path was accepted'
    fi
) || fail 'bundle checksum validation cases failed'

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

# CLI 完成前收到信号，首装撤销本次指针，重装恢复旧控制版本。
for signal in INT TERM; do
    signalStatus=130
    [[ "${signal}" != TERM ]] || signalStatus=143
    for installKind in first repeat; do
        TRANSACTION_ROOT="${TEST_ROOT}/install-${signal}-${installKind}"
        TRANSACTION_BIN="${TEST_ROOT}/install-${signal}-${installKind}-bin"
        previousTarget=
        if [[ "${installKind}" == repeat ]]; then
            runControl 0 "install-${signal}-prepare" "${TRANSACTION_ROOT}" "${NATIVE_ROOT}" \
                "${TRANSACTION_BIN}" install --source "${NO_COMPOSE_SOURCE}"
            previousTarget=$(readlink "${TRANSACTION_ROOT}/bundle")
            printf 'keep\n' >"${TRANSACTION_ROOT}/data/sentinel"
        fi
        (
            mv() {
                if [[ "${*: -1}" == "${PADM_DOCKER_BIN_DIR}/padm-docker" ]]; then
                    command mv "$@"
                    kill -"${PHASE1_INSTALL_SIGNAL}" "${BASHPID:-$$}"
                    return
                fi
                command mv "$@"
            }
            export -f mv
            export PHASE1_INSTALL_SIGNAL=${signal}
            runControl "${signalStatus}" "install-${signal}-${installKind}" "${TRANSACTION_ROOT}" \
                "${NATIVE_ROOT}" "${TRANSACTION_BIN}" install --source "${NO_COMPOSE_SOURCE}" \
                --ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        )
        [[ ! -e "${TRANSACTION_ROOT}/locks/deployment.lock" ]] ||
            fail "install-${signal}-${installKind}: deployment lock leaked"
        if [[ "${installKind}" == repeat ]]; then
            [[ "$(readlink "${TRANSACTION_ROOT}/bundle")" == "${previousTarget}" &&
                "$(<"${TRANSACTION_ROOT}/data/sentinel")" == keep &&
                "$(readlink "${TRANSACTION_BIN}/padm-docker")" == "${TRANSACTION_ROOT}/bundle/install-docker.sh" ]] ||
                fail "install-${signal}: old deployment was not restored"
        else
            [[ ! -e "${TRANSACTION_ROOT}/bundle" && ! -L "${TRANSACTION_ROOT}/bundle" &&
                ! -e "${TRANSACTION_BIN}/padm-docker" ]] ||
                fail "install-${signal}: first installation kept an active bundle"
        fi
    done
done

# CLI 临时链接创建后中断或读取 inode 失败，不保留本次临时命令。
for failure in INT TERM stat; do
    TRANSACTION_ROOT="${TEST_ROOT}/install-cli-temp-${failure}"
    TRANSACTION_BIN="${TEST_ROOT}/install-cli-temp-${failure}-bin"
    expectedStatus=130
    case "${failure}" in
    TERM) expectedStatus=143 ;;
    stat) expectedStatus=15 ;;
    esac
    (
        ln() {
            command ln "$@" || return $?
            if [[ "${PHASE1_CLI_TEMP_FAILURE}" != stat &&
                "${*: -1}" == "${PADM_DOCKER_BIN_DIR}/.padm-docker."* ]]; then
                kill -"${PHASE1_CLI_TEMP_FAILURE}" "${BASHPID:-$$}"
            fi
        }
        stat() {
            [[ "${PHASE1_CLI_TEMP_FAILURE}" != stat ||
                "${*: -1}" != "${PADM_DOCKER_BIN_DIR}/.padm-docker."* ]] || return 1
            command stat "$@"
        }
        export -f ln stat
        export PHASE1_CLI_TEMP_FAILURE=${failure}
        runControl "${expectedStatus}" "install-cli-temp-${failure}" "${TRANSACTION_ROOT}" \
            "${NATIVE_ROOT}" "${TRANSACTION_BIN}" install --source "${NO_COMPOSE_SOURCE}"
    )
    [[ ! -e "${TRANSACTION_ROOT}/bundle" && ! -L "${TRANSACTION_ROOT}/bundle" &&
        ! -e "${TRANSACTION_BIN}/padm-docker" &&
        ! -e "${TRANSACTION_ROOT}/locks/deployment.lock" &&
        -z "$(find "${TRANSACTION_BIN}" -maxdepth 1 -name '.padm-docker.*' -print)" ]] ||
        fail "install-cli-temp-${failure}: temporary command or installed pointer leaked"
done

# 激活指针已移动但安装尚未返回时，仍使用提前登记的精确目标恢复。
TRANSACTION_ROOT="${TEST_ROOT}/install-activation"
TRANSACTION_BIN="${TEST_ROOT}/install-activation-bin"
mkdir -p -- "${TRANSACTION_BIN}"
ln -s "${TRANSACTION_ROOT}/bundle/install-docker.sh" "${TRANSACTION_BIN}/padm-docker"
(
    mv() {
        if [[ "${*: -1}" == "${PADM_DOCKER_INSTALL_DIR}/bundle" ]]; then
            command mv "$@"
            kill -TERM "${BASHPID:-$$}"
            return
        fi
        command mv "$@"
    }
    export -f mv
    runControl 143 install-activation "${TRANSACTION_ROOT}" "${NATIVE_ROOT}" "${TRANSACTION_BIN}" \
        install --source "${NO_COMPOSE_SOURCE}"
)
[[ ! -e "${TRANSACTION_ROOT}/bundle" && ! -L "${TRANSACTION_ROOT}/bundle" &&
    -L "${TRANSACTION_BIN}/padm-docker" &&
    "$(readlink "${TRANSACTION_BIN}/padm-docker")" == "${TRANSACTION_ROOT}/bundle/install-docker.sh" &&
    ! -e "${TRANSACTION_ROOT}/locks/deployment.lock" ]] ||
    fail 'install-activation: exact activation cleanup or old CLI preservation failed'

# 中断前本次指针或命令被替换时，不删除用户的新状态。
for installKind in first repeat; do
    TRANSACTION_ROOT="${TEST_ROOT}/install-changed-${installKind}"
    TRANSACTION_BIN="${TEST_ROOT}/install-changed-${installKind}-bin"
    if [[ "${installKind}" == repeat ]]; then
        runControl 0 install-changed-prepare "${TRANSACTION_ROOT}" "${NATIVE_ROOT}" \
            "${TRANSACTION_BIN}" install --source "${NO_COMPOSE_SOURCE}"
    fi
    (
        mv() {
            if [[ "${*: -1}" == "${PADM_DOCKER_BIN_DIR}/padm-docker" ]]; then
                command mv "$@"
                rm -f -- "${PADM_DOCKER_INSTALL_DIR}/bundle" "${PADM_DOCKER_BIN_DIR}/padm-docker"
                printf 'user-bundle\n' >"${PADM_DOCKER_INSTALL_DIR}/bundle"
                printf 'user-command\n' >"${PADM_DOCKER_BIN_DIR}/padm-docker"
                kill -TERM "${BASHPID:-$$}"
                return
            fi
            command mv "$@"
        }
        export -f mv
        runControl 143 "install-changed-${installKind}" "${TRANSACTION_ROOT}" "${NATIVE_ROOT}" \
            "${TRANSACTION_BIN}" install --source "${NO_COMPOSE_SOURCE}" \
            --ref aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    )
    [[ "$(<"${TRANSACTION_ROOT}/bundle")" == user-bundle &&
        "$(<"${TRANSACTION_BIN}/padm-docker")" == user-command &&
        ! -e "${TRANSACTION_ROOT}/locks/deployment.lock" ]] ||
        fail "install-changed-${installKind}: interrupted cleanup changed user state"
done

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
[[ ! -e "${AMBIGUOUS_ROOT}/mode" ]] || fail 'ambiguous state received a mode marker'

# 初始化部分失败后，保留归属标记并允许下一次完整安装恢复。
RETRY_ROOT="${TEST_ROOT}/initialize-retry"
RETRY_BIN="${TEST_ROOT}/initialize-retry-bin"
(
    mkdir() {
        [[ "$*" != "-- ${PADM_DOCKER_INSTALL_DIR}/config" ]] || return 1
        command mkdir "$@"
    }
    export -f mkdir
    runControl 15 initialize-failure "${RETRY_ROOT}" "${NATIVE_ROOT}" "${RETRY_BIN}" \
        install --source "${NO_COMPOSE_SOURCE}"
)
[[ "$(<"${RETRY_ROOT}/mode")" == docker && -d "${RETRY_ROOT}/.bundles" &&
    ! -e "${RETRY_ROOT}/config" ]] || fail 'initialization failure lost its managed state'
runControl 0 initialize-retry "${RETRY_ROOT}" "${NATIVE_ROOT}" "${RETRY_BIN}" \
    install --source "${NO_COMPOSE_SOURCE}"
[[ -d "${RETRY_ROOT}/config" && -L "${RETRY_ROOT}/bundle" &&
    -L "${RETRY_BIN}/padm-docker" ]] || fail 'retry did not finish initialization'

# 写入归属标记前中断，只清理本次临时文件，并允许同根重试。
for signal in INT TERM; do
    INTERRUPTED_ROOT="${TEST_ROOT}/initialize-${signal}"
    INTERRUPTED_BIN="${TEST_ROOT}/initialize-${signal}-bin"
    signalStatus=130
    [[ "${signal}" != TERM ]] || signalStatus=143
    (
        chmod() {
            if [[ "$1" == 0640 && "${2:-}" == "${PADM_DOCKER_INSTALL_DIR}/.mode."* ]]; then
                kill -"${PHASE1_INITIALIZE_SIGNAL}" "${BASHPID:-$$}"
            fi
            command chmod "$@"
        }
        export -f chmod
        export PHASE1_INITIALIZE_SIGNAL=${signal}
        runControl "${signalStatus}" "initialize-${signal}" "${INTERRUPTED_ROOT}" \
            "${NATIVE_ROOT}" "${INTERRUPTED_BIN}" install --source "${NO_COMPOSE_SOURCE}"
    )
    [[ ! -e "${INTERRUPTED_ROOT}/mode" &&
        ! -e "${INTERRUPTED_ROOT}/locks/deployment.lock" &&
        -z "$(find "${INTERRUPTED_ROOT}" -maxdepth 1 -name '.mode.*' -print)" ]] ||
        fail "initialize-${signal}: interruption left bootstrap residue"
    runControl 0 "initialize-${signal}-retry" "${INTERRUPTED_ROOT}" "${NATIVE_ROOT}" \
        "${INTERRUPTED_BIN}" install --source "${NO_COMPOSE_SOURCE}"
    [[ -L "${INTERRUPTED_ROOT}/bundle" && -L "${INTERRUPTED_BIN}/padm-docker" ]] ||
        fail "initialize-${signal}: retry did not finish installation"
done

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

export FAKE_COMPOSE_VERSION=5.6.0
runControl 0 compose-v5 "${TEST_ROOT}/compose-v5" "${NATIVE_ROOT}" "${TEST_ROOT}/compose-v5-bin" install --source "${PROJECT_ROOT}"
[[ -f "${TEST_ROOT}/compose-v5/mode" ]] || fail 'Compose v5 preflight did not initialize state'
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

# 无 PID 的过期锁含残留文件时，清理失败也必须遵守超时。
ORPHAN_LOCK_ROOT="${TEST_ROOT}/orphan-lock"
mkdir -p "${ORPHAN_LOCK_ROOT}/locks/deployment.lock"
printf 'keep\n' >"${ORPHAN_LOCK_ROOT}/locks/deployment.lock/residual"
touch -d '10 seconds ago' "${ORPHAN_LOCK_ROOT}/locks/deployment.lock"
lockStatus=0
PADM_DOCKER_INSTALL_DIR="${ORPHAN_LOCK_ROOT}" PADM_DOCKER_LOCK_TIMEOUT=0 \
    timeout 3 bash -c 'source "$1/docker/lib/bootstrap.sh"; dockerAcquireDeploymentLock' \
    bash "${PROJECT_ROOT}" >"${CONTROL_LOG}" 2>&1 || lockStatus=$?
[[ "${lockStatus}" == 1 ]] || fail "orphan-lock: expected timeout failure, got ${lockStatus}"
grep -q '等待 Docker 部署锁超时' "${CONTROL_LOG}" || fail 'orphan-lock: timeout diagnostic missing'
[[ "$(<"${ORPHAN_LOCK_ROOT}/locks/deployment.lock/residual")" == keep ]] || fail 'orphan-lock: removed unknown file'

LINK_LOCK_ROOT="${TEST_ROOT}/link-lock"
LINK_LOCK_TARGET="${TEST_ROOT}/external-lock"
mkdir -p "${LINK_LOCK_ROOT}/locks" "${LINK_LOCK_TARGET}"
printf '99999999\n' >"${LINK_LOCK_TARGET}/pid"
ln -s "${LINK_LOCK_TARGET}" "${LINK_LOCK_ROOT}/locks/deployment.lock"
lockStatus=0
PADM_DOCKER_INSTALL_DIR="${LINK_LOCK_ROOT}" PADM_DOCKER_LOCK_TIMEOUT=0 \
    bash -c 'source "$1/docker/lib/bootstrap.sh"; dockerAcquireDeploymentLock' \
    bash "${PROJECT_ROOT}" >"${CONTROL_LOG}" 2>&1 || lockStatus=$?
[[ "${lockStatus}" == 1 && -L "${LINK_LOCK_ROOT}/locks/deployment.lock" &&
    "$(<"${LINK_LOCK_TARGET}/pid")" == 99999999 ]] || fail 'lock symlink changed external state'
PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/released-lock" PADM_DOCKER_LOCK_TIMEOUT=1 \
    bash -c '
        source "$1/docker/lib/bootstrap.sh"
        raced=false
        mkdir() {
            if [[ "$*" == "-- ${PADM_DOCKER_INSTALL_DIR}/locks/deployment.lock" && "$raced" == false ]]; then
                raced=true
                return 1
            fi
            command mkdir "$@"
        }
        dockerAcquireDeploymentLock && dockerReleaseDeploymentLock
    ' bash "${PROJECT_ROOT}" || fail 'released lock was treated as an unsafe path'

BROKEN_SOURCE="${TEST_ROOT}/broken-source"
copyBundleFixture "${BROKEN_SOURCE}"
rm -f -- "${BROKEN_SOURCE}/docker/lib/lifecycle.sh"
runControl 13 broken-bundle "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${BROKEN_SOURCE}"
[[ "$(readlink "${DOCKER_ROOT}/bundle")" == "${bundleBefore}" ]] || fail 'failed bundle refresh changed the active bundle'
[[ "$(<"${DOCKER_ROOT}/data/sentinel")" == "keep" ]] || fail 'failed bundle refresh changed persistent data'

for missing in docker/lib/reality-targets.sh shell/core/runtime.sh shell/core/reality_targets.sh shell/core/cores.sh \
    docker/lib/schedule.sh docker/lib/geo.sh docker/lib/control-sync.sh docker/lib/control.sh; do
    incompleteSource="${TEST_ROOT}/incomplete-${missing//\//-}"
    copyBundleFixture "${incompleteSource}"
    rm -f -- "${incompleteSource}/${missing}"
    runControl 13 incomplete-target-module "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" \
        install --source "${incompleteSource}"
    [[ "$(readlink "${DOCKER_ROOT}/bundle")" == "${bundleBefore}" ]] ||
        fail 'incomplete target module changed the active bundle'
done

COMPOSE_SOURCE="${TEST_ROOT}/compose-source"
copyBundleFixture "${COMPOSE_SOURCE}"
printf 'services: {}\n' >"${COMPOSE_SOURCE}/docker/compose.yaml"
runControl 0 install-compose-fixture "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" install --source "${COMPOSE_SOURCE}"
cat >"${DOCKER_ROOT}/deployment.json" <<'EOF'
{
  "schema_version": 1,
  "mode": "docker",
  "padm_version": "test",
  "core": {"type": "xray"},
  "host_integrations": [],
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

# 使用生产 Compose 入口核验有界执行，不只断言调用方设置了超时变量。
DOCKER_COMPOSE_TIMEOUT=10 runControl 0 compose-bounded "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" status
for invalidTimeout in 0 31 invalid; do
    DOCKER_COMPOSE_TIMEOUT=${invalidTimeout} runControl 2 compose-invalid-timeout \
        "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" status
done
started=${SECONDS}
FAKE_DOCKER_MODE=compose-slow DOCKER_COMPOSE_TIMEOUT=1 \
    runControl 14 compose-timeout "${DOCKER_ROOT}" "${NATIVE_ROOT}" "${CLI_DIR}" status
((SECONDS - started < 6)) || fail 'bounded Compose command did not terminate promptly'

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
