#!/usr/bin/env bash

SCRIPT_VERSION="1.7.5"

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
