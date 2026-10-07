#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
workflow=${project_root}/.github/workflows/refresh-upstreams.yml
test_root=$(mktemp -d "${project_root}/.tmp-refresh-upstreams.XXXXXX")
trap 'rm -rf -- "${test_root}"' EXIT

# Windows 回归使用原生 Git；所有场景均拒绝强制推送。
git_binary=$(command -v git)
[[ ! -x '/c/Program Files/Git/cmd/git.exe' ]] || git_binary='/c/Program Files/Git/cmd/git.exe'
git() {
    local argument
    if [[ "${1-}" == push ]]; then
        for argument in "$@"; do
            case "${argument}" in
            --force*|-f|+*) printf 'Unexpected forced push\n' >&2; return 98 ;;
            esac
        done
    fi
    if [[ "${git_binary}" == *.exe ]]; then
        case "${1-}" in
        clone|fetch|push|ls-remote) "${git_binary}" -c http.sslbackend=openssl "$@"; return ;;
        esac
    fi
    "${git_binary}" "$@"
}
export git_binary
export -f git
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GITHUB_REPOSITORY=example/padm GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1
export SING_BOX_RESULT=success

fail() { printf 'refresh-upstreams-test: %s\n' "$*" >&2; exit 1; }
extract_step() {
    awk -v step="$1" '
        $0 == "      - name: " step {found = 1; next}
        found && /^      - name:/ {exit}
        found && /^        run: \|$/ {code = 1; next}
        code {sub(/^          /, ""); print}
    ' "${workflow}"
}
extract_step 'Prepare update branch' >"${test_root}/prepare.sh"
extract_step 'Refresh stable upstream releases' >"${test_root}/update.sh"
extract_step 'Save update branch' >"${test_root}/save.sh"
extract_step 'Ensure Docker CI' >"${test_root}/ci.sh"
extract_step 'Promote validated update' >"${test_root}/promote.sh"
extract_step 'Ensure Release' >"${test_root}/release.sh"
for step in prepare update save ci promote release; do
    [[ -s "${test_root}/${step}.sh" ]] || fail "workflow step is missing: ${step}"
done
# 无更新时不提交候选或等待 CI；已有机器人更新可补发 Release。
for step in 'Validate the refreshed lock' 'Preflight refreshed Alpine dependencies' \
    'Save update branch' 'Ensure Docker CI' 'Promote validated update'; do
    awk -v step="${step}" '
        $0 == "      - name: " step {found = 1; next}
        found && /^      - name:/ {exit}
        found && $0 == "        if: steps.update.outputs.changed == '\''true'\''" {gated = 1}
        END {exit !gated}
    ' "${workflow}" || fail "unchanged update is not gated: ${step}"
done
! grep -Eq 'gh pr |pull-requests:|checks:' "${workflow}" || fail 'refresh workflow still uses PR permissions or commands'
grep -Fq 'bash docker/release.sh validate-lock' "${workflow}" || fail 'refreshed lock validation is missing'
if grep -Fq 'bash docker/tests/phase5.sh' "${workflow}"; then
    fail 'refresh workflow duplicates the Docker contract suite'
fi

argument_value() {
    local flag=$1
    shift
    while [[ "$#" -gt 1 ]]; do
        if [[ "$1" == "${flag}" ]]; then printf '%s\n' "$2"; return; fi
        shift
    done
}
gh() {
    local query runs event
    printf '%s\n' "$*" >>"${case_root}/gh-calls"
    case "$1 $2 ${3-}" in
    'workflow run docker-ci.yml')
        [[ "$(argument_value --ref "$@")" == "${BRANCH}" ]] || return 98
        [[ "${scenario}" != dispatch-failure ]] || return 1 ;;
    'workflow run create_release.yml')
        [[ "$(argument_value --ref "$@")" == main ]] || return 98
        [[ "$(argument_value -F "$@")" == force_release=false ]] || return 98
        if [[ "${scenario}" == release-dispatch-* && ! -f "${case_root}/release-failed" ]]; then
            : >"${case_root}/release-failed"
            return 1
        fi ;;
    'run list '*)
        [[ "$(argument_value --workflow "$@")" == docker-ci.yml ]] || return 98
        [[ "$(argument_value --branch "$@")" == "${BRANCH}" ]] || return 98
        [[ "$(argument_value --commit "$@")" == "${COMMIT_SHA}" ]] || return 98
        event=$(argument_value --event "$@")
        [[ "${event}" == workflow_dispatch ]] || return 98
        query=$(argument_value --jq "$@")
        runs='[{"databaseId":999,"event":"pull_request"}]'
        if [[ "${scenario}" != ci-missing ]]; then
            runs='[{"databaseId":999,"event":"pull_request"},{"databaseId":42,"event":"workflow_dispatch"}]'
        fi
        jq --arg event "${event}" '[.[] | select(.event == $event)]' <<<"${runs}" | jq -r "${query}" ;;
    'run watch '*)
        [[ "$3" == 42 && " $* " == *' --exit-status '* ]] || return 98
        if [[ "${scenario}" == head-after-ci ]]; then
            git --git-dir="${case_root}/remote.git" update-ref "refs/heads/${BRANCH}" "${BASE_SHA}"
        fi
        [[ "${scenario}" != ci-failure ]] || return 1 ;;
    *) printf 'Unexpected gh command: %s\n' "$*" >&2; return 99 ;;
    esac
}
sleep() { :; }
bash() {
    if [[ "${1-} ${2-}" == 'docker/release.sh refresh-upstreams' ]]; then
        [[ "${scenario}" == unchanged || "${REFRESH_UNCHANGED}" == true ]] ||
            sed -i 's/PADM_LOCK_XRAY_VERSION=v1.0.0/PADM_LOCK_XRAY_VERSION=v1.1.0/' versions.lock
    else
        command bash "$@"
    fi
}
export -f argument_value gh sleep bash
run_step() {
    local step=$1
    export GITHUB_OUTPUT=${case_root}/${step}.outputs
    : >"${GITHUB_OUTPUT}"
    (cd "${runner_root}"; bash "${test_root}/${step}.sh") >"${case_root}/${step}.log" 2>&1
}
expect_success() {
    run_step "$1" || { cat "${case_root}/$1.log"; fail "${scenario}: $1"; }
}
expect_failure() {
    if run_step "$1"; then fail "${scenario}: $1 accepted unsafe update"; fi
}
assert_remote() {
    local expected_main=$1
    [[ "$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/main)" == "${expected_main}" ]] || fail "${scenario}: main changed unexpectedly"
    [[ "$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing)" == "${original_sha}" ]] || fail "${scenario}: existing update branch changed"
}

for scenario in success unchanged main-race head-before-ci head-after-ci push-rejected \
    ci-failure ci-missing dispatch-failure unrelated-file release-dispatch-failure release-dispatch-docs; do
    case_root=${test_root}/${scenario}
    runner_root=${case_root}/runner
    export case_root scenario
    export GITHUB_RUN_ATTEMPT=1 REFRESH_UNCHANGED=false
    mkdir -p "${case_root}"
    : >"${case_root}/gh-calls"
    (
        cd "${case_root}"
        git init --bare remote.git >/dev/null
        git init --initial-branch=main seed >/dev/null
        cd seed
        git config user.name 'Regression'
        git config user.email regression@example.invalid
        git config commit.gpgsign false
        printf 'PADM_LOCK_XRAY_VERSION=v1.0.0\nPADM_LOCK_SING_BOX_VERSION=v1.0.0\nPADM_LOCK_ACME_SH_VERSION=1.0.0\n' >versions.lock
        printf 'base\n' >shared.txt
        git add .
        git commit -m base >/dev/null
        git remote add origin ../remote.git
        git push origin main >/dev/null
        git switch --create codex/upstream-versions-existing >/dev/null
        printf 'manual fix\n' >manual.txt
        git add manual.txt
        git commit -m 'manual repair' >/dev/null
        git push origin HEAD >/dev/null
        git switch main >/dev/null
        git rev-parse HEAD >../main-sha
    ) >"${case_root}/setup.log" 2>&1 || { cat "${case_root}/setup.log"; fail "${scenario}: fixture"; }
    original_sha=$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing)
    git clone --branch main "${case_root}/remote.git" "${case_root}/runner" >"${case_root}/clone.log" 2>&1
    export RUNNER_TEMP=${case_root} GITHUB_STEP_SUMMARY=${case_root}/summary
    expect_success prepare
    export BRANCH BASE_SHA COMMIT_SHA LOCK_CHANGED
    BRANCH=$(sed -n 's/^branch=//p' "${GITHUB_OUTPUT}")
    BASE_SHA=$(sed -n 's/^base_sha=//p' "${GITHUB_OUTPUT}")
    [[ "${BRANCH}" == codex/upstream-versions-123-1 && "${BASE_SHA}" == "$(cat "${case_root}/main-sha")" ]] || fail "${scenario}: wrong update base"
    [[ ! -f "${case_root}/runner/manual.txt" ]] || fail "${scenario}: old update branch was followed"
    expect_success update
    LOCK_CHANGED=$(sed -n 's/^changed=//p' "${GITHUB_OUTPUT}")
    if [[ "${scenario}" == unchanged ]]; then
        grep -Fxq 'changed=false' "${GITHUB_OUTPUT}" || fail 'unchanged lock reported an update'
        expect_success release
        [[ ! -s "${case_root}/gh-calls" ]] || fail 'unchanged lock called GitHub'
        ! git --git-dir="${case_root}/remote.git" show-ref --verify --quiet "refs/heads/${BRANCH}" || fail 'unchanged update branch was pushed'
        # 同标题但改动其它文件的人工提交不能触发补发。
        (
            cd "${runner_root}"
            printf 'manual\n' >shared.txt
            git add shared.txt
            git commit -m 'chore(deps): refresh upstream versions'
        ) >"${case_root}/manual-subject.log" 2>&1
        expect_success release
        [[ ! -s "${case_root}/gh-calls" ]] || fail 'non-lock commit dispatched Release'
        assert_remote "${BASE_SHA}"
        continue
    fi
    grep -Fxq 'changed=true' "${GITHUB_OUTPUT}" || fail "${scenario}: lock change not reported"
    expect_success save
    COMMIT_SHA=$(sed -n 's/^commit_sha=//p' "${GITHUB_OUTPUT}")
    [[ "${COMMIT_SHA}" == "$(git --git-dir="${case_root}/remote.git" rev-parse "refs/heads/${BRANCH}")" ]] || fail "${scenario}: wrong candidate head"
    if [[ "${scenario}" == unrelated-file ]]; then
        (
            cd "${case_root}/runner"
            printf 'unexpected\n' >shared.txt
            git add shared.txt
            git commit -m unexpected
            git push origin "${BRANCH}"
        ) >"${case_root}/extra.log" 2>&1
        COMMIT_SHA=$(git -C "${case_root}/runner" rev-parse HEAD)
    elif [[ "${scenario}" == head-before-ci ]]; then
        git --git-dir="${case_root}/remote.git" update-ref "refs/heads/${BRANCH}" "${BASE_SHA}"
    fi

    case "${scenario}" in
    head-before-ci|head-after-ci|ci-failure|ci-missing|dispatch-failure)
        expect_failure ci
        assert_remote "${BASE_SHA}"
        if [[ "${scenario}" == head-before-ci ]]; then
            [[ ! -s "${case_root}/gh-calls" ]] || fail 'moved candidate dispatched CI'
        else
            [[ "$(grep -c '^workflow run docker-ci.yml ' "${case_root}/gh-calls")" == 1 ]] || fail "${scenario}: CI was not dispatched once"
        fi
        ! grep -q '^workflow run create_release.yml ' "${case_root}/gh-calls" || fail "${scenario}: release dispatched after failed CI"
        continue ;;
    esac
    expect_success ci
    [[ "$(grep -c '^workflow run docker-ci.yml ' "${case_root}/gh-calls")" == 1 ]] || fail "${scenario}: CI was not dispatched once"
    expected_main=${BASE_SHA}
    if [[ "${scenario}" == main-race ]]; then
        (
            cd "${case_root}/seed"
            printf 'concurrent\n' >shared.txt
            git add shared.txt
            git commit -m concurrent
            git push origin main
        ) >"${case_root}/race.log" 2>&1
        expected_main=$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/main)
    elif [[ "${scenario}" == push-rejected ]]; then
        printf '%s\n' '#!/usr/bin/env bash' 'while read -r old new ref; do' \
            '    [[ "${ref}" != refs/heads/main ]] || exit 1' 'done' >"${case_root}/remote.git/hooks/pre-receive"
        chmod +x "${case_root}/remote.git/hooks/pre-receive"
    fi
    if [[ "${scenario}" == success || "${scenario}" == release-dispatch-* ]]; then
        expect_success promote
        expected_main=${COMMIT_SHA}
        ! grep -q '^workflow run create_release.yml ' "${case_root}/gh-calls" || fail 'promotion dispatched Release before its dedicated step'
        if [[ "${scenario}" == release-dispatch-* ]]; then
            expect_failure release
            assert_remote "${COMMIT_SHA}"
            if [[ "${scenario}" == release-dispatch-docs ]]; then
                git clone --branch main "${case_root}/remote.git" "${case_root}/docs-writer" >"${case_root}/docs-clone.log" 2>&1
                (
                    cd "${case_root}/docs-writer"
                    git config user.name 'Regression'
                    git config user.email regression@example.invalid
                    git config commit.gpgsign false
                    printf 'documentation update\n' >README.md
                    git add README.md
                    git commit -m 'docs: clarify upstream updates'
                    git push origin main
                ) >"${case_root}/docs-push.log" 2>&1
                expected_main=$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/main)
                git --git-dir="${case_root}/remote.git" merge-base --is-ancestor "${COMMIT_SHA}" "${expected_main}" || fail 'docs update lost the validated lock commit'
            fi
            git clone --branch main "${case_root}/remote.git" "${case_root}/runner-retry" >"${case_root}/retry-clone.log" 2>&1
            runner_root=${case_root}/runner-retry
            export GITHUB_RUN_ATTEMPT=2 REFRESH_UNCHANGED=true
            expect_success prepare
            [[ "$(sed -n 's/^base_sha=//p' "${GITHUB_OUTPUT}")" == "${expected_main}" ]] || fail 'release retry did not start from current main'
            expect_success update
            LOCK_CHANGED=$(sed -n 's/^changed=//p' "${GITHUB_OUTPUT}")
            [[ "${LOCK_CHANGED}" == false ]] || fail 'release retry changed the promoted lock'
            expect_success release
            [[ "$(grep -c '^workflow run create_release.yml ' "${case_root}/gh-calls")" == 2 ]] || fail 'release retry did not recover the failed dispatch'
            [[ "$(grep -c '^workflow run docker-ci.yml ' "${case_root}/gh-calls")" == 1 ]] || fail 'release retry dispatched candidate CI again'
            ! git --git-dir="${case_root}/remote.git" show-ref --verify --quiet refs/heads/codex/upstream-versions-123-2 || fail 'release retry pushed an unchanged candidate'
        else
            expect_success release
            [[ "$(grep -c '^workflow run create_release.yml ' "${case_root}/gh-calls")" == 1 ]] || fail 'validated update did not dispatch one release'
        fi
        git --git-dir="${case_root}/remote.git" show main:versions.lock | grep -Fxq 'PADM_LOCK_XRAY_VERSION=v1.1.0' || fail 'main lock was not refreshed'
    else
        expect_failure promote
        ! grep -q '^workflow run create_release.yml ' "${case_root}/gh-calls" || fail "${scenario}: rejected update dispatched a release"
    fi
    assert_remote "${expected_main}"
done

printf 'refresh-upstreams-regression-ok\n'
