#requires -Version 7.3
[CmdletBinding()]
param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
    [string]$Selector = 'fast',
    [ValidateRange(1, 4)]
    [int]$Jobs,
    [switch]$Rebuild,
    [switch]$ForceRun
)

$ErrorActionPreference = 'Stop'
$fullRegression = $Selector -in @('all', 'ci', 'ci-pr')
if (-not $PSBoundParameters.ContainsKey('Jobs')) {
    $Jobs = if ($fullRegression) { 3 } else { 2 }
}
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$git = 'C:\Program Files\Git\cmd\git.exe'
$tar = Join-Path $env:SystemRoot 'System32\tar.exe'
$docker = (Get-Command docker -ErrorAction Stop).Source
$image = 'padm-regression:local'
$platform = & $docker version --format '{{.Server.Os}}/{{.Server.Arch}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker Linux engine is unavailable.' }
if ($platform -notmatch '^linux/(amd64|arm64)$') { throw "Unsupported Docker platform: $platform" }
if ($Selector -in @('ci', 'ci-pr') -and $Jobs -lt 2) { throw 'CI selectors require 2 to 4 jobs.' }
$containerDirectory = Join-Path $PSScriptRoot 'container'

$runId = [guid]::NewGuid().ToString('N')
$runDir = Join-Path $root ".tmp-regression-docker-$runId"
New-Item -ItemType Directory -Path $runDir | Out-Null
$manifest = Join-Path $runDir 'files.list'
$snapshot = Join-Path $runDir 'source.tar'
$log = Join-Path $runDir 'regression.log'

# Git 只列路径；归档读取当前文件，保留未提交改动和未忽略的新文件。
$listed = & $git -C $root ls-files --cached --others --exclude-standard -z
if ($LASTEXITCODE -ne 0) { throw 'Cannot list current workspace files.' }
$files = @(
    ([string]::Join("`n", @($listed)) -split "`0") |
        Where-Object {
            $_ -and $_ -notmatch '(^|/)\.tmp-[^/]*(/|$)' -and
            (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf)
        } | Sort-Object -Unique
)
if ($files.Count -eq 0) { throw 'The source snapshot is empty.' }
[IO.File]::WriteAllText($manifest, ($files -join "`0") + "`0", [Text.UTF8Encoding]::new($false))
& $tar -cf $snapshot -C $root --null -T $manifest
if ($LASTEXITCODE -ne 0) { throw 'Source snapshot creation failed.' }

$userKey = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$commonDirectory = & $git -C $root rev-parse --path-format=absolute --git-common-dir
if ($LASTEXITCODE -ne 0) { throw 'Cannot locate the shared repository directory.' }
$commonDirectory = [IO.Path]::GetFullPath($commonDirectory)
$repositoryKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($commonDirectory.ToLowerInvariant())
)).Substring(0, 16)
$queueKey = "$userKey-$repositoryKey"
$sharedDirectory = Join-Path (Split-Path $commonDirectory -Parent) ".tmp-regression-shared-$userKey"
New-Item -ItemType Directory -Path $sharedDirectory -Force | Out-Null
$pendingPath = Join-Path $sharedDirectory "$runId.pending"
$pendingStream = $null
$mutexPrefix = "Global\padm-regression-$queueKey"
$queueGuard = [Threading.Mutex]::new($false, "$mutexPrefix-queue-guard")
$buildGuard = [Threading.Mutex]::new($false, "Global\padm-regression-$userKey-build")
$slotMutexes = @(
    [Threading.Mutex]::new($false, "$mutexPrefix-slot-1")
    [Threading.Mutex]::new($false, "$mutexPrefix-slot-2")
)
$requiredSlots = if ($fullRegression) { 2 } else { 1 }
$heldSlots = @()
$slotLabels = @('--label', "padm.regression.queue=$queueKey")
$buildHeld = $false
$queueMessageShown = $false

function Wait-NamedMutex {
    param([Threading.Mutex]$Mutex)
    do {
        try { $entered = $Mutex.WaitOne(200) }
        catch [Threading.AbandonedMutexException] {
            # 放弃的互斥锁已交给当前进程，继续接管。
            return
        }
    } while (-not $entered)
}

function Try-EnterNamedMutex {
    param([Threading.Mutex]$Mutex)
    try {
        return $Mutex.WaitOne(0)
    }
    catch [Threading.AbandonedMutexException] {
        return $true
    }
}

function Get-TextHash {
    param([string]$Text)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}

function Get-SnapshotContentHash {
    Add-Type -AssemblyName System.Formats.Tar
    $stream = [IO.File]::OpenRead($snapshot)
    $reader = [System.Formats.Tar.TarReader]::new($stream)
    $entries = [Collections.Generic.List[string]]::new()
    try {
        while ($entry = $reader.GetNextEntry()) {
            $hash = if ($entry.DataStream) {
                [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entry.DataStream))
            } else { '' }
            $entries.Add((@($entry.Name, [int]$entry.Mode, [string]$entry.EntryType, $entry.LinkName, $hash) |
                ConvertTo-Json -Compress))
        }
    }
    finally { $reader.Dispose(); $stream.Dispose() }
    # 内容、路径、类型和权限都参与匹配，忽略不影响测试的归档时间戳。
    $entries.Sort([StringComparer]::Ordinal)
    return Get-TextHash ($entries -join "`n")
}

function Test-PendingFullRegression {
    foreach ($file in Get-ChildItem -LiteralPath $sharedDirectory -Filter '*.pending') {
        try {
            $probe = [IO.File]::Open($file.FullName, 'Open', 'ReadWrite', 'None')
        }
        catch [IO.IOException] { return $true }
        $probe.Dispose()
        Remove-Item -LiteralPath $file.FullName
    }
    return $false
}

function Enter-RegressionSlots {
    if ($fullRegression) {
        Wait-NamedMutex $queueGuard
        try {
            $script:pendingStream = [IO.File]::Open($pendingPath, 'CreateNew', 'Write', 'None')
        }
        finally { $queueGuard.ReleaseMutex() }
    }
    # ponytail: 完整回归优先排空槽位；同类任务不保证 FIFO，需要严格顺序再加票号。
    while ($true) {
        $granted = $false
        $guardHeld = $false
        $acquired = @()
        try {
            Wait-NamedMutex $queueGuard
            $guardHeld = $true
            if ($fullRegression -or -not (Test-PendingFullRegression)) {
                for ($index = 0; $index -lt $slotMutexes.Count; $index++) {
                    if (Try-EnterNamedMutex $slotMutexes[$index]) {
                        $acquired += $index
                        if ($acquired.Count -eq $requiredSlots) { break }
                    }
                }
            }
            if ($acquired.Count -eq $requiredSlots) {
                $script:heldSlots = $acquired
                $granted = $true
                foreach ($index in $acquired) {
                    $label = "padm.regression.slot-$($index + 1)=true"
                    $script:slotLabels += @('--label', $label)
                    $orphans = @(& $docker ps -aq --filter "label=padm.regression.queue=$queueKey" --filter "label=$label")
                    if ($LASTEXITCODE -ne 0) { throw 'Cannot check abandoned regression containers.' }
                    if ($orphans.Count) {
                        Write-Host "Regression queue: cleaning abandoned container(s): $($orphans -join ', ')"
                        & $docker rm --force @orphans
                        if ($LASTEXITCODE -ne 0) { throw 'Abandoned regression container cleanup failed.' }
                    }
                }
                if ($pendingStream) {
                    $pendingStream.Dispose()
                    $script:pendingStream = $null
                    Remove-Item -LiteralPath $pendingPath
                }
                return
            }
        }
        finally {
            if (-not $granted) {
                foreach ($index in $acquired) { $slotMutexes[$index].ReleaseMutex() }
            }
            if ($guardHeld) { $queueGuard.ReleaseMutex() }
        }
        if (-not $script:queueMessageShown) {
            Write-Host "Regression queue: waiting for $requiredSlots slot(s)..."
            $script:queueMessageShown = $true
        }
        Start-Sleep -Milliseconds 200
    }
}

$containerContext = Get-ChildItem -LiteralPath $containerDirectory -File -Recurse -Force |
    Sort-Object FullName | ForEach-Object {
    "$([IO.Path]::GetRelativePath($containerDirectory, $_.FullName))`n$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)"
}
$containerContextHash = Get-TextHash ($containerContext -join "`n")
$buildArgs = @(
    'build', '--load', '--platform', $platform, '--tag', $image,
    '--label', "padm.regression.tools-context-sha256=$containerContextHash"
)
if ($Rebuild) { $buildArgs += '--no-cache' }

$container = $null
$exitCode = 1
$watch = [Diagnostics.Stopwatch]::new()
$queueWatch = [Diagnostics.Stopwatch]::StartNew()
try {
    Enter-RegressionSlots
    $queueWatch.Stop()
    Wait-NamedMutex $buildGuard
    $buildHeld = $true
    try {
        $imageInfo = $null
        if (-not $Rebuild) {
            $candidate = & $docker image inspect $image 2>$null
            if ($LASTEXITCODE -eq 0) {
                $candidate = $candidate | ConvertFrom-Json | Select-Object -First 1
                $labels = $candidate.Config.Labels
                if ($candidate.Os -eq 'linux' -and $candidate.Architecture -eq ($platform -replace '^linux/', '') -and
                    $labels.'padm.regression.tools-context-sha256' -eq $containerContextHash) {
                    $imageInfo = $candidate
                    Write-Host "Regression image: reusing $image ($containerContextHash)"
                }
            }
        }
        if (-not $imageInfo) {
            & $docker @buildArgs $containerDirectory
            if ($LASTEXITCODE -ne 0) { throw 'Regression image build failed.' }
            $imageInfo = & $docker image inspect $image
            if ($LASTEXITCODE -ne 0) { throw 'Cannot read regression image ID.' }
            $imageInfo = $imageInfo | ConvertFrom-Json | Select-Object -First 1
        }
        $imageId = $imageInfo.Id
        $toolHash = Get-TextHash (@($imageInfo.RootFS, $imageInfo.Config) | ConvertTo-Json -Depth 20 -Compress)
    }
    finally {
        if ($buildHeld) {
            $buildGuard.ReleaseMutex() | Out-Null
            $buildHeld = $false
        }
    }

    $resultPath = Join-Path $runDir 'result.json'
    $result = [ordered]@{
        selector = $Selector
        platform = $platform
        jobs = $Jobs
        queue_slots = $requiredSlots
        queue_wait_ms = $queueWatch.ElapsedMilliseconds
        image_id = $imageId
        tool_sha256 = $toolHash
        elapsed_ms = 0
        exit_code = 0
        source_sha256 = (Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash
        cache_hit = $false
    }
    $cachePath = $null
    if ($fullRegression) {
        $result.source_content_sha256 = Get-SnapshotContentHash
        $cacheKey = Get-TextHash (@('v1', $Selector, $platform, $Jobs, $toolHash, $result.source_content_sha256) -join "`n")
        $cachePath = Join-Path $sharedDirectory "$cacheKey.json"
        if (-not $ForceRun -and (Test-Path -LiteralPath $cachePath)) {
            try {
                $completed = Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json
                if ((Test-Path -LiteralPath $completed.result_path) -and (Test-Path -LiteralPath $completed.log_path) -and
                    (Get-FileHash -LiteralPath $completed.result_path).Hash -eq $completed.result_sha256 -and
                    (Get-FileHash -LiteralPath $completed.log_path).Hash -eq $completed.log_sha256) {
                    $original = Get-Content -Raw -LiteralPath $completed.result_path | ConvertFrom-Json
                    if ($original.exit_code -eq 0 -and $original.selector -eq $Selector -and
                        $original.platform -eq $platform -and $original.jobs -eq $Jobs -and
                        $original.tool_sha256 -eq $toolHash -and
                        $original.source_content_sha256 -eq $result.source_content_sha256) {
                        Copy-Item -LiteralPath $completed.log_path -Destination $log
                        $result.cache_hit = $true
                        $result.reused_from = $completed.result_path
                        $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
                        Write-Host "Regression: reusing successful $Selector result: $($completed.result_path)"
                        Write-Host "Artifacts: $runDir"
                        $exitCode = 0
                        exit $exitCode
                    }
                }
            }
            catch { Write-Warning "Cannot reuse cached result; rerunning: $($_.Exception.Message)" }
        }
        # 重跑开始前撤销旧成功索引，失败或中断不能重新命中旧证据。
        if (Test-Path -LiteralPath $cachePath) { Remove-Item -LiteralPath $cachePath }
    }

    $container = & $docker create --name "padm-regression-$runId" --platform $platform @slotLabels `
        --network none --init `
        --env "PADM_REGRESSION_PARALLEL_JOBS=$Jobs" `
        --env "PADM_REGRESSION_ALL_PARALLEL_JOBS=$Jobs" `
        --env "PADM_REGRESSION_CI_PARALLEL_JOBS=$Jobs" `
        --env PADM_REGRESSION_VERBOSE=1 $imageId $Selector
    if ($LASTEXITCODE -ne 0) { $container = $null; throw 'Regression container creation failed.' }
    & $docker cp $snapshot "${container}:/snapshot.tar"
    if ($LASTEXITCODE -ne 0) { throw 'Source snapshot copy failed.' }

    Write-Host "Regression: $Selector, $Jobs jobs, $platform"
    Write-Host "Artifacts: $runDir"
    $watch.Start()
    & $docker start --attach $container 2>&1 | Tee-Object -FilePath $log
    $attachCode = $LASTEXITCODE
    $watch.Stop()
    $state = & $docker inspect --format '{{json .State}}' $container
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read regression container status.' }
    $state = $state | ConvertFrom-Json
    if ($state.Status -ne 'exited') { throw "Regression container did not exit: $($state.Status)" }
    $exitCode = [int]$state.ExitCode
    if ($attachCode -ne 0 -and $exitCode -eq 0) { $exitCode = $attachCode }
    $result.elapsed_ms = $watch.ElapsedMilliseconds
    $result.exit_code = $exitCode
    $result | ConvertTo-Json | Set-Content -LiteralPath $resultPath -Encoding utf8
    & $docker rm --force $container
    if ($LASTEXITCODE -ne 0) { throw "Container cleanup failed: $container" }
    $container = $null
    if ($cachePath -and $exitCode -eq 0) {
        [ordered]@{
            result_path = $resultPath
            result_sha256 = (Get-FileHash -LiteralPath $resultPath).Hash
            log_path = $log
            log_sha256 = (Get-FileHash -LiteralPath $log).Hash
        } | ConvertTo-Json | Set-Content -LiteralPath "$cachePath.$runId.tmp" -Encoding utf8
        [IO.File]::Move("$cachePath.$runId.tmp", $cachePath, $true)
    }
    Write-Host "Exit: $exitCode, elapsed: $($watch.ElapsedMilliseconds) ms"
}
finally {
    try {
        if ($container) {
            & $docker rm --force $container
            if ($LASTEXITCODE -ne 0) { throw "Container cleanup failed: $container" }
        }
    }
    finally {
        if ($buildHeld) { $buildGuard.ReleaseMutex() }
        foreach ($index in $heldSlots) { $slotMutexes[$index].ReleaseMutex() }
        if ($pendingStream) { $pendingStream.Dispose() }
        $slotMutexes | ForEach-Object { $_.Dispose() }
        $buildGuard.Dispose()
        $queueGuard.Dispose()
    }
}
exit $exitCode
