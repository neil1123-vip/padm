#!/usr/bin/env bash

# 仅用于离线回归：模拟验证器仍核对固定发布身份和实际清单摘要。
dockerConfigureTestFixture() {
    local source="${TEST_ROOT}/configure-control" relative controlSha
    CONFIGURE_MANIFEST="${TEST_ROOT}/configure-release-manifest.json"
    CONFIGURE_BUNDLE="${TEST_ROOT}/configure-release-manifest.sigstore.json"
    CONFIGURE_CONTROL="${TEST_ROOT}/configure-control.tar.gz"
    CONFIGURE_IDENTITY=https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main
    mkdir -p "${source}/docker" "${source}/shell/core"
    cp "${PROJECT_ROOT}/install-docker.sh" "${source}/install-docker.sh"
    cp -R "${PROJECT_ROOT}/docker/lib" "${source}/docker/lib"
    cp -R "${PROJECT_ROOT}/docker/contracts" "${source}/docker/contracts"
    for relative in deployment_mode.sh stats_grpc.sh runtime.sh reality_targets.sh; do
        cp "${PROJECT_ROOT}/shell/core/${relative}" "${source}/shell/core/${relative}"
    done
    tar -czf "${CONFIGURE_CONTROL}" -C "${source}" install-docker.sh docker shell
    controlSha=$(sha256sum "${CONFIGURE_CONTROL}" | cut -d ' ' -f 1)
    jq -n --arg sha "${controlSha}" --arg digest "${IMAGE_DIGEST}" --arg ops "${OPS_IMAGE}" '
      def image($name): {
        reference: ("ghcr.io/example/padm-" + $name + ":test@sha256:" + $digest),
        index_digest: ("sha256:" + $digest),
        platforms: {"linux/amd64": ("sha256:" + $digest), "linux/arm64": ("sha256:" + $digest)}
      };
      {schema_version: 1,
       release: {version: "3.1.8", commit: ("a" * 40), created_at: "2026-10-05T00:00:00Z"},
       control: {bundle_url: "https://example.invalid/control.tar.gz", sha256: $sha, min_version: "3.1.8"},
       images: {xray: image("xray"), "sing-box": image("sing-box"), nginx: image("nginx"),
         ops: (image("ops") | .reference = $ops), net: image("net")},
       upstream: {alpine: "3", xray: "1", sing_box: "1", nginx: "1", acme_sh: "1"},
       formats: {compose: 1, config: 1, data: 1},
       compatibility: {host: ["linux", "rootful-docker", "compose-v2"],
         architectures: ["amd64", "arm64"], profiles: ["core-xray", "core-sing-box", "nginx", "subscription"],
         features_version: 1},
       migrations: []}
    ' >"${CONFIGURE_MANIFEST}"
    CONFIGURE_MANIFEST_SHA=$(sha256sum "${CONFIGURE_MANIFEST}" | cut -d ' ' -f 1)
    jq -n --arg sha "${CONFIGURE_MANIFEST_SHA}" --arg identity "${CONFIGURE_IDENTITY}" '
      {signature: "fixture-valid", manifest_sha256: $sha, identity: $identity,
       issuer: "https://token.actions.githubusercontent.com"}
    ' >"${CONFIGURE_BUNDLE}"
    cat >"${MOCK_BIN}/cosign" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == verify-blob ]] || exit 1
shift
bundle= identity= issuer= manifest=
while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --bundle) bundle=$2; shift 2 ;;
    --certificate-identity-regexp) identity=$2; shift 2 ;;
    --certificate-oidc-issuer) issuer=$2; shift 2 ;;
    *) manifest=$1; shift ;;
    esac
done
[[ "${identity}" == '^https://github\.com/neil1123-vip/padm/\.github/workflows/create_release\.yml@refs/heads/main$' &&
    "${issuer}" == https://token.actions.githubusercontent.com ]] || exit 1
jq -e --arg sha "$(sha256sum "${manifest}" | cut -d ' ' -f 1)" '
  .signature == "fixture-valid" and .manifest_sha256 == $sha and
  .identity == "https://github.com/neil1123-vip/padm/.github/workflows/create_release.yml@refs/heads/main" and
  .issuer == "https://token.actions.githubusercontent.com"
' "${bundle}" >/dev/null
EOF
    chmod 0755 "${MOCK_BIN}/cosign"
}
