#!/usr/bin/env bash

SCRIPT_VERSION_BASE="1.0.0"
SCRIPT_VERSION_MAJOR_BASE_COMMIT="4e05a11"
SCRIPT_VERSION_REMOTE_REPO="neil1123-vip/padm"
SCRIPT_VERSION_REMOTE_BRANCH="master"

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

getScriptVersionCommitsFromGit() {
    local baseCommit=$1

    if command -v git >/dev/null 2>&1 && git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        if git -C "${PROJECT_ROOT}" cat-file -e "${baseCommit}^{commit}" >/dev/null 2>&1; then
            git -C "${PROJECT_ROOT}" log --format=%B "${baseCommit}..HEAD" 2>/dev/null
        fi
    fi
}

getScriptVersionCommitsFromRemote() {
    local baseCommit=$1
    local compareUrl="https://api.github.com/repos/${SCRIPT_VERSION_REMOTE_REPO}/compare/${baseCommit}...${SCRIPT_VERSION_REMOTE_BRANCH}"

    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 10 "${compareUrl}" 2>/dev/null | jq -r '.commits[].commit.message' 2>/dev/null
    fi
}

getScriptVersion() {
    local version=${SCRIPT_VERSION_BASE}
    local baseCommit=${SCRIPT_VERSION_MAJOR_BASE_COMMIT}
    local commits=

    commits=$(getScriptVersionCommitsFromGit "${baseCommit}")
    if [[ -z "${commits}" ]]; then
        commits=$(getScriptVersionCommitsFromRemote "${baseCommit}")
    fi
    if [[ -n "${commits}" ]]; then
        version=$(nextScriptVersionFromCommits "${version}" "${commits}")
    fi

    echo "v${version}"
}
