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
# 只隔离服务启停，文件复制、属主和所有权限检查均使用实际共享函数。
dockerComposeRun() { printf '%s\n' "$*" >>"${TEST_ROOT}/compose.log"; }
dockerTrafficScheduleRemove() { printf 'removed\n' >>"${TEST_ROOT}/schedule.log"; }

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
printf '{}\n' >"${PADM_DOCKER_INSTALL_DIR}/compose.json"
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
DOCKER_CONFIG_SWITCHED=1
dockerRestoreConfiguration || fail 'runtime backup restore failed'
assertMetadata "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" '600 0 0'
dockerManagedSpecMatchesDeployment "${PADM_DOCKER_INSTALL_DIR}/config/spec.json" \
    "${PADM_DOCKER_INSTALL_DIR}/deployment.json" "${PADM_DOCKER_INSTALL_DIR}/images.env" || fail 'restored spec was inconsistent'
(
    cd "${PADM_DOCKER_INSTALL_DIR}/config"
    ! setpriv --reuid 10001 --regid 10001 --clear-groups -- sh -c 'cat spec.json' >/dev/null 2>&1
) || fail 'container UID could read the root-only spec'
assertRuntimeSecrets

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
printf 'docker-permissions-regression-ok\n'
