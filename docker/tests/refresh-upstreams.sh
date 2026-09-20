#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
workflow=${project_root}/.github/workflows/refresh-upstreams.yml
test_root=$(mktemp -d "${project_root}/.tmp-refresh-upstreams.XXXXXX")
trap 'rm -rf -- "${test_root}"' EXIT

# Windows 回归使用原生 Git，避免 MSYS2 的 Git/签名环境差异。
if [[ -x '/c/Program Files/Git/cmd/git.exe' ]]; then
    git() {
        case "$1" in
        clone|fetch|push) '/c/Program Files/Git/cmd/git.exe' -c http.sslbackend=openssl "$@" ;;
        *) '/c/Program Files/Git/cmd/git.exe' "$@" ;;
        esac
    }
    export -f git
fi
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GITHUB_REPOSITORY=example/padm GITHUB_RUN_ID=123 GITHUB_RUN_ATTEMPT=1

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
extract_step 'Save update PR' >"${test_root}/save.sh"
extract_step 'Ensure Docker CI' | sed '/^find_ci_run()/,$d' >"${test_root}/check-head.sh"
[[ -s "${test_root}/prepare.sh" && -s "${test_root}/save.sh" ]] || fail 'workflow steps are missing'
# 无锁变化的已有 PR 也必须进入保存和同 head CI 校验。
grep -Fq "if: steps.update.outputs.changed == 'true' || steps.pending.outputs.pr_url != ''" "${workflow}" || fail 'existing PR continuation is gated by lock changes'
grep -Fq "if: steps.save.outputs.pr_url != ''" "${workflow}" || fail 'existing PR CI is not ensured'

gh() {
    printf '%s\n' "$*" >>"${case_root}/gh-calls"
    case "$1 $2" in
    'api --paginate') cat "${case_root}/pulls.json" ;;
    'pr create') printf 'https://example.invalid/pull/2\n' ;;
    'pr view') cat "${case_root}/head.json" ;;
    *) return 99 ;;
    esac
}
export -f gh

for scenario in updated unchanged new fork mixed ambiguous conflict fetch-race push-race; do
    case_root=${test_root}/${scenario}
    export case_root
    mkdir -p "${case_root}"
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
        if [[ "${scenario}" != new ]]; then
            git switch --create codex/upstream-versions-existing >/dev/null
            printf 'manual fix\n' >manual.txt
            printf 'MANUAL_LOCK_FIX=kept\n' >>versions.lock
            [[ "${scenario}" != conflict ]] || printf 'PR edit\n' >shared.txt
            git add .
            git commit -m 'manual repair' >/dev/null
            git push origin HEAD >/dev/null
            git switch main >/dev/null
        fi
        if [[ "${scenario}" != unchanged ]]; then
            printf 'main fix\n' >main.txt
            [[ "${scenario}" != conflict ]] || printf 'main edit\n' >shared.txt
            git add .
            git commit -m 'main repair' >/dev/null
            git push origin main >/dev/null
        fi
        git rev-parse HEAD >../main-sha
    ) >"${case_root}/setup.log" 2>&1 || { cat "${case_root}/setup.log"; fail "${scenario}: fixture"; }
    original_sha=$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing 2>/dev/null || true)
    head_repo=${GITHUB_REPOSITORY}
    [[ "${scenario}" != fork ]] || head_repo=untrusted/fork
    api_sha=${original_sha}
    [[ "${scenario}" != fetch-race ]] || api_sha=$(cat "${case_root}/main-sha")
    jq -n --arg repo "${head_repo}" --arg sha "${api_sha}" --arg scenario "${scenario}" '
      {head: {ref: "codex/upstream-versions-existing", repo: {full_name: $repo}, sha: $sha},
       html_url: "https://example.invalid/pull/1"} |
      if $scenario == "new" then [[]]
      elif $scenario == "ambiguous" then [[., .]]
      elif $scenario == "mixed" then [[., (.head.repo.full_name = "untrusted/fork")]]
      else [[.]] end
    ' >"${case_root}/pulls.json"
    git clone --branch main "${case_root}/remote.git" "${case_root}/runner" >"${case_root}/clone.log" 2>&1
    export RUNNER_TEMP=${case_root} GITHUB_OUTPUT=${case_root}/outputs GITHUB_STEP_SUMMARY=${case_root}/summary
    result=success
    (cd "${case_root}/runner"; bash "${test_root}/prepare.sh") >"${case_root}/prepare.log" 2>&1 || result=failure
    case "${scenario}" in
    ambiguous|conflict|fetch-race)
        [[ "${result}" == failure ]] || fail "${scenario}: unsafe continuation"
        [[ "$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing)" == "${original_sha}" ]] || fail "${scenario}: remote changed"
        continue ;;
    esac
    [[ "${result}" == success ]] || { cat "${case_root}/prepare.log"; fail "${scenario}: prepare"; }
    export BRANCH PR_URL ORIGINAL_SHA
    BRANCH=$(sed -n 's/^branch=//p' "${GITHUB_OUTPUT}")
    PR_URL=$(sed -n 's/^pr_url=//p' "${GITHUB_OUTPUT}")
    ORIGINAL_SHA=$(sed -n 's/^original_sha=//p' "${GITHUB_OUTPUT}")
    if [[ "${scenario}" != unchanged ]]; then
        sed -i 's/PADM_LOCK_XRAY_VERSION=v1.0.0/PADM_LOCK_XRAY_VERSION=v1.1.0/' "${case_root}/runner/versions.lock"
    fi
    if [[ "${scenario}" == push-race ]]; then
        (
            cd "${case_root}/seed"
            git switch codex/upstream-versions-existing
            printf 'concurrent fix\n' >concurrent.txt
            git add concurrent.txt
            git commit -m concurrent
            git push origin HEAD
        ) >"${case_root}/race.log" 2>&1
        original_sha=$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing)
    fi
    : >"${GITHUB_OUTPUT}"
    result=success
    (cd "${case_root}/runner"; bash "${test_root}/save.sh") >"${case_root}/save.log" 2>&1 || result=failure
    if [[ "${scenario}" == push-race ]]; then
        [[ "${result}" == failure ]] || fail 'concurrent human commit was overwritten'
        [[ "$(git --git-dir="${case_root}/remote.git" rev-parse refs/heads/codex/upstream-versions-existing)" == "${original_sha}" ]] || fail 'concurrent remote changed'
        continue
    fi
    [[ "${result}" == success ]] || { cat "${case_root}/save.log"; fail "${scenario}: save"; }
    remote_sha=$(git --git-dir="${case_root}/remote.git" rev-parse "refs/heads/${BRANCH}")
    [[ "${remote_sha}" == "$(sed -n 's/^commit_sha=//p' "${GITHUB_OUTPUT}")" ]] || fail "${scenario}: wrong CI head"
    if [[ "${scenario}" != new && "${scenario}" != fork ]]; then
        git --git-dir="${case_root}/remote.git" merge-base --is-ancestor "${ORIGINAL_SHA}" "${remote_sha}" || fail 'manual commit lost'
        git --git-dir="${case_root}/remote.git" show "${remote_sha}:manual.txt" | grep -Fxq 'manual fix' || fail 'manual file lost'
        git --git-dir="${case_root}/remote.git" show "${remote_sha}:versions.lock" | grep -Fxq 'MANUAL_LOCK_FIX=kept' || fail 'manual lock fix lost'
        ! grep -q '^pr create ' "${case_root}/gh-calls" || fail 'created duplicate PR'
    else
        grep -q '^pr create ' "${case_root}/gh-calls" || fail 'new PR not created'
        [[ "${BRANCH}" == codex/upstream-versions-123-1 && ! -f "${case_root}/runner/manual.txt" ]] || fail 'fork branch was followed'
    fi
    git --git-dir="${case_root}/remote.git" merge-base --is-ancestor "$(cat "${case_root}/main-sha")" "${remote_sha}" || fail 'main repair not merged'
    [[ "${scenario}" != unchanged || "${remote_sha}" == "${ORIGINAL_SHA}" ]] || fail 'unchanged head was recommitted'
done

export COMMIT_SHA=0123456789012345678901234567890123456789
for head_case in matching moved fork closed; do
    jq -n --arg branch "${BRANCH}" --arg sha "${COMMIT_SHA}" --arg scenario "${head_case}" '
      {state: "OPEN", isCrossRepository: false, headRefName: $branch, headRefOid: $sha} |
      if $scenario == "moved" then .headRefOid = "changed"
      elif $scenario == "fork" then .isCrossRepository = true
      elif $scenario == "closed" then .state = "CLOSED" else . end
    ' >"${case_root}/head.json"
    result=success
    bash "${test_root}/check-head.sh" >"${case_root}/head-check.log" 2>&1 || result=failure
    expected=failure
    [[ "${head_case}" != matching ]] || expected=success
    [[ "${result}" == "${expected}" ]] || fail "CI accepted wrong PR head: ${head_case}"
done

printf 'refresh-upstreams-regression-ok\n'
