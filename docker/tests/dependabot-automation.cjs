#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const automate = require('../../.github/scripts/dependabot-merge.cjs');

const owner = 'example';
const repo = 'padm';
const base = 'a'.repeat(40);
const head = 'b'.repeat(40);
const newer = 'c'.repeat(40);
const merged = 'd'.repeat(40);
const testedTree = 'e'.repeat(40);
const currentTime = Date.parse('2026-11-18T02:00:00Z');
const workflowPath = '.github/workflows/docker-ci.yml';
const source = 'name: Docker CI\njobs:\n  static:\n    steps:\n      - uses: actions/cache@v6.1.0\n';
const updated = source.replace('v6.1.0', 'v6.1.1');
const signingJob = 'Cosign install and signature checks';

function fixture(options = {}) {
    const calls = [];
    const messages = [];
    let now = currentTime;
    const pr = {
        number: 11,
        title: 'chore(deps): bump actions/cache from 6.1.0 to 6.1.1',
        state: 'open',
        draft: false,
        locked: false,
        user: { login: 'dependabot[bot]', type: 'Bot' },
        head: { sha: head, ref: 'dependabot/github_actions/actions/cache-6.1.1', repo: { full_name: `${owner}/${repo}`, fork: false } },
        base: { sha: base, ref: 'main', repo: { full_name: `${owner}/${repo}` } },
        changed_files: 1,
        mergeable: true,
        mergeable_state: 'clean',
        ...options.pr
    };
    const otherPr = {
        ...pr, number: 12,
        head: { ...pr.head, sha: newer, ref: `${pr.head.ref}-next` }
    };
    const run = {
        id: 42,
        path: workflowPath,
        event: 'pull_request',
        head_sha: head,
        head_branch: pr.head.ref,
        head_repository: { full_name: `${owner}/${repo}` },
        status: 'completed',
        conclusion: 'success',
        run_attempt: 1,
        created_at: '2026-11-17T01:00:00Z',
        pull_requests: [{ number: pr.number }],
        ...options.run
    };
    const jobs = [
        'Native static checks',
        'Native shell and workflow checks',
        'TLS transactions and renewal',
        'images / Image input checks',
        signingJob
    ].filter(name => name !== options.missingJob).map((name, index) => ({
        id: index + 1,
        name,
        status: 'completed',
        conclusion: 'success'
    }));
    let branchReads = 0;
    let pullReads = 0;
    let promoted = false;
    let branchUpdated = false;
    let dispatchFailed = false;
    const ciRuns = options.noRun ? [] : options.runs ? options.runs.map(item => ({ ...run, ...item }))
        : options.conflict ? [{ ...run, head_sha: newer, head_branch: otherPr.head.ref }] : [run];
    const releaseRuns = [...options.releaseRuns ?? []];
    const closed = [...options.closed ?? []];
    function method(name, handler) {
        return async params => {
            calls.push({ name, params });
            return { data: await handler(params) };
        };
    }
    const rest = {
        repos: {
            get: method('repos.get', () => ({ full_name: `${owner}/${repo}`, default_branch: 'main' })),
            getBranch: method('repos.getBranch', () => ({
                name: 'main',
                protected: options.protected ?? false,
                commit: { sha: ++branchReads > 1 && options.mainChanged ? newer : promoted || options.mainHead || base }
            })),
            compareCommits: method('repos.compareCommits', params => ({
                status: options.identical ? 'identical' : options.behind && params.head === head ? 'diverged' : 'ahead',
                ahead_by: 1,
                behind_by: options.behind && params.head === head ? 1 : 0,
                merge_base_commit: { sha: base }
            })),
            getContent: method('repos.getContent', params => ({
                type: 'file',
                encoding: 'base64',
                content: Buffer.from(params.ref === base ? options.source ?? source : options.updated ?? updated).toString('base64')
            }))
        },
        git: {
            getCommit: method('git.getCommit', params => {
                assert.equal(params.commit_sha, options.conflict ? newer : head);
                return { sha: params.commit_sha, tree: { sha: testedTree } };
            }),
            createCommit: method('git.createCommit', params => {
                const checked = options.conflict ? otherPr : pr;
                assert.deepEqual(params.parents, [options.mainHead ?? base, checked.head.sha],
                    'main 必须是第一父提交，受测 PR head 必须是第二父提交');
                assert.equal(params.tree, testedTree, '合并提交必须保持受测提交的树');
                assert.equal(params.message, `${checked.title} (#${checked.number})`);
                return { sha: merged, tree: { sha: params.tree } };
            }),
            getTree: method('git.getTree', () => ({
                truncated: false,
                tree: [{ path: workflowPath, type: 'blob', mode: options.mode ?? '100644' }]
            })),
            updateRef: method('git.updateRef', params => {
                assert.equal(params.force, false, '必须使用非强制快进');
                assert.equal(params.ref, 'heads/main');
                assert.equal(params.sha, merged, 'main 应指向保留受测树的新合并提交');
                promoted = params.sha;
                const checked = options.conflict ? otherPr : pr;
                Object.assign(checked, {
                    state: 'closed', merged_at: new Date(now).toISOString(), merge_commit_sha: merged
                });
                closed.push(checked);
                return { ref: 'refs/heads/main', object: { sha: params.sha } };
            })
        },
        pulls: {
            list: method('pulls.list', params => params.state === 'closed' ? closed
                : options.noCandidates ? [] : (options.conflict || options.secondFails ? [pr, otherPr] : [pr])
                    .filter(candidate => candidate.state === 'open')),
            get: method('pulls.get', params => {
                if (params.pull_number === otherPr.number) {
                    if (options.secondFails) throw new Error('second candidate API unavailable');
                    return otherPr;
                }
                pullReads++;
                if ((pullReads > 1 && options.headChanged) || branchUpdated) {
                    return { ...pr, head: { ...pr.head, sha: newer } };
                }
                return pullReads > 1 ? { ...pr, ...options.finalPr } : pr;
            }),
            listReviews: method('pulls.listReviews', () => options.reviews ?? []),
            listFiles: method('pulls.listFiles', () => options.files ?? [{
                filename: workflowPath, status: 'modified', additions: 1, deletions: 1, changes: 2
            }]),
            updateBranch: method('pulls.updateBranch', () => {
                if (options.conflict) {
                    const error = new Error('Merge conflict.');
                    error.status = 422;
                    throw error;
                }
                branchUpdated = true;
                return { message: 'Updating pull request branch.' };
            })
        },
        actions: {
            listWorkflowRuns: method('actions.listWorkflowRuns', params => {
                if (params.workflow_id === 'create_release.yml') {
                    return { total_count: releaseRuns.length, workflow_runs: [...releaseRuns] };
                }
                return { total_count: ciRuns.length, workflow_runs: [...ciRuns] };
            }),
            listJobsForWorkflowRun: method('actions.listJobsForWorkflowRun', () => ({ total_count: jobs.length, jobs })),
            createWorkflowDispatch: method('actions.createWorkflowDispatch', params => {
                if (options.failRelease && params.workflow_id === 'create_release.yml' && !dispatchFailed) {
                    dispatchFailed = true;
                    throw new Error('release dispatch unavailable');
                }
                if (params.workflow_id === 'create_release.yml') {
                    releaseRuns.push({
                        id: 100 + releaseRuns.length, head_sha: promoted || options.mainHead || base,
                        event: 'workflow_dispatch', status: 'queued'
                    });
                } else {
                    ciRuns.push({
                        ...run, id: 100 + ciRuns.length, head_sha: branchUpdated ? newer : head,
                        event: 'workflow_dispatch', status: 'queued', conclusion: null,
                        created_at: new Date(now).toISOString(), updated_at: new Date(now).toISOString()
                    });
                }
                return undefined;
            })
        }
    };
    const github = {
        rest,
        async paginate(api, params) {
            const { data } = await api(params);
            if (Array.isArray(data)) return data;
            return data.workflow_runs ?? data.jobs ?? [];
        }
    };
    const core = {
        info: message => messages.push(message),
        warning: message => messages.push(message),
        notice: message => messages.push(message),
        setFailed: message => { throw new Error(message); },
        summary: {
            addRaw() { return this; },
            addHeading() { return this; },
            addList() { return this; },
            async write() {}
        }
    };
    const context = {
        repo: { owner, repo },
        eventName: options.eventName ?? 'workflow_dispatch',
        payload: {
            repository: { full_name: `${owner}/${repo}`, default_branch: 'main' },
            workflow_run: { ...run, ...options.eventRun }
        }
    };
    return {
        github, core, context, calls, messages, pr, run,
        workflowTokenConfigured: true, sleep: async () => {}, now: () => now,
        advanceTime: milliseconds => { now += milliseconds; },
    };
}

async function execute(options) {
    const state = fixture(options);
    await automate(state);
    return state;
}

function writes(state) {
    return state.calls.filter(call => /createCommit|updateRef|updateBranch|createWorkflowDispatch/.test(call.name));
}

function releaseReads(state) {
    return state.calls.filter(call => call.name === 'actions.listWorkflowRuns' &&
        call.params.workflow_id === 'create_release.yml');
}

test('未配置专用工作流凭据时在任何 API 调用前明确失败', async () => {
    const state = fixture();
    delete state.workflowTokenConfigured;
    await assert.rejects(() => automate(state), /DEPENDABOT_AUTOMATION_TOKEN.*Workflows write/);
    assert.deepEqual(state.calls, []);
});

for (const event of ['pull_request', 'workflow_dispatch']) {
    test(`成功的 ${event} 完成事件只处理对应分支和 head`, async () => {
        const state = await execute({
            eventName: 'workflow_run', eventRun: { event }, secondFails: true
        });
        assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
        assert.equal(state.calls.some(call => call.name === 'pulls.get' && call.params.pull_number === 12), false);
        assert.equal(state.calls.some(call => call.name === 'pulls.list' && call.params.state === 'closed'), false);
    });
}

for (const [name, eventRun] of [
    ['陈旧 head', { head_sha: newer }],
    ['其它分支', { head_branch: 'other-branch' }],
    ['其它仓库', { head_repository: { full_name: 'other/padm' } }],
    ['push 事件', { event: 'push' }],
    ['失败结论', { conclusion: 'failure' }]
]) {
    test(`忽略${name}的 workflow_run，不同步、不补 CI、不恢复发布`, async () => {
        const state = await execute({
            eventName: 'workflow_run', eventRun, behind: true,
            closed: [{
                user: { login: 'dependabot[bot]' }, merged_at: '2026-11-18T01:00:00Z',
                merge_commit_sha: base
            }]
        });
        assert.deepEqual(writes(state), []);
        assert.equal(state.calls.some(call => call.name === 'pulls.list' && call.params.state === 'closed'), false);
        assert.deepEqual(releaseReads(state), []);
    });
}

test('用受测树和 main 第一父提交合入小版本后等待 push 发布', async () => {
    const state = await execute();
    assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
    const commit = state.calls.find(call => call.name === 'git.createCommit');
    assert.deepEqual(commit.params.parents, [base, head]);
    assert.equal(commit.params.tree, testedTree);
    assert.equal(state.calls.find(call => call.name === 'git.updateRef').params.sha, merged);
    assert.deepEqual(releaseReads(state).map(call => call.params.head_sha), [merged]);
    assert.equal(state.calls.some(call => call.name === 'actions.createWorkflowDispatch'), false);
});

for (const [name, options] of [
    ['次版本更新', { updated: updated.replace('v6.1.1', 'v6.2.0') }],
    ['大版本更新', { updated: updated.replace('v6.1.1', 'v7.0.0') }],
    ['主版本标签更新', { source: source.replace('v6.1.0', 'v6'), updated: updated.replace('v6.1.1', 'v7') }],
    ['零主版本的次版本更新', { source: source.replace('v6.1.0', 'v0.1.0'), updated: updated.replace('v6.1.1', 'v0.2.0') }]
]) {
    test(`自动合入通过 CI 的${name}并等待 push 发布`, async () => {
        const state = await execute(options);
        assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
        assert.deepEqual(writes(state).filter(call => call.name === 'actions.createWorkflowDispatch')
            .map(call => call.params.workflow_id), []);
        assert.deepEqual(releaseReads(state).map(call => call.params.head_sha), [merged]);
    });
}

for (const [name, options] of [
    ['降级更新', { updated: updated.replace('v6.1.1', 'v6.0.9') }],
    ['跨主版本降级', { source: source.replace('v6.1.0', 'v7.0.0'), updated: updated.replace('v6.1.1', 'v6.9.9') }],
    ['额外执行脚本', { updated: `${updated}      - run: echo unexpected\n` }],
    ['更换依赖来源', { updated: updated.replace('actions/cache', 'untrusted/cache') }],
    ['非机器人 PR', { pr: { user: { login: 'maintainer', type: 'User' } } }],
    ['跨仓库 PR', { pr: { head: { sha: head, ref: 'patch', repo: { full_name: 'other/padm', fork: true } } } }],
    ['草稿 PR', { pr: { draft: true } }],
    ['非工作流文件', { files: [{ filename: 'install.sh', status: 'modified' }] }],
    ['新增工作流文件', { files: [{ filename: workflowPath, status: 'added' }] }],
    ['改变文件执行权限', { mode: '100755' }]
]) {
    test(`拒绝${name}`, async () => {
        const state = await execute(options);
        assert.deepEqual(writes(state), []);
    });
}

test('同步落后的基线后等待 PAT 自然触发 CI', async () => {
    const state = await execute({ behind: true });
    const update = state.calls.find(call => call.name === 'pulls.updateBranch');
    assert.equal(update.params.expected_head_sha, head);
    assert.equal(state.calls.some(call => call.name === 'actions.createWorkflowDispatch'), false);
    assert.equal(state.calls.some(call => call.name === 'git.updateRef'), false);
});

test('一个候选存在同步冲突时继续处理其它候选', async () => {
    const state = await execute({ behind: true, conflict: true });
    assert.equal(state.calls.filter(call => call.name === 'pulls.updateBranch').length, 1);
    const promotion = state.calls.find(call => call.name === 'git.updateRef');
    assert.equal(promotion.params.sha, merged);
    assert.deepEqual(state.calls.find(call => call.name === 'git.createCommit').params.parents, [base, newer]);
    assert.ok(state.messages.some(message => message.includes('PR #11 cannot update automatically')));
});

test('main 已包含相同 head 时不再创建合并提交', async () => {
    const state = await execute({ identical: true, mainHead: head });
    assert.deepEqual(writes(state), []);
});

test('main 受保护时明确停止而不写入', async () => {
    const state = fixture({ protected: true });
    await assert.rejects(() => automate(state), /main is protected/);
    assert.deepEqual(writes(state), []);
});

test('精确提交的 CI 失败时不合并也不自动重跑', async () => {
    const state = await execute({ run: { conclusion: 'failure' } });
    assert.deepEqual(writes(state), []);
});

for (const [name, latest] of [
    ['失败', { status: 'completed', conclusion: 'failure' }],
    ['运行中', { status: 'in_progress', conclusion: null }]
]) {
    test(`旧编号 CI 后来重跑${name}时不能使用较新编号的旧成功`, async () => {
        const state = await execute({
            runs: [
                { id: 42, updated_at: '2026-11-17T01:01:00Z' },
                { id: 40, updated_at: '2026-11-17T01:02:00Z', run_attempt: 2, ...latest }
            ]
        });
        assert.deepEqual(writes(state), []);
    });
}

test('CI 历史缺少更新时间时按创建时间选择最新失败', async () => {
    const state = await execute({
        runs: [
            { id: 42, created_at: '2026-11-17T01:01:00Z' },
            { id: 40, created_at: '2026-11-17T01:02:00Z', conclusion: 'failure' }
        ]
    });
    assert.deepEqual(writes(state), []);
});

test('CI 更新时间相同时用编号选择最新失败', async () => {
    const state = await execute({
        runs: [
            { id: 40, updated_at: '2026-11-17T01:02:00Z' },
            { id: 42, updated_at: '2026-11-17T01:02:00Z', conclusion: 'failure' }
        ]
    });
    assert.deepEqual(writes(state), []);
});

test('原生 CI 待审批时只补派一次验证', async () => {
    const state = fixture({ run: { event: 'pull_request', conclusion: 'action_required' } });
    await automate(state);
    await automate(state);
    assert.deepEqual(writes(state).map(call => call.params.workflow_id), ['docker-ci.yml']);
});

test('手动 CI 仍待审批时不再次补派', async () => {
    const state = await execute({ run: { event: 'workflow_dispatch', conclusion: 'action_required' } });
    assert.deepEqual(writes(state), []);
});

for (const [name, manual] of [
    ['失败', { status: 'completed', conclusion: 'failure' }],
    ['运行中', { status: 'in_progress', conclusion: null }]
]) {
    test(`历史已包含${name}的手动 CI 时不因原生待审批再次补派`, async () => {
        const state = await execute({
            runs: [
                { id: 41, event: 'workflow_dispatch', updated_at: '2026-11-18T01:00:00Z', ...manual },
                { id: 42, event: 'pull_request', updated_at: '2026-11-18T01:01:00Z', conclusion: 'action_required' }
            ]
        });
        assert.deepEqual(writes(state), []);
    });
}

for (const [name, run] of [
    ['排队中', { status: 'queued', conclusion: null }],
    ['运行中', { status: 'in_progress', conclusion: null }],
    ['已失败', { status: 'completed', conclusion: 'failure' }],
    ['已取消', { status: 'completed', conclusion: 'cancelled' }]
]) {
    test(`已有${name}的当前 head CI 时不补派`, async () => {
        const state = await execute({ run });
        assert.deepEqual(writes(state), []);
    });
}

test('较新运行来自其它仓库时仍使用本仓库已通过的验证', async () => {
    const state = await execute({
        runs: [
            { id: 42, updated_at: '2026-11-17T01:01:00Z' },
            { id: 43, updated_at: '2026-11-17T01:02:00Z', conclusion: 'failure',
                head_repository: { full_name: 'other/padm' } }
        ]
    });
    assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
});

for (const [name, options] of [
    ['CI 失败', { run: { conclusion: 'failure' } }],
    ['缺少签名验证', { missingJob: signingJob }]
]) {
    test(`大版本更新${name}时不合入`, async () => {
        const state = await execute({ ...options, updated: updated.replace('v6.1.1', 'v7.0.0') });
        assert.deepEqual(writes(state), []);
    });
}

test('保留人工请求修改的决定', async () => {
    const state = await execute({ reviews: [{ state: 'CHANGES_REQUESTED', user: { id: 1 } }] });
    assert.deepEqual(writes(state), []);
});

test('人工重新批准后允许合入', async () => {
    const state = await execute({
        reviews: [
            { state: 'CHANGES_REQUESTED', user: { id: 1 } },
            { state: 'APPROVED', user: { id: 1 } }
        ]
    });
    assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
});

test('缺少签名验证任务时不合并', async () => {
    const state = await execute({ missingJob: signingJob });
    assert.equal(state.calls.some(call => call.name === 'git.updateRef'), false);
});

test('没有 CI 且缺少更新时间时补派一次，重复巡检不重复派发', async () => {
    const state = fixture({ noRun: true });
    await automate(state);
    await automate(state);
    assert.deepEqual(writes(state).map(call => call.params.workflow_id), ['docker-ci.yml']);
});

test('PR 刚更新时先等原生 CI，满 10 分钟后只补派一次', async () => {
    const state = fixture({
        noRun: true, pr: { updated_at: new Date(currentTime - 9 * 60 * 1000).toISOString() }
    });
    await automate(state);
    assert.deepEqual(writes(state), []);
    state.advanceTime(60 * 1000);
    await automate(state);
    await automate(state);
    assert.deepEqual(writes(state).map(call => call.params.workflow_id), ['docker-ci.yml']);
});

for (const [name, options] of [
    ['PR head 变化', { headChanged: true }],
    ['main 变化', { mainChanged: true }],
    ['最终检查时 PR 转为草稿', { finalPr: { draft: true } }],
    ['最终检查时 PR 更换目标分支', { finalPr: { base: { ref: 'other', sha: base } } }]
]) {
    test(`${name}后不提升旧结果`, async () => {
        const state = await execute(options);
        assert.equal(state.calls.some(call => call.name === 'git.updateRef'), false);
    });
}

test('缺失发布首次补派失败保持可见，下一轮可恢复且不重复', async () => {
    const state = fixture({ failRelease: true });
    await automate(state);
    assert.equal(state.calls.some(call => call.name === 'actions.createWorkflowDispatch'), false);
    state.advanceTime(10 * 60 * 1000);
    await assert.rejects(() => automate(state), /release dispatch unavailable/);
    assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
    await automate(state);
    await automate(state);
    const dispatches = state.calls.filter(call => call.name === 'actions.createWorkflowDispatch');
    assert.equal(dispatches.length, 2);
    assert.ok(dispatches.every(call => call.params.workflow_id === 'create_release.yml'));
    assert.equal(String(dispatches[1].params.inputs.force_release), 'false');
});

test('已合入候选在后续候选 API 失败前检查 push 发布', async () => {
    const state = fixture({ secondFails: true });
    await assert.rejects(() => automate(state), /second candidate API unavailable/);
    const checked = state.calls.findIndex(call => call.name === 'actions.listWorkflowRuns' &&
        call.params.workflow_id === 'create_release.yml');
    const failedRead = state.calls.findIndex(call => call.name === 'pulls.get' &&
        call.params.pull_number === 12);
    assert.ok(checked >= 0 && checked < failedRead, '已合入提交应先检查 push 发布，再读取后续候选');
    assert.equal(state.calls[checked].params.head_sha, merged);
    assert.equal(state.calls.some(call => call.name === 'actions.createWorkflowDispatch'), false);
    assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
});

test('合入后只查询新 merge SHA，旧 head 的发布不能阻止延迟补派', async () => {
    const state = fixture({
        releaseRuns: [{ head_sha: head, event: 'push', status: 'queued' }]
    });
    await automate(state);
    assert.deepEqual(releaseReads(state).map(call => call.params.head_sha), [merged]);
    state.advanceTime(10 * 60 * 1000);
    await automate(state);
    assert.deepEqual(writes(state).filter(call => call.name === 'actions.createWorkflowDispatch')
        .map(call => call.params.workflow_id), ['create_release.yml']);
});

for (const eventName of ['schedule', 'workflow_dispatch']) {
    test(`${eventName} 巡检仅在合入满 10 分钟后为当前 merge SHA 补派发布`, async () => {
        const state = fixture({
            eventName, noCandidates: true, mainHead: merged,
            closed: [{
                user: { login: 'dependabot[bot]' },
                merged_at: new Date(currentTime - 9 * 60 * 1000).toISOString(),
                merge_commit_sha: merged
            }]
        });
        await automate(state);
        assert.deepEqual(writes(state), []);
        state.advanceTime(60 * 1000);
        await automate(state);
        await automate(state);
        assert.deepEqual(writes(state).map(call => call.params.workflow_id), ['create_release.yml']);
        assert.ok(releaseReads(state).every(call => call.params.head_sha === merged));
    });
}

test('workflow_run 不对已关闭 PR 执行发布恢复', async () => {
    const state = await execute({
        eventName: 'workflow_run', noCandidates: true, mainHead: merged,
        closed: [{
            user: { login: 'dependabot[bot]' }, merged_at: '2026-11-18T01:00:00Z',
            merge_commit_sha: merged
        }]
    });
    assert.deepEqual(writes(state), []);
    assert.deepEqual(releaseReads(state), []);
    assert.equal(state.calls.some(call => call.name === 'pulls.list' && call.params.state === 'closed'), false);
});

for (const [name, releaseRun] of [
    ['排队中', { status: 'queued', conclusion: null }],
    ['成功', { status: 'completed', conclusion: 'success' }],
    ['运行中', { status: 'in_progress', conclusion: null }],
    ['失败', { status: 'completed', conclusion: 'failure' }]
]) {
    test(`不重复派发当前 merge SHA 已有的${name}发布`, async () => {
        const state = fixture({ releaseRuns: [{ head_sha: merged, ...releaseRun }] });
        await automate(state);
        state.advanceTime(10 * 60 * 1000);
        await automate(state);
        assert.equal(state.calls.filter(call => call.name === 'git.updateRef').length, 1);
        assert.equal(state.calls.some(call => call.name === 'actions.createWorkflowDispatch'), false);
    });
}
