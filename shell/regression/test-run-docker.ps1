#requires -Version 7.3
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$fixture = Join-Path $root ".tmp-regression-runner-check-$([guid]::NewGuid().ToString('N'))\workspace with spaces"
$runnerDir = Join-Path $fixture 'shell\regression'
New-Item -ItemType Directory -Path $runnerDir | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'container') -Destination $runnerDir -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run-docker.ps1') -Destination $runnerDir
$git = 'C:\Program Files\Git\cmd\git.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
$entry = Join-Path $fixture 'shell\subscription_groups_regression.sh'
[IO.File]::WriteAllText($entry, 'exit 99', $utf8)
[IO.File]::WriteAllText((Join-Path $fixture '.gitignore'), "ignored.txt`n.tmp-*`n", $utf8)
& $git init --quiet $fixture
if ($LASTEXITCODE -ne 0) { throw 'Fixture Git initialization failed.' }
Push-Location $fixture
try {
    & $git add .
    if ($LASTEXITCODE -ne 0) { throw 'Fixture staging failed.' }
}
finally { Pop-Location }

$probe = @'
#!/usr/bin/env bash
set -euo pipefail
[[ "$(cat 'new file.txt')" == untracked-current ]]
[[ "$(cat probe.lock)" == linux-text ]]
python3 -c 'from pathlib import Path; assert Path("probe.bin").read_bytes() == b"\0\r\n\xff"'
# 只有精确的真实节点 selector 获得额外网络能力，普通和近似名称均不能获得。
python3 - "$1" <<'PY'
import sys
import json
import subprocess
from pathlib import Path
status = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines())
mask = (1 << 12) | (1 << 21)
expected = mask if sys.argv[1] in (
    "docker-control-two-node-real", "docker-control-two-deployment-real"
) else 0
assert int(status["CapEff"].strip(), 16) & mask == expected
privileged_mask = (1 << 19) | (1 << 25)
assert int(status["CapEff"].strip(), 16) & privileged_mask == (
    privileged_mask if sys.argv[1] == "docker-control-two-deployment-real" else 0)
assert [link["ifname"] for link in json.loads(
    subprocess.check_output(["ip", "-j", "link"])
)] == ["lo"]
assert not Path("/var/run/docker.sock").exists()
assert Path("/node-images.json").is_file() == (sys.argv[1] == "docker-control-two-deployment-real")
assert Path("/n").is_mount() == (sys.argv[1] == "docker-control-two-deployment-real")
PY
[[ ! -e ignored.txt && ! -e .git ]]
[[ "$HOME" == /tmp/padm-regression-home && "$TMPDIR" == /tmp/padm-regression-tmp ]]
printf 'current-worktree-snapshot-ok\n'
case "$1" in
    hold) sleep 12 ;;
    ci) sleep 8 ;;
    ci-pr) sleep 60 ;;
esac
[[ "$1" != fail ]] || exit 7
'@
[IO.File]::WriteAllText($entry, $probe.Replace("`n", "`r`n"), $utf8)
[IO.File]::WriteAllText((Join-Path $fixture 'new file.txt'), 'untracked-current', $utf8)
[IO.File]::WriteAllText((Join-Path $fixture 'probe.lock'), "linux-text`r`n", $utf8)
[IO.File]::WriteAllBytes((Join-Path $fixture 'probe.bin'), [byte[]]@(0, 13, 10, 255))
[IO.File]::WriteAllText((Join-Path $fixture 'ignored.txt'), 'must-not-copy', $utf8)
$runner = Join-Path $runnerDir 'run-docker.ps1'
foreach ($case in @(
    @{ selector = 'fast'; expected = 0 },
    @{ selector = 'fail'; expected = 7 },
    @{ selector = 'docker-control-two-node-real'; expected = 0 },
    @{ selector = 'docker-control-two-node-real-other'; expected = 0 },
    @{ selector = 'docker-control-two-deployment-real'; expected = 0 },
    @{ selector = 'docker-control-two-deployment-real-other'; expected = 0 }
)) {
    & $runner -Selector $case.selector
    if ($LASTEXITCODE -ne $case.expected) { throw "Wrong exit code for $($case.selector): $LASTEXITCODE" }
    $artifacts = Get-ChildItem -Directory -LiteralPath $fixture -Filter '.tmp-regression-docker-*' |
        Sort-Object CreationTime -Descending | Select-Object -First 1
    $result = Get-Content -Raw -LiteralPath (Join-Path $artifacts.FullName 'result.json') | ConvertFrom-Json
    if ($result.exit_code -ne $case.expected) { throw 'Wrong saved exit code.' }
    if ($result.jobs -ne 2 -or $result.cache_hit) { throw 'Wrong ordinary regression defaults.' }
    if ($result.queue_slots -ne 1 -or $result.image_id -notmatch '^sha256:') { throw 'Missing queue or image evidence.' }
    if (-not (Select-String -Quiet -LiteralPath (Join-Path $artifacts.FullName 'regression.log') `
        -SimpleMatch 'current-worktree-snapshot-ok')) { throw 'Missing snapshot proof in saved log.' }
}

$PSVersionTable.PSVersion
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$processes = @()

function Start-RunnerCheck {
    param([string]$Selector, [string]$Name, [int]$Jobs = 0, [switch]$ForceRun)
    $run = [pscustomobject]@{
        Output = Join-Path $fixture ".tmp-$Name.log"
        Error = Join-Path $fixture ".tmp-$Name.err"
        Process = $null
    }
    $arguments = @('-NoLogo', '-NoProfile', '-File', "`"$runner`"", '-Selector', $Selector)
    if ($Jobs) { $arguments += @('-Jobs', "$Jobs") }
    if ($ForceRun) { $arguments += '-ForceRun' }
    $run.Process = Start-Process -FilePath $pwsh -ArgumentList $arguments `
        -RedirectStandardOutput $run.Output -RedirectStandardError $run.Error -PassThru -WindowStyle Hidden
    $script:processes += $run.Process
    return $run
}

function Wait-RunnerOutput {
    param($Run, [string]$Text)
    $deadline = (Get-Date).AddSeconds(60)
    do {
        if ((Test-Path -LiteralPath $Run.Output) -and
            (Select-String -Quiet -LiteralPath $Run.Output -SimpleMatch $Text)) { return }
        if ($Run.Process.HasExited) {
            throw "Runner exited before '$Text': $(Get-Content -Raw -LiteralPath $Run.Error)"
        }
        Start-Sleep -Milliseconds 100
    } while ((Get-Date) -lt $deadline)
    throw "Runner output timed out: $Text"
}

function Wait-RunnerExit {
    param($Run)
    if (-not $Run.Process.WaitForExit(60000)) { throw 'Queued runner timed out.' }
    if ($Run.Process.ExitCode -ne 0) {
        throw "Queued runner failed: $(Get-Content -Raw -LiteralPath $Run.Error)"
    }
}

function Get-RunnerResult {
    param($Run)
    $artifactLine = Select-String -LiteralPath $Run.Output -Pattern '^Artifacts: ' | Select-Object -Last 1
    if (-not $artifactLine) { throw 'Runner did not report its artifacts.' }
    $directory = $artifactLine.Line.Substring('Artifacts: '.Length)
    return Get-Content -Raw -LiteralPath (Join-Path $directory result.json) | ConvertFrom-Json
}

try {
    # 两个普通任务必须重叠；第三个等待，并继续使用排队前的快照。
    $first = Start-RunnerCheck hold queue-first
    Wait-RunnerOutput $first current-worktree-snapshot-ok
    $second = Start-RunnerCheck hold queue-second
    Wait-RunnerOutput $second current-worktree-snapshot-ok
    if ($first.Process.HasExited) { throw 'Ordinary regressions did not overlap.' }
    $third = Start-RunnerCheck fast queue-third
    Wait-RunnerOutput $third 'Regression queue: waiting'
    [IO.File]::WriteAllText((Join-Path $fixture 'new file.txt'), 'changed-while-queued', $utf8)
    Wait-RunnerExit $first
    Wait-RunnerExit $second
    Wait-RunnerExit $third
    [IO.File]::WriteAllText((Join-Path $fixture 'new file.txt'), 'untracked-current', $utf8)

    # 完整 CI 等待时，后来的普通任务不能使用空闲槽位插入。
    $holder = Start-RunnerCheck hold queue-before-heavy
    Wait-RunnerOutput $holder current-worktree-snapshot-ok
    $heavy = Start-RunnerCheck ci queue-heavy
    Wait-RunnerOutput $heavy 'Regression queue: waiting'
    $queued = Start-RunnerCheck fast queue-after-heavy
    Wait-RunnerOutput $queued 'Regression queue: waiting'
    if ($holder.Process.HasExited) { throw 'Priority check missed the occupied slot.' }
    Wait-RunnerExit $holder
    Wait-RunnerOutput $heavy current-worktree-snapshot-ok
    if (Select-String -Quiet -LiteralPath $queued.Output -SimpleMatch current-worktree-snapshot-ok) {
        throw 'Ordinary regression bypassed a waiting CI regression.'
    }
    Wait-RunnerExit $heavy
    Wait-RunnerExit $queued
    if ((Get-RunnerResult $heavy).jobs -ne 3) { throw 'Wrong full regression default jobs.' }

    # 强制结束持有者后，接管槽位必须先移除它留下的容器。
    $orphan = Start-RunnerCheck ci-pr queue-orphan
    Wait-RunnerOutput $orphan current-worktree-snapshot-ok
    $recovery = Start-RunnerCheck all queue-recovery
    Wait-RunnerOutput $recovery 'Regression queue: waiting'
    Stop-Process -Id $orphan.Process.Id -Force
    $orphan.Process.WaitForExit()
    Wait-RunnerExit $recovery
    if (-not (Select-String -Quiet -LiteralPath $recovery.Output -SimpleMatch 'cleaning abandoned container')) {
        throw 'Abandoned regression container was not recovered.'
    }

    # 内容不变、时间戳变化仍复用；参数、内容或工具变化必须重跑。
    $baseline = Get-RunnerResult $recovery
    (Get-Item -LiteralPath (Join-Path $fixture 'probe.lock')).LastWriteTime = (Get-Date).AddMinutes(1)
    $reused = Start-RunnerCheck all cache-same-content
    Wait-RunnerExit $reused
    if (-not (Get-RunnerResult $reused).cache_hit) { throw 'Identical full regression was not reused.' }
    $forced = Start-RunnerCheck all cache-forced -ForceRun
    Wait-RunnerExit $forced
    if ((Get-RunnerResult $forced).cache_hit) { throw 'ForceRun did not bypass result reuse.' }
    $parameters = Start-RunnerCheck all cache-new-jobs -Jobs 2
    Wait-RunnerExit $parameters
    if ((Get-RunnerResult $parameters).cache_hit) { throw 'Different parallel jobs reused a result.' }
    [IO.File]::WriteAllText((Join-Path $fixture 'extra.txt'), 'new-source-content', $utf8)
    $content = Start-RunnerCheck all cache-new-content
    Wait-RunnerExit $content
    if ((Get-RunnerResult $content).cache_hit) { throw 'Different source content reused a result.' }
    $fullFirst = Start-RunnerCheck ci cache-concurrent-first
    Wait-RunnerOutput $fullFirst current-worktree-snapshot-ok
    $fullSecond = Start-RunnerCheck ci cache-concurrent-second
    Wait-RunnerOutput $fullSecond 'Regression queue: waiting'
    Wait-RunnerExit $fullFirst
    Wait-RunnerExit $fullSecond
    if ((Get-RunnerResult $fullFirst).cache_hit -or -not (Get-RunnerResult $fullSecond).cache_hit) {
        throw 'Identical concurrent full regressions were not combined.'
    }
    $interrupted = Start-RunnerCheck ci cache-interrupted -ForceRun
    Wait-RunnerOutput $interrupted current-worktree-snapshot-ok
    Stop-Process -Id $interrupted.Process.Id -Force
    $interrupted.Process.WaitForExit()
    $afterInterruption = Start-RunnerCheck ci cache-after-interruption
    Wait-RunnerExit $afterInterruption
    if ((Get-RunnerResult $afterInterruption).cache_hit) { throw 'Interrupted rerun reused an older success.' }
    Remove-Item -LiteralPath (Join-Path $fixture 'extra.txt')

    # 修改工具入口，但不改变测试行为，验证工具内容参与复用匹配。
    $toolEntry = Join-Path $runnerDir 'container\entrypoint.sh'
    $toolOriginal = [IO.File]::ReadAllText($toolEntry)
    [IO.File]::WriteAllText($toolEntry, $toolOriginal + "`n# 自检工具变化`n", $utf8)
    $tools = Start-RunnerCheck all cache-new-tools
    Wait-RunnerExit $tools
    $toolResult = Get-RunnerResult $tools
    if ($toolResult.cache_hit -or $toolResult.tool_sha256 -eq $baseline.tool_sha256) {
        throw 'Different tool content reused a result.'
    }
    [IO.File]::WriteAllText($toolEntry, $toolOriginal, $utf8)

    # 失败的完整回归不得进入成功结果复用。
    $originalProbe = [IO.File]::ReadAllText($entry)
    [IO.File]::WriteAllText($entry, $originalProbe + "`nexit 7`n", $utf8)
    foreach ($name in @('cache-failed-first', 'cache-failed-second')) {
        $failed = Start-RunnerCheck all $name
        if (-not $failed.Process.WaitForExit(60000)) { throw 'Failed full regression timed out.' }
        $failedResult = Get-RunnerResult $failed
        if ($failed.Process.ExitCode -ne 7 -or $failedResult.cache_hit) { throw 'Failed regression was reused.' }
    }
    [IO.File]::WriteAllText($entry, $originalProbe, $utf8)

    # 被取消的等待任务不能留下永久的完整回归优先标记。
    $holder = Start-RunnerCheck hold queue-cancel-holder
    Wait-RunnerOutput $holder current-worktree-snapshot-ok
    $cancelled = Start-RunnerCheck ci queue-cancel-waiter -ForceRun
    Wait-RunnerOutput $cancelled 'Regression queue: waiting'
    Stop-Process -Id $cancelled.Process.Id -Force
    $cancelled.Process.WaitForExit()
    $afterCancel = Start-RunnerCheck fast queue-after-cancel
    Wait-RunnerOutput $afterCancel current-worktree-snapshot-ok
    if ($holder.Process.HasExited) { throw 'Cancelled priority marker blocked the available slot.' }
    Wait-RunnerExit $holder
    Wait-RunnerExit $afterCancel
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        $process.Dispose()
    }
    foreach ($directory in Get-ChildItem -Directory -LiteralPath $fixture -Filter '.tmp-regression-docker-*') {
        $id = $directory.Name.Substring('.tmp-regression-docker-'.Length)
        if ($id -notmatch '^[0-9a-f]{32}$') { throw 'Invalid fixture container ID.' }
        $leftover = & docker ps -aq --filter "name=^/padm-regression-$id$"
        if ($LASTEXITCODE -ne 0) { throw 'Cannot check fixture container cleanup.' }
        if ($leftover) {
            & docker rm --force --volumes $leftover
            if ($LASTEXITCODE -ne 0) { throw 'Fixture container cleanup failed.' }
        }
    }
}

Write-Host 'regression-docker-queue-check-ok'
Write-Host 'regression-docker-runner-check-ok'
exit 0
