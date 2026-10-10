#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    printf 'docker-permissions-regression-skip: Linux root is required\n'
    exit 0
fi
[[ "$(id -u)" == 0 ]] || { printf 'docker-permissions-regression-fail: run as root\n' >&2; exit 1; }
for tool in jq setpriv stat chown chmod; do
    command -v "${tool}" >/dev/null || { printf 'missing tool: %s\n' "${tool}" >&2; exit 1; }
done
PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-permissions.XXXXXX")
trap 'rm -rf -- "${TEST_ROOT}"' EXIT
export PADM_DOCKER_SKIP_CHOWN=0
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/bundle.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/manifest.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/services.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"

fail() { printf 'docker-permissions-regression-fail: %s\n' "$*" >&2; exit 1; }
assertMetadata() {
    [[ "$(stat -c '%a %u %g' "$1")" == "$2" ]] || fail "unexpected permissions/owner: $1"
}
# 只隔离服务启停和只读归属查询，文件复制、属主和权限检查均使用实际共享函数。
dockerComposeExecute() {
    [[ "$*" == down ||
        "$*" == "up -d --force-recreate --wait --wait-timeout ${PADM_DOCKER_HEALTH_TIMEOUT:-60}" ]] ||
        fail "unexpected restore service operation: $*"
    printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"
}
dockerComposeRun() { dockerComposeExecute "$@"; }
dockerTrafficScheduleRemove() { printf 'removed\n' >>"${TEST_ROOT}/schedule.log"; }
docker() {
    [[ "$*" == 'ps -aq --filter label=com.docker.compose.project=padm-docker --filter label=com.docker.compose.service=net-fail2ban --filter label=com.docker.compose.oneoff=False' ]] ||
        fail "unexpected ownership query: $*"
    printf '%s\n' "$*" >>"${TEST_ROOT}/ownership.log"
    [[ "${OWNERSHIP_QUERY_FAIL:-0}" != 1 ]]
}

seedRuntimeSecrets() {
    mkdir -p "${PADM_DOCKER_INSTALL_DIR}/secrets/tls" "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0700 "${PADM_DOCKER_INSTALL_DIR}/secrets"
    printf 'certificate\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.crt"
    printf 'private-key\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
    printf 'acme-account\n' >"${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
    dockerTlsRuntimePermissions "${PADM_DOCKER_INSTALL_DIR}/secrets/tls"
    chown -R 10001:10001 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0750 "${PADM_DOCKER_INSTALL_DIR}/data/acme"
    chmod 0600 "${PADM_DOCKER_INSTALL_DIR}/data/acme/account.conf"
}
assertRuntimeSecrets() {
    local root=${PADM_DOCKER_INSTALL_DIR}
    assertMetadata "${root}/secrets" '700 0 0'
    assertMetadata "${root}/secrets/tls/example.com.key" '600 10001 10001'
    assertMetadata "${root}/secrets/tls/example.com.crt" '640 0 10001'
    [[ "$(stat -c '%u %g' "${root}/data/acme/account.conf")" == '10001 10001' ]] ||
        fail 'ACME account was not restored to the container user'
    # 进入实际 bind 子目录视图后降权，不让宿主私密父目录影响容器读取结论。
    (
        cd "${root}/secrets/tls"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r example.com.key && test -r example.com.crt && test "$(cat example.com.key)" = private-key'
    ) || fail 'container UID could not read the restored TLS key and certificate'
    (
        cd "${root}/data/acme"
        setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
            'test -r account.conf && test -w account.conf && test -w .'
    ) || fail 'container UID could not use the restored ACME account'
}

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/configured"
dockerInitializeStateRoot
dockerInstallBundle "${PROJECT_ROOT}" "$(printf 'a%.0s' {1..40})"
mkdir -p "${PADM_DOCKER_INSTALL_DIR}/config/xray" "${PADM_DOCKER_INSTALL_DIR}/data/subscription"
seedRuntimeSecrets
jq -n '
    def ref($name): "ghcr.io/example/padm-" + $name + ":3.2.0@sha256:" + ("2" * 64);
    {schema_version:1, release:{version:"3.2.0",manifest_sha256:("a"*64),signature_identity:"test"},
     core:{type:"xray",protocols:[{id:21,server:"proxy.example.com",public_port:24443,
       address_families:["ipv4"],name:"main",uuid:"11111111-1111-4111-8111-111111111111",
       websocket:{domain:"example.com",path:"abcdefgh"}}]},
     tls:{domain:"example.com"},subscription:{enabled:false,token:("a"*32)},
     images:{xray:ref("xray"),"sing-box":ref("sing-box"),nginx:ref("nginx"),ops:ref("ops"),net:ref("net")},
     host_integrations:[]}
' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
jq -n --slurpfile spec "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '
    $spec[0] as $s |
    {schema_version:1,mode:"docker",padm_version:$s.release.version,bundle_version:"fixture",
     manifest:{sha256:$s.release.manifest_sha256,signature_identity:$s.release.signature_identity},
     compose:{project:"padm-docker",profiles:["core-xray","nginx"]},
     core:{type:"xray",protocol_ids:[21]},
     listeners:[{service:"nginx",public_port:24443,container_port:8443,transport:"tcp",address_families:["ipv4"]}],
     images:($s.images|with_entries(.value={index_digest:(.value|split("@")|last)})),
     formats:{compose:1,config:1,data:1},previous_manifest_sha256:null,host_integrations:[]}
' >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
printf '{"name":"padm-docker","services":{}}\n' >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
jq -r '.images | "PADM_XRAY_IMAGE=" + .xray, "PADM_SINGBOX_IMAGE=" + ."sing-box",
    "PADM_NGINX_IMAGE=" + .nginx, "PADM_OPS_IMAGE=" + .ops, "PADM_NET_IMAGE=" + .net' \
    "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" >"${PADM_DOCKER_INSTALL_DIR}/images.env"
dockerEnsureRuntimeDataPermissions
dockerBackupConfiguration configure
backup=${DOCKER_CONFIG_BACKUP}
[[ -z "$(find "${backup}" ! -uid 0 -o ! -gid 0)" ]] || fail 'backup retained runtime file owners'
dockerValidateConfigurationBackup "${backup}" || fail 'root-owned runtime backup did not validate'
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/config/spec.json"
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
jq 'del(.host_integrations)' "${backup}/deployment.json" \
    >"${PADM_DOCKER_INSTALL_DIR}/deployment.json"
DOCKER_CONFIG_SWITCHED=1
! dockerRestoreConfiguration >"${TEST_ROOT}/restore-corrupt.log" 2>&1 ||
    fail 'runtime restore overwrote a corrupt current spec with unknown integration metadata'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" ||
    fail 'corrupt-spec refusal changed the current spec'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key" ||
    fail 'corrupt-spec refusal changed the current TLS key'
cp -p -- "${backup}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/deployment.json"
OWNERSHIP_QUERY_FAIL=1
! dockerRestoreConfiguration >"${TEST_ROOT}/restore-query-fail.log" 2>&1 ||
    fail 'runtime restore ignored an ownership query failure'
[[ "${DOCKER_CONFIG_SWITCHED}" == 1 ]] || fail 'ownership query refusal discarded the restore transaction'
grep -qxF changed "${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key" ||
    fail 'ownership query refusal changed the current TLS key'
[[ ! -e "${TEST_ROOT}/compose.log" ]] || fail 'refused restore stopped or started services'
OWNERSHIP_QUERY_FAIL=0
dockerRestoreConfiguration || fail 'runtime backup restore failed'
assertMetadata "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '600 0 0'
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" || fail 'restored spec was inconsistent'
(
    cd "${PADM_DOCKER_INSTALL_DIR}/config"
    ! setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c 'cat spec.json' >/dev/null 2>&1
) || fail 'container UID could read the root-only spec'
assertRuntimeSecrets

# 主控来源日志只允许 root 管理目录、运行 UID 追加普通单链接文件。
controlRoot="${TEST_ROOT}/control-log-runtime"
mkdir -p -- "${controlRoot}/config"
chmod 0750 "${controlRoot}" "${controlRoot}/config"
printf '{"control":{"role":"main"}}\n' >"${controlRoot}/config/spec.json"
dockerControlAccessLogEnsure "${controlRoot}"
controlLog="${controlRoot}/logs/control/auth.log"
sourceReceipt="${controlRoot}/logs/control/source.receipt"
sourceChallenge="${controlRoot}/data/control-source/challenge.json"
assertMetadata "${controlRoot}/logs/control" '750 0 10001'
assertMetadata "${controlLog}" '640 10001 10001'
assertMetadata "${sourceReceipt}" '640 10001 10001'
assertMetadata "${controlRoot}/data/control-source" '750 0 10001'
[[ ! -e "${sourceChallenge}" ]] || fail 'runtime permissions created a challenge'
(
    cd "${controlRoot}/logs/control"
    setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
        'test -w auth.log && test ! -w . && printf "kept-control-evidence\n" >>auth.log'
) || fail 'control UID could not append to the protected log'
controlDigest=$(sha256sum "${controlLog}")
printf 'kept-source-receipt\n' >"${sourceReceipt}"
receiptDigest=$(sha256sum "${sourceReceipt}")
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLog}")" == "${controlDigest}" ]] || fail 'existing control log was truncated'
[[ "$(sha256sum "${sourceReceipt}")" == "${receiptDigest}" ]] || fail 'existing source receipt was truncated'
mv -- "${controlLog}" "${controlRoot}/saved-auth.log"
printf 'untouched\n' >"${controlRoot}/outside-log"
chmod 0600 "${controlRoot}/outside-log"
chown 12345:12345 "${controlRoot}/outside-log"
ln -s "${controlRoot}/outside-log" "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log symlink was accepted'
rm -- "${controlLog}"
ln "${controlRoot}/outside-log" "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log hardlink was accepted'
assertMetadata "${controlRoot}/outside-log" '600 12345 12345'
grep -qxF untouched "${controlRoot}/outside-log" || fail 'unsafe control log changed its external target'
rm -- "${controlLog}"
mv -- "${controlRoot}/saved-auth.log" "${controlLog}"
chmod 0660 "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log permissions were repaired'
assertMetadata "${controlLog}" '660 10001 10001'
chmod 0640 "${controlLog}"
chown 0:10001 "${controlLog}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log owner was repaired'
assertMetadata "${controlLog}" '640 0 10001'
chown 10001:10001 "${controlLog}"
for unsafeParent in "${controlRoot}" "${controlRoot}/logs" "${controlRoot}/logs/control"; do
    safeMode=$(stat -c %a -- "${unsafeParent}")
    chmod 0770 "${unsafeParent}"
    ! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe control log parent was accepted'
    [[ "$(stat -c %a -- "${unsafeParent}")" == 770 ]] || fail 'unsafe log parent was silently repaired'
    chmod "${safeMode}" "${unsafeParent}"
done
mv -- "${controlRoot}/logs/control" "${controlRoot}/saved-control"
ln -s "${controlRoot}/saved-control" "${controlRoot}/logs/control"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'control log directory symlink was accepted'
rm -- "${controlRoot}/logs/control"
mv -- "${controlRoot}/saved-control" "${controlRoot}/logs/control"
mkdir -- "${controlRoot}/logs/control/unexpected"
chmod 0777 "${controlRoot}/logs/control/unexpected"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unexpected control log tree was accepted'
[[ "$(stat -c %a -- "${controlRoot}/logs/control/unexpected")" == 777 ]] ||
    fail 'unexpected control log tree was recursively repaired'
rmdir -- "${controlRoot}/logs/control/unexpected"
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${controlLog}")" == "${controlDigest}" ]] || fail 'control log changed after rejected unsafe inputs'
mv -- "${sourceReceipt}" "${controlRoot}/saved-source.receipt"
ln -s "${controlRoot}/outside-log" "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source receipt symlink was accepted'
rm -- "${sourceReceipt}"
ln "${controlRoot}/saved-source.receipt" "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source receipt hardlink was accepted'
rm -- "${sourceReceipt}"
mv -- "${controlRoot}/saved-source.receipt" "${sourceReceipt}"
chmod 0660 "${sourceReceipt}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source receipt permissions were repaired'
assertMetadata "${sourceReceipt}" '660 10001 10001'
chmod 0640 "${sourceReceipt}"
printf '{"fixture":"registered-source"}\n' >"${sourceChallenge}"
chmod 0640 "${sourceChallenge}"
chown 0:10001 "${sourceChallenge}"
challengeDigest=$(sha256sum "${sourceChallenge}")
dockerControlAccessLogEnsure "${controlRoot}"
(
    cd "${controlRoot}/data/control-source"
    setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c \
        'test -r challenge.json && test ! -w challenge.json && test ! -w .'
) || fail 'control UID could modify the root-owned challenge registration'
ln "${sourceChallenge}" "${controlRoot}/challenge-link"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source challenge hardlink was accepted'
rm -- "${controlRoot}/challenge-link"
chmod 0660 "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source challenge permissions were repaired'
assertMetadata "${sourceChallenge}" '660 0 10001'
chmod 0640 "${sourceChallenge}"
chown 10001:10001 "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'API-owned source challenge was accepted'
assertMetadata "${sourceChallenge}" '640 10001 10001'
chown 0:10001 "${sourceChallenge}"
[[ "$(sha256sum "${sourceChallenge}")" == "${challengeDigest}" ]] || fail 'challenge content was replaced'
mv -- "${sourceChallenge}" "${controlRoot}/saved-challenge.json"
ln -s "${controlRoot}/saved-challenge.json" "${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'source challenge symlink was accepted'
rm -- "${sourceChallenge}"
mv -- "${controlRoot}/saved-challenge.json" "${sourceChallenge}"
printf '%4097s' '' >"${sourceChallenge}"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'oversize source challenge was accepted'
[[ "$(stat -c %s -- "${sourceChallenge}")" == 4097 ]] || fail 'oversize source challenge was truncated'
rm -- "${sourceChallenge}"
chmod 0770 "${controlRoot}/data"
! dockerControlAccessLogEnsure "${controlRoot}" || fail 'unsafe source directory parent was accepted'
chmod 0750 "${controlRoot}/data"
dockerControlAccessLogEnsure "${controlRoot}"
[[ "$(sha256sum "${sourceReceipt}")" == "${receiptDigest}" ]] || fail 'source receipt changed after rejected unsafe inputs'
printf '{"control_sync":{}}\n' >"${controlRoot}/config/spec.json"
rm -- "${controlLog}" "${sourceReceipt}"
rmdir -- "${controlRoot}/logs/control"
rmdir -- "${controlRoot}/data/control-source"
dockerControlAccessLogEnsure "${controlRoot}"
[[ ! -e "${controlRoot}/logs/control" && ! -e "${controlRoot}/data/control-source" ]] ||
    fail 'controlled node created unused source paths'

export PADM_DOCKER_INSTALL_DIR="${TEST_ROOT}/unconfigured"
dockerInitializeStateRoot
seedRuntimeSecrets
dockerBackupConfiguration configure
backup=${DOCKER_CONFIG_BACKUP}
[[ -z "$(find "${backup}" ! -uid 0 -o ! -gid 0)" ]] || fail 'unconfigured backup retained runtime owners'
! dockerValidateConfigurationBackup "${backup}" || fail 'unconfigured snapshot was accepted as a deployment backup'
printf 'changed\n' >"${PADM_DOCKER_INSTALL_DIR}/secrets/tls/example.com.key"
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration || fail 'unconfigured backup restore failed'
[[ ! -e "${PADM_DOCKER_INSTALL_DIR}/deployment.json" ]] || fail 'unconfigured restore created a deployment'
assertRuntimeSecrets
grep -qxF removed "${TEST_ROOT}/schedule.log" || fail 'unconfigured restore did not remove the runtime scheduler'
# 权限准备必须在 chmod/chown 前拒绝指向候选之外的链接。
unsafeCandidate="${TEST_ROOT}/unsafe-candidate"
mkdir -p "${unsafeCandidate}/config/xray"
printf 'external\n' >"${TEST_ROOT}/external"
chmod 0600 "${TEST_ROOT}/external"
chown 12345:12345 "${TEST_ROOT}/external"
ln -s "${TEST_ROOT}/external" "${unsafeCandidate}/config/xray/unsafe"
! dockerPrepareCandidatePermissions "${unsafeCandidate}" || fail 'candidate symlink was accepted'
assertMetadata "${TEST_ROOT}/external" '600 12345 12345'
unsafeLogCandidate="${TEST_ROOT}/unsafe-log-candidate"
mkdir -p "${unsafeLogCandidate}/logs/control"
printf 'not-candidate-evidence\n' >"${unsafeLogCandidate}/logs/control/auth.log"
chmod 0600 "${unsafeLogCandidate}/logs/control/auth.log"
chown 12345:12345 "${unsafeLogCandidate}/logs/control/auth.log"
! dockerPrepareCandidatePermissions "${unsafeLogCandidate}" || fail 'candidate carried runtime control evidence'
assertMetadata "${unsafeLogCandidate}/logs/control/auth.log" '600 12345 12345'
unsafeSourceCandidate="${TEST_ROOT}/unsafe-source-candidate"
mkdir -p "${unsafeSourceCandidate}/data/control-source"
printf 'not-candidate-registration\n' >"${unsafeSourceCandidate}/data/control-source/challenge.json"
chmod 0600 "${unsafeSourceCandidate}/data/control-source/challenge.json"
chown 12345:12345 "${unsafeSourceCandidate}/data/control-source/challenge.json"
! dockerPrepareCandidatePermissions "${unsafeSourceCandidate}" || fail 'candidate carried a runtime challenge'
assertMetadata "${unsafeSourceCandidate}/data/control-source/challenge.json" '600 12345 12345'
printf 'docker-permissions-regression-ok\n'
