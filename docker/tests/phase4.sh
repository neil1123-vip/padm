#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase4.XXXXXX")
MOCK_BIN="${TEST_ROOT}/bin"
DOCKER_LOG="${TEST_ROOT}/docker.log"
CONTROL_LOG="${TEST_ROOT}/control.log"
DOCKER_ROOT="${TEST_ROOT}/state"
FAIL2BAN_INSPECT="${TEST_ROOT}/fail2ban-inspect.json"
SOURCE_BOUNDARY="${TEST_ROOT}/source-boundary.sh"
FAIL2BAN_CONTAINER=abcdef123456
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
if [[ "${1:-}" == "--format=%a" ]]; then printf '600\n'; else command -p stat "$@"; fi
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
    if [[ " ${*} " == *' net-fail2ban preflight fail2ban 24444,24445 unowned '* &&
        " ${*} " == *" --file ${FAKE_DOCKER_ROOT:?}/compose.json "* ]]; then
        jq -e 'any(.host_integrations[]; .type == "fail2ban")' \
            "${FAKE_DOCKER_ROOT:?}/config/spec.json" >/dev/null || exit 1
        case "${FAKE_DOCKER_MODE:-ok}" in
        fail2ban-cleanup-proof-fail) exit 1 ;;
        fail2ban-cleanup-proof-term-fail) kill -TERM "${PPID}"; exit 1 ;;
        fail2ban-cleanup-proof-term)
            if [[ ! -e "${FAKE_DOCKER_SIGNAL_ONCE:?}" ]]; then
                : >"${FAKE_DOCKER_SIGNAL_ONCE}"
                kill -TERM "${PPID}"
            fi
            ;;
        esac
        [[ ! -e "${FAKE_DOCKER_ROOT}/data/net/fail2ban/fail2ban.state" ]] || exit 1
    fi
    if [[ " ${*} " == *' up -d '* && "${FAKE_DOCKER_MODE:-ok}" == fail-next-up &&
        ! -e "${FAKE_DOCKER_FAIL_ONCE:?}" ]]; then
        : >"${FAKE_DOCKER_FAIL_ONCE}"
        exit 1
    fi
    if [[ " ${*} " == *' up -d '* && " ${*} " == *' --no-deps '* &&
        " ${*} " == *' net-fail2ban --remove-orphans ' ]]; then
        jq -n --arg root "${FAKE_DOCKER_ROOT:?}" --arg id "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" \
            --slurpfile spec "${FAKE_DOCKER_ROOT}/config/spec.json" \
            --slurpfile compose "${FAKE_DOCKER_ROOT}/compose.json" '
          $compose[0].services["net-fail2ban"] as $service |
          [{
            Id: ($id + ("a" * (64 - ($id | length)))),
            State: {Status: "running", Running: true, Restarting: false,
              Paused: false, Dead: false, OOMKilled: false, ExitCode: 0, Error: ""},
            Config: {
              Image: $spec[0].images.net, Cmd: $service.command,
              Entrypoint: ["/usr/local/bin/padm-entrypoint"], User: "0:0",
              Labels: ($service.labels + {
                "com.docker.compose.project": "padm-docker",
                "com.docker.compose.project.working_dir": $root,
                "com.docker.compose.project.config_files": ($root + "/compose.json"),
                "com.docker.compose.service": "net-fail2ban",
                "com.docker.compose.oneoff": "False"
              })
            },
            HostConfig: {
              NetworkMode: $service.network_mode,
              ReadonlyRootfs: $service.read_only, Privileged: false,
              RestartPolicy: {Name: $service.restart},
              CapAdd: $service.cap_add, CapDrop: $service.cap_drop,
              Tmpfs: ($service.tmpfs | map({key: split(":")[0], value: "rw"}) | from_entries)
            },
            Mounts: ($service.volumes | map({
              Type: .type, Source: (.source | sub("^\\$\\{PADM_NET_ROOT\\}"; $root)),
              Destination: .target, RW: (.read_only | not)
            }))
          }]
        ' >"${FAKE_DOCKER_FAIL2BAN_INSPECT:?}" || exit 1
        rm -f -- "${FAKE_DOCKER_FAIL2BAN_STOPPED:?}"
    fi
    ;;
ps)
    [[ "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ]] || exit 0
    case "${FAKE_DOCKER_MODE:-ok}" in
    fail2ban-absent) ;;
    fail2ban-ps-fail) exit 1 ;;
    fail2ban-orphan) printf '%s\n' "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" ;;
    fail2ban-duplicate) printf '%s\nfedcba654321\n' "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" ;;
    fail2ban-invalid-id) printf 'padm-net-fail2ban-1\n' ;;
    *)
        if [[ -f "${FAKE_DOCKER_FAIL2BAN_INSPECT:?}" ]]; then
            printf '%s\n' "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}"
        fi
        ;;
    esac
    ;;
container)
    [[ "$*" == "container inspect ${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" ]] || exit 1
    filter=${FAKE_DOCKER_INSPECT_FILTER:-.}
    if [[ -e "${FAKE_DOCKER_FAIL2BAN_STOPPED:?}" ]]; then
        filter+=' | .[0].State = {Status:"exited",Running:false,Restarting:false,Paused:false,Dead:false,OOMKilled:false,ExitCode:0,Error:""}'
        case "${FAKE_DOCKER_MODE:-ok}" in
        fail2ban-stop-137) filter+=' | .[0].State.ExitCode = 137' ;;
        fail2ban-stop-owner-drift) filter+=' | .[0].Id = ("f" * 64)' ;;
        esac
    fi
    jq "${filter}" "${FAKE_DOCKER_FAIL2BAN_INSPECT:?}"
    ;;
stop)
    [[ "$*" == "stop ${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" ]] || exit 1
    [[ "${FAKE_DOCKER_MODE:-ok}" != fail2ban-stop-fail ]] || exit 42
    : >"${FAKE_DOCKER_FAIL2BAN_STOPPED:?}"
    case "${FAKE_DOCKER_MODE:-ok}" in
    fail2ban-stop-137|fail2ban-cleanup-proof-fail|fail2ban-cleanup-proof-term-fail) ;;
    *) rm -f -- "${FAKE_DOCKER_ROOT:?}/data/net/fail2ban/fail2ban.state" ;;
    esac
    ;;
rm)
    [[ "$*" == "rm ${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" &&
        ! -e "${FAKE_DOCKER_ROOT:?}/data/net/fail2ban/fail2ban.state" &&
        ! -L "${FAKE_DOCKER_ROOT}/data/net/fail2ban/fail2ban.state" ]] || exit 1
    "${BASH_SOURCE[0]}" container inspect "${FAKE_DOCKER_FAIL2BAN_CONTAINER}" |
        jq -e 'length == 1 and (.[0].State |
          .Status == "exited" and .Running == false and .Restarting == false and
          .Paused == false and .Dead == false and .OOMKilled == false and
          .ExitCode == 0 and .Error == "")' >/dev/null || exit 1
    rm -f -- "${FAKE_DOCKER_FAIL2BAN_INSPECT:?}" "${FAKE_DOCKER_FAIL2BAN_STOPPED:?}"
    ;;
exec)
    if [[ "$#" -eq 5 && "${2:-}" == "-i" && "${3:-}" == "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" &&
        "${4:-}" == python3 && "${5:-}" == - ]]; then
        cat >/dev/null
        case "${FAKE_DOCKER_MODE:-ok}" in
        fail2ban-audit-drift)
            printf 'simulated loaded action drift\n' >&2
            exit 1
            ;;
        fail2ban-audit-query-fail)
            printf 'simulated fail2ban query failure\n' >&2
            exit 1
            ;;
        esac
        exit 0
    fi
    if [[ "$*" == "exec ${FAKE_DOCKER_FAIL2BAN_CONTAINER:?} sh /usr/local/bin/padm-entrypoint fail2ban-health" ]]; then
        [[ "${FAKE_DOCKER_MODE:-ok}" != fail2ban-owner-drift ]] || exit 1
        exit 0
    fi
    [[ "${2:-}" == "${FAKE_DOCKER_FAIL2BAN_CONTAINER:?}" &&
        "${3:-}" == fail2ban-client ]] || exit 1
    if [[ "$#" -eq 5 && "${4:-}" == status && "${5:-}" == padm-nginx ]]; then
        output=$'Status for the jail: padm-nginx\nCurrently banned: 1\nBanned IP list: 192.0.2.7'
    elif [[ "$#" -eq 7 && "${4:-}" == set && "${5:-}" == padm-nginx &&
        "${6:-}" == unbanip ]]; then
        output=1
    else
        exit 1
    fi
    if [[ "${FAKE_DOCKER_MODE:-ok}" == fail2ban-client-fail ]]; then
        printf 'simulated fail2ban-client failure\n' >&2
        exit 37
    fi
    printf '%s\n' "${output}"
    ;;
run)
    if [[ " ${*} " == *'ssl.cert_time_to_seconds'* ]]; then
        [[ "${FAKE_DOCKER_MODE:-ok}" != tls-validity-fail ]]
        exit $?
    fi
    if [[ " ${*} " == *'DNS CNAME probe requires nslookup'* ]]; then
        exit 0
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

# 只替换 Nginx 现场边界，来源计划、输入校验、停止证明和两阶段启动仍走生产函数。
cat >"${SOURCE_BOUNDARY}" <<'EOF'
dockerFail2banSourceContainer() {
    local listener=$1 family=$2
    jq -ec --arg listener "${listener}" --arg family "${family}" '
      . as $spec | [.core.protocols[] | select(.listener_id == $listener and .id == 21 and
        (.address_families | index($family)) != null)] |
      if length == 1 then .[0] as $entry |
        {id:("b"*64),started_at:"2026-10-10T01:00:00.000000000Z",restart_count:0,
         public_port:$entry.public_port,internal_port:($entry.websocket.tls_port // 8443),
         domain:($spec.tls.domain | ascii_downcase),addresses:["192.0.2.1"],
         networks:[{name:"padm-docker",id:("c"*64)}]}
      else error("invalid source tuple") end
    ' "${FAKE_DOCKER_ROOT:?}/config/spec.json"
}
dockerFail2banSourceWitness() {
    local listener=$1 address=$2 family=ipv4 snapshot number=0
    [[ "${address}" != *:* ]] || family=ipv6
    snapshot=$(dockerFail2banSourceContainer "${listener}" "${family}") || return 1
    [[ ! -f "${FAKE_DOCKER_WITNESS_COUNT:?}" ]] || number=$(<"${FAKE_DOCKER_WITNESS_COUNT}")
    number=$((number + 1))
    printf '%s\n' "${number}" >"${FAKE_DOCKER_WITNESS_COUNT}"
    printf 'source-witness %s %s %s %048x\n' "${listener}" "${family}" "${address}" "${number}" \
        >>"${FAKE_DOCKER_LOG:?}"
    printf 'source-challenge=%s\n' "${snapshot}" >&2
    if [[ "${listener}" == entry-alt-ws ]]; then
        case "${FAKE_DOCKER_MODE:-ok}" in
        fail2ban-source-last-fail) return 1 ;;
        fail2ban-source-last-once)
            if [[ ! -e "${FAKE_DOCKER_SOURCE_FAIL_ONCE:?}" ]]; then
                : >"${FAKE_DOCKER_SOURCE_FAIL_ONCE}"
                return 1
            fi
            ;;
        esac
    fi
    printf 'source-verified=%s\n' "${snapshot}" >&2
}
EOF

runControl() {
    local expected=$1 name=$2 actual=0
    local -a command=(bash -u -c '
      source "$1"
      source "${FAKE_DOCKER_SOURCE_BOUNDARY:?}"
      shift
      dockerMain "$@"
    ' test "${PROJECT_ROOT}/install-docker.sh")
    shift 2
    if [[ "${1:-}" == configure ]]; then
        set -- "$@" --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
            --control-bundle "${CONFIGURE_CONTROL}"
    elif [[ "${1:-}" == edit ]]; then
        set -- "$@" --manifest "${CONFIGURE_MANIFEST}" --bundle "${CONFIGURE_BUNDLE}" \
            --control-bundle "${CONFIGURE_CONTROL}"
    elif [[ "${1:-}" == disable-prepare ]]; then
        shift
        command=(bash -u -c '
          source "$1"
          source "${FAKE_DOCKER_SOURCE_BOUNDARY:?}"
          dockerFail2banDisablePrepare "$2"
        ' test "${PROJECT_ROOT}/install-docker.sh")
    elif [[ "${1:-}" == shared-compose || "${1:-}" == restore-backup ]]; then
        local directOperation=$1
        shift
        command=(bash -u -c '
          source "$1"
          source "${FAKE_DOCKER_SOURCE_BOUNDARY:?}"
          directOperation=$2
          shift 2
          dockerHostPreflight || exit 10
          dockerLockInstalledDeployment || exit $?
          DOCKER_FAIL2BAN_SOURCE_IPV4=
          DOCKER_FAIL2BAN_SOURCE_IPV6=
          if [[ "${directOperation}" == restore-backup ]]; then
              DOCKER_CONFIG_BACKUP=$1
              DOCKER_CONFIG_SWITCHED=1
              dockerFail2banSourceInputsPrepare "${DOCKER_CONFIG_BACKUP}/config/spec.json" \
                  "${FAKE_DOCKER_ROOT}/config/spec.json" || exit 15
              dockerRestoreConfiguration
          else
              if [[ -n "${PADM_DOCKER_FAIL2BAN_SOURCE_IPV4:-}" ||
                  -n "${PADM_DOCKER_FAIL2BAN_SOURCE_IPV6:-}" ]]; then
                  dockerFail2banSourceInputsPrepare "${FAKE_DOCKER_ROOT}/config/spec.json" || exit 15
              fi
              dockerComposeRun "$@"
          fi
          status=$?
          dockerReleaseDeploymentLock
          exit "${status}"
        ' test "${PROJECT_ROOT}/install-docker.sh" "${directOperation}")
    elif [[ "${1:-}" == apply-cancel ]]; then
        shift
        command=(bash -u -c '
          source "$1"
          source "${FAKE_DOCKER_SOURCE_BOUNDARY:?}"
          dockerHostPreflight || exit 10
          dockerLockInstalledDeployment || exit $?
          dockerConfigureReleasePrepare "$2" "$3" "$4" || exit $?
          dockerConfigureApply "$5" "" "" interactive <<<n
          status=$?
          dockerReleaseDeploymentLock
          dockerCleanupStagedBundle
          dockerManifestCleanup
          exit "${status}"
        ' test "${PROJECT_ROOT}/install-docker.sh"
            "${CONFIGURE_MANIFEST}" "${CONFIGURE_BUNDLE}" "${CONFIGURE_CONTROL}")
    elif [[ "${1:-}" == apply-staged ]]; then
        shift
        command=(bash -u -c '
          source "$1"
          source "${FAKE_DOCKER_SOURCE_BOUNDARY:?}"
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
        PADM_DOCKER_FAIL2BAN_SOURCE_IPV4="${PADM_DOCKER_FAIL2BAN_SOURCE_IPV4-198.51.100.9}" \
        FAKE_DOCKER_LOG="${DOCKER_LOG}" FAKE_DOCKER_MODE="${FAKE_DOCKER_MODE:-ok}" \
        FAKE_DOCKER_FAIL2BAN_CONTAINER="${FAIL2BAN_CONTAINER}" \
        FAKE_DOCKER_FAIL2BAN_INSPECT="${FAIL2BAN_INSPECT}" \
        FAKE_DOCKER_ROOT="${DOCKER_ROOT}" \
        FAKE_DOCKER_FAIL2BAN_STOPPED="${TEST_ROOT}/fail2ban-stopped" \
        FAKE_DOCKER_INSPECT_FILTER="${FAKE_DOCKER_INSPECT_FILTER:-.}" \
        FAKE_DOCKER_FAIL_ONCE="${TEST_ROOT}/fail-once" \
        FAKE_DOCKER_SIGNAL_ONCE="${TEST_ROOT}/signal-once" \
        FAKE_DOCKER_SOURCE_BOUNDARY="${SOURCE_BOUNDARY}" \
        FAKE_DOCKER_WITNESS_COUNT="${TEST_ROOT}/witness-count" \
        FAKE_DOCKER_SOURCE_FAIL_ONCE="${TEST_ROOT}/source-fail-once" \
        "${command[@]}" "$@" >"${CONTROL_LOG}" 2>&1 || actual=$?
    if [[ "${actual}" -ne "${expected}" ]]; then
        sed 's/^/  /' "${CONTROL_LOG}" >&2
        fail "${name}: expected rc=${expected}, got rc=${actual}"
    fi
    if [[ "${1:-}" == fail2ban ]]; then
        [[ -z "$(find "${DOCKER_ROOT}" -maxdepth 1 -name '.fail2ban-check.*' -print -quit)" ]] ||
            fail "${name}: Fail2ban maintenance leaked its validation candidate"
    fi
}

rejectFail2ban() {
    : >"${DOCKER_LOG}"
    runControl "$@"
    ! grep -Eq '^(exec|run|start|stop|restart) |^compose .* (run|up|start|stop|restart)( |$)' "${DOCKER_LOG}" ||
        fail 'rejected Fail2ban maintenance executed or started a container'
}

fail2banManagedSnapshot() {
    tar --sort=name --numeric-owner -cf - -C "${DOCKER_ROOT}" \
        compose.json deployment.json images.env config secrets data logs | sha256sum
}

# 公共 CLI 只精确转发专项参数；不为测试扩大它可接受的发布参数。
(
    source "${PROJECT_ROOT}/install-docker.sh"
    dockerEditCommand() { printf '%s\n' "$*"; }
    for action in enable settings; do
        output=$(dockerFail2banCommand "${action}" 24444,24445 6 600 3600 --preview)
        [[ "${output}" == "--fail2ban-${action} 24444,24445 6 600 3600 --preview" ]] ||
            fail "Fail2ban ${action} preview 参数未精确转发"
        output=$(dockerFail2banCommand "${action}" 24444 7 900 7200 --confirm PADM-DOCKER-EDIT)
        [[ "${output}" == "--fail2ban-${action} 24444 7 900 7200 --confirm PADM-DOCKER-EDIT" ]] ||
            fail "Fail2ban ${action} confirm 参数未精确转发"
        for suffix in extra bad-confirm release; do
            status=0
            case "${suffix}" in
            extra) args=(--preview extra) ;;
            bad-confirm) args=(--confirm wrong) ;;
            release) args=(--manifest fixture) ;;
            esac
            output=$(dockerFail2banCommand "${action}" 24444 6 600 3600 "${args[@]}") || status=$?
            [[ "${status}" -eq 2 && -z "${output}" ]] ||
                fail "Fail2ban ${action} 接受多余参数、错误确认或发布参数"
        done
    done
)

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
      .schema_version = 2 |
      .core.protocols = [{id: 21, listener_id: "entry-main-ws", server: "proxy.example.com", public_port: 24444,
        address_families: ["ipv4"], name: "main-ws",
        uuid: "22222222-2222-4222-8222-222222222222",
        websocket: {domain: "proxy.example.com", path: "websocket_path", backend_port: 31297, tls_port: 8443}},
       {id: 21, listener_id: "entry-alt-ws", server: "proxy.example.com", public_port: 24445,
        address_families: ["ipv4"], name: "alt-ws",
        uuid: "33333333-3333-4333-8333-333333333333",
        websocket: {domain: "proxy.example.com", path: "alternate_path", backend_port: 31296, tls_port: 8444}}] |
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
  devices: [], schedules: [], settings: {log_file: "access.log", ports: [24444, 24445],
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
if [[ "$(command -p uname -s)" == Linux ]]; then
    [[ "$(command -p stat --format=%a "${DOCKER_ROOT}/config/spec.json")" == 600 ]] ||
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
# 已部署时，候选配置与在线归属从不同只读输入核对。
: >"${DOCKER_LOG}"
runControl 0 wireguard-reconfigure configure --spec "${WIREGUARD_SPEC}"
grep -Fq "${DOCKER_ROOT}/data/net/wireguard:/run/padm-wireguard-owner:ro net-wireguard preflight" \
    "${DOCKER_LOG}" || fail 'WireGuard candidate did not mount live ownership read-only'
rejectFail2ban 15 fail2ban-not-configured-status fail2ban status
rejectFail2ban 15 fail2ban-not-configured-unban fail2ban unban 192.0.2.7

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
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 15 fail2ban-source-missing configure --spec "${FAIL2BAN_SPEC}"
! grep -Eq '^compose .* up -d |^(stop|rm) ' "${DOCKER_LOG}" ||
    fail 'Missing Fail2ban source input stopped or started the deployment'
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${BEFORE_TLS_RECONFIGURE}" ]] ||
    fail 'Missing Fail2ban source input changed deployment'
: >"${DOCKER_LOG}"
runControl 0 fail2ban configure --spec "${FAIL2BAN_SPEC}"
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Fail2ban configure did not verify both protected IPv4 entry ports'
python3 - "${DOCKER_LOG}" <<'PY'
import sys
commands = open(sys.argv[1], encoding="utf-8").read().splitlines()
starts = [(i, line) for i, line in enumerate(commands) if " up -d " in line]
witnesses = [i for i, line in enumerate(commands) if line.startswith("source-witness ")]
assert len(starts) == 2 and starts[0][0] < witnesses[0] < witnesses[1] < starts[1][0]
assert " xray " in starts[0][1] and " nginx " in starts[0][1]
assert " net-fail2ban --remove-orphans" not in starts[0][1]
assert " --no-deps " in starts[1][1] and " net-fail2ban --remove-orphans" in starts[1][1]
assert " acme --remove-orphans" not in starts[0][1]
PY
grep -q 'access_log /var/log/nginx/access.log combined;' "${DOCKER_ROOT}/config/nginx/default.conf" ||
    fail 'Nginx real-source access log was not enabled'
grep -qF "before = iptables.conf" "${DOCKER_ROOT}/config/net/fail2ban/padm-docker-user.conf" ||
    fail 'Fail2ban does not inherit native address-family commands'
for operation in start stop flush check ban unban; do
    grep -qF "action${operation} = sh /usr/local/bin/padm-entrypoint fail2ban-action ${operation} \"\$PADM_FAIL2BAN_TOKEN\" <iptables>" \
        "${DOCKER_ROOT}/config/net/fail2ban/padm-docker-user.conf" ||
        fail "Fail2ban ${operation} bypasses the bound ownership helper"
done
! grep -qE ' -[FX] | -[ID] DOCKER-USER' "${DOCKER_ROOT}/config/net/fail2ban/padm-docker-user.conf" ||
    fail 'Fail2ban action mutates firewall rules without ownership verification'
grep -qF 'port="24444,24445"' "${DOCKER_ROOT}/config/net/fail2ban/padm.local" ||
    fail 'Fail2ban did not preserve all protected published ports'
grep -qx 'allowipv6 = no' "${DOCKER_ROOT}/config/net/fail2ban/fail2ban.local" ||
    fail 'IPv4-only Fail2ban unnecessarily requires IPv6'
grep -q '^logtarget = STDOUT$' "${DOCKER_ROOT}/config/net/fail2ban/fail2ban.local" ||
    fail 'Fail2ban does not log to stdout on a read-only root'
jq -e '
  .services["net-fail2ban"].network_mode == "host" and
  .services["net-fail2ban"].cap_add == ["NET_ADMIN"] and
  ((.services.nginx.cap_add // []) | length) == 0
' "${DOCKER_ROOT}/compose.json" >/dev/null || fail 'Fail2ban privilege boundary is wrong'
grep -q 'net-fail2ban preflight fail2ban 24444,24445' "${DOCKER_LOG}" || fail 'Fail2ban preflight was not called for all ports'
: >"${DOCKER_LOG}"
runControl 0 fail2ban-installed-validate validate
grep -q 'net-fail2ban preflight fail2ban 24444,24445 owned' "${DOCKER_LOG}" ||
    fail 'Installed Fail2ban validation did not verify its existing owner'

# 维护命令只使用刚由最终阶段创建的当前容器和固定 jail。
cp -p -- "${FAIL2BAN_INSPECT}" "${TEST_ROOT}/fail2ban-inspect.fixture"
printf 'existing-nginx-access-log\n' >>"${DOCKER_ROOT}/logs/nginx/access.log"
FAIL2BAN_MAINTENANCE_BEFORE=$(fail2banManagedSnapshot)
: >"${DOCKER_LOG}"
runControl 0 fail2ban-status fail2ban status
grep -qx 'Currently banned: 1' "${CONTROL_LOG}" || fail 'Fail2ban status hid the client output'
grep -qxF "exec ${FAIL2BAN_CONTAINER} fail2ban-client status padm-nginx" "${DOCKER_LOG}" ||
    fail 'Fail2ban status did not target the managed container and jail'
[[ "$(grep '^exec ' "${DOCKER_LOG}")" == "exec -i ${FAIL2BAN_CONTAINER} python3 -"$'\n'"exec ${FAIL2BAN_CONTAINER} sh /usr/local/bin/padm-entrypoint fail2ban-health"$'\n'"exec ${FAIL2BAN_CONTAINER} fail2ban-client status padm-nginx" ]] ||
    fail 'Fail2ban status did not audit loaded actions before the maintenance client'
for ip in 192.0.2.7 2001:db8::1 ::ffff:192.0.2.7; do
    : >"${DOCKER_LOG}"
    runControl 0 fail2ban-unban fail2ban unban "${ip}"
    grep -qxF "exec ${FAIL2BAN_CONTAINER} fail2ban-client set padm-nginx unbanip ${ip}" "${DOCKER_LOG}" ||
        fail 'Fail2ban unban changed the literal IP, container or jail'
    [[ "$(grep '^exec ' "${DOCKER_LOG}")" == "exec -i ${FAIL2BAN_CONTAINER} python3 -"$'\n'"exec ${FAIL2BAN_CONTAINER} sh /usr/local/bin/padm-entrypoint fail2ban-health"$'\n'"exec ${FAIL2BAN_CONTAINER} fail2ban-client set padm-nginx unbanip ${ip}" ]] ||
        fail 'Fail2ban unban did not audit loaded actions before the maintenance client'
done
FAKE_DOCKER_MODE=fail2ban-client-fail runControl 37 fail2ban-status-client-error fail2ban status
grep -qx 'simulated fail2ban-client failure' "${CONTROL_LOG}" ||
    fail 'Fail2ban status hid the client error'
FAKE_DOCKER_MODE=fail2ban-client-fail runControl 37 fail2ban-unban-client-error fail2ban unban 192.0.2.7
! grep -Eq '^(run|start|restart) |^compose .* (run|up|start|restart)( |$)' "${DOCKER_LOG}" ||
    fail 'Fail2ban maintenance automatically started a container'

for auditMode in fail2ban-audit-drift fail2ban-audit-query-fail fail2ban-owner-drift; do
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${auditMode}" runControl 15 "${auditMode}-status" fail2ban status
    grep -qxF "exec -i ${FAIL2BAN_CONTAINER} python3 -" "${DOCKER_LOG}" ||
        fail "${auditMode}: status skipped the loaded-action audit"
    ! grep -qF "fail2ban-client" "${DOCKER_LOG}" ||
        fail "${auditMode}: status executed the maintenance client after audit failure"
    ! grep -Eq '^(run|start|restart) |^compose .* (run|up|start|restart)( |$)' "${DOCKER_LOG}" ||
        fail "${auditMode}: status started a container after audit failure"
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${auditMode}" runControl 15 "${auditMode}-unban" fail2ban unban 192.0.2.7
    grep -qxF "exec -i ${FAIL2BAN_CONTAINER} python3 -" "${DOCKER_LOG}" ||
        fail "${auditMode}: unban skipped the loaded-action audit"
    ! grep -qF "fail2ban-client" "${DOCKER_LOG}" ||
        fail "${auditMode}: unban executed the maintenance client after audit failure"
    ! grep -Eq '^(run|start|restart) |^compose .* (run|up|start|restart)( |$)' "${DOCKER_LOG}" ||
        fail "${auditMode}: unban started a container after audit failure"
done

rejectFail2ban 2 fail2ban-missing-command fail2ban
rejectFail2ban 2 fail2ban-arbitrary-jail fail2ban status sshd
rejectFail2ban 2 fail2ban-status-option fail2ban status --all
rejectFail2ban 2 fail2ban-missing-ip fail2ban unban
rejectFail2ban 2 fail2ban-extra-ip fail2ban unban 192.0.2.7 192.0.2.8
rejectFail2ban 2 fail2ban-unban-jail fail2ban unban padm-nginx 192.0.2.7
rejectFail2ban 2 fail2ban-arbitrary-command fail2ban restart
for ip in '' --all -192.0.2.7 192.0.2.7/32 2001:db8::1/128 fe80::1%eth0 \
    '[2001:db8::1]' '192.0.2.7;id' '192.0.2.7 192.0.2.8' 192.0.2.999 \
    192.000.2.7 2001:db8:::1 ::ffff:192.000.2.7 ' 192.0.2.7' '192.0.2.7 '; do
    rejectFail2ban 2 fail2ban-invalid-ip fail2ban unban "${ip}"
done
for mode in fail2ban-absent fail2ban-duplicate fail2ban-invalid-id; do
    FAKE_DOCKER_MODE="${mode}" rejectFail2ban 15 "${mode}" fail2ban status
done
FAKE_DOCKER_INSPECT_FILTER='.[0].HostConfig.CapAdd = ["CAP_NET_ADMIN"]' \
    runControl 0 fail2ban-canonical-capability fail2ban status
while read -r name filter; do
    FAKE_DOCKER_INSPECT_FILTER="${filter}" rejectFail2ban 15 "fail2ban-${name}" fail2ban status
done <<'EOF'
stopped .[0].State.Running = false
restarting .[0].State.Restarting = true
compose-project .[0].Config.Labels["com.docker.compose.project"] = "foreign"
compose-root .[0].Config.Labels["com.docker.compose.project.working_dir"] = "/foreign"
compose-file .[0].Config.Labels["com.docker.compose.project.config_files"] = "/foreign/compose.json"
compose-service .[0].Config.Labels["com.docker.compose.service"] = "foreign"
compose-oneoff .[0].Config.Labels["com.docker.compose.oneoff"] = "True"
padm-mode .[0].Config.Labels["io.padm.mode"] = "native"
padm-project .[0].Config.Labels["io.padm.project"] = "foreign"
padm-component .[0].Config.Labels["io.padm.component"] = "foreign"
padm-release .[0].Config.Labels["io.padm.release"] = "0.0.0"
image .[0].Config.Image = "foreign:latest"
command .[0].Config.Cmd = ["fail2ban", "1"]
entrypoint .[0].Config.Entrypoint = ["/bin/sh"]
user .[0].Config.User = "65534:65534"
network .[0].HostConfig.NetworkMode = "bridge"
restart-policy .[0].HostConfig.RestartPolicy.Name = "unless-stopped"
readonly-root .[0].HostConfig.ReadonlyRootfs = false
privileged .[0].HostConfig.Privileged = true
cap-add .[0].HostConfig.CapAdd += ["SYS_ADMIN"]
cap-drop .[0].HostConfig.CapDrop = []
tmpfs .[0].HostConfig.Tmpfs["/foreign"] = "rw"
mount-type .[0].Mounts[0].Type = "volume"
mount-source .[0].Mounts[0].Source = "/foreign/config"
mount-target .[0].Mounts[0].Destination = "/foreign/config"
mount-write .[0].Mounts[0].RW = true
extra-mount .[0].Mounts += [{Type:"bind",Source:"/foreign",Destination:"/foreign",RW:true}]
inspect-empty []
inspect-multiple . + .
EOF
FAKE_DOCKER_INSPECT_FILTER='.[0].State.Running = false' \
    rejectFail2ban 15 fail2ban-stopped-unban fail2ban unban 192.0.2.7
FAKE_DOCKER_INSPECT_FILTER='.[0].Mounts[0].Source = "/foreign/config"' \
    rejectFail2ban 15 fail2ban-foreign-unban fail2ban unban 192.0.2.7
for config in padm-docker-user.conf padm.local; do
    configFile="${DOCKER_ROOT}/config/net/fail2ban/${config}"
    cp -p -- "${configFile}" "${TEST_ROOT}/${config}.backup"
    if [[ "${config}" == padm-docker-user.conf ]]; then
        sed 's/^actionunban = .*/actionunban = <iptables> -F DOCKER-USER/' "${configFile}" \
            >"${TEST_ROOT}/fail2ban-drift.conf"
    else
        sed 's/^enabled = true$/enabled = false/' "${configFile}" >"${TEST_ROOT}/fail2ban-drift.conf"
    fi
    cp -- "${TEST_ROOT}/fail2ban-drift.conf" "${configFile}"
    ! cmp -s -- "${TEST_ROOT}/${config}.backup" "${configFile}" ||
        fail 'Fail2ban configuration drift fixture did not change its input'
    FAIL2BAN_DRIFT_BEFORE=$(fail2banManagedSnapshot)
    rejectFail2ban 15 "fail2ban-drift-status-${config}" fail2ban status
    rejectFail2ban 15 "fail2ban-drift-unban-${config}" fail2ban unban 192.0.2.7
    [[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DRIFT_BEFORE}" ]] ||
        fail 'rejected Fail2ban configuration drift modified managed files'
    cp -p -- "${TEST_ROOT}/${config}.backup" "${configFile}"
done
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_MAINTENANCE_BEFORE}" ]] ||
    fail 'Fail2ban status or unban modified managed files'

# 停用先验证旧 owner 和正常清理，候选预览、取消及失败不能借机重启或删库。
FAIL2BAN_DISABLED_SPEC="${TEST_ROOT}/fail2ban-disabled.json"
# 专项编辑沿用既有 schema 迁移，完整对照必须使用同一规范化基线。
(
    source "${PROJECT_ROOT}/install-docker.sh"
    dockerConfigureSpecMigrate "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/fail2ban-normalized.json"
)
jq '.host_integrations |= map(select(.type != "fail2ban"))' \
    "${TEST_ROOT}/fail2ban-normalized.json" >"${FAIL2BAN_DISABLED_SPEC}"
printf 'persistent-fail2ban-sqlite-fixture\n' >"${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3"
FAIL2BAN_SQLITE_HASH=$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")
writeFail2banOwnerState() {
    printf 'schema_version=2\ntoken=%s\nchain=padm-f2b-aaaaaaaaaaaa\nports=24444,24445\nipv6=no\n' \
        "$(printf 'a%.0s' {1..32})" >"${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
    chmod 0600 "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
    cp -p -- "${TEST_ROOT}/fail2ban-inspect.fixture" "${FAIL2BAN_INSPECT}"
    rm -f -- "${TEST_ROOT}/fail2ban-stopped"
}
assertFail2banDisablePreserved() {
    cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
        fail 'rejected Fail2ban disable changed the installed spec'
    [[ "$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")" == "${FAIL2BAN_SQLITE_HASH}" ]] ||
        fail 'Fail2ban disable deleted or changed its persistent SQLite'
    ! grep -Eq '^compose .* (up|down|restart|stop)( |$)|^(rm|start|restart) ' "${DOCKER_LOG}" ||
        fail 'rejected Fail2ban disable restarted or removed a container'
}
writeFail2banOwnerState
FAIL2BAN_DISABLE_BEFORE=$(fail2banManagedSnapshot)
: >"${DOCKER_LOG}"
runControl 0 fail2ban-disable-preview edit --fail2ban-off --preview
! grep -q "^stop " "${DOCKER_LOG}" || fail 'Fail2ban disable preview stopped the owner'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_BEFORE}" ]] ||
    fail 'Fail2ban disable preview changed managed files'
: >"${DOCKER_LOG}"
runControl 0 fail2ban-disable-cancel apply-cancel "${FAIL2BAN_DISABLED_SPEC}"
! grep -q "^stop " "${DOCKER_LOG}" || fail 'Fail2ban disable cancellation stopped the owner'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_BEFORE}" ]] ||
    fail 'Fail2ban disable cancellation changed managed files'
rejectFail2ban 2 fail2ban-disable-missing-confirm fail2ban disable
rejectFail2ban 2 fail2ban-disable-bad-confirm fail2ban disable --confirm wrong
rejectFail2ban 2 fail2ban-disable-extra-arg fail2ban disable --preview extra
rejectFail2ban 2 fail2ban-disable-other-edit fail2ban disable --site-default --preview
rejectFail2ban 2 fail2ban-disable-import edit --fail2ban-off --spec "${FAIL2BAN_SPEC}" --preview
cp -p "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/fail2ban-enabled.spec"
cp "${FAIL2BAN_DISABLED_SPEC}" "${DOCKER_ROOT}/config/spec.json"
rejectFail2ban 1 fail2ban-disable-spec-deployment-mismatch disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
cp -p "${DOCKER_ROOT}/deployment.json" "${TEST_ROOT}/fail2ban-enabled.deployment"
jq '.host_integrations |= map(select(.type != "fail2ban"))' "${TEST_ROOT}/fail2ban-enabled.deployment" \
    >"${DOCKER_ROOT}/deployment.json"
rejectFail2ban 1 fail2ban-disable-spec-compose-mismatch disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
cp -p "${DOCKER_ROOT}/compose.json" "${TEST_ROOT}/fail2ban-enabled.compose"
jq 'del(.services["net-fail2ban"])' "${TEST_ROOT}/fail2ban-enabled.compose" >"${DOCKER_ROOT}/compose.json"
cp -p "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state" "${TEST_ROOT}/fail2ban-owner.fixture"
FAIL2BAN_RESIDUAL_BEFORE=$(fail2banManagedSnapshot)
FAKE_DOCKER_MODE=fail2ban-absent rejectFail2ban 1 fail2ban-disabled-residual-state \
    disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_RESIDUAL_BEFORE}" ]] ||
    fail 'Disabled Fail2ban residual-state refusal changed owner evidence'
rm -f -- "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
ln -s missing-owner-state "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
FAIL2BAN_RESIDUAL_BEFORE=$(fail2banManagedSnapshot)
FAKE_DOCKER_MODE=fail2ban-absent rejectFail2ban 1 fail2ban-disabled-residual-state-symlink \
    disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_RESIDUAL_BEFORE}" ]] ||
    fail 'Disabled Fail2ban broken-symlink refusal changed owner evidence'
rm -f -- "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
FAKE_DOCKER_MODE=fail2ban-absent runControl 0 fail2ban-disabled-clean-noop \
    disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
FAKE_DOCKER_MODE=fail2ban-orphan rejectFail2ban 1 fail2ban-disabled-runtime-orphan \
    disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
FAKE_DOCKER_MODE=fail2ban-ps-fail rejectFail2ban 1 fail2ban-disabled-runtime-query-failed \
    disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
cp -p "${TEST_ROOT}/fail2ban-enabled.compose" "${DOCKER_ROOT}/compose.json"
cp -p "${TEST_ROOT}/fail2ban-enabled.deployment" "${DOCKER_ROOT}/deployment.json"
cp -p "${TEST_ROOT}/fail2ban-enabled.spec" "${DOCKER_ROOT}/config/spec.json"
cp -p "${TEST_ROOT}/fail2ban-owner.fixture" "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
FAIL2BAN_DISABLE_BEFORE=$(fail2banManagedSnapshot)
for auditMode in fail2ban-absent fail2ban-audit-drift fail2ban-owner-drift; do
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${auditMode}" runControl 14 "${auditMode}-disable" \
        edit --fail2ban-off --confirm PADM-DOCKER-EDIT
    ! grep -q "^stop " "${DOCKER_LOG}" || fail "${auditMode}: disable stopped an unaudited owner"
    assertFail2banDisablePreserved
    [[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_BEFORE}" ]] ||
        fail "${auditMode}: rejected disable changed managed files"
done
for filter in \
    '.[0].Config.Labels["com.docker.compose.project"] = "foreign"' \
    '.[0].Id = ("f" * 64)' \
    '.[0].State = {Status:"exited",Running:false,Restarting:false,Paused:false,Dead:false,OOMKilled:false,ExitCode:137,Error:""}' \
    '.[0].State = {Status:"exited",Running:false,Restarting:false,Paused:false,Dead:false,OOMKilled:true,ExitCode:0,Error:""}'; do
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_INSPECT_FILTER="${filter}" runControl 14 fail2ban-disable-owner-state \
        edit --fail2ban-off --confirm PADM-DOCKER-EDIT
    ! grep -q "^stop " "${DOCKER_LOG}" || fail 'Fail2ban disable stopped a foreign or invalid exited owner'
    assertFail2banDisablePreserved
    [[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_BEFORE}" ]] ||
        fail 'Fail2ban disable owner refusal changed managed files'
done
for mode in fail2ban-stop-fail fail2ban-stop-137 fail2ban-cleanup-proof-fail; do
    writeFail2banOwnerState
    FAIL2BAN_DISABLE_ATTEMPT_BEFORE=$(fail2banManagedSnapshot)
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${mode}" runControl 14 "${mode}" edit --fail2ban-off --confirm PADM-DOCKER-EDIT
    grep -qxF "stop ${FAIL2BAN_CONTAINER}" "${DOCKER_LOG}" || fail "${mode}: stop was not attempted"
    assertFail2banDisablePreserved
    [[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_ATTEMPT_BEFORE}" ]] ||
        fail "${mode}: stop refusal changed managed files or owner evidence"
done
writeFail2banOwnerState
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-stop-owner-drift runControl 14 fail2ban-disable-cid-replaced \
    edit --fail2ban-off --confirm PADM-DOCKER-EDIT
assertFail2banDisablePreserved
! grep -q 'net-fail2ban preflight fail2ban 24444,24445 unowned' "${DOCKER_LOG}" ||
    fail 'Fail2ban disable accepted an owner CID replaced during stop'
writeFail2banOwnerState
FAIL2BAN_DISABLE_ATTEMPT_BEFORE=$(fail2banManagedSnapshot)
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-cleanup-proof-term-fail runControl 143 fail2ban-disable-failed-proof-term \
    edit --fail2ban-off --confirm PADM-DOCKER-EDIT
assertFail2banDisablePreserved
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_DISABLE_ATTEMPT_BEFORE}" ]] ||
    fail 'TERM after failed cleanup proof changed files or removed owner evidence'
writeFail2banOwnerState
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-cleanup-proof-term runControl 143 fail2ban-disable-clean-proof-term \
    edit --fail2ban-off --confirm PADM-DOCKER-EDIT
cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'TERM after successful cleanup proof did not restore the enabled spec'
grep -Eq '^compose .* up -d .*--remove-orphans' "${DOCKER_LOG}" ||
    fail 'TERM after successful cleanup proof did not restart the old deployment'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'TERM recovery started the old jail without fresh source witnesses'
grep -Eq '^compose .* up -d --no-deps .* net-fail2ban --remove-orphans' "${DOCKER_LOG}" ||
    fail 'TERM recovery skipped the final isolated jail start'
[[ "$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")" == "${FAIL2BAN_SQLITE_HASH}" ]] ||
    fail 'TERM recovery changed the persistent SQLite'
writeFail2banOwnerState
rm -f -- "${TEST_ROOT}/fail-once"
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail-next-up runControl 14 fail2ban-disable-start-failed \
    edit --fail2ban-off --confirm PADM-DOCKER-EDIT
cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'Fail2ban disable startup failure did not restore the enabled spec'
[[ "$(grep -Ec '^compose .* up -d ' "${DOCKER_LOG}")" == 3 ]] ||
    fail 'Fail2ban disable startup failure did not retry the old deployment'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Fail2ban disable rollback reused an old source witness'
[[ "$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")" == "${FAIL2BAN_SQLITE_HASH}" ]] ||
    fail 'Fail2ban disable rollback changed the persistent SQLite'
rm -f -- "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state" "${TEST_ROOT}/fail2ban-stopped"
: >"${DOCKER_LOG}"
FAKE_DOCKER_INSPECT_FILTER='.[0].State = {Status:"exited",Running:false,Restarting:false,Paused:false,Dead:false,OOMKilled:false,ExitCode:0,Error:""}' \
    runControl 0 fail2ban-disable-exited-proof disable-prepare "${FAIL2BAN_DISABLED_SPEC}"
! grep -Eq '^(exec|stop) ' "${DOCKER_LOG}" ||
    fail 'Fail2ban disable executed or stopped an already cleanly exited owner'
grep -q 'net-fail2ban preflight fail2ban 24444,24445 unowned' "${DOCKER_LOG}" ||
    fail 'Fail2ban disable skipped cleanup proof for an exited owner'
grep -qxF "rm ${FAIL2BAN_CONTAINER}" "${DOCKER_LOG}" ||
    fail 'Fail2ban disable did not remove the audited cleanly exited owner'
writeFail2banOwnerState
: >"${DOCKER_LOG}"
runControl 0 fail2ban-disable-success edit --fail2ban-off --confirm PADM-DOCKER-EDIT
cmp -s "${FAIL2BAN_DISABLED_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'Fail2ban disable changed fields other than its managed integration'
jq -e '.services["net-fail2ban"] == null' "${DOCKER_ROOT}/compose.json" >/dev/null ||
    fail 'Fail2ban disable retained the installed Compose service'
[[ "$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")" == "${FAIL2BAN_SQLITE_HASH}" ]] ||
    fail 'Successful Fail2ban disable deleted the persistent SQLite'
python3 - "${DOCKER_LOG}" "${FAIL2BAN_CONTAINER}" <<'PY'
import sys
commands = open(sys.argv[1], encoding="utf-8").read().splitlines()
cid = sys.argv[2]
audit = commands.index(f"exec -i {cid} python3 -")
health = commands.index(f"exec {cid} sh /usr/local/bin/padm-entrypoint fail2ban-health")
stop = commands.index(f"stop {cid}")
proof = next(i for i, command in enumerate(commands)
             if "net-fail2ban preflight fail2ban 24444,24445 unowned" in command)
up = next(i for i, command in enumerate(commands) if " up -d " in command)
assert audit < health < stop < proof < up, "disable skipped its old-owner stop/cleanup gate"
PY

# 三份记录均停用时仍须拒绝运行时孤儿和残留 state，不能把旧 jail 当作无关服务删除。
for residualMode in orphan state; do
    if [[ "${residualMode}" == state ]]; then
        cp -p -- "${TEST_ROOT}/fail2ban-owner.fixture" \
            "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"
        residualDockerMode=fail2ban-absent
    else
        residualDockerMode=fail2ban-orphan
    fi
    FAIL2BAN_RESIDUAL_BEFORE=$(fail2banManagedSnapshot)
    : >"${DOCKER_LOG}"
    FAKE_DOCKER_MODE="${residualDockerMode}" runControl 15 "disabled-${residualMode}-up" up
    FAKE_DOCKER_MODE="${residualDockerMode}" runControl 15 "disabled-${residualMode}-down" down
    ! grep -Eq '^(stop|rm) |^compose .* (up|down|restart|stop)( |$)' "${DOCKER_LOG}" ||
        fail "${residualMode}: disabled shared wrapper touched Compose or owner"
    [[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_RESIDUAL_BEFORE}" ]] ||
        fail "${residualMode}: disabled shared wrapper changed residual evidence"
done
rm -f -- "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.state"

# 专项启用与参数修改保留其它集成，并复用逐入口见证及失败恢复，不另造启动路径。
FAIL2BAN_EDIT_BASE="${TEST_ROOT}/fail2ban-edit-base.json"
jq --slurpfile wireguard "${WIREGUARD_SPEC}" \
    '.host_integrations += $wireguard[0].host_integrations' \
    "${FAIL2BAN_DISABLED_SPEC}" >"${FAIL2BAN_EDIT_BASE}"
runControl 0 fail2ban-edit-base configure --spec "${FAIL2BAN_EDIT_BASE}"
FAIL2BAN_EDIT_BEFORE=$(fail2banManagedSnapshot)
rejectFail2ban 15 fail2ban-settings-disabled edit --fail2ban-settings 24444,24445 6 600 3600 --preview
rejectFail2ban 2 fail2ban-enable-no-confirm edit --fail2ban-enable 24444,24445 6 600 3600
rejectFail2ban 2 fail2ban-enable-missing-value edit --fail2ban-enable 24444,24445 6 600 --preview
rejectFail2ban 2 fail2ban-enable-extra-value edit --fail2ban-enable 24444,24445 6 600 3600 extra --preview
for action in enable settings; do
    rejectFail2ban 2 "fail2ban-${action}-import" edit "--fail2ban-${action}" \
        24444,24445 6 600 3600 --spec "${FAIL2BAN_SPEC}" --preview
    rejectFail2ban 2 "fail2ban-${action}-other-edit" edit "--fail2ban-${action}" \
        24444,24445 6 600 3600 --site-default --preview
    rejectFail2ban 2 "fail2ban-${action}-off" edit "--fail2ban-${action}" \
        24444,24445 6 600 3600 --fail2ban-off --preview
    rejectFail2ban 2 "fail2ban-${action}-duplicate" edit "--fail2ban-${action}" \
        24444,24445 6 600 3600 "--fail2ban-${action}" 24444 6 600 3600 --preview
done
while IFS='|' read -r ports maxRetry findTime banTime; do
    rejectFail2ban 2 fail2ban-enable-invalid edit --fail2ban-enable \
        "${ports}" "${maxRetry}" "${findTime}" "${banTime}" --preview
done <<'EOF'
|6|600|3600
0|6|600|3600
65536|6|600|3600
24444,24444|6|600|3600
24444,|6|600|3600
24444, 24445|6|600|3600
24444-24445|6|600|3600
1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17|6|600|3600
24444|0|600|3600
24444|21|600|3600
24444|6x|600|3600
24444|6|59|3600
24444|6|86401|3600
24444|6|600|59
24444|6|600|604801
EOF
rejectFail2ban 15 fail2ban-enable-unmanaged-port edit --fail2ban-enable 24446 6 600 3600 --preview
for limits in '1 60 60' '20 86400 604800'; do
    read -r maxRetry findTime banTime <<<"${limits}"
    : >"${DOCKER_LOG}"
    PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 0 fail2ban-enable-preview edit \
        --fail2ban-enable 24444,24445 "${maxRetry}" "${findTime}" "${banTime}" --preview
    ! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|down|restart)( |$)' "${DOCKER_LOG}" ||
        fail 'Fail2ban enable preview changed the owner, runtime or source proof'
done
FAIL2BAN_ENABLE_DRAFT="${TEST_ROOT}/fail2ban-enable-draft.json"
jq '.host_integrations += [{
  type:"fail2ban",profile:"net-fail2ban",firewall_rules:["DOCKER-USER"],devices:[],schedules:[],
  settings:{log_file:"access.log",ports:[24444,24445],max_retry:6,find_time:600,ban_time:3600}
}]' "${FAIL2BAN_EDIT_BASE}" >"${FAIL2BAN_ENABLE_DRAFT}"
: >"${DOCKER_LOG}"
runControl 0 fail2ban-enable-cancel apply-cancel "${FAIL2BAN_ENABLE_DRAFT}"
! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|down|restart)( |$)' "${DOCKER_LOG}" ||
    fail 'Fail2ban enable cancellation changed the owner, runtime or source proof'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_EDIT_BEFORE}" ]] ||
    fail 'Fail2ban enable preview, cancellation or rejected parameters changed managed files'
: >"${DOCKER_LOG}"
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 15 fail2ban-enable-missing-source edit \
    --fail2ban-enable 24444,24445 6 600 3600 --confirm PADM-DOCKER-EDIT
! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|down|restart)( |$)' "${DOCKER_LOG}" ||
    fail 'Fail2ban enable touched the deployment without current source input'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_EDIT_BEFORE}" ]] ||
    fail 'Fail2ban enable without source input changed managed files'
: >"${DOCKER_LOG}"
runControl 0 fail2ban-enable-success edit --fail2ban-enable 24444,24445 6 600 3600 \
    --confirm PADM-DOCKER-EDIT
jq -en --slurpfile before "${FAIL2BAN_EDIT_BASE}" --slurpfile after "${DOCKER_ROOT}/config/spec.json" '
  ($before[0] | del(.host_integrations)) == ($after[0] | del(.host_integrations)) and
  $after[0].host_integrations == ($before[0].host_integrations + [{
    type:"fail2ban",profile:"net-fail2ban",firewall_rules:["DOCKER-USER"],devices:[],schedules:[],
    settings:{log_file:"access.log",ports:[24444,24445],max_retry:6,find_time:600,ban_time:3600}
  }])
' >/dev/null || fail 'Fail2ban enable changed fields or integrations beyond its new jail'
python3 - "${DOCKER_LOG}" <<'PY'
import sys
commands = open(sys.argv[1], encoding="utf-8").read().splitlines()
witnesses = [(i, line.split()) for i, line in enumerate(commands) if line.startswith("source-witness ")]
starts = [(i, line) for i, line in enumerate(commands) if " up -d " in line]
assert len(witnesses) == 2 and len({line[4] for _, line in witnesses}) == 2
assert [line[1] for _, line in witnesses] == ["entry-main-ws", "entry-alt-ws"]
assert len(starts) == 2 and starts[0][0] < witnesses[0][0] < witnesses[1][0] < starts[1][0]
assert " net-fail2ban --remove-orphans" not in starts[0][1]
assert " --no-deps " in starts[1][1] and " net-fail2ban --remove-orphans" in starts[1][1]
PY
rejectFail2ban 15 fail2ban-enable-already-enabled edit --fail2ban-enable 24444 1 60 60 --preview
FAIL2BAN_SETTINGS_BEFORE=$(fail2banManagedSnapshot)
cp -p -- "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/fail2ban-settings-before.json"
: >"${DOCKER_LOG}"
runControl 0 fail2ban-settings-preview edit --fail2ban-settings 24444 7 900 7200 --preview
! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|down|restart)( |$)' "${DOCKER_LOG}" ||
    fail 'Fail2ban settings preview changed the owner, runtime or source proof'
: >"${DOCKER_LOG}"
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 15 fail2ban-settings-missing-source edit \
    --fail2ban-settings 24444 7 900 7200 --confirm PADM-DOCKER-EDIT
! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|down|restart)( |$)' "${DOCKER_LOG}" ||
    fail 'Fail2ban settings stopped or restarted an owner without current source input'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_SETTINGS_BEFORE}" ]] ||
    fail 'Fail2ban settings preview or missing source input changed managed files'
: >"${DOCKER_LOG}"
runControl 0 fail2ban-settings-success edit --fail2ban-settings 24444 7 900 7200 \
    --confirm PADM-DOCKER-EDIT
jq -en --slurpfile before "${TEST_ROOT}/fail2ban-settings-before.json" \
    --slurpfile after "${DOCKER_ROOT}/config/spec.json" '
  ($before[0] | .host_integrations |= map(if .type == "fail2ban" then
    .settings.ports = [24444] | .settings.max_retry = 7 |
    .settings.find_time = 900 | .settings.ban_time = 7200 else . end)) == $after[0]
' >/dev/null || fail 'Fail2ban settings changed other fields or integrations'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 1 ]] &&
    grep -q '^source-witness entry-main-ws ipv4 198.51.100.9 ' "${DOCKER_LOG}" ||
    fail 'Fail2ban settings did not verify exactly its selected protected port'
cp -p -- "${DOCKER_ROOT}/config/spec.json" "${TEST_ROOT}/fail2ban-settings-subset.json"
rm -f -- "${TEST_ROOT}/source-fail-once"
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-source-last-once runControl 14 fail2ban-settings-source-rollback edit \
    --fail2ban-settings 24444,24445 8 1200 10800 --confirm PADM-DOCKER-EDIT
cmp -s "${TEST_ROOT}/fail2ban-settings-subset.json" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'Fail2ban settings source failure did not restore the previous selected ports and parameters'
python3 - "${DOCKER_LOG}" <<'PY'
import sys
commands = open(sys.argv[1], encoding="utf-8").read().splitlines()
witnesses = [(i, line.split()) for i, line in enumerate(commands) if line.startswith("source-witness ")]
jails = [i for i, line in enumerate(commands) if " up -d " in line and " net-fail2ban --remove-orphans" in line]
assert [line[1] for _, line in witnesses] == ["entry-main-ws", "entry-alt-ws", "entry-main-ws"]
assert len({line[4] for _, line in witnesses}) == 3, "settings rollback reused a witness nonce"
assert len(jails) == 1 and jails[0] > witnesses[-1][0], "settings jail started without fresh recovery proof"
PY
[[ "$(sha256sum "${DOCKER_ROOT}/data/net/fail2ban/fail2ban.sqlite3")" == "${FAIL2BAN_SQLITE_HASH}" ]] ||
    fail 'Fail2ban enable or settings changed persistent SQLite'

runControl 0 fail2ban-restore-for-other-contracts configure --spec "${FAIL2BAN_SPEC}"
rm -f -- "${TEST_ROOT}/fail2ban-stopped"

# 旧策略只可经配置事务清理；当前启动和 Nginx reload 不得先停 owner 再尝试修复。
jq '.services["net-fail2ban"].restart = "unless-stopped"' "${DOCKER_ROOT}/compose.json" \
    >"${TEST_ROOT}/legacy-restart.compose"
cp -p -- "${TEST_ROOT}/legacy-restart.compose" "${DOCKER_ROOT}/compose.json"
jq '.[0].HostConfig.RestartPolicy.Name = "unless-stopped"' "${FAIL2BAN_INSPECT}" \
    >"${TEST_ROOT}/legacy-restart.inspect"
cp -p -- "${TEST_ROOT}/legacy-restart.inspect" "${FAIL2BAN_INSPECT}"
FAIL2BAN_LEGACY_BEFORE=$(fail2banManagedSnapshot)
: >"${DOCKER_LOG}"
runControl 15 legacy-restart-up up
runControl 15 legacy-restart-restart restart
runControl 15 legacy-restart-reload shared-compose exec -T nginx nginx -e /dev/stderr -s reload
! grep -Eq '^(stop|rm) |^compose .* (up|restart|down|exec)( |$)' "${DOCKER_LOG}" ||
    fail 'Legacy restart policy was not rejected before changing owner or runtime services'
[[ "$(fail2banManagedSnapshot)" == "${FAIL2BAN_LEGACY_BEFORE}" ]] ||
    fail 'Legacy restart refusal changed managed files'
: >"${DOCKER_LOG}"
runControl 0 legacy-restart-normalize configure --spec "${FAIL2BAN_SPEC}"
grep -qxF "stop ${FAIL2BAN_CONTAINER}" "${DOCKER_LOG}" ||
    fail 'Standard configure did not use owner-mode cleanup for legacy restart policy'
grep -qxF "rm ${FAIL2BAN_CONTAINER}" "${DOCKER_LOG}" ||
    fail 'Standard configure retained the audited legacy owner'
jq -e '.services["net-fail2ban"].restart == "no"' "${DOCKER_ROOT}/compose.json" >/dev/null ||
    fail 'Standard configure did not normalize legacy restart policy'
LEGACY_RESTART_BACKUP=$(sed -n 's/^Docker 配置已提交，回滚快照: //p' "${CONTROL_LOG}")
[[ -n "${LEGACY_RESTART_BACKUP}" ]] || fail 'Legacy normalization did not preserve its rollback snapshot'
cmp -s -- "${TEST_ROOT}/legacy-restart.compose" "${LEGACY_RESTART_BACKUP}/compose.json" ||
    fail 'Legacy normalization modified the saved Compose evidence'
LEGACY_RESTART_BACKUP_HASH=$(sha256sum "${LEGACY_RESTART_BACKUP}/compose.json")
: >"${DOCKER_LOG}"
runControl 0 legacy-restart-backup-restore restore-backup "${LEGACY_RESTART_BACKUP}"
jq -e '.services["net-fail2ban"].restart == "no"' "${DOCKER_ROOT}/compose.json" >/dev/null ||
    fail 'Legacy backup restore republished automatic jail restart'
[[ "$(sha256sum "${LEGACY_RESTART_BACKUP}/compose.json")" == "${LEGACY_RESTART_BACKUP_HASH}" ]] ||
    fail 'Legacy backup restore rewrote the saved Compose evidence'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Legacy backup restore skipped fresh source evidence'

# 明确的核心无依赖操作继续可用，未知 Compose 参数不能绕过来源门禁。
: >"${DOCKER_LOG}"
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 0 core-no-deps shared-compose up -d --no-deps xray
grep -Eq '^compose .* up -d --no-deps xray --remove-orphans$' "${DOCKER_LOG}" ||
    fail 'Shared wrapper rejected a targeted core no-deps operation'
! grep -Eq '^(stop|rm|source-witness) ' "${DOCKER_LOG}" ||
    fail 'Targeted core no-deps operation changed Fail2ban owner or source proof'
: >"${DOCKER_LOG}"
PADM_DOCKER_FAIL2BAN_SOURCE_IPV4='' runControl 15 shared-full-up-missing-source shared-compose up -d
! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|restart|down)( |$)' "${DOCKER_LOG}" ||
    fail 'Shared full up stopped or started Fail2ban without this-command source input'
for operation in up restart; do
    : >"${DOCKER_LOG}"
    runControl 2 "shared-${operation}-unknown-option" shared-compose "${operation}" --scale xray=2
    ! grep -Eq '^(stop|rm|source-witness) |^compose .* (up|restart|down)( |$)' "${DOCKER_LOG}" ||
        fail 'Unknown Compose arguments bypassed the shared source guard'
done

# 失败恢复重新遍历两个保护入口，最后一个失败时不能启动 jail。
rm -f -- "${TEST_ROOT}/source-fail-once"
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-source-last-once runControl 14 fail2ban-source-rollback \
    configure --spec "${FAIL2BAN_SPEC}"
cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'Source witness failure did not restore the old spec'
[[ "$(grep -Ec '^compose .* up -d ' "${DOCKER_LOG}")" -eq 3 &&
    "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 4 ]] ||
    fail 'Source witness rollback skipped a protected entry or its fresh restart'
python3 - "${DOCKER_LOG}" <<'PY'
import sys
commands = open(sys.argv[1], encoding="utf-8").read().splitlines()
witnesses = [(i, line.split()) for i, line in enumerate(commands) if line.startswith("source-witness ")]
jails = [i for i, line in enumerate(commands) if " up -d " in line and " net-fail2ban --remove-orphans" in line]
assert [line[1:4] for _, line in witnesses] == [
    ["entry-main-ws", "ipv4", "198.51.100.9"], ["entry-alt-ws", "ipv4", "198.51.100.9"],
    ["entry-main-ws", "ipv4", "198.51.100.9"], ["entry-alt-ws", "ipv4", "198.51.100.9"]]
assert len({line[4] for _, line in witnesses}) == 4, "rollback reused a witness nonce"
assert len(jails) == 1 and jails[0] > witnesses[-1][0], "jail started before fresh recovery witnesses"
PY
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail2ban-source-last-fail runControl 14 fail2ban-source-rollback-refused \
    configure --spec "${FAIL2BAN_SPEC}"
cmp -s "${FAIL2BAN_SPEC}" "${DOCKER_ROOT}/config/spec.json" ||
    fail 'Failed recovery source witness changed the old spec'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 4 ]] ||
    fail 'Failed recovery did not challenge every protected entry anew'
! grep -Eq '^compose .* up -d .* net-fail2ban --remove-orphans' "${DOCKER_LOG}" ||
    fail 'Jail started despite the final source witness failure'
[[ ! -e "${FAIL2BAN_INSPECT}" ]] || fail 'Failed recovery retained a running jail'
grep -qF '旧配置恢复失败' "${CONTROL_LOG}" ||
    fail 'Failed recovery hid its incomplete source proof'
runControl 0 fail2ban-source-recovery configure --spec "${FAIL2BAN_SPEC}"

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
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail-next-up runControl 14 rollback-net configure --spec "${TPROXY_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/config/net/fail2ban/padm.local" | cut -d ' ' -f 1)" == "${FAIL2BAN_HASH}" ]] ||
    fail 'failed deployment did not restore config/net'
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${DEPLOYMENT_HASH}" ]] ||
    fail 'failed deployment did not restore deployment state'
[[ "$(sha256sum "${DOCKER_ROOT}/config/spec.json" | cut -d ' ' -f 1)" == "${SPEC_HASH}" ]] ||
    fail 'failed deployment did not restore complete spec'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Host integration rollback restarted Fail2ban without both fresh source witnesses'

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
: >"${DOCKER_LOG}"
FAKE_DOCKER_MODE=fail-next-up runControl 14 rollback-staged apply-staged \
    "${FAIL2BAN_SPEC}" "${STAGED_TLS}" "${STAGED_ACME}"
grep -qxF fake-certificate "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'failed deployment committed candidate TLS'
grep -qxF old-acme-account "${DOCKER_ROOT}/data/acme/account" ||
    fail 'failed deployment committed candidate ACME data'
[[ "$(sha256sum "${DOCKER_ROOT}/config/spec.json" | cut -d ' ' -f 1)" == "${SPEC_HASH}" ]] ||
    fail 'failed staged deployment did not restore complete spec'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Staged deployment rollback reused Fail2ban source evidence'
: >"${DOCKER_LOG}"
runControl 0 commit-staged apply-staged "${FAIL2BAN_SPEC}" "${STAGED_TLS}" "${STAGED_ACME}"
grep -qxF new-certificate "${DOCKER_ROOT}/secrets/tls/proxy.example.com.crt" ||
    fail 'successful deployment did not commit candidate TLS'
grep -qxF new-acme-account "${DOCKER_ROOT}/data/acme/account" ||
    fail 'successful deployment did not commit candidate ACME data'
[[ "$(grep -c '^source-witness ' "${DOCKER_LOG}")" -eq 2 ]] ||
    fail 'Staged deployment did not verify both protected source tuples'

# Fail2ban 的双栈发布复用受管辅助网，不扩大核心的出站网络范围。
(
    source "${PROJECT_ROOT}/install-docker.sh"
    jq '.core.protocols[0].address_families += ["ipv6"]' \
        "${DOCKER_ROOT}/config/spec.json" >"${TEST_ROOT}/fail2ban-dual.json"
    dockerGenerateCompose "${TEST_ROOT}/fail2ban-dual.json" "${TEST_ROOT}/fail2ban-dual-compose.json"
    jq -e '.networks.ipv6.enable_ipv6 == true and
      .services.nginx.networks == ["default","ipv6"] and
      .services.xray.networks == null' "${TEST_ROOT}/fail2ban-dual-compose.json"
    jq -e '.networks.ipv6 == null and .services.nginx.networks == null' "${DOCKER_ROOT}/compose.json"
    cleanupRoot="${TEST_ROOT}/fail2ban-network-cleanup"
    export PADM_DOCKER_INSTALL_DIR="${cleanupRoot}"
    mkdir -p "${cleanupRoot}"
    cp "${TEST_ROOT}/fail2ban-dual-compose.json" "${cleanupRoot}/compose.json"
    dockerIPv6NetworkManage() { printf '%s\n' "$*" >>"${cleanupRoot}/network.calls"; }
    for current in dual ipv4; do
        DOCKER_CONFIG_CANDIDATE="${cleanupRoot}/candidate"
        mkdir -p "${DOCKER_CONFIG_CANDIDATE}"
        cp "${TEST_ROOT}/fail2ban-dual-compose.json" "${DOCKER_CONFIG_CANDIDATE}/compose.json"
        if [[ "${current}" == ipv4 ]]; then
            cp "${DOCKER_ROOT}/compose.json" "${cleanupRoot}/compose.json"
        fi
        dockerCleanupConfigurationCandidate
        if [[ "${current}" == dual ]]; then
            [[ ! -e "${cleanupRoot}/network.calls" ]]
        else
            grep -qx cleanup "${cleanupRoot}/network.calls"
        fi
    done
)

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
grep -q 'net-transparent preflight tproxy 31298 129 unowned$' "${DOCKER_LOG}" ||
    fail 'first TProxy configuration borrowed ownership'
! grep -q '/run/padm-tproxy-owner:ro' "${DOCKER_LOG}" ||
    fail 'first TProxy configuration mounted an owner'

: >"${DOCKER_LOG}"
runControl 0 tproxy-reconfigure configure --spec "${TPROXY_SPEC}"
grep -q -- "--volume ${DOCKER_ROOT}/data/net/transparent:/run/padm-tproxy-owner:ro net-transparent preflight tproxy 31298 129 owned /run/padm-tproxy-owner$" "${DOCKER_LOG}" ||
    fail 'TProxy reconfiguration did not read the current owner'
: >"${DOCKER_LOG}"
runControl 0 tproxy-validate validate
grep -q 'net-transparent preflight tproxy 31298 129 owned$' "${DOCKER_LOG}" ||
    fail 'TProxy validation did not check the live owner'

LIVE_HASH=$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)
runControl 15 reject-nginx-tproxy configure --spec "${INVALID_SPEC}"
[[ "$(sha256sum "${DOCKER_ROOT}/deployment.json" | cut -d ' ' -f 1)" == "${LIVE_HASH}" ]] ||
    fail 'invalid transparent topology changed live state'

sh -n "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" || fail 'net entrypoint syntax is invalid'
grep -q 'padm-tproxy' "${PROJECT_ROOT}/docker/images/net/entrypoint.sh" || fail 'TProxy rule ownership is missing'
printf 'docker-phase4-regression-ok\n'
