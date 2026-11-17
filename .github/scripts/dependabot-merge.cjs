const allowedActions = new Set([
  'actions/cache', 'actions/checkout', 'actions/download-artifact',
  'actions/github-script', 'actions/setup-go', 'actions/upload-artifact',
  'docker/bake-action', 'docker/login-action', 'docker/setup-buildx-action',
  'sigstore/cosign-installer',
]);
const workflow = '.github/workflows/docker-ci.yml';
const requiredJobs = [
  'Native static checks', 'Native shell and workflow checks',
  'TLS transactions and renewal', 'Cosign install and signature checks',
];

function actionVersionUpdate(before, after) {
  const pattern = /^([ \t]*(?:-[ \t]*)?uses:[ \t]+)([\w./-]+)@(v\d+(?:\.\d+){0,2})([ \t]*(?:#[^\r\n]*)?)$/gm;
  const oldUses = [...before.matchAll(pattern)];
  const newUses = [...after.matchAll(pattern)];
  if (oldUses.length !== newUses.length) return false;
  let changes = 0;
  for (let i = 0; i < oldUses.length; i++) {
    const oldUse = oldUses[i], newUse = newUses[i];
    if (oldUse[0] === newUse[0]) continue;
    if (oldUse[1] !== newUse[1] || oldUse[2] !== newUse[2] ||
        oldUse[4] !== newUse[4] || !allowedActions.has(oldUse[2])) return false;
    const oldVersion = oldUse[3].slice(1).split('.').map(Number);
    const newVersion = newUse[3].slice(1).split('.').map(Number);
    while (oldVersion.length < 3) oldVersion.push(0);
    while (newVersion.length < 3) newVersion.push(0);
    const different = oldVersion.findIndex((part, index) => part !== newVersion[index]);
    if (different < 0 || newVersion[different] < oldVersion[different]) return false;
    changes++;
  }
  const normalize = text => text.replace(pattern, '$1$2@VERSION$4');
  return changes > 0 && normalize(before) === normalize(after);
}

module.exports = async ({
  github, context, core, workflowTokenConfigured = false,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
}) => {
  if (!workflowTokenConfigured) {
    throw new Error('Configure the DEPENDABOT_AUTOMATION_TOKEN repository secret with Actions, Contents, Pull requests and Workflows write permissions. GITHUB_TOKEN cannot synchronize workflow updates.');
  }
  const repo = context.repo;
  const { data: repository } = await github.rest.repos.get(repo);
  const branch = repository.default_branch;
  if (branch !== 'main') throw new Error('Dependabot automation requires the main default branch.');
  const main = async () => (await github.rest.repos.getBranch({ ...repo, branch })).data;
  const candidates = await github.paginate(github.rest.pulls.list, {
    ...repo, state: 'open', base: branch, per_page: 100,
  });
  const content = async (path, ref) => {
    const { data } = await github.rest.repos.getContent({ ...repo, path, ref });
    if (data.type !== 'file' || data.encoding !== 'base64') throw new Error(`Not a regular workflow: ${path}`);
    return Buffer.from(data.content, 'base64').toString('utf8');
  };
  const compare = async (base, head) =>
    (await github.rest.repos.compareCommits({ ...repo, base, head })).data;
  const runs = async head => github.paginate(github.rest.actions.listWorkflowRuns, {
    ...repo, workflow_id: 'docker-ci.yml', head_sha: head, per_page: 100,
  });
  const dispatchCi = async ref => {
    await github.rest.actions.createWorkflowDispatch({ ...repo, workflow_id: 'docker-ci.yml', ref });
    core.info(`Docker CI dispatched for ${ref}.`);
  };
  const ensureRelease = async (sha, waitForPush = false) => {
    const attempts = waitForPush ? 4 : 1;
    for (let attempt = 0; attempt < attempts; attempt++) {
      const releases = await github.paginate(github.rest.actions.listWorkflowRuns, {
        ...repo, workflow_id: 'create_release.yml', head_sha: sha, per_page: 100,
      });
      if (releases.some(run => run.head_sha === sha)) return;
      if (attempt + 1 < attempts) await sleep(2000);
    }
    await github.rest.actions.createWorkflowDispatch({
      ...repo, workflow_id: 'create_release.yml', ref: branch, inputs: { force_release: 'false' },
    });
    core.info('Release dispatched with force_release=false.');
  };
  let promoted = false;
  for (const candidate of candidates) {
    if (candidate.user.login !== 'dependabot[bot]') continue;
    let { data: pr } = await github.rest.pulls.get({ ...repo, pull_number: candidate.number });
    if (pr.state !== 'open' || pr.draft || pr.user.login !== 'dependabot[bot]' ||
        pr.base.ref !== branch || pr.head.repo?.full_name !== repository.full_name ||
        !pr.head.ref.startsWith('dependabot/github_actions/') ||
        pr.changed_files < 1 || pr.changed_files > 50) continue;
    const current = await main();
    // 当前仓库沿用受测提交快进；新增保护规则后交回平台合并门禁。
    if (current.protected) throw new Error('main is protected; configure the required PR merge policy before enabling promotion.');
    const diff = await compare(current.commit.sha, pr.head.sha);
    const files = await github.paginate(github.rest.pulls.listFiles, {
      ...repo, pull_number: pr.number, per_page: 100,
    });
    if (files.length !== pr.changed_files || files.some(file =>
      file.status !== 'modified' || !/^\.github\/workflows\/[\w-]+\.ya?ml$/.test(file.filename))) continue;
    const base = diff.merge_base_commit.sha;
    const trees = await Promise.all([base, pr.head.sha].map(async tree_sha =>
      (await github.rest.git.getTree({ ...repo, tree_sha, recursive: '1' })).data));
    if (trees.some(tree => tree.truncated)) throw new Error('Cannot verify a truncated Git tree.');
    let eligible = true;
    for (const file of files) {
      if (trees.some(tree => !tree.tree.some(entry =>
        entry.path === file.filename && entry.type === 'blob' && entry.mode === '100644'))) {
        eligible = false;
        break;
      }
      const [before, after] = await Promise.all([
        content(file.filename, base), content(file.filename, pr.head.sha),
      ]);
      if (!actionVersionUpdate(before, after)) {
        eligible = false;
        break;
      }
    }
    if (!eligible) {
      core.info(`PR #${pr.number} needs manual review: changes exceed allowed Action version updates.`);
      continue;
    }
    const reviews = await github.paginate(github.rest.pulls.listReviews, {
      ...repo, pull_number: pr.number, per_page: 100,
    });
    const decisions = new Map();
    for (const review of reviews) {
      if (['APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'].includes(review.state)) {
        decisions.set(review.user.id, review.state);
      }
    }
    if ([...decisions.values()].includes('CHANGES_REQUESTED')) continue;
    if (!['ahead', 'identical'].includes(diff.status)) {
      const previous = pr.head.sha;
      try {
        await github.rest.pulls.updateBranch({
          ...repo, pull_number: pr.number, expected_head_sha: previous,
        });
      } catch (error) {
        if (error.status !== 422) throw error;
        core.warning(`PR #${pr.number} cannot update automatically: ${error.message}`);
        continue;
      }
      // PAT 更新会触发 PR CI；确认同步完成，缺失运行由后续巡检补派。
      for (let attempt = 0; attempt < 6; attempt++) {
        ({ data: pr } = await github.rest.pulls.get({ ...repo, pull_number: pr.number }));
        if (pr.head.sha !== previous &&
            ['ahead', 'identical'].includes((await compare(current.commit.sha, pr.head.sha)).status)) break;
        await sleep(2000);
      }
      if (pr.head.sha === previous ||
          !['ahead', 'identical'].includes((await compare(current.commit.sha, pr.head.sha)).status)) {
        throw new Error(`PR #${pr.number} branch update is not ready; rerun automation after GitHub finishes updating it.`);
      }
      core.info(`PR #${pr.number} updated; waiting for its pull_request CI.`);
      continue;
    }
    const history = (await runs(pr.head.sha)).filter(run =>
      run.head_sha === pr.head.sha && run.head_repository?.full_name === repository.full_name &&
      run.path.split('@')[0] === workflow && ['pull_request', 'workflow_dispatch'].includes(run.event))
      .sort((a, b) => Date.parse(b.updated_at || b.created_at) -
        Date.parse(a.updated_at || a.created_at) || b.id - a.id);
    const latest = history[0];
    if (!latest || latest.conclusion === 'action_required') {
      await dispatchCi(pr.head.ref);
      continue;
    }
    if (latest.status !== 'completed' || latest.conclusion !== 'success') continue;
    const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun, {
      ...repo, run_id: latest.id, filter: 'latest', per_page: 100,
    });
    if (!requiredJobs.every(name => jobs.some(job =>
      job.name === name && job.status === 'completed' && job.conclusion === 'success'))) {
      // 缺少新增签名检查的旧结果不能作为合入依据。
      core.info(`PR #${pr.number} lacks the required current CI jobs; manual inspection is required.`);
      continue;
    }
    const { data: checked } = await github.rest.pulls.get({ ...repo, pull_number: pr.number });
    const finalMain = await main();
    if (checked.state !== 'open' || checked.draft || checked.base.ref !== branch ||
        checked.head.repo?.full_name !== repository.full_name || checked.head.sha !== pr.head.sha ||
        finalMain.commit.sha !== current.commit.sha || finalMain.protected) continue;
    // 非强制快进保证 main 并发前进时拒绝写入，也不产生未经测试的合并提交。
    await github.rest.git.updateRef({ ...repo, ref: `heads/${branch}`, sha: pr.head.sha, force: false });
    core.info(`Promoted PR #${pr.number} at tested commit ${pr.head.sha}.`);
    promoted = true;
    // 先接续已合入提交的发布，避免后续候选异常挡住派发。
    await ensureRelease(pr.head.sha, true);
  }
  // shortcut: 补派只匹配当前 main；需要跨提交恢复时再跟踪发布状态。
  if (promoted) return;
  const current = await main();
  const closed = await github.paginate(github.rest.pulls.list, {
    ...repo, state: 'closed', base: branch, sort: 'updated', direction: 'desc', per_page: 100,
  });
  if (closed.some(pr => pr.user.login === 'dependabot[bot]' &&
    pr.merged_at && pr.merge_commit_sha === current.commit.sha)) {
    await ensureRelease(current.commit.sha);
  }
};
