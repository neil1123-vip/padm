#requires -Version 7.3
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'run-docker.ps1'), [ref]$tokens, [ref]$errors
)
if ($errors.Count) { throw $errors[0] }
# 从入口直接取镜像准备块，避免检查维护一份重复实现。
$imageBlock = $ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and
    $node.Body.Extent.Text.Contains('$candidate = & $docker image inspect')
}, $true) | Sort-Object { $_.Extent.Text.Length } | Select-Object -First 1
if (-not $imageBlock) { throw 'Cannot locate regression image preparation.' }
$prepare = [scriptblock]::Create($imageBlock.Body.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))

function Invoke-ImageCheckDocker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq 'build') {
        $script:buildCount++
        $script:candidate = [ordered]@{
            Id = 'rebuilt'
            Os = 'linux'
            Architecture = 'amd64'
            Config = @{ Labels = @{ 'padm.regression.tools-context-sha256' = 'expected' } }
            RootFS = @{ Layers = @('tools') }
        }
        return
    }
    if ($Arguments[0] -eq 'image' -and $Arguments[1] -eq 'inspect') {
        if (-not $script:candidate) { $global:LASTEXITCODE = 1; return }
        return ,(ConvertTo-Json -InputObject @($script:candidate) -Depth 10 -Compress)
    }
    throw "Unexpected Docker call: $Arguments"
}

function Get-TextHash {
    param([string]$Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))
}

$docker = 'Invoke-ImageCheckDocker'
$image = 'padm-regression:local'
$platform = 'linux/amd64'
$containerContextHash = 'expected'
$containerDirectory = Join-Path $PSScriptRoot 'container'
$buildArgs = @('build', '--label', "padm.regression.tools-context-sha256=$containerContextHash")
foreach ($case in @('match', 'missing', 'changed', 'platform', 'unlabelled', 'rebuild')) {
    $script:buildCount = 0
    $script:candidate = if ($case -eq 'missing') { $null } else {
        [ordered]@{
            Id = 'original'
            Os = 'linux'
            Architecture = if ($case -eq 'platform') { 'arm64' } else { 'amd64' }
            Config = @{ Labels = @{
                'padm.regression.tools-context-sha256' = if ($case -eq 'changed') { 'changed' }
                    elseif ($case -eq 'unlabelled') { $null } else { 'expected' }
            } }
            RootFS = @{ Layers = @('tools') }
        }
    }
    $Rebuild = $case -eq 'rebuild'
    . $prepare
    $expectedBuilds = if ($case -eq 'match') { 0 } else { 1 }
    if ($script:buildCount -ne $expectedBuilds -or -not $imageId -or -not $toolHash) {
        throw "Image preparation failed: $case (builds=$script:buildCount)"
    }
}
'Regression image preparation: 6 checks passed.'
