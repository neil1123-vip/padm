#!/usr/bin/env bash

if [[ "${PADM_DOCKER_BUNDLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_BUNDLE_LOADED=1

readonly PADM_DOCKER_BUNDLE_MANIFEST=.padm-docker-bundle-manifest
readonly PADM_DOCKER_BUNDLE_REF=.padm-docker-bundle-ref
DOCKER_BUNDLE_LINK_TEMP_PATH=
DOCKER_BUNDLE_LINK_TEMP_TARGET=

dockerBundleRelativePathIsSafe() {
    local path=$1 segment
    local -a segments=()
    [[ -n "${path}" && "${path}" != /* && "${path}" != *[[:space:]]* ]] || return 1
    IFS='/' read -r -a segments <<<"${path}"
    for segment in "${segments[@]}"; do
        [[ -n "${segment}" && "${segment}" != "." && "${segment}" != ".." ]] || return 1
    done
}

dockerBundlePayloadPaths() {
    local sourceRoot=$1 path paths
    [[ -f "${sourceRoot}/install-docker.sh" && ! -L "${sourceRoot}/install-docker.sh" ]] || return 1
    [[ -d "${sourceRoot}/docker" && ! -L "${sourceRoot}/docker" ]] || return 1
    paths=$(find "${sourceRoot}/docker" -type l -print -quit 2>/dev/null) || return 1
    [[ -z "${paths}" ]] || return 1
    [[ -f "${sourceRoot}/shell/core/deployment_mode.sh" &&
        ! -L "${sourceRoot}/shell/core/deployment_mode.sh" ]] || return 1
    printf 'install-docker.sh\n'
    paths=$(find "${sourceRoot}/docker" -type f -print) || return 1
    paths=$(LC_ALL=C sort <<<"${paths}") || return 1
    while IFS= read -r path; do
        [[ -n "${path}" ]] || continue
        path=${path#"${sourceRoot}/"}
        dockerBundleRelativePathIsSafe "${path}" || return 1
        printf '%s\n' "${path}"
    done <<<"${paths}"
    printf 'shell/core/deployment_mode.sh\n'
    printf 'shell/core/stats_grpc.sh\n'
    if [[ "$(<"${sourceRoot}/docker/lib/lifecycle.sh")" == *'/shell/core/cores.sh"'* ]]; then
        [[ -f "${sourceRoot}/shell/core/cores.sh" && ! -L "${sourceRoot}/shell/core/cores.sh" ]] || return 1
        printf 'shell/core/cores.sh\n'
    fi
    if [[ -f "${sourceRoot}/docker/lib/reality-targets.sh" ]]; then
        for path in shell/core/runtime.sh shell/core/reality_targets.sh; do
            [[ -f "${sourceRoot}/${path}" && ! -L "${sourceRoot}/${path}" ]] || return 1
            printf '%s\n' "${path}"
        done
    fi
    if [[ -d "${sourceRoot}/documents" && ! -L "${sourceRoot}/documents" ]]; then
        paths=$(find "${sourceRoot}/documents" -maxdepth 1 -type f -name 'docker*.md' -print) || return 1
        paths=$(LC_ALL=C sort <<<"${paths}") || return 1
        while IFS= read -r path; do
            [[ -n "${path}" ]] || continue
            path=${path#"${sourceRoot}/"}
            dockerBundleRelativePathIsSafe "${path}" || return 1
            printf '%s\n' "${path}"
        done <<<"${paths}"
    fi
}

dockerBundleSourceIsComplete() {
    local sourceRoot=$1 required
    [[ -d "${sourceRoot}" && ! -L "${sourceRoot}" ]] || return 1
    for required in \
        install-docker.sh \
        docker/lib/bootstrap.sh \
        docker/lib/bundle.sh \
        docker/lib/manifest.sh \
        docker/lib/services.sh \
        docker/lib/traffic.sh \
        docker/lib/lifecycle.sh \
        docker/lib/setup.sh \
        docker/lib/accounts.sh \
        docker/lib/subscriptions.sh \
        docker/lib/business.sh \
        docker/lib/menu.sh \
        docker/contracts/configure.schema.json \
        docker/contracts/deployment.schema.json \
        docker/contracts/features.json \
        shell/core/deployment_mode.sh \
        shell/core/stats_grpc.sh; do
        [[ -f "${sourceRoot}/${required}" && ! -L "${sourceRoot}/${required}" ]] || return 1
    done
    for required in renewal schedule geo control-sync control; do
        if grep -qF "/${required}.sh\"" "${sourceRoot}/docker/lib/services.sh"; then
            [[ -f "${sourceRoot}/docker/lib/${required}.sh" &&
                ! -L "${sourceRoot}/docker/lib/${required}.sh" ]] || return 1
        fi
    done
    if grep -qF '/docker/lib/ssh-source.py"' "${sourceRoot}/docker/lib/services.sh"; then
        for required in ssh-source.py ssh-source-client.py; do
            [[ -f "${sourceRoot}/docker/lib/${required}" &&
                ! -L "${sourceRoot}/docker/lib/${required}" ]] || return 1
        done
    fi
    if grep -qF '/reality-targets.sh"' "${sourceRoot}/docker/lib/services.sh"; then
        for required in docker/lib/reality-targets.sh shell/core/runtime.sh shell/core/reality_targets.sh; do
            [[ -f "${sourceRoot}/${required}" && ! -L "${sourceRoot}/${required}" ]] || return 1
        done
    fi
    dockerBundlePayloadPaths "${sourceRoot}" >/dev/null
}

dockerBundleHashPaths() {
    local root=$1 pathList=$2 output=$3 relativePath
    local -a files=()
    while IFS= read -r relativePath; do
        dockerBundleRelativePathIsSafe "${relativePath}" || return 1
        # manifest 不接受 sha256sum 的文件名转义格式。
        [[ "${relativePath}" != *'\'* ]] || return 1
        [[ -f "${root}/${relativePath}" && ! -L "${root}/${relativePath}" ]] || return 1
        files+=("${relativePath}")
    done <"${pathList}"
    ((${#files[@]} > 0)) || return 1
    if ! (cd -- "${root}" && sha256sum -- "${files[@]}") >"${output}"; then
        rm -f -- "${output}"
        return 1
    fi
}

dockerBundleRefIsValid() {
    [[ "$1" =~ ^[0-9a-f]{40}$ || "$1" =~ ^sha256:[0-9a-f]{64}$ ]]
}

dockerBundleSourceDigest() {
    local sourceRoot=$1 pathList hashList digest
    pathList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-source.XXXXXX") || return 1
    dockerBundlePayloadPaths "${sourceRoot}" >"${pathList}" || {
        rm -f -- "${pathList}"
        return 1
    }
    hashList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-source-hashes.XXXXXX") || {
        rm -f -- "${pathList}"
        return 1
    }
    dockerBundleHashPaths "${sourceRoot}" "${pathList}" "${hashList}" || {
        rm -f -- "${pathList}" "${hashList}"
        return 1
    }
    digest=$(sha256sum -- "${hashList}") || {
        rm -f -- "${pathList}" "${hashList}"
        return 1
    }
    digest=${digest%% *}
    rm -f -- "${pathList}" "${hashList}"
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf 'sha256:%s\n' "${digest}"
}

dockerResolveBundleRef() {
    local sourceRoot=$1 requestedRef=${2:-} ref
    if [[ -n "${requestedRef}" ]]; then
        dockerBundleRefIsValid "${requestedRef}" || return 1
        printf '%s\n' "${requestedRef}"
        return 0
    fi
    if [[ -n "${DOCKER_ENTRY_FETCHED_REF:-}" ]]; then
        dockerBundleRefIsValid "${DOCKER_ENTRY_FETCHED_REF}" || return 1
        printf '%s\n' "${DOCKER_ENTRY_FETCHED_REF}"
        return 0
    fi
    if [[ -f "${sourceRoot}/${PADM_DOCKER_BUNDLE_REF}" &&
        ! -L "${sourceRoot}/${PADM_DOCKER_BUNDLE_REF}" ]]; then
        ref=$(<"${sourceRoot}/${PADM_DOCKER_BUNDLE_REF}")
        dockerBundleRefIsValid "${ref}" || return 1
        printf '%s\n' "${ref}"
        return 0
    fi
    if command -v git >/dev/null 2>&1 &&
        [[ -z "$(git -C "${sourceRoot}" status --porcelain --untracked-files=normal -- . 2>/dev/null)" ]]; then
        ref=$(git -C "${sourceRoot}" rev-parse --verify HEAD 2>/dev/null || true)
        if [[ "${ref}" =~ ^[0-9a-f]{40}$ ]]; then
            printf '%s\n' "${ref}"
            return 0
        fi
    fi
    dockerBundleSourceDigest "${sourceRoot}"
}

dockerWriteBundleManifest() {
    local bundleRoot=$1 manifest tempList
    manifest="${bundleRoot}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    tempList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-paths.XXXXXX") || return 1
    dockerBundlePayloadPaths "${bundleRoot}" >"${tempList}" || {
        rm -f -- "${tempList}"
        return 1
    }
    printf '%s\n' "${PADM_DOCKER_BUNDLE_REF}" >>"${tempList}" || {
        rm -f -- "${tempList}"
        return 1
    }
    if ! LC_ALL=C sort -u "${tempList}" -o "${tempList}"; then
        rm -f -- "${tempList}"
        return 1
    fi
    dockerBundleHashPaths "${bundleRoot}" "${tempList}" "${manifest}" || {
        rm -f -- "${tempList}"
        rm -f -- "${manifest}"
        return 1
    }
    rm -f -- "${tempList}"
    chmod 0640 "${manifest}"
}

dockerValidateBundle() {
    local bundleRoot=$1 manifest expectedList manifestList line expectedHash relativePath status directory directories
    manifest="${bundleRoot}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    [[ -d "${bundleRoot}" && ! -L "${bundleRoot}" && -O "${bundleRoot}" &&
        -f "${manifest}" && ! -L "${manifest}" && -O "${manifest}" ]] || return 1
    dockerBundleSourceIsComplete "${bundleRoot}" || return 1
    directories=$(find "${bundleRoot}" -type d -print) || return 1
    while IFS= read -r directory; do
        [[ -O "${directory}" ]] || return 1
    done <<<"${directories}"
    expectedList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-expected.XXXXXX") || return 1
    manifestList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-manifest.XXXXXX") || {
        rm -f -- "${expectedList}"
        return 1
    }
    if ! dockerBundlePayloadPaths "${bundleRoot}" >"${expectedList}" ||
        ! printf '%s\n' "${PADM_DOCKER_BUNDLE_REF}" >>"${expectedList}" ||
        ! LC_ALL=C sort -u "${expectedList}" -o "${expectedList}"; then
        rm -f -- "${expectedList}" "${manifestList}"
        return 1
    fi
    : >"${manifestList}"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ ! "${line}" =~ ^([0-9a-f]{64})[[:space:]][[:space:]]([^[:space:]]+)$ ]]; then
            rm -f -- "${expectedList}" "${manifestList}"
            return 1
        fi
        expectedHash=${BASH_REMATCH[1]}
        relativePath=${BASH_REMATCH[2]}
        dockerBundleRelativePathIsSafe "${relativePath}" || {
            rm -f -- "${expectedList}" "${manifestList}"
            return 1
        }
        [[ -f "${bundleRoot}/${relativePath}" && ! -L "${bundleRoot}/${relativePath}" &&
            -O "${bundleRoot}/${relativePath}" ]] || {
            rm -f -- "${expectedList}" "${manifestList}"
            return 1
        }
        printf '%s  %s\n' "${expectedHash}" "${relativePath}" >>"${manifestList}"
    done <"${manifest}"
    LC_ALL=C sort -k2,2 "${manifestList}" -o "${manifestList}" || {
        rm -f -- "${expectedList}" "${manifestList}"
        return 1
    }
    [[ -z "$(cut -c 67- "${manifestList}" | uniq -d)" ]] &&
        cmp -s "${expectedList}" <(cut -c 67- "${manifestList}") &&
        (cd -- "${bundleRoot}" && sha256sum --check --status --strict) <"${manifestList}"
    status=$?
    rm -f -- "${expectedList}" "${manifestList}"
    return "${status}"
}

dockerStageBundle() {
    local sourceRoot=$1 requestedRef=${2:-} root bundlesRoot stageDir candidate relativePath ref payloadPaths
    root=$(dockerInstallRoot) || return 1
    bundlesRoot="${root}/.bundles"
    [[ -d "${bundlesRoot}" && ! -L "${bundlesRoot}" ]] || return 1
    dockerBundleSourceIsComplete "${sourceRoot}" || {
        dockerError "Docker bundle 源不完整: ${sourceRoot}"
        return 1
    }
    ref=$(dockerResolveBundleRef "${sourceRoot}" "${requestedRef}") || {
        dockerError '无法确定 Docker bundle ref'
        return 1
    }
    payloadPaths=$(dockerBundlePayloadPaths "${sourceRoot}") || return 1
    stageDir=$(mktemp -d "${bundlesRoot}/.stage.XXXXXX") || return 1
    candidate="${stageDir}/bundle"
    # 创建候选目录前登记，复制或校验中断时统一清理本次 stage。
    DOCKER_STAGED_BUNDLE_DIR=${stageDir}
    DOCKER_STAGED_BUNDLE_PATH=${candidate}
    mkdir -- "${candidate}" || {
        dockerRemoveManagedTree "${root}" "${stageDir}" || true
        return 1
    }
    while IFS= read -r relativePath; do
        dockerBundleRelativePathIsSafe "${relativePath}" || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        mkdir -p -- "${candidate}/$(dirname -- "${relativePath}")" &&
            cp -- "${sourceRoot}/${relativePath}" "${candidate}/${relativePath}" || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
    done <<<"${payloadPaths}"
    printf '%s\n' "${ref}" >"${candidate}/${PADM_DOCKER_BUNDLE_REF}" || {
        dockerRemoveManagedTree "${root}" "${stageDir}" || true
        return 1
    }
    find "${candidate}" -type d -exec chmod 0750 {} + &&
        find "${candidate}" -type f -exec chmod 0640 {} + &&
        chmod 0750 "${candidate}/install-docker.sh" || {
        dockerRemoveManagedTree "${root}" "${stageDir}" || true
        return 1
    }
    dockerWriteBundleManifest "${candidate}" && dockerValidateBundle "${candidate}" || {
        dockerRemoveManagedTree "${root}" "${stageDir}" || true
        return 1
    }
}

dockerCleanupStagedBundle() {
    local root stageDir=${DOCKER_STAGED_BUNDLE_DIR:-}
    [[ -n "${stageDir}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    if [[ -e "${stageDir}" || -L "${stageDir}" ]]; then
        dockerRemoveManagedTree "${root}" "${stageDir}" || return 1
    fi
    DOCKER_STAGED_BUNDLE_DIR=
    DOCKER_STAGED_BUNDLE_PATH=
}

dockerBundleSupportsSpec() {
    local bundlePath=$1 specFile=$2
    [[ -f "${bundlePath}/docker/contracts/configure.schema.json" &&
        ! -L "${bundlePath}/docker/contracts/configure.schema.json" &&
        -f "${bundlePath}/docker/contracts/features.json" &&
        ! -L "${bundlePath}/docker/contracts/features.json" ]] &&
        jq -en --slurpfile schema "${bundlePath}/docker/contracts/configure.schema.json" \
            --slurpfile features "${bundlePath}/docker/contracts/features.json" \
            --slurpfile spec "${specFile}" '
          ($spec | length) == 1 and ($spec[0] | type == "object") and
          ($spec[0].schema_version | type == "number" and floor == . and . >= 1) and
          ($spec[0].schema_version as $version |
            $schema[0].properties.schema_version |
            (.const == $version) or ((.enum // []) | index($version)) != null) and
          (if $spec[0] | has("reality_stream") then
            ($schema[0].properties | has("reality_stream"))
           else true end) and
          (if $spec[0].reality_stream != null then
            $schema[0]["x-padm-reality-stream-deployment"] == true
           else true end) and
          (if $spec[0].reality_stream.host_website != null then
            $schema[0]["x-padm-reality-stream-host-website"] == true
           else true end) and
          (if $spec[0].reality_stream.host_website.network_mode == "host" then
            $schema[0]["x-padm-reality-stream-host-network"] == true
          else true end) and
          (if $spec[0] | has("accounts") then
            $schema[0]["x-padm-accounts"] == true
          else true end) and
          (if $spec[0] | has("control_sync") then
            $schema[0]["x-padm-control-sync"] == true and
              $schema[0]["x-padm-control-sync-rollback"] == true
          else true end) and
          (if ($spec[0].control_sync // {}) | has("connection") then
            $schema[0]["x-padm-control-client"] == true
          else true end) and
          (if $spec[0] | has("control") then
            $schema[0]["x-padm-control-state"] == true
          else true end) and
          (if any($spec[0].host_integrations[]; .type == "fail2ban-control") then
            $schema[0]["x-padm-control-fail2ban"] == true
          else true end) and
          (if $spec[0] | has("site") then
            $schema[0]["x-padm-site-content"] == true
          else true end) and
          (if any($spec[0].core.protocols[]; (.fallback_tls // {}) | has("alpn")) then
            $schema[0]["x-padm-fallback-alpn"] == true
          else true end) and
          (if ($spec[0].tls // {}) | has("http01") then
            $schema[0]["x-padm-acme-webroot"] == true
          else true end) and
          (if $spec[0].routing.socks5 != null then
            $schema[0]["x-padm-routing-socks5"] == true
          else true end) and
          (if $spec[0].relay.http != null then
            $schema[0]["x-padm-relay-http"] == true and $spec[0].relay.http.core == "xray"
          else true end) and
          (if $spec[0] | has("port_aliases") then
            $schema[0]["x-padm-port-aliases"] == true
          else true end) and
          (if any($spec[0].port_aliases[]?; has("share_default")) then
            $schema[0]["x-padm-port-alias-default"] == true
          else true end) and
          (if ($spec[0].routing.socks5 // {}) | has("domains") then
            $schema[0]["x-padm-routing-domains"] == true
          else true end) and
          (if $spec[0].routing.dns != null or $spec[0].routing.hosts != null then
            $schema[0]["x-padm-routing-dns-hosts"] == true
          else true end) and
          (if $spec[0].routing.direct != null or $spec[0].routing.block != null then
            $schema[0]["x-padm-routing-direct-block"] == true
          else true end) and
          (if $spec[0].routing.block_ips != null then
            $schema[0]["x-padm-routing-block-ips"] == true
          else true end) and
          (if ($spec[0].routing // {}) | has("block_bt") then
            $schema[0]["x-padm-routing-block-bt"] == true
          else true end) and
          (if ($spec[0].routing // {}) | has("region") then
            $schema[0]["x-padm-routing-region"] == true
          else true end) and
          (if ($spec[0].routing // {}) | has("ipv6") then
            $schema[0]["x-padm-routing-ipv6"] == true
          else true end) and
          (if ($spec[0].routing // {}) | has("warp") then
            $schema[0]["x-padm-routing-warp"] == true
          else true end) and
          ($features | length) == 1 and ($features[0].protocols | type == "array") and
          all($spec[0].core.protocols[];
            . as $entry |
            (.core // $spec[0].core.type) as $core |
            [$features[0].protocols[] | select(.id == $entry.id)] as $matches |
            ($matches | length) == 1 and $matches[0].status == "supported" and
            ($matches[0].cores | index($core)) != null)
        ' >/dev/null 2>&1 || {
        dockerError '目标控制 bundle 不支持该规格版本、共存拓扑或协议/核心组合，拒绝切换配置或回滚'
        return 1
    }
}

dockerStageReleaseBundle() {
    local root tempDir sourceRoot ref
    root=$(dockerInstallRoot) || return 1
    tempDir=${PADM_DOCKER_MANIFEST_TEMP_DIR:-}
    dockerManagedPathIsSafe "${root}" "${tempDir}" &&
        [[ -d "${tempDir}" && ! -L "${tempDir}" ]] || return 1
    [[ -f "${PADM_DOCKER_CONTROL_BUNDLE:-}" && ! -L "${PADM_DOCKER_CONTROL_BUNDLE}" ]] || return 1
    dockerCleanupStagedBundle || return 1
    # 签名和摘要已校验，解压前仍拒绝越界路径、链接和超大归档。
    dockerEntryArchiveIsSafe "${PADM_DOCKER_CONTROL_BUNDLE}" \
        "${tempDir}/control.entries" "${tempDir}/control.details" || {
        dockerError 'release 控制 bundle 归档不安全或损坏'
        return 1
    }
    sourceRoot=$(mktemp -d "${tempDir}/control.XXXXXX") || return 1
    tar -xzf "${PADM_DOCKER_CONTROL_BUNDLE}" --no-same-owner -C "${sourceRoot}" || return 1
    ref=$(jq -er '.release.commit' "${PADM_DOCKER_MANIFEST_FILE}") || return 1
    dockerStageBundle "${sourceRoot}" "${ref}"
}

dockerActivateStagedBundle() {
    local root stageDir candidate manifest digest releaseDir existingDigest
    root=$(dockerInstallRoot) || return 1
    stageDir=${DOCKER_STAGED_BUNDLE_DIR:-}
    candidate=${DOCKER_STAGED_BUNDLE_PATH:-}
    dockerManagedPathIsSafe "${root}" "${stageDir}" && [[ "${candidate}" == "${stageDir}/bundle" ]] || return 1
    dockerValidateBundle "${candidate}" || return 1
    manifest="${candidate}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    digest=$(sha256sum -- "${manifest}") || return 1
    digest=${digest%% *}
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    releaseDir="${root}/.bundles/${digest}"
    if [[ -e "${releaseDir}" || -L "${releaseDir}" ]]; then
        [[ -d "${releaseDir}" && ! -L "${releaseDir}" ]] && dockerValidateBundle "${releaseDir}" || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        existingDigest=$(sha256sum -- "${releaseDir}/${PADM_DOCKER_BUNDLE_MANIFEST}") || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        existingDigest=${existingDigest%% *}
        [[ "${existingDigest}" == "${digest}" ]] || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        dockerRemoveManagedTree "${root}" "${stageDir}" || return 1
    else
        mv -- "${candidate}" "${releaseDir}" || return 1
        rmdir -- "${stageDir}" || return 1
    fi
    if [[ "${DOCKER_INSTALL_TRANSACTION_ACTIVE:-0}" == 1 ]]; then
        DOCKER_INSTALL_BUNDLE_TARGET=".bundles/${digest}"
    fi
    dockerActivateBundle ".bundles/${digest}"
}

dockerBundlePathForTarget() {
    local target=$1 root digest manifestDigest
    root=$(dockerInstallRoot) || return 1
    [[ "${target}" =~ ^[.]bundles/([0-9a-f]{64})$ ]] || return 1
    digest=${BASH_REMATCH[1]}
    [[ -d "${root}/.bundles" && ! -L "${root}/.bundles" &&
        -d "${root}/${target}" && ! -L "${root}/${target}" ]] || return 1
    manifestDigest=$(sha256sum -- "${root}/${target}/${PADM_DOCKER_BUNDLE_MANIFEST}") || return 1
    manifestDigest=${manifestDigest%% *}
    [[ "${manifestDigest}" == "${digest}" ]] || return 1
    dockerValidateBundle "${root}/${target}" || return 1
    printf '%s\n' "${root}/${target}"
}

dockerActivateBundle() {
    local linkTarget=$1 root tempLink currentTarget
    root=$(dockerInstallRoot) || return 1
    dockerBundlePathForTarget "${linkTarget}" >/dev/null || return 1
    if [[ -e "${root}/bundle" || -L "${root}/bundle" ]]; then
        [[ -L "${root}/bundle" ]] || {
            dockerError "Docker bundle 目标不是受管符号链接: ${root}/bundle"
            return 1
        }
        currentTarget=$(readlink "${root}/bundle" 2>/dev/null || true)
        [[ "${currentTarget}" == "${linkTarget}" ]] && return 0
    fi
    tempLink="${root}/.bundle-link.${BASHPID:-$$}"
    [[ ! -e "${tempLink}" && ! -L "${tempLink}" ]] || {
        dockerError "bundle 临时链接路径已存在，已保留: ${tempLink}"
        return 1
    }
    DOCKER_BUNDLE_LINK_TEMP_PATH=${tempLink}
    DOCKER_BUNDLE_LINK_TEMP_TARGET=${linkTarget}
    ln -s "${linkTarget}" "${tempLink}" || {
        dockerCleanupBundleLinkTemp || true
        return 1
    }
    mv -Tf -- "${tempLink}" "${root}/bundle" || {
        dockerCleanupBundleLinkTemp || true
        return 1
    }
    DOCKER_BUNDLE_LINK_TEMP_PATH=
    DOCKER_BUNDLE_LINK_TEMP_TARGET=
}

dockerCleanupBundleLinkTemp() {
    local root temp=${DOCKER_BUNDLE_LINK_TEMP_PATH:-} expectedTarget=${DOCKER_BUNDLE_LINK_TEMP_TARGET:-}
    [[ -n "${temp}" ]] || return 0
    root=$(dockerInstallRoot) || return 1
    dockerManagedPathIsSafe "${root}" "${temp}" &&
        [[ "${temp}" == "${root}/.bundle-link.${BASHPID:-$$}" &&
            "${expectedTarget}" =~ ^[.]bundles/[0-9a-f]{64}$ ]] || return 1
    if [[ -L "${temp}" ]]; then
        [[ -O "${temp}" && "$(readlink "${temp}" 2>/dev/null || true)" == "${expectedTarget}" ]] || return 1
        rm -f -- "${temp}" || return 1
    elif [[ -e "${temp}" ]]; then
        return 1
    fi
    DOCKER_BUNDLE_LINK_TEMP_PATH=
    DOCKER_BUNDLE_LINK_TEMP_TARGET=
}

dockerInstallBundle() {
    local sourceRoot=$1 requestedRef=${2:-} root
    DOCKER_STAGED_BUNDLE_DIR=
    DOCKER_STAGED_BUNDLE_PATH=
    dockerStageBundle "${sourceRoot}" "${requestedRef}" || return 1
    root=$(dockerInstallRoot) || return 1
    if [[ -e "${root}/config/spec.json" || -L "${root}/config/spec.json" ]]; then
        [[ -f "${root}/config/spec.json" && ! -L "${root}/config/spec.json" ]] &&
            dockerBundleSupportsSpec "${DOCKER_STAGED_BUNDLE_PATH}" "${root}/config/spec.json" || return 1
    fi
    dockerRenewalBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return 1
    dockerGeoBundleCheck "${DOCKER_STAGED_BUNDLE_PATH}" || return 1
    dockerActivateStagedBundle
}

dockerCurrentBundlePath() {
    local root target
    root=$(dockerInstallRoot) || return 1
    [[ -L "${root}/bundle" ]] || return 1
    target=$(readlink "${root}/bundle" 2>/dev/null) || return 1
    dockerBundlePathForTarget "${target}"
}
