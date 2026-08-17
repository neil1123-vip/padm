#!/usr/bin/env bash

if [[ "${PADM_DOCKER_BUNDLE_LOADED:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi
PADM_DOCKER_BUNDLE_LOADED=1

readonly PADM_DOCKER_BUNDLE_MANIFEST=.padm-docker-bundle-manifest
readonly PADM_DOCKER_BUNDLE_REF=.padm-docker-bundle-ref

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
    local sourceRoot=$1 path
    [[ -f "${sourceRoot}/install-docker.sh" && ! -L "${sourceRoot}/install-docker.sh" ]] || return 1
    [[ -d "${sourceRoot}/docker" && ! -L "${sourceRoot}/docker" ]] || return 1
    [[ -z "$(find "${sourceRoot}/docker" -type l -print -quit 2>/dev/null)" ]] || return 1
    [[ -f "${sourceRoot}/shell/core/deployment_mode.sh" &&
        ! -L "${sourceRoot}/shell/core/deployment_mode.sh" ]] || return 1
    printf 'install-docker.sh\n'
    while IFS= read -r path; do
        path=${path#"${sourceRoot}/"}
        dockerBundleRelativePathIsSafe "${path}" || return 1
        printf '%s\n' "${path}"
    done < <(find "${sourceRoot}/docker" -type f -print | LC_ALL=C sort)
    printf 'shell/core/deployment_mode.sh\n'
    if [[ -d "${sourceRoot}/documents" && ! -L "${sourceRoot}/documents" ]]; then
        while IFS= read -r path; do
            path=${path#"${sourceRoot}/"}
            dockerBundleRelativePathIsSafe "${path}" || return 1
            printf '%s\n' "${path}"
        done < <(find "${sourceRoot}/documents" -maxdepth 1 -type f -name 'docker*.md' -print | LC_ALL=C sort)
    fi
}

dockerBundleSourceIsComplete() {
    local sourceRoot=$1 required
    [[ -d "${sourceRoot}" && ! -L "${sourceRoot}" ]] || return 1
    for required in \
        install-docker.sh \
        docker/lib/bootstrap.sh \
        docker/lib/bundle.sh \
        docker/lib/lifecycle.sh \
        docker/contracts/deployment.schema.json \
        shell/core/deployment_mode.sh; do
        [[ -f "${sourceRoot}/${required}" && ! -L "${sourceRoot}/${required}" ]] || return 1
    done
    dockerBundlePayloadPaths "${sourceRoot}" >/dev/null
}

dockerBundleRefIsValid() {
    [[ "$1" =~ ^[0-9a-f]{40}$ || "$1" =~ ^sha256:[0-9a-f]{64}$ ]]
}

dockerBundleSourceDigest() {
    local sourceRoot=$1 pathList relativePath digest
    pathList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-source.XXXXXX") || return 1
    : >"${pathList}"
    while IFS= read -r relativePath; do
        sha256sum "${sourceRoot}/${relativePath}" |
            awk -v path="${relativePath}" '{ print $1 "  " path }' >>"${pathList}" || {
            rm -f -- "${pathList}"
            return 1
        }
    done < <(dockerBundlePayloadPaths "${sourceRoot}")
    digest=$(sha256sum "${pathList}" | cut -d ' ' -f 1) || {
        rm -f -- "${pathList}"
        return 1
    }
    rm -f -- "${pathList}"
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
    local bundleRoot=$1 manifest tempList relativePath
    manifest="${bundleRoot}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    tempList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-paths.XXXXXX") || return 1
    if ! { dockerBundlePayloadPaths "${bundleRoot}"; printf '%s\n' "${PADM_DOCKER_BUNDLE_REF}"; } |
        LC_ALL=C sort -u >"${tempList}"; then
        rm -f -- "${tempList}"
        return 1
    fi
    : >"${manifest}" || {
        rm -f -- "${tempList}"
        return 1
    }
    while IFS= read -r relativePath; do
        [[ -f "${bundleRoot}/${relativePath}" && ! -L "${bundleRoot}/${relativePath}" ]] || {
            rm -f -- "${tempList}" "${manifest}"
            return 1
        }
        sha256sum "${bundleRoot}/${relativePath}" |
            awk -v path="${relativePath}" '{ print $1 "  " path }' >>"${manifest}" || {
            rm -f -- "${tempList}" "${manifest}"
            return 1
        }
    done <"${tempList}"
    rm -f -- "${tempList}"
    chmod 0640 "${manifest}"
}

dockerValidateBundle() {
    local bundleRoot=$1 manifest expectedList manifestList line expectedHash relativePath actualHash status directory
    manifest="${bundleRoot}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    [[ -d "${bundleRoot}" && ! -L "${bundleRoot}" && -O "${bundleRoot}" &&
        -f "${manifest}" && ! -L "${manifest}" && -O "${manifest}" ]] || return 1
    while IFS= read -r directory; do
        [[ -O "${directory}" ]] || return 1
    done < <(find "${bundleRoot}" -type d -print)
    expectedList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-expected.XXXXXX") || return 1
    manifestList=$(mktemp "${TMPDIR:-/tmp}/padm-docker-manifest.XXXXXX") || {
        rm -f -- "${expectedList}"
        return 1
    }
    if ! { dockerBundlePayloadPaths "${bundleRoot}"; printf '%s\n' "${PADM_DOCKER_BUNDLE_REF}"; } |
        LC_ALL=C sort -u >"${expectedList}"; then
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
        actualHash=$(sha256sum "${bundleRoot}/${relativePath}" | cut -d ' ' -f 1) || {
            rm -f -- "${expectedList}" "${manifestList}"
            return 1
        }
        [[ "${actualHash}" == "${expectedHash}" ]] || {
            rm -f -- "${expectedList}" "${manifestList}"
            return 1
        }
        printf '%s\n' "${relativePath}" >>"${manifestList}"
    done <"${manifest}"
    LC_ALL=C sort "${manifestList}" -o "${manifestList}"
    [[ -z "$(uniq -d "${manifestList}")" ]] && cmp -s "${expectedList}" "${manifestList}"
    status=$?
    rm -f -- "${expectedList}" "${manifestList}"
    return "${status}"
}

dockerStageBundle() {
    local sourceRoot=$1 requestedRef=${2:-} root bundlesRoot stageDir candidate relativePath ref
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
    stageDir=$(mktemp -d "${bundlesRoot}/.stage.XXXXXX") || return 1
    candidate="${stageDir}/bundle"
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
    done < <(dockerBundlePayloadPaths "${sourceRoot}")
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
    DOCKER_STAGED_BUNDLE_DIR=${stageDir}
    DOCKER_STAGED_BUNDLE_PATH=${candidate}
}

dockerActivateStagedBundle() {
    local root stageDir candidate manifest digest releaseDir existingDigest linkTarget tempLink currentTarget
    root=$(dockerInstallRoot) || return 1
    stageDir=${DOCKER_STAGED_BUNDLE_DIR:-}
    candidate=${DOCKER_STAGED_BUNDLE_PATH:-}
    dockerManagedPathIsSafe "${root}" "${stageDir}" && [[ "${candidate}" == "${stageDir}/bundle" ]] || return 1
    dockerValidateBundle "${candidate}" || return 1
    manifest="${candidate}/${PADM_DOCKER_BUNDLE_MANIFEST}"
    digest=$(sha256sum "${manifest}" | cut -d ' ' -f 1) || return 1
    [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    releaseDir="${root}/.bundles/${digest}"
    if [[ -e "${releaseDir}" || -L "${releaseDir}" ]]; then
        [[ -d "${releaseDir}" && ! -L "${releaseDir}" ]] && dockerValidateBundle "${releaseDir}" || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        existingDigest=$(sha256sum "${releaseDir}/${PADM_DOCKER_BUNDLE_MANIFEST}" | cut -d ' ' -f 1) || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        [[ "${existingDigest}" == "${digest}" ]] || {
            dockerRemoveManagedTree "${root}" "${stageDir}" || true
            return 1
        }
        dockerRemoveManagedTree "${root}" "${stageDir}" || return 1
    else
        mv -- "${candidate}" "${releaseDir}" || return 1
        rmdir -- "${stageDir}" || return 1
    fi
    linkTarget=".bundles/${digest}"
    if [[ -e "${root}/bundle" || -L "${root}/bundle" ]]; then
        [[ -L "${root}/bundle" ]] || {
            dockerError "Docker bundle 目标不是受管符号链接: ${root}/bundle"
            return 1
        }
        currentTarget=$(readlink "${root}/bundle" 2>/dev/null || true)
        [[ "${currentTarget}" == "${linkTarget}" ]] && return 0
    fi
    tempLink="${root}/.bundle-link.${BASHPID:-$$}"
    rm -f -- "${tempLink}" 2>/dev/null || true
    ln -s "${linkTarget}" "${tempLink}" || return 1
    mv -Tf -- "${tempLink}" "${root}/bundle" || {
        rm -f -- "${tempLink}" 2>/dev/null || true
        return 1
    }
}

dockerInstallBundle() {
    local sourceRoot=$1 requestedRef=${2:-}
    DOCKER_STAGED_BUNDLE_DIR=
    DOCKER_STAGED_BUNDLE_PATH=
    dockerStageBundle "${sourceRoot}" "${requestedRef}" && dockerActivateStagedBundle
}

dockerCurrentBundlePath() {
    local root target digest
    root=$(dockerInstallRoot) || return 1
    [[ -L "${root}/bundle" ]] || return 1
    target=$(readlink "${root}/bundle" 2>/dev/null) || return 1
    [[ "${target}" =~ ^[.]bundles/([0-9a-f]{64})$ ]] || return 1
    digest=${BASH_REMATCH[1]}
    [[ -d "${root}/${target}" && ! -L "${root}/${target}" ]] || return 1
    [[ "$(sha256sum "${root}/${target}/${PADM_DOCKER_BUNDLE_MANIFEST}" | cut -d ' ' -f 1)" == "${digest}" ]] || return 1
    dockerValidateBundle "${root}/${target}" || return 1
    printf '%s\n' "${root}/${target}"
}
