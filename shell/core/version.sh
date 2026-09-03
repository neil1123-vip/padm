#!/usr/bin/env bash

SCRIPT_VERSION="3.6.14"

commitRequiresMajorBump() {
    local commitMessage=$1
    echo "${commitMessage}" | grep -qE '^[a-zA-Z]+(\([^)]*\))?!:|BREAKING CHANGE:'
}

commitRequiresMinorBump() {
    local commitMessage=$1
    echo "${commitMessage}" | grep -qE '^feat(\([^)]*\))?:'
}

commitRequiresPatchBump() {
    local commitMessage=$1
    echo "${commitMessage}" | grep -qE '^(fix|perf|refactor|docs|test|build|ci|chore)(\([^)]*\))?:'
}

nextScriptVersionFromCommits() {
    local baseVersion=$1
    local commits=$2
    local major minor patch
    local bump=none

    baseVersion=${baseVersion#v}
    major=${baseVersion%%.*}
    minor=${baseVersion#*.}
    minor=${minor%%.*}
    patch=${baseVersion##*.}

    while IFS= read -r commitMessage; do
        if commitRequiresMajorBump "${commitMessage}"; then
            bump=major
            break
        elif [[ "${bump}" != "minor" ]] && commitRequiresMinorBump "${commitMessage}"; then
            bump=minor
        elif [[ "${bump}" == "none" ]] && commitRequiresPatchBump "${commitMessage}"; then
            bump=patch
        fi
    done <<<"${commits}"

    case "${bump}" in
    major)
        major=$((major + 1))
        minor=0
        patch=0
        ;;
    minor)
        minor=$((minor + 1))
        patch=0
        ;;
    patch)
        patch=$((patch + 1))
        ;;
    esac

    echo "${major}.${minor}.${patch}"
}

getScriptVersion() {
    echo "v${SCRIPT_VERSION}"
}

versionCreateTempPath() {
    local resultVar=$1
    local template=${2:-padm-version.XXXXXX}
    local path

    if declare -F padmCreateTempPath >/dev/null 2>&1; then
        padmCreateTempPath "${resultVar}" "${TMPDIR:-/tmp}/${template}"
        return $?
    fi

    path=$(mktemp "${TMPDIR:-/tmp}/${template}") || return 1
    printf -v "${resultVar}" '%s' "${path}"
}

setScriptVersion() {
    local version=${1#v}
    local versionFile=${2:-${BASH_SOURCE[0]}}
    local tmpFile
    if [[ -z "${version}" || ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version: ${version}" >&2
        return 1
    fi
    versionCreateTempPath tmpFile || return 1
    awk -v version="${version}" '
        BEGIN { replaced = 0 }
        /^SCRIPT_VERSION=/ {
            print "SCRIPT_VERSION=\"" version "\""
            replaced = 1
            next
        }
        { print }
        END {
            if (!replaced) exit 1
        }
    ' "${versionFile}" >"${tmpFile}" || {
        if declare -F padmRemoveCleanupPath >/dev/null 2>&1; then
            padmRemoveCleanupPath "${tmpFile}"
        else
            rm -f "${tmpFile}"
        fi
        echo "SCRIPT_VERSION not found" >&2
        return 1
    }
    mv "${tmpFile}" "${versionFile}"
    if declare -F padmForgetCleanupPath >/dev/null 2>&1; then
        padmForgetCleanupPath "${tmpFile}"
    fi
}
