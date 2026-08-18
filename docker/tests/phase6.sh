#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase6.XXXXXX")
MOCK_BIN=${TEST_ROOT}/bin
STATE_ROOT=${TEST_ROOT}/state
DOCKER_LOG=${TEST_ROOT}/docker.log
MANIFEST=${TEST_ROOT}/release-manifest.json
OLD_DIGEST=$(printf '1%.0s' {1..64})
NEW_DIGEST=$(printf '2%.0s' {1..64})
ROLLBACK_DIGEST=$(printf '3%.0s' {1..64})
REF_PREFIX=ghcr.io/example/padm
mkdir -p "${MOCK_BIN}" "${STATE_ROOT}"/{backups,config/xray,config/sing-box,config/nginx,config/net,data/subscription,logs,secrets,locks}
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    printf 'docker-phase6-regression-fail: %s\n' "$*" >&2
    exit 1
}

for tool in bash jq sha256sum awk sed find mktemp stat; do
    command -v "${tool}" >/dev/null 2>&1 || fail "missing tool: ${tool}"
done

cat >"${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_DOCKER_LOG:?}"
case "${1:-}" in
compose)
    [[ "${2:-}" == version ]] && { printf 'v2.29.1\n'; exit 0; }
    if [[ " ${*} " == *' up -d '* && "${FAKE_DOCKER_FAIL_UP:-0}" == 1 &&
        ! -e "${FAKE_DOCKER_FAIL_MARK:?}" ]]; then
        : >"${FAKE_DOCKER_FAIL_MARK}"
        exit 1
    fi
    ;;
ps) ;;
pull) ;;
image) ;;
*) exit 0 ;;
esac
EOF
chmod 0755 "${MOCK_BIN}/docker"

cat >"${MANIFEST}" <<EOF
$(jq -n --arg old "${OLD_DIGEST}" --arg new "${NEW_DIGEST}" --arg prefix "${REF_PREFIX}" '
  def image($name): {reference: ($prefix + "-" + $name + ":3.2.0@sha256:" + $new), index_digest: ("sha256:" + $new),
    platforms: {"linux/amd64": ("sha256:" + ("4" * 64)), "linux/arm64": ("sha256:" + ("5" * 64))}};
  {schema_version: 1, release: {version: "3.2.0", commit: ("a" * 40), created_at: "2026-08-18T00:00:00Z"},
   control: {bundle_url: "https://example.invalid/bundle.tar.gz", sha256: ("b" * 64), min_version: "3.2.0"},
   images: {xray: image("xray"), "sing-box": image("sing-box"), nginx: image("nginx"), ops: image("ops"), net: image("net")},
   upstream: {alpine: "3", xray: "1", sing_box: "1", nginx: "1", acme_sh: "1"},
   formats: {compose: 1, config: 1, data: 1},
   compatibility: {host: ["linux", "rootful-docker", "compose-v2"], architectures: ["amd64", "arm64"], profiles: ["core-xray"], features_version: 1},
   migrations: []}' )
EOF

MSYS=winsymlinks:sys PATH="${MOCK_BIN}:${PATH}" FAKE_DOCKER_LOG="${DOCKER_LOG}" \
    FAKE_DOCKER_FAIL_MARK="${TEST_ROOT}/fail-up" \
    PHASE6_PROJECT_ROOT="${PROJECT_ROOT}" PHASE6_MANIFEST="${MANIFEST}" \
    PADM_DOCKER_INSTALL_DIR="${STATE_ROOT}" PADM_DOCKER_SKIP_CHOWN=1 \
    bash -uc '
        set -euo pipefail
        source "$PHASE6_PROJECT_ROOT/docker/lib/bootstrap.sh"
        source "$PHASE6_PROJECT_ROOT/docker/lib/manifest.sh"
        source "$PHASE6_PROJECT_ROOT/docker/lib/services.sh"
        source "$PHASE6_PROJECT_ROOT/docker/lib/lifecycle.sh"
        root=$(dockerInstallRoot)
        printf "docker\n" >"$root/mode"
        digest=$(printf "1%.0s" {1..64})
        ref="ghcr.io/example/padm-xray:3.1.9@sha256:$digest"
        jq -n --arg d "sha256:$digest" --arg r "$ref" "
          {schema_version: 1, mode: \"docker\", padm_version: \"3.1.9\", bundle_version: \"test\",
           manifest: {sha256: (\"a\" * 64), signature_identity: \"test\"},
           compose: {project: \"padm-docker\", profiles: [\"core-xray\"]}, core: {type: \"xray\", protocol_ids: [1]},
           listeners: [{service: \"xray\", public_port: 24443, container_port: 24443, transport: \"tcp\", address_families: [\"ipv4\"]}],
           images: {xray: {index_digest: \$d}, \"sing-box\": {index_digest: \$d}, nginx: {index_digest: \$d}, ops: {index_digest: \$d}, net: {index_digest: \$d}},
           formats: {compose: 1, config: 1, data: 1}, previous_manifest_sha256: null, host_integrations: []}" >"$root/deployment.json"
        printf "{}\n" >"$root/compose.json"
        for key in PADM_XRAY_IMAGE PADM_SINGBOX_IMAGE PADM_NGINX_IMAGE PADM_OPS_IMAGE PADM_NET_IMAGE; do
            printf "%s=%s\n" "$key" "ghcr.io/example/padm-test:3.1.9@sha256:$digest"
        done >"$root/images.env"
        printf "PADM_DOCKER_ROOT=%s\nPADM_NET_ROOT=%s\n" "$root" "$root" >>"$root/images.env"
        printf "old\n" >"$root/config/xray/config.json"
        source="$PHASE6_MANIFEST"
        dockerManifestValidate "$source"
        jq ".images.xray.reference = \"ghcr.io/example/padm-xray:3.2.0@sha256:$digest\"" "$source" >"$source.bad"
        ! dockerManifestValidate "$source.bad"
        dockerManifestVerifySignature() { return 1; }
        ! dockerManifestVerifySignature "$source" a b

        dockerHostPreflight() { :; }
        dockerLockInstalledDeployment() { :; }
        dockerManifestPrepare() {
            PADM_DOCKER_MANIFEST_FILE=$source
            PADM_DOCKER_MANIFEST_SHA256=$(printf "a%.0s" {1..64})
            PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=test
        }
        dockerManifestImageReference() { jq -er --arg n "$1" ".images[\$n].reference" "$PADM_DOCKER_MANIFEST_FILE"; }
        dockerManifestImageDigest() { jq -er --arg n "$1" ".images[\$n].index_digest" "$PADM_DOCKER_MANIFEST_FILE"; }
        dockerManifestReleaseVersion() { printf "3.2.0\n"; }
        dockerComposeFile() { printf "%s/compose.json\n" "$(dockerInstallRoot)"; }
        dockerRemoveCli() { :; }
        dockerUpdateCommand --manifest "$source"
        test "$(grep -c "^pull " "${FAKE_DOCKER_LOG}")" -eq 5
        grep -q "3.2.0@sha256:$(printf 2%.0s {1..64})" "$root/images.env"
        test -n "$(find "$root/backups" -maxdepth 1 -type d -name "update.*" -print -quit)"

        jq ".images.xray.index_digest = \"sha256:$(printf 3%.0s {1..64})\"" "$source" >"$source.rollback"
        source="$source.rollback"
        export FAKE_DOCKER_FAIL_UP=1
        dockerManifestPrepare() { PADM_DOCKER_MANIFEST_FILE=$source; PADM_DOCKER_MANIFEST_SHA256=$(printf "c%.0s" {1..64}); }
        dockerManifestImageReference() { jq -er --arg n "$1" ".images[\$n].reference" "$PADM_DOCKER_MANIFEST_FILE"; }
        dockerManifestImageDigest() { jq -er --arg n "$1" ".images[\$n].index_digest" "$PADM_DOCKER_MANIFEST_FILE"; }
        ! dockerUpdateCommand --manifest "$source"
        grep -q "3.2.0@sha256:$(printf 2%.0s {1..64})" "$root/images.env"
        latest=$(find "$root/backups" -maxdepth 1 -type d -name "update.*" -printf "%T@ %p\n" | sort -nr | head -n 1 | cut -d" " -f2-)
        rm -rf -- "$latest"
        unset FAKE_DOCKER_FAIL_UP
        dockerRollbackCommand
        grep -q "3.1.9@sha256:$(printf 1%.0s {1..64})" "$root/images.env"
        test -d "$root"
        ! dockerUninstallCommand --purge
        test -d "$root"
        dockerUninstallCommand
        test -d "$root"
        dockerUninstallCommand --purge --confirm PADM-DOCKER-PURGE
        test ! -e "$root"
    ' || fail 'phase 6 transaction contract failed'

printf 'docker-phase6-regression-ok\n'
