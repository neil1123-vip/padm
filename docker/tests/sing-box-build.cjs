#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const project = path.resolve(__dirname, '../..');
const workflow = fs.readFileSync(path.join(project, '.github/workflows/build-sing-box.yml'), 'utf8').replace(/\r\n/g, '\n');
const root = fs.mkdtempSync(path.join(project, '.tmp-sing-box-ci-'));
assert.equal(path.dirname(root), project);
const windows = os.platform() === 'win32';
const git = windows ? 'C:/Program Files/Git/cmd/git.exe' : 'git';
const bash = windows ? 'D:/msys64/usr/bin/bash.exe' : 'bash';

function script(name, type = 'run') {
    const step = workflow.split(`      - name: ${name}\n`)[1]?.split('\n      - ')[0];
    assert.ok(step, `Missing workflow step: ${name}`);
    const indent = type === 'run' ? 10 : 12;
    const body = step.split(`${' '.repeat(indent - 2)}${type}: |\n`)[1];
    assert.ok(body, `Missing ${type}: ${name}`);
    const lines = [];
    for (const line of body.split('\n')) {
        if (line.trim() && !line.startsWith(' '.repeat(indent))) break;
        lines.push(line.slice(indent));
    }
    return lines.join('\n');
}

function run(command, args, env = {}, success = true) {
    const result = spawnSync(command, args, { cwd: root, encoding: 'utf8', env: { ...process.env, ...env } });
    if (success) assert.equal(result.status, 0, `${command}: ${result.error || result.stderr || result.stdout}`);
    else assert.notEqual(result.status, 0, 'Expected failure');
    return result.stdout?.trim();
}

function shell(code, env = {}, success = true) {
    // Windows 使用指定 MSYS2 和原生 Git；Linux runner 直接复用已安装工具。
    const prefix = windows ? 'export PATH="/c/Program Files/Git/cmd:/d/msys64/usr/bin:/d/msys64/clang64/bin:$PATH"\n' : '';
    return run(bash, ['-c', prefix + code], env, success);
}

function write(file, contents) {
    fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    fs.writeFileSync(path.join(root, file), contents);
}

function commit() {
    run(git, ['add', '.']);
    run(git, ['-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture']);
    return run(git, ['rev-parse', 'HEAD']);
}

async function main() {
    const detect = script('Detect sing-box build input changes');
    const inputs = ['.github/workflows/build-sing-box.yml', 'shell/build-sing-box.sh',
        'shell/subscription/traffic.sh', 'shell/core/stats_grpc.sh', 'docker-bake.hcl',
        'docker/images/sing-box/Dockerfile', 'docker/tests/image-smoke.sh', 'docker/tests/sing-box-build.cjs'];
    write('.gitignore', 'output\n');
    write('versions.lock', fs.readFileSync(path.join(project, 'versions.lock')));
    for (const file of inputs) write(file, '# fixture\n');
    run(git, ['init', '-q']);
    run(git, ['config', 'user.name', 'padm CI regression']);
    run(git, ['config', 'user.email', 'padm-ci@example.invalid']);
    run(git, ['config', 'core.autocrlf', 'false']);
    let before = commit();
    function check(event, expected, base = before) {
        write('output', '');
        shell(detect, { GITHUB_EVENT_NAME: event, BEFORE_SHA: base, GITHUB_OUTPUT: path.join(root, 'output') });
        const actual = Object.fromEntries(fs.readFileSync(path.join(root, 'output'), 'utf8').trim().split('\n').map(line => line.split('=')));
        assert.deepEqual(actual, expected);
    }
    for (const [key, changed, verify] of [
        ['XRAY_VERSION', 'false', 'false'], ['SING_BOX_AMD64_SHA256', 'false', 'false'],
        ['SING_BOX_VERSION', 'true', 'false'], ['SING_BOX_ARM64_UPSTREAM_SHA256', 'true', 'true'],
        ['ALPINE_BASE', 'true', 'true'], ['CA_CERTIFICATES_VERSION', 'true', 'true'],
        ['GCOMPAT_VERSION', 'true', 'true'], ['LIBGCC_VERSION', 'true', 'true']
    ]) {
        const lock = fs.readFileSync(path.join(root, 'versions.lock'), 'utf8');
        write('versions.lock', lock.replace(new RegExp(`^PADM_LOCK_${key}=.*$`, 'm'), `PADM_LOCK_${key}=changed`));
        const head = commit();
        check('push', { changed, verify });
        before = head;
    }
    for (const file of inputs) {
        assert.ok(workflow.includes(`      - '${file === 'docker/images/sing-box/Dockerfile' ? 'docker/images/sing-box/**' : file}'`), `Missing trigger: ${file}`);
        write(file, '# changed\n');
        const head = commit();
        check('push', { changed: 'true', verify: 'true' });
        before = head;
    }
    check('schedule', { changed: 'true', verify: 'false' });
    check('workflow_dispatch', { changed: 'true', verify: 'true' });
    check('push', { changed: 'true', verify: 'true' }, '0'.repeat(40));
    check('push', { changed: 'true', verify: 'true' }, 'f'.repeat(40));

    const resolve = new (Object.getPrototypeOf(async function () {}).constructor)('github', 'context', 'core', script('Resolve immutable source and release assets', 'script'));
    const digest = 'a'.repeat(64);
    const version = 'v1.14.1';
    process.env.LOCK_VERSION = version;
    process.env.LOCK_AMD64 = digest;
    process.env.LOCK_ARM64 = digest;
    process.env.REQUESTED_VERSION = '';
    const asset = name => ({ name, size: 100, digest: `sha256:${digest}` });
    const release = { draft: false, assets: ['linux-amd64.tar.gz', 'linux-arm64.tar.gz', 'source.tar.gz'].map(suffix => asset(`sing-box-1.14.1-${suffix}`)).concat(asset('SHA256SUMS')) };
    async function decision(existing, verify, expected, badDigest = false) {
        const outputs = {};
        let upstreamCalls = 0;
        process.env.VERIFY_EXISTING = verify;
        const github = { rest: {
            repos: { getReleaseByTag: async ({ owner }) => {
                if (owner === 'SagerNet') {
                    upstreamCalls++;
                    return { data: { ...release, tag_name: version } };
                }
                if (!existing) throw Object.assign(new Error('missing'), { status: 404 });
                return { data: existing };
            } },
            git: { getRef: async () => ({ data: { object: { type: 'commit', sha: 'b'.repeat(40) } } }) }
        } };
        process.env.LOCK_ARM64 = badDigest ? 'c'.repeat(64) : digest;
        const call = () => resolve(github, { repo: { owner: 'test', repo: 'padm' } }, { setOutput: (key, value) => { outputs[key] = value; } });
        if (expected instanceof RegExp) return assert.rejects(call, expected);
        await call();
        assert.equal(outputs.skip, expected.skip);
        assert.equal(outputs.publish, expected.publish);
        assert.equal(upstreamCalls, expected.skip === 'true' ? 0 : 1);
        if (outputs.skip !== 'true') assert.deepEqual(JSON.parse(outputs.matrix).include.map(item => item.arch), ['amd64', 'arm64']);
    }
    await decision(release, 'false', { skip: 'true', publish: 'false' });
    await decision(release, 'true', { skip: 'false', publish: 'false' });
    await decision(null, 'false', { skip: 'false', publish: 'true' });
    await decision({ ...release, draft: true }, 'false', { skip: 'false', publish: 'true' });
    await decision({ ...release, assets: [] }, 'true', /Published release is incomplete/);
    await decision(release, 'true', /digest differs/, true);

    // 执行实际候选步骤，确认包进入覆盖上下文，构建或 smoke 失败均向上传播。
    const alpine = script('Verify candidate in the Alpine image');
    write('versions.lock', fs.readFileSync(path.join(project, 'versions.lock')));
    write('package/sing-box', 'candidate-binary');
    fs.mkdirSync(path.join(root, '.tmp-sing-box-artifacts'));
    shell('tar -czf .tmp-sing-box-artifacts/sing-box-1.14.1-linux-amd64.tar.gz package');
    write('docker/tests/image-smoke.sh', '[[ "$1" == padm-sing-box-candidate:amd64 && "$2" == sing-box ]]\nexit "${SMOKE_STATUS:-0}"\n');
    const mock = `docker() {
        [[ "$*" == *'sing-box.platform=linux/amd64'* && "$*" == *'sing-box.contexts.fetch=.tmp-sing-box-image'* && "$*" == *'sing-box.args.SING_BOX_VERSION=v1.14.1'* && "$*" == *'--load'* ]] || return 90
        [[ "$(cat .tmp-sing-box-image/out/sing-box)" == candidate-binary ]] || return 91
        return "${'${BUILD_STATUS:-0}'}"
    }\n`;
    const env = { VERSION: version, ARCH: 'amd64', GITHUB_SHA: 'b'.repeat(40) };
    shell(mock + alpine, env);
    shell(mock + alpine, { ...env, BUILD_STATUS: '1' }, false);
    shell(mock + alpine, { ...env, SMOKE_STATUS: '1' }, false);
    assert.ok(workflow.indexOf('Verify candidate in the Alpine image') < workflow.indexOf('uses: actions/upload-artifact@'));
    assert.match(workflow, /needs: \[prepare, build\]\s+if: needs\.prepare\.outputs\.publish == 'true' && needs\.build\.result == 'success'/);
    console.log('sing-box-build-regression-ok');
}

main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => fs.rmSync(root, { recursive: true, force: true }));
