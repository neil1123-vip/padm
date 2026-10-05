#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/padm-docker-phase6.XXXXXX")
MOCK_BIN=${TEST_ROOT}/bin
STATE_ROOT=${TEST_ROOT}/state
DOCKER_LOG=${TEST_ROOT}/docker.log
MANIFEST=${TEST_ROOT}/release-manifest.json
CONTROL_SOURCE=${TEST_ROOT}/control-old
CONTROL_BUNDLE=${TEST_ROOT}/control-new.tar.gz
FAILED_CONTROL_BUNDLE=${TEST_ROOT}/control-failed.tar.gz
LEGACY_CONTROL_BUNDLE=${TEST_ROOT}/control-legacy.tar.gz
OLD_DIGEST=$(printf '1%.0s' {1..64})
NEW_DIGEST=$(printf '2%.0s' {1..64})
ROLLBACK_DIGEST=$(printf '3%.0s' {1..64})
REF_PREFIX=ghcr.io/example/padm
mkdir -p "${MOCK_BIN}" "${STATE_ROOT}"/{.bundles,backups,config/xray,config/sing-box,config/nginx,config/net,data/subscription,logs,secrets,locks}
trap 'rm -rf -- "${TEST_ROOT}"' EXIT

fail() {
    printf 'docker-phase6-regression-fail: %s\n' "$*" >&2
    exit 1
}

for tool in bash jq sha256sum awk sed find mktemp stat tar readlink; do
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

copyControlFixture() {
    local target=$1 marker=$2 relative
    for relative in \
        docker/lib/bootstrap.sh docker/lib/bundle.sh docker/lib/manifest.sh \
        docker/lib/services.sh docker/lib/traffic.sh docker/lib/lifecycle.sh docker/lib/setup.sh docker/lib/menu.sh \
        docker/contracts/configure.schema.json docker/contracts/deployment.schema.json \
        docker/contracts/features.json shell/core/deployment_mode.sh shell/core/stats_grpc.sh; do
        mkdir -p "${target}/$(dirname -- "${relative}")"
        cp "${PROJECT_ROOT}/${relative}" "${target}/${relative}"
    done
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "${marker}" >"${target}/install-docker.sh"
}
copyControlFixture "${CONTROL_SOURCE}" old-control
jq '.properties.schema_version = {const: 1}' \
    "${CONTROL_SOURCE}/docker/contracts/configure.schema.json" >"${TEST_ROOT}/legacy-schema.json"
mv -- "${TEST_ROOT}/legacy-schema.json" "${CONTROL_SOURCE}/docker/contracts/configure.schema.json"
copyControlFixture "${TEST_ROOT}/control-new" new-control
copyControlFixture "${TEST_ROOT}/control-failed" failed-control
tar -czf "${CONTROL_BUNDLE}" -C "${TEST_ROOT}/control-new" install-docker.sh docker shell
tar -czf "${FAILED_CONTROL_BUNDLE}" -C "${TEST_ROOT}/control-failed" install-docker.sh docker shell
tar -czf "${LEGACY_CONTROL_BUNDLE}" -C "${CONTROL_SOURCE}" install-docker.sh docker shell

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
    PHASE6_CONTROL_SOURCE="${CONTROL_SOURCE}" PHASE6_CONTROL_BUNDLE="${CONTROL_BUNDLE}" \
    PHASE6_FAILED_CONTROL_BUNDLE="${FAILED_CONTROL_BUNDLE}" \
    PHASE6_NEW_CONTROL_SOURCE="${TEST_ROOT}/control-new" PHASE6_LEGACY_CONTROL_BUNDLE="${LEGACY_CONTROL_BUNDLE}" \
    PADM_DOCKER_BIN_DIR="${TEST_ROOT}/installed-bin" \
    PADM_DOCKER_INSTALL_DIR="${STATE_ROOT}" PADM_DOCKER_SKIP_CHOWN=1 \
    bash -uc '
        set -Eeuo pipefail
        source "$PHASE6_PROJECT_ROOT/install-docker.sh" help
        trap "printf \"docker-phase6-error: source=%s line=%s stack=%s callers=%s command=%s\\n\" \"\${BASH_SOURCE[*]:-fixture}\" \"\${LINENO}\" \"\${FUNCNAME[*]:-main}\" \"\${BASH_LINENO[*]:-0}\" \"\${BASH_COMMAND}\" >&2" ERR
        root=$(dockerInstallRoot)
        oldCommit=$(printf "f%.0s" {1..40})
        newCommit=$(printf "a%.0s" {1..40})
        failedCommit=$(printf "d%.0s" {1..40})
        dockerInstallBundle "$PHASE6_CONTROL_SOURCE" "$oldCommit"
        dockerInstallCli
        oldBundle=$(readlink "$root/bundle")
        cli="$PADM_DOCKER_BIN_DIR/padm-docker"
        test "$(bash "$cli")" == old-control
        printf "docker\n" >"$root/mode"
        digest=$(printf "1%.0s" {1..64})
        ref="ghcr.io/example/padm-xray:3.1.9@sha256:$digest"
        jq -n --arg d "sha256:$digest" --arg r "$ref" --arg bundle "$oldCommit" "
          {schema_version: 1, mode: \"docker\", padm_version: \"3.1.9\", bundle_version: \$bundle,
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
        printf "%s\n" "{\"inbounds\":[{\"protocol\":\"vless\",\"tag\":\"test\",\"settings\":{\"clients\":[{\"id\":\"11111111-1111-4111-8111-111111111111\",\"email\":\"test\"}]}}]}" >"$root/config/xray/config.json"
        source="$PHASE6_MANIFEST"
        dockerManifestValidate "$source"
        jq ".images.xray.reference = \"ghcr.io/example/padm-xray:3.2.0@sha256:$digest\"" "$source" >"$source.bad"
        ! dockerManifestValidate "$source.bad"
        dockerManifestVerifySignature() { return 1; }
        ! dockerManifestVerifySignature "$source" b

        dockerHostPreflight() { :; }
        dockerLockInstalledDeployment() { :; }
        dockerTrafficScheduleCheck() { :; }
        dockerTrafficScheduleInstall() { :; }
        dockerTrafficScheduleRemove() { :; }
        dockerTrafficBeforeChange() { :; }
        dockerManifestPrepare() {
            PADM_DOCKER_MANIFEST_FILE=$source
            PADM_DOCKER_MANIFEST_SHA256=$(sha256sum "$source" | awk "{print \$1}")
            PADM_DOCKER_MANIFEST_SIGNATURE_IDENTITY=test
            PADM_DOCKER_MANIFEST_TEMP_DIR="$root/.manifest-fixture"
            mkdir -p "$PADM_DOCKER_MANIFEST_TEMP_DIR"
            PADM_DOCKER_CONTROL_BUNDLE=$control
        }
        dockerManifestImageReference() { jq -er --arg n "$1" ".images[\$n].reference" "$PADM_DOCKER_MANIFEST_FILE"; }
        dockerManifestImageDigest() { jq -er --arg n "$1" ".images[\$n].index_digest" "$PADM_DOCKER_MANIFEST_FILE"; }
        dockerManifestReleaseVersion() { printf "3.2.0\n"; }
        dockerComposeFile() { printf "%s/compose.json\n" "$(dockerInstallRoot)"; }
        dockerRemoveCli() { :; }
        assertCurrent() {
            local bundle=$1 commit=$2 marker=$3 imageDigest=$4 path
            test "$(readlink "$root/bundle")" == "$bundle"
            path=$(dockerCurrentBundlePath)
            test "$(<"$path/$PADM_DOCKER_BUNDLE_REF")" == "$commit"
            test "$(readlink "$cli")" == "$root/bundle/install-docker.sh"
            test "$(bash "$cli")" == "$marker"
            jq -e --arg bundle "$commit" --arg digest "sha256:$imageDigest" \
                ".bundle_version == \$bundle and (.images | length) == 5 and all(.images[]; .index_digest == \$digest)" \
                "$root/deployment.json" >/dev/null
            test "$(grep -c "@sha256:$imageDigest$" "$root/images.env")" -eq 5
        }
        control=$PHASE6_CONTROL_BUNDLE
        dockerUpdateCommand --manifest "$source"
        test "$(grep -c "^pull " "${FAKE_DOCKER_LOG}")" -eq 5
        newBundle=$(readlink "$root/bundle")
        test "$newBundle" != "$oldBundle"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        successfulBackup=$DOCKER_CONFIG_BACKUP
        test "$(<"$successfulBackup/bundle.target")" == "$oldBundle"
        ! grep -qxF bundle.target "$successfulBackup/present"
        # 旧版没有原始规格的部署与快照仍能更新和回滚。
        ! grep -qxF config/spec.json "$successfulBackup/present"
        test ! -e "$root/config/spec.json"
        dockerValidateConfigurationBackup "$successfulBackup"
        dockerCleanupStagedBundle

        jq --arg commit "$failedCommit" --arg digest "$(printf 3%.0s {1..64})" \
            ".release.commit = \$commit | .images |= with_entries(.value.index_digest = \"sha256:\" + \$digest |
              .value.reference |= sub(\"@sha256:[0-9a-f]+$\"; \"@sha256:\" + \$digest))" \
            "$source" >"$source.rollback"
        source="$source.rollback"
        control=$PHASE6_FAILED_CONTROL_BUNDLE
        # 所有切换后的故障都必须恢复同一组控制脚本、镜像与部署记录。
        for failure in health schedule activation; do
            case "$failure" in
            health) export FAKE_DOCKER_FAIL_UP=1 ;;
            schedule) dockerTrafficScheduleInstall() { return 1; } ;;
            activation) mkdir "$root/.bundle-link.${BASHPID:-$$}" ;;
            esac
            ! dockerUpdateCommand --manifest "$source"
            assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
            test "$DOCKER_CONFIG_BACKUP" != "$successfulBackup"
            test -d "$DOCKER_CONFIG_BACKUP"
            test "$(<"$DOCKER_CONFIG_BACKUP/bundle.target")" == "$newBundle"
            test ! -e "$root/config/spec.json"
            dockerRemoveManagedTree "$root" "$DOCKER_CONFIG_BACKUP"
            dockerCleanupStagedBundle
            unset FAKE_DOCKER_FAIL_UP
            dockerTrafficScheduleInstall() { :; }
            if [[ "$failure" == activation ]]; then
                dockerRemoveManagedTree "$root" "$root/.bundle-link.${BASHPID:-$$}"
            fi
        done
        # 缺失内容和越界成员在拉取镜像、停止现有服务之前被拒绝。
        mkdir "$root/incomplete-control"
        printf "incomplete\n" >"$root/incomplete-control/install-docker.sh"
        tar -czf "$root/incomplete-control.tar.gz" -C "$root/incomplete-control" install-docker.sh
        tar -czf "$root/unsafe-control.tar.gz" --transform="s|^install-docker.sh$|../outside-control|" \
            -C "$PHASE6_CONTROL_SOURCE" install-docker.sh
        for control in "$root/missing-control.tar.gz" "$root/incomplete-control.tar.gz" "$root/unsafe-control.tar.gz"; do
            logBefore=$(wc -l <"$FAKE_DOCKER_LOG")
            ! dockerUpdateCommand --manifest "$source"
            test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
            assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        done
        # 损坏的新快照不能绕过校验，恢复也不能先停止当前服务。
        printf "../outside-control\n" >"$successfulBackup/bundle.target"
        ! dockerValidateConfigurationBackup "$successfulBackup"
        DOCKER_CONFIG_BACKUP=$successfulBackup
        DOCKER_CONFIG_SWITCHED=1
        logBefore=$(wc -l <"$FAKE_DOCKER_LOG")
        ! dockerRestoreConfiguration
        test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
        ! dockerRollbackCommand
        test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test ! -e "$root/config/spec.json"
        printf "%s\n" "$oldBundle" >"$successfulBackup/bundle.target"
        DOCKER_CONFIG_SWITCHED=0
        scheduleAttempts=0
        dockerTrafficScheduleInstall() { scheduleAttempts=$((scheduleAttempts + 1)); [[ "$scheduleAttempts" -gt 1 ]]; }
        ! dockerRollbackCommand
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        [[ "$scheduleAttempts" == 2 ]]
        dockerTrafficScheduleInstall() { :; }
        dockerRollbackCommand
        assertCurrent "$oldBundle" "$oldCommit" old-control "$(printf 1%.0s {1..64})"
        test ! -e "$root/config/spec.json"
        dockerValidateConfigurationBackup "$successfulBackup"
        rm -f -- "$successfulBackup/bundle.target"
        dockerValidateConfigurationBackup "$successfulBackup"
        dockerRemoveManagedTree "$root" "$successfulBackup"

        # 受管规格只更新发布输入，其余账号、参数和协议输入必须完整保留。
        oldSpec="$root/.spec-before-update.json"
        newSpec="$root/.spec-after-update.json"
        jq --arg ref "ghcr.io/example/padm-test:3.1.9@sha256:$digest" "
          .release = {version: \"3.1.9\", manifest_sha256: (\"a\" * 64), signature_identity: \"test\"} |
          .core.protocols[0].public_port = 24443 |
          .core.protocols[0].address_families = [\"ipv4\"] |
          .images |= map_values(\$ref)
        " "$PHASE6_PROJECT_ROOT/docker/configure.example.json" >"$oldSpec"
        cp -- "$oldSpec" "$root/config/spec.json"
        chmod 0600 "$oldSpec" "$root/config/spec.json"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" \
            "$root/deployment.json" "$root/images.env"
        source="$PHASE6_MANIFEST"
        manifestSha=$(sha256sum "$source" | awk "{print \$1}")
        jq --arg sha "$manifestSha" --slurpfile manifest "$source" "
          .release = {version: \$manifest[0].release.version, manifest_sha256: \$sha, signature_identity: \"test\"} |
          .images = (\$manifest[0].images | map_values(.reference))
        " "$oldSpec" >"$newSpec"
        chmod 0600 "$newSpec"
        control=$PHASE6_CONTROL_BUNDLE
        dockerUpdateCommand --manifest "$source"
        newBundle=$(readlink "$root/bundle")
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$newSpec")"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" \
            "$root/deployment.json" "$root/images.env"
        successfulBackup=$DOCKER_CONFIG_BACKUP
        grep -qxF config/spec.json "$successfulBackup/present"
        test "$(jq -Sc . "$successfulBackup/config/spec.json")" == "$(jq -Sc . "$oldSpec")"
        dockerManagedSpecMatchesDeployment "$successfulBackup/config/spec.json" \
            "$successfulBackup/deployment.json" "$successfulBackup/images.env"
        dockerValidateConfigurationBackup "$successfulBackup"
        dockerCleanupStagedBundle

        source="$PHASE6_MANIFEST.rollback"
        control=$PHASE6_FAILED_CONTROL_BUNDLE
        rm -f -- "$FAKE_DOCKER_FAIL_MARK"
        export FAKE_DOCKER_FAIL_UP=1
        ! dockerUpdateCommand --manifest "$source"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$newSpec")"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" \
            "$root/deployment.json" "$root/images.env"
        test "$DOCKER_CONFIG_BACKUP" != "$successfulBackup"
        dockerValidateConfigurationBackup "$DOCKER_CONFIG_BACKUP"
        dockerRemoveManagedTree "$root" "$DOCKER_CONFIG_BACKUP"
        dockerCleanupStagedBundle
        unset FAKE_DOCKER_FAIL_UP

        # 每种损坏快照都在调用 Docker 前拒绝，不能回退选中另一份有效更新快照。
        cp -- "$successfulBackup/present" "$root/.spec-backup-present"
        for corruption in json release digest reference unlisted deployment-unlisted; do
            cp -- "$root/.spec-backup-present" "$successfulBackup/present"
            case "$corruption" in
            json) printf "{\n" >"$successfulBackup/config/spec.json" ;;
            release)
                jq ".release.version = \"9.9.9\"" "$oldSpec" >"$successfulBackup/config/spec.json"
                ;;
            digest)
                jq ".images.ops |= sub(\"@sha256:[0-9a-f]+$\"; \"@sha256:\" + (\"3\" * 64))" \
                    "$oldSpec" >"$successfulBackup/config/spec.json"
                ;;
            reference)
                jq ".images.ops |= sub(\"padm-test\"; \"padm-wrong\")" \
                    "$oldSpec" >"$successfulBackup/config/spec.json"
                ;;
            unlisted)
                cp -- "$oldSpec" "$successfulBackup/config/spec.json"
                sed "/^config\\/spec\\.json$/d" "$root/.spec-backup-present" >"$successfulBackup/present"
                ;;
            deployment-unlisted)
                cp -- "$oldSpec" "$successfulBackup/config/spec.json"
                sed "/^deployment\\.json$/d" "$root/.spec-backup-present" >"$successfulBackup/present"
                ;;
            esac
            ! dockerValidateConfigurationBackup "$successfulBackup"
            logBefore=$(wc -l <"$FAKE_DOCKER_LOG")
            DOCKER_CONFIG_BACKUP=$successfulBackup
            DOCKER_CONFIG_SWITCHED=1
            ! dockerRestoreConfiguration
            test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
            DOCKER_CONFIG_SWITCHED=0
            ! dockerRollbackCommand
            test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
            assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
            test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$newSpec")"
        done
        cp -- "$oldSpec" "$successfulBackup/config/spec.json"
        cp -- "$root/.spec-backup-present" "$successfulBackup/present"
        dockerValidateConfigurationBackup "$successfulBackup"
        scheduleAttempts=0
        dockerTrafficScheduleInstall() { scheduleAttempts=$((scheduleAttempts + 1)); [[ "$scheduleAttempts" -gt 1 ]]; }
        ! dockerRollbackCommand
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$newSpec")"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" \
            "$root/deployment.json" "$root/images.env"
        [[ "$scheduleAttempts" == 2 ]]
        dockerTrafficScheduleInstall() { :; }
        dockerRollbackCommand
        assertCurrent "$oldBundle" "$oldCommit" old-control "$(printf 1%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$oldSpec")"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" \
            "$root/deployment.json" "$root/images.env"
        cp -- "$root/config/spec.json" "$root/.spec-before-invalid-backup"
        jq ".release.version = \"9.9.9\"" "$root/.spec-before-invalid-backup" >"$root/config/spec.json"
        logBefore=$(wc -l <"$FAKE_DOCKER_LOG")
        ! dockerBackupConfiguration configure
        test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
        cp -- "$root/.spec-before-invalid-backup" "$root/config/spec.json"

        # 多入口更新保留稳定身份和累计流量，旧格式控制脚本不能接管 v2。
        legacySpecBackup=$successfulBackup
        dockerInstallBundle "$PHASE6_NEW_CONTROL_SOURCE" "$newCommit"
        newBundle=$(readlink "$root/bundle")
        multiOldSpec="$root/.spec-v2-before-update.json"
        multiNewSpec="$root/.spec-v2-after-update.json"
        dockerConfigureSpecMigrate "$oldSpec" "$root/.spec-v2-migrated.json"
        jq ".core.protocols += [(.core.protocols[0] |
          .listener_id = \"entry-secondary\" | .public_port = 25443 | .name = \"secondary\")]" \
            "$root/.spec-v2-migrated.json" >"$multiOldSpec"
        cp -- "$multiOldSpec" "$root/config/spec.json"
        chmod 0600 "$multiOldSpec" "$root/config/spec.json"
        dockerGenerateXrayConfig "$multiOldSpec" "$root/config/xray/config.json"
        cp -- "$root/config/xray/config.json" "$root/config/xray/users.base"
        mkdir -p "$root/data/traffic"
        jq -n --arg account "$(jq -r ".core.protocols[0].uuid" "$multiOldSpec")" "
          {schema_version:1, accounts:{(\$account):{name:\"main-reality\", upload:7,
            download:11, limit_bytes:0, baseline:{}}}}" >"$root/data/traffic/state.json"
        trafficBefore=$(jq -Sc . "$root/data/traffic/state.json")
        dockerTrafficPrepareCandidate "$root"
        dockerGenerateCompose "$multiOldSpec" "$root/compose.json"
        dockerGenerateDeployment "$multiOldSpec" "$root/deployment.json"
        dockerManagedSpecMatchesDeployment "$root/config/spec.json" "$root/deployment.json" "$root/images.env"
        listenersBefore=$(jq -Sc ".listeners" "$root/deployment.json")
        source="$PHASE6_MANIFEST"
        manifestSha=$(sha256sum "$source" | awk "{print \$1}")
        jq --arg sha "$manifestSha" --slurpfile manifest "$source" "
          .release = {version: \$manifest[0].release.version, manifest_sha256: \$sha, signature_identity: \"test\"} |
          .images = (\$manifest[0].images | map_values(.reference))
        " "$multiOldSpec" >"$multiNewSpec"
        control=$PHASE6_CONTROL_BUNDLE
        dockerUpdateCommand --manifest "$source"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$multiNewSpec")"
        test "$(jq -Sc ".listeners" "$root/deployment.json")" == "$listenersBefore"
        test "$(jq -Sc . "$root/data/traffic/state.json")" == "$trafficBefore"
        multiBackup=$DOCKER_CONFIG_BACKUP
        dockerValidateConfigurationBackup "$multiBackup"
        dockerCleanupStagedBundle

        ! dockerInstallBundle "$PHASE6_CONTROL_SOURCE" "$oldCommit"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        dockerCleanupStagedBundle
        control=$PHASE6_LEGACY_CONTROL_BUNDLE
        ! dockerUpdateCommand --manifest "$source"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$multiNewSpec")"
        dockerCleanupStagedBundle

        source="$PHASE6_MANIFEST.rollback"
        control=$PHASE6_FAILED_CONTROL_BUNDLE
        rm -f -- "$FAKE_DOCKER_FAIL_MARK"
        export FAKE_DOCKER_FAIL_UP=1
        ! dockerUpdateCommand --manifest "$source"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$multiNewSpec")"
        test "$(jq -Sc ".listeners" "$root/deployment.json")" == "$listenersBefore"
        test "$(jq -Sc . "$root/data/traffic/state.json")" == "$trafficBefore"
        dockerRemoveManagedTree "$root" "$DOCKER_CONFIG_BACKUP"
        dockerCleanupStagedBundle
        unset FAKE_DOCKER_FAIL_UP

        # 恢复先验证目标规格与目标 bundle，不能误拿仍在运行的 v2 规格限制合法 v1 回滚。
        printf "%s\n" "$oldBundle" >"$multiBackup/bundle.target"
        ! dockerValidateConfigurationBackup "$multiBackup"
        DOCKER_CONFIG_BACKUP=$multiBackup
        DOCKER_CONFIG_SWITCHED=1
        logBefore=$(wc -l <"$FAKE_DOCKER_LOG")
        ! dockerRestoreConfiguration
        test "$(wc -l <"$FAKE_DOCKER_LOG")" == "$logBefore"
        assertCurrent "$newBundle" "$newCommit" new-control "$(printf 2%.0s {1..64})"
        printf "%s\n" "$newBundle" >"$multiBackup/bundle.target"
        DOCKER_CONFIG_SWITCHED=0
        dockerValidateConfigurationBackup "$multiBackup"
        dockerLatestUpdateBackup() { printf "%s\n" "$legacySpecBackup"; }
        dockerRollbackCommand
        assertCurrent "$oldBundle" "$oldCommit" old-control "$(printf 1%.0s {1..64})"
        test "$(jq -Sc . "$root/config/spec.json")" == "$(jq -Sc . "$oldSpec")"
        test "$(jq -Sc . "$root/data/traffic/state.json")" == "$trafficBefore"

        test -d "$root"
        ! dockerUninstallCommand --purge
        test -d "$root"
        dockerUninstallCommand
        test -d "$root"
        dockerUninstallCommand --purge --confirm PADM-DOCKER-PURGE
        test ! -e "$root"
    ' || fail 'phase 6 transaction contract failed'

(
    source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"
    scheduleRoot="${TEST_ROOT}/schedule"
    export PADM_DOCKER_SYSTEMD_DIR="${scheduleRoot}/units"
    export PADM_DOCKER_BIN_DIR="${scheduleRoot}/bin"
    mkdir -p "${scheduleRoot}/locks" "${PADM_DOCKER_SYSTEMD_DIR}" "${PADM_DOCKER_BIN_DIR}"
    dockerInstallRoot() { printf '%s\n' "${scheduleRoot}"; }
    dockerError() { printf '%s\n' "$*" >&2; }
    scheduler=systemd
    systemctl() {
        [[ "${scheduler}" == systemd ]] || return 1
        printf '%s\n' "$*" >>"${scheduleRoot}/systemctl.log"
    }
    pgrep() { [[ "${scheduler}" == cron ]]; }
    crontab() {
        if [[ "$1" == -l ]]; then
            if [[ -f "${scheduleRoot}/crontab" ]]; then cat "${scheduleRoot}/crontab";
            else printf 'no crontab for root\n' >&2; return 1; fi
        else
            cat >"${scheduleRoot}/crontab"
        fi
    }
    dockerTrafficScheduleInstall
    dockerTrafficScheduleInstall
    grep -qF "Environment=PADM_DOCKER_INSTALL_DIR=${scheduleRoot}" "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service"
    grep -qF 'traffic collect' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.service"
    grep -qxF 'AccuracySec=1s' "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.timer"
    dockerTrafficScheduleRemove
    [[ ! -e "${PADM_DOCKER_SYSTEMD_DIR}/padm-docker-traffic.timer" ]]
    scheduler=cron
    printf '0 0 * * * true # existing-job\n' >"${scheduleRoot}/crontab"
    dockerTrafficScheduleInstall
    dockerTrafficScheduleInstall
    [[ "$(grep -c '# padm-docker-traffic$' "${scheduleRoot}/crontab")" == 1 ]]
    dockerTrafficScheduleRemove
    [[ "$(<"${scheduleRoot}/crontab")" == '0 0 * * * true # existing-job' ]]
    scheduler=none
    ! dockerTrafficScheduleCheck
)

(
    source "${PROJECT_ROOT}/docker/lib/bootstrap.sh"
    source "${PROJECT_ROOT}/docker/lib/lifecycle.sh"
    rollbackRoot="${TEST_ROOT}/rollback-capability"
    rollbackFixture="${rollbackRoot}/backups/update.test"
    export PADM_DOCKER_INSTALL_DIR="${rollbackRoot}"
    mkdir -p "${rollbackFixture}" "${rollbackRoot}/config/sing-box"
    printf '%s\n' '{"core":{"type":"sing-box"}}' >"${rollbackFixture}/deployment.json"
    printf '{}\n' >"${rollbackRoot}/config/sing-box/users.base"
    dockerHostPreflight() { :; }
    dockerLockInstalledDeployment() { :; }
    dockerComposeFile() { :; }
    dockerLatestUpdateBackup() { printf '%s\n' "${rollbackFixture}"; }
    dockerTrafficBeforeChange() { touch "${rollbackRoot}/changed"; }
    dockerCandidateCompose() { touch "${rollbackRoot}/checked"; printf 'sing-box version 1.14.0\nTags: with_quic\n'; }
    ! dockerRollbackCommand
    [[ -f "${rollbackRoot}/checked" && ! -e "${rollbackRoot}/changed" ]]
    dockerCandidateCompose() { printf 'sing-box version 1.14.0\nTags: with_quic,with_v2ray_api\n'; }
    dockerTrafficRollbackCheck "${rollbackFixture}"
    dockerTrafficRuntimeCheck() { :; }
    dockerTrafficBeforeChange() { :; }
    dockerTrafficScheduleInstall() { return 1; }
    dockerComposeRun() { touch "${rollbackRoot}/changed"; }
    ! dockerLifecycleCommand up
    ! dockerLifecycleCommand restart
    [[ ! -e "${rollbackRoot}/changed" ]]
)

printf 'docker-phase6-regression-ok\n'
